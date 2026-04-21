###############################################################################
# network_exposure_regs_1_build_frozen_weights.R
#
# PURPOSE:
#   Build the frozen base-period A matrix (upstream) and B matrix (downstream)
#   as averages over 2005-2012, plus base-period average costs per firm.
#
# SPECIFICATION:
#   A_base[i,j] = (sum of flows i->j across 2005-2012) / (sum of costs_i across 2005-2012)
#   B_base[j,i] = (sum of flows i->j across 2005-2012) / (sum of sales_j across 2005-2012)
#   avg_costs_i = mean over base years (in which firm i has positive cost data)
#     where costs_i = inputs_i + wage_bill_i + emissions_cost_i
#
# DATA:
#   - NBB_data/processed/b2b_selected_sample.RData
#   - NBB_data/processed/firm_year_belgian_euets.RData
#   - NBB_data/processed/annual_accounts_selected_sample_key_variables.RData
#
# OUTPUT:
#   - data/processed/frozen_weights_matrices.RData
#     (A_base, B_base, firms_base, avg_costs)
###############################################################################

rm(list = ls())

library(dplyr)
library(Matrix)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- EUA prices (annual average, EUR/tCO2) ----
eua_prices <- data.frame(
  year = 2005:2021,
  eua_price = c(22, 18, 0.7, 22, 13, 14, 13, 7.5,
                4.5, 6, 7.5, 5, 5.8, 16, 25, 25, 53)
)

# ---- Load data ----
cat("Loading data...\n")
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))

colnames(df_b2b_selected_sample) <- c("vat_supplier", "vat_buyer",
                                       "year", "corr_sales")

# ===========================================================================
# Build frozen A matrix (average over 2005-2012)
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

# Normalize: A[i,j] = (sum of flows i->j across base years) / (sum of costs_i across base years)
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

# ---- Save ----
save(A_base, B_base, firms_base, avg_costs,
     file = file.path(OUT_DATA, "frozen_weights_matrices.RData"))
cat("\nMatrices saved to:", file.path(OUT_DATA, "frozen_weights_matrices.RData"), "\n")
cat("Done.\n")
