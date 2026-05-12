###############################################################################
# phase5_test_g_feasibility_restricted.R
#
# Test G of Plan B (SHOCK_AND_SUBSTITUTION_PLAN.md): feasibility-restricted
# substitution test. The foundational Plan B test ("if substitution happens
# anywhere, it should happen here").
#
# CONSTRUCTION:
#   - Cell unit: (buyer × seller_nace4d × year). Each cell is the buyer's
#     spending on a particular input NACE 4d in that year.
#   - For each cell compute:
#       n_ets_sellers       = # active ETS sellers in cell
#       spread              = max - min of firm_cost_share_regressor among
#                             active ETS sellers in cell
#       max_pair_shock      = max_j (fcs_j × corr_sales_{j,b,t}
#                             / Σ_{j' in cell} corr_sales_{j',b,t})
#                             (NACE-4d-denominator pair-shock; option b)
#       max_pair_shock_total= max_j (fcs_j × corr_sales_{j,b,t}
#                             / inputs_VAT_{b,t})
#                             (total-input-denominator pair-shock; option c.
#                             Apples-to-apples with σ_share noise floor.)
#
#   High-power cell filter:
#     n_ets_sellers >= 2         (alternative ETS supplier exists)
#     spread >= θ_spread         (intensity gap across alternatives)
#     max_pair_shock_total >= θ_shock_total  (buyer materially exposed at TOTAL-cost level)
#
#   Default: θ_spread = 0.005, θ_shock_total = 0.005.
#
# REGRESSION SAMPLE:
#   All ACTIVE (corr_sales > 0) rows in cells that pass the filter, including
#   non-ETS sellers (firm_cost_share = 0). Active-only is the Phase 3
#   convention; extensive-margin behavior is a separate question.
#
# SPECIFICATION G1 (granular, headline):
#   share_{j,b,n,t} = β · firm_cost_share_j × Post_t + α_{j,b} + δ_{n,t} + ε
#   share          = corr_sales / Σ within (buyer × seller_nace4d × year)
#   firm_cost_share = time-invariant pre-shock regressor (Prep 2)
#   Post_t          = 1(t >= 2015)
#   FE              = pair (seller^buyer) + NACE 4d × year
#   Cluster         = seller, buyer (two-way; Phase 3 convention)
#
# SPECIFICATION G2 (aggregated cell-level, descriptive):
#   weighted_intensity_{b,n,t} = Σ_j (share_{j,b,n,t} × firm_cost_share_j)
#   weighted_intensity ~ Post_t | (b × n) + (n × t)
#
# OUTPUT:
#   output/tables/phase5_test_g_g1_threshold_grid.csv   -- G1 across grids
#   output/tables/phase5_test_g_g1_main.csv             -- G1 default thresholds
#   output/tables/phase5_test_g_g2_main.csv             -- G2 default thresholds
#   output/tables/phase5_test_g_filter_diagnostics.csv  -- cells passing each grid
#   output/figures/phase5_test_g_weighted_intensity_by_year.pdf
###############################################################################

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE))
  install.packages("fixest", repos = "https://cloud.r-project.org")
if (!requireNamespace("ggplot2", quietly = TRUE))
  install.packages("ggplot2", repos = "https://cloud.r-project.org")

library(data.table)
library(fixest)
library(ggplot2)

POST_FROM <- 2015L  # MSR-binding shock date (Phase 3 convention)

# ---------------------------------------------------------------------------
# 1. Load b2b panel + Prep 2 firm_cost_share + buyer's total inputs
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "b2b_cdgm_panel.RData"))                     # panel
load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))            # cost_share_outcome, cost_share_regressor

panel <- as.data.table(panel)
cost_share_regressor <- as.data.table(cost_share_regressor)

# Buyer's total declared inputs (from VAT returns) -- denominator for
# pair_shock_total. Same source as phase5_pair_shock_magnitude.R.
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
buyer_inputs <- as.data.table(df_annual_accounts_more_selected_sample)[
  !is.na(inputs_VAT) & inputs_VAT > 0,
  .(buyer = vat_ano, year, inputs_VAT_total = inputs_VAT)]
rm(df_annual_accounts_more_selected_sample)

# Drop contaminated VATs from 2021+ (consistent with Plan A scripts).
contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
n_drop <- panel[seller %in% contaminated_vats & year >= 2021L, .N]
panel <- panel[!(seller %in% contaminated_vats & year >= 2021L)]
cat(sprintf("Dropped %d B2B rows for contaminated sellers (year >= 2021).\n",
            n_drop))

# ---------------------------------------------------------------------------
# 2. Attach time-invariant firm_cost_share (regressor flavor); 0 for non-ETS
# ---------------------------------------------------------------------------
panel <- merge(panel,
               cost_share_regressor[, .(seller = vat,
                                        firm_cost_share = firm_cost_share_regressor)],
               by = "seller", all.x = TRUE)
panel[is.na(firm_cost_share), firm_cost_share := 0]

# Drop ETS sellers without a regressor value (they have ETS status but no clean
# pre-shock cost-share -- excluded for the same reason as Phase 3 continuous).
ets_with_fcs <- cost_share_regressor$vat
panel <- panel[!(seller_is_ets == 1L & !(seller %in% ets_with_fcs))]

cat(sprintf("Panel rows after firm_cost_share join: %d\n", nrow(panel)))

# ---------------------------------------------------------------------------
# 3. Restrict to ACTIVE pair-years and attach buyer's total inputs
# ---------------------------------------------------------------------------
active <- panel[corr_sales > 0]
active <- merge(active, buyer_inputs, by = c("buyer", "year"), all.x = TRUE)
cat(sprintf("Active pair-years: %d (with inputs_VAT defined: %d)\n",
            nrow(active), active[!is.na(inputs_VAT_total), .N]))

# ---------------------------------------------------------------------------
# 4. Compute cell-level filter ingredients
#    Cell = (buyer, seller_nace4d, year)
# ---------------------------------------------------------------------------
# pair-level shock measures (per active row).
active[, pair_shock_nace := firm_cost_share *
                            corr_sales / sum(corr_sales),
       by = .(buyer, seller_nace4d, year)]
active[!is.na(inputs_VAT_total),
       pair_shock_total := firm_cost_share * corr_sales / inputs_VAT_total]
active[is.na(pair_shock_total), pair_shock_total := NA_real_]

# Cell-level summary: only ETS sellers contribute to n_ets_sellers and spread.
safe_max <- function(x) {
  v <- x[!is.na(x)]
  if (length(v) == 0L) NA_real_ else max(v)
}
cell_stats <- active[, .(
  n_active_sellers      = .N,
  n_ets_sellers         = sum(seller_is_ets == 1L),
  ets_fcs_max           = if (any(seller_is_ets == 1L))
                            max(firm_cost_share[seller_is_ets == 1L]) else NA_real_,
  ets_fcs_min           = if (any(seller_is_ets == 1L))
                            min(firm_cost_share[seller_is_ets == 1L]) else NA_real_,
  max_pair_shock        = safe_max(pair_shock_nace),
  max_pair_shock_total  = safe_max(pair_shock_total),
  has_inputs_VAT        = any(!is.na(inputs_VAT_total))
), by = .(buyer, seller_nace4d, year)]
cell_stats[, spread := ifelse(is.na(ets_fcs_max) | is.na(ets_fcs_min),
                              0, ets_fcs_max - ets_fcs_min)]

cat(sprintf("Total cells (buyer x seller_nace4d x year): %d\n", nrow(cell_stats)))
cat(sprintf("Cells with >= 2 ETS sellers:            %d\n",
            cell_stats[n_ets_sellers >= 2L, .N]))
cat(sprintf("Cells with inputs_VAT defined:          %d\n",
            cell_stats[has_inputs_VAT == TRUE, .N]))

# ---------------------------------------------------------------------------
# 5. Threshold-grid filter diagnostics
# ---------------------------------------------------------------------------
spread_grid <- c(0.001, 0.005, 0.01, 0.02)
shock_grid  <- c(0.001, 0.005, 0.01, 0.02)

filter_diag <- CJ(theta_spread = spread_grid, theta_shock_total = shock_grid)
filter_diag[, n_cells := mapply(function(s, t) {
    cell_stats[n_ets_sellers >= 2L &
                 spread >= s &
                 !is.na(max_pair_shock_total) &
                 max_pair_shock_total >= t, .N]
  }, theta_spread, theta_shock_total)]

cat("\nFilter-grid diagnostics (cells passing):\n")
print(dcast(filter_diag, theta_spread ~ theta_shock_total, value.var = "n_cells"))

fwrite(filter_diag, file.path(OUTPUT_TAB, "phase5_test_g_filter_diagnostics.csv"))

# ---------------------------------------------------------------------------
# 6. G1 + G2 regressions per (theta_spread, theta_shock_total) on the grid
# ---------------------------------------------------------------------------
cat("\n=== G1 + G2 regressions across threshold grid ===\n")

active[, post := as.integer(year >= POST_FROM)]
active[, treat_post := firm_cost_share * post]
active[, sn4d_year := paste(seller_nace4d, year, sep = "_")]
active[, seller_buyer := paste(seller, buyer, sep = "_")]
active[, buyer_n4d := paste(buyer, seller_nace4d, sep = "_")]

run_g1 <- function(d) {
  if (nrow(d) < 50L || uniqueN(d$year) < 2L) return(NULL)
  if (uniqueN(d[firm_cost_share > 0]$firm_cost_share) < 2L) return(NULL)
  fm <- as.formula("share ~ treat_post | seller_buyer + sn4d_year")
  tryCatch(
    feols(fm, data = d, cluster = ~ seller + buyer),
    error = function(e) NULL
  )
}
run_g2 <- function(d_cell) {
  if (nrow(d_cell) < 50L || uniqueN(d_cell$year) < 2L) return(NULL)
  fm <- as.formula("weighted_intensity ~ post | buyer_n4d + sn4d_year")
  tryCatch(
    feols(fm, data = d_cell, cluster = ~ buyer + seller_nace4d),
    error = function(e) NULL
  )
}

extract_coef <- function(model, var) {
  if (is.null(model)) return(data.table(estimate = NA_real_, se = NA_real_,
                                        tval = NA_real_, pval = NA_real_,
                                        n = NA_integer_))
  ct <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(ct, c("term", "estimate", "se", "tval", "pval"))
  row <- ct[term == var]
  if (nrow(row) == 0L) return(data.table(estimate = NA_real_, se = NA_real_,
                                         tval = NA_real_, pval = NA_real_,
                                         n = NA_integer_))
  cbind(row[, .(estimate, se, tval, pval)], n = nobs(model))
}

g1_grid <- vector("list", nrow(filter_diag))
g2_grid <- vector("list", nrow(filter_diag))

for (i in seq_len(nrow(filter_diag))) {
  ts <- filter_diag$theta_spread[i]
  tt <- filter_diag$theta_shock_total[i]
  passing_cells <- cell_stats[n_ets_sellers >= 2L &
                                spread >= ts &
                                !is.na(max_pair_shock_total) &
                                max_pair_shock_total >= tt,
                              .(buyer, seller_nace4d, year)]
  if (nrow(passing_cells) == 0L) next

  # G1 sample: all active rows in passing cells.
  d_reg <- merge(active, passing_cells,
                 by = c("buyer", "seller_nace4d", "year"), all = FALSE)
  d_reg[, share := corr_sales / sum(corr_sales),
        by = .(buyer, seller_nace4d, year)]

  # G2 sample: cell-level weighted intensity.
  d_cell <- d_reg[, .(weighted_intensity = sum(share * firm_cost_share),
                      post = max(post)),
                  by = .(buyer, seller_nace4d, year)]
  d_cell[, sn4d_year := paste(seller_nace4d, year, sep = "_")]
  d_cell[, buyer_n4d := paste(buyer, seller_nace4d, sep = "_")]

  m1 <- run_g1(d_reg)
  m2 <- run_g2(d_cell)

  g1_grid[[i]] <- cbind(theta_spread = ts, theta_shock_total = tt,
                        n_cells = nrow(passing_cells),
                        n_obs   = nrow(d_reg),
                        extract_coef(m1, "treat_post"))
  g2_grid[[i]] <- cbind(theta_spread = ts, theta_shock_total = tt,
                        n_cells = nrow(d_cell),
                        n_obs   = nrow(d_cell),
                        extract_coef(m2, "post"))
}

g1_grid <- rbindlist(g1_grid, fill = TRUE)
g2_grid <- rbindlist(g2_grid, fill = TRUE)

cat("\nG1 (share ~ firm_cost_share x post; pair FE + nace4d x year FE):\n")
print(g1_grid)
cat("\nG2 (weighted_intensity ~ post; cell FE + nace4d x year FE):\n")
print(g2_grid)

fwrite(g1_grid, file.path(OUTPUT_TAB, "phase5_test_g_g1_threshold_grid.csv"))
fwrite(g2_grid, file.path(OUTPUT_TAB, "phase5_test_g_g2_threshold_grid.csv"))

# ---------------------------------------------------------------------------
# 7. Default-threshold tables and sector decomposition
# ---------------------------------------------------------------------------
THETA_SPREAD <- 0.005
THETA_SHOCK  <- 0.005

passing_default <- cell_stats[n_ets_sellers >= 2L &
                                 spread >= THETA_SPREAD &
                                 !is.na(max_pair_shock_total) &
                                 max_pair_shock_total >= THETA_SHOCK,
                               .(buyer, seller_nace4d, year)]
cat(sprintf("\nDefault filter (spread >= %.3f, shock_total >= %.3f): %d cells\n",
            THETA_SPREAD, THETA_SHOCK, nrow(passing_default)))

if (nrow(passing_default) > 0L) {
  d_main <- merge(active, passing_default,
                  by = c("buyer", "seller_nace4d", "year"), all = FALSE)
  d_main[, share := corr_sales / sum(corr_sales),
         by = .(buyer, seller_nace4d, year)]
  d_main[, sn4d_year := paste(seller_nace4d, year, sep = "_")]
  d_main[, seller_buyer := paste(seller, buyer, sep = "_")]
  d_main[, buyer_n4d := paste(buyer, seller_nace4d, sep = "_")]

  d_cell_main <- d_main[, .(weighted_intensity = sum(share * firm_cost_share),
                            post = max(post)),
                        by = .(buyer, seller_nace4d, year, buyer_nace2d)]
  d_cell_main[, sn4d_year := paste(seller_nace4d, year, sep = "_")]
  d_cell_main[, buyer_n4d := paste(buyer, seller_nace4d, sep = "_")]

  m_g1 <- run_g1(d_main)
  m_g2 <- run_g2(d_cell_main)

  cat("\n--- G1 main (default thresholds) ---\n")
  if (!is.null(m_g1)) print(summary(m_g1))
  cat("\n--- G2 main (default thresholds) ---\n")
  if (!is.null(m_g2)) print(summary(m_g2))

  # Sector decomposition (split by buyer NACE 2d).
  sector_results <- d_main[, {
    n_y <- uniqueN(year)
    n_var <- uniqueN(firm_cost_share[firm_cost_share > 0])
    if (.N >= 50L && n_y >= 2L && n_var >= 1L) {
      m <- tryCatch(feols(share ~ treat_post |
                            seller_buyer + sn4d_year,
                          data = .SD, cluster = ~ seller + buyer),
                    error = function(e) NULL)
      if (!is.null(m)) {
        ec <- extract_coef(m, "treat_post")
        list(n_obs = nobs(m),
             estimate = ec$estimate, se = ec$se,
             tval = ec$tval, pval = ec$pval)
      } else {
        list(n_obs = .N, estimate = NA_real_, se = NA_real_,
             tval = NA_real_, pval = NA_real_)
      }
    } else {
      list(n_obs = .N, estimate = NA_real_, se = NA_real_,
           tval = NA_real_, pval = NA_real_)
    }
  }, by = buyer_nace2d]
  setorder(sector_results, -n_obs)
  cat("\n--- G1 by buyer NACE 2d (default thresholds) ---\n")
  print(sector_results)

  fwrite(sector_results,
         file.path(OUTPUT_TAB, "phase5_test_g_g1_by_buyer_nace2d.csv"))

  # Save main coefficients.
  fwrite(extract_coef(m_g1, "treat_post"),
         file.path(OUTPUT_TAB, "phase5_test_g_g1_main.csv"))
  fwrite(extract_coef(m_g2, "post"),
         file.path(OUTPUT_TAB, "phase5_test_g_g2_main.csv"))

  # ---------------------------------------------------------------------------
  # 8. G2 over time -- weighted_intensity_{b,n,t} averaged by buyer NACE 2d
  # ---------------------------------------------------------------------------
  ts_plot <- d_cell_main[, .(
    mean_intensity = mean(weighted_intensity, na.rm = TRUE),
    n_cells        = .N
  ), by = .(year, buyer_nace2d)]

  p <- ggplot(ts_plot[n_cells >= 5],
              aes(x = year, y = mean_intensity, colour = buyer_nace2d)) +
    geom_line(linewidth = 0.6) +
    geom_point(size = 1.2) +
    geom_vline(xintercept = POST_FROM - 0.5, linetype = "dashed",
               colour = "grey40") +
    scale_y_continuous(labels = scales::percent_format(accuracy = 0.01)) +
    labs(title = "Test G: cell-level weighted carbon intensity over time",
         subtitle = sprintf("Default high-power filter: spread>=%.3f, shock_total>=%.3f. Each line = mean over (buyer, NACE 4d) cells in that buyer NACE 2d.",
                            THETA_SPREAD, THETA_SHOCK),
         x = NULL, y = "weighted_intensity_{b,n,t}",
         colour = "Buyer NACE 2d") +
    theme_minimal(base_size = 11)

  ggsave(file.path(OUTPUT_FIG, "phase5_test_g_weighted_intensity_by_year.pdf"),
         p, width = 9, height = 5)
  cat(sprintf("\nSaved: %s\n",
              file.path(OUTPUT_FIG, "phase5_test_g_weighted_intensity_by_year.pdf")))

} else {
  cat("\nNo cells survive default filter -- skipping main regression and plot.\n")
}

cat("\nTest G complete.\n")
