###############################################################################
# phase2_network_exposure_variability.R
#
# PURPOSE:
#   Assess whether there is meaningful within-NACE4d variation in
#   network-adjusted ETS exposure. If all firms in a sector have similar
#   network exposure, regressions with sector×year FE won't have power.
#
# DATA:
#   - data/processed/network_exposure_panel.RData
#
# OUTPUT:
#   - output/figures/phase2_within_sector_variance.png
#   - output/figures/phase2_exposure_distributions.png
#   - output/figures/phase2_direct_vs_network.png
#   - Summary statistics printed to console
###############################################################################

rm(list = ls())

library(dplyr)
library(tidyr)
library(ggplot2)
library(stringr)

# ---- Paths ----
project_root <- "c:/Users/jota_/Documents/carbon_policy_networks"
out_data     <- file.path(project_root, "data", "processed")
output_fig   <- file.path(project_root, "output", "figures")

dir.create(output_fig, recursive = TRUE, showWarnings = FALSE)

# ---- Load data ----
load(file.path(out_data, "network_exposure_panel.RData"))

# Filter to firms with valid sector and exposure data
df <- network_exposure_panel %>%
  filter(!is.na(nace4d), !is.na(upstream_exposure))

cat(sprintf("Panel: %d firm-years, %d unique firms, %d NACE4d sectors\n",
            nrow(df), n_distinct(df$vat), n_distinct(df$nace4d)))

# ---- 1. Within vs Between sector variance decomposition ----
cat("\n=== Variance Decomposition (upstream_exposure) ===\n")

# By year, decompose total variance into between-sector and within-sector
variance_decomp <- df %>%
  group_by(year) %>%
  mutate(grand_mean = mean(upstream_exposure, na.rm = TRUE)) %>%
  group_by(year, nace4d) %>%
  mutate(
    sector_mean = mean(upstream_exposure, na.rm = TRUE),
    n_sector = n()
  ) %>%
  ungroup() %>%
  group_by(year) %>%
  summarise(
    total_var = var(upstream_exposure, na.rm = TRUE),
    between_var = var(sector_mean, na.rm = TRUE),
    within_var = mean((upstream_exposure - sector_mean)^2, na.rm = TRUE),
    n_firms = n(),
    n_sectors = n_distinct(nace4d),
    .groups = "drop"
  ) %>%
  mutate(
    within_share = within_var / total_var,
    between_share = between_var / total_var
  )

cat("\nYear | Total Var | Between Share | Within Share | N firms | N sectors\n")
cat(paste(rep("-", 80), collapse = ""), "\n")
for (i in seq_len(nrow(variance_decomp))) {
  r <- variance_decomp[i, ]
  cat(sprintf("%d |  %.2e   |    %.1f%%     |    %.1f%%    |  %d  |  %d\n",
              r$year, r$total_var, r$between_share * 100,
              r$within_share * 100, r$n_firms, r$n_sectors))
}

# ---- 2. Within-sector statistics by NACE4d-year ----
sector_stats <- df %>%
  group_by(nace4d, year) %>%
  summarise(
    n_firms = n(),
    mean_upstream = mean(upstream_exposure, na.rm = TRUE),
    sd_upstream = sd(upstream_exposure, na.rm = TRUE),
    cv_upstream = ifelse(mean_upstream > 0,
                         sd_upstream / mean_upstream, NA_real_),
    iqr_upstream = IQR(upstream_exposure, na.rm = TRUE),
    p10 = quantile(upstream_exposure, 0.1, na.rm = TRUE),
    p90 = quantile(upstream_exposure, 0.9, na.rm = TRUE),
    mean_downstream = mean(downstream_exposure, na.rm = TRUE),
    sd_downstream = sd(downstream_exposure, na.rm = TRUE),
    .groups = "drop"
  )

# Focus on sectors with at least 5 firms
sector_stats_5 <- sector_stats %>% filter(n_firms >= 5)

cat(sprintf("\n\nSector-years with >= 5 firms: %d (out of %d total sector-years)\n",
            nrow(sector_stats_5), nrow(sector_stats)))
cat(sprintf("Median CV of upstream exposure (within sector-year): %.3f\n",
            median(sector_stats_5$cv_upstream, na.rm = TRUE)))
cat(sprintf("Mean CV of upstream exposure (within sector-year): %.3f\n",
            mean(sector_stats_5$cv_upstream, na.rm = TRUE)))
cat(sprintf("Share of sector-years with CV > 0.5: %.1f%%\n",
            mean(sector_stats_5$cv_upstream > 0.5, na.rm = TRUE) * 100))
cat(sprintf("Share of sector-years with CV > 1.0: %.1f%%\n",
            mean(sector_stats_5$cv_upstream > 1.0, na.rm = TRUE) * 100))

# ---- 3. Plot: within-sector variance share over time ----
p1 <- ggplot(variance_decomp, aes(x = year, y = within_share)) +

geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  labs(
    title = "Within-NACE4d Share of Total Variance in Upstream Network Exposure",
    x = "Year", y = "Within-sector share of total variance"
  ) +
  theme_minimal(base_size = 12)

ggsave(file.path(output_fig, "phase2_within_sector_variance.png"),
       p1, width = 8, height = 5, dpi = 150)

# ---- 4. Plot: distribution of upstream exposure for selected sectors ----
# Pick top 5 sectors by number of firm-years
top_sectors <- df %>%
  count(nace4d) %>%
  arrange(desc(n)) %>%
  slice_head(n = 5) %>%
  pull(nace4d)

df_top <- df %>%
  filter(nace4d %in% top_sectors, year %in% c(2010, 2015, 2021))

p2 <- ggplot(df_top, aes(x = upstream_exposure, fill = nace4d)) +
  geom_histogram(bins = 30, alpha = 0.6, position = "identity") +
  facet_grid(nace4d ~ year, scales = "free_y") +
  labs(
    title = "Distribution of Upstream Network Exposure within Top Sectors",
    x = "Upstream exposure (intensity)", y = "Count"
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "none")

ggsave(file.path(output_fig, "phase2_exposure_distributions.png"),
       p2, width = 10, height = 8, dpi = 150)

# ---- 5. Plot: direct vs network exposure ----
# Are they just correlated, or does the network add information?
df_with_direct <- df %>% filter(direct_exposure_intensity > 0 | upstream_indirect > 0)

p3 <- ggplot(df_with_direct %>% filter(year == 2021),
             aes(x = direct_exposure_intensity, y = upstream_indirect)) +
  geom_point(alpha = 0.4, size = 1.5) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") +
  scale_x_log10() + scale_y_log10() +
  labs(
    title = "Direct vs. Upstream Indirect Exposure (2021)",
    x = "Direct exposure intensity (log scale)",
    y = "Upstream indirect exposure (log scale)"
  ) +
  theme_minimal(base_size = 12)

ggsave(file.path(output_fig, "phase2_direct_vs_network.png"),
       p3, width = 7, height = 6, dpi = 150)

# ---- 6. Key diagnostic: correlation between direct and network ----
cat("\n=== Correlation: Direct vs. Network Exposure ===\n")
for (y in c(2010, 2015, 2018, 2021)) {
  sub <- df %>% filter(year == y)
  r_up <- cor(sub$direct_exposure_intensity, sub$upstream_indirect,
              use = "complete.obs")
  r_down <- cor(sub$direct_exposure_intensity, sub$downstream_indirect,
                use = "complete.obs")
  cat(sprintf("  %d: cor(direct, upstream_indirect)=%.3f, cor(direct, downstream_indirect)=%.3f\n",
              y, r_up, r_down))
}

# ---- 7. Non-ETS firms: do they have meaningful variation? ----
cat("\n=== Non-ETS Firms Network Exposure ===\n")
nonets <- df %>% filter(is_ets == 0 | is.na(is_ets))
cat(sprintf("Non-ETS firm-years: %d\n", nrow(nonets)))
cat(sprintf("  With positive upstream_indirect: %d (%.1f%%)\n",
            sum(nonets$upstream_indirect > 0, na.rm = TRUE),
            mean(nonets$upstream_indirect > 0, na.rm = TRUE) * 100))
cat(sprintf("  Mean upstream_indirect: %.6f\n",
            mean(nonets$upstream_indirect, na.rm = TRUE)))
cat(sprintf("  SD upstream_indirect: %.6f\n",
            sd(nonets$upstream_indirect, na.rm = TRUE)))
cat(sprintf("  P25/P50/P75: %.6f / %.6f / %.6f\n",
            quantile(nonets$upstream_indirect, 0.25, na.rm = TRUE),
            quantile(nonets$upstream_indirect, 0.50, na.rm = TRUE),
            quantile(nonets$upstream_indirect, 0.75, na.rm = TRUE)))

cat("\nDone.\n")
