###############################################################################
# phase5_shock_benchmarks.R
#
# PURPOSE:
#   Plan A, Moment 5 (per SHOCK_AND_SUBSTITUTION_PLAN.md).
#
#   Calibrate the magnitude of the pair-shock against benchmarks of "what
#   cost difference plausibly induces a sourcing switch in normal trade."
#
#   PRIMARY MEASURE: directly-declared input cost from VAT returns
#   (inputs_VAT in annual_accounts_more_selected_sample.RData), NOT the
#   accounting-derived `revenue - value_added` measure used in the prior
#   version of this script. The accounting measure conflates revenue
#   volatility (prices, demand shocks, inventory drawdowns) with input-cost
#   volatility, inflating sigma_b. inputs_VAT is what the firm actually
#   reported paying for inputs in year t -- the right concept for the
#   benchmark question.
#
#   ROBUSTNESS: domestic input cost from firm_year_domestic_input_cost.RData
#   (B2B-aggregated buyer-side total). The two should track each other once
#   imports are accounted for; gap = imports, mostly.
#
#   PERIODS: report sigma_b for three windows:
#     - 2005-2019 (pre-Phase-IV; clean noise floor for the comparison)
#     - 2019-2022 (during the Phase-IV / pandemic shock window; contaminated)
#     - 2005-2022 (pooled; sanity)
#
#   BENCHMARKS:
#     (b) sigma_b distribution per buyer in the B2B leakage panel.
#     (c) Heise 2024 (AER) calibrated FX shock magnitude.
#     (a) cross-source-country price gap -- DEFERRED (needs customs unit
#         values, Plan B Test F prep).
#
# INPUT:
#   ${PROC_DATA}/annual_accounts_more_selected_sample.RData
#     (df_annual_accounts_more_selected_sample; columns include vat_ano,
#      year, inputs_VAT, turnover_VAT, nace5d)
#   ${PROC_DATA}/firm_year_domestic_input_cost.RData
#     (firm_year_domestic_input_cost; vat, year, input_cost)
#   ${PROC_DATA}/b2b_cdgm_panel.RData (panel) -- for buyer set + buyer NACE
#
# OUTPUT:
#   output/tables/phase5_moment5_buyer_volatility_inputsVAT.csv
#   output/tables/phase5_moment5_buyer_volatility_by_nace2d.csv
#   output/tables/phase5_moment5_inputsVAT_vs_domestic_check.csv
#   output/tables/phase5_moment5_benchmarks_summary.txt
#
# CAVEATS:
#   - inputs_VAT reflects nominal input expenditure. Inflation is part of
#     the buyer's actual cost noise floor and SHOULD be included for the
#     benchmark question (a buyer absorbing a 5% input-price shock still
#     has to pay it). Pre-2020 vs post-2019 split separates the
#     low-inflation noise floor from the high-inflation Phase IV noise.
#   - Buyers without inputs_VAT in the underlying VAT data fall back to
#     `inputs_VAT == NA` -- dropped from sigma_b. Worth checking coverage.
###############################################################################

rm(list = ls())

library(dplyr)
library(stringr)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load ----
cat("Loading annual accounts (more_selected with VAT-declared inputs)...\n")
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- df_annual_accounts_more_selected_sample
rm(df_annual_accounts_more_selected_sample)

cat("Loading firm-year domestic input cost...\n")
load(file.path(PROC_DATA, "firm_year_domestic_input_cost.RData"))

cat("Loading B2B panel (for buyer set)...\n")
load(file.path(PROC_DATA, "b2b_cdgm_panel.RData"))

# ---- Buyer set: VATs that appear as buyers in the B2B leakage panel ----
b2b_buyers <- panel %>% distinct(buyer) %>% pull(buyer)
cat(sprintf("Distinct buyers in B2B panel: %d\n", length(b2b_buyers)))

# ---- Restrict annual accounts to B2B buyers, build inputs_VAT panel ----
#
# `vat_ano` in annual_accounts_more is the same identifier as `vat` (B2B
# uses `seller`/`buyer` columns; firm_year_belgian_euets uses `vat`).
# All are SHA256 hashes of the same underlying VAT.
cat("Building inputs_VAT panel for B2B buyers...\n")

aa_inputs <- aa %>%
  rename(vat = vat_ano) %>%
  filter(vat %in% b2b_buyers) %>%
  select(vat, year, inputs_VAT, turnover_VAT, nace5d) %>%
  mutate(nace2d = str_sub(as.character(nace5d), 1, 2)) %>%
  filter(!is.na(inputs_VAT), inputs_VAT > 0)

cat(sprintf("Buyer-year obs with positive inputs_VAT: %d\n", nrow(aa_inputs)))
cat(sprintf("Distinct buyers covered: %d\n",
            n_distinct(aa_inputs$vat)))
cat(sprintf("Year range: %d-%d\n",
            min(aa_inputs$year), max(aa_inputs$year)))

# ===========================================================================
# Compute sigma_b for three windows
# ===========================================================================
#
# Two parallel measures:
#
#   (1) sigma_b_inputs    = sd_t( Δlog(inputs_VAT_{b,t}) )
#       Mixes scale variation (firm growing/shrinking) with input-cost
#       variation. The "raw" buyer-cost-volatility number.
#
#   (2) sigma_b_share     = sd_t( Δlog(inputs_VAT_{b,t} / turnover_VAT_{b,t}) )
#                         = sd_t( Δlog(inputs) - Δlog(revenue) )
#       The variation in the input-cost-per-unit-of-revenue ratio. If
#       inputs and revenue scale together with quantity, this ratio
#       strips out scale and isolates the input-cost-structure component.
#       This is the right benchmark for an ETS shock, which is a pure
#       price shock and doesn't depend on the firm's quantity decisions.
#
# Both are computed on consecutive-year differences within firm.
# Drop differences that span >1 year. Require >=3 differences for the
# 2005-2019 window (long); >=2 for the short 2019-2022 window (only 3
# differences possible at most). Pooled requires >=3.
# ===========================================================================
cat("\n=== Computing sigma_b -- raw inputs_VAT, three windows ===\n")

aa_diffs <- aa_inputs %>%
  arrange(vat, year) %>%
  group_by(vat) %>%
  mutate(dlog = log(inputs_VAT) - log(lag(inputs_VAT)),
         dyear = year - lag(year)) %>%
  ungroup() %>%
  filter(!is.na(dlog), dyear == 1)

cat(sprintf("Buyer-year diffs on inputs_VAT (consec): %d\n", nrow(aa_diffs)))

# ── Approach A: inputs_VAT / turnover_VAT ratio ─────────────────────────
# Strip out scale variation. Construct the input-cost-share-of-revenue
# series and take Δlog, which equals Δlog(inputs) − Δlog(revenue).

cat("\n=== Computing sigma_b -- inputs_VAT / turnover_VAT ratio ===\n")

aa_share <- aa_inputs %>%
  filter(!is.na(turnover_VAT), turnover_VAT > 0) %>%
  mutate(input_share = inputs_VAT / turnover_VAT)

cat(sprintf("Firm-year obs with input_share defined: %d\n", nrow(aa_share)))
cat(sprintf("  (input_share quantile 25/50/75): %.3f / %.3f / %.3f\n",
            quantile(aa_share$input_share, 0.25),
            quantile(aa_share$input_share, 0.50),
            quantile(aa_share$input_share, 0.75)))

aa_share_diffs <- aa_share %>%
  arrange(vat, year) %>%
  group_by(vat) %>%
  mutate(dlog = log(input_share) - log(lag(input_share)),
         dyear = year - lag(year)) %>%
  ungroup() %>%
  filter(!is.na(dlog), dyear == 1)

cat(sprintf("Buyer-year diffs on inputs/revenue ratio (consec): %d\n",
            nrow(aa_share_diffs)))

# Helper to compute sigma_b on a window
compute_sigma_b <- function(diffs, year_min, year_max, min_n) {
  diffs %>%
    filter(year >= year_min, year <= year_max) %>%
    group_by(vat) %>%
    summarise(n_diffs = n(),
              sigma_b = sd(dlog, na.rm = TRUE),
              mean_dlog = mean(dlog, na.rm = TRUE),
              .groups = "drop") %>%
    filter(n_diffs >= min_n, !is.na(sigma_b), sigma_b > 0)
}

# Helper to compute the "typical year-on-year change" |Δlog| on a window.
#
# sigma_b describes the SPREAD of year-on-year changes around the firm's
# own mean. For the more direct "how big is a typical year-on-year change"
# question, the right statistic is median(|Δlog|).
#
# Returns:
#   - pool_median_abs : pooled median of |Δlog| across ALL firm-year diffs
#                       in the window. Answers "the typical (firm-year)
#                       year-on-year |change| in input costs is X%"
#   - cross_firm_med_within_firm_med_abs : for each firm, compute its own
#                       median of |Δlog|; then take the median across firms.
#                       Answers "the typical firm's typical year has |change| X%"
compute_typical_change <- function(diffs, year_min, year_max, min_n) {
  d <- diffs %>%
    filter(year >= year_min, year <= year_max) %>%
    mutate(abs_dlog = abs(dlog))

  pooled <- tibble(
    n_firm_years = nrow(d),
    n_distinct_firms = n_distinct(d$vat),
    pool_median_abs = median(d$abs_dlog, na.rm = TRUE),
    pool_mean_abs   = mean(d$abs_dlog, na.rm = TRUE)
  )

  per_firm_meds <- d %>%
    group_by(vat) %>%
    summarise(n_diffs = n(),
              firm_median_abs = median(abs_dlog, na.rm = TRUE),
              firm_mean_abs   = mean(abs_dlog, na.rm = TRUE),
              .groups = "drop") %>%
    filter(n_diffs >= min_n)

  cross_firm <- tibble(
    n_buyers = nrow(per_firm_meds),
    cross_firm_median_within_firm_median_abs = median(per_firm_meds$firm_median_abs),
    cross_firm_median_within_firm_mean_abs   = median(per_firm_meds$firm_mean_abs)
  )

  bind_cols(pooled, cross_firm)
}

# 2005-2019: pre-pandemic, pre-Phase-IV. Clean noise floor.
sigma_pre  <- compute_sigma_b(aa_diffs, 2005, 2019, min_n = 3)
# 2019-2022: pandemic + Phase-IV bite. Contaminated noise floor.
sigma_post <- compute_sigma_b(aa_diffs, 2019, 2022, min_n = 2)
# 2005-2022: pooled.
sigma_full <- compute_sigma_b(aa_diffs, 2005, 2022, min_n = 3)

cat(sprintf("Buyers with usable sigma_b (2005-2019, n_diffs>=3): %d\n", nrow(sigma_pre)))
cat(sprintf("Buyers with usable sigma_b (2019-2022, n_diffs>=2): %d\n", nrow(sigma_post)))
cat(sprintf("Buyers with usable sigma_b (2005-2022, n_diffs>=3): %d\n", nrow(sigma_full)))

# sigma_b on inputs/revenue ratio (purified of scale)
sigma_share_pre  <- compute_sigma_b(aa_share_diffs, 2005, 2019, min_n = 3)
sigma_share_post <- compute_sigma_b(aa_share_diffs, 2019, 2022, min_n = 2)
sigma_share_full <- compute_sigma_b(aa_share_diffs, 2005, 2022, min_n = 3)

cat(sprintf("Buyers with usable sigma_share (2005-2019, n_diffs>=3): %d\n", nrow(sigma_share_pre)))
cat(sprintf("Buyers with usable sigma_share (2019-2022, n_diffs>=2): %d\n", nrow(sigma_share_post)))
cat(sprintf("Buyers with usable sigma_share (2005-2022, n_diffs>=3): %d\n", nrow(sigma_share_full)))

# Compute the more directly interpretable typical-change statistics
typical_pre  <- compute_typical_change(aa_diffs, 2005, 2019, min_n = 3)
typical_post <- compute_typical_change(aa_diffs, 2019, 2022, min_n = 2)
typical_full <- compute_typical_change(aa_diffs, 2005, 2022, min_n = 3)

typical_table <- bind_rows(
  typical_pre  %>% mutate(window = "2005-2019 (pre-shock)"),
  typical_post %>% mutate(window = "2019-2022 (Phase IV / pandemic)"),
  typical_full %>% mutate(window = "2005-2022 (pooled)")
) %>% select(window, everything())

cat("\n=== Typical year-on-year |change| in input costs ===\n")
cat("(median |Δlog|, pooled across firm-years and via two-stage cross-firm median)\n")
print(as.data.frame(typical_table), digits = 4)

write.csv(typical_table,
          file.path(OUTPUT_TAB, "phase5_moment5_typical_change.csv"),
          row.names = FALSE)
cat("Saved:", file.path(OUTPUT_TAB, "phase5_moment5_typical_change.csv"), "\n")

# Same typical-change calculation on inputs/revenue ratio
typical_share_pre  <- compute_typical_change(aa_share_diffs, 2005, 2019, min_n = 3)
typical_share_post <- compute_typical_change(aa_share_diffs, 2019, 2022, min_n = 2)
typical_share_full <- compute_typical_change(aa_share_diffs, 2005, 2022, min_n = 3)

typical_share_table <- bind_rows(
  typical_share_pre  %>% mutate(window = "2005-2019 (pre-shock)"),
  typical_share_post %>% mutate(window = "2019-2022 (Phase IV / pandemic)"),
  typical_share_full %>% mutate(window = "2005-2022 (pooled)")
) %>% select(window, everything())

cat("\n=== Typical |Δlog| on inputs/revenue ratio (scale-stripped) ===\n")
print(as.data.frame(typical_share_table), digits = 4)

write.csv(typical_share_table,
          file.path(OUTPUT_TAB, "phase5_moment5_typical_change_input_share.csv"),
          row.names = FALSE)
cat("Saved:", file.path(OUTPUT_TAB, "phase5_moment5_typical_change_input_share.csv"), "\n")

# Distribution table
qtab <- function(x, label) {
  q <- quantile(x, c(.10, .25, .50, .75, .90, .95), na.rm = TRUE)
  data.frame(window = label,
             n_buyers = length(x),
             p10 = q[1], p25 = q[2], p50 = q[3], p75 = q[4],
             p90 = q[5], p95 = q[6],
             mean = mean(x, na.rm = TRUE))
}

vol_table <- bind_rows(
  qtab(sigma_pre$sigma_b,  "2005-2019 (pre-shock)"),
  qtab(sigma_post$sigma_b, "2019-2022 (Phase IV / pandemic)"),
  qtab(sigma_full$sigma_b, "2005-2022 (pooled)")
) %>% as_tibble()

cat("\nCross-buyer distribution of sigma_b (within-firm sd of Δlog inputs_VAT):\n")
print(vol_table, digits = 4)

write.csv(vol_table,
          file.path(OUTPUT_TAB, "phase5_moment5_buyer_volatility_inputsVAT.csv"),
          row.names = FALSE)

# ---- Cross-buyer distribution of sigma_share (Δlog of inputs/revenue ratio) ----
vol_share_table <- bind_rows(
  qtab(sigma_share_pre$sigma_b,  "2005-2019 (pre-shock)"),
  qtab(sigma_share_post$sigma_b, "2019-2022 (Phase IV / pandemic)"),
  qtab(sigma_share_full$sigma_b, "2005-2022 (pooled)")
) %>% as_tibble()

cat("\nCross-buyer distribution of sigma_share (within-firm sd of Δlog inputs_VAT/turnover_VAT):\n")
cat("(scale-stripped: removes variation common to inputs and revenue;\n")
cat(" isolates input-cost-structure component, the right benchmark for ETS shock)\n")
print(vol_share_table, digits = 4)

write.csv(vol_share_table,
          file.path(OUTPUT_TAB, "phase5_moment5_buyer_volatility_input_share.csv"),
          row.names = FALSE)

# ---- By buyer NACE 2d ----
buyer_nace_lookup <- panel %>% distinct(buyer, buyer_nace2d)

vol_by_nace <- function(sigma_df, label) {
  sigma_df %>%
    left_join(buyer_nace_lookup, by = c("vat" = "buyer")) %>%
    filter(!is.na(buyer_nace2d)) %>%
    group_by(buyer_nace2d) %>%
    summarise(window = label,
              n_buyers = n(),
              p25  = quantile(sigma_b, 0.25),
              p50  = quantile(sigma_b, 0.50),
              p75  = quantile(sigma_b, 0.75),
              p90  = quantile(sigma_b, 0.90),
              mean = mean(sigma_b),
              .groups = "drop") %>%
    select(window, buyer_nace2d, everything()) %>%
    arrange(desc(p50))
}

vol_nace_table <- bind_rows(
  vol_by_nace(sigma_pre,  "2005-2019"),
  vol_by_nace(sigma_post, "2019-2022"),
  vol_by_nace(sigma_full, "2005-2022")
)

cat("\n=== sigma_b by buyer NACE 2d (raw inputs_VAT) ===\n")
print(as.data.frame(vol_nace_table), digits = 4)

write.csv(vol_nace_table,
          file.path(OUTPUT_TAB, "phase5_moment5_buyer_volatility_by_nace2d.csv"),
          row.names = FALSE)

# Same NACE-2d split for the scale-stripped sigma_share
vol_share_nace_table <- bind_rows(
  vol_by_nace(sigma_share_pre,  "2005-2019"),
  vol_by_nace(sigma_share_post, "2019-2022"),
  vol_by_nace(sigma_share_full, "2005-2022")
)

cat("\n=== sigma_share by buyer NACE 2d (scale-stripped inputs/revenue ratio) ===\n")
print(as.data.frame(vol_share_nace_table), digits = 4)

write.csv(vol_share_nace_table,
          file.path(OUTPUT_TAB, "phase5_moment5_buyer_volatility_input_share_by_nace2d.csv"),
          row.names = FALSE)

# ===========================================================================
# Sanity check -- inputs_VAT vs firm_year_domestic_input_cost
# ===========================================================================
#
# inputs_VAT is total declared inputs (domestic + imports);
# firm_year_domestic_input_cost is the domestic-only B2B-aggregated total.
# Their ratio (domestic / total) should be < 1 for buyers that import; for
# buyers with no imports it should be ~1. Big discrepancies indicate
# coverage issues.
# ===========================================================================
cat("\n=== Sanity check: inputs_VAT vs domestic_input_cost ===\n")

both <- aa_inputs %>%
  inner_join(firm_year_domestic_input_cost,
             by = c("vat", "year")) %>%
  mutate(domestic_share = input_cost / inputs_VAT)

ds_summary <- both %>%
  summarise(n_obs = n(),
            n_distinct_firms = n_distinct(vat),
            p25 = quantile(domestic_share, 0.25, na.rm = TRUE),
            p50 = quantile(domestic_share, 0.50, na.rm = TRUE),
            p75 = quantile(domestic_share, 0.75, na.rm = TRUE),
            p90 = quantile(domestic_share, 0.90, na.rm = TRUE),
            mean = mean(domestic_share, na.rm = TRUE),
            pct_above_one = 100 * mean(domestic_share > 1, na.rm = TRUE))

cat("Distribution of domestic_share = input_cost / inputs_VAT:\n")
print(as.data.frame(ds_summary), digits = 4)

write.csv(ds_summary,
          file.path(OUTPUT_TAB, "phase5_moment5_inputsVAT_vs_domestic_check.csv"),
          row.names = FALSE)

# ===========================================================================
# (b)-comparator: NACE-4d-specific scale-stripped sigma
# ===========================================================================
#
# For comparing pair_shock (denominator = NACE-4d-specific input spend)
# against a noise floor on the same denominator, compute:
#
#   nace_share_{b,n,t} = NACE-4d-spending_{b,n,t} / turnover_VAT_{b,t}
#   sigma_nace_{b,n}    = sd_t( Δlog(nace_share_{b,n,t}) )
#
# where NACE-4d-spending_{b,n,t} = Σ_{j in seller_nace4d == n} corr_sales_{j,b,t}
#
# This is the within-(buyer × NACE 4d) standard deviation of how much the
# buyer's spending in that NACE 4d swings as a fraction of their revenue.
# Apples-to-apples with pair_shock (option (b) in user's framing).
#
# Caveat: NACE-4d spending here uses domestic B2B-aggregated values from
# b2b_cdgm_panel; misses imports and intra-firm transactions in that NACE.
# This is the closest measurable proxy.
# ===========================================================================
cat("\n=== sigma_nace: scale-stripped sigma at (buyer x NACE 4d) level ===\n")

# Step 1: aggregate B2B to (buyer, seller_nace4d, year)
buyer_nace_year_spend <- panel %>%
  filter(corr_sales > 0) %>%
  group_by(buyer, seller_nace4d, year) %>%
  summarise(nace_spend = sum(corr_sales, na.rm = TRUE),
            buyer_nace2d = first(buyer_nace2d),
            .groups = "drop")

cat(sprintf("(buyer x NACE 4d x year) cells with positive spend: %d\n",
            nrow(buyer_nace_year_spend)))

# Step 2: divide by buyer's revenue (turnover_VAT)
buyer_revenue <- aa_inputs %>%
  filter(!is.na(turnover_VAT), turnover_VAT > 0) %>%
  select(vat, year, turnover_VAT)

buyer_nace_share <- buyer_nace_year_spend %>%
  left_join(buyer_revenue, by = c("buyer" = "vat", "year")) %>%
  filter(!is.na(turnover_VAT), turnover_VAT > 0, nace_spend > 0) %>%
  mutate(nace_share = nace_spend / turnover_VAT)

# Step 3: Δlog within (buyer × NACE 4d) over consec years
buyer_nace_diffs <- buyer_nace_share %>%
  arrange(buyer, seller_nace4d, year) %>%
  group_by(buyer, seller_nace4d) %>%
  mutate(dlog = log(nace_share) - log(lag(nace_share)),
         dyear = year - lag(year)) %>%
  ungroup() %>%
  filter(!is.na(dlog), dyear == 1)

cat(sprintf("(buyer x NACE 4d) consec-year diffs: %d\n", nrow(buyer_nace_diffs)))

# Step 4: sigma per (buyer × NACE 4d) cell
compute_sigma_nace <- function(diffs, year_min, year_max, min_n) {
  diffs %>%
    filter(year >= year_min, year <= year_max) %>%
    group_by(buyer, seller_nace4d, buyer_nace2d) %>%
    summarise(n_diffs = n(),
              sigma_nace = sd(dlog, na.rm = TRUE),
              .groups = "drop") %>%
    filter(n_diffs >= min_n, !is.na(sigma_nace), sigma_nace > 0)
}

sigma_nace_pre  <- compute_sigma_nace(buyer_nace_diffs, 2005, 2019, min_n = 3)
sigma_nace_post <- compute_sigma_nace(buyer_nace_diffs, 2019, 2022, min_n = 2)
sigma_nace_full <- compute_sigma_nace(buyer_nace_diffs, 2005, 2022, min_n = 3)

cat(sprintf("Cells with usable sigma_nace (2005-2019, n_diffs>=3): %d\n",
            nrow(sigma_nace_pre)))
cat(sprintf("Cells with usable sigma_nace (2019-2022, n_diffs>=2): %d\n",
            nrow(sigma_nace_post)))
cat(sprintf("Cells with usable sigma_nace (2005-2022, n_diffs>=3): %d\n",
            nrow(sigma_nace_full)))

# Step 5: cross-cell distribution
sigma_nace_table <- bind_rows(
  qtab(sigma_nace_pre$sigma_nace,  "2005-2019 (pre-shock)"),
  qtab(sigma_nace_post$sigma_nace, "2019-2022 (Phase IV / pandemic)"),
  qtab(sigma_nace_full$sigma_nace, "2005-2022 (pooled)")
) %>% as_tibble() %>% rename(n_cells = n_buyers)

cat("\nCross-cell distribution of sigma_nace at (buyer x NACE 4d) level:\n")
print(sigma_nace_table, digits = 4)

write.csv(sigma_nace_table,
          file.path(OUTPUT_TAB, "phase5_moment5_sigma_nace_distribution.csv"),
          row.names = FALSE)

# By BUYER NACE 2d (which downstream sectors face most/least NACE-4d-specific volatility)
sigma_nace_bynace_pre <- sigma_nace_pre %>%
  filter(!is.na(buyer_nace2d)) %>%
  group_by(buyer_nace2d) %>%
  summarise(n_cells = n(),
            p25  = quantile(sigma_nace, 0.25),
            p50  = quantile(sigma_nace, 0.50),
            p75  = quantile(sigma_nace, 0.75),
            p90  = quantile(sigma_nace, 0.90),
            mean = mean(sigma_nace),
            .groups = "drop") %>%
  arrange(desc(p50))

cat("\nsigma_nace by BUYER NACE 2d (2005-2019, pre-shock):\n")
print(as.data.frame(sigma_nace_bynace_pre), digits = 4)

write.csv(sigma_nace_bynace_pre,
          file.path(OUTPUT_TAB, "phase5_moment5_sigma_nace_by_buyer_nace2d.csv"),
          row.names = FALSE)

# Also compute sigma_b on the domestic-only series, full window, as
# robustness -- if conclusion changes between inputs_VAT and input_cost,
# something is off.
fy_diffs <- firm_year_domestic_input_cost %>%
  filter(vat %in% b2b_buyers, !is.na(input_cost), input_cost > 0) %>%
  arrange(vat, year) %>%
  group_by(vat) %>%
  mutate(dlog = log(input_cost) - log(lag(input_cost)),
         dyear = year - lag(year)) %>%
  ungroup() %>%
  filter(!is.na(dlog), dyear == 1)

sigma_dom <- fy_diffs %>%
  group_by(vat) %>%
  summarise(n_diffs = n(),
            sigma_b = sd(dlog, na.rm = TRUE),
            .groups = "drop") %>%
  filter(n_diffs >= 3, !is.na(sigma_b), sigma_b > 0)

dom_summary <- qtab(sigma_dom$sigma_b, "2002-2022 (domestic-only series, all years)")
cat("\nRobustness: sigma_b on domestic-only input_cost (firm_year_domestic_input_cost):\n")
print(dom_summary, digits = 4)

# ===========================================================================
# Heise 2024 FX-shock benchmark
# ===========================================================================
cat("\n=== Heise 2024 (AER) FX shock benchmark ===\n")

heise_sigma_xi      <- 0.066
heise_alpha         <- 0.444
heise_q_costshock   <- heise_sigma_xi * heise_alpha
heise_annual_shock  <- heise_q_costshock * sqrt(4)
heise_buyer_25pct   <- heise_annual_shock * 0.25

cat(sprintf("Heise quarterly sd of log e: %.3f\n", heise_sigma_xi))
cat(sprintf("Heise alpha (FX -> seller cost): %.3f\n", heise_alpha))
cat(sprintf("=> 1-sigma quarterly seller-cost shock: %.2f%%\n",
            100 * heise_q_costshock))
cat(sprintf("=> 1-sigma annualized seller-cost shock: %.2f%%\n",
            100 * heise_annual_shock))
cat(sprintf("=> Buyer-side at 25%% import share, annual: %.2f%%\n",
            100 * heise_buyer_25pct))

# ===========================================================================
# Combined readable summary
# ===========================================================================
sink(file.path(OUTPUT_TAB, "phase5_moment5_benchmarks_summary.txt"))

cat("================================================================\n")
cat("Plan A -- Moment 5: substitution-relevant benchmarks\n")
cat("Generated by analysis/phase5_shock_benchmarks.R\n")
cat("Primary measure: inputs_VAT (declared on VAT returns; not derived\n")
cat("from accounting revenue - value_added).\n")
cat("================================================================\n\n")

cat("Definition: sigma_b = within-firm sd of Δlog(inputs_VAT) over\n")
cat("consecutive years. Reports cross-buyer distribution of sigma_b for\n")
cat("three windows.\n\n")

cat("--------------------------------------------------------------\n")
cat("(b) sigma_b distribution by window -- inputs_VAT (raw)\n")
cat("    sigma_b = within-firm sd of Δlog(inputs_VAT) over consec years\n")
cat("    Mixes scale variation with input-cost-structure variation.\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(vol_table), digits = 4)
cat("\n")

cat("--------------------------------------------------------------\n")
cat("(b') sigma_share distribution -- inputs_VAT / turnover_VAT (scale-stripped)\n")
cat("    sigma_share = within-firm sd of Δlog(inputs_VAT / turnover_VAT)\n")
cat("                = within-firm sd of [Δlog(inputs) - Δlog(revenue)]\n")
cat("    Strips scale variation (firm growing/shrinking moves both inputs\n")
cat("    and revenue together). Isolates input-cost-structure component,\n")
cat("    the right benchmark for an ETS shock (which is a pure price shock).\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(vol_share_table), digits = 4)
cat("\n")

cat("--------------------------------------------------------------\n")
cat("Typical year-on-year |change| in input costs\n")
cat("    pool_median_abs = median |Δlog| pooled across all firm-years\n")
cat("    cross_firm_median_within_firm_median_abs = median across firms\n")
cat("        of each firm's median |Δlog|\n")
cat("--------------------------------------------------------------\n")
cat("On raw inputs_VAT:\n")
print(as.data.frame(typical_table), digits = 4)
cat("\n")
cat("On inputs_VAT / turnover_VAT (scale-stripped):\n")
print(as.data.frame(typical_share_table), digits = 4)
cat("\n")

cat("--------------------------------------------------------------\n")
cat("sigma_b by buyer NACE 2d (within window)\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(vol_nace_table), digits = 4)
cat("\n")

cat("--------------------------------------------------------------\n")
cat("Sanity: inputs_VAT vs firm_year_domestic_input_cost\n")
cat("(domestic-only B2B total, should be < inputs_VAT)\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(ds_summary), digits = 4)
cat("\nRobustness sigma_b on domestic-only series:\n")
print(as.data.frame(dom_summary), digits = 4)
cat("\n")

cat("--------------------------------------------------------------\n")
cat("(c) Heise 2024 (AER) calibrated FX shock benchmark\n")
cat("--------------------------------------------------------------\n")
cat(sprintf("Heise sigma_xi (quarterly): %.3f\n", heise_sigma_xi))
cat(sprintf("Heise alpha (FX -> seller cost): %.3f\n", heise_alpha))
cat(sprintf("=> 1-sigma quarterly seller-cost shock: %.2f%%\n",
            100 * heise_q_costshock))
cat(sprintf("=> 1-sigma annualized: %.2f%%\n",
            100 * heise_annual_shock))
cat(sprintf("=> Buyer-side at 25%% import share, annual: %.2f%%\n",
            100 * heise_buyer_25pct))

cat("\n--------------------------------------------------------------\n")
cat("(a) Cross-border alternative-source price gap -- DEFERRED\n")
cat("--------------------------------------------------------------\n")
cat("Requires customs unit-value rebuild (Plan B Test F prep).\n\n")

cat("================================================================\n")
cat("Reading: compare Phase IV TREATED pair-shock p90 (~2%, ~10% for\n")
cat("cement) against:\n")
cat("  - sigma_b 2005-2019 (clean pre-shock noise floor)\n")
cat("  - sigma_b 2019-2022 (realized noise during the test window)\n")
cat("  - Heise FX benchmark ~1.5%% buyer-side annual\n")
cat("If pair-shock <= sigma_b, the ETS shock is within noise and the\n")
cat("null leakage finding is uninterpretable for that buyer. If\n")
cat("pair-shock >> sigma_b, the null is informative.\n")
cat("================================================================\n")

sink()
cat("Saved:", file.path(OUTPUT_TAB, "phase5_moment5_benchmarks_summary.txt"), "\n")

cat("\nDone.\n")
