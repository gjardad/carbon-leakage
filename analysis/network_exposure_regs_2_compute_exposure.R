###############################################################################
# network_exposure_regs_2_compute_exposure.R
#
# PURPOSE:
#   For each year 2012-2021, compute upstream and downstream network exposure
#   using the FROZEN base-period A and B matrices (from script 1) combined
#   with time-varying direct exposure (shortage x EUA price, normalized by
#   base-period average costs).
#
# SPECIFICATION:
#   upstream_exposure_t  = (I - A_base)^{-1} x e_t
#   downstream_exposure_t = (I - B_base)^{-1} x e_t
#   e_jt = max(emissions_jt - free_allowances_jt, 0) x price_t / avg_costs_j_base
#
# DATA:
#   - data/processed/frozen_weights_matrices.RData  (from script 1)
#   - NBB_data/processed/firm_year_belgian_euets.RData
#
# OUTPUT:
#   - data/processed/frozen_weights_exposure_raw.RData
#     (frozen_exposure_panel_raw, convergence_df)
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
load(file.path(OUT_DATA, "frozen_weights_matrices.RData"))
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))

n_firms_base <- length(firms_base)

# ---- Neumann series ----
neumann_series <- function(A, v, max_iter = 200, tol = 1e-8) {
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
# For each year 2012-2021, compute exposure using frozen A_base, B_base
# ===========================================================================
cat("\nComputing frozen-weight exposure for 2012-2021...\n")

analysis_years <- 2012:2021
exposure_list <- list()
convergence_log <- list()

for (y in analysis_years) {
  cat(sprintf("  Year %d...", y))

  eua_price_y <- eua_prices$eua_price[eua_prices$year == y]

  # Direct exposure vector: shortage x price, for ETS firms in base universe.
  # Exclude firms with missing emissions/allocated_free (otherwise NA flows
  # through the Neumann iteration and breaks convergence checks).
  ets_y <- firm_year_belgian_euets %>%
    filter(year == y, in_sample == 1,
           !is.na(emissions), !is.na(allocated_free)) %>%
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

  # Upstream: (I - A_base)^{-1} x e_t
  upstream_res <- neumann_series(A_base, direct_exposure_intensity)

  # Downstream: (I - B_base)^{-1} x e_t
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

frozen_exposure_panel_raw <- bind_rows(exposure_list)
convergence_df <- bind_rows(convergence_log)

cat("\n=== Convergence (frozen A_base) ===\n")
print(convergence_df)

# ---- Save ----
save(frozen_exposure_panel_raw, convergence_df,
     file = file.path(OUT_DATA, "frozen_weights_exposure_raw.RData"))
cat("\nRaw exposure saved to:",
    file.path(OUT_DATA, "frozen_weights_exposure_raw.RData"), "\n")
cat("Done.\n")
