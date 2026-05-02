# =============================================================================
# Phase II firm_cost_share regressor flavor — for §5.1.6 / §5.1.7 of the paper.
#
# Sibling of phase5_attach_firm_cost_share.R. Adds a third flavor to
# firm_cost_share_flavors.RData (without disturbing the existing two):
#
#   (3) cost_share_regressor_phase2 :: data.table (vat, firm_cost_share_regressor_phase2)
#       Time-invariant treatment intensity for the Phase II event-study (2008
#       cutoff). Same construction as the Phase IV regressor in the existing
#       script but on a pre-2008 window:
#         numerator: mean_{2005-2007}(shortage * EUA)
#         denominator: mean_{2005-2007}(total_cost)
#
#       2005-2007 is Phase I (the only available pre-2008 window with both
#       EUTL coverage and Annual Accounts). Free allocation was generous in
#       Phase I so most firms have shortage ≈ 0; this is fine -- the paper
#       (§3) documents that Phase II shock magnitudes are small at the
#       population level and the value-add of A3/A4 is in the long-horizon
#       identification, not the level magnitude.
#
# Reads:
#   - firm_year_belgian_euets.RData (built upstream)
#   - firm_cost_share_flavors.RData (existing two flavors, will be re-saved
#     with the third flavor appended)
#
# Output: ${PROC_DATA}/firm_cost_share_flavors.RData (overwrites)
#   cost_share_outcome           :: existing (preserved)
#   cost_share_regressor         :: existing (preserved)
#   cost_share_regressor_phase2  :: new
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)

# Pre-shock window for the Phase II regressor.
PRE_LO <- 2005L
PRE_HI <- 2007L

# 3 contaminated VATs (NACE 20 / 24 post-2020 break) — irrelevant pre-2008
# but apply the same drop convention for consistency.
CONTAMINATED_VATS <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
CONTAMINATION_YEAR_FROM <- 2021L

# EUA prices (matches phase5_attach_firm_cost_share.R).
eua_prices <- data.table(
  year = 2005:2022,
  eua_price = c(22, 18, 0.7, 22, 13, 14, 13, 7.5,
                4.5, 6, 7.5, 5, 5.8, 16, 25, 25, 53, 80))

# ---------------------------------------------------------------------------
# 1. Load EUTL firm-year panel
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets <- as.data.table(firm_year_belgian_euets)
cat("Raw EUTL firm-year rows:", nrow(ets), "\n")

ets <- ets[!(vat %in% CONTAMINATED_VATS & year >= CONTAMINATION_YEAR_FROM)]
ets <- merge(ets, eua_prices, by = "year", all.x = TRUE)

ets[, shortage    := pmax(emissions - allocated_free, 0, na.rm = TRUE)]
ets[, carbon_cost := shortage * eua_price]
ets[, mat_inputs  := revenue - value_added]
ets[, total_cost  := mat_inputs + wage_bill]

if (!"is_regulated" %in% names(ets)) {
  ets[, is_regulated := as.integer(!is.na(emissions))]
}
ets[is_regulated == 0L, carbon_cost := NA_real_]

# ---------------------------------------------------------------------------
# 2. Build cost_share_regressor_phase2
# ---------------------------------------------------------------------------
num_pre <- ets[year %between% c(PRE_LO, PRE_HI) & !is.na(carbon_cost),
               .(mean_carbon_cost = mean(carbon_cost, na.rm = TRUE)),
               by = vat]
denom_pre <- ets[year %between% c(PRE_LO, PRE_HI) &
                   !is.na(total_cost) & total_cost > 0,
                 .(mean_total_cost = mean(total_cost, na.rm = TRUE)),
                 by = vat]

cost_share_regressor_phase2 <- merge(num_pre, denom_pre, by = "vat", all = FALSE)
cost_share_regressor_phase2[, firm_cost_share_regressor_phase2 :=
                              mean_carbon_cost / mean_total_cost]
cost_share_regressor_phase2 <- cost_share_regressor_phase2[
  !is.na(firm_cost_share_regressor_phase2),
  .(vat, firm_cost_share_regressor_phase2)]
setkey(cost_share_regressor_phase2, vat)

cat(sprintf("\ncost_share_regressor_phase2 (pre-shock %d-%d):\n", PRE_LO, PRE_HI))
cat("  Sellers covered:", nrow(cost_share_regressor_phase2), "\n")
cat("  Quantiles:\n")
print(quantile(cost_share_regressor_phase2$firm_cost_share_regressor_phase2,
               c(0.1, 0.5, 0.75, 0.9, 0.99), na.rm = TRUE))

# ---------------------------------------------------------------------------
# 3. Save (preserve existing two flavors)
# ---------------------------------------------------------------------------
existing <- file.path(PROC_DATA, "firm_cost_share_flavors.RData")
if (file.exists(existing)) {
  e <- new.env()
  load(existing, envir = e)
  cost_share_outcome   <- get("cost_share_outcome", envir = e)
  cost_share_regressor <- get("cost_share_regressor", envir = e)
  cat("\nLoaded existing two flavors:\n")
  cat("  cost_share_outcome:   ", nrow(cost_share_outcome), "rows\n")
  cat("  cost_share_regressor: ", nrow(cost_share_regressor), "rows\n")
} else {
  stop("firm_cost_share_flavors.RData not found. Run phase5_attach_firm_cost_share.R first.")
}

save(cost_share_outcome, cost_share_regressor, cost_share_regressor_phase2,
     file = existing)
cat("\nSaved (3 flavors) to", existing, "\n")
