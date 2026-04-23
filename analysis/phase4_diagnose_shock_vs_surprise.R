###############################################################################
# phase4_diagnose_shock_vs_surprise.R
#
# Diagnostics for the Spec 1.A shock-vs-surprise sign flip (see
# REALLOCATION_MECHANISM_PLAN follow-up A, and PASSTHROUGH_CPSHOCK.md).
#
# Four checks:
#   1. Correlation between annual cpshock_surprise and cpshock_shock.
#   2. Correlation of each with (a) contemporaneous EUA price changes, and
#      (b) a Belgian business-cycle proxy (aggregate ETS real revenue growth).
#   3. Rerun Spec 1.A on the subsample of years where surprise and shock agree
#      in sign.
#   4. Time-series plot and descriptive comparison of the two annual series.
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(stringr); library(fixest); library(ggplot2)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load series ----
load(file.path(OUT_DATA, "cpshock_annual.RData"))

eua_prices <- tibble(
  year = 2005:2022,
  eua_price = c(22, 18, 0.7, 22, 13, 14, 13, 7.5,
                4.5, 6, 7.5, 5, 5.8, 16, 25, 25, 53, 80)
)

cpshock_annual <- cpshock_annual %>%
  left_join(eua_prices, by = "year") %>%
  arrange(year) %>%
  mutate(d_eua = eua_price - lag(eua_price))

cat("\n=== Annual series, 2005-2019 (Kanzig coverage) ===\n")
print(as.data.frame(cpshock_annual %>%
  filter(year >= 2005, year <= 2019) %>%
  select(year, cpshock_surprise, cpshock_shock, eua_price, d_eua) %>%
  mutate(across(c(cpshock_surprise, cpshock_shock, d_eua), ~round(., 3)))))

# =============================================================================
# DIAGNOSTIC 1: Correlation between surprise and shock at annual frequency
# =============================================================================
d <- cpshock_annual %>% filter(year >= 2005, year <= 2019)

cat("\n=== Diagnostic 1: Corr(surprise, shock) ===\n")
cat("Pearson  :", round(cor(d$cpshock_surprise, d$cpshock_shock), 3), "\n")
cat("Spearman :", round(cor(d$cpshock_surprise, d$cpshock_shock, method = "spearman"), 3), "\n")

# =============================================================================
# DIAGNOSTIC 2: Correlations with macro confounders
# =============================================================================

# (a) Delta EUA (macro price change)
cat("\n=== Diagnostic 2a: Corr with annual Delta EUA ===\n")
cat("Corr(surprise, d_EUA) :", round(cor(d$cpshock_surprise, d$d_eua, use = "complete"), 3), "\n")
cat("Corr(shock,    d_EUA) :", round(cor(d$cpshock_shock,    d$d_eua, use = "complete"), 3), "\n")

# (b) Belgian business-cycle proxy: aggregate real revenue growth of ETS firms
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData"))

ets_agg <- firm_year_belgian_euets %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(!is.na(nace4d), !is.na(revenue), revenue > 0) %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = coalesce(ppi, ppi_2d)) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_rev = revenue / ppi * 100) %>%
  group_by(year) %>%
  summarise(ets_real_rev = sum(real_rev), .groups = "drop") %>%
  arrange(year) %>%
  mutate(ets_rev_growth = (ets_real_rev / lag(ets_real_rev)) - 1)

d2 <- d %>% left_join(ets_agg %>% select(year, ets_rev_growth), by = "year")

cat("\n=== Diagnostic 2b: Corr with Belgian ETS-agg real revenue growth ===\n")
cat("Corr(surprise, ETS rev growth) :", round(cor(d2$cpshock_surprise, d2$ets_rev_growth, use = "complete"), 3), "\n")
cat("Corr(shock,    ETS rev growth) :", round(cor(d2$cpshock_shock,    d2$ets_rev_growth, use = "complete"), 3), "\n")

cat("\n=== Joint correlation matrix (surprise, shock, d_EUA, ETS rev growth) ===\n")
print(round(cor(d2 %>% select(cpshock_surprise, cpshock_shock, d_eua, ets_rev_growth),
                use = "complete"), 3))

# =============================================================================
# DIAGNOSTIC 3: Rerun Spec 1.A restricted to years where surprise and shock agree in sign
# =============================================================================

# Load firm-level treatment panel (should exist from phase4_firm_output_reallocation.R)
# If not, build it minimally here.
treat_path <- file.path(OUT_DATA, "phase4_firm_treatment.rds")
if (!file.exists(treat_path)) stop("Need phase4_firm_treatment.rds from phase4_firm_output_reallocation.R")
firm_treat <- readRDS(treat_path)
cat("\nfirm_treat cols:", paste(names(firm_treat), collapse = ", "), "\n")
cat("firm_treat rows:", nrow(firm_treat), "(one per firm)\n")

# Build firm-year panel: take real revenue from firm_year_belgian_euets + deflator,
# then merge firm-level treatment.
firm_year <- firm_year_belgian_euets %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(!is.na(nace4d), !is.na(revenue), revenue > 0) %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = coalesce(ppi, ppi_2d)) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_revenue = revenue / ppi * 100,
         log_real_rev = log(real_revenue)) %>%
  select(vat, year, nace4d, nace2d, real_revenue, log_real_rev)

# Mark years where surprise and shock agree in sign
cpshock_annual <- cpshock_annual %>%
  mutate(same_sign = sign(cpshock_surprise) == sign(cpshock_shock))

cat("\n=== Diagnostic 3: Years with same-sign surprise and shock ===\n")
print(as.data.frame(cpshock_annual %>%
  filter(year >= 2005, year <= 2019) %>%
  select(year, cpshock_surprise, cpshock_shock, same_sign)))

firm_panel <- firm_year %>%
  inner_join(firm_treat %>% select(vat, firm_dev_share, firm_dev_phys),
             by = "vat") %>%
  left_join(cpshock_annual %>% select(year, cpshock_surprise, cpshock_shock, same_sign),
            by = "year") %>%
  arrange(vat, year) %>%
  group_by(vat) %>%
  mutate(d_log_rev_h0 = log_real_rev - lag(log_real_rev)) %>%
  ungroup() %>%
  filter(year >= 2005, year <= 2019, !is.na(d_log_rev_h0), !is.na(firm_dev_share))

cat("\nPanel rows for Spec 1.A diagnostic:", nrow(firm_panel), "\n")

# Spec 1.A on full panel (sanity reproduction of the known sign flip)
cat("\n=== Spec 1.A on full 2005-2019, surprise variant ===\n")
m_full_surprise <- feols(
  d_log_rev_h0 ~ i(cpshock_surprise, firm_dev_share)
  | vat + nace4d^year,
  cluster = ~ vat + nace4d^year,
  data = firm_panel
)
# Simpler with a single interaction:
m_full_surprise <- feols(
  d_log_rev_h0 ~ firm_dev_share:cpshock_surprise
  | vat + nace4d^year,
  cluster = ~ vat + nace4d^year,
  data = firm_panel
)
print(summary(m_full_surprise))

cat("\n=== Spec 1.A on full 2005-2019, shock variant ===\n")
m_full_shock <- feols(
  d_log_rev_h0 ~ firm_dev_share:cpshock_shock
  | vat + nace4d^year,
  cluster = ~ vat + nace4d^year,
  data = firm_panel
)
print(summary(m_full_shock))

# Restricted to same-sign years
firm_panel_same <- firm_panel %>% filter(same_sign)

cat("\n=== Same-sign subsample: years retained ===\n")
print(sort(unique(firm_panel_same$year)))
cat("Panel rows:", nrow(firm_panel_same), "\n")

cat("\n=== Spec 1.A on same-sign subsample, surprise variant ===\n")
m_same_surprise <- feols(
  d_log_rev_h0 ~ firm_dev_share:cpshock_surprise
  | vat + nace4d^year,
  cluster = ~ vat + nace4d^year,
  data = firm_panel_same
)
print(summary(m_same_surprise))

cat("\n=== Spec 1.A on same-sign subsample, shock variant ===\n")
m_same_shock <- feols(
  d_log_rev_h0 ~ firm_dev_share:cpshock_shock
  | vat + nace4d^year,
  cluster = ~ vat + nace4d^year,
  data = firm_panel_same
)
print(summary(m_same_shock))

# =============================================================================
# DIAGNOSTIC 4: Plot the two series
# =============================================================================

plot_df <- cpshock_annual %>%
  filter(year >= 2005, year <= 2019) %>%
  select(year, surprise = cpshock_surprise, shock = cpshock_shock) %>%
  pivot_longer(-year, names_to = "series", values_to = "value")

p <- ggplot(plot_df, aes(x = year, y = value, color = series, linetype = series)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_line(size = 1) +
  geom_point(size = 2) +
  scale_color_manual(values = c("surprise" = "#2166AC", "shock" = "#D6604D")) +
  labs(title = "Kanzig annual cpshock series: surprise vs shock",
       subtitle = "Sum of monthly values within calendar year",
       x = "", y = "EUR/tCO2") +
  theme_minimal() +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")

ggsave(file.path(OUTPUT_FIG, "phase4_shock_vs_surprise_timeseries.pdf"),
       p, width = 9, height = 5)

cat("\n\nSaved plot:", file.path(OUTPUT_FIG, "phase4_shock_vs_surprise_timeseries.pdf"), "\n")

# ---- Save results ----
sink_path <- file.path(OUTPUT_TAB, "phase4_diagnose_shock_vs_surprise.txt")
sink(sink_path)
cat("=== Diagnostic 1: Corr(surprise, shock) ===\n")
cat("Pearson  :", round(cor(d$cpshock_surprise, d$cpshock_shock), 3), "\n")
cat("Spearman :", round(cor(d$cpshock_surprise, d$cpshock_shock, method = "spearman"), 3), "\n\n")

cat("=== Diagnostic 2: Correlations with macro confounders ===\n")
print(round(cor(d2 %>% select(cpshock_surprise, cpshock_shock, d_eua, ets_rev_growth),
                use = "complete"), 3))

cat("\n=== Diagnostic 3: Same-sign sample ===\n")
cat("Years kept:", paste(sort(unique(firm_panel_same$year)), collapse = ", "), "\n")
cat("Panel rows:", nrow(firm_panel_same), "\n")

cat("\n=== Spec 1.A: full panel ===\n")
cat("Surprise variant:\n"); print(summary(m_full_surprise))
cat("\nShock variant:\n"); print(summary(m_full_shock))

cat("\n=== Spec 1.A: same-sign subsample ===\n")
cat("Surprise variant:\n"); print(summary(m_same_surprise))
cat("\nShock variant:\n"); print(summary(m_same_shock))
sink()

cat("Saved diagnostic tables:", sink_path, "\n")
