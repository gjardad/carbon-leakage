###############################################################################
# phase4_within_intensive_did_mht.R
#
# PURPOSE
#   Multiple-hypothesis-testing correction on the within-NACE4d / intensive-
#   margin DiD table (4 cuts x 3 treatment periods = 12 cells).
#
#   The table has 12 cells: {Pooled, top-Q cost shock, top-Q input share,
#   top-Q exposure gap} x {Phase II onset 2008, Phase III onset 2013, MSR
#   2017}. Three cells point in the leakage direction at conventional
#   significance under naive p-values; they share data (same buyers /
#   suppliers across cuts and treatment periods), so the tests are
#   positively dependent and a Bonferroni-style correction over-corrects.
#
#   Two corrections are appropriate:
#   1. Romano-Wolf step-down with cluster-bootstrap (cluster on buyer).
#      Controls family-wise error rate while estimating the dependence
#      structure across the 12 tests from the data.
#   2. Bootstrap Wald test of the global null that all 12 coefficients
#      equal zero. Single p-value for "any leakage anywhere in the table".
#
#   Also reports Bonferroni, Holm-Bonferroni, and Benjamini-Hochberg
#   adjusted p-values for reference.
#
# DEPENDENCIES (same as phase4_within_intensive_table_and_distributions.R)
#   - b2b_selected_sample.RData
#   - annual_accounts_selected_sample.RData
#   - annual_accounts_selected_sample_key_variables.RData
#   - phase3_firm_exposure.RData
#
# OUTPUTS (output_<machine>/tables/)
#   - phase4_within_nace4d_intensive_mht_results.csv
#       12-row CSV: cut, version, beta, se, t_stat, p_unadj, p_bonf,
#       p_holm, p_bh, p_rw
#   - phase4_within_nace4d_intensive_mht_wald.txt
#       Joint Wald W statistic and p-value
#   - phase4_within_nace4d_intensive_mht_notes.tex
#       LaTeX snippet for the table notes
#
# RUNTIME
#   On local-1 downsampled B2B: ~5-10 minutes at B=200, ~20 minutes at B=500.
#   On RMD full panel:           ~30 minutes at B=200, ~1.5 hours at B=500.
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
})

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
set.seed(20260513)

YEAR_LO <- 2005L
YEAR_HI <- 2022L
B       <- 200L  # bootstrap replicates; bump for production runs

INTERVALS <- list(
  "treat_2008" = list(years = c(2006L, 2007L), treat_year = 2008L),
  "treat_2013" = list(years = c(2011L, 2012L), treat_year = 2013L),
  "treat_2017" = list(years = c(2015L, 2016L), treat_year = 2017L)
)
CUT_LABELS <- c("pooled", "cost_shock", "input_share", "exposure_gap")

# ---------------------------------------------------------------------------
# 1. Load data (mirror phase4_within_intensive_table_and_distributions.R)
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
                                       year, shortage, total_cost,
                                       allocated_free)]
rm(firm_exposure)
fe[, omega := ifelse(!is.na(total_cost) & total_cost > 0,
                     pmax(shortage, 0) / total_cost, NA_real_)]

b2b <- merge(b2b, aa, by.x = c("seller", "year"), by.y = c("vat", "year"),
             all.x = TRUE)
setnames(b2b, "nace4d", "seller_nace4d")
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d != ""]
b2b[, total_buyer_nace4d_spend := sum(sales),
    by = .(buyer, seller_nace4d, year)]

cat(sprintf("  B2B rows after seller-NACE4d merge: %s\n",
            format(nrow(b2b), big.mark = ",")))

# ---------------------------------------------------------------------------
# 2. Build cells per interval with all three heterogeneity scores
# ---------------------------------------------------------------------------
build_cells_interval <- function(version_label, years, treat_year) {
  yrs <- seq(years[1], years[2])
  seller_int <- b2b[year %in% yrs,
                    .(int_sales = sum(sales)),
                    by = .(buyer, seller_nace4d, seller)]
  fe_int <- fe[year %in% yrs,
               .(int_omega = mean(omega, na.rm = TRUE)),
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

  cells_top_bot[, version    := version_label]
  cells_top_bot[, treat_year := treat_year]
  cells_top_bot[]
}

cells_list <- lapply(names(INTERVALS), function(lab) {
  iv <- INTERVALS[[lab]]
  cat(sprintf("Building cells for %s...\n", lab))
  build_cells_interval(lab, iv$years, iv$treat_year)
})
cells_all <- rbindlist(cells_list, use.names = TRUE, fill = TRUE)
cat(sprintf("Cells built: %s total rows across versions.\n",
            format(nrow(cells_all), big.mark = ",")))

# ---------------------------------------------------------------------------
# 3. Build long panels for each (cut, event-year) combination
# ---------------------------------------------------------------------------
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

build_long_for_cut <- function(cut_label) {
  if (cut_label == "pooled") {
    sub <- cells_all[, .(buyer, seller_nace4d, version, treat_year,
                         top_supplier, bot_supplier)]
  } else {
    flag_col <- switch(cut_label,
                       "cost_shock"   = "topQ_buyertotal",
                       "input_share"  = "topQ_nace4dshare",
                       "exposure_gap" = "topQ_omegagap")
    sub <- cells_all[get(flag_col) == TRUE,
                     .(buyer, seller_nace4d, version, treat_year,
                       top_supplier, bot_supplier)]
  }
  if (nrow(sub) == 0L) return(data.table())

  long <- rbind(
    sub[, .(buyer, seller_nace4d, version, treat_year,
            seller = top_supplier, supplier_role = "top")],
    sub[, .(buyer, seller_nace4d, version, treat_year,
            seller = bot_supplier, supplier_role = "bot")]
  )
  panel <- long[, .(year = YEAR_LO:YEAR_HI),
                by = .(buyer, seller_nace4d, version, treat_year,
                       seller, supplier_role)]
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
  panel[]
}

cat("Building long panels for the 4 cuts...\n")
panels <- list()
for (cut_lab in CUT_LABELS) {
  panels[[cut_lab]] <- build_long_for_cut(cut_lab)
  cat(sprintf("  %-13s %s rows\n", cut_lab,
              format(nrow(panels[[cut_lab]]), big.mark = ",")))
}

# ---------------------------------------------------------------------------
# 4. Baseline DiD: 12 coefficients
# ---------------------------------------------------------------------------
run_did <- function(dt) {
  d <- dt[!is.na(share)]
  if (nrow(d) == 0L || uniqueN(d$post) < 2L || uniqueN(d$top) < 2L) {
    return(c(beta = NA_real_, se = NA_real_))
  }
  d[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]
  d[, cell_role_id := paste(cell_id, supplier_role, sep = "::")]
  fit <- tryCatch(
    feols(share ~ i(post, top, ref = 0) | cell_role_id + year,
          data = d, cluster = ~ cell_id, notes = FALSE),
    error = function(e) NULL
  )
  if (is.null(fit)) return(c(beta = NA_real_, se = NA_real_))
  ct <- coeftable(fit)
  c(beta = as.numeric(ct[1, "Estimate"]),
    se   = as.numeric(ct[1, "Std. Error"]))
}

cat("Baseline DiDs (12 cells)...\n")
baseline <- data.table(
  cut     = rep(CUT_LABELS, each = length(INTERVALS)),
  version = rep(names(INTERVALS), times = length(CUT_LABELS))
)
for (i in seq_len(nrow(baseline))) {
  panel_dt <- panels[[baseline$cut[i]]][version == baseline$version[i]]
  est <- run_did(panel_dt)
  baseline[i, beta := est["beta"]]
  baseline[i, se   := est["se"]]
}
baseline[, t_stat  := beta / se]
baseline[, p_unadj := 2 * (1 - pnorm(abs(t_stat)))]
print(baseline)

# ---------------------------------------------------------------------------
# 5. Cluster-bootstrap on buyer; re-run all 12 DiDs each iteration
# ---------------------------------------------------------------------------
cat(sprintf("\nCluster bootstrap (B = %d, cluster = buyer)...\n", B))

# Union of buyers across all 4 panels = clustering universe
all_buyers <- unique(rbindlist(lapply(panels, function(p) p[, .(buyer)])))$buyer
n_buyers   <- length(all_buyers)
cat(sprintf("  unique buyer clusters: %s\n", format(n_buyers, big.mark = ",")))

boot_betas <- matrix(NA_real_, nrow = B, ncol = nrow(baseline))
colnames(boot_betas) <- paste(baseline$cut, baseline$version, sep = "__")

t0 <- Sys.time()
for (b in 1:B) {
  if (b %% 20L == 0L || b == 1L) {
    elapsed <- as.numeric(Sys.time() - t0, units = "secs")
    eta     <- elapsed / b * (B - b)
    cat(sprintf("  iter %4d / %d  elapsed %5.0fs  ETA %5.0fs\n",
                b, B, elapsed, eta))
  }
  # Sample buyers with replacement; each sampled buyer gets a unique draw id
  sampled <- sample.int(n_buyers, n_buyers, replace = TRUE)
  draw_lookup <- data.table(buyer = all_buyers[sampled],
                            draw_id = paste0("d", seq_len(n_buyers)))

  for (i in seq_len(nrow(baseline))) {
    cut_lab <- baseline$cut[i]
    ver_lab <- baseline$version[i]
    panel_dt <- panels[[cut_lab]][version == ver_lab]
    if (nrow(panel_dt) == 0L) next
    boot_panel <- merge(panel_dt, draw_lookup, by = "buyer",
                        allow.cartesian = TRUE)
    # Build cell IDs that vary across draws so the same buyer in two draws
    # is treated as two clusters (standard cluster-bootstrap convention).
    boot_panel[, buyer        := paste(buyer, draw_id, sep = "@")]
    est <- run_did(boot_panel)
    boot_betas[b, i] <- est["beta"]
  }
}
cat(sprintf("Bootstrap done in %s.\n",
            format(Sys.time() - t0, digits = 1)))

# ---------------------------------------------------------------------------
# 6. Romano-Wolf step-down adjusted p-values
# ---------------------------------------------------------------------------
abs_t_obs  <- abs(baseline$t_stat)
abs_t_boot <- abs(sweep(boot_betas, 2, baseline$beta, "-") /
                  matrix(baseline$se, nrow = B,
                         ncol = nrow(baseline), byrow = TRUE))

ord    <- order(-abs_t_obs)
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
baseline[, p_rw := p_rw]

# Other corrections for reference
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
out <- baseline[, .(cut, version, beta, se, t_stat, p_unadj,
                    p_bonf, p_holm, p_bh, p_rw)]
fwrite(out, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_mht_results.csv"))

writeLines(c(
  sprintf("Joint Wald test of the global null (all 12 coefficients = 0)"),
  sprintf("  W_obs       = %.4f", W_obs),
  sprintf("  bootstrap p = %.4f", p_wald),
  sprintf("  chi-sq(%d) 95%% critical value = %.2f", n_tests, qchisq(0.95, n_tests)),
  sprintf("  B = %d cluster-bootstrap iterations (cluster = buyer)", B)
), file.path(OUTPUT_TAB, "phase4_within_nace4d_intensive_mht_wald.txt"))

# LaTeX snippet for the table notes
sig_rows <- baseline[p_unadj < 0.05]
rw_lines <- sig_rows[, sprintf(
  "%s, %s: $\\hat{p}^{\\mathrm{RW}} = %.3f$",
  c(pooled = "Pooled",
    cost_shock = "Cost shock",
    input_share = "Input share",
    exposure_gap = "Exposure gap")[cut],
  c(treat_2008 = "Phase II onset (2008)",
    treat_2013 = "Phase III onset (2013)",
    treat_2017 = "MSR (2017)")[version],
  p_rw)]
writeLines(c(
  "% MHT notes (auto-generated by phase4_within_intensive_did_mht.R)",
  sprintf("\\textit{Multiple-testing correction.} Joint Wald test of the global null (all 12 coefficients $=0$): $W = %.2f$, bootstrap $p = %.3f$ (cluster-bootstrap on buyer, $B = %d$). Romano-Wolf step-down adjusted $p$-values for cells significant at $p < 0.05$ before correction:",
          W_obs, p_wald, B),
  paste(rw_lines, collapse = "; "),
  "."
), file.path(OUTPUT_TAB, "phase4_within_nace4d_intensive_mht_notes.tex"))

cat("\nAll outputs:\n")
cat("  CSV  :", file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_mht_results.csv"), "\n")
cat("  Wald :", file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_mht_wald.txt"), "\n")
cat("  Notes:", file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_mht_notes.tex"), "\n")
cat("Done.\n")
