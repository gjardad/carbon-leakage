# =============================================================================
# R7 builder — time-varying firm-year EU-ETS intensity for dCdH (2022)
# intertemporal estimator. Plan ref: imperative-whistling-acorn.md §R7.
#
# Motivation. The static §5.1 specifications collapse the EU-ETS into a single
# 2015 (or 2008) cutoff with a pre-shock-frozen firm cost share. That treats
# every post-cutoff year as the "same" treatment, even though the actual EUA
# price went €7→€25→€90 across 2014–2022 with regime breaks (MSR 2018,
# REPowerEU 2022). At the policy-effect level (RSBP Table 1, Q1 = NO), the
# bite is continuously time-varying and unit-specific, and the appropriate
# estimator is dCdH (2022) with a continuously-time-varying treatment.
#
# This script builds the firm-year time-varying intensity:
#
#   intensity_{i,t} = (allowance_shortage_{i,t} × eua_price_t) / revenue_pre_i
#
# where:
#   allowance_shortage_{i,t} = emissions_{i,t} − allocated_total_{i,t}
#                              (positive = firm had to buy permits)
#   eua_price_t              = €/tCO2 annual mean (Phase I/II curated,
#                              Phase III/IV ICAP — phase3_eua_prices.RData)
#   revenue_pre_i            = pre-shock 2010–2014 mean revenue of firm i
#                              (frozen denominator; same convention as
#                              firm_cost_share_regressor)
#
# Notes:
#   • For ETS firms with negative allowance shortage (= net long allowances),
#     intensity is set to zero — they did not feel the bite that year.
#   • For non-ETS firms, intensity is zero in every year (they were never
#     directly exposed).
#   • A second flavour `intensity_p2_{i,t}` uses pre-shock 2003–05 revenue as
#     denominator (Phase II analog).
#
# Inputs:
#   firm_year_belgian_euets.RData        — firm-year emissions + allocation
#   firm_cost_share_flavors.RData        — pre-shock revenue (already built)
#   data/processed/phase3_eua_prices.RData — annual EUA prices
#
# Outputs:
#   ${OUT_DATA}/firm_year_timevarying_intensity.RData — table with
#       cols: vat, year, eua_price, allowance_shortage, intensity_phase4,
#             intensity_phase2
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
})

# ---------------------------------------------------------------------------
# 1. Firm-year EU-ETS data (emissions, allocation, revenue)
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets <- as.data.table(firm_year_belgian_euets)[
  , .(vat, year, emissions_belgian, allocated_total, allowance_shortage,
      revenue_ets = revenue)]
ets[, year := as.integer(year)]
ets <- ets[!is.na(vat) & !is.na(year)]

# Some rows have allowance_shortage NA but emissions and allocated_total
# present — recompute from primitives where necessary.
ets[is.na(allowance_shortage) & !is.na(emissions_belgian) & !is.na(allocated_total),
    allowance_shortage := emissions_belgian - allocated_total]

cat(sprintf("ETS firm-years: %d rows, %d unique vats, %d–%d\n",
            nrow(ets), uniqueN(ets$vat), min(ets$year), max(ets$year)))

# ---------------------------------------------------------------------------
# 2. EUA prices
# ---------------------------------------------------------------------------
load(file.path(REPO_DIR, "data/processed/phase3_eua_prices.RData"))
prices <- as.data.table(eua_prices_annual)[, .(year = as.integer(year),
                                                eua_price = eua_price)]
ets <- merge(ets, prices, by = "year", all.x = TRUE)
stopifnot(!any(is.na(ets$eua_price[ets$year %between% c(2005L, 2022L)])))

# ---------------------------------------------------------------------------
# 3. Pre-shock revenue denominators (Phase IV: 2010–14, Phase II: 2003–05).
#    Use firm_cost_share_regressor's denominator if available; else build
#    from the in-ETS revenue series.
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
csr <- as.data.table(cost_share_regressor)

# Phase IV denominator: pre-shock 2010–14 mean revenue (within ETS panel).
rev_p4 <- ets[year %between% c(2010L, 2014L) & !is.na(revenue_ets) &
                revenue_ets > 0,
              .(revenue_pre_p4 = mean(revenue_ets, na.rm = TRUE)),
              by = vat]

# Phase II denominator: pre-shock 2003–05 mean revenue. Our ETS panel
# starts at 2005 so we use 2005 only; if the cost_share_regressor_phase2
# variable is present we prefer that flavor's implied denominator.
rev_p2 <- ets[year %between% c(2005L, 2007L) & !is.na(revenue_ets) &
                revenue_ets > 0,
              .(revenue_pre_p2 = mean(revenue_ets, na.rm = TRUE)),
              by = vat]

ets <- merge(ets, rev_p4, by = "vat", all.x = TRUE)
ets <- merge(ets, rev_p2, by = "vat", all.x = TRUE)

# ---------------------------------------------------------------------------
# 4. Compute intensities
# ---------------------------------------------------------------------------
# Define bite at firm-year as (positive) allowance shortage × EUA price.
# Floor at zero — when allocation exceeds emissions, firm was a net seller
# and felt no cost bite that year.
ets[, bite_eur := pmax(allowance_shortage, 0, na.rm = FALSE) * eua_price]
ets[is.na(bite_eur), bite_eur := 0]

# Phase IV intensity (denominator: 2010–14 mean revenue).
ets[, intensity_phase4 := bite_eur / revenue_pre_p4]
ets[is.na(intensity_phase4) | !is.finite(intensity_phase4),
    intensity_phase4 := 0]

# Phase II intensity (denominator: 2005 revenue if 2003-05 unavailable).
ets[, intensity_phase2 := bite_eur / revenue_pre_p2]
ets[is.na(intensity_phase2) | !is.finite(intensity_phase2),
    intensity_phase2 := 0]

# ---------------------------------------------------------------------------
# 5. Distributional sanity checks
# ---------------------------------------------------------------------------
cat("\nIntensity (Phase IV) by year (median, p90, p99):\n")
chk <- ets[, .(median = quantile(intensity_phase4, 0.5, na.rm = TRUE),
               p90    = quantile(intensity_phase4, 0.9, na.rm = TRUE),
               p99    = quantile(intensity_phase4, 0.99, na.rm = TRUE),
               n      = .N), by = year][order(year)]
print(chk)

cat("\nIntensity (Phase II) by year:\n")
chk2 <- ets[, .(median = quantile(intensity_phase2, 0.5, na.rm = TRUE),
                p90    = quantile(intensity_phase2, 0.9, na.rm = TRUE),
                p99    = quantile(intensity_phase2, 0.99, na.rm = TRUE),
                n      = .N), by = year][order(year)]
print(chk2)

# ---------------------------------------------------------------------------
# 6. Save
# ---------------------------------------------------------------------------
firm_year_timevarying_intensity <- ets[,
  .(vat, year, eua_price, allowance_shortage, bite_eur,
    revenue_pre_p4, revenue_pre_p2,
    intensity_phase4, intensity_phase2)]

dir.create(file.path(REPO_DIR, "data/processed"), recursive = TRUE,
           showWarnings = FALSE)
save(firm_year_timevarying_intensity,
     file = file.path(REPO_DIR,
                      "data/processed/firm_year_timevarying_intensity.RData"))

cat(sprintf(
  "\nSaved %d ETS firm-year rows to data/processed/firm_year_timevarying_intensity.RData\n",
  nrow(firm_year_timevarying_intensity)))
