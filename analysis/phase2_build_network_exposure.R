###############################################################################
# phase2_build_network_exposure.R
#
# PURPOSE:
#   Build firm-year network-adjusted exposure to ETS treatment using the
#   Leontief inverse. Direct exposure = max(emissions - free_allowances, 0) *
#   EUA_price for ETS firms (zero for non-ETS). Network exposure propagates
#   this through the production network via (I-A)^{-1}.
#
#   Computes both UPSTREAM (cost-push: exposure through suppliers) and
#   DOWNSTREAM (demand-pull: exposure through customers) measures.
#
# DATA:
#   - NBB_data/processed/b2b_selected_sample.RData
#   - NBB_data/processed/firm_year_belgian_euets.RData
#   - NBB_data/processed/annual_accounts_selected_sample_key_variables.RData
#   - NBB_data/processed/firm_year_domestic_input_cost.RData
#   - NBB_data/processed/deflator_nace4d_2005base.RData
#   - NBB_data/processed/training_sample.RData
#   - NBB_data/processed/deployment_panel.RData
#
# OUTPUT:
#   - data/processed/network_exposure_panel.RData
#   - data/processed/io_matrices_by_year.RData (intermediate, for diagnostics)
###############################################################################

rm(list = ls())

library(dplyr)
library(stringr)
library(Matrix)

# ---- Paths ----
nbb_data     <- "c:/Users/jota_/Documents/NBB_data"
project_root <- "c:/Users/jota_/Documents/carbon_policy_networks"
proc_data    <- file.path(nbb_data, "processed")
out_data     <- file.path(project_root, "data", "processed")

dir.create(out_data, recursive = TRUE, showWarnings = FALSE)

base_year <- 2005
end_year  <- 2021

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
load(file.path(proc_data, "firm_year_domestic_input_cost.RData"))
load(file.path(proc_data, "deflator_nace4d_2005base.RData"))
load(file.path(proc_data, "training_sample.RData"))
load(file.path(proc_data, "deployment_panel.RData"))

# Rename B2B columns for clarity: vat_i_ano = supplier, vat_j_ano = buyer
colnames(df_b2b_selected_sample) <- c("vat_supplier", "vat_buyer",
                                       "year", "corr_sales")

# ---- Neumann series function ----
# Computes (I - A)^{-1} * v via power series: v + Av + A^2v + ...
# Returns list(result, k_iterations, rel_err, converged)
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

# ---- Build firm characteristics panel ----
# Combine ETS + non-ETS firms for sector/revenue info
ets_firms <- firm_year_belgian_euets %>%
  filter(in_sample == 1) %>%
  select(vat, year, nace5d, revenue, emissions, allocated_free) %>%
  mutate(is_ets = 1L)

nonets_firms <- deployment_panel %>%
  select(vat, year, nace5d, revenue) %>%
  mutate(is_ets = 0L, emissions = 0, allocated_free = 0)

all_firms_panel <- bind_rows(ets_firms, nonets_firms) %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(year >= base_year, year <= end_year,
         !is.na(nace4d), !is.na(revenue), revenue > 0)

# ---- Main loop: build exposure measures by year ----
cat("Building network exposure measures year by year...\n")

exposure_list <- list()
convergence_log <- list()
io_matrices <- list()

for (y in base_year:end_year) {

  cat(sprintf("  Year %d...", y))

  # --- Subset B2B for this year ---
  b2b_year <- df_b2b_selected_sample %>%
    filter(year == y, corr_sales > 0)

  if (nrow(b2b_year) == 0) {
    cat(" no B2B data, skipping.\n")
    next
  }

  # --- Define firm universe (all firms in B2B network this year) ---
  firms <- unique(c(b2b_year$vat_supplier, b2b_year$vat_buyer))
  n_firms <- length(firms)
  firm_idx <- setNames(seq_along(firms), firms)

  # --- Build expenditure matrix (rows = buyers, cols = suppliers) ---
  idx_buyer    <- firm_idx[b2b_year$vat_buyer]
  idx_supplier <- firm_idx[b2b_year$vat_supplier]

  exp_matrix <- sparseMatrix(
    i = idx_buyer,
    j = idx_supplier,
    x = b2b_year$corr_sales,
    dims = c(n_firms, n_firms)
  )

  # --- Total costs vector ---
  # wage_bill from annual accounts
  wages_year <- df_annual_accounts_selected_sample_key_variables %>%
    filter(year == y) %>%
    select(vat, wage_bill)

  ordered_wage_bill <- rep(0, n_firms)
  wage_match <- match(wages_year$vat, firms)
  valid <- !is.na(wage_match)
  ordered_wage_bill[wage_match[valid]] <- wages_year$wage_bill[valid]

  # domestic input purchases (row sums of expenditure matrix)
  ordered_input_purchases <- as.numeric(rowSums(exp_matrix))

  # emissions costs (for ETS firms only)
  ets_year <- firm_year_belgian_euets %>%
    filter(year == y, in_sample == 1) %>%
    select(vat, emissions, allocated_free)

  eua_price_y <- eua_prices$eua_price[eua_prices$year == y]

  ordered_emissions_costs <- rep(0, n_firms)
  ets_match <- match(ets_year$vat, firms)
  valid_ets <- !is.na(ets_match)
  if (any(valid_ets)) {
    ordered_emissions_costs[ets_match[valid_ets]] <-
      ets_year$emissions[valid_ets] * eua_price_y
  }

  # total costs = inputs + wages + emissions costs
  ordered_total_costs <- ordered_input_purchases + ordered_wage_bill +
    ordered_emissions_costs

  # Replace zeros with a small positive to avoid division by zero
  ordered_total_costs[ordered_total_costs <= 0] <- NA

  # --- Build A matrix (upstream/input coefficient matrix) ---
  # A[i,j] = expenditure of firm i on firm j / total_costs_i
  A <- exp_matrix
  # Only normalize rows where total_costs is not NA
  valid_costs <- !is.na(ordered_total_costs)
  # For rows with valid costs, divide by total costs
  # sparseMatrix stores in (i,j,x) triplet format; @i is 0-indexed row
  row_costs <- ordered_total_costs[A@i + 1]
  valid_entries <- !is.na(row_costs) & row_costs > 0
  A@x[valid_entries] <- A@x[valid_entries] / row_costs[valid_entries]
  A@x[!valid_entries] <- 0  # zero out entries for firms without cost data

  # Check convergence condition: max row sum < 1
  row_sums_A <- rowSums(A)
  max_rowsum_A <- max(row_sums_A, na.rm = TRUE)

  if (max_rowsum_A >= 1) {
    cat(sprintf(" WARNING: max rowsum(A) = %.4f >= 1, capping.\n", max_rowsum_A))
    # Scale down rows that exceed 1
    bad_rows <- which(row_sums_A >= 1)
    for (r in bad_rows) {
      row_start <- A@p[r] + 1
      row_end <- A@p[r + 1]
      if (row_end >= row_start) {
        A@x[row_start:row_end] <- A@x[row_start:row_end] * 0.99 / row_sums_A[r]
      }
    }
    max_rowsum_A <- max(rowSums(A))
  }

  # --- Build B matrix (downstream/output coefficient matrix) ---
  # B[i,j] = sales from i to j / total_revenue_i
  # exp_matrix[buyer, supplier] = buyer's purchases from supplier
  # So t(exp_matrix)[supplier, buyer] = supplier's sales to buyer
  sales_matrix <- t(exp_matrix)  # rows = suppliers, cols = buyers (= sales destinations)

  # Total revenue approximation: sum of sales to all B2B customers
  # (This undercounts total revenue but captures network-relevant sales)
  ordered_total_sales <- as.numeric(rowSums(sales_matrix))
  ordered_total_sales[ordered_total_sales <= 0] <- NA

  B <- sales_matrix
  row_sales <- ordered_total_sales[B@i + 1]
  valid_sales <- !is.na(row_sales) & row_sales > 0
  B@x[valid_sales] <- B@x[valid_sales] / row_sales[valid_sales]
  B@x[!valid_sales] <- 0

  # Check convergence condition for B
  row_sums_B <- rowSums(B)
  max_rowsum_B <- max(row_sums_B, na.rm = TRUE)

  if (max_rowsum_B >= 1) {
    cat(sprintf(" WARNING: max rowsum(B) = %.4f >= 1, capping.\n", max_rowsum_B))
    bad_rows_B <- which(row_sums_B >= 1)
    for (r in bad_rows_B) {
      row_start <- B@p[r] + 1
      row_end <- B@p[r + 1]
      if (row_end >= row_start) {
        B@x[row_start:row_end] <- B@x[row_start:row_end] * 0.99 / row_sums_B[r]
      }
    }
    max_rowsum_B <- max(rowSums(B))
  }

  # --- Direct exposure vector ---
  # e_i = max(emissions_i - allocated_free_i, 0) * eua_price / total_costs_i
  # For non-ETS firms: e_i = 0
  direct_exposure_abs <- rep(0, n_firms)  # in EUR
  if (any(valid_ets)) {
    shortage <- pmax(ets_year$emissions[valid_ets] -
                       ets_year$allocated_free[valid_ets], 0)
    direct_exposure_abs[ets_match[valid_ets]] <- shortage * eua_price_y
  }

  # Normalize by total costs for the Leontief calculation
  direct_exposure_intensity <- rep(0, n_firms)
  has_costs <- valid_costs & ordered_total_costs > 0
  direct_exposure_intensity[has_costs] <-
    direct_exposure_abs[has_costs] / ordered_total_costs[has_costs]

  # --- Compute upstream network exposure: (I-A)^{-1} * e ---
  upstream_result <- neumann_series(A, direct_exposure_intensity)

  # --- Compute downstream network exposure: (I-B)^{-1} * e ---
  # For downstream, we use the same direct exposure intensity but propagate

  # through the sales network
  downstream_result <- neumann_series(B, direct_exposure_intensity)

  # --- Store convergence info ---
  convergence_log[[as.character(y)]] <- data.frame(
    year = y,
    n_firms = n_firms,
    max_rowsum_A = max_rowsum_A,
    max_rowsum_B = max_rowsum_B,
    upstream_k = upstream_result$k,
    upstream_rel_err = upstream_result$rel_err,
    upstream_converged = upstream_result$converged,
    downstream_k = downstream_result$k,
    downstream_rel_err = downstream_result$rel_err,
    downstream_converged = downstream_result$converged
  )

  # --- Assemble firm-year output ---
  year_df <- data.frame(
    vat = firms,
    year = y,
    direct_exposure = direct_exposure_abs,
    direct_exposure_intensity = direct_exposure_intensity,
    upstream_exposure = upstream_result$result,
    downstream_exposure = downstream_result$result,
    total_costs = ifelse(valid_costs, ordered_total_costs, NA_real_),
    stringsAsFactors = FALSE
  )

  # Network-only exposure (subtract direct component)
  year_df$upstream_indirect <- year_df$upstream_exposure -
    year_df$direct_exposure_intensity
  year_df$downstream_indirect <- year_df$downstream_exposure -
    year_df$direct_exposure_intensity

  exposure_list[[as.character(y)]] <- year_df

  # Store IO matrix for diagnostics
  io_matrices[[as.character(y)]] <- list(
    A = A, firms = firms, max_rowsum_A = max_rowsum_A
  )

  cat(sprintf(" done. N=%d, upstream k=%d (err=%.2e), downstream k=%d (err=%.2e)\n",
              n_firms, upstream_result$k, upstream_result$rel_err,
              downstream_result$k, downstream_result$rel_err))
}

# ---- Combine into panel ----
cat("Combining into panel...\n")
network_exposure_panel <- bind_rows(exposure_list)

# Merge firm characteristics (nace codes, revenue, ETS status)
network_exposure_panel <- network_exposure_panel %>%
  left_join(
    all_firms_panel %>% select(vat, year, nace5d, nace2d, nace4d,
                                revenue, is_ets),
    by = c("vat", "year")
  )

# Deflate revenue
network_exposure_panel <- network_exposure_panel %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = ifelse(is.na(ppi), ppi_2d, ppi)) %>%
  select(-ppi_2d) %>%
  mutate(real_revenue = revenue / ppi * 100)

# ---- Summary diagnostics ----
convergence_df <- bind_rows(convergence_log)
cat("\n=== Convergence Summary ===\n")
print(convergence_df)

cat("\n=== Panel Summary ===\n")
cat(sprintf("Total firm-years: %d\n", nrow(network_exposure_panel)))
cat(sprintf("Unique firms: %d\n", n_distinct(network_exposure_panel$vat)))
cat(sprintf("Years: %d-%d\n", min(network_exposure_panel$year),
            max(network_exposure_panel$year)))
cat(sprintf("Firms with positive direct exposure: %d\n",
            sum(network_exposure_panel$direct_exposure > 0, na.rm = TRUE)))
cat(sprintf("Firms with positive upstream indirect: %d\n",
            sum(network_exposure_panel$upstream_indirect > 0, na.rm = TRUE)))
cat(sprintf("Firms with positive downstream indirect: %d\n",
            sum(network_exposure_panel$downstream_indirect > 0, na.rm = TRUE)))

# ---- Save ----
save(network_exposure_panel, convergence_df,
     file = file.path(out_data, "network_exposure_panel.RData"))

save(io_matrices, file = file.path(out_data, "io_matrices_by_year.RData"))

cat("\nSaved to:", out_data, "\n")
cat("Done.\n")
