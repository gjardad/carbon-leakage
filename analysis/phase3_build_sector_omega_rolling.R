###############################################################################
# phase3_build_sector_omega_rolling.R
#
# PURPOSE:
#   Build the rolling-window emissions-intensity exposure measure ω_{s,t}
#   used in the pass-through panel-LP regression. ω is a PHYSICAL emissions
#   intensity (tCO2 per EUR of cost), NOT a carbon-cost share — the EUA
#   price factor is intentionally excluded so ω stays well-identified in
#   periods when EUA collapsed (Phase I overallocation crash 2007, Phase II
#   crisis trough). The EUA-price channel enters the regression through the
#   CPShock interaction, not through ω.
#
#   For each sector s and year t, ω_{s,t} = (emissions / total cost) at
#   year t-1. Predetermined relative to year t and updates annually.
#
#   Three flavours are computed in parallel:
#
#     ω_gross_{s,t} = gross_emissions / total_cost   at t-1
#                     [main: physical exposure to ETS regulation]
#
#     ω_short_{s,t} = shortage / total_cost          at t-1
#                     [robustness: emissions in excess of free allocation]
#
#     ω_free_{s,t}  = ω_gross_{s,t} - ω_short_{s,t}
#                   = free_allowance / total_cost    at t-1
#                     [free-allocation share of the emissions intensity]
#
#   Units of ω: tCO2 per EUR. To convert to a cost-share at a reference EUA
#   price P, multiply by P. Headline pass-through coefficient β_h is then
#   normalised by E[EUA] in-sample so β=1 still corresponds to full
#   Shephard's-lemma pass-through.
#
# INPUT:
#   ${OUT_DATA}/phase3_sector_exposure.RData     (sector_exposure)
#       columns used: nace4d, year, total_emissions, total_shortage,
#                     total_cost_denom
#   (Note: EUA price is NO LONGER used here. It was used in the previous
#   carbon-cost-share construction; under the new physical-intensity
#   convention it enters only via the CPShock interaction in the regression.)
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

cat(sprintf("sector_exposure: %d sector-years, %d distinct NACE 4d, %d-%d\n",
            nrow(sector_exposure), n_distinct(sector_exposure$nace4d),
            min(sector_exposure$year), max(sector_exposure$year)))

# ---------------------------------------------------------------------------
# 2. Compute 1-year (t-1) emissions-intensity omegas (no EUA factor)
#
#    For each (s, t), ω_{s,t} = emissions_{s, t-1} / total_cost_{s, t-1}.
#    Predetermined relative to year t. Units: tCO2 per EUR.
# ---------------------------------------------------------------------------
sx <- sector_exposure %>%
  select(nace4d, year, total_emissions, total_shortage, total_cost_denom) %>%
  arrange(nace4d, year)

omega <- sx %>%
  group_by(nace4d) %>%
  mutate(
    em_gross_lag1 = dplyr::lag(total_emissions, 1),
    em_short_lag1 = dplyr::lag(total_shortage,  1),
    cost_lag1     = dplyr::lag(total_cost_denom, 1)
  ) %>%
  ungroup() %>%
  mutate(
    n_obs_used  = as.integer(!is.na(em_gross_lag1) &
                             !is.na(cost_lag1) & cost_lag1 > 0),
    omega_gross = ifelse(!is.na(cost_lag1) & cost_lag1 > 0,
                         em_gross_lag1 / cost_lag1, NA_real_),
    omega_short = ifelse(!is.na(cost_lag1) & cost_lag1 > 0,
                         em_short_lag1 / cost_lag1, NA_real_),
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
