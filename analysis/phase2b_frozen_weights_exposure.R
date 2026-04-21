###############################################################################
# phase2b_frozen_weights_exposure.R
#
# PURPOSE:
#   Build firm-year network exposure using FROZEN base-period network weights
#   (average A matrix over 2005-2012) combined with time-varying direct
#   exposure (shortage × price, 2012-2021).
#
#   This eliminates mechanical correlation between contemporaneous output
#   and network exposure: the only time-variation comes from (a) exogenous
#   carbon price changes and (b) changes in suppliers' allowance shortage.
#
# SPECIFICATION:
#   exposure_it = (I - A_base)^{-1} × e_t
#   where A_base = average A matrix over 2005-2012
#         e_jt = max(emissions_jt - free_allowances_jt, 0) × price_t / costs_j_base
#
# DATA:
#   - NBB_data/processed/b2b_selected_sample.RData
#   - NBB_data/processed/firm_year_belgian_euets.RData
#   - NBB_data/processed/annual_accounts_selected_sample_key_variables.RData
#   - NBB_data/processed/deflator_nace4d_2005base.RData
#   - NBB_data/processed/training_sample.RData
#   - NBB_data/processed/deployment_panel.RData
#
# OUTPUT:
#   - data/processed/frozen_weights_exposure_panel.RData
###############################################################################

rm(list = ls())

library(dplyr)
library(stringr)
library(Matrix)

# ---- Paths ----
if (Sys.info()[["user"]] == "JARDANG") {
  # RMD
  nbb_data     <- "X:/Documents/JARDANG/NBB_data"
  project_root <- "X:/Documents/JARDANG/carbon_policy_networks"
} else {
  # Local 1
  nbb_data     <- "c:/Users/jota_/Documents/NBB_data"
  project_root <- "c:/Users/jota_/Documents/carbon_policy_networks"
}
proc_data    <- file.path(nbb_data, "processed")
out_data     <- file.path(project_root, "data", "processed")

dir.create(out_data, recursive = TRUE, showWarnings = FALSE)

# ---- EUA prices (annual average, EUR/tCO2) ----
eua_prices <- data.frame(
  year = 2005:2021,
  eua_price = c(22, 18, 0.7, 22, 13, 14, 13, 7.5,
                4.5, 6, 7.5, 5, 5.8, 16, 25, 25, 53)
)

# ---- Load data ----
cat("Loading data...\n")
load(file.path(proc_data, "b2b_selected_sample.RData"))
load(file.path(proc_data, "firm_year_belgian_euets.RData"))
load(file.path(proc_data, "annual_accounts_selected_sample_key_variables.RData"))
load(file.path(proc_data, "deflator_nace4d_2005base.RData"))
load(file.path(proc_data, "training_sample.RData"))
load(file.path(proc_data, "deployment_panel.RData"))

colnames(df_b2b_selected_sample) <- c("vat_supplier", "vat_buyer",
                                       "year", "corr_sales")

# ---- Neumann series ----
neumann_series <- function(A, v, max_iter = 50, tol = 1e-8) {
  result <- v
  current_power <- as.numeric(A %*% v)
  for (k in seq_len(max_iter)) {
    result <- result + current_power
    current_power <- as.numeric(A %*% current_power)
    rel_err <- max(abs(current_power)) / (max(abs(result)) + 1e-15)
    if (rel_err < tol) {
      return(list(result = result, k = k, rel_err = rel_err, converged = TRUE))
    }
  }
  list(result = result, k = max_iter, rel_err = rel_err, converged = (rel_err < tol))
}

# ===========================================================================
# STEP 1: Build frozen A matrix (average over 2005-2012)
# ===========================================================================
cat("Building base-period A matrix (average 2005-2012)...\n")

base_years <- 2005:2012

# Get the universe of firms that appear in B2B during the base period
b2b_base <- df_b2b_selected_sample %>%
  filter(year %in% base_years, corr_sales > 0)

firms_base <- sort(unique(c(b2b_base$vat_supplier, b2b_base$vat_buyer)))
n_firms_base <- length(firms_base)
firm_idx_base <- setNames(seq_along(firms_base), firms_base)

cat(sprintf("  Base-period firm universe: %d firms\n", n_firms_base))

# Average expenditure matrix over base years
# Sum all flows then divide by number of years the pair is observed
# (equivalent to averaging the A matrices if costs are also averaged)
exp_sum <- sparseMatrix(i = 1, j = 1, x = 0,
                        dims = c(n_firms_base, n_firms_base))

cost_sum <- rep(0, n_firms_base)
cost_count <- rep(0, n_firms_base)

for (y in base_years) {
  cat(sprintf("  Processing %d...\n", y))

  b2b_y <- b2b_base %>% filter(year == y)

  idx_buyer <- firm_idx_base[b2b_y$vat_buyer]
  idx_supplier <- firm_idx_base[b2b_y$vat_supplier]

  # Some firms might not be in base universe (shouldn't happen but be safe)
  valid <- !is.na(idx_buyer) & !is.na(idx_supplier)

  exp_y <- sparseMatrix(
    i = idx_buyer[valid],
    j = idx_supplier[valid],
    x = b2b_y$corr_sales[valid],
    dims = c(n_firms_base, n_firms_base)
  )

  exp_sum <- exp_sum + exp_y

  # Costs: wage_bill + row sums of expenditure + emissions costs
  wages_y <- df_annual_accounts_selected_sample_key_variables %>%
    filter(year == y) %>%
    select(vat, wage_bill)

  ordered_wages <- rep(0, n_firms_base)
  wm <- match(wages_y$vat, firms_base)
  valid_w <- !is.na(wm)
  ordered_wages[wm[valid_w]] <- wages_y$wage_bill[valid_w]

  ordered_inputs <- as.numeric(rowSums(exp_y))

  ets_y <- firm_year_belgian_euets %>%
    filter(year == y, in_sample == 1) %>%
    select(vat, emissions)
  eua_p <- eua_prices$eua_price[eua_prices$year == y]

  ordered_emcost <- rep(0, n_firms_base)
  em <- match(ets_y$vat, firms_base)
  valid_e <- !is.na(em)
  if (any(valid_e)) {
    ordered_emcost[em[valid_e]] <- ets_y$emissions[valid_e] * eua_p
  }

  year_costs <- ordered_inputs + ordered_wages + ordered_emcost
  cost_sum <- cost_sum + year_costs
  cost_count <- cost_count + as.numeric(year_costs > 0)
}

# Average costs over years with positive data
avg_costs <- ifelse(cost_count > 0, cost_sum / cost_count, NA_real_)

# Build average A matrix: average expenditure / average costs
A_base <- exp_sum
n_base_years <- length(base_years)

# Normalize: A[i,j] = (sum of flows i→j across base years) / (sum of costs_i across base years)
# This is equivalent to a weighted average of annual A matrices
row_costs_total <- cost_sum[A_base@i + 1]
valid_entries <- !is.na(row_costs_total) & row_costs_total > 0
A_base@x[valid_entries] <- A_base@x[valid_entries] / row_costs_total[valid_entries]
A_base@x[!valid_entries] <- 0

# Check and cap row sums
row_sums_A <- rowSums(A_base)
max_rowsum <- max(row_sums_A, na.rm = TRUE)
cat(sprintf("  Max row sum of A_base: %.6f\n", max_rowsum))

if (max_rowsum >= 1) {
  bad_rows <- which(row_sums_A >= 1)
  cat(sprintf("  Capping %d rows with rowsum >= 1\n", length(bad_rows)))
  for (r in bad_rows) {
    row_start <- A_base@p[r] + 1
    row_end <- A_base@p[r + 1]
    if (row_end >= row_start) {
      A_base@x[row_start:row_end] <- A_base@x[row_start:row_end] * 0.99 / row_sums_A[r]
    }
  }
}

cat(sprintf("  Final max row sum: %.6f\n", max(rowSums(A_base))))

# Also build B_base (downstream: sales matrix)
sales_sum <- t(exp_sum)  # rows = suppliers, cols = buyers
total_sales_base <- as.numeric(rowSums(sales_sum))
total_sales_base[total_sales_base <= 0] <- NA_real_

B_base <- sales_sum
row_sales <- total_sales_base[B_base@i + 1]
valid_s <- !is.na(row_sales) & row_sales > 0
B_base@x[valid_s] <- B_base@x[valid_s] / row_sales[valid_s]
B_base@x[!valid_s] <- 0

row_sums_B <- rowSums(B_base)
max_rowsum_B <- max(row_sums_B, na.rm = TRUE)
cat(sprintf("  Max row sum of B_base: %.6f\n", max_rowsum_B))

if (max_rowsum_B >= 1) {
  bad_rows_B <- which(row_sums_B >= 1)
  cat(sprintf("  Capping %d rows with rowsum >= 1\n", length(bad_rows_B)))
  for (r in bad_rows_B) {
    row_start <- B_base@p[r] + 1
    row_end <- B_base@p[r + 1]
    if (row_end >= row_start) {
      B_base@x[row_start:row_end] <- B_base@x[row_start:row_end] * 0.99 / row_sums_B[r]
    }
  }
}

cat(sprintf("  Final max row sum B: %.6f\n", max(rowSums(B_base))))

# ===========================================================================
# STEP 2: For each year 2012-2021, compute exposure using frozen A_base
# ===========================================================================
cat("\nComputing frozen-weight exposure for 2012-2021...\n")

analysis_years <- 2012:2021
exposure_list <- list()
convergence_log <- list()

for (y in analysis_years) {
  cat(sprintf("  Year %d...", y))

  eua_price_y <- eua_prices$eua_price[eua_prices$year == y]

  # Direct exposure vector: shortage × price, for ETS firms in base universe
  ets_y <- firm_year_belgian_euets %>%
    filter(year == y, in_sample == 1) %>%
    select(vat, emissions, allocated_free)

  direct_exposure_abs <- rep(0, n_firms_base)
  em <- match(ets_y$vat, firms_base)
  valid_e <- !is.na(em)
  if (any(valid_e)) {
    shortage <- pmax(ets_y$emissions[valid_e] - ets_y$allocated_free[valid_e], 0)
    direct_exposure_abs[em[valid_e]] <- shortage * eua_price_y
  }

  # Normalize by base-period average costs
  direct_exposure_intensity <- rep(0, n_firms_base)
  has_costs <- !is.na(avg_costs) & avg_costs > 0
  direct_exposure_intensity[has_costs] <-
    direct_exposure_abs[has_costs] / avg_costs[has_costs]

  # Upstream: (I - A_base)^{-1} × e_t
  upstream_res <- neumann_series(A_base, direct_exposure_intensity)

  # Downstream: (I - B_base)^{-1} × e_t
  downstream_res <- neumann_series(B_base, direct_exposure_intensity)

  convergence_log[[as.character(y)]] <- data.frame(
    year = y,
    upstream_k = upstream_res$k,
    upstream_rel_err = upstream_res$rel_err,
    upstream_converged = upstream_res$converged,
    downstream_k = downstream_res$k,
    downstream_rel_err = downstream_res$rel_err,
    downstream_converged = downstream_res$converged
  )

  year_df <- data.frame(
    vat = firms_base,
    year = y,
    direct_exposure = direct_exposure_abs,
    direct_exposure_intensity = direct_exposure_intensity,
    upstream_exposure = upstream_res$result,
    downstream_exposure = downstream_res$result,
    stringsAsFactors = FALSE
  )

  year_df$upstream_indirect <- year_df$upstream_exposure -
    year_df$direct_exposure_intensity
  year_df$downstream_indirect <- year_df$downstream_exposure -
    year_df$direct_exposure_intensity

  exposure_list[[as.character(y)]] <- year_df

  cat(sprintf(" done. upstream k=%d (err=%.2e), downstream k=%d (err=%.2e)\n",
              upstream_res$k, upstream_res$rel_err,
              downstream_res$k, downstream_res$rel_err))
}

# ===========================================================================
# STEP 3: Combine into panel and merge firm characteristics
# ===========================================================================
cat("\nAssembling panel...\n")

frozen_exposure_panel <- bind_rows(exposure_list)

# Merge firm characteristics
ets_firms <- firm_year_belgian_euets %>%
  filter(in_sample == 1) %>%
  select(vat, year, nace5d, revenue) %>%
  mutate(is_ets = 1L)

nonets_firms <- deployment_panel %>%
  select(vat, year, nace5d, revenue) %>%
  mutate(is_ets = 0L)

all_firms_panel <- bind_rows(ets_firms, nonets_firms) %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(year >= 2012, year <= 2021,
         !is.na(nace4d), !is.na(revenue), revenue > 0)

frozen_exposure_panel <- frozen_exposure_panel %>%
  left_join(all_firms_panel %>% select(vat, year, nace5d, nace2d, nace4d,
                                        revenue, is_ets),
            by = c("vat", "year"))

# Deflate revenue
frozen_exposure_panel <- frozen_exposure_panel %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = ifelse(is.na(ppi), ppi_2d, ppi)) %>%
  select(-ppi_2d) %>%
  mutate(real_revenue = revenue / ppi * 100)

# ---- Save panel (before regressions, in case fixest not installed) ----
save(frozen_exposure_panel, convergence_df, A_base, B_base,
     firms_base, avg_costs,
     file = file.path(out_data, "frozen_weights_exposure_panel.RData"))
cat("\nPanel saved to:", file.path(out_data, "frozen_weights_exposure_panel.RData"), "\n")

# ===========================================================================
# STEP 4: Regressions (requires fixest)
# ===========================================================================
if (!requireNamespace("fixest", quietly = TRUE)) {
  cat("\nWARNING: fixest not installed — skipping regressions.\n")
  cat("Install with: install.packages('fixest')\n")
  cat("Then re-run this script, or run regressions separately.\n")
  cat("Done (panel saved, regressions skipped).\n")
  q(save = "no")
}

cat("\n=== REGRESSIONS (frozen base-period weights) ===\n")

library(fixest)

df <- frozen_exposure_panel %>%
  filter(!is.na(nace4d), !is.na(real_revenue), real_revenue > 0,
         !is.na(upstream_exposure)) %>%
  mutate(log_real_rev = log(real_revenue))

# Within-NACE4d output share
df <- df %>%
  group_by(nace4d, year) %>%
  mutate(
    sector_output = sum(real_revenue, na.rm = TRUE),
    theta_it = real_revenue / sector_output,
    n_in_sector = n()
  ) %>%
  ungroup() %>%
  filter(n_in_sector >= 3)

# Standardize
df <- df %>%
  mutate(
    upstream_std = (upstream_exposure - mean(upstream_exposure, na.rm = TRUE)) /
      sd(upstream_exposure, na.rm = TRUE),
    downstream_std = (downstream_exposure - mean(downstream_exposure, na.rm = TRUE)) /
      sd(downstream_exposure, na.rm = TRUE),
    upstream_indirect_std = (upstream_indirect - mean(upstream_indirect, na.rm = TRUE)) /
      sd(upstream_indirect, na.rm = TRUE),
    downstream_indirect_std = (downstream_indirect - mean(downstream_indirect, na.rm = TRUE)) /
      sd(downstream_indirect, na.rm = TRUE)
  )

cat(sprintf("\nRegression sample: %d firm-years, %d firms, years %d-%d\n",
            nrow(df), n_distinct(df$vat),
            min(df$year), max(df$year)))
cat(sprintf("  ETS: %d firm-years, Non-ETS: %d firm-years\n",
            sum(df$is_ets == 1, na.rm = TRUE),
            sum(df$is_ets == 0 | is.na(df$is_ets))))

# --- Firm FE specs (the clean causal ones) ---
cat("\n--- Firm FE + nace4d×year FE (frozen weights) ---\n")
cat("  Identification: within-firm changes driven by time-varying carbon\n")
cat("  price × suppliers' shortage, with predetermined network position.\n\n")

reg1 <- feols(log_real_rev ~ upstream_std | nace4d^year + vat, data = df,
              cluster = ~vat)
cat("[1] log(rev) ~ upstream, firm FE:\n")
print(summary(reg1))

reg2 <- feols(theta_it ~ upstream_std | nace4d^year + vat, data = df,
              cluster = ~vat)
cat("\n[2] theta ~ upstream, firm FE:\n")
print(summary(reg2))

reg3 <- feols(log_real_rev ~ downstream_std | nace4d^year + vat, data = df,
              cluster = ~vat)
cat("\n[3] log(rev) ~ downstream, firm FE:\n")
print(summary(reg3))

reg4 <- feols(theta_it ~ downstream_std | nace4d^year + vat, data = df,
              cluster = ~vat)
cat("\n[4] theta ~ downstream, firm FE:\n")
print(summary(reg4))

reg5 <- feols(log_real_rev ~ upstream_std + downstream_std | nace4d^year + vat,
              data = df, cluster = ~vat)
cat("\n[5] log(rev) ~ upstream + downstream, firm FE:\n")
print(summary(reg5))

reg6 <- feols(theta_it ~ upstream_std + downstream_std | nace4d^year + vat,
              data = df, cluster = ~vat)
cat("\n[6] theta ~ upstream + downstream, firm FE:\n")
print(summary(reg6))

# --- Non-ETS only ---
cat("\n--- Non-ETS firms only (pure indirect channel) ---\n")
df_nonets <- df %>% filter(is_ets == 0 | is.na(is_ets))

df_nonets <- df_nonets %>%
  mutate(
    upstream_indirect_std_ne = (upstream_indirect - mean(upstream_indirect, na.rm = TRUE)) /
      sd(upstream_indirect, na.rm = TRUE)
  )

cat(sprintf("  Non-ETS sample: %d firm-years, %d firms\n",
            nrow(df_nonets), n_distinct(df_nonets$vat)))

reg7 <- feols(log_real_rev ~ upstream_indirect_std_ne | nace4d^year + vat,
              data = df_nonets, cluster = ~vat)
cat("\n[7] Non-ETS, log(rev) ~ upstream indirect, firm FE:\n")
print(summary(reg7))

reg8 <- feols(theta_it ~ upstream_indirect_std_ne | nace4d^year + vat,
              data = df_nonets, cluster = ~vat)
cat("\n[8] Non-ETS, theta ~ upstream indirect, firm FE:\n")
print(summary(reg8))

# --- Summary ---
cat("\n\n========================================\n")
cat("COEFFICIENT SUMMARY (frozen weights, firm FE)\n")
cat("========================================\n")
cat("\nSpec | Dep Var | Sample | Regressor | Coef | SE | t-stat | N\n")
cat(paste(rep("-", 80), collapse = ""), "\n")

print_coef <- function(label, reg) {
  ct <- coeftable(reg)
  cat(sprintf("%s | %.5f | %.5f | %.2f | %d\n",
              label, ct[1, 1], ct[1, 2], ct[1, 3], reg$nobs))
}

print_coef("[1] log(rev) | All     | upstream", reg1)
print_coef("[2] theta   | All     | upstream", reg2)
print_coef("[3] log(rev) | All     | downstream", reg3)
print_coef("[4] theta   | All     | downstream", reg4)
print_coef("[7] log(rev) | Non-ETS | upstream_indirect", reg7)
print_coef("[8] theta   | Non-ETS | upstream_indirect", reg8)

# ===========================================================================
# STEP 5: Convergence summary
# ===========================================================================
convergence_df <- bind_rows(convergence_log)
cat("\n\n=== Convergence (frozen A_base) ===\n")
print(convergence_df)

cat("\nDone.\n")
