###############################################################################
# phase4_within_nace4d_extensive_did_mht.R
#
# PURPOSE
#   Extensive-margin analog of phase4_within_intensive_did_mht.R. Same cells,
#   same heterogeneity cuts, same specifications, same Romano-Wolf MHT --
#   only the outcome changes:
#
#       intensive : share_ijt = sales_ijt / total_buyer_nace4d_spend_jt
#       extensive : transact_ijt = 1{sales_ijt > 0}
#
#   Runs 56 cells = 2 omega definitions (shortage; emissions) x 2
#   specifications (unconditional; size_controlled with year x log(pre-period
#   sales)) x 7 cuts (pooled + 3 scores x {top 25%, top 10%}) x 2 treatment
#   periods (2005; 2017).
#
#   For each of the 4 families of 14 tests (one per omega_def x spec
#   combination), applies Romano-Wolf step-down adjusted p-values using a
#   cluster-bootstrap on buyer. Headline-reported family is shortage x
#   size_controlled. Also reports Bonferroni, Holm, BH over the full 56-test
#   pool for reference, and a bootstrap joint Wald test of the global null.
#
# DEPENDENCIES
#   - b2b_selected_sample.RData
#   - annual_accounts_selected_sample.RData
#   - annual_accounts_selected_sample_key_variables.RData
#   - phase3_firm_exposure.RData
#
# OUTPUTS (output_<machine>/tables/)
#   - phase4_within_nace4d_extensive_mht_results.csv
#       56-row CSV: omega_def, spec, cut, version, n_treated_cells,
#       beta, se, t_stat, p_unadj, p_bonf, p_holm, p_bh, p_rw
#   - phase4_within_nace4d_extensive_mht_wald.txt
#   - phase4_within_nace4d_extensive_mht_notes.tex
#   - phase4_within_nace4d_extensive_did_table_combined.tex
#       Paper-ready LaTeX table: size-controlled extensive DiD with
#       Romano-Wolf adjusted significance stars (shortage family)
#
# RUNTIME
#   Bootstrap is dispatched in parallel across workers (multisession plan;
#   works on Windows). Each iteration is independent -- linear speedup up
#   to N_WORKERS subject to per-worker memory.
#   On RMD with 28 workers: ~10-20 min at B = 500 (vs ~3 hours sequential).
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(future)
  library(future.apply)
})

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
set.seed(20260514)

YEAR_LO <- 2002L  # B2B panel starts in 2002
YEAR_HI <- 2022L
B       <- 500L   # bootstrap replicates
# Leave a few cores idle for the OS and for fixest's internal threading.
N_WORKERS <- max(1L, parallel::detectCores() - 4L)

INTERVALS <- list(
  "treat_2005" = list(years = c(2005L),         treat_year = 2005L),
  "treat_2017" = list(years = c(2015L, 2016L),  treat_year = 2017L)
)
CUT_LABELS <- c("pooled",
                "cost_shock_q",   "cost_shock_d",
                "input_share_q",  "input_share_d",
                "exposure_gap_q", "exposure_gap_d")

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

cat(sprintf("  B2B rows after seller-NACE4d merge: %s\n",
            format(nrow(b2b), big.mark = ",")))

# ---------------------------------------------------------------------------
# 2. Build cells per interval with all heterogeneity scores
#    Identical logic to phase4_within_intensive_did_mht.R.
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
                     .(sum_buyer_tc = sum(buyer_total_cost), n_yr_tc = .N),
                     by = buyer]
  cells_top_bot <- merge(cells_top_bot, spend_int,
                         by = c("buyer", "seller_nace4d"))
  cells_top_bot <- merge(cells_top_bot, bt_int, by = "buyer", all.x = TRUE)
  cells_top_bot[, nace4d_input_share := ifelse(!is.na(sum_buyer_tc) &
                                                 sum_buyer_tc > 0,
                                               int_nace4d_spend / sum_buyer_tc,
                                               NA_real_)]
  cells_top_bot[, top_supplier_share_of_buyer := ifelse(
    !is.na(sum_buyer_tc) & sum_buyer_tc > 0,
    top_sales / sum_buyer_tc, NA_real_
  )]
  cells_top_bot[, shock_buyertotal := omega_top * top_supplier_share_of_buyer]

  qtl_share <- quantile(cells_top_bot$nace4d_input_share, 0.75, na.rm = TRUE)
  qtl_gap   <- quantile(cells_top_bot$omega_gap,           0.75, na.rm = TRUE)
  qtl_buy   <- quantile(cells_top_bot$shock_buyertotal,    0.75, na.rm = TRUE)
  cells_top_bot[, topQ_nace4dshare := nace4d_input_share >= qtl_share &
                                       !is.na(nace4d_input_share)]
  cells_top_bot[, topQ_omegagap    := omega_gap           >= qtl_gap &
                                       !is.na(omega_gap)]
  cells_top_bot[, topQ_buyertotal  := shock_buyertotal    >= qtl_buy &
                                       !is.na(shock_buyertotal)]
  dec_share <- quantile(cells_top_bot$nace4d_input_share, 0.90, na.rm = TRUE)
  dec_gap   <- quantile(cells_top_bot$omega_gap,           0.90, na.rm = TRUE)
  dec_buy   <- quantile(cells_top_bot$shock_buyertotal,    0.90, na.rm = TRUE)
  cells_top_bot[, topD_nace4dshare := nace4d_input_share >= dec_share &
                                       !is.na(nace4d_input_share)]
  cells_top_bot[, topD_omegagap    := omega_gap           >= dec_gap &
                                       !is.na(omega_gap)]
  cells_top_bot[, topD_buyertotal  := shock_buyertotal    >= dec_buy &
                                       !is.na(shock_buyertotal)]

  cells_top_bot[, version    := version_label]
  cells_top_bot[, treat_year := treat_year]
  cells_top_bot[]
}

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

# ---------------------------------------------------------------------------
# 3. Build long panels for each (cut, event-year, omega_def) combination
#    Outcome = transact_ijt = 1{sales_ijt > 0}. Panel includes every year
#    in [YEAR_LO, YEAR_HI] for every (cell, role) row, with transact = 0
#    when the pair did not transact in that year.
# ---------------------------------------------------------------------------
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
  panel <- merge(panel, yr_sales,
                 by = c("buyer", "seller_nace4d", "seller", "year"),
                 all.x = TRUE)
  panel[, transact := as.integer(!is.na(sales) & sales > 0)]
  panel[, top  := as.integer(supplier_role == "top")]
  panel[, post := as.integer(year >= treat_year)]
  panel[, log_pre_sales := log1p(pmax(pre_sales_role, 0))]
  panel[]
}

cat("Building long panels (2 omega defs x 7 cuts)...\n")
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

# ---------------------------------------------------------------------------
# 4. Baseline DiD: 56 coefficients
#    (2 omega defs x 7 cuts x 2 versions x 2 specs). Linear probability model.
# ---------------------------------------------------------------------------
SPECS <- c("unconditional", "size_controlled")

run_did <- function(dt, size_control = FALSE) {
  if (nrow(dt) == 0L || uniqueN(dt$post) < 2L || uniqueN(dt$top) < 2L) {
    return(c(beta = NA_real_, se = NA_real_))
  }
  d <- copy(dt)
  d[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]
  d[, cell_role_id := paste(cell_id, supplier_role, sep = "::")]
  if (size_control && "log_pre_sales" %in% names(d) &&
      uniqueN(d$log_pre_sales) > 1L) {
    fml <- transact ~ i(post, top, ref = 0) + i(year, log_pre_sales) |
                  cell_role_id + year
  } else {
    fml <- transact ~ i(post, top, ref = 0) | cell_role_id + year
  }
  fit <- tryCatch(
    feols(fml, data = d, cluster = ~ cell_id, notes = FALSE),
    error = function(e) NULL
  )
  if (is.null(fit)) return(c(beta = NA_real_, se = NA_real_))
  ct <- coeftable(fit)
  c(beta = as.numeric(ct[1, "Estimate"]),
    se   = as.numeric(ct[1, "Std. Error"]))
}

cat("Baseline DiDs (56 cells: 2 omega defs x 7 cuts x 2 versions x 2 specs)...\n")
baseline <- CJ(omega_def = names(OMEGA_DEFS),
               spec      = SPECS,
               cut       = CUT_LABELS,
               version   = names(INTERVALS),
               sorted    = FALSE)
for (i in seq_len(nrow(baseline))) {
  panel_dt <- panels_by_def[[baseline$omega_def[i]]][[baseline$cut[i]]][
    version == baseline$version[i]
  ]
  est <- run_did(panel_dt,
                 size_control = (baseline$spec[i] == "size_controlled"))
  baseline[i, beta := est["beta"]]
  baseline[i, se   := est["se"]]
}
baseline[, t_stat  := beta / se]
baseline[, p_unadj := 2 * (1 - pnorm(abs(t_stat)))]
print(baseline)

# ---------------------------------------------------------------------------
# 5. Cluster-bootstrap on buyer; re-run all 56 DiDs each iteration
#    Each iteration is independent -> dispatch across worker processes.
# ---------------------------------------------------------------------------
cat(sprintf("\nCluster bootstrap (B = %d, cluster = buyer, %d cells per iter)...\n",
            B, nrow(baseline)))

all_buyers <- unique(rbindlist(
  lapply(unlist(panels_by_def, recursive = FALSE),
         function(p) p[, .(buyer)])
))$buyer
n_buyers   <- length(all_buyers)
cat(sprintf("  unique buyer clusters: %s\n", format(n_buyers, big.mark = ",")))

# Pure-function bootstrap iteration. Resamples buyer clusters, re-fits all
# 56 DiDs, returns a length-56 numeric vector of betas. No reads from outside
# its arguments -> safe to dispatch to a worker process.
boot_one_iter <- function(iter_idx,
                          panels_by_def,
                          baseline,
                          all_buyers,
                          run_did_fn) {
  n_buyers  <- length(all_buyers)
  sampled   <- sample.int(n_buyers, n_buyers, replace = TRUE)
  draw_lookup <- data.table::data.table(
    buyer   = all_buyers[sampled],
    draw_id = paste0("d", seq_len(n_buyers))
  )
  betas <- rep(NA_real_, nrow(baseline))
  for (i in seq_len(nrow(baseline))) {
    panel_dt <- panels_by_def[[baseline$omega_def[i]]][[baseline$cut[i]]][
      version == baseline$version[i]
    ]
    if (nrow(panel_dt) == 0L) next
    boot_panel <- merge(panel_dt, draw_lookup, by = "buyer",
                        allow.cartesian = TRUE)
    boot_panel[, buyer := paste(buyer, draw_id, sep = "@")]
    est <- run_did_fn(boot_panel,
                      size_control = (baseline$spec[i] == "size_controlled"))
    betas[i] <- est["beta"]
  }
  betas
}

cat(sprintf("  Parallel plan: multisession with %d workers (detected %d cores).\n",
            N_WORKERS, parallel::detectCores()))
old_plan <- plan(multisession, workers = N_WORKERS)
on.exit(plan(old_plan), add = TRUE)

t0 <- Sys.time()
boot_list <- future_lapply(
  seq_len(B),
  FUN              = boot_one_iter,
  panels_by_def    = panels_by_def,
  baseline         = baseline,
  all_buyers       = all_buyers,
  run_did_fn       = run_did,
  future.seed      = TRUE,
  future.packages  = c("data.table", "fixest")
)
boot_betas <- do.call(rbind, boot_list)
colnames(boot_betas) <- paste(baseline$omega_def,
                              baseline$spec,
                              baseline$cut,
                              baseline$version, sep = "__")
cat(sprintf("Bootstrap done in %s (B = %d, workers = %d).\n",
            format(Sys.time() - t0, digits = 1), B, N_WORKERS))

# ---------------------------------------------------------------------------
# 6. Romano-Wolf step-down adjusted p-values (within each family of 14)
# ---------------------------------------------------------------------------
rw_one_family <- function(idx) {
  abs_t_obs  <- abs(baseline$t_stat[idx])
  abs_t_boot <- abs(sweep(boot_betas[, idx, drop = FALSE], 2,
                          baseline$beta[idx], "-") /
                    matrix(baseline$se[idx], nrow = B,
                           ncol = length(idx), byrow = TRUE))
  ord <- order(-abs_t_obs)
  sorted_t_obs  <- abs_t_obs[ord]
  sorted_t_boot <- abs_t_boot[, ord, drop = FALSE]

  p_rw_sorted <- numeric(length(ord))
  for (j in seq_along(ord)) {
    remain_idx <- j:length(ord)
    max_t_boot <- if (length(remain_idx) == 1L)
      sorted_t_boot[, remain_idx]
    else
      apply(sorted_t_boot[, remain_idx, drop = FALSE], 1, max, na.rm = TRUE)
    raw <- mean(max_t_boot >= sorted_t_obs[j], na.rm = TRUE)
    p_rw_sorted[j] <- if (j == 1L) raw else max(p_rw_sorted[j - 1L], raw)
  }
  p_rw <- numeric(length(ord))
  p_rw[ord] <- p_rw_sorted
  p_rw
}

baseline[, p_rw := NA_real_]
for (def_name in names(OMEGA_DEFS)) {
  for (spec_lab in SPECS) {
    fam_idx <- baseline[, which(omega_def == def_name & spec == spec_lab)]
    baseline[fam_idx, p_rw := rw_one_family(fam_idx)]
  }
}

n_tests <- nrow(baseline)
baseline[, p_bonf := pmin(p_unadj * n_tests, 1)]
baseline[, p_holm := p.adjust(p_unadj, method = "holm")]
baseline[, p_bh   := p.adjust(p_unadj, method = "BH")]

# ---------------------------------------------------------------------------
# 7. Bootstrap joint Wald test of the global null
# ---------------------------------------------------------------------------
cat("\nJoint Wald test...\n")
Sigma <- cov(boot_betas, use = "pairwise.complete.obs")
Sigma_inv <- tryCatch(solve(Sigma),
                      error = function(e) MASS::ginv(Sigma))
beta_vec <- baseline$beta
W_obs    <- as.numeric(t(beta_vec) %*% Sigma_inv %*% beta_vec)

centered <- sweep(boot_betas, 2, baseline$beta, "-")
W_boot   <- apply(centered, 1, function(v) {
  if (any(is.na(v))) NA_real_
  else as.numeric(t(v) %*% Sigma_inv %*% v)
})
p_wald <- mean(W_boot >= W_obs, na.rm = TRUE)
cat(sprintf("  W = %.2f, p_wald = %.4f (chi-sq df %d ref crit at 0.05 = %.2f)\n",
            W_obs, p_wald, n_tests, qchisq(0.95, n_tests)))

# ---------------------------------------------------------------------------
# 8. Outputs
# ---------------------------------------------------------------------------
cell_counts <- list()
for (def_name in names(OMEGA_DEFS)) {
  for (cut_lab in CUT_LABELS) {
    for (ver_lab in names(INTERVALS)) {
      panel_dt <- panels_by_def[[def_name]][[cut_lab]][version == ver_lab]
      cell_counts[[length(cell_counts) + 1L]] <- data.table(
        omega_def       = def_name,
        cut             = cut_lab,
        version         = ver_lab,
        n_treated_cells = uniqueN(
          panel_dt[, paste(buyer, seller_nace4d, sep = "::")]
        )
      )
    }
  }
}
cell_counts <- rbindlist(cell_counts)
baseline <- merge(baseline, cell_counts,
                  by = c("omega_def", "cut", "version"), all.x = TRUE)

out <- baseline[, .(omega_def, spec, cut, version, n_treated_cells,
                    beta, se, t_stat, p_unadj, p_bonf, p_holm, p_bh, p_rw)]
fwrite(out, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_extensive_mht_results.csv"))

writeLines(c(
  sprintf("Joint Wald test of the global null (all %d coefficients = 0)", n_tests),
  sprintf("  W_obs       = %.4f", W_obs),
  sprintf("  bootstrap p = %.4f", p_wald),
  sprintf("  chi-sq(%d) 95%% critical value = %.2f", n_tests, qchisq(0.95, n_tests)),
  sprintf("  B = %d cluster-bootstrap iterations (cluster = buyer)", B)
), file.path(OUTPUT_TAB, "phase4_within_nace4d_extensive_mht_wald.txt"))

sig_rows <- baseline[p_unadj < 0.05]
cut_display_lookup <- c(
  "pooled"         = "Pooled",
  "cost_shock_q"   = "Cost shock (Top 25\\%)",
  "cost_shock_d"   = "Cost shock (Top 10\\%)",
  "input_share_q"  = "Input share (Top 25\\%)",
  "input_share_d"  = "Input share (Top 10\\%)",
  "exposure_gap_q" = "Exposure gap (Top 25\\%)",
  "exposure_gap_d" = "Exposure gap (Top 10\\%)"
)
version_display_lookup <- c(
  "treat_2005" = "2005",
  "treat_2017" = "2017"
)
omega_display_lookup <- c(
  "shortage"  = "shortage classification",
  "emissions" = "emissions classification"
)
rw_lines <- sig_rows[, sprintf(
  "%s, %s (%s), %s: $\\hat{p}^{\\mathrm{RW}} = %.3f$",
  omega_display_lookup[omega_def],
  cut_display_lookup[cut],
  spec,
  version_display_lookup[version],
  p_rw)]
writeLines(c(
  "% MHT notes (auto-generated by phase4_within_nace4d_extensive_did_mht.R)",
  sprintf("\\textit{Multiple-testing correction.} Joint Wald test of the global null (all %d coefficients $=0$): $W = %.2f$, bootstrap $p = %.3f$ (cluster-bootstrap on buyer, $B = %d$). Romano-Wolf step-down adjusted $p$-values applied within each (omega definition, specification) family of 14 tests. Cells significant at $p < 0.05$ before correction:",
          n_tests, W_obs, p_wald, B),
  paste(rw_lines, collapse = "; "),
  "."
), file.path(OUTPUT_TAB, "phase4_within_nace4d_extensive_mht_notes.tex"))

# ---------------------------------------------------------------------------
# 9. LaTeX table: size-controlled + Romano-Wolf adjusted stars
# ---------------------------------------------------------------------------
build_latex_size_rw <- function(d14) {
  versions    <- c("treat_2005", "treat_2017")
  event_years <- c("2005", "2017")
  cut_order   <- c("pooled",
                   "cost_shock_q",   "cost_shock_d",
                   "input_share_q",  "input_share_d",
                   "exposure_gap_q", "exposure_gap_d")

  cell_fmt <- function(beta, se, pv, n) {
    if (length(beta) == 0L || is.na(beta)) return("---")
    sig <- ifelse(pv < 0.001, "$^{***}$",
                  ifelse(pv < 0.01, "$^{**}$",
                         ifelse(pv < 0.05, "$^{*}$",
                                ifelse(pv < 0.10, "$^{\\dagger}$", ""))))
    sprintf("\\makecell{%.3f%s \\\\ \\footnotesize{(%.3f)} \\\\ \\footnotesize{N=%s}}",
            beta, sig, se, format(n, big.mark = ","))
  }

  body <- ""
  for (i in seq_along(versions)) {
    v <- versions[i]; ev <- event_years[i]
    body <- paste0(body, "\n", ev)
    for (cut_lab in cut_order) {
      r <- d14[version == v & cut == cut_lab]
      body <- paste0(body, " & ",
                     cell_fmt(r$beta, r$se, r$p_rw, r$n_treated_cells))
    }
    body <- paste0(body, " \\\\\\addlinespace")
  }

  header <- paste0(
    "% Requires \\usepackage{makecell,booktabs} in main.tex\n",
    "% Size-controlled extensive-margin DiD with Romano-Wolf adjusted significance.\n",
    "\\begin{tabular}{lccccccc}\n",
    "\\toprule\n",
    " & & \\multicolumn{2}{c}{Cost shock} & \\multicolumn{2}{c}{Input share} & \\multicolumn{2}{c}{Exposure gap} \\\\\n",
    "\\cmidrule(lr){3-4}\\cmidrule(lr){5-6}\\cmidrule(lr){7-8}\n",
    "Treatment & Pooled & Top 25\\% & Top 10\\% & Top 25\\% & Top 10\\% & Top 25\\% & Top 10\\% \\\\\n",
    "\\midrule"
  )
  footer <- paste0(
    "\n\\bottomrule\n",
    "\\end{tabular}\n",
    sprintf("%% Notes: Size-controlled within-cell extensive-margin DiD (LPM with outcome = $\\mathbf{1}\\{\\text{sales}_{ijt}>0\\}$; cell-role FE + year FE + year $\\times$ log(pre-period sales) interaction). Cluster-robust SE in parentheses (cluster = buyer $\\times$ NACE4d cell). Stars use Romano-Wolf step-down adjusted $p$-values from a cluster-bootstrap on buyer with $B = %d$ replicates, applied within the 14-test shortage family. Significance: $^{\\dagger}\\,p^{\\mathrm{RW}}<0.10$, $^{*}\\,p^{\\mathrm{RW}}<0.05$, $^{**}\\,p^{\\mathrm{RW}}<0.01$, $^{***}\\,p^{\\mathrm{RW}}<0.001$.", B)
  )

  paste0(header, body, footer)
}

shortage_size <- baseline[omega_def == "shortage" & spec == "size_controlled"]
tex_did_combined <- build_latex_size_rw(shortage_size)
writeLines(tex_did_combined,
           file.path(OUTPUT_TAB,
                     "phase4_within_nace4d_extensive_did_table_combined.tex"))

cat("\nAll outputs:\n")
cat("  CSV    :", file.path(OUTPUT_TAB,
       "phase4_within_nace4d_extensive_mht_results.csv"), "\n")
cat("  Wald   :", file.path(OUTPUT_TAB,
       "phase4_within_nace4d_extensive_mht_wald.txt"), "\n")
cat("  Notes  :", file.path(OUTPUT_TAB,
       "phase4_within_nace4d_extensive_mht_notes.tex"), "\n")
cat("  Table  :", file.path(OUTPUT_TAB,
       "phase4_within_nace4d_extensive_did_table_combined.tex"), "\n")
cat("Done.\n")
