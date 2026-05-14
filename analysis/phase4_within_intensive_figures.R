###############################################################################
# phase4_within_intensive_figures.R
#
# PURPOSE
#   Builds the paper artifacts for the within-NACE4d / intensive-margin
#   subsection, under two treatment periods (2005, 2017):
#     (1) Top-omega vs bottom-omega trajectory figure (2-panel).
#     (2) "Fix-ideas-about-magnitudes" distribution figures for the three
#         cut variables that define top quartile / top decile:
#           (a) omega_top * (cell spend on top-omega supplier / buyer total cost)
#           (b) (cell spend on NACE4d / buyer total cost)
#           (c) omega_top - omega_bot
#     (3) Diagnostic CSV with all 56 spec x cut x version x omega_def DiDs
#         (specs_comparison.csv) -- uncorrected reference for the headline
#         table produced by phase4_within_intensive_did_mht.R.
#     (4) Counterfactual savings + horizon-robustness CSV / figures
#         (diagnostic; not in paper).
#
#   The headline DiD table (size-controlled, Romano-Wolf adjusted) is built
#   by phase4_within_intensive_did_mht.R.
#
# DEPENDENCIES
#   - b2b_selected_sample.RData
#   - annual_accounts_selected_sample.RData
#   - annual_accounts_selected_sample_key_variables.RData
#   - phase3_firm_exposure.RData
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(fixest)
  library(xtable)
})

set.seed(20260513)

YEAR_LO <- 2002L  # B2B panel starts in 2002; AA in 2000. Extended below 2005 to provide a real pre-period for the EU ETS launch (2005).
YEAR_HI <- 2022L

# Two treatment periods we report on:
#   "treat_2005" = EU ETS launch. omega computed from 2005 (the year
#     the policy starts and the first year of EUTL records); post = 1
#     from 2005 onwards. Pre-period uses B2B data from 2002-2004
#     (which extends back to 2002, before the EU ETS existed).
#   "treat_2017" = MSR reform. omega computed from 2015-16. Post = 1
#     from 2017 onwards; pre-period is 2005-2016.
INTERVALS <- list(
  "treat_2005" = list(years = c(2005L),         treat_year = 2005L),
  "treat_2017" = list(years = c(2015L, 2016L),  treat_year = 2017L)
)

DIST_VERSION <- "treat_2017"  # for distribution + savings figures
RHO_GRID     <- c(0.25, 0.5, 0.75, 1.0)

# Eurostat HICP (prc_hicp_aind), EA changing composition, all items
# (CP00), base 2015 = 100. Used to deflate end-of-year EUA prices into
# 2016 base euros so the cost-shock distribution and savings figures
# are on a real-euro scale that matches the buyer-total-cost
# denominator (built from 2015-16 accounts).
HICP_BASE <- list("2016" = 100.23,
                  "2017" = 101.78,
                  "2022" = 117.04)
HICP_BASE_YEAR <- 2016L

# End-of-year EUA prices come from the daily settlement CSV; they are
# deflated to 2016 euros using HICP and used to scale the cost shock
# and savings distributions.
EUA_EOY_YEARS <- c(2017L, 2022L)

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
  vat   = as.character(vat_ano),
  year  = as.integer(year),
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

# Two firm-year omega definitions:
#   omega_sh = max(shortage, 0) / total_cost  (the cost shock the firm
#       actually pays at the margin -- the headline measure).
#   omega_em = emissions / total_cost  (physical carbon intensity --
#       a falsification benchmark: if the leakage signal is driven by
#       the cost shock, classification by omega_em should *not* produce
#       significant DiD coefficients, because omega_em does not reflect
#       what the firm pays).
fe[, omega_sh := ifelse(!is.na(total_cost) & total_cost > 0,
                        pmax(shortage, 0) / total_cost, NA_real_)]
fe[, omega_em := ifelse(!is.na(total_cost) & total_cost > 0,
                        pmax(emissions, 0) / total_cost, NA_real_)]

# Attach seller NACE4d to B2B
b2b <- merge(b2b, aa, by.x = c("seller", "year"), by.y = c("vat", "year"),
             all.x = TRUE)
setnames(b2b, "nace4d", "seller_nace4d")
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d != ""]

cat(sprintf("  B2B rows after seller-NACE4d merge: %s\n",
            format(nrow(b2b), big.mark = ",")))

# Annual buyer-NACE4d spend (denominator for shares)
b2b[, total_buyer_nace4d_spend := sum(sales),
    by = .(buyer, seller_nace4d, year)]

# ---------------------------------------------------------------------------
# 2. Build cells per interval with all three heterogeneity scores
# ---------------------------------------------------------------------------
build_cells_interval <- function(version_label, years, treat_year,
                                  omega_col = "omega_sh") {
  # `years` is the vector of pre-event years used to compute omega.
  # `omega_col` selects which firm-level omega definition to use:
  #   "omega_sh" = shortage/total_cost (the cost-shock measure -- headline)
  #   "omega_em" = emissions/total_cost (physical intensity -- falsification)
  yrs <- years

  # Interval-period seller-level aggregates within (buyer, seller_nace4d)
  seller_int <- b2b[year %in% yrs,
                    .(int_sales = sum(sales)),
                    by = .(buyer, seller_nace4d, seller)]

  # Attach interval-period omega for each seller (uses the requested
  # omega definition).
  fe_int <- fe[year %in% yrs,
               .(int_omega = mean(get(omega_col), na.rm = TRUE)),
               by = .(vat)]
  seller_int <- merge(seller_int, fe_int,
                      by.x = "seller", by.y = "vat", all.x = TRUE)
  seller_int[is.na(int_omega), int_omega := 0]

  # Require >=2 distinct suppliers and >=1 with omega>0 per cell
  setorder(seller_int, buyer, seller_nace4d, -int_omega, -int_sales, seller)
  seller_int[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
  cell_summary <- seller_int[, .(n_suppliers = .N,
                                 max_omega   = max(int_omega, na.rm = TRUE)),
                             by = .(buyer, seller_nace4d)]
  cell_summary <- cell_summary[n_suppliers >= 2L & max_omega > 0]

  cells <- merge(seller_int, cell_summary[, .(buyer, seller_nace4d)],
                 by = c("buyer", "seller_nace4d"))

  # Top-omega vs bottom-omega supplier within cell
  top_sup <- cells[rk == 1, .(buyer, seller_nace4d,
                              top_supplier = seller,
                              omega_top    = int_omega,
                              top_sales    = int_sales)]
  bot_sup <- cells[, .SD[.N], by = .(buyer, seller_nace4d)][,
                  .(buyer, seller_nace4d,
                    bot_supplier = seller,
                    omega_bot    = int_omega,
                    bot_sales    = int_sales)]

  cells_top_bot <- merge(top_sup, bot_sup, by = c("buyer", "seller_nace4d"))
  cells_top_bot[, omega_gap := omega_top - omega_bot]

  # NACE4d input share = sum_t in interval [spend(buyer, NACE4d, t)] /
  #                      sum_t in interval [buyer_total_cost(t)]
  spend_int <- b2b[year %in% yrs,
                   .(int_nace4d_spend = sum(sales)),
                   by = .(buyer, seller_nace4d)]
  bt_int <- buyer_tc[year %in% yrs,
                     .(sum_buyer_tc = sum(buyer_total_cost),
                       n_yr_tc      = .N),
                     by = buyer]
  cells_top_bot <- merge(cells_top_bot, spend_int,
                         by = c("buyer", "seller_nace4d"))
  cells_top_bot <- merge(cells_top_bot, bt_int, by = "buyer", all.x = TRUE)
  cells_top_bot[, nace4d_input_share := ifelse(!is.na(sum_buyer_tc) &
                                                 sum_buyer_tc > 0,
                                               int_nace4d_spend / sum_buyer_tc,
                                               NA_real_)]

  # Dollar shock at buyer's total cost from the top-omega supplier:
  #   shock_buyertotal = omega_top * (top_sales / buyer_total_cost)
  cells_top_bot[, top_supplier_share_of_buyer := ifelse(
    !is.na(sum_buyer_tc) & sum_buyer_tc > 0,
    top_sales / sum_buyer_tc, NA_real_
  )]
  cells_top_bot[, shock_buyertotal := omega_top * top_supplier_share_of_buyer]

  # Top-quartile flags (>= 75th percentile) per cut (within version)
  qtl_share <- quantile(cells_top_bot$nace4d_input_share, 0.75, na.rm = TRUE)
  qtl_gap   <- quantile(cells_top_bot$omega_gap,           0.75, na.rm = TRUE)
  qtl_buy   <- quantile(cells_top_bot$shock_buyertotal,    0.75, na.rm = TRUE)
  cells_top_bot[, topQ_nace4dshare := nace4d_input_share >= qtl_share &
                                       !is.na(nace4d_input_share)]
  cells_top_bot[, topQ_omegagap    := omega_gap           >= qtl_gap   &
                                       !is.na(omega_gap)]
  cells_top_bot[, topQ_buyertotal  := shock_buyertotal    >= qtl_buy   &
                                       !is.na(shock_buyertotal)]
  # Top-decile flags (>= 90th percentile) per cut (within version)
  dec_share <- quantile(cells_top_bot$nace4d_input_share, 0.90, na.rm = TRUE)
  dec_gap   <- quantile(cells_top_bot$omega_gap,           0.90, na.rm = TRUE)
  dec_buy   <- quantile(cells_top_bot$shock_buyertotal,    0.90, na.rm = TRUE)
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

# Build cells under both omega definitions: omega_sh (shortage-based,
# the headline) and omega_em (emissions-based, the falsification).
OMEGA_DEFS <- c("shortage" = "omega_sh", "emissions" = "omega_em")
cells_by_def <- list()
for (def_name in names(OMEGA_DEFS)) {
  omega_col <- OMEGA_DEFS[[def_name]]
  cat(sprintf("--- Building cells under omega definition: %s (%s)\n",
              def_name, omega_col))
  cl <- lapply(names(INTERVALS), function(lab) {
    iv <- INTERVALS[[lab]]
    build_cells_interval(lab, iv$years, iv$treat_year, omega_col = omega_col)
  })
  cells_by_def[[def_name]] <- rbindlist(cl, use.names = TRUE, fill = TRUE)
  cat(sprintf("  %s: %s rows across versions.\n",
              def_name, format(nrow(cells_by_def[[def_name]]), big.mark = ",")))
}

# Headline cells_all uses the shortage-based definition (what the figures
# and the prior outputs use).
cells_all <- cells_by_def[["shortage"]]
fwrite(cells_all, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_cells_all_scores.csv"))

# Classification agreement between shortage- and emissions-based omega.
agreement_rows <- list()
for (ver in names(INTERVALS)) {
  a <- cells_by_def[["shortage"]][version == ver,
                                   .(buyer, seller_nace4d,
                                     top_sh = top_supplier, bot_sh = bot_supplier,
                                     omega_top_sh = omega_top)]
  b <- cells_by_def[["emissions"]][version == ver,
                                    .(buyer, seller_nace4d,
                                      top_em = top_supplier, bot_em = bot_supplier,
                                      omega_top_em = omega_top)]
  m <- merge(a, b, by = c("buyer", "seller_nace4d"))
  agreement_rows[[ver]] <- data.table(
    version             = ver,
    n_cells_both        = nrow(m),
    pct_same_top        = mean(m$top_sh == m$top_em, na.rm = TRUE),
    pct_same_bot        = mean(m$bot_sh == m$bot_em, na.rm = TRUE),
    spearman_omega_top  = suppressWarnings(cor(m$omega_top_sh, m$omega_top_em,
                                                method = "spearman",
                                                use = "pairwise.complete.obs"))
  )
}
agreement <- rbindlist(agreement_rows)
fwrite(agreement, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_omega_classification_agreement.csv"))
cat("\n--- Classification agreement: shortage- vs emissions-based omega ---\n")
print(agreement)

# ---------------------------------------------------------------------------
# 3. Build long panels (one per cut) and run DiDs internally.
#    Self-contained: does not read from any other script's CSVs.
# ---------------------------------------------------------------------------
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

build_long_for_cut <- function(cut_label, cells_dt = cells_all) {
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
  panel[, post := as.integer(year >= treat_year)]
  # Pre-period within-cell role size (log). Used as a control for the
  # size-confound robustness: top-omega and bottom-omega may differ
  # systematically in baseline size, and large vs small suppliers may
  # have different secular trends in within-cell share for reasons
  # unrelated to carbon exposure.
  panel[, log_pre_sales := log1p(pmax(pre_sales_role, 0))]
  panel[]
}

CUT_LABELS <- c("pooled",
                "cost_shock_q",   "cost_shock_d",
                "input_share_q",  "input_share_d",
                "exposure_gap_q", "exposure_gap_d")
CUT_DISPLAY <- c(
  "pooled"         = "Pooled (no heterogeneity)",
  "cost_shock_q"   = "Top quartile by buyer-total shock",
  "cost_shock_d"   = "Top decile by buyer-total shock",
  "input_share_q"  = "Top quartile by NACE4d input share",
  "input_share_d"  = "Top decile by NACE4d input share",
  "exposure_gap_q" = "Top quartile by omega gap",
  "exposure_gap_d" = "Top decile by omega gap"
)

cat("Building long panels for the 4 cuts under both omega definitions...\n")
panels_by_def <- list()
for (def_name in names(OMEGA_DEFS)) {
  panels_by_def[[def_name]] <- list()
  for (cut_lab in CUT_LABELS) {
    panels_by_def[[def_name]][[cut_lab]] <- build_long_for_cut(
      cut_lab, cells_dt = cells_by_def[[def_name]]
    )
  }
  cat(sprintf("  [%s] panels built\n", def_name))
}
# Backward-compatibility alias for the "panels" used by the headline path
# (the shortage-based definition).
panels <- panels_by_def[["shortage"]]

run_did_one <- function(panel_dt, size_control = FALSE) {
  d <- panel_dt[!is.na(share)]
  if (nrow(d) == 0L || uniqueN(d$post) < 2L || uniqueN(d$top) < 2L) {
    return(list(beta = NA_real_, se = NA_real_, t = NA_real_,
                p = NA_real_, n_obs = 0L, n_cells = 0L))
  }
  d[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]
  d[, cell_role_id := paste(cell_id, supplier_role, sep = "::")]
  if (size_control && "log_pre_sales" %in% names(d) &&
      uniqueN(d$log_pre_sales) > 1L) {
    # Year x log(pre-period sales) interaction lets large vs small
    # suppliers follow different secular trends.
    fml <- share ~ i(post, top, ref = 0) + i(year, log_pre_sales) |
                  cell_role_id + year
  } else {
    fml <- share ~ i(post, top, ref = 0) | cell_role_id + year
  }
  fit <- tryCatch(
    feols(fml, data = d, cluster = ~ cell_id, notes = FALSE),
    error = function(e) NULL
  )
  if (is.null(fit)) return(list(beta = NA_real_, se = NA_real_, t = NA_real_,
                                 p = NA_real_, n_obs = 0L, n_cells = 0L))
  ct <- coeftable(fit)
  list(beta    = as.numeric(ct[1, "Estimate"]),
       se      = as.numeric(ct[1, "Std. Error"]),
       t       = as.numeric(ct[1, "t value"]),
       p       = as.numeric(ct[1, "Pr(>|t|)"]),
       n_obs   = as.integer(nobs(fit)),
       n_cells = uniqueN(d$cell_id))
}

cat("Running baseline DiDs: 2 omega defs x 2 specs x 7 cuts x 2 versions = 56 cells...\n")
did_rows <- list()
for (def_name in names(OMEGA_DEFS)) {
  for (spec_name in c("unconditional", "size_controlled")) {
    for (cut_lab in CUT_LABELS) {
      for (ver in names(INTERVALS)) {
        d <- panels_by_def[[def_name]][[cut_lab]][version == ver]
        est <- run_did_one(d, size_control = (spec_name == "size_controlled"))
        did_rows[[length(did_rows) + 1L]] <- data.table(
          omega_def       = def_name,
          spec            = spec_name,
          cut             = CUT_DISPLAY[[cut_lab]],
          version         = ver,
          n_obs           = est$n_obs,
          n_treated_cells = est$n_cells,
          term            = "post::1:top",
          estimate        = est$beta,
          std_error       = est$se,
          t_stat          = est$t,
          p_value         = est$p
        )
      }
    }
  }
}
did_all_full <- rbindlist(did_rows, use.names = TRUE)
fwrite(did_all_full, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_reallocation_did_specs_comparison.csv"))

# Print a compact summary to console for quick comparison
cat("\n--- DiD comparison (omega_def x spec) ---\n")
cmp <- dcast(did_all_full,
             cut + version ~ omega_def + spec,
             value.var = "estimate")
print(cmp)

# The headline table uses omega_def = "shortage" and spec = "unconditional"
# (matches prior outputs).
did_all <- did_all_full[omega_def == "shortage" & spec == "unconditional",
                         .(cut, version, n_obs, n_treated_cells, term,
                           estimate, std_error, t_stat, p_value)]

# ---------------------------------------------------------------------------
# 4a. Horizon robustness: vary the post-period end year for treat_2005.
#     If the leakage signal at the EU ETS launch is real, it should appear
#     even at short post-period horizons (not only at the full 2005-2022
#     window). The treat_2017 spec is not varied -- its post-period is
#     already short (2017-2022, 6 years).
# ---------------------------------------------------------------------------
HORIZONS <- c(2008L, 2010L, 2015L, 2022L)
cat("\nHorizon robustness for treat_2005 (omega = shortage, unconditional)...\n")
horizon_rows <- list()
for (horizon in HORIZONS) {
  for (cut_lab in CUT_LABELS) {
    d_full <- panels_by_def[["shortage"]][[cut_lab]][version == "treat_2005"]
    d <- d_full[year <= horizon]
    est <- run_did_one(d, size_control = FALSE)
    horizon_rows[[length(horizon_rows) + 1L]] <- data.table(
      horizon         = horizon,
      cut             = CUT_DISPLAY[[cut_lab]],
      n_obs           = est$n_obs,
      n_treated_cells = est$n_cells,
      estimate        = est$beta,
      std_error       = est$se,
      t_stat          = est$t,
      p_value         = est$p
    )
  }
}
horizon_df <- rbindlist(horizon_rows, use.names = TRUE)
fwrite(horizon_df, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_reallocation_did_horizon_robustness.csv"))

cat("--- Horizon robustness (treat_2005, shortage-based omega) ---\n")
print(dcast(horizon_df, cut ~ horizon, value.var = "estimate"))

# ---------------------------------------------------------------------------
# 4b. All-cells top-omega vs bottom-omega trajectory (faceted by version).
#     Analog of phase4_within_nace4d_reallocation_allcells_buyertotal.pdf
#     under the new 2005 / 2017 treatment-period structure.
# ---------------------------------------------------------------------------
cat("\nBuilding all-cells top vs bot trajectory figure...\n")
traj <- panels_by_def[["shortage"]][["pooled"]][!is.na(share),
  .(mean_share = mean(share),
    se_share   = sd(share) / sqrt(.N),
    n_cells    = .N),
  by = .(version, year, supplier_role)
]
traj[, lo := mean_share - 1.96 * se_share]
traj[, hi := mean_share + 1.96 * se_share]
traj[, version_label := fcase(
  version == "treat_2005", "EU ETS start (2005)",
  version == "treat_2017", "MSR (2017)"
)]
traj[, role_label := fcase(
  supplier_role == "top", "Top-omega supplier",
  supplier_role == "bot", "Bottom-omega supplier"
)]
traj[, role_label := factor(role_label,
                            levels = c("Top-omega supplier",
                                       "Bottom-omega supplier"))]

treat_lines <- data.table(
  version_label = c("EU ETS start (2005)", "MSR (2017)"),
  treat_year    = c(2005, 2017)
)

p_traj <- ggplot(traj,
                 aes(x = year, y = mean_share,
                     color = role_label, fill = role_label)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.4) +
  geom_vline(data = treat_lines,
             aes(xintercept = treat_year - 0.5),
             linetype = "dashed", color = "firebrick", inherit.aes = FALSE) +
  facet_wrap(~ version_label, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_color_manual(values = c("Top-omega supplier"    = "firebrick",
                                 "Bottom-omega supplier" = "navy"),
                     name = NULL) +
  scale_fill_manual(values = c("Top-omega supplier"    = "firebrick",
                                "Bottom-omega supplier" = "navy"),
                    name = NULL) +
  labs(x = NULL,
       y = "Mean within-cell expenditure share") +
  theme_classic(base_size = 13) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 14, margin = margin(r = 12)),
        axis.text        = element_text(size = 12),
        strip.text       = element_text(face = "bold", size = 13),
        legend.position  = "bottom",
        legend.text      = element_text(size = 12))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_allcells_topbot_trajectory.png"),
       p_traj, width = 9, height = 8, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_allcells_topbot_trajectory.pdf"),
       p_traj, width = 9, height = 8)
fwrite(traj, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_allcells_topbot_trajectory.csv"))
cat("Trajectory figure + CSV written.\n")
cat("--- Top vs bot mean shares around the treatment year ---\n")
print(traj[, .(version, year, supplier_role,
               mean_share = round(mean_share, 4),
               n_cells)][version == "treat_2005" & year %in% 2002:2008
                          | version == "treat_2017" & year %in% 2014:2020])

cut_order <- c("Pooled (no heterogeneity)",
               "Top quartile by buyer-total shock",
               "Top decile by buyer-total shock",
               "Top quartile by NACE4d input share",
               "Top decile by NACE4d input share",
               "Top quartile by omega gap",
               "Top decile by omega gap")
did_all[, cut := factor(cut, levels = cut_order)]
setorder(did_all, version, cut)
fwrite(did_all, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_reallocation_did_table_combined.csv"))

# LaTeX DiD table is now produced exclusively by phase4_within_intensive_did_mht.R
# (size-controlled with Romano-Wolf adjusted significance). This script keeps the
# diagnostic CSV (specs_comparison.csv) with all 56 unconditional/size_controlled
# x omega_def cells for reference.

# ---------------------------------------------------------------------------
# 5. Distribution figures (using DIST_VERSION cells)
# ---------------------------------------------------------------------------
cat(sprintf("Building distribution figures using version %s...\n",
            DIST_VERSION))
cells_dist <- cells_all[version == DIST_VERSION &
                          !is.na(shock_buyertotal) &
                          !is.na(nace4d_input_share) &
                          !is.na(omega_gap)]

# Read daily EUA settlement prices to extract end-of-year values.
cat("Reading daily EUA settlement prices for end-of-year EUA...\n")
eua_daily <- fread(file.path(RAW_DATA,
                "European Union Carbon Permits Allowance (EUA) Yearly Futures Historical Data.csv"))
eua_daily[, date := as.Date(Date, format = "%m/%d/%Y")]
eua_daily <- eua_daily[!is.na(date)]
eua_daily[, yr := as.integer(format(date, "%Y"))]
setorder(eua_daily, date)
eua_eoy <- eua_daily[, .(eua_nominal = last(Price)), by = yr]

deflate_to_base <- function(yr) {
  HICP_BASE[[as.character(yr)]] / HICP_BASE[[as.character(HICP_BASE_YEAR)]]
}

eua_real <- list()
for (yr_target in EUA_EOY_YEARS) {
  nom <- eua_eoy[yr == yr_target, eua_nominal]
  defl <- deflate_to_base(yr_target)
  eua_real[[as.character(yr_target)]] <- nom / defl
  cat(sprintf("  EUA end of %d: nominal = %.2f EUR/tCO2; real (2016 base) = %.2f\n",
              yr_target, nom, eua_real[[as.character(yr_target)]]))
}

# Shared theme for the clean histograms (cost shock, NACE4d input share).
clean_hist_theme <- theme_classic(base_size = 13) +
  theme(panel.grid       = element_blank(),
        axis.title.x     = element_text(margin = margin(t = 14), size = 15),
        axis.title.y     = element_text(margin = margin(r = 14), size = 15),
        axis.text        = element_text(size = 13),
        plot.title       = element_blank(),
        plot.subtitle    = element_blank())

# Generic clean histogram on a log-scale x-axis displayed in %, with a
# dashed line at p75. `vals` is a vector of positive fractions (e.g.
# 0.001 displays as 0.1%). If `floor` is supplied, values below it are
# bottom-coded into a single leftmost bin and that tick is labelled
# "<floor%".
plot_dist_pct_log <- function(vals, xlab, floor = NULL) {
  d <- data.table(val = vals)
  d <- d[is.finite(val) & val > 0]
  if (nrow(d) == 0L) return(NULL)

  if (!is.null(floor)) d[val < floor, val := floor]

  qs <- quantile(d$val, c(0.50, 0.75, 0.90, 0.99), na.rm = TRUE)

  if (!is.null(floor)) {
    log_min <- log10(floor)
    log_max <- ceiling(log10(max(d$val)))
    bin_breaks <- 10^seq(log_min, log_max, length.out = 61)
    pct_breaks <- 10^seq(log_min, log_max)
    pct_labels <- vapply(pct_breaks, function(b) {
      lab <- sprintf("%g%%", b * 100)
      if (abs(b - floor) < 1e-12) paste0("<", lab) else lab
    }, character(1))
    hist_layer <- geom_histogram(breaks = bin_breaks,
                                 fill = "steelblue",
                                 color = "white", alpha = 0.9)
  } else {
    pct_breaks <- c(1e-7, 1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1)
    pct_labels <- c("0.00001%", "0.0001%", "0.001%", "0.01%",
                    "0.1%", "1%", "10%", "100%")
    hist_layer <- geom_histogram(bins = 60, fill = "steelblue",
                                 color = "white", alpha = 0.9)
  }

  ggplot(d, aes(x = val)) +
    hist_layer +
    geom_vline(xintercept = qs[2], linetype = "dashed", color = "firebrick") +
    annotate("text", x = qs[2], y = Inf, label = " p75",
             vjust = 1.5, hjust = 0, color = "firebrick", size = 4.5) +
    scale_x_log10(breaks = pct_breaks, labels = pct_labels) +
    labs(x = xlab, y = "Number of cells") +
    clean_hist_theme
}

# Cost shock distribution: shock_buyertotal * deflated EUA, per EUA year.
for (yr_target in EUA_EOY_YEARS) {
  p_cs <- plot_dist_pct_log(
    cells_dist$shock_buyertotal * eua_real[[as.character(yr_target)]],
    "Cost shock",
    floor = 1e-4
  )
  fig_base <- sprintf("phase4_within_nace4d_intensive_dist_shock_buyertotal_eua%d",
                      yr_target)
  ggsave(file.path(OUTPUT_FIG, paste0(fig_base, ".png")), p_cs,
         width = 8, height = 5, dpi = 200)
  ggsave(file.path(OUTPUT_FIG, paste0(fig_base, ".pdf")), p_cs,
         width = 8, height = 5)
  cat(sprintf("  Cost-shock distribution (EUA %d) written.\n", yr_target))
}

# NACE4d input share: same clean styling, displayed as a percent on a
# log-scale x-axis.
p_nshare <- plot_dist_pct_log(
  cells_dist$nace4d_input_share,
  "Supplier's sector cost share"
)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_nace4d_share.png"),
       p_nshare, width = 8, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_nace4d_share.pdf"),
       p_nshare, width = 8, height = 5)
cat("  NACE4d input share distribution written.\n")

# Omega gap distribution keeps the older title/subtitle styling for now.
base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        plot.title    = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(size = 10, color = "grey30"))

plot_dist <- function(x, xlab, title, subtitle, log_x = FALSE) {
  d <- data.table(val = x[is.finite(x) & x > 0])
  if (nrow(d) == 0L) {
    cat(sprintf("No positive values for %s\n", title)); return(NULL)
  }
  qs <- quantile(d$val, c(0.50, 0.75, 0.90, 0.99), na.rm = TRUE)
  subtitle_full <- sprintf(
    "%s\nMedian = %s | p75 = %s | p90 = %s | p99 = %s | N = %s cells",
    subtitle,
    formatC(qs[1], format = "g", digits = 3),
    formatC(qs[2], format = "g", digits = 3),
    formatC(qs[3], format = "g", digits = 3),
    formatC(qs[4], format = "g", digits = 3),
    format(nrow(d), big.mark = ",")
  )
  p <- ggplot(d, aes(x = val)) +
    geom_histogram(bins = 60, fill = "steelblue", color = "white", alpha = 0.85) +
    geom_vline(xintercept = qs[2], linetype = "dashed", color = "firebrick") +
    annotate("text", x = qs[2], y = Inf, label = " p75",
             vjust = 1.5, hjust = 0, color = "firebrick", size = 3) +
    labs(title = title, subtitle = subtitle_full,
         x = xlab, y = "Number of cells") +
    base_theme
  if (log_x) p <- p + scale_x_log10(labels = scales::comma_format())
  p
}

p_gap <- plot_dist(
  cells_dist$omega_gap,
  expression(omega[top] - omega[bot]),
  expression("Distribution of " * omega[top] - omega[bot]),
  sprintf("Across (buyer, NACE4d) cells with >=2 ETS-relevant suppliers in %s pre-period.",
          DIST_VERSION),
  log_x = TRUE
)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_omega_gap.png"),
       p_gap, width = 8, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_omega_gap.pdf"),
       p_gap, width = 8, height = 5)
cat("All distribution figures written.\n")

# ---------------------------------------------------------------------------
# 6. Counterfactual savings figures: TWO versions, one per EUA scenario
#    savings(b,n,rho,EUA) = rho * EUA_real * (omega_top - omega_bot)
#                                * (top supplier spend / buyer total cost)
#    Matches the top-vs-bot reallocation tested in the DiD: the buyer
#    switches what it currently buys from the top-omega supplier over to
#    the bottom-omega supplier. EUA_real is the deflated end-of-year EUA
#    price (2016 base).
# ---------------------------------------------------------------------------
cat("Building counterfactual savings figures (two EUA scenarios)...\n")
sv <- cells_dist[, .(buyer, seller_nace4d, omega_gap,
                     top_supplier_share_of_buyer)]
sv <- sv[!is.na(omega_gap) & !is.na(top_supplier_share_of_buyer) &
           omega_gap > 0 & top_supplier_share_of_buyer > 0]

savings_x_breaks <- c(0, 0.001, 0.005, 0.01, 0.05)
savings_x_labels <- c("0%", "0.1%", "0.5%", "1%", "5%")
savings_x_limits <- c(0, 0.05)

summary_rows <- list()
for (yr_target in EUA_EOY_YEARS) {
  eua_p_real <- eua_real[[as.character(yr_target)]]

  sv_panels <- rbindlist(lapply(RHO_GRID, function(rho) {
    data.table(rho     = rho,
               savings = rho * eua_p_real * sv$omega_gap *
                           sv$top_supplier_share_of_buyer)
  }))

  sv_summary <- sv_panels[, .(
    eua_year   = yr_target,
    eua_price_real = eua_p_real,
    median = quantile(savings, 0.50, na.rm = TRUE),
    p75    = quantile(savings, 0.75, na.rm = TRUE),
    p90    = quantile(savings, 0.90, na.rm = TRUE),
    p99    = quantile(savings, 0.99, na.rm = TRUE),
    n      = .N
  ), by = rho]
  summary_rows[[as.character(yr_target)]] <- sv_summary

  p_sv <- ggplot(sv_panels[savings >= 0],
                 aes(x = savings, fill = factor(rho), color = factor(rho))) +
    stat_ecdf(geom = "step", linewidth = 0.9, alpha = 0.9) +
    scale_x_continuous(limits = savings_x_limits,
                       breaks = savings_x_breaks,
                       labels = savings_x_labels,
                       oob    = scales::squish) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    scale_color_brewer(palette = "Set1",
                       name = expression("Pass-through " * rho)) +
    scale_fill_brewer(palette = "Set1",
                      name = expression("Pass-through " * rho)) +
    labs(x = "Savings as % of buyer total input cost",
         y = "Cumulative share of cells") +
    theme_classic(base_size = 13) +
    theme(panel.grid       = element_blank(),
          axis.title.x     = element_text(margin = margin(t = 14), size = 15),
          axis.title.y     = element_text(margin = margin(r = 14), size = 15),
          axis.text        = element_text(size = 13),
          plot.title       = element_blank(),
          plot.subtitle    = element_blank(),
          legend.position  = "bottom",
          legend.title     = element_text(size = 13),
          legend.text      = element_text(size = 12))

  fig_base <- sprintf("phase4_within_nace4d_intensive_savings_by_passthrough_eua%d",
                      yr_target)
  ggsave(file.path(OUTPUT_FIG, paste0(fig_base, ".png")), p_sv,
         width = 8, height = 5.5, dpi = 200)
  ggsave(file.path(OUTPUT_FIG, paste0(fig_base, ".pdf")), p_sv,
         width = 8, height = 5.5)
}

sv_summary_all <- rbindlist(summary_rows, use.names = TRUE)
fwrite(sv_summary_all, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_savings_summary.csv"))
cat("Counterfactual savings figures written (2 EUA scenarios).\n")

cat("\nAll outputs:\n")
cat("  Figures:", OUTPUT_FIG, "\n")
cat("  Tables :", OUTPUT_TAB, "\n")
cat("Done.\n")
