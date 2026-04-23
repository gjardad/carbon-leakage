###############################################################################
# phase3_build_cpshock.R
#
# PURPOSE:
#   Load Känzig (2025 JMP) carbon policy surprise/shock series and aggregate
#   to an annual panel for use as an exogenous instrument / interaction term
#   in the NACE4d PPI pass-through regressions.
#
#   Two series provided in carbonPolicyShocks.xlsx:
#     - Surprise: high-frequency event-study surprise (orthogonalized daily
#       EUA price change relative to the prevailing wholesale electricity
#       price). Monthly = sum of daily surprises in each month; zero in
#       months without regulatory events.
#     - Shock: carbon policy shock identified by the external-instruments
#       VAR using Surprise as the instrument. Available monthly.
#
#   We use Surprise as the primary annual series:
#     CPShock_y = sum_{m in year y} Surprise_m.
#   Shock is also aggregated for completeness (robustness).
#
#   Coverage ends 2019M12 (JMP sample). BKR 2026 extended to 2024 but the
#   extended series is not publicly posted. Pre-2005 values are mechanically
#   zero (no ETS); we keep them zero explicitly.
#
# INPUT:
#   NBB_data/raw/carbonPolicyShocks.xlsx
#
# OUTPUT:
#   data/processed/cpshock_annual.RData  -- data.frame(year, cpshock_surprise,
#                                                       cpshock_shock, n_months)
###############################################################################

rm(list = ls())

library(dplyr)
library(readxl)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

xlsx_path <- file.path(RAW_DATA, "carbonPolicyShocks.xlsx")
stopifnot(file.exists(xlsx_path))

# ---- Load monthly sheet ----
mly <- read_excel(xlsx_path, sheet = "Monthly") %>%
  mutate(
    year  = as.integer(substr(Date, 1, 4)),
    month = as.integer(substr(Date, 6, 7))
  ) %>%
  rename(surprise = Surprise, shock = Shock)

cat(sprintf("Monthly sheet: %d rows, %d-%d\n",
            nrow(mly), min(mly$year), max(mly$year)))

# ---- Aggregate to annual ----
cpshock_annual <- mly %>%
  group_by(year) %>%
  summarise(
    cpshock_surprise = sum(surprise, na.rm = TRUE),
    cpshock_shock    = sum(shock,    na.rm = TRUE),
    n_months         = n(),
    n_surprise_nonzero = sum(surprise != 0, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(year)

# Pre-2005 is pre-ETS: set Surprise to exactly zero (already is), Shock is
# VAR-generated noise that we should not attribute to carbon policy.
# We keep the Shock values as-is for transparency but flag them.
cpshock_annual <- cpshock_annual %>%
  mutate(pre_ets = year < 2005)

cat("\nAnnual CPShock series:\n")
print(cpshock_annual)

cat(sprintf("\nCoverage: %d-%d (%d years)\n",
            min(cpshock_annual$year), max(cpshock_annual$year),
            nrow(cpshock_annual)))
cat(sprintf("Usable window (ETS era, 2005+): %d-%d (%d years)\n",
            max(2005, min(cpshock_annual$year)),
            max(cpshock_annual$year),
            sum(cpshock_annual$year >= 2005)))

cat(sprintf("\nSurprise: mean=%.4f, sd=%.4f, min=%.4f, max=%.4f (ETS era)\n",
            mean(cpshock_annual$cpshock_surprise[cpshock_annual$year >= 2005]),
            sd(cpshock_annual$cpshock_surprise[cpshock_annual$year >= 2005]),
            min(cpshock_annual$cpshock_surprise[cpshock_annual$year >= 2005]),
            max(cpshock_annual$cpshock_surprise[cpshock_annual$year >= 2005])))

# ---- Save ----
save(cpshock_annual, file = file.path(OUT_DATA, "cpshock_annual.RData"))
cat(sprintf("\nSaved: %s\n", file.path(OUT_DATA, "cpshock_annual.RData")))
