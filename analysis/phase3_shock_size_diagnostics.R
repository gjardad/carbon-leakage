###############################################################################
# phase3_shock_size_diagnostics.R
#
# PURPOSE:
#   Task 3. Diagnostics characterizing how big the Belgian ETS carbon-price
#   shock was and how it changed over time. Items covered here (1-4, 7 in the
#   Phase 3 plan; items 5 and 6 deferred per TODO.md):
#
#     1. Effective carbon price per tonne emitted, aggregate by year.
#        = sum(shortage * EUA) / sum(emissions).
#     2. Share of emissions priced over time, aggregate and by NACE2d.
#        = sum(shortage) / sum(emissions).
#     3. Share of ETS firms with strictly positive shortage, by year,
#        plus the distribution of shortage intensity among positive firms.
#     4. Concentration: share of total Belgian carbon cost paid by top 5 / 10
#        firms per year.
#     7. Free-allocation stringency by NACE2d: sum(free) / sum(emissions).
#
# INPUT:
#   data/processed/phase3_firm_exposure.RData
#   data/processed/phase3_eua_prices.RData
#
# OUTPUT:
#   output/figures/phase3_task3_effective_price.pdf
#   output/figures/phase3_task3_share_priced_agg.pdf
#   output/figures/phase3_task3_share_priced_nace2d.pdf
#   output/figures/phase3_task3_pct_firms_positive.pdf
#   output/figures/phase3_task3_dist_positive_by_year.pdf
#   output/figures/phase3_task3_concentration.pdf
#   output/figures/phase3_task3_free_stringency_nace2d.pdf
#   output/tables/phase3_task3_diagnostics.csv
###############################################################################

rm(list = ls())

library(dplyr)
library(ggplot2)
library(tidyr)
library(stringr)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load ----
load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
load(file.path(OUT_DATA, "phase3_eua_prices.RData"))

phase_breaks <- tibble(
  phase_start = c(2005, 2008, 2013, 2021),
  phase_end   = c(2007, 2012, 2020, max(firm_exposure$year)),
  phase_lab   = c("I", "II", "III", "IV")
)

# Shaded rectangles & labels for every plot
phase_shade <- geom_rect(
  data = phase_breaks,
  aes(xmin = phase_start - 0.5, xmax = phase_end + 0.5,
      ymin = -Inf, ymax = Inf, fill = phase_lab),
  alpha = 0.08, inherit.aes = FALSE
)
phase_fill <- scale_fill_manual(
  values = c("I" = "#cccccc", "II" = "#dddddd", "III" = "#cccccc", "IV" = "#dddddd"),
  guide = "none"
)
phase_labels <- function(ymax) {
  geom_text(
    data = phase_breaks,
    aes(x = (phase_start + phase_end) / 2, y = ymax,
        label = paste0("Phase ", phase_lab)),
    inherit.aes = FALSE, size = 3, vjust = 1.2, color = "grey30"
  )
}

# ===========================================================================
# Diagnostic 1: Effective carbon price per tonne emitted (aggregate)
# ===========================================================================
cat("\n[1] Effective carbon price per tonne emitted\n")

eff_price <- firm_exposure %>%
  group_by(year) %>%
  summarise(
    total_carbon_cost = sum(carbon_cost, na.rm = TRUE),
    total_emissions   = sum(emissions,   na.rm = TRUE),
    total_shortage    = sum(shortage,    na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(eua_prices_annual %>% select(year, eua_price), by = "year") %>%
  mutate(
    effective_price = total_carbon_cost / total_emissions,
    share_priced    = total_shortage / total_emissions
  )

print(as.data.frame(eff_price))

p1 <- ggplot(eff_price, aes(x = year)) +
  phase_shade + phase_fill +
  geom_line(aes(y = eua_price,      color = "Market EUA price"), linewidth = 0.8) +
  geom_point(aes(y = eua_price,     color = "Market EUA price"), size = 1.5) +
  geom_line(aes(y = effective_price, color = "Effective price (per t emitted)"), linewidth = 0.8) +
  geom_point(aes(y = effective_price, color = "Effective price (per t emitted)"), size = 1.5) +
  phase_labels(ymax = max(eff_price$eua_price, na.rm = TRUE) * 1.05) +
  scale_color_manual(values = c("Market EUA price" = "#1f77b4",
                                "Effective price (per t emitted)" = "#d62728"),
                     name = NULL) +
  labs(
    title = "Effective carbon price per tonne of Belgian ETS emissions",
    subtitle = "Effective = sum(shortage x EUA) / sum(emissions). Gap to market price reflects free allocation.",
    x = NULL, y = "EUR / tCO2"
  ) +
  theme_bw(base_size = 10) +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold"))

ggsave(file.path(OUTPUT_FIG, "phase3_task3_effective_price.pdf"), p1,
       width = 8, height = 5)

# ===========================================================================
# Diagnostic 2a: Share of emissions priced, aggregate
# ===========================================================================
cat("\n[2a] Share of emissions priced, aggregate\n")

p2a <- ggplot(eff_price, aes(x = year, y = 100 * share_priced)) +
  phase_shade + phase_fill +
  geom_line(color = "#1f77b4", linewidth = 0.8) +
  geom_point(color = "#1f77b4", size = 1.5) +
  phase_labels(ymax = max(100 * eff_price$share_priced, na.rm = TRUE) * 1.05) +
  labs(
    title = "Share of Belgian ETS emissions that required allowance purchase",
    subtitle = "= sum(max(emissions - free, 0)) / sum(emissions).",
    x = NULL, y = "Percent of emissions priced"
  ) +
  theme_bw(base_size = 10) +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(OUTPUT_FIG, "phase3_task3_share_priced_agg.pdf"), p2a,
       width = 8, height = 5)

# ===========================================================================
# Diagnostic 2b: Share of emissions priced, by NACE2d
# ===========================================================================
cat("\n[2b] Share of emissions priced by NACE2d\n")

share_by_nace2d <- firm_exposure %>%
  filter(!is.na(nace2d)) %>%
  group_by(nace2d, year) %>%
  summarise(
    emissions = sum(emissions, na.rm = TRUE),
    shortage  = sum(shortage,  na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(share_priced = shortage / emissions)

# Keep only major NACE2d for legibility: top 6 by total 2005-2022 emissions
top_nace2d <- firm_exposure %>%
  filter(!is.na(nace2d)) %>%
  group_by(nace2d) %>%
  summarise(total_em = sum(emissions, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(total_em)) %>%
  head(6) %>%
  pull(nace2d)

share_by_top <- share_by_nace2d %>% filter(nace2d %in% top_nace2d)

p2b <- ggplot(share_by_top, aes(x = year, y = 100 * share_priced, color = nace2d)) +
  phase_shade + phase_fill +
  geom_line(linewidth = 0.7) +
  geom_point(size = 1) +
  phase_labels(ymax = max(100 * share_by_top$share_priced, na.rm = TRUE) * 1.05) +
  labs(
    title = "Share of emissions priced, by NACE 2-digit (top 6 sectors by emissions)",
    x = NULL, y = "Percent of emissions priced",
    color = "NACE2d"
  ) +
  theme_bw(base_size = 10) +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "bottom")

ggsave(file.path(OUTPUT_FIG, "phase3_task3_share_priced_nace2d.pdf"), p2b,
       width = 9, height = 5.5)

# ===========================================================================
# Diagnostic 3a: Share of ETS firms with strictly positive shortage
# ===========================================================================
cat("\n[3a] Share of ETS firms with positive shortage\n")

pct_positive <- firm_exposure %>%
  group_by(year) %>%
  summarise(
    n_firms         = n_distinct(vat),
    n_positive      = n_distinct(vat[shortage > 0]),
    pct_positive    = 100 * n_positive / n_firms,
    .groups = "drop"
  )

p3a <- ggplot(pct_positive, aes(x = year, y = pct_positive)) +
  phase_shade + phase_fill +
  geom_col(fill = "#1f77b4", alpha = 0.9) +
  phase_labels(ymax = max(pct_positive$pct_positive) * 1.05) +
  labs(
    title = "Share of in-sample Belgian ETS firms with strictly positive shortage",
    subtitle = "A firm has positive shortage when emissions exceed its free allocation.",
    x = NULL, y = "% of firms"
  ) +
  theme_bw(base_size = 10) +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(OUTPUT_FIG, "phase3_task3_pct_firms_positive.pdf"), p3a,
       width = 8, height = 5)

# ===========================================================================
# Diagnostic 3b: Distribution of shortage intensity among positive firms
# ===========================================================================
cat("\n[3b] Distribution of shortage intensity (emissions basis) among positive firms\n")

shortage_dist <- firm_exposure %>%
  filter(shortage > 0, emissions > 0) %>%
  mutate(short_intensity = shortage / emissions,
         short_intensity_pct = 100 * short_intensity)

# Summarise by year: p25, p50, p75, p90 of short_intensity_pct
dist_q <- shortage_dist %>%
  group_by(year) %>%
  summarise(
    n = n(),
    p25 = quantile(short_intensity_pct, 0.25),
    p50 = quantile(short_intensity_pct, 0.50),
    p75 = quantile(short_intensity_pct, 0.75),
    p90 = quantile(short_intensity_pct, 0.90),
    .groups = "drop"
  ) %>%
  pivot_longer(starts_with("p"), names_to = "quantile", values_to = "value")

p3b <- ggplot(dist_q, aes(x = year, y = value, color = quantile)) +
  phase_shade + phase_fill +
  geom_line(linewidth = 0.7) +
  geom_point(size = 1) +
  phase_labels(ymax = max(dist_q$value) * 1.05) +
  scale_color_manual(values = c("p25" = "#9ecae1", "p50" = "#3182bd",
                                "p75" = "#08519c", "p90" = "#08306b"),
                     labels = c("25th pct", "Median", "75th pct", "90th pct"),
                     name = NULL) +
  labs(
    title = "Shortage intensity (shortage / emissions) among firms with positive shortage",
    subtitle = "Higher = firm needed to buy allowances for a larger share of its emissions.",
    x = NULL, y = "% of firm's emissions that were priced"
  ) +
  theme_bw(base_size = 10) +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "bottom")

ggsave(file.path(OUTPUT_FIG, "phase3_task3_dist_positive_by_year.pdf"), p3b,
       width = 9, height = 5.5)

# ===========================================================================
# Diagnostic 4: Concentration of carbon cost
# ===========================================================================
cat("\n[4] Concentration of total carbon cost (top 5 / top 10 firms)\n")

conc <- firm_exposure %>%
  filter(!is.na(carbon_cost), carbon_cost > 0) %>%
  group_by(year) %>%
  arrange(year, desc(carbon_cost)) %>%
  mutate(rank = row_number(),
         total_cc = sum(carbon_cost),
         cumshare = cumsum(carbon_cost) / total_cc) %>%
  summarise(
    n_positive = n(),
    top5  = if (n() >= 5)  cumshare[rank == 5]  else cumshare[rank == n()],
    top10 = if (n() >= 10) cumshare[rank == 10] else cumshare[rank == n()],
    .groups = "drop"
  ) %>%
  pivot_longer(c(top5, top10), names_to = "group", values_to = "share") %>%
  mutate(group = recode(group, top5 = "Top 5 firms", top10 = "Top 10 firms"))

p4 <- ggplot(conc, aes(x = year, y = 100 * share, color = group)) +
  phase_shade + phase_fill +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.5) +
  phase_labels(ymax = 100) +
  scale_color_manual(values = c("Top 5 firms" = "#d62728",
                                "Top 10 firms" = "#ff7f0e"),
                     name = NULL) +
  ylim(0, 100) +
  labs(
    title = "Concentration: share of total Belgian carbon cost paid by top firms",
    subtitle = "Denominator = sum of carbon_cost over ETS firms with shortage > 0.",
    x = NULL, y = "Share of total carbon cost (%)"
  ) +
  theme_bw(base_size = 10) +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "bottom")

ggsave(file.path(OUTPUT_FIG, "phase3_task3_concentration.pdf"), p4,
       width = 8, height = 5)

# ===========================================================================
# Diagnostic 7: Free-allocation stringency by NACE2d
#   stringency = free / emissions (capped at 1 for display).
#   Low = binding cap; near 1 = soft cap; >1 = over-allocated.
# ===========================================================================
cat("\n[7] Free-allocation stringency by NACE2d\n")

stringency <- firm_exposure %>%
  filter(!is.na(nace2d)) %>%
  group_by(nace2d, year) %>%
  summarise(
    emissions = sum(emissions, na.rm = TRUE),
    free      = sum(allocated_free, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(emissions > 0) %>%
  mutate(stringency = free / emissions,
         stringency_c = pmin(stringency, 2))

# Keep top 8 by total emissions
top_nace2d_8 <- firm_exposure %>%
  filter(!is.na(nace2d)) %>%
  group_by(nace2d) %>%
  summarise(total_em = sum(emissions, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(total_em)) %>%
  head(8) %>%
  pull(nace2d)

stringency_top <- stringency %>% filter(nace2d %in% top_nace2d_8)

p7 <- ggplot(stringency_top, aes(x = year, y = stringency_c, color = nace2d)) +
  phase_shade + phase_fill +
  geom_line(linewidth = 0.7) +
  geom_point(size = 1) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "grey40") +
  phase_labels(ymax = max(stringency_top$stringency_c, na.rm = TRUE) * 1.05) +
  labs(
    title = "Free-allocation stringency by NACE2d: free / emissions",
    subtitle = "Values <1 = sector must buy; values >1 = over-allocated (capped at 2 for display).",
    x = NULL, y = "free / emissions",
    color = "NACE2d"
  ) +
  theme_bw(base_size = 10) +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "bottom")

ggsave(file.path(OUTPUT_FIG, "phase3_task3_free_stringency_nace2d.pdf"), p7,
       width = 9, height = 5.5)

# ===========================================================================
# Write a combined summary CSV
# ===========================================================================
diag_summary <- eff_price %>%
  left_join(pct_positive, by = "year") %>%
  left_join(
    conc %>% pivot_wider(names_from = group, values_from = share,
                         names_prefix = "share_") %>%
      rename(conc_top5  = `share_Top 5 firms`,
             conc_top10 = `share_Top 10 firms`),
    by = "year"
  ) %>%
  select(year, eua_price, effective_price, total_emissions, total_shortage,
         share_priced, n_firms, pct_positive, conc_top5, conc_top10)

write.csv(diag_summary,
          file = file.path(OUTPUT_TAB, "phase3_task3_diagnostics.csv"),
          row.names = FALSE)

cat("\nSummary diagnostics:\n")
print(as.data.frame(diag_summary))

cat("\nAll task 3 figures written to:", OUTPUT_FIG, "\n")
cat("Summary table written to:",
    file.path(OUTPUT_TAB, "phase3_task3_diagnostics.csv"), "\n")
cat("Done.\n")
