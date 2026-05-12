###############################################################################
# phase5_buyer_input_shock_measures.R
#
# Computes the new buyer-side shock-magnitude measures for §3 (Shock to treated
# buyers), complementing the pair-shock distributions already in
# phase5_pair_shock_magnitude.R and the buyer-volatility (sigma_share)
# distribution in phase5_shock_benchmarks.R.
#
# MEASURES:
#   M1  share of buyer b's year-t total B2B input cost going to suppliers in
#       any ETS-treated NACE 4d sector. Distribution across (b, t).
#
#   M2  share of buyer b's year-t total B2B input cost going to ETS-treated
#       firms (subset of M1: only sellers in EUTL). Distribution across (b, t).
#
#   M3  number of distinct suppliers buyer b has in (ETS-treated) NACE 4d n in
#       year t. Distribution across (b, n, t) where n is ETS-treated.
#
#   M7  buyer-year signal-to-noise ratio
#         SNR_{b,t} = buyer_total_shock_{b,t} / sigma_share_b
#       where sigma_share_b is the within-buyer SD of Δlog(input_cost / revenue)
#       on a clean pre-shock window (2005--2019). Reported as the distribution
#       across buyer-years.
#
# ALREADY DONE (re-used by reference, not recomputed here):
#   M4  pair-shock distribution -> phase5_moment4_pair_shock_distribution.csv
#   M5  pair-shock-total distribution -> phase5_moment4c_pair_shock_total_distribution.csv
#   M6  buyer-total-shock distribution -> phase5_moment4a_buyer_total_shock_distribution.csv
#
# DEFINITIONS:
#   "ETS-treated NACE 4d sector" = any NACE 4-digit code that contains at
#   least one ETS-regulated seller across the 2005--2022 sample. Same
#   convention as nace_exposure_n > 0 in phase5_test_i_cross_nace_substitution.R.
#
# SAMPLE:
#   All Belgian buyers with at least one B2B inflow in 2005--2022, from the
#   raw b2b_selected_sample (NOT the regulated-intensive cdgm_panel). The
#   broader sample is appropriate for a descriptive subsection that asks
#   "how many buyers face any ETS exposure at all?". §5.1 regressions stay
#   on the b2b_cdgm_panel.
#
# INPUT:
#   ${PROC_DATA}/b2b_selected_sample.RData
#   ${OUT_DATA}/phase3_firm_exposure.RData
#   ${RAW_DATA}/NBB/Annual_Accounts_MASTER_ANO.dta              (NACE 4d crosswalk)
#   ${PROC_DATA}/annual_accounts_more_selected_sample.RData     (inputs_VAT)
#
# OUTPUT (under output_${MACHINE_TAG}/tables):
#   phase5_M1_buyer_share_regulated_nace4d.csv
#   phase5_M2_buyer_share_ets_firms.csv
#   phase5_M3_n_suppliers_per_regulated_nace4d.csv
#   phase5_M7_buyer_year_signal_to_noise.csv
#   phase5_buyer_input_shock_summary.txt
#
# CAVEATS:
#   - Drops the 3 contaminated VAT hashes (NACE 20, 24) from 2021+ per
#     memory/project_nace24_eutl_break_post2020.md, on both buyer and seller
#     sides.
#   - sigma_share_b computed on 2005--2019 to avoid contamination from the
#     Phase IV / pandemic shock window. Buyers with fewer than 4 valid
#     Δlog(inputs_VAT/turnover_VAT) observations are dropped from M7.
#   - For M7 a buyer-year is in-sample only if (a) the buyer has a valid
#     sigma_share_b and (b) buyer_total_shock_{b,t} is defined.
###############################################################################

rm(list = ls())

library(data.table)
library(dplyr)
library(haven)

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

YEAR_LO <- 2005L
YEAR_HI <- 2022L

contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)

add_phase5 <- function(dt) {
  dt[, phase5 := factor(fcase(
    year %in% 2005:2007, "I",
    year %in% 2008:2012, "II",
    year %in% 2013:2017, "III pre-MSR",
    year %in% 2018:2020, "III post-MSR",
    year >= 2021,        "IV"
  ), levels = c("I", "II", "III pre-MSR", "III post-MSR", "IV"))]
  dt
}

# ---------------------------------------------------------------------------
# 1. Load raw B2B + Annual Accounts NACE crosswalk + firm exposure
# ---------------------------------------------------------------------------
cat("Loading b2b_selected_sample, firm_exposure, Annual Accounts NACE...\n")

load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)

setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "corr_sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(corr_sales) & corr_sales > 0]
cat("B2B rows after year + positive-flow filter:", nrow(b2b), "\n")

b2b <- b2b[!(seller %in% contaminated_vats & year >= 2021)]
b2b <- b2b[!(buyer  %in% contaminated_vats & year >= 2021)]
cat("B2B rows after contaminated-VAT drop:", nrow(b2b), "\n")

aa_path <- file.path(RAW_DATA, "NBB", "Annual_Accounts_MASTER_ANO.dta")
aa <- as.data.table(read_dta(aa_path,
                             col_select = c("vat_ano", "year", "nace5d")))
setnames(aa, "vat_ano", "vat")
aa[, year := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa <- unique(aa[, .(vat, year, nace4d)])

seller_nace <- copy(aa); setnames(seller_nace, c("vat", "nace4d"),
                                  c("seller", "seller_nace4d"))
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
n_drop <- sum(is.na(b2b$seller_nace4d))
cat(sprintf("B2B rows missing seller NACE 4d (dropped): %d (%.2f%%)\n",
            n_drop, 100 * n_drop / nrow(b2b)))
b2b <- b2b[!is.na(seller_nace4d)]

# firm_exposure -> set of EUTL-matched ETS firms (sellers we tag as ETS)
load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))   # firm_exposure
ets_vats <- unique(firm_exposure$vat[!is.na(firm_exposure$cost_share_total)])
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

# ETS-treated NACE 4d set: any NACE 4d that contains at least one ETS seller
reg_nace4d <- b2b[seller_is_ets == 1, unique(seller_nace4d)]
b2b[, seller_in_reg_nace4d := as.integer(seller_nace4d %in% reg_nace4d)]
cat(sprintf("ETS-treated NACE 4d codes: %d\n", length(reg_nace4d)))

b2b <- add_phase5(b2b)

# ---------------------------------------------------------------------------
# 2. M1, M2: buyer-year input-cost shares
# ---------------------------------------------------------------------------
cat("\n=== M1 + M2: buyer-year input-cost shares ===\n")

buyer_year <- b2b[, .(
  total_inputs           = sum(corr_sales),
  inputs_from_reg_nace4d = sum(corr_sales * seller_in_reg_nace4d),
  inputs_from_ets_firms  = sum(corr_sales * seller_is_ets)
), by = .(buyer, year, phase5)]
buyer_year[, share_reg_nace4d := inputs_from_reg_nace4d / total_inputs]
buyer_year[, share_ets_firms  := inputs_from_ets_firms  / total_inputs]

m1 <- buyer_year[, .(
  n_buyer_years = .N,
  n_buyers      = uniqueN(buyer),
  share_zero    = mean(share_reg_nace4d == 0),
  p50           = quantile(share_reg_nace4d, 0.50),
  p75           = quantile(share_reg_nace4d, 0.75),
  p90           = quantile(share_reg_nace4d, 0.90),
  p95           = quantile(share_reg_nace4d, 0.95),
  p99           = quantile(share_reg_nace4d, 0.99),
  mean          = mean(share_reg_nace4d),
  sales_wmean   = sum(share_reg_nace4d * total_inputs) / sum(total_inputs)
), by = phase5][order(phase5)]

m2 <- buyer_year[, .(
  n_buyer_years = .N,
  n_buyers      = uniqueN(buyer),
  share_zero    = mean(share_ets_firms == 0),
  p50           = quantile(share_ets_firms, 0.50),
  p75           = quantile(share_ets_firms, 0.75),
  p90           = quantile(share_ets_firms, 0.90),
  p95           = quantile(share_ets_firms, 0.95),
  p99           = quantile(share_ets_firms, 0.99),
  mean          = mean(share_ets_firms),
  sales_wmean   = sum(share_ets_firms * total_inputs) / sum(total_inputs)
), by = phase5][order(phase5)]

cat("\n--- M1: share of input cost from ETS-treated NACE 4d ---\n")
print(m1, digits = 4)
cat("\n--- M2: share of input cost from ETS-treated firms ---\n")
print(m2, digits = 4)

fwrite(m1, file.path(OUTPUT_TAB, "phase5_M1_buyer_share_regulated_nace4d.csv"))
fwrite(m2, file.path(OUTPUT_TAB, "phase5_M2_buyer_share_ets_firms.csv"))

# ---------------------------------------------------------------------------
# 3. M3: number of suppliers per buyer × ETS-NACE-4d × year
# ---------------------------------------------------------------------------
cat("\n=== M3: number of suppliers per buyer × ETS-NACE-4d × year ===\n")

cell <- b2b[seller_in_reg_nace4d == 1,
            .(n_suppliers = uniqueN(seller),
              cell_spend  = sum(corr_sales)),
            by = .(buyer, seller_nace4d, year, phase5)]

m3 <- cell[, .(
  n_cells               = .N,
  n_buyers_distinct     = uniqueN(buyer),
  n_nace4d_distinct     = uniqueN(seller_nace4d),
  share_with_one_supp   = mean(n_suppliers == 1),
  share_with_le_two     = mean(n_suppliers <= 2),
  p50                   = quantile(n_suppliers, 0.50),
  p75                   = quantile(n_suppliers, 0.75),
  p90                   = quantile(n_suppliers, 0.90),
  p95                   = quantile(n_suppliers, 0.95),
  p99                   = quantile(n_suppliers, 0.99),
  mean                  = mean(n_suppliers),
  spend_wmean           = sum(n_suppliers * cell_spend) / sum(cell_spend)
), by = phase5][order(phase5)]

print(m3, digits = 4)
fwrite(m3, file.path(OUTPUT_TAB, "phase5_M3_n_suppliers_per_regulated_nace4d.csv"))

# ---------------------------------------------------------------------------
# 4. M7: buyer-year signal-to-noise distribution
#    Numerator   = buyer_total_shock_{b,t}
#                = sum_{j ∈ ETS} pair_shock_total_{j,b,t}
#                = sum_{j ∈ ETS} firm_cost_share_{j,t} × (corr_sales_{j,b,t} /
#                                                        total_inputs_{b,t})
#    Denominator = sigma_share_b
#                = within-buyer SD of Δlog(inputs_VAT_{b,t} / turnover_VAT_{b,t})
#                  on the 2005--2019 window (matches phase5_shock_benchmarks.R).
# ---------------------------------------------------------------------------
cat("\n=== M7: buyer-year signal-to-noise distribution ===\n")

# 4a. Buyer-year denominator: total_inputs from B2B (already computed in
# buyer_year) + buyer_total_shock numerator from firm_cost_share × pair share.
# Use buyer's TOTAL-INPUTS-from-B2B as the denominator for pair_shock_total
# (matches phase5_pair_shock_magnitude.R Moment 4c on the b2b_cdgm_panel,
# rebuilt here on the broader b2b_selected_sample).
firm_cs <- as.data.table(firm_exposure)[, .(seller = vat, year, cost_share_total)]
firm_cs <- firm_cs[!is.na(cost_share_total)]

ets_b2b <- merge(b2b[seller_is_ets == 1], firm_cs, by = c("seller", "year"))
ets_b2b <- merge(ets_b2b,
                 buyer_year[, .(buyer, year, total_inputs)],
                 by = c("buyer", "year"))
ets_b2b[, pair_shock_total := cost_share_total * (corr_sales / total_inputs)]

bts <- ets_b2b[, .(buyer_total_shock = sum(pair_shock_total)),
               by = .(buyer, year)]
bts <- merge(buyer_year[, .(buyer, year, phase5)],
             bts, by = c("buyer", "year"), all.x = TRUE)
bts[is.na(buyer_total_shock), buyer_total_shock := 0]

# 4b. sigma_share_b on 2005--2019 from inputs_VAT / turnover_VAT
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa_more <- as.data.table(df_annual_accounts_more_selected_sample)
rm(df_annual_accounts_more_selected_sample)
setnames(aa_more, "vat_ano", "buyer", skip_absent = TRUE)

aa_more <- aa_more[year %between% c(YEAR_LO, 2019L) &
                   !is.na(inputs_VAT) & !is.na(turnover_VAT) &
                   inputs_VAT > 0 & turnover_VAT > 0]
aa_more[, share := inputs_VAT / turnover_VAT]
aa_more[, log_share := log(share)]
setorder(aa_more, buyer, year)
aa_more[, dlog_share := log_share - shift(log_share),
        by = buyer]

sigma_share <- aa_more[!is.na(dlog_share),
                       .(sigma_share_b = sd(dlog_share),
                         n_obs         = .N),
                       by = buyer]
sigma_share <- sigma_share[n_obs >= 4 & sigma_share_b > 0]
cat(sprintf("Buyers with sigma_share defined (n_obs >= 4, 2005--2019): %d\n",
            nrow(sigma_share)))

# 4c. Join + compute SNR
snr <- merge(bts, sigma_share[, .(buyer, sigma_share_b)],
             by = "buyer")
snr[, signal_to_noise := buyer_total_shock / sigma_share_b]

m7 <- snr[, .(
  n_buyer_years     = .N,
  n_buyers          = uniqueN(buyer),
  share_zero        = mean(signal_to_noise == 0),
  p50               = quantile(signal_to_noise, 0.50),
  p75               = quantile(signal_to_noise, 0.75),
  p90               = quantile(signal_to_noise, 0.90),
  p95               = quantile(signal_to_noise, 0.95),
  p99               = quantile(signal_to_noise, 0.99),
  mean              = mean(signal_to_noise),
  share_above_1sd   = mean(signal_to_noise >= 1),
  share_above_0p5sd = mean(signal_to_noise >= 0.5)
), by = phase5][order(phase5)]

print(m7, digits = 4)
fwrite(m7, file.path(OUTPUT_TAB, "phase5_M7_buyer_year_signal_to_noise.csv"))

# ---------------------------------------------------------------------------
# 5. Summary text file
# ---------------------------------------------------------------------------
sink(file.path(OUTPUT_TAB, "phase5_buyer_input_shock_summary.txt"))
cat("=== M1: share of buyer-year input cost from ETS-treated NACE 4d ===\n")
print(m1, digits = 4)
cat("\n=== M2: share of buyer-year input cost from ETS-treated firms ===\n")
print(m2, digits = 4)
cat("\n=== M3: number of suppliers per buyer × ETS-NACE-4d × year ===\n")
print(m3, digits = 4)
cat("\n=== M7: buyer-year signal-to-noise distribution ===\n")
print(m7, digits = 4)
cat("\n=== Already on disk (referenced, not recomputed) ===\n")
cat("M4 pair-shock         -> phase5_moment4_pair_shock_distribution.csv\n")
cat("M5 pair-shock-total   -> phase5_moment4c_pair_shock_total_distribution.csv\n")
cat("M6 buyer-total-shock  -> phase5_moment4a_buyer_total_shock_distribution.csv\n")
sink()

cat("\nDone. Outputs in:", OUTPUT_TAB, "\n")
