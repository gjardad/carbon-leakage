###############################################################################
# phase4_within_intensive_did_honestdid.R
#
# PURPOSE
#   Rambachan-Roth (2023, ReStud) sensitivity analysis on the within-NACE4d
#   intensive-margin DiD. For each cell of the comparison table (omega_def
#   x cut x version), estimate the event-study coefficients and the
#   cluster-robust variance, then bound the post-treatment effect under
#   two restrictions:
#     (i)  relative magnitudes (Delta^RM): post-treatment violation of
#          parallel trends bounded by Mbar x max pre-treatment violation.
#     (ii) smoothness (Delta^SD): bounded second differences of the
#          differential trend.
#
#   The reported breakdown values are the smallest Mbar (RM) or M (SD)
#   at which the robust 95% confidence set includes zero. Small breakdown
#   values => the conclusion that beta != 0 is fragile to pre-trend
#   violations. Large breakdown values => robust.
#
#   For each cell we run R&R for both treatment periods if the pre-period
#   has enough leads. treat_2005 has 3 pre-period years (2002-04), which
#   gives R&R 2 pre-period differences -- limited but usable. treat_2017
#   has 12 pre-period years (2005-16), giving R&R 11 pre-period
#   differences -- ample.
#
# DEPENDENCIES
#   Same as phase4_within_intensive_table_and_distributions.R
#   plus HonestDiD package.
#
# OUTPUTS (output_<machine>/tables/)
#   - phase4_within_nace4d_intensive_honestdid_results.csv
#       For each (omega_def, cut, version, restriction): the original
#       95% CI, the robust 95% CI at each Mbar/M value, and the
#       breakdown M.
#   - phase4_within_nace4d_intensive_honestdid_event_studies.csv
#       Event-study coefficients for each cell, with cluster-robust SE.
#
# RUNTIME
#   ~5-10 minutes on local-1; similar on RMD (no bootstrap).
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(ggplot2)
  library(HonestDiD)
})

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
set.seed(20260513)

YEAR_LO <- 2002L
YEAR_HI <- 2022L

INTERVALS <- list(
  "treat_2005" = list(years = c(2005L),         treat_year = 2005L),
  "treat_2017" = list(years = c(2015L, 2016L),  treat_year = 2017L)
)

CUT_LABELS <- c("pooled",
                "cost_shock_q",   "cost_shock_d",
                "input_share_q",  "input_share_d",
                "exposure_gap_q", "exposure_gap_d")

OMEGA_DEFS <- c("shortage" = "omega_sh", "emissions" = "omega_em")

# Mbar grid for the relative-magnitudes restriction and M grid for
# smoothness. Standard choices in the R&R literature.
MBAR_GRID <- c(0, 0.25, 0.5, 0.75, 1, 1.5, 2)
M_GRID    <- c(0, 0.001, 0.005, 0.01, 0.02, 0.05)

# ---------------------------------------------------------------------------
# 1. Load data
# ---------------------------------------------------------------------------
cat("Loading data...\n")

load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year),
             sales)]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano),
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))
aa_kv <- as.data.table(df_annual_accounts_selected_sample_key_variables)[, .(
  vat = as.character(vat),
  year = as.integer(year),
  revenue, value_added, wage_bill
)]
rm(df_annual_accounts_selected_sample_key_variables)
aa_kv[, total_cost := (revenue - value_added) + wage_bill]
buyer_tc <- aa_kv[!is.na(total_cost) & total_cost > 0,
                  .(buyer = vat, year, buyer_total_cost = total_cost)]

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(vat = as.character(vat),
                                       year, shortage, emissions,
                                       total_cost, allocated_free)]
rm(firm_exposure)
fe[, omega_sh := ifelse(!is.na(total_cost) & total_cost > 0,
                        pmax(shortage, 0) / total_cost, NA_real_)]
fe[, omega_em := ifelse(!is.na(total_cost) & total_cost > 0,
                        pmax(emissions, 0) / total_cost, NA_real_)]

b2b <- merge(b2b, aa, by.x = c("seller", "year"), by.y = c("vat", "year"),
             all.x = TRUE)
setnames(b2b, "nace4d", "seller_nace4d")
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d != ""]
b2b[, total_buyer_nace4d_spend := sum(sales),
    by = .(buyer, seller_nace4d, year)]

# ---------------------------------------------------------------------------
# 2. Build cells per (interval, omega_def)
# ---------------------------------------------------------------------------
build_cells_interval <- function(version_label, years, treat_year,
                                  omega_col = "omega_sh") {
  yrs <- years
  seller_int <- b2b[year %in% yrs,
                    .(int_sales = sum(sales)),
                    by = .(buyer, seller_nace4d, seller)]
  fe_int <- fe[year %in% yrs,
               .(int_omega = mean(get(omega_col), na.rm = TRUE)),
               by = .(vat)]
  seller_int <- merge(seller_int, fe_int,
                      by.x = "seller", by.y = "vat", all.x = TRUE)
  seller_int[is.na(int_omega), int_omega := 0]
  setorder(seller_int, buyer, seller_nace4d, -int_omega, -int_sales, seller)
  seller_int[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
  cell_summary <- seller_int[, .(n_suppliers = .N,
                                 max_omega   = max(int_omega, na.rm = TRUE)),
                             by = .(buyer, seller_nace4d)]
  cell_summary <- cell_summary[n_suppliers >= 2L & max_omega > 0]
  cells <- merge(seller_int, cell_summary[, .(buyer, seller_nace4d)],
                 by = c("buyer", "seller_nace4d"))

  top_sup <- cells[rk == 1, .(buyer, seller_nace4d,
                              top_supplier = seller, omega_top = int_omega,
                              top_sales = int_sales)]
  bot_sup <- cells[, .SD[.N], by = .(buyer, seller_nace4d)][,
                  .(buyer, seller_nace4d,
                    bot_supplier = seller, omega_bot = int_omega,
                    bot_sales = int_sales)]
  cells_top_bot <- merge(top_sup, bot_sup, by = c("buyer", "seller_nace4d"))
  cells_top_bot[, omega_gap := omega_top - omega_bot]

  spend_int <- b2b[year %in% yrs,
                   .(int_nace4d_spend = sum(sales)),
                   by = .(buyer, seller_nace4d)]
  bt_int <- buyer_tc[year %in% yrs,
                     .(sum_buyer_tc = sum(buyer_total_cost)),
                     by = buyer]
  cells_top_bot <- merge(cells_top_bot, spend_int,
                         by = c("buyer", "seller_nace4d"))
  cells_top_bot <- merge(cells_top_bot, bt_int, by = "buyer", all.x = TRUE)
  cells_top_bot[, nace4d_input_share := ifelse(!is.na(sum_buyer_tc) &
                                                 sum_buyer_tc > 0,
                                               int_nace4d_spend / sum_buyer_tc,
                                               NA_real_)]
  cells_top_bot[, shock_buyertotal := omega_top *
                  ifelse(!is.na(sum_buyer_tc) & sum_buyer_tc > 0,
                         top_sales / sum_buyer_tc, NA_real_)]

  qtl_share <- quantile(cells_top_bot$nace4d_input_share, 0.75, na.rm = TRUE)
  qtl_gap   <- quantile(cells_top_bot$omega_gap,           0.75, na.rm = TRUE)
  qtl_buy   <- quantile(cells_top_bot$shock_buyertotal,    0.75, na.rm = TRUE)
  dec_share <- quantile(cells_top_bot$nace4d_input_share, 0.90, na.rm = TRUE)
  dec_gap   <- quantile(cells_top_bot$omega_gap,           0.90, na.rm = TRUE)
  dec_buy   <- quantile(cells_top_bot$shock_buyertotal,    0.90, na.rm = TRUE)
  cells_top_bot[, topQ_nace4dshare := nace4d_input_share >= qtl_share &
                                       !is.na(nace4d_input_share)]
  cells_top_bot[, topQ_omegagap    := omega_gap           >= qtl_gap   &
                                       !is.na(omega_gap)]
  cells_top_bot[, topQ_buyertotal  := shock_buyertotal    >= qtl_buy   &
                                       !is.na(shock_buyertotal)]
  cells_top_bot[, topD_nace4dshare := nace4d_input_share >= dec_share &
                                       !is.na(nace4d_input_share)]
  cells_top_bot[, topD_omegagap    := omega_gap           >= dec_gap   &
                                       !is.na(omega_gap)]
  cells_top_bot[, topD_buyertotal  := shock_buyertotal    >= dec_buy   &
                                       !is.na(shock_buyertotal)]

  cells_top_bot[, version    := version_label]
  cells_top_bot[, treat_year := treat_year]
  cells_top_bot[]
}

cat("Building cells under both omega definitions...\n")
cells_by_def <- list()
for (def_name in names(OMEGA_DEFS)) {
  cl <- lapply(names(INTERVALS), function(lab) {
    iv <- INTERVALS[[lab]]
    build_cells_interval(lab, iv$years, iv$treat_year,
                         omega_col = OMEGA_DEFS[[def_name]])
  })
  cells_by_def[[def_name]] <- rbindlist(cl, use.names = TRUE, fill = TRUE)
}

# ---------------------------------------------------------------------------
# 3. Build long panels (one per cut, per omega_def)
# ---------------------------------------------------------------------------
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

build_long_for_cut <- function(cut_label, cells_dt) {
  base_cols <- c("buyer", "seller_nace4d", "version", "treat_year",
                 "top_supplier", "bot_supplier", "top_sales", "bot_sales")
  if (cut_label == "pooled") {
    sub <- cells_dt[, ..base_cols]
  } else {
    flag_col <- switch(cut_label,
                       "cost_shock_q"   = "topQ_buyertotal",
                       "cost_shock_d"   = "topD_buyertotal",
                       "input_share_q"  = "topQ_nace4dshare",
                       "input_share_d"  = "topD_nace4dshare",
                       "exposure_gap_q" = "topQ_omegagap",
                       "exposure_gap_d" = "topD_omegagap")
    sub <- cells_dt[get(flag_col) == TRUE, ..base_cols]
  }
  if (nrow(sub) == 0L) return(data.table())

  long <- rbind(
    sub[, .(buyer, seller_nace4d, version, treat_year,
            seller = top_supplier, supplier_role = "top",
            pre_sales_role = top_sales)],
    sub[, .(buyer, seller_nace4d, version, treat_year,
            seller = bot_supplier, supplier_role = "bot",
            pre_sales_role = bot_sales)]
  )
  panel <- long[, .(year = YEAR_LO:YEAR_HI),
                by = .(buyer, seller_nace4d, version, treat_year,
                       seller, supplier_role, pre_sales_role)]
  panel <- merge(panel, yr_denom,
                 by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
  panel <- merge(panel, yr_sales,
                 by = c("buyer", "seller_nace4d", "seller", "year"),
                 all.x = TRUE)
  panel[is.na(sales), sales := 0]
  panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                            total_buyer_nace4d_spend <= 0,
                          NA_real_,
                          sales / total_buyer_nace4d_spend)]
  panel[, top  := as.integer(supplier_role == "top")]
  panel[, event_time := year - treat_year]
  panel[]
}

panels_by_def <- list()
for (def_name in names(OMEGA_DEFS)) {
  panels_by_def[[def_name]] <- list()
  for (cut_lab in CUT_LABELS) {
    panels_by_def[[def_name]][[cut_lab]] <- build_long_for_cut(
      cut_lab, cells_dt = cells_by_def[[def_name]]
    )
  }
}

# ---------------------------------------------------------------------------
# 4. Event-study estimation + R&R sensitivity per cell
# ---------------------------------------------------------------------------
run_event_study <- function(panel_dt, size_control = FALSE) {
  # Returns: list with beta (named vector keyed by event_time), sigma
  # (cov matrix), pre_event_times, post_event_times. event_time = -1
  # is the omitted reference.
  d <- panel_dt[!is.na(share)]
  if (nrow(d) == 0L) return(NULL)
  d[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]
  d[, cell_role_id := paste(cell_id, supplier_role, sep = "::")]
  # Attach pre-period within-cell role size for the size-controlled spec.
  if (size_control) {
    d[, log_pre_sales := log1p(pmax(pre_sales_role, 0))]
    if (uniqueN(d$log_pre_sales) < 2L) size_control <- FALSE
  }
  fml <- if (size_control) {
    share ~ i(event_time, top, ref = -1) + i(year, log_pre_sales) |
            cell_role_id + year
  } else {
    share ~ i(event_time, top, ref = -1) | cell_role_id + year
  }
  fit <- tryCatch(
    feols(fml, data = d, cluster = ~ cell_id, notes = FALSE),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  ct <- as.data.table(coeftable(fit), keep.rownames = "term")
  # Parse event_time from term name; only keep the event_time::*:top rows
  ct[, et := suppressWarnings(as.integer(sub(
    ".*event_time::(-?\\d+):top", "\\1", term)))]
  ct <- ct[!is.na(et) & grepl("event_time::-?\\d+:top$", term)]
  setorder(ct, et)
  betahat <- ct[["Estimate"]]
  names(betahat) <- ct$et

  V <- tryCatch(vcov(fit, cluster = ~ cell_id),
                error = function(e) vcov(fit))
  et_terms <- paste0("event_time::", ct$et, ":top")
  et_terms <- intersect(et_terms, rownames(V))
  V <- V[et_terms, et_terms, drop = FALSE]
  betahat <- betahat[match(et_terms, paste0("event_time::", names(betahat), ":top"))]

  list(betahat = betahat, sigma = V,
       pre_et  = sort(as.integer(names(betahat))[as.integer(names(betahat)) < 0]),
       post_et = sort(as.integer(names(betahat))[as.integer(names(betahat)) >= 0]))
}

run_honestdid <- function(es, MbarVec, MVec) {
  # es from run_event_study. Returns rows for both restrictions.
  if (is.null(es)) return(NULL)
  if (length(es$pre_et) < 1L || length(es$post_et) < 1L) return(NULL)

  numPrePeriods  <- length(es$pre_et)
  numPostPeriods <- length(es$post_et)

  # HonestDiD orders the beta vector so that pre-periods come first
  # (in increasing order), then post-periods. Our betahat is already
  # sorted by event_time, so the order matches the package convention.

  # Original CI (asymptotic, normal): for the first post-treatment
  # coefficient (event_time = 0). HonestDiD reports a robust set
  # relative to this.
  out_rows <- list()

  # Relative magnitudes restriction
  rm_res <- tryCatch(
    HonestDiD::createSensitivityResults_relativeMagnitudes(
      betahat        = es$betahat,
      sigma          = es$sigma,
      numPrePeriods  = numPrePeriods,
      numPostPeriods = numPostPeriods,
      Mbarvec        = MbarVec,
      alpha          = 0.05
    ),
    error = function(e) {
      message("RM failed: ", conditionMessage(e)); NULL
    }
  )
  if (!is.null(rm_res)) {
    out_rows[["RM"]] <- as.data.table(rm_res)[, .(
      restriction = "Delta_RM",
      Mbar        = Mbar,
      lb          = lb,
      ub          = ub,
      method      = method,
      Delta       = Delta
    )]
  }

  # Smoothness restriction
  sd_res <- tryCatch(
    HonestDiD::createSensitivityResults(
      betahat        = es$betahat,
      sigma          = es$sigma,
      numPrePeriods  = numPrePeriods,
      numPostPeriods = numPostPeriods,
      Mvec           = MVec,
      alpha          = 0.05
    ),
    error = function(e) {
      message("SD failed: ", conditionMessage(e)); NULL
    }
  )
  if (!is.null(sd_res)) {
    out_rows[["SD"]] <- as.data.table(sd_res)[, .(
      restriction = "Delta_SD",
      Mbar        = M,
      lb          = lb,
      ub          = ub,
      method      = method,
      Delta       = Delta
    )]
  }

  rbindlist(out_rows, use.names = TRUE, fill = TRUE)
}

cat("\nRunning event-study + R&R for all 28 cells, both unconditional + size-controlled...\n")
hd_rows <- list()
es_rows <- list()
for (def_name in names(OMEGA_DEFS)) {
  for (cut_lab in CUT_LABELS) {
    for (ver in names(INTERVALS)) {
      panel_dt <- panels_by_def[[def_name]][[cut_lab]][version == ver]
      if (nrow(panel_dt) == 0L) next
      cat(sprintf("  %-9s | %-15s | %s\n", def_name, cut_lab, ver))

      for (spec_name in c("unconditional", "size_controlled")) {
        es <- run_event_study(panel_dt,
                              size_control = (spec_name == "size_controlled"))
        if (is.null(es)) next

        es_rows[[length(es_rows) + 1L]] <- data.table(
          omega_def  = def_name,
          spec       = spec_name,
          cut        = cut_lab,
          version    = ver,
          event_time = as.integer(names(es$betahat)),
          beta       = unname(es$betahat),
          se         = sqrt(diag(es$sigma))
        )

        # Only run R&R sensitivity on the unconditional spec to keep
        # the output compact; size-controlled event studies are still
        # exported for plotting.
        if (spec_name == "unconditional") {
          hd <- run_honestdid(es, MBAR_GRID, M_GRID)
          if (!is.null(hd)) {
            hd[, omega_def := def_name]
            hd[, cut       := cut_lab]
            hd[, version   := ver]
            hd_rows[[length(hd_rows) + 1L]] <- hd
          }
        }
      }
    }
  }
}

es_df <- rbindlist(es_rows, use.names = TRUE)
hd_df <- rbindlist(hd_rows, use.names = TRUE, fill = TRUE)

# ---------------------------------------------------------------------------
# 5. Outputs
# ---------------------------------------------------------------------------
fwrite(es_df, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_honestdid_event_studies.csv"))
fwrite(hd_df, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_honestdid_results.csv"))

# ---------------------------------------------------------------------------
# 5a. Event-study figure for headline cells (shortage-based omega).
#     Shows year-by-year (top - bot) gap from -3/-12 (pre) to +5/+17 (post),
#     with both unconditional and size-controlled specs on the same panel.
#     This is the residualized-(top-bot) trajectory the user asked for:
#     each beta_tau is the (top - bot) share gap at event-time tau,
#     residualized by cell-role FE, year FE, and (size x year) under
#     the size-controlled spec.
# ---------------------------------------------------------------------------
HEADLINE_CUTS <- c("pooled", "cost_shock_q", "input_share_q", "exposure_gap_q")
cut_labels <- c(
  "pooled"        = "Pooled",
  "cost_shock_q"  = "Cost shock (Top 25%)",
  "input_share_q" = "Input share (Top 25%)",
  "exposure_gap_q"= "Exposure gap (Top 25%)"
)
version_labels <- c(
  "treat_2005" = "EU ETS start (2005)",
  "treat_2017" = "MSR (2017)"
)
es_plot <- es_df[omega_def == "shortage" & cut %in% HEADLINE_CUTS]
es_plot[, cut_lab     := factor(cut_labels[cut], levels = cut_labels)]
es_plot[, version_lab := factor(version_labels[version], levels = version_labels)]
es_plot[, lo := beta - 1.96 * se]
es_plot[, hi := beta + 1.96 * se]
es_plot[, spec_lab := factor(spec,
                              levels = c("unconditional", "size_controlled"),
                              labels = c("Unconditional", "Size-controlled"))]

p_es <- ggplot(es_plot,
               aes(x = event_time, y = beta,
                   color = spec_lab, fill = spec_lab,
                   group = spec_lab)) +
  geom_hline(yintercept = 0, color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "firebrick") +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, color = NA) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 1.6) +
  facet_grid(cut_lab ~ version_lab, scales = "free_x") +
  scale_color_manual(values = c("Unconditional" = "navy",
                                 "Size-controlled" = "firebrick"),
                     name = NULL) +
  scale_fill_manual(values = c("Unconditional" = "navy",
                                "Size-controlled" = "firebrick"),
                    name = NULL) +
  labs(x = "Event time (years relative to treatment)",
       y = "Event-study coefficient (top - bottom)") +
  theme_classic(base_size = 12) +
  theme(panel.grid       = element_blank(),
        strip.text       = element_text(face = "bold", size = 11),
        legend.position  = "bottom",
        axis.title       = element_text(size = 13),
        axis.text        = element_text(size = 11))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_event_studies_headline.png"),
       p_es, width = 11, height = 12, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_event_studies_headline.pdf"),
       p_es, width = 11, height = 12)
cat("Event-study figure written.\n")

cat("\n--- HonestDiD breakdown summary (smallest M / Mbar for which CI includes 0) ---\n")
breakdowns <- hd_df[!is.na(lb) & !is.na(ub),
                    .(breakdown = ifelse(any(lb <= 0 & ub >= 0),
                                          min(Mbar[lb <= 0 & ub >= 0]),
                                          NA_real_)),
                    by = .(omega_def, cut, version, restriction)]
print(breakdowns)

cat("\nDone.\n")
cat("  CSVs:\n")
cat("    ", file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_honestdid_event_studies.csv"), "\n")
cat("    ", file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_honestdid_results.csv"), "\n")
