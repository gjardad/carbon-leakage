###############################################################################
# phase5_shock_distribution_byphase.R
#
# PURPOSE:
#   Plan A, Moments 1, 3, 6 (per streamed-leaping-tide.md).
#
#   Characterize how big the ETS cost shock is at the firm-year level over
#   time. Plan A is descriptive: we use the same-year cost-share definition
#   (numerator and denominator both in year t), which is `cost_share_total`
#   already computed in phase3_firm_exposure.RData.
#
#     firm_cost_share_{j,t} = (shortage_{j,t} * EUA_t) / total_cost_{j,t}
#
#   Five-phase split (finer than the canonical 4-phase coding so that
#   pre-MSR vs post-MSR Phase III is visible):
#     I              : 2005-2007
#     II             : 2008-2012
#     III pre-MSR    : 2013-2017
#     III post-MSR   : 2018-2020
#     IV             : 2021-2022
#
# INPUT:
#   data/processed/phase3_firm_exposure.RData       (firm_exposure)
#   data/processed/phase3_eua_prices.RData          (eua_prices_annual)
#
# OUTPUT:
#   output/tables/phase5_moment1_cost_share_distribution.csv
#   output/tables/phase5_moment3_effective_carbon_price.csv
#   output/tables/phase5_moment6_phase4_stress.csv
#   output/figures/phase5_moment1_distribution_by_phase.pdf
#   output/tables/phase5_shock_distribution_summary.txt
#
# CAVEATS:
#   - Drops the 3 contaminated VAT hashes (NACE 20, 24) from 2021+ per
#     MEMORY.md project_nace24_eutl_break_post2020.md. These post-2020
#     drops are EUTL registry artefacts, not real emissions changes.
#   - Drops firm-years where total_cost <= 0 (cost_share_total is NA in
#     these; counted and reported).
###############################################################################

rm(list = ls())

library(dplyr)
library(tidyr)
library(ggplot2)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load ----
cat("Loading firm-year exposure panel and EUA prices...\n")
load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))   # firm_exposure
load(file.path(OUT_DATA, "phase3_eua_prices.RData"))      # eua_prices_annual

# ---- Drop contaminated VATs from 2021+ ----
contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)

n_drop <- firm_exposure %>%
  filter(vat %in% contaminated_vats, year >= 2021) %>%
  nrow()

firm_exposure <- firm_exposure %>%
  filter(!(vat %in% contaminated_vats & year >= 2021))

cat(sprintf("Dropped %d contaminated firm-year obs (NACE 20/24 EUTL artefact, year >= 2021).\n", n_drop))

# ---- Fine-grained phase column ----
firm_exposure <- firm_exposure %>%
  mutate(phase5 = case_when(
    year %in% 2005:2007 ~ "I",
    year %in% 2008:2012 ~ "II",
    year %in% 2013:2017 ~ "III pre-MSR",
    year %in% 2018:2020 ~ "III post-MSR",
    year >= 2021        ~ "IV",
    TRUE                ~ NA_character_
  ))

phase5_levels <- c("I", "II", "III pre-MSR", "III post-MSR", "IV")
firm_exposure$phase5 <- factor(firm_exposure$phase5, levels = phase5_levels)

# ---- Drop firm-years with cost_share_total undefined (total_cost <= 0) ----
n_total <- nrow(firm_exposure)
n_undef <- sum(is.na(firm_exposure$cost_share_total))

cat(sprintf("Firm-years total: %d\n", n_total))
cat(sprintf("Firm-years with cost_share_total undefined (total_cost<=0): %d (%.2f%%)\n",
            n_undef, 100 * n_undef / n_total))

shock_panel <- firm_exposure %>%
  filter(!is.na(cost_share_total))

cat(sprintf("Firm-years used in distribution: %d\n", nrow(shock_panel)))

# ===========================================================================
# Moment 1 -- distribution of same-year cost share by phase
# ===========================================================================
cat("\n=== Moment 1: distribution of firm_cost_share_{j,t} by phase ===\n")

# Sales weight = revenue (firm-year). When NA, drop from sales-weighted mean.
moment1 <- shock_panel %>%
  group_by(phase5) %>%
  summarise(
    n_firm_years        = n(),
    n_distinct_firms    = n_distinct(vat),
    pct_pos_shortage    = 100 * mean(shortage > 0, na.rm = TRUE),
    p25                 = quantile(cost_share_total, 0.25, na.rm = TRUE),
    p50                 = quantile(cost_share_total, 0.50, na.rm = TRUE),
    p75                 = quantile(cost_share_total, 0.75, na.rm = TRUE),
    p90                 = quantile(cost_share_total, 0.90, na.rm = TRUE),
    p99                 = quantile(cost_share_total, 0.99, na.rm = TRUE),
    mean                = mean(cost_share_total, na.rm = TRUE),
    sales_wmean         = sum(cost_share_total * revenue, na.rm = TRUE) /
                          sum(revenue * !is.na(cost_share_total), na.rm = TRUE),
    .groups = "drop"
  )

print(as.data.frame(moment1), digits = 4)

write.csv(moment1,
          file.path(OUTPUT_TAB, "phase5_moment1_cost_share_distribution.csv"),
          row.names = FALSE)
cat("Saved:", file.path(OUTPUT_TAB, "phase5_moment1_cost_share_distribution.csv"), "\n")

# ===========================================================================
# Moment 3 -- effective carbon price per tonne emitted, by phase
# ===========================================================================
#
#   effective_eur_per_tonne = sum_j(carbon_cost_{j,t}) / sum_j(emissions_{j,t})
#
#   This is the average price actually paid per tonne emitted, after
#   netting out free allocation. % emissions priced = sum(shortage)/sum(em).
#
# Aggregated within phase across all ETS firms in_sample.
# ===========================================================================
cat("\n=== Moment 3: effective carbon price per tonne emitted, by phase ===\n")

moment3 <- shock_panel %>%
  group_by(phase5) %>%
  summarise(
    eua_min                  = min(eua_price, na.rm = TRUE),
    eua_max                  = max(eua_price, na.rm = TRUE),
    sum_emissions            = sum(emissions, na.rm = TRUE),
    sum_shortage             = sum(shortage, na.rm = TRUE),
    sum_carbon_cost          = sum(carbon_cost, na.rm = TRUE),
    pct_emissions_priced     = 100 * sum(shortage, na.rm = TRUE) /
                                     sum(emissions, na.rm = TRUE),
    eff_eur_per_tonne_emitted = sum(carbon_cost, na.rm = TRUE) /
                                sum(emissions, na.rm = TRUE),
    .groups = "drop"
  )

print(as.data.frame(moment3), digits = 4)

write.csv(moment3,
          file.path(OUTPUT_TAB, "phase5_moment3_effective_carbon_price.csv"),
          row.names = FALSE)
cat("Saved:", file.path(OUTPUT_TAB, "phase5_moment3_effective_carbon_price.csv"), "\n")

# ===========================================================================
# Moment 6 -- Phase IV stress test (population-level)
# ===========================================================================
#
# Plan A's pair-level Moment 6 lives in phase5_pair_shock_magnitude.R.
# Here we report the firm-year distribution restricted to Phase IV only,
# split by NACE 2d so the high-intensity vs low-intensity decomposition
# is visible.
# ===========================================================================
cat("\n=== Moment 6 (population, Phase IV only, by NACE 2d) ===\n")

moment6 <- shock_panel %>%
  filter(phase5 == "IV") %>%
  group_by(nace2d) %>%
  summarise(
    n_firm_years        = n(),
    n_distinct_firms    = n_distinct(vat),
    sum_emissions       = sum(emissions, na.rm = TRUE),
    p25                 = quantile(cost_share_total, 0.25, na.rm = TRUE),
    p50                 = quantile(cost_share_total, 0.50, na.rm = TRUE),
    p75                 = quantile(cost_share_total, 0.75, na.rm = TRUE),
    p90                 = quantile(cost_share_total, 0.90, na.rm = TRUE),
    p99                 = quantile(cost_share_total, 0.99, na.rm = TRUE),
    mean                = mean(cost_share_total, na.rm = TRUE),
    sales_wmean         = sum(cost_share_total * revenue, na.rm = TRUE) /
                          sum(revenue * !is.na(cost_share_total), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(p90))

print(as.data.frame(moment6), digits = 4)

write.csv(moment6,
          file.path(OUTPUT_TAB, "phase5_moment6_phase4_stress.csv"),
          row.names = FALSE)
cat("Saved:", file.path(OUTPUT_TAB, "phase5_moment6_phase4_stress.csv"), "\n")

# ===========================================================================
# Figure -- distribution histograms by phase
# ===========================================================================
cat("\n=== Figure: cost-share histograms by phase ===\n")

# Winsorize within phase at p99 for plotting only -- so Phase IV's right
# tail does not crush the visible range of Phase I/II.
plot_data <- shock_panel %>%
  group_by(phase5) %>%
  mutate(p99_within = quantile(cost_share_total, 0.99, na.rm = TRUE),
         x_plot     = pmin(cost_share_total, p99_within)) %>%
  ungroup()

p_hist <- ggplot(plot_data, aes(x = x_plot)) +
  geom_histogram(bins = 50, fill = "steelblue", alpha = 0.85) +
  facet_wrap(~ phase5, scales = "free", ncol = 2) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  labs(
    title   = "Distribution of firm_cost_share_{j,t} by ETS phase",
    subtitle = paste0("Same-year ratio (shortage * EUA) / total_cost. Winsorized at p99 within phase. ",
                      "Belgian ETS firms in_sample, contaminated VATs dropped 2021+."),
    x       = "Firm-year cost share (carbon cost as % of total cost)",
    y       = "Number of firm-years"
  ) +
  theme_minimal(base_size = 11) +
  theme(strip.background = element_rect(fill = "grey92", colour = NA),
        plot.title.position = "plot")

ggsave(file.path(OUTPUT_FIG, "phase5_moment1_distribution_by_phase.pdf"),
       p_hist, width = 9, height = 6)
cat("Saved:", file.path(OUTPUT_FIG, "phase5_moment1_distribution_by_phase.pdf"), "\n")

# ===========================================================================
# Combined readable summary
# ===========================================================================
sink(file.path(OUTPUT_TAB, "phase5_shock_distribution_summary.txt"))

cat("================================================================\n")
cat("Plan A -- Shock magnitude descriptive moments\n")
cat("Moments 1, 3, 6 from streamed-leaping-tide.md\n")
cat("Generated by analysis/phase5_shock_distribution_byphase.R\n")
cat("================================================================\n\n")

cat("Definition:\n")
cat("  firm_cost_share_{j,t} = (shortage_{j,t} * EUA_t) / total_cost_{j,t}\n")
cat("  Same-year ratio. Plan A is descriptive; no Bartik denominator.\n\n")

cat("Sample:\n")
cat(sprintf("  Total firm-years (ETS in_sample): %d\n", n_total))
cat(sprintf("  Dropped (contaminated VATs, 2021+): %d\n", n_drop))
cat(sprintf("  Dropped (total_cost <= 0): %d\n", n_undef))
cat(sprintf("  Used: %d\n\n", nrow(shock_panel)))

cat("--------------------------------------------------------------\n")
cat("Moment 1 -- distribution of cost share by phase\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(moment1), digits = 4)
cat("\n")

cat("--------------------------------------------------------------\n")
cat("Moment 3 -- effective carbon price per tonne emitted, by phase\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(moment3), digits = 4)
cat("\n")

cat("--------------------------------------------------------------\n")
cat("Moment 6 -- Phase IV only, by NACE 2d (firm-year distribution)\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(moment6), digits = 4)
cat("\n")

cat("================================================================\n")
cat("Plan A verdict reading:\n")
cat("  Phase IV p90 in Moment 1 above >5% means real shock (population).\n")
cat("  Moment 6 by NACE 2d shows whether high-intensity sectors\n")
cat("  (cement/refining/basic metals) are the upper tail.\n")
cat("  Pair-level Moment 4 (in phase5_pair_shock_magnitude.R) gives\n")
cat("  the buyer-side exposure distribution that drives the verdict.\n")
cat("================================================================\n")

sink()
cat("Saved:", file.path(OUTPUT_TAB, "phase5_shock_distribution_summary.txt"), "\n")

cat("\nDone.\n")
