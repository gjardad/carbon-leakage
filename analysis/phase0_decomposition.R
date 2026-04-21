###############################################################################
# phase0_decomposition.R
#
# PURPOSE:
#   Statistical decomposition of Belgian manufacturing emission changes into
#   scale, composition, and technique effects — at the FIRM level.
#
#   Following Grossman & Krueger (1993), Levinson (2009), Martinsson et al. (2024).
#   Firm-level so that:
#     - "composition" captures within-sector reallocation (market share shifts)
#     - "technique" captures pure within-firm abatement
#   Further decomposed into between-sector and within-sector reallocation.
#
#   Purely mechanical/accounting — no causal claims.
#
# DEFLATION:
#   Firm revenue deflated by domestic market PPI:
#     - 2005-2009: Eurostat NACE 2-digit PPI (sts_inpp_a)
#     - 2010+:     Statbel NACE 4-digit PPI (TABEL_WEBSITE_AANGEVERS_EN.xlsx)
#   Both re-indexed to 2005 = 100.
#
# VERSIONS:
#   A — ETS-only: uses only EUTL verified emissions
#   B — Imputed:  (TODO) uses imputed emissions for non-ETS firms
#   C — Bounds:   (TODO) prediction intervals on imputed emissions
#
# DATA SOURCES (on RMD):
#   - NBB_data/processed/firm_year_belgian_euets.RData
#   - NBB_data/raw/statbel_ppi/TABEL_WEBSITE_AANGEVERS_EN.xlsx  (download from Statbel)
#   - Eurostat sts_inpp_a (via eurostat R package, or pre-downloaded)
#
# OUTPUT:
#   - output/figures/phase0_decomp_firm_level_vA.pdf
#   - output/figures/phase0_decomp_channels_vA.pdf
#   - output/tables/phase0_decomp_summary_vA.csv
###############################################################################

# ---- Setup ----
rm(list = ls())

library(dplyr)
library(tidyr)
library(ggplot2)
library(stringr)

# ---- Paths ----
nbb_data     <- "c:/Users/jota_/Documents/NBB_data"  # <-- ADJUST ON RMD
project_root <- "c:/Users/jota_/Documents/carbon_policy_networks"

proc_data  <- file.path(nbb_data, "processed")
raw_data   <- file.path(nbb_data, "raw")
output_fig <- file.path(project_root, "output", "figures")
output_tab <- file.path(project_root, "output", "tables")
dir.create(output_fig, showWarnings = FALSE, recursive = TRUE)
dir.create(output_tab, showWarnings = FALSE, recursive = TRUE)

# ---- Config ----
emissions_version <- "ets_only"
base_year <- 2005
end_year  <- 2022

###############################################################################
# SECTION 1: LOAD PPI DEFLATOR
#
# Built by phase0_build_deflator.R — run that script first.
# Chain-linked: Eurostat 2-digit (2005-2009) + Statbel 4-digit (2010+),
# all in 2005 = 100 units.
###############################################################################

deflator_file <- file.path(proc_data, "deflator_nace4d_2005base.RData")

if (!file.exists(deflator_file)) {
  stop("Deflator not found. Run phase0_build_deflator.R first.\n",
       "Expected at: ", deflator_file)
}

load(deflator_file)  # loads: deflator (4-digit), deflator_2d_only (fallback)
cat("Deflator loaded:", n_distinct(deflator$nace4d), "NACE 4-digit sectors\n")

###############################################################################
# SECTION 2: LOAD FIRM DATA AND DEFLATE
###############################################################################

load(file.path(proc_data, "firm_year_belgian_euets.RData"))

df <- firm_year_belgian_euets %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(year >= base_year, year <= end_year,
         !is.na(nace2d), !is.na(emissions), !is.na(revenue),
         emissions > 0, revenue > 0)

# Merge deflator: try NACE 4-digit first, fall back to 2-digit
df <- df %>%
  left_join(deflator %>% select(nace4d, year, ppi, ppi_source),
            by = c("nace4d", "year"))

# For firms with no 4-digit match, use 2-digit fallback
n_miss_4d <- sum(is.na(df$ppi))
cat("Firms missing NACE 4-digit deflator:", n_miss_4d, "of", nrow(df), "\n")

if (n_miss_4d > 0) {
  df <- df %>%
    left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
              by = c("nace2d", "year")) %>%
    mutate(ppi = ifelse(is.na(ppi), ppi_2d, ppi),
           ppi_source = ifelse(is.na(ppi_source), "eurostat_2d_fallback", ppi_source)) %>%
    select(-ppi_2d)
}

n_still_miss <- sum(is.na(df$ppi))
cat("Firms still missing deflator after fallback:", n_still_miss, "of", nrow(df), "\n")

# Deflate revenue
df <- df %>%
  filter(!is.na(ppi)) %>%
  mutate(real_revenue = revenue / ppi * 100)

cat("Deflator source breakdown:\n")
print(table(df$ppi_source))

###############################################################################
# SECTION 3: FIRM-LEVEL DECOMPOSITION
#
# theta_it = firm i's real revenue / total real revenue in year t
# z_it     = firm i's emissions / firm i's real revenue
#
# E_scale       = Y_t * sum_i(theta_i0 * z_i0)
# E_scale_comp  = Y_t * sum_i(theta_it * z_i0)
# E_actual      = Y_t * sum_i(theta_it * z_it)
#
# Composition = E_scale_comp - E_scale   (reallocation across firms)
# Technique   = E_actual - E_scale_comp  (within-firm abatement)
###############################################################################

# Total real output by year
agg_year <- df %>%
  group_by(year) %>%
  summarise(Y_t = sum(real_revenue), .groups = "drop")

# Firm shares and intensities
df <- df %>%
  left_join(agg_year, by = "year") %>%
  mutate(
    theta_it = real_revenue / Y_t,
    z_it     = emissions / real_revenue
  )

# Base-year values
base <- df %>%
  filter(year == base_year) %>%
  select(vat, nace2d, theta_i0 = theta_it, z_i0 = z_it)

cat("Firms in base year (", base_year, "):", nrow(base), "\n")

# Decomposition for each year (balanced pairs: firms in both base year and t)
decomp_list <- list()

for (yr in base_year:end_year) {
  df_yr <- df %>%
    filter(year == yr) %>%
    inner_join(base, by = "vat", suffix = c("", "_base"))

  Y_t <- df_yr %>% pull(Y_t) %>% first()

  E_actual     <- sum(df_yr$theta_it * df_yr$z_it) * Y_t
  E_scale_comp <- sum(df_yr$theta_it * df_yr$z_i0) * Y_t
  E_scale      <- sum(df_yr$theta_i0 * df_yr$z_i0) * Y_t

  decomp_list[[as.character(yr)]] <- tibble(
    year = yr, n_firms = nrow(df_yr), Y_t = Y_t,
    E_actual = E_actual, E_scale_comp = E_scale_comp, E_scale = E_scale
  )
}

decomp <- bind_rows(decomp_list)

E_base <- decomp %>% filter(year == base_year) %>% pull(E_actual)

decomp <- decomp %>%
  mutate(
    idx_actual     = (E_actual / E_base) * 100,
    idx_scale      = (E_scale / E_base) * 100,
    idx_scale_comp = (E_scale_comp / E_base) * 100,
    total_change = idx_actual - 100,
    scale_effect = idx_scale - 100,
    comp_effect  = idx_scale_comp - idx_scale,
    tech_effect  = idx_actual - idx_scale_comp
  )

###############################################################################
# SECTION 4: NESTED DECOMPOSITION — BETWEEN VS WITHIN SECTOR
###############################################################################

# Sector-level aggregates
sector_year <- df %>%
  group_by(nace2d, year) %>%
  summarise(emissions_s = sum(emissions), revenue_s = sum(real_revenue),
            .groups = "drop") %>%
  left_join(agg_year, by = "year") %>%
  mutate(theta_st = revenue_s / Y_t, z_st = emissions_s / revenue_s)

base_sector <- sector_year %>%
  filter(year == base_year) %>%
  select(nace2d, theta_s0 = theta_st, z_s0 = z_st)

decomp_sector_list <- list()
for (yr in base_year:end_year) {
  sy <- sector_year %>%
    filter(year == yr) %>%
    inner_join(base_sector, by = "nace2d")
  Y_t <- sy %>% pull(Y_t) %>% first()
  decomp_sector_list[[as.character(yr)]] <- tibble(
    year = yr,
    E_actual_s     = sum(sy$theta_st * sy$z_st) * Y_t,
    E_scale_comp_s = sum(sy$theta_st * sy$z_s0) * Y_t,
    E_scale_s      = sum(sy$theta_s0 * sy$z_s0) * Y_t
  )
}

decomp_sector <- bind_rows(decomp_sector_list)
E_base_s <- decomp_sector %>% filter(year == base_year) %>% pull(E_actual_s)

decomp_sector <- decomp_sector %>%
  mutate(
    idx_scale_s      = (E_scale_s / E_base_s) * 100,
    idx_scale_comp_s = (E_scale_comp_s / E_base_s) * 100,
    between_sector_comp = idx_scale_comp_s - idx_scale_s,
    sector_tech         = (E_actual_s / E_base_s) * 100 - idx_scale_comp_s
  )

decomp <- decomp %>%
  left_join(decomp_sector %>% select(year, between_sector_comp, sector_tech),
            by = "year") %>%
  mutate(within_sector_comp = comp_effect - between_sector_comp)

###############################################################################
# SECTION 4B: YEAR-ON-YEAR DECOMPOSITION (no fixed base year)
#
# Instead of comparing every year to 2005, we compare each year t to t-1.
# This avoids the balanced-panel problem: for each pair (t-1, t) we use all
# firms present in BOTH years, which can differ across pairs.
# We then chain the year-on-year changes to build a cumulative index.
#
# For each consecutive pair (t-1, t), among firms present in both:
#   E_scale      = Y_t * sum_i(theta_{i,t-1} * z_{i,t-1})
#   E_scale_comp = Y_t * sum_i(theta_{i,t}   * z_{i,t-1})
#   E_actual     = Y_t * sum_i(theta_{i,t}   * z_{i,t})
#
# Year-on-year changes are then chained multiplicatively.
###############################################################################

yoy_list <- list()

for (yr in (base_year + 1):end_year) {

  # Firms in both t-1 and t (with clean data)
  df_prev <- df %>% filter(year == yr - 1) %>% select(vat, nace2d, theta_prev = theta_it, z_prev = z_it)
  df_curr <- df %>% filter(year == yr)

  df_pair <- df_curr %>%
    inner_join(df_prev, by = "vat", suffix = c("", "_prev"))

  if (nrow(df_pair) == 0) next

  Y_t <- df_pair$Y_t[1]

  E_actual     <- sum(df_pair$theta_it * df_pair$z_it) * Y_t
  E_scale_comp <- sum(df_pair$theta_it * df_pair$z_prev) * Y_t
  E_scale      <- sum(df_pair$theta_prev * df_pair$z_prev) * Y_t

  # Ratios (multiplicative changes relative to t-1 counterfactual)
  yoy_list[[as.character(yr)]] <- tibble(
    year    = yr,
    n_firms = nrow(df_pair),
    # These are ratios: E_actual(t) / E_counterfactual(t using t-1 shares & intensities)
    r_total      = E_actual / E_scale,
    r_scale_comp = E_scale_comp / E_scale,   # reallocation component
    r_tech       = E_actual / E_scale_comp    # technique component
  )
}

yoy <- bind_rows(yoy_list)

# Use LOG decomposition: log changes are additive across years.
# log(E_t / E_{t-1}) = log(Y_t/Y_{t-1}) + log(sum theta_it z_it / sum theta_{i,t-1} z_{i,t-1})
# The last term = log(r_total) = log(r_scale_comp) + log(r_tech)
#   where log(r_scale_comp) = reallocation, log(r_tech) = technique

yoy <- yoy %>%
  arrange(year) %>%
  mutate(
    dlog_total = log(r_total),
    dlog_comp  = log(r_scale_comp),
    dlog_tech  = log(r_total / r_scale_comp),
    # Cumulative sums → cumulative log changes from base year
    cum_total = cumsum(dlog_total),
    cum_comp  = cumsum(dlog_comp),
    cum_tech  = cumsum(dlog_tech),
    # Convert to index (base_year = 100)
    idx_actual_yoy     = 100 * exp(cum_total),
    idx_scale_comp_yoy = 100 * exp(cum_comp),
    # Scale index: chain Y_t / Y_{t-1} separately
    # (not needed for the decomposition but useful for the figure)
  )

# Add the base year row
yoy <- bind_rows(
  tibble(year = base_year, n_firms = nrow(df %>% filter(year == base_year)),
         r_total = 1, r_scale_comp = 1, r_tech = 1,
         dlog_total = 0, dlog_comp = 0, dlog_tech = 0,
         cum_total = 0, cum_comp = 0, cum_tech = 0,
         idx_actual_yoy = 100, idx_scale_comp_yoy = 100),
  yoy
)

# Sector-level year-on-year for between vs within decomposition
yoy_sector_list <- list()
for (yr in (base_year + 1):end_year) {
  sy_prev <- sector_year %>% filter(year == yr - 1) %>%
    select(nace2d, theta_prev = theta_st, z_prev = z_st)
  sy_curr <- sector_year %>% filter(year == yr) %>%
    inner_join(sy_prev, by = "nace2d")

  if (nrow(sy_curr) == 0) next

  Y_t <- sy_curr$Y_t[1]
  E_scale_comp_s <- sum(sy_curr$theta_st * sy_curr$z_prev) * Y_t
  E_scale_s      <- sum(sy_curr$theta_prev * sy_curr$z_prev) * Y_t

  yoy_sector_list[[as.character(yr)]] <- tibble(
    year = yr,
    dlog_between = log(E_scale_comp_s / E_scale_s)
  )
}

yoy_sector <- bind_rows(yoy_sector_list) %>%
  arrange(year) %>%
  mutate(cum_between = cumsum(dlog_between))

yoy_sector <- bind_rows(
  tibble(year = base_year, dlog_between = 0, cum_between = 0),
  yoy_sector
)

# NOTE: The year-on-year within-sector decomposition (firm-level comp vs tech)
# produces extremely noisy results because individual firm shares fluctuate
# massively year to year. The within-sector decomposition is only meaningful
# with a fixed base year (Section 3-4 above).
#
# The year-on-year version is therefore only used for:
#   (a) the TOTAL emission index (robust to sample composition)
#   (b) the between-sector reallocation (sector shares are stable year to year)
#   (c) the residual sector-level technique (between-sector comp + technique)

yoy <- yoy %>%
  left_join(yoy_sector %>% select(year, cum_between), by = "year") %>%
  mutate(
    total_change_yoy    = cum_total * 100,
    between_sector_yoy  = cum_between * 100,
    sector_tech_yoy     = total_change_yoy - between_sector_yoy
  )

cat("\n=== Year-on-year chained decomposition (sector-level only) ===\n")
cat("between_sector = between-sector reallocation\n")
cat("sector_tech    = residual (within-sector abatement + within-sector reallocation)\n\n")
print(as.data.frame(yoy %>%
  filter(year %in% c(base_year, 2008, 2012, 2016, 2019, end_year)) %>%
  select(year, n_firms, total_change_yoy, between_sector_yoy, sector_tech_yoy) %>%
  mutate(across(where(is.numeric) & !matches("n_firms"), ~ round(., 1)))))

###############################################################################
# SECTION 5: FIGURES
###############################################################################

# ---- Figure 0A: Three-line decomposition ----
plot_data_A <- decomp %>%
  select(year, idx_scale, idx_scale_comp, idx_actual) %>%
  pivot_longer(-year, names_to = "series", values_to = "index") %>%
  mutate(series = factor(series,
    levels = c("idx_scale", "idx_scale_comp", "idx_actual"),
    labels = c("(1) Scale only",
               "(2) Scale + Reallocation",
               "(3) Actual")
  ))

p_A <- ggplot(plot_data_A, aes(x = year, y = index, color = series, linetype = series)) +
  geom_line(linewidth = 1.1) +
  geom_point(size = 1.5) +
  geom_hline(yintercept = 100, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = c(2013, 2017, 2021),
             linetype = "dashed", color = "grey70", linewidth = 0.4) +
  annotate("text", x = 2005.5, y = 103, label = "Phase I", size = 2.5, color = "grey50") +
  annotate("text", x = 2009,   y = 103, label = "Phase II", size = 2.5, color = "grey50") +
  annotate("text", x = 2015,   y = 103, label = "Phase III", size = 2.5, color = "grey50") +
  annotate("text", x = 2021.5, y = 103, label = "Phase IV", size = 2.5, color = "grey50") +
  scale_color_manual(values = c(
    "(1) Scale only" = "#2166AC",
    "(2) Scale + Reallocation" = "#4393C3",
    "(3) Actual" = "#D6604D"
  )) +
  scale_linetype_manual(values = c("solid", "longdash", "solid")) +
  labs(
    title = paste0("Firm-level decomposition of Belgian ETS emissions (", base_year, " = 100)"),
    subtitle = paste0("Version A: ETS firms only | Revenue deflated by domestic PPI"),
    x = "", y = paste0("CO2 emissions (", base_year, " = 100)"),
    color = NULL, linetype = NULL,
    caption = paste0("Gap (1)-(2) = reallocation across firms. ",
                     "Gap (2)-(3) = within-firm abatement.")
  ) +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank(),
    legend.position  = "bottom", legend.direction = "vertical",
    axis.line = element_line(color = "black"),
    plot.caption = element_text(hjust = 0, size = 8)
  ) +
  scale_x_continuous(breaks = seq(base_year, end_year, by = 2))

ggsave(file.path(output_fig, paste0("phase0_decomp_firm_level_v",
       switch(emissions_version, ets_only = "A", imputed = "B", bounds = "C"), ".pdf")),
       p_A, width = 10, height = 7)

# ---- Figure 0B: Stacked bar — three channels ----
plot_data_B <- decomp %>%
  select(year, between_sector_comp, within_sector_comp, tech_effect) %>%
  pivot_longer(-year, names_to = "component", values_to = "pp") %>%
  mutate(component = factor(component,
    levels = c("tech_effect", "within_sector_comp", "between_sector_comp"),
    labels = c("Within-firm abatement",
               "Within-sector reallocation",
               "Between-sector reallocation")
  ))

p_B <- ggplot(plot_data_B, aes(x = year, y = pp, fill = component)) +
  geom_bar(stat = "identity", position = "stack", width = 0.7) +
  geom_hline(yintercept = 0, color = "black", linewidth = 0.5) +
  scale_fill_manual(values = c(
    "Within-firm abatement" = "#D6604D",
    "Within-sector reallocation" = "#4393C3",
    "Between-sector reallocation" = "#2166AC"
  )) +
  labs(
    title = paste0("Three channels of emission change (pp relative to ", base_year, ")"),
    subtitle = "Version A: ETS firms only | Revenue deflated by domestic PPI",
    x = "", y = "Percentage points", fill = NULL
  ) +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank(),
    legend.position  = "bottom",
    axis.line = element_line(color = "black")
  ) +
  scale_x_continuous(breaks = seq(base_year, end_year, by = 2))

ggsave(file.path(output_fig, paste0("phase0_decomp_channels_v",
       switch(emissions_version, ets_only = "A", imputed = "B", bounds = "C"), ".pdf")),
       p_B, width = 10, height = 7)

# ---- Figure 0C: Year-on-year chained vs fixed-base comparison (actual only) ----
plot_data_C <- bind_rows(
  decomp %>%
    select(year, idx_actual) %>%
    mutate(method = "Fixed base (2005)") %>%
    rename(index = idx_actual),
  yoy %>%
    select(year, idx_actual_yoy) %>%
    mutate(method = "Year-on-year chained") %>%
    rename(index = idx_actual_yoy)
)

p_C <- ggplot(plot_data_C, aes(x = year, y = index, color = method, linetype = method)) +
  geom_line(linewidth = 1) +
  geom_point(size = 1.5) +
  geom_hline(yintercept = 100, linetype = "dotted", color = "grey50") +
  scale_color_manual(values = c("Fixed base (2005)" = "#D6604D", "Year-on-year chained" = "#4393C3")) +
  scale_linetype_manual(values = c("Fixed base (2005)" = "solid", "Year-on-year chained" = "longdash")) +
  labs(
    title = "Actual emissions: fixed-base vs. year-on-year chained",
    subtitle = paste0("Version A: ETS firms only | ",
                      "Fixed base uses only firms present in 2005 (n=162); ",
                      "YoY uses all firms in each consecutive pair (~160-190)"),
    x = "", y = paste0("CO2 emissions (2005 = 100)"),
    color = NULL, linetype = NULL
  ) +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank(),
    legend.position = "bottom",
    axis.line = element_line(color = "black")
  ) +
  scale_x_continuous(breaks = seq(base_year, end_year, by = 2))

ggsave(file.path(output_fig, paste0("phase0_decomp_comparison_v",
       switch(emissions_version, ets_only = "A", imputed = "B", bounds = "C"), ".pdf")),
       p_C, width = 10, height = 7)

# ---- Figure 0D: Year-on-year stacked bar (two channels: between-sector + residual) ----
plot_data_D <- yoy %>%
  filter(year > base_year) %>%
  select(year, between_sector_yoy, sector_tech_yoy) %>%
  pivot_longer(-year, names_to = "component", values_to = "pp") %>%
  mutate(component = factor(component,
    levels = c("sector_tech_yoy", "between_sector_yoy"),
    labels = c("Within-sector (abatement + reallocation)", "Between-sector reallocation")
  ))

p_D <- ggplot(plot_data_D, aes(x = year, y = pp, fill = component)) +
  geom_bar(stat = "identity", position = "stack", width = 0.7) +
  geom_hline(yintercept = 0, color = "black", linewidth = 0.5) +
  scale_fill_manual(values = c(
    "Within-sector (abatement + reallocation)" = "#D6604D",
    "Between-sector reallocation" = "#2166AC"
  )) +
  labs(
    title = paste0("Year-on-year chained decomposition (pp relative to ", base_year, ")"),
    subtitle = "Version A: ETS firms only | Uses all firms in each consecutive year pair",
    x = "", y = "Percentage points", fill = NULL,
    caption = "Within-sector term combines firm-level abatement and within-sector reallocation (cannot be separated reliably in YoY framework)."
  ) +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank(),
    legend.position = "bottom",
    axis.line = element_line(color = "black"),
    plot.caption = element_text(hjust = 0, size = 7)
  ) +
  scale_x_continuous(breaks = seq(base_year, end_year, by = 2))

ggsave(file.path(output_fig, paste0("phase0_decomp_channels_yoy_v",
       switch(emissions_version, ets_only = "A", imputed = "B", bounds = "C"), ".pdf")),
       p_D, width = 10, height = 7)

cat("Figures saved.\n")

###############################################################################
# SECTION 6: SUMMARY TABLE
###############################################################################

key_years <- c(base_year, 2008, 2012, 2016, 2019, end_year)
key_years <- key_years[key_years <= end_year]

summary_table <- decomp %>%
  filter(year %in% key_years) %>%
  select(year, n_firms, total_change, scale_effect,
         comp_effect, between_sector_comp, within_sector_comp, tech_effect) %>%
  mutate(across(where(is.numeric) & !matches("n_firms"), ~ round(., 1)))

cat("\n=== Phase 0: Firm-Level Decomposition (Version A: ETS-only) ===\n")
cat("Base year:", base_year, "| Revenue deflated by domestic PPI\n")
cat("All effects in pp relative to base year\n\n")
cat("comp_effect        = between_sector + within_sector reallocation\n")
cat("tech_effect        = within-firm abatement\n\n")
print(as.data.frame(summary_table))

write.csv(summary_table,
          file.path(output_tab, paste0("phase0_decomp_summary_v",
                    switch(emissions_version, ets_only = "A", imputed = "B", bounds = "C"), ".csv")),
          row.names = FALSE)

###############################################################################
# SECTION 7: DIAGNOSTICS
###############################################################################

cat("\n=== Diagnostics ===\n")
cat("Base year:", base_year, "\n")
cat("Firms in base year:", nrow(base), "\n")
cat("Sectors (NACE 2d) in base year:", n_distinct(base$nace2d), "\n")
cat("Total ETS emissions in base year (tonnes):",
    format(E_base, big.mark = ","), "\n")
cat("Total ETS emissions in", end_year, "(tonnes):",
    format(decomp %>% filter(year == end_year) %>% pull(E_actual),
           big.mark = ","), "\n")

cat("\n=== Top sectors in base year ===\n")
sector_base <- sector_year %>%
  filter(year == base_year) %>%
  arrange(desc(emissions_s)) %>%
  mutate(share = emissions_s / sum(emissions_s) * 100,
         cum_share = cumsum(share))
print(as.data.frame(sector_base %>%
  select(nace2d, revenue_s, emissions_s, share, cum_share, z_st)))

cat("\n=== Panel attrition (balanced pairs with base year) ===\n")
print(as.data.frame(decomp %>% select(year, n_firms)))
