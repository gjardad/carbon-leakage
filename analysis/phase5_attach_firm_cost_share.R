# phase5_attach_firm_cost_share.R
#
# Prep 2 for Plan B (SHOCK_AND_SUBSTITUTION_PLAN.md).
#
# Two firm-cost-share flavors -- each test in Plan B uses a different one
# because each test answers a different question:
#
#   (1) firm_cost_share_outcome_{j,t}  -- per-seller, per-year. Used as
#       OUTCOME in Test A (new-pair tilt: regress seller's carbon intensity
#       at the time of match on Post indicators). Definition:
#         (shortage_{j,t} * EUA_t) / total_cost_{j,t-1}
#       Lagging the denominator avoids the mechanical correlation that would
#       arise when emissions and total cost both move together within year.
#       Bartik-style exogeneity is not needed here because cost-share is on
#       the LHS.
#
#   (2) firm_cost_share_regressor_j -- per-seller, time-invariant. Used as
#       REGRESSOR / treatment intensity in Test B (hazard) and Test G
#       (feasibility-restricted). Definition:
#         mean_{2012-14}(shortage * EUA) / mean_{2012-14}(total_cost)
#       Same window for numerator and denominator (no Bartik trick) -- 2012-14
#       is post-Phase-II free-allocation reduction and pre-MSR-binding, so it
#       reflects an emerging real cost shock. We do NOT define a comparable
#       2005-binding pre-period treatment intensity because Phase II free
#       allocation makes the numerator near-zero for most ETS sellers.
#
# Reads:
#   - firm_year_belgian_euets.RData (built upstream)
#   - EUA price series (hardcoded; matches phase3_b2b_cmdj_did_continuous.R)
#
# Drops the 3 VATs flagged as contaminated post-2020 in NACE 20 / 24 (per
# memory note 2026-04-23): exclude them from both flavors so they cannot
# contaminate any seller-side regression.
#
# Output: ${PROC_DATA}/firm_cost_share_flavors.RData
#   cost_share_outcome   :: data.table (vat, year, firm_cost_share_outcome)
#   cost_share_regressor :: data.table (vat, firm_cost_share_regressor)

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)

# Pre-shock window for the regressor flavor.
PRE_LO <- 2012L
PRE_HI <- 2014L

# Year window for the outcome flavor.
OUT_YEAR_LO <- 2003L  # needs t-1 = 2002 for total_cost lag
OUT_YEAR_HI <- 2022L

# 3 contaminated VATs (NACE 20 / 24 post-2020 break). We drop only the
# 2021+ rows for these firms so their pre-2020 history (clean) is preserved.
CONTAMINATED_VATS <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",  # NACE 24
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",  # NACE 20
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"   # NACE 20
)
CONTAMINATION_YEAR_FROM <- 2021L

# EUA prices (Angle 4 convention; matches phase3_b2b_cmdj_did_continuous.R:73-76).
eua_prices <- data.table(
  year = 2005:2022,
  eua_price = c(22, 18, 0.7, 22, 13, 14, 13, 7.5,
                4.5, 6, 7.5, 5, 5.8, 16, 25, 25, 53, 80))

# ---------------------------------------------------------------------------
# 1. Load EUTS firm-year panel
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets <- as.data.table(firm_year_belgian_euets)
cat("Raw EUTS firm-year rows:", nrow(ets), "\n")

# Drop the 3 contaminated VATs only from 2021 onward (pre-2020 history is
# clean and useful for the 2012-14 regressor flavor).
ets <- ets[!(vat %in% CONTAMINATED_VATS & year >= CONTAMINATION_YEAR_FROM)]
cat("After dropping 3 contaminated VATs (2021+):", nrow(ets), "\n")

# Bring in EUA price.
ets <- merge(ets, eua_prices, by = "year", all.x = TRUE)

# Compute carbon cost and total cost. Use the same construction as
# phase3_b2b_cmdj_did_continuous.R for consistency.
ets[, shortage    := pmax(emissions - allocated_free, 0, na.rm = TRUE)]
ets[, carbon_cost := shortage * eua_price]
ets[, mat_inputs  := revenue - value_added]
ets[, total_cost  := mat_inputs + wage_bill]

# is_regulated == 1 (emissions observed in EUTL) is required for a meaningful
# shortage. The upstream build script adds this column; if running against an
# older panel without it, derive locally as !is.na(emissions).
if (!"is_regulated" %in% names(ets)) {
  ets[, is_regulated := as.integer(!is.na(emissions))]
  cat("is_regulated column missing from upstream panel; derived locally as ",
      "!is.na(emissions).\n")
}
ets[is_regulated == 0L, carbon_cost := NA_real_]

# ---------------------------------------------------------------------------
# 2. firm_cost_share_outcome_{j,t}  -- same-year numerator, t-1 denominator
# ---------------------------------------------------------------------------
setorder(ets, vat, year)
ets[, total_cost_lag1 := shift(total_cost, 1, type = "lag"), by = vat]
ets[, year_gap        := year - shift(year, 1, type = "lag"),  by = vat]

# Lag is only valid if the previous row is exactly t-1 (no gap).
ets[year_gap != 1L, total_cost_lag1 := NA_real_]

ets[, firm_cost_share_outcome := ifelse(
  !is.na(carbon_cost) & !is.na(total_cost_lag1) & total_cost_lag1 > 0,
  carbon_cost / total_cost_lag1,
  NA_real_
)]

cost_share_outcome <- ets[year %between% c(OUT_YEAR_LO, OUT_YEAR_HI) &
                            !is.na(firm_cost_share_outcome),
                          .(vat, year, firm_cost_share_outcome)]
setkey(cost_share_outcome, vat, year)

cat("\nfirm_cost_share_outcome rows:", nrow(cost_share_outcome), "\n")
cat("Distinct sellers covered:    ", uniqueN(cost_share_outcome$vat), "\n")
cat("Year range:                  ",
    min(cost_share_outcome$year), "-", max(cost_share_outcome$year), "\n")
cat("Quantiles (whole sample):\n")
print(quantile(cost_share_outcome$firm_cost_share_outcome,
               c(0.5, 0.75, 0.9, 0.99), na.rm = TRUE))

cat("\nQuantiles by phase:\n")
cost_share_outcome[, phase := fcase(
  year %between% c(2005L, 2007L),  "I",
  year %between% c(2008L, 2012L),  "II",
  year %between% c(2013L, 2017L),  "III pre-MSR",
  year %between% c(2018L, 2020L),  "III post-MSR",
  year %between% c(2021L, 2022L),  "IV",
  default = "pre-2005"
)]
print(cost_share_outcome[, .(
  n   = .N,
  p50 = quantile(firm_cost_share_outcome, 0.5, na.rm = TRUE),
  p90 = quantile(firm_cost_share_outcome, 0.9, na.rm = TRUE),
  p99 = quantile(firm_cost_share_outcome, 0.99, na.rm = TRUE)
), by = phase][order(phase)])
cost_share_outcome[, phase := NULL]

# ---------------------------------------------------------------------------
# 3. firm_cost_share_regressor_j  -- mean 2012-14 numerator / mean 2012-14 denom
# ---------------------------------------------------------------------------
num_pre <- ets[year %between% c(PRE_LO, PRE_HI) & !is.na(carbon_cost),
               .(mean_carbon_cost = mean(carbon_cost, na.rm = TRUE)),
               by = vat]
denom_pre <- ets[year %between% c(PRE_LO, PRE_HI) &
                   !is.na(total_cost) & total_cost > 0,
                 .(mean_total_cost = mean(total_cost, na.rm = TRUE)),
                 by = vat]

cost_share_regressor <- merge(num_pre, denom_pre, by = "vat", all = FALSE)
cost_share_regressor[, firm_cost_share_regressor :=
                       mean_carbon_cost / mean_total_cost]
cost_share_regressor <- cost_share_regressor[!is.na(firm_cost_share_regressor),
                                              .(vat, firm_cost_share_regressor)]
setkey(cost_share_regressor, vat)

cat("\nfirm_cost_share_regressor (pre-shock 2012-14):\n")
cat("  Sellers covered:", nrow(cost_share_regressor), "\n")
cat("  Quantiles:\n")
print(quantile(cost_share_regressor$firm_cost_share_regressor,
               c(0.1, 0.5, 0.75, 0.9, 0.99), na.rm = TRUE))

# ---------------------------------------------------------------------------
# 4. Save
# ---------------------------------------------------------------------------
out_path <- file.path(PROC_DATA, "firm_cost_share_flavors.RData")
save(cost_share_outcome, cost_share_regressor, file = out_path)
cat("\nSaved", out_path, "\n")
