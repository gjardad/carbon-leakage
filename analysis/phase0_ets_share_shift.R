###############################################################################
# phase0_ets_share_shift.R
#
# PURPOSE:
#   Has output shifted from ETS to non-ETS firms within ETS sectors?
#   Correlate the change in ETS output share with carbon cost exposure,
#   including dynamic (lagged) effects.
#
#   No imputed emissions needed — only output data + ETS status.
#
# DATA:
#   - NBB_data/processed/firm_year_belgian_euets.RData (for ETS firm IDs + emissions)
#   - NBB_data/processed/annual_accounts_selected_sample.RData (all firms' revenue)
#   - NBB_data/processed/deflator_nace4d_2005base.RData
###############################################################################

rm(list = ls())

library(dplyr)
library(stringr)
library(tidyr)
library(ggplot2)

# ---- Paths ----
nbb_data     <- "c:/Users/jota_/Documents/NBB_data"
project_root <- "c:/Users/jota_/Documents/carbon_policy_networks"
proc_data    <- file.path(nbb_data, "processed")
output_fig   <- file.path(project_root, "output", "figures")
output_tab   <- file.path(project_root, "output", "tables")

base_year <- 2005
end_year  <- 2021

# ---- Load data ----
load(file.path(proc_data, "deflator_nace4d_2005base.RData"))
load(file.path(proc_data, "firm_year_belgian_euets.RData"))
load(file.path(proc_data, "training_sample.RData"))     # ETS + matched non-ETS firms
load(file.path(proc_data, "deployment_panel.RData"))     # all non-ETS firms

# ---- Build full panel: training (ETS) + deployment (non-ETS) ----
# Training sample has euets flag; deployment panel is all non-ETS
ets_panel <- training_sample %>%
  filter(euets == 1) %>%
  select(vat, year, nace5d, revenue) %>%
  mutate(is_ets = 1L)

nonets_panel <- deployment_panel %>%
  select(vat, year, nace5d, revenue) %>%
  mutate(is_ets = 0L)

all_firms <- bind_rows(ets_panel, nonets_panel) %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(year >= base_year, year <= end_year,
         !is.na(nace2d), !is.na(revenue), revenue > 0)

# Restrict to sectors containing at least one ETS firm
ets_nace2d <- unique(all_firms$nace2d[all_firms$is_ets == 1])
ets_nace2d <- ets_nace2d[!is.na(ets_nace2d)]

all_firms <- all_firms %>%
  filter(nace2d %in% ets_nace2d)

# Deflate revenue
all_firms <- all_firms %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi), by = c("nace2d", "year")) %>%
  mutate(ppi = ifelse(is.na(ppi), ppi_2d, ppi)) %>%
  select(-ppi_2d) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_revenue = revenue / ppi * 100)

cat("Firms in ETS sectors:", n_distinct(all_firms$vat), "\n")
cat("  ETS firms:", n_distinct(all_firms$vat[all_firms$is_ets == 1]), "\n")
cat("  Non-ETS firms:", n_distinct(all_firms$vat[all_firms$is_ets == 0]), "\n")
cat("Firm-years:", nrow(all_firms), "\n")

# ---- ETS output share by sector-year ----
sector_year <- all_firms %>%
  group_by(nace2d, year) %>%
  summarise(
    total_rev = sum(real_revenue),
    ets_rev   = sum(real_revenue[is_ets == 1]),
    n_total   = n_distinct(vat),
    n_ets     = n_distinct(vat[is_ets == 1]),
    n_nonets  = n_total - n_ets,
    .groups = "drop"
  ) %>%
  mutate(ets_share = ets_rev / total_rev)

# ---- Carbon cost exposure from EUTL ----
eua_prices <- tibble(
  year = 2005:2021,
  eua_price = c(22, 18, 0.7, 22, 13, 14, 13, 7.5,
                4.5, 6, 7.5, 5, 5.8, 16, 25, 25, 53)
)

# Use firm_year_belgian_euets for emissions + allowances (has allocated_free)
carbon_exp <- firm_year_belgian_euets %>%
  mutate(nace2d = str_sub(nace5d, 1, 2)) %>%
  filter(year >= base_year, year <= end_year, !is.na(nace2d)) %>%
  left_join(eua_prices, by = "year") %>%
  group_by(nace2d, year) %>%
  summarise(
    sector_emissions = sum(emissions, na.rm = TRUE),
    sector_shortage  = sum(pmax(emissions - allocated_free, 0), na.rm = TRUE),
    eua_price = first(eua_price),
    .groups = "drop"
  ) %>%
  mutate(carbon_cost = sector_shortage * eua_price)

sector_year <- sector_year %>%
  left_join(carbon_exp, by = c("nace2d", "year")) %>%
  mutate(carbon_cost_share = carbon_cost / total_rev)

# ---- Year-on-year changes + lags ----
sector_year <- sector_year %>%
  arrange(nace2d, year) %>%
  group_by(nace2d) %>%
  mutate(
    delta_ets_share = ets_share - lag(ets_share),
    lag0_ccs = carbon_cost_share,
    lag1_ccs = lag(carbon_cost_share, 1),
    lag2_ccs = lag(carbon_cost_share, 2),
    lag3_ccs = lag(carbon_cost_share, 3)
  ) %>%
  ungroup() %>%
  filter(!is.na(delta_ets_share))

###############################################################################
# FIGURES
###############################################################################

# ---- Figure 1: ETS share over time by sector ----
top_sectors <- sector_year %>%
  filter(year == base_year + 1) %>%
  slice_max(ets_rev, n = 7) %>%
  pull(nace2d)

p1 <- ggplot(sector_year %>% filter(nace2d %in% top_sectors),
             aes(x = year, y = ets_share, color = nace2d)) +
  geom_line(linewidth = 1) +
  geom_point(size = 1.5) +
  geom_vline(xintercept = c(2013, 2017), linetype = "dashed", color = "grey70") +
  labs(
    title = "ETS firms' output share within their sector",
    subtitle = "Top 7 sectors by ETS revenue | Denominator = all firms in Annual Accounts",
    x = "", y = "ETS share of sector real revenue", color = "NACE 2d"
  ) +
  theme_minimal() +
  theme(legend.position = "right", axis.line = element_line(color = "black")) +
  scale_x_continuous(breaks = seq(base_year, end_year, by = 2)) +
  scale_y_continuous(labels = scales::percent_format())

ggsave(file.path(output_fig, "phase0_ets_output_share_over_time.pdf"), p1, width = 10, height = 6)

# ---- Figure 2: Aggregate ETS share ----
agg_share <- all_firms %>%
  group_by(year) %>%
  summarise(ets_share = sum(real_revenue[is_ets == 1]) / sum(real_revenue), .groups = "drop")

p2 <- ggplot(agg_share, aes(x = year, y = ets_share)) +
  geom_line(linewidth = 1.2, color = "#D6604D") +
  geom_point(size = 2, color = "#D6604D") +
  geom_vline(xintercept = c(2013, 2017), linetype = "dashed", color = "grey70") +
  labs(
    title = "Aggregate output share of ETS firms (across all ETS sectors)",
    subtitle = "Denominator = all firms in Annual Accounts sample in ETS-containing sectors",
    x = "", y = "ETS firms' share of total revenue"
  ) +
  theme_minimal() +
  theme(axis.line = element_line(color = "black")) +
  scale_x_continuous(breaks = seq(base_year, end_year, by = 2)) +
  scale_y_continuous(labels = scales::percent_format())

ggsave(file.path(output_fig, "phase0_ets_agg_output_share.pdf"), p2, width = 9, height = 5)

# ---- Figure 3: Scatter of delta_ets_share vs lagged carbon cost ----
p3 <- ggplot(sector_year %>% filter(!is.na(lag1_ccs)),
             aes(x = lag1_ccs * 100, y = delta_ets_share * 100)) +
  geom_point(aes(color = nace2d, size = total_rev), alpha = 0.5) +
  geom_smooth(method = "lm", se = TRUE, color = "black", linewidth = 0.7) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  labs(
    title = "Change in ETS output share vs. lagged carbon cost",
    subtitle = "Each dot = sector-year | Raw correlation (no FE)",
    x = "Carbon cost (t-1) as % of sector revenue",
    y = "Year-on-year change in ETS output share (pp)",
    color = "NACE 2d", size = "Sector revenue"
  ) +
  theme_minimal() +
  theme(legend.position = "right")

ggsave(file.path(output_fig, "phase0_delta_ets_share_vs_lag_carbon_cost.pdf"),
       p3, width = 10, height = 7)

cat("Figures saved.\n")

###############################################################################
# REGRESSIONS
###############################################################################

cat("\n=== Correlations: delta_ets_share vs carbon cost share ===\n")
cat("Contemporaneous:", round(cor(sector_year$delta_ets_share,
    sector_year$lag0_ccs, use = "complete"), 3), "\n")
cat("Lag 1:", round(cor(sector_year$delta_ets_share,
    sector_year$lag1_ccs, use = "complete"), 3), "\n")
cat("Lag 2:", round(cor(sector_year$delta_ets_share,
    sector_year$lag2_ccs, use = "complete"), 3), "\n")
cat("Lag 3:", round(cor(sector_year$delta_ets_share,
    sector_year$lag3_ccs, use = "complete"), 3), "\n")

cat("\n=== Regressions with sector + year FE ===\n")
cat("Negative coef = higher carbon cost -> ETS firms lose share to non-ETS\n\n")

# Individual lags
for (h in 0:3) {
  varname <- paste0("lag", h, "_ccs")
  formula_str <- paste0("delta_ets_share ~ ", varname, " + factor(nace2d) + factor(year)")
  m <- lm(as.formula(formula_str), data = sector_year)
  coef_val <- coef(m)[varname]
  se_val <- summary(m)$coefficients[varname, "Std. Error"]
  t_val <- summary(m)$coefficients[varname, "t value"]
  p_val <- summary(m)$coefficients[varname, "Pr(>|t|)"]
  cat(sprintf("Lag %d: coef = %8.4f  se = %8.4f  t = %5.2f  p = %5.3f\n",
              h, coef_val, se_val, t_val, p_val))
}

# Distributed lag (all lags 0-3 together)
cat("\n--- Distributed lag (lags 0-3 jointly) ---\n")
m_dl <- lm(delta_ets_share ~ lag0_ccs + lag1_ccs + lag2_ccs + lag3_ccs +
            factor(nace2d) + factor(year), data = sector_year)

for (h in 0:3) {
  varname <- paste0("lag", h, "_ccs")
  cat(sprintf("  Lag %d: %8.4f (%.4f)\n", h,
              coef(m_dl)[varname], summary(m_dl)$coefficients[varname, "Std. Error"]))
}
sum_coefs <- sum(coef(m_dl)[paste0("lag", 0:3, "_ccs")])
cat(sprintf("  Sum:   %8.4f\n", sum_coefs))

# F-test for joint significance
if (requireNamespace("car", quietly = TRUE)) {
  library(car)
  ftest <- linearHypothesis(m_dl, c("lag0_ccs = 0", "lag1_ccs = 0",
                                     "lag2_ccs = 0", "lag3_ccs = 0"))
  cat(sprintf("  F-test joint: F = %.2f, p = %.3f\n", ftest$F[2], ftest[["Pr(>F)"]][2]))
}

cat("\nDone.\n")
