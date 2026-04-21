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

cost_sum    <- rep(0, n_firms_base)
cost_count  <- rep(0, n_firms_base)
revenue_sum <- rep(0, n_firms_base)  # used as denominator for B_base (downstream)

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

  # Pull wages + revenue from annual accounts (one pass)
  aa_y <- df_annual_accounts_selected_sample_key_variables %>%
    filter(year == y) %>%
    select(vat, wage_bill, revenue)

  ordered_wages   <- rep(0, n_firms_base)
  ordered_revenue <- rep(0, n_firms_base)
  am <- match(aa_y$vat, firms_base)
  valid_a <- !is.na(am)
  ordered_wages[am[valid_a]]   <- aa_y$wage_bill[valid_a]
  ordered_revenue[am[valid_a]] <- aa_y$revenue[valid_a]

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
  cost_sum    <- cost_sum + year_costs
  cost_count  <- cost_count + as.numeric(year_costs > 0)
  revenue_sum <- revenue_sum + ordered_revenue
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

# Vectorized row-scaling: cap any row with rowsum >= 1 to 0.99.
# Only bites on data-inconsistency edges (e.g. inputs > total cost, or B2B sales > revenue).
cap_rows <- function(M, cap = 0.99) {
  rs <- rowSums(M)
  bad <- !is.na(rs) & rs >= 1
  if (!any(bad)) return(list(M = M, max = max(rs, na.rm = TRUE), n_capped = 0L))
  scale <- rep(1, nrow(M))
  scale[bad] <- cap / rs[bad]
  M@x <- M@x * scale[M@i + 1]
  list(M = M, max = max(rowSums(M), na.rm = TRUE), n_capped = sum(bad))
}

cat(sprintf("  Max row sum of A_base (pre-cap): %.6f\n", max(rowSums(A_base), na.rm = TRUE)))
a_cap <- cap_rows(A_base)
A_base <- a_cap$M
if (a_cap$n_capped > 0) cat(sprintf("  Capped %d rows of A_base\n", a_cap$n_capped))
cat(sprintf("  Final max row sum of A_base: %.6f\n", a_cap$max))

# Build B_base (downstream: B[supplier, buyer] = sales / total_revenue_supplier)
# Denominator is the supplier's TOTAL revenue (from annual accounts), not just its
# B2B sales -- otherwise every row's sum would be exactly 1 by construction.
sales_sum <- t(exp_sum)  # rows = suppliers, cols = buyers

B_base <- sales_sum
row_rev <- revenue_sum[B_base@i + 1]
valid_s <- !is.na(row_rev) & row_rev > 0
B_base@x[valid_s] <- B_base@x[valid_s] / row_rev[valid_s]
B_base@x[!valid_s] <- 0

cat(sprintf("  Max row sum of B_base (pre-cap): %.6f\n", max(rowSums(B_base), na.rm = TRUE)))
b_cap <- cap_rows(B_base)
B_base <- b_cap$M
if (b_cap$n_capped > 0) cat(sprintf("  Capped %d rows of B_base (sales > revenue in data)\n",
                                     b_cap$n_capped))
cat(sprintf("  Final max row sum of B_base: %.6f\n", b_cap$max))

# ---- Save ----
save(A_base, B_base, firms_base, avg_costs,
     file = file.path(OUT_DATA, "frozen_weights_matrices.RData"))
cat("\nMatrices saved to:", file.path(OUT_DATA, "frozen_weights_matrices.RData"), "\n")
cat("Done.\n")
