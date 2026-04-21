###############################################################################
# phase3_build_exposure_panel.R
#
# PURPOSE:
#   Build a firm-year panel of direct carbon-cost exposure for every ETS
#   firm-year 2005-2023, with three cost denominators:
#     - total_cost = (revenue - value_added) + wage_bill     [main]
#     - mat_inputs = (revenue - value_added)                 [alternative 1]
#     - revenue                                              [alternative 2]
#
#   Direct carbon-cost exposure:
#     carbon_cost_it  = max(emissions_it - allocated_free_it, 0) * EUA_t
#     cost_share_it   = carbon_cost_it / denominator_it
#
#   Also produce a NACE4d sector-year panel that aggregates firm-level
#   exposure using base-period revenue weights, for Task 2 (PPI pass-through).
#
# DATA:
#   - NBB_data/processed/firm_year_belgian_euets.RData
#   - data/processed/phase3_eua_prices.RData       (from phase3_eua_prices.R)
#   - data/processed/frozen_weights_exposure_panel.RData  (network exposure)
#
# OUTPUT:
#   - data/processed/phase3_firm_exposure.RData
#       firm_exposure    -- firm-year panel, all denominators
#   - data/processed/phase3_sector_exposure.RData
#       sector_exposure  -- NACE4d-year panel for pass-through regressions
#
# NOTES:
#   - We keep firm-years with denominator > 0; firm-years with bad (negative or
#     zero) denominators are flagged but dropped from cost_share calculations
#     for that denominator.
#   - `in_sample == 1` is required (matches the project's standard filter).
###############################################################################

rm(list = ls())

library(dplyr)
library(stringr)
library(tidyr)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load ----
cat("Loading data...\n")
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
load(file.path(OUT_DATA, "phase3_eua_prices.RData"))

# ===========================================================================
# 1. Firm-year exposure panel
# ===========================================================================
cat("\n=== Firm-year exposure panel ===\n")

firm_exposure <- firm_year_belgian_euets %>%
  filter(in_sample == 1) %>%
  left_join(eua_prices_annual %>% select(year, eua_price, phase),
            by = "year") %>%
  mutate(
    shortage      = pmax(emissions - allocated_free, 0),
    carbon_cost   = shortage * eua_price,
    mat_inputs    = revenue - value_added,
    total_cost    = mat_inputs + wage_bill,
    nace4d        = str_sub(nace5d, 1, 4),
    nace2d        = str_sub(nace5d, 1, 2)
  )

# Share denominators (NA where denominator <= 0)
firm_exposure <- firm_exposure %>%
  mutate(
    cost_share_total = ifelse(!is.na(total_cost)  & total_cost  > 0,
                              carbon_cost / total_cost,  NA_real_),
    cost_share_mat   = ifelse(!is.na(mat_inputs)  & mat_inputs  > 0,
                              carbon_cost / mat_inputs,  NA_real_),
    cost_share_rev   = ifelse(!is.na(revenue)     & revenue     > 0,
                              carbon_cost / revenue,     NA_real_)
  )

cat(sprintf("Rows (ETS firm-years in_sample): %d\n", nrow(firm_exposure)))
cat(sprintf("Years: %d-%d\n", min(firm_exposure$year), max(firm_exposure$year)))
cat(sprintf("Unique firms: %d\n", n_distinct(firm_exposure$vat)))

# Coverage by denominator
cat("\nCoverage by denominator:\n")
cat(sprintf("  cost_share_total defined: %d (%.1f%%)\n",
            sum(!is.na(firm_exposure$cost_share_total)),
            100 * mean(!is.na(firm_exposure$cost_share_total))))
cat(sprintf("  cost_share_mat   defined: %d (%.1f%%)\n",
            sum(!is.na(firm_exposure$cost_share_mat)),
            100 * mean(!is.na(firm_exposure$cost_share_mat))))
cat(sprintf("  cost_share_rev   defined: %d (%.1f%%)\n",
            sum(!is.na(firm_exposure$cost_share_rev)),
            100 * mean(!is.na(firm_exposure$cost_share_rev))))

# Summary by phase (main denom)
cat("\nSummary of cost_share_total by phase (ETS firm-years):\n")
print(as.data.frame(
  firm_exposure %>%
    group_by(phase) %>%
    summarise(
      n_firm_years = sum(!is.na(cost_share_total)),
      pct_positive = 100 * mean(cost_share_total > 0, na.rm = TRUE),
      mean_share   = mean(cost_share_total, na.rm = TRUE),
      median_share = median(cost_share_total, na.rm = TRUE),
      p90_share    = quantile(cost_share_total, 0.9, na.rm = TRUE),
      p99_share    = quantile(cost_share_total, 0.99, na.rm = TRUE),
      .groups = "drop"
    )
))

# ---- Save firm-year panel ----
save(firm_exposure, file = file.path(OUT_DATA, "phase3_firm_exposure.RData"))
cat("\nSaved firm-year panel to:",
    file.path(OUT_DATA, "phase3_firm_exposure.RData"), "\n")

# ===========================================================================
# 2. Sector-year (NACE4d) exposure panel for Task 2
# ===========================================================================
#
# For each NACE4d sector-year we compute:
#   total_carbon_cost_st  = sum of carbon_cost over ETS firms in (s,t)
#   total_cost_st         = sum of total_cost over ETS firms in (s,t)
#   sector_exposure_st    = total_carbon_cost_st / total_cost_st
#
# This is the "ETS exposure intensity" of the sector: what share of ETS firms'
# cost base went to EUAs. It is zero for sectors without ETS firms.
#
# We ALSO compute a revenue-weighted average of firm-level cost_share_total,
# which may differ slightly (and is less influenced by which firms happen to
# have a big revenue that year).
# ===========================================================================
cat("\n=== Sector-year exposure panel ===\n")

sector_direct <- firm_exposure %>%
  filter(!is.na(nace4d), !is.na(total_cost), total_cost > 0) %>%
  group_by(nace4d, nace2d, year, phase) %>%
  summarise(
    n_ets_firms       = n_distinct(vat),
    total_emissions   = sum(emissions, na.rm = TRUE),
    total_shortage    = sum(shortage, na.rm = TRUE),
    total_free        = sum(allocated_free, na.rm = TRUE),
    total_carbon_cost = sum(carbon_cost, na.rm = TRUE),
    total_cost_denom  = sum(total_cost, na.rm = TRUE),
    total_mat_denom   = sum(pmax(mat_inputs, 0), na.rm = TRUE),
    total_revenue     = sum(revenue, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    exposure_direct_total = total_carbon_cost / total_cost_denom,
    exposure_direct_mat   = ifelse(total_mat_denom > 0,
                                   total_carbon_cost / total_mat_denom, NA_real_),
    exposure_direct_rev   = ifelse(total_revenue > 0,
                                   total_carbon_cost / total_revenue, NA_real_)
  )

# ===========================================================================
# Base-period-fixed denominator (diagnostic)
#
# The time-varying cost denominator in exposure_direct is partly endogenous:
# when input costs rise in a sector, total_cost_denom rises, exposure falls,
# AND the sector's PPI tends to rise because it's passing input cost shocks
# through. That generates a negative mechanical correlation between exposure
# and PPI that has nothing to do with ETS pass-through.
#
# Fix: compute a fixed base-period (2010-2012) average denominator per
# sector. All time variation in exposure_alt_* then comes from
# shortage_{s,t} * EUA_t, which is independent of current cost inflation.
#
# For sectors that have no ETS firms in 2010-2012, we fall back to the
# earliest available 3-year window; if still nothing, exposure_alt is NA.
# ===========================================================================
base_years_denom <- 2010:2012

base_denom <- sector_direct %>%
  filter(year %in% base_years_denom) %>%
  group_by(nace4d) %>%
  summarise(
    base_cost_denom = mean(total_cost_denom, na.rm = TRUE),
    base_mat_denom  = mean(total_mat_denom,  na.rm = TRUE),
    base_revenue    = mean(total_revenue,    na.rm = TRUE),
    n_base_years    = n(),
    .groups = "drop"
  )

# Fallback: earliest 3-year window for sectors without 2010-2012 coverage
needs_fallback <- sector_direct %>%
  distinct(nace4d) %>%
  anti_join(base_denom, by = "nace4d") %>%
  pull(nace4d)

if (length(needs_fallback) > 0) {
  fallback <- sector_direct %>%
    filter(nace4d %in% needs_fallback) %>%
    group_by(nace4d) %>%
    arrange(year) %>%
    slice_head(n = 3) %>%
    summarise(
      base_cost_denom = mean(total_cost_denom, na.rm = TRUE),
      base_mat_denom  = mean(total_mat_denom,  na.rm = TRUE),
      base_revenue    = mean(total_revenue,    na.rm = TRUE),
      n_base_years    = n(),
      .groups = "drop"
    )
  base_denom <- bind_rows(base_denom, fallback)
}

cat(sprintf("Base-period (2010-2012) denominators: %d sectors, fallback for %d\n",
            nrow(base_denom) - length(needs_fallback),
            length(needs_fallback)))

sector_direct <- sector_direct %>%
  left_join(base_denom, by = "nace4d") %>%
  mutate(
    exposure_alt_total = ifelse(!is.na(base_cost_denom) & base_cost_denom > 0,
                                total_carbon_cost / base_cost_denom, NA_real_),
    exposure_alt_mat   = ifelse(!is.na(base_mat_denom) & base_mat_denom > 0,
                                total_carbon_cost / base_mat_denom, NA_real_),
    exposure_alt_rev   = ifelse(!is.na(base_revenue) & base_revenue > 0,
                                total_carbon_cost / base_revenue, NA_real_)
  )

cat(sprintf("Sector-year rows (ETS sectors only): %d\n", nrow(sector_direct)))
cat(sprintf("Unique NACE4d sectors with ETS firms: %d\n",
            n_distinct(sector_direct$nace4d)))
cat(sprintf("Sector-years with exposure_alt_total defined: %d / %d (%.1f%%)\n",
            sum(!is.na(sector_direct$exposure_alt_total)),
            nrow(sector_direct),
            100 * mean(!is.na(sector_direct$exposure_alt_total))))

# ===========================================================================
# 3. Add network-adjusted exposure (from frozen-weights pipeline, 2012-2021)
# ===========================================================================
#
# The existing frozen-weights panel gives per-firm upstream_exposure and
# direct_exposure_intensity where the denominator is base-period avg_costs.
# For sector-level pass-through we aggregate these with a revenue weight
# (base-period averages) so the sector-level indicator is not dominated by a
# single firm's year.
#
# For years outside 2012-2021 (Phase I, early Phase II, Phase IV tail) the
# network column will be NA; that just means Task 2 regressions with network
# exposure will be restricted to 2012-2021.
# ===========================================================================
cat("\n=== Merging network-adjusted exposure (2012-2021) ===\n")

frozen_path <- file.path(OUT_DATA, "frozen_weights_exposure_panel.RData")
if (file.exists(frozen_path)) {
  load(frozen_path)

  # Firm-year network exposure joined to our firm_exposure (base-period
  # revenue for weights = average revenue over 2010-2012 when available)
  base_rev <- firm_exposure %>%
    filter(year %in% 2010:2012, !is.na(revenue), revenue > 0) %>%
    group_by(vat) %>%
    summarise(base_revenue = mean(revenue, na.rm = TRUE), .groups = "drop")

  network_firm_year <- frozen_exposure_panel %>%
    select(vat, year, nace4d_fx = nace4d,
           direct_exposure_intensity,
           upstream_exposure, upstream_indirect,
           downstream_exposure, downstream_indirect)

  # Map to sector using the firm_exposure sector (prefer our own nace4d from
  # the ETS panel; fall back to the one from frozen panel if ETS info missing).
  sector_network <- network_firm_year %>%
    left_join(firm_exposure %>% select(vat, year, nace4d_ets = nace4d),
              by = c("vat", "year")) %>%
    mutate(nace4d = coalesce(nace4d_ets, nace4d_fx)) %>%
    left_join(base_rev, by = "vat") %>%
    filter(!is.na(nace4d), !is.na(base_revenue)) %>%
    group_by(nace4d, year) %>%
    summarise(
      # Revenue-weighted means across firms in the sector
      net_upstream       = weighted.mean(upstream_exposure,    base_revenue, na.rm = TRUE),
      net_upstream_ind   = weighted.mean(upstream_indirect,    base_revenue, na.rm = TRUE),
      net_downstream     = weighted.mean(downstream_exposure,  base_revenue, na.rm = TRUE),
      net_downstream_ind = weighted.mean(downstream_indirect,  base_revenue, na.rm = TRUE),
      net_direct         = weighted.mean(direct_exposure_intensity, base_revenue, na.rm = TRUE),
      n_firms_net        = n_distinct(vat),
      .groups = "drop"
    )

  sector_exposure <- sector_direct %>%
    left_join(sector_network, by = c("nace4d", "year"))

  cat(sprintf("  Sector-years with network exposure: %d / %d\n",
              sum(!is.na(sector_exposure$net_upstream)),
              nrow(sector_exposure)))
} else {
  cat("WARNING: frozen_weights_exposure_panel.RData not found; network\n")
  cat("  columns will be absent from sector_exposure.\n")
  sector_exposure <- sector_direct
}

# ---- Save ----
save(sector_exposure, file = file.path(OUT_DATA, "phase3_sector_exposure.RData"))
cat("\nSaved sector-year panel to:",
    file.path(OUT_DATA, "phase3_sector_exposure.RData"), "\n")

cat("\nDone.\n")
