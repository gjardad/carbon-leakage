###############################################################################
# phase4_within_intensive_did_mht.R
#
# PURPOSE
#   Heterogeneity table for the within-NACE-4d intensive-margin DiD with
#   Romano-Wolf step-down adjusted p-values. Same sample and panel as
#   phase4_within_intensive_did.R:
#     - present-in-2010-14 cells, portfolio bot
#     - panel 2012-2020 (clean pre-trends; pre-COVID)
#     - cell-role panel
#
#   For each of 7 sample restrictions, runs the naive DiD:
#     share_{c,r,t}  =  alpha_{c,r}  +  delta_t  +  gamma * (post * top)  +  eps
#
#   Sample restrictions (each at top quartile and top decile of a heterogeneity
#   variable, plus pooled):
#     1. pooled         -- all cells, no restriction
#     2. cost_shock_q   -- top quartile of cost shock at buyer total cost
#     3. cost_shock_d   -- top decile
#     4. input_share_q  -- top quartile of NACE-4d input share at buyer
#     5. input_share_d  -- top decile
#     6. exposure_gap_q -- top quartile of within-cell exposure gap omega_top - omega_bot
#     7. exposure_gap_d -- top decile
#
#   Romano-Wolf step-down p-values are computed via cluster-bootstrap on
#   buyer over the 7 hypotheses tested simultaneously. Controls family-wise
#   error rate while learning the dependence structure from the data.
#
# OUTPUTS
#   - phase4_within_intensive_did_mht_results.csv
#       7-row CSV with unadj/Bonf/Holm/BH/Romano-Wolf p-values per cell.
#   - phase4_within_intensive_did_mht_heterogeneity.tex
#       Paper-ready LaTeX table.
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
  library(xtable)
})

set.seed(20260521)

YEAR_LO       <- 2012L
YEAR_HI       <- 2020L
PRE_WINDOW    <- 2010L:2014L
OMEGA_WIN     <- c(2015L, 2016L)
TREAT_YEAR    <- 2017L

EUA_2018_REAL <- 23.70   # end-of-2018 deflated EUA (matches descriptive script)

# Bootstrap reps. Bump for production runs; 500 is the standard published level.
B         <- 500L
N_WORKERS <- max(1L, parallel::detectCores() - 4L)

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
cat("Loading data...\n")
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(2002L, YEAR_HI) & !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year),
             sales)]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano), year = as.integer(year),
  nace4d = substr(nace5d, 1, 4))]
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
                                       year, shortage, total_cost)]
rm(firm_exposure)
fe[, omega_sh := ifelse(!is.na(total_cost) & total_cost > 0,
                        pmax(shortage, 0) / total_cost, NA_real_)]

b2b <- merge(b2b, aa, by.x = c("seller", "year"), by.y = c("vat", "year"),
             all.x = TRUE)
setnames(b2b, "nace4d", "seller_nace4d")
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d != ""]
b2b[, total_buyer_nace4d_spend := sum(sales),
    by = .(buyer, seller_nace4d, year)]

# ---------------------------------------------------------------------------
# Build present-in-2010-14 sample with portfolio bot
# (mirrors phase4_within_intensive_did.R)
# ---------------------------------------------------------------------------
cat("Building present-in-2010-14 sample...\n")
pre_active <- b2b[year %in% PRE_WINDOW,
                  .(pre_sales = sum(sales)),
                  by = .(buyer, seller_nace4d, seller)]
omega_window_active <- b2b[year %in% OMEGA_WIN,
                            .(omega_win_sales = sum(sales)),
                            by = .(buyer, seller_nace4d, seller)]
pool_pairs <- merge(pre_active, omega_window_active,
                    by = c("buyer", "seller_nace4d", "seller"))

omega_byvat <- fe[year %in% OMEGA_WIN,
                  .(omega_anchor = mean(omega_sh, na.rm = TRUE)),
                  by = vat]
pool_pairs <- merge(pool_pairs, omega_byvat,
                    by.x = "seller", by.y = "vat", all.x = TRUE)
pool_pairs[is.na(omega_anchor), omega_anchor := 0]

cell_summary <- pool_pairs[, .(n = .N,
                               max_omega = max(omega_anchor),
                               min_omega = min(omega_anchor)),
                           by = .(buyer, seller_nace4d)]
cell_ok <- cell_summary[n >= 2L & max_omega > 0 & min_omega < max_omega]
pool <- merge(pool_pairs, cell_ok[, .(buyer, seller_nace4d)],
              by = c("buyer", "seller_nace4d"))

pool[, cell_min_omega := min(omega_anchor), by = .(buyer, seller_nace4d)]
setorder(pool, buyer, seller_nace4d, -omega_anchor, -pre_sales, seller)
pool[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
top_sup <- pool[rk == 1L,
                .(buyer, seller_nace4d, top_supplier = seller,
                  omega_top = omega_anchor, top_pre_sales = pre_sales)]
bot_pool <- pool[omega_anchor == cell_min_omega,
                 .(buyer, seller_nace4d, seller)]
cat(sprintf("  Cells: %d  |  Bot pool: %d (mean %.2f per cell)\n",
            nrow(cell_ok), nrow(bot_pool),
            nrow(bot_pool) / nrow(cell_ok)))

# ---------------------------------------------------------------------------
# Compute heterogeneity variables at the cell level
#   cost_shock = ω_top × (top supplier's pre-window sales to buyer)
#                       / (buyer's pre-window total cost) × EUA_2018_REAL
#                       -- the carbon cost burden the top supplier puts on
#                          the buyer at peak EUA, as fraction of total cost.
#   nace4d_input_share = (buyer's pre-window NACE-4d spend) / (buyer's pre-
#                        window total cost). How important the input is to
#                        the buyer.
#   exposure_gap = max_omega - min_omega within the cell. Carbon-cost
#                  exposure differential between top and bot at peak EUA
#                  (we report as ω-units; multiply by EUA for cost-share units).
# ---------------------------------------------------------------------------
cat("Computing heterogeneity variables...\n")

# Buyer's pre-window total cost (sum over PRE_WINDOW years)
buyer_tc_pre <- buyer_tc[year %in% PRE_WINDOW,
                          .(sum_buyer_tc = sum(buyer_total_cost)),
                          by = buyer]
# Buyer's pre-window NACE-4d spend
nace4d_spend_pre <- b2b[year %in% PRE_WINDOW,
                         .(nace4d_spend = sum(sales)),
                         by = .(buyer, seller_nace4d)]

cell_het <- merge(cell_ok, top_sup, by = c("buyer", "seller_nace4d"))
cell_het <- merge(cell_het, buyer_tc_pre, by = "buyer", all.x = TRUE)
cell_het <- merge(cell_het, nace4d_spend_pre,
                  by = c("buyer", "seller_nace4d"), all.x = TRUE)

cell_het[, nace4d_input_share := ifelse(!is.na(sum_buyer_tc) &
                                          sum_buyer_tc > 0,
                                        nace4d_spend / sum_buyer_tc,
                                        NA_real_)]
cell_het[, top_share_of_buyer := ifelse(!is.na(sum_buyer_tc) &
                                          sum_buyer_tc > 0,
                                        top_pre_sales / sum_buyer_tc,
                                        NA_real_)]
cell_het[, cost_shock := omega_top * top_share_of_buyer * EUA_2018_REAL]
cell_het[, exposure_gap := max_omega - min_omega]

cat("  Cells with usable heterogeneity values:\n")
print(cell_het[, .(cost_shock_n   = sum(!is.na(cost_shock)),
                    input_share_n  = sum(!is.na(nace4d_input_share)),
                    exposure_gap_n = sum(!is.na(exposure_gap)))])

# Quantile thresholds
q_cost      <- quantile(cell_het$cost_shock,         0.75, na.rm = TRUE)
d_cost      <- quantile(cell_het$cost_shock,         0.90, na.rm = TRUE)
q_share     <- quantile(cell_het$nace4d_input_share, 0.75, na.rm = TRUE)
d_share     <- quantile(cell_het$nace4d_input_share, 0.90, na.rm = TRUE)
q_gap       <- quantile(cell_het$exposure_gap,       0.75, na.rm = TRUE)
d_gap       <- quantile(cell_het$exposure_gap,       0.90, na.rm = TRUE)

cell_het[, in_cost_q  := !is.na(cost_shock)         & cost_shock         >= q_cost]
cell_het[, in_cost_d  := !is.na(cost_shock)         & cost_shock         >= d_cost]
cell_het[, in_share_q := !is.na(nace4d_input_share) & nace4d_input_share >= q_share]
cell_het[, in_share_d := !is.na(nace4d_input_share) & nace4d_input_share >= d_share]
cell_het[, in_gap_q   := !is.na(exposure_gap)       & exposure_gap       >= q_gap]
cell_het[, in_gap_d   := !is.na(exposure_gap)       & exposure_gap       >= d_gap]

CUTS <- list(
  pooled         = NULL,
  cost_shock_q   = "in_cost_q",
  cost_shock_d   = "in_cost_d",
  input_share_q  = "in_share_q",
  input_share_d  = "in_share_d",
  exposure_gap_q = "in_gap_q",
  exposure_gap_d = "in_gap_d"
)
CUT_DISPLAY <- c(
  pooled         = "Pooled (no restriction)",
  cost_shock_q   = "Top quartile, cost shock",
  cost_shock_d   = "Top decile, cost shock",
  input_share_q  = "Top quartile, input share",
  input_share_d  = "Top decile, input share",
  exposure_gap_q = "Top quartile, exposure gap",
  exposure_gap_d = "Top decile, exposure gap"
)

# ---------------------------------------------------------------------------
# Build cell-role-year panel (same as Script 1)
# ---------------------------------------------------------------------------
cat("Building cell-role-year panel...\n")
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

top_panel <- top_sup[, .(year = YEAR_LO:YEAR_HI),
                     by = .(buyer, seller_nace4d, top_supplier)]
setnames(top_panel, "top_supplier", "seller")
top_panel <- merge(top_panel, yr_denom,
                   by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
top_panel <- merge(top_panel, yr_sales,
                   by = c("buyer", "seller_nace4d", "seller", "year"),
                   all.x = TRUE)
top_panel[is.na(sales), sales := 0]
top_panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                              total_buyer_nace4d_spend <= 0,
                            NA_real_, sales / total_buyer_nace4d_spend)]
top_panel[, role := "top"]
top_panel <- top_panel[, .(buyer, seller_nace4d, year, role, share)]

bot_panel_long <- bot_pool[, .(year = YEAR_LO:YEAR_HI),
                            by = .(buyer, seller_nace4d, seller)]
bot_panel_long <- merge(bot_panel_long, yr_denom,
                        by = c("buyer", "seller_nace4d", "year"),
                        all.x = TRUE)
bot_panel_long <- merge(bot_panel_long, yr_sales,
                        by = c("buyer", "seller_nace4d", "seller", "year"),
                        all.x = TRUE)
bot_panel_long[is.na(sales), sales := 0]
bot_panel_long[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                                   total_buyer_nace4d_spend <= 0,
                                 NA_real_, sales / total_buyer_nace4d_spend)]
bot_panel <- bot_panel_long[!is.na(share),
                            .(share = mean(share)),
                            by = .(buyer, seller_nace4d, year)]
bot_panel[, role := "bot"]
bot_panel <- bot_panel[, .(buyer, seller_nace4d, year, role, share)]

panel <- rbind(top_panel, bot_panel)
panel <- panel[!is.na(share)]
panel[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]
panel[, cell_role_id := paste(cell_id, role, sep = "::")]
panel[, group_top    := as.integer(role == "top")]
panel[, post         := as.integer(year >= TREAT_YEAR)]
panel[, post_top     := post * group_top]
cat(sprintf("  Panel rows: %s (%d cells)\n",
            format(nrow(panel), big.mark = ","),
            uniqueN(panel$cell_id)))

# ---------------------------------------------------------------------------
# Helper: run DiD on a subset of cells, return point estimate + t-stat
# ---------------------------------------------------------------------------
run_did <- function(panel_dt, cell_keys) {
  sub <- panel_dt[cell_id %in% cell_keys]
  if (nrow(sub) == 0L || uniqueN(sub$cell_id) < 2L) {
    return(list(beta = NA_real_, se = NA_real_, t = NA_real_,
                p = NA_real_, n_cells = 0L))
  }
  fit <- tryCatch(
    feols(share ~ post_top | cell_role_id + year,
          data = sub, cluster = ~ cell_id, notes = FALSE),
    error = function(e) NULL
  )
  if (is.null(fit)) {
    return(list(beta = NA_real_, se = NA_real_, t = NA_real_,
                p = NA_real_, n_cells = uniqueN(sub$cell_id)))
  }
  ct <- coeftable(fit)
  list(beta    = as.numeric(ct[1, "Estimate"]),
       se      = as.numeric(ct[1, "Std. Error"]),
       t       = as.numeric(ct[1, "t value"]),
       p       = as.numeric(ct[1, "Pr(>|t|)"]),
       n_cells = uniqueN(sub$cell_id))
}

# Build cell-key vectors for each cut
cell_keys_by_cut <- lapply(CUTS, function(flag) {
  if (is.null(flag)) cell_het[, paste(buyer, seller_nace4d, sep = "::")]
  else cell_het[get(flag) == TRUE,
                  paste(buyer, seller_nace4d, sep = "::")]
})

# ---------------------------------------------------------------------------
# Point-estimate DiD per cut
# ---------------------------------------------------------------------------
cat("\nRunning point-estimate DiDs (7 cuts)...\n")
pt_rows <- lapply(names(CUTS), function(cut) {
  est <- run_did(panel, cell_keys_by_cut[[cut]])
  data.table(cut     = cut,
              display = CUT_DISPLAY[[cut]],
              n_cells = est$n_cells,
              beta    = est$beta,
              se      = est$se,
              t       = est$t,
              p_unadj = est$p)
})
pt_dt <- rbindlist(pt_rows)
cat("\n--- Point estimates by cut ---\n")
print(pt_dt[, .(cut, n_cells,
                 beta = round(beta, 4), se = round(se, 4),
                 t = round(t, 3), p_unadj = round(p_unadj, 4))])

# ---------------------------------------------------------------------------
# Cluster-bootstrap on buyer for Romano-Wolf step-down adjusted p-values
# ---------------------------------------------------------------------------
cat(sprintf("\nCluster-bootstrap on buyer (B = %d, workers = %d)...\n",
            B, N_WORKERS))
buyers_all <- unique(panel$buyer)
n_buyers   <- length(buyers_all)

plan(multisession, workers = N_WORKERS)
boot_t <- future_sapply(seq_len(B), function(b) {
  set.seed(20260521L + b)
  draw <- sample(buyers_all, n_buyers, replace = TRUE)
  draw_tbl <- data.table(buyer = draw, draw_id = seq_along(draw))
  # Resample by buyer with replacement; assign new cell_id and cell_role_id
  # so duplicated buyers form independent clusters in the bootstrap sample.
  draw_panel <- merge(panel, draw_tbl, by = "buyer", allow.cartesian = TRUE)
  draw_panel[, cell_id      := paste(draw_id, seller_nace4d, sep = "::")]
  draw_panel[, cell_role_id := paste(cell_id, role, sep = "::")]
  # Map cell keys -- for each cut, find which (draw_id, seller_nace4d)
  # combinations were drawn and qualify under the cut.
  het_draw <- merge(cell_het[, .(buyer, seller_nace4d,
                                  in_cost_q, in_cost_d,
                                  in_share_q, in_share_d,
                                  in_gap_q, in_gap_d)],
                    draw_tbl, by = "buyer", allow.cartesian = TRUE)
  het_draw[, cell_id := paste(draw_id, seller_nace4d, sep = "::")]
  vapply(names(CUTS), function(cut) {
    flag <- CUTS[[cut]]
    keys <- if (is.null(flag)) het_draw$cell_id
            else het_draw[get(flag) == TRUE, cell_id]
    est <- run_did(draw_panel, keys)
    est$t
  }, numeric(1))
}, future.seed = TRUE)
plan(sequential)

# boot_t is a matrix: rows = cuts, cols = bootstrap replicates
if (is.vector(boot_t)) boot_t <- matrix(boot_t, nrow = length(CUTS))
rownames(boot_t) <- names(CUTS)
cat("  Bootstrap done. boot_t dims:", dim(boot_t), "\n")

# Two-sided studentized bootstrap p-value per cut (unadjusted)
abs_obs <- abs(pt_dt$t)
abs_boot <- abs(boot_t)
n_finite <- rowSums(is.finite(abs_boot))
p_boot_unadj <- vapply(seq_len(nrow(boot_t)), function(i) {
  good <- is.finite(abs_boot[i, ])
  if (sum(good) < 10L) return(NA_real_)
  mean(abs_boot[i, good] >= abs_obs[i])
}, numeric(1))

# Romano-Wolf step-down: order cuts by |t|-statistic descending, then for
# each step compute the supremum of the |t|-bootstrap statistics over the
# remaining (not yet rejected) cuts. p_rw is the bootstrap probability that
# the supremum exceeds the observed |t|.
ord <- order(-abs_obs)
p_rw <- numeric(length(abs_obs))
for (j in seq_along(ord)) {
  remaining <- ord[j:length(ord)]
  sup_boot <- apply(abs_boot[remaining, , drop = FALSE], 2L,
                    function(x) {
                      x <- x[is.finite(x)]
                      if (length(x) == 0L) NA_real_ else max(x)
                    })
  sup_boot <- sup_boot[is.finite(sup_boot)]
  if (length(sup_boot) == 0L) {
    p_rw[ord[j]] <- NA_real_
  } else {
    p_rw[ord[j]] <- mean(sup_boot >= abs_obs[ord[j]])
  }
}
# Enforce monotonicity in order of step
p_rw[ord] <- cummax(p_rw[ord])

# Bonferroni, Holm, BH for reference
p_bonf <- pmin(1, pt_dt$p_unadj * length(CUTS))
p_holm <- p.adjust(pt_dt$p_unadj, method = "holm")
p_bh   <- p.adjust(pt_dt$p_unadj, method = "BH")

pt_dt[, `:=`(p_boot_unadj = p_boot_unadj,
             p_bonf       = p_bonf,
             p_holm       = p_holm,
             p_bh         = p_bh,
             p_rw         = p_rw)]
cat("\n--- All p-values ---\n")
print(pt_dt[, .(cut, n_cells,
                 beta    = round(beta, 4),
                 t       = round(t, 3),
                 p_unadj = round(p_unadj, 4),
                 p_rw    = round(p_rw, 4),
                 p_bonf  = round(p_bonf, 4),
                 p_bh    = round(p_bh, 4))])
fwrite(pt_dt, file.path(OUTPUT_TAB,
       "phase4_within_intensive_did_mht_results.csv"))

# ---------------------------------------------------------------------------
# Paper-ready LaTeX table
# ---------------------------------------------------------------------------
star <- function(p) {
  if (is.na(p)) ""
  else if (p < 0.01) "***"
  else if (p < 0.05) "**"
  else if (p < 0.10) "*"
  else ""
}

tex_dt <- copy(pt_dt)
tex_dt[, est_str := sprintf("%.4f%s", beta, vapply(p_rw, star, character(1)))]
tex_dt[, se_str  := sprintf("(%.4f)", se)]
tex_dt[, ncell_str := format(n_cells, big.mark = ",")]
tex_dt <- tex_dt[, .(Cut = display,
                     Cells = ncell_str,
                     `$\\widehat{\\gamma}$` = est_str,
                     `SE`  = se_str,
                     `RW $p$` = sprintf("%.4f", p_rw))]
xt <- xtable(tex_dt,
             caption = paste("Within-NACE-4d intensive-margin DiD by",
                             "heterogeneity cut.  Each row reports the",
                             "post-2017 top vs bot share differential",
                             "$\\widehat{\\gamma}$ from a separate naive",
                             "DiD on the indicated subsample. Heterogeneity",
                             "variables: cost shock (= $\\omega_{top}$",
                             "$\\times$ (top supplier's pre-window sales to",
                             "buyer / buyer's pre-window total cost)",
                             "$\\times$ EUA at peak); input share (= NACE-4d",
                             "spend / buyer total cost); exposure gap (=",
                             "$\\omega_{top} - \\omega_{bot}$). Significance",
                             "stars use Romano-Wolf step-down adjusted",
                             "$p$-values (cluster-bootstrap on buyer,",
                             "$B = 500$). Clustered SEs at the cell level."),
             label   = "tab:phase4_within_intensive_did_mht_heterogeneity",
             align   = "lllllr")
print(xt,
      file = file.path(OUTPUT_TAB,
                       "phase4_within_intensive_did_mht_heterogeneity.tex"),
      include.rownames = FALSE, booktabs = TRUE,
      sanitize.colnames.function = identity,
      sanitize.text.function     = identity,
      caption.placement = "top")

cat("\nDone.\n  tables :", OUTPUT_TAB, "\n")
