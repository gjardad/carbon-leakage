###############################################################################
# phase3_build_sector_omega_rolling.R
#
# PURPOSE:
#   Build the rolling-window cost-share exposure measure ω_{s,t} used in the
#   pass-through IV regression (§4 Strategy 1, replacing intensity_s^base).
#
#   For each sector s and year t, ω_{s,t} = (carbon cost / total cost) at
#   year t-1. This is predetermined relative to year t and updates annually
#   as technology and emissions evolve, addressing the staleness of a fixed-
#   window construction (e.g. 2005-07 or 2013-16) when the regression panel
#   spans many years.
#
#   Three flavours are computed in parallel:
#
#     ω_gross_{s,t} = (gross_emissions × EUA / total_cost) at t-1
#                     [marginal-pricing-relevant cost share under Shephard's lemma]
#
#     ω_short_{s,t} = (shortage × EUA / total_cost) at t-1
#                     [realized-cost-pricing alternative; legacy convention]
#
#     ω_free_{s,t}  = ω_gross_{s,t} - ω_short_{s,t}
#                     [the free-allocation portion of the cost share; used in the
#                      windfall-profit decomposition test in the appendix]
#
#   Main-text headline regression uses ω_gross. Appendix uses ω_gross + ω_free
#   together as a direct test of windfall-profit pricing.
#
# INPUT:
#   ${OUT_DATA}/phase3_sector_exposure.RData     (sector_exposure)
#       columns used: nace4d, year, total_emissions, total_shortage,
#                     total_cost_denom
#   ${OUT_DATA}/phase3_eua_prices.RData          (eua_prices_annual)
#       columns used: year, eua_price
#
# OUTPUT:
#   ${OUT_DATA}/phase3_sector_omega_rolling.RData (sector_omega_rolling)
#       columns: nace4d, year, omega_gross, omega_short, omega_free, n_obs_used
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---------------------------------------------------------------------------
# 1. Load inputs
# ---------------------------------------------------------------------------
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))   # sector_exposure
load(file.path(OUT_DATA, "phase3_eua_prices.RData"))        # eua_prices_annual

cat(sprintf("sector_exposure: %d sector-years, %d distinct NACE 4d, %d-%d\n",
            nrow(sector_exposure), n_distinct(sector_exposure$nace4d),
            min(sector_exposure$year), max(sector_exposure$year)))
cat(sprintf("eua_prices_annual: %d-%d\n",
            min(eua_prices_annual$year), max(eua_prices_annual$year)))

# ---------------------------------------------------------------------------
# 2. Build sector-year carbon-cost components (gross and short)
# ---------------------------------------------------------------------------
sx <- sector_exposure %>%
  select(nace4d, year, total_emissions, total_shortage, total_cost_denom) %>%
  left_join(eua_prices_annual %>% select(year, eua_price), by = "year") %>%
  mutate(
    carbon_cost_gross = total_emissions * eua_price,
    carbon_cost_short = total_shortage  * eua_price
  )

# Drop rows where the denominator is missing or non-positive (mostly very
# early years for sectors not yet observed). Keep them as NA-valued for
# the lag computation; they'll just produce NA omegas downstream.
sx <- sx %>% arrange(nace4d, year)

# ---------------------------------------------------------------------------
# 3. Compute 1-year (t-1) omegas
#
#    For each (s, t), ω_{s,t} = carbon_cost_{s, t-1} / total_cost_{s, t-1}
#    where carbon_cost is gross or short. Predetermined relative to year t.
# ---------------------------------------------------------------------------
omega <- sx %>%
  group_by(nace4d) %>%
  mutate(
    cc_gross_lag1 = dplyr::lag(carbon_cost_gross, 1),
    cc_short_lag1 = dplyr::lag(carbon_cost_short, 1),
    cost_lag1     = dplyr::lag(total_cost_denom,  1)
  ) %>%
  ungroup() %>%
  mutate(
    n_obs_used  = as.integer(!is.na(cc_gross_lag1) &
                             !is.na(cost_lag1) & cost_lag1 > 0),
    omega_gross = ifelse(!is.na(cost_lag1) & cost_lag1 > 0,
                         cc_gross_lag1 / cost_lag1, NA_real_),
    omega_short = ifelse(!is.na(cost_lag1) & cost_lag1 > 0,
                         cc_short_lag1 / cost_lag1, NA_real_),
    omega_free  = omega_gross - omega_short
  )

sector_omega_rolling <- omega %>%
  select(nace4d, year, omega_gross, omega_short, omega_free, n_obs_used)

# ---------------------------------------------------------------------------
# 4. Diagnostics
# ---------------------------------------------------------------------------
cat("\n=== Sector-year ω coverage ===\n")
print(sector_omega_rolling %>%
        group_by(year) %>%
        summarise(n_sectors           = n(),
                  n_sectors_omega_def = sum(!is.na(omega_gross)),
                  pct_def             = round(100 * mean(!is.na(omega_gross)), 1),
                  .groups = "drop") %>%
        arrange(year),
      n = 30)

cat("\n=== Distribution of ω_gross by year ===\n")
print(sector_omega_rolling %>%
        filter(!is.na(omega_gross), omega_gross > 0) %>%
        group_by(year) %>%
        summarise(n        = n(),
                  median   = round(median(omega_gross), 5),
                  p90      = round(quantile(omega_gross, 0.90), 5),
                  p99      = round(quantile(omega_gross, 0.99), 5),
                  max      = round(max(omega_gross), 5),
                  .groups = "drop") %>%
        arrange(year),
      n = 30)

# ---------------------------------------------------------------------------
# 5. Save
# ---------------------------------------------------------------------------
save(sector_omega_rolling,
     file = file.path(OUT_DATA, "phase3_sector_omega_rolling.RData"))
cat("\nSaved:", file.path(OUT_DATA, "phase3_sector_omega_rolling.RData"), "\n")
