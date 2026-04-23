###############################################################################
# phase0_ets_vs_nonets_reallocation.R
#
# Replaces the old phase0_ets_share_shift.R. Tests whether non-ETS firms gain
# revenue share relative to ETS firms in sectors with high carbon-cost
# exposure, as EUA price rises.
#
# Fixes applied vs. the predecessor:
#   (1) NACE 4d aggregation (not 2d).
#   (2) Mixed-sector restriction: only NACE 4d sectors with both ETS and
#       non-ETS firms present in >= 1 year.
#   (3) Bartik-style exposure: intensity_base_s (pre-MSR 2013-16 mean of
#       sector ETS carbon cost share) x EUA_t. Pre-determined in the numerator,
#       pre-determined in the denominator; only the EUA scalar moves.
#   (4) Clustered SEs on NACE 4d.
#   (5) Firm-level log(real_rev) LHS with ETS x shock interaction, not a
#       revenue-ratio LHS (which suffered from denominator endogeneity).
#   (6) Sample: includes non-ETS firms in zero-emission ETS sectors (NACE 17,
#       18, 19, and parts of 24) which were previously dropped because they
#       live in training_sample (with imputed e=0) rather than deployment_panel.
#       These are exactly the competitors we want to see for the big emitting
#       sectors (paper, petroleum, parts of metals).
#
# Output:
#   output/tables/phase0_ets_vs_nonets_reallocation.txt
#   output/tables/phase0_ets_vs_nonets_reallocation.csv
###############################################################################

rm(list = ls())

library(dplyr)
library(tidyr)
library(stringr)
library(fixest)

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Config ----
year_lo <- 2005
year_hi <- 2022

contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)

eua_prices <- tibble(
  year = 2005:2022,
  eua_price = c(22, 18, 0.7, 22, 13, 14, 13, 7.5,
                4.5, 6, 7.5, 5, 5.8, 16, 25, 25, 53, 80)
)

# ---- Load raw panels ----
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
load(file.path(PROC_DATA, "training_sample.RData"))
load(file.path(PROC_DATA, "deployment_panel.RData"))
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData"))

# ---- Build combined firm-year panel ----
# ETS firms: take directly from firm_year_belgian_euets (authoritative).
ets_panel <- firm_year_belgian_euets %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(year >= year_lo, year <= year_hi,
         !is.na(nace4d), !is.na(revenue), revenue > 0) %>%
  transmute(vat, year, nace2d, nace4d, revenue, is_ets = 1L)

ets_vats <- unique(ets_panel$vat)

# Non-ETS firms: union of (training_sample where euets = 0) and deployment_panel,
# deduplicated. This captures:
#   - training_sample zero-sector non-ETS firms (NACE 17, 18, 19, zero-24): excluded
#     from deployment_panel but live in training_sample with imputed e=0.
#   - deployment_panel: non-ETS firms in all other ETS-covered sectors.
train_nonets <- training_sample %>%
  filter(euets == 0) %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  select(vat, year, nace2d, nace4d, revenue)

deploy_panel <- deployment_panel %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  select(vat, year, nace2d, nace4d, revenue)

nonets_panel <- bind_rows(train_nonets, deploy_panel) %>%
  distinct(vat, year, .keep_all = TRUE) %>%       # dedupe by firm-year
  filter(!(vat %in% ets_vats),                    # strict non-ETS
         year >= year_lo, year <= year_hi,
         !is.na(nace4d), !is.na(revenue), revenue > 0) %>%
  mutate(is_ets = 0L)

firm_panel <- bind_rows(ets_panel, nonets_panel)

cat("=== Panel composition ===\n")
cat("ETS firm-years:      ", sum(firm_panel$is_ets == 1), "\n")
cat("Non-ETS firm-years:  ", sum(firm_panel$is_ets == 0), "\n")
cat("Distinct ETS firms:  ", n_distinct(firm_panel$vat[firm_panel$is_ets == 1]), "\n")
cat("Distinct non-ETS:    ", n_distinct(firm_panel$vat[firm_panel$is_ets == 0]), "\n\n")

# ---- Apply deflator ----
firm_panel <- firm_panel %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = coalesce(ppi, ppi_2d)) %>%
  select(-ppi_2d) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_revenue = revenue / ppi * 100,
         log_real_rev = log(real_revenue))

# ---- Restrict to mixed 4d sectors ----
mixed_nace4d <- firm_panel %>%
  group_by(nace4d) %>%
  summarise(has_ets = any(is_ets == 1),
            has_nonets = any(is_ets == 0),
            .groups = "drop") %>%
  filter(has_ets, has_nonets) %>%
  pull(nace4d)

cat("Mixed NACE 4d sectors (both ETS and non-ETS firms present): ", length(mixed_nace4d), "\n\n")

firm_panel <- firm_panel %>% filter(nace4d %in% mixed_nace4d)

# ---- Exclude the 3 contaminated ETS VATs from every year ----
firm_panel <- firm_panel %>% filter(!(vat %in% contaminated_vats))

# ---- Merge intensity_base at NACE 4d (2013-16 mean of sector exposure_alt_total) ----
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))

intensity_base <- sector_exposure %>%
  filter(year %in% 2013:2016) %>%
  group_by(nace4d) %>%
  summarise(intensity_base = mean(exposure_alt_total, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(intensity_base = coalesce(intensity_base, 0))

firm_panel <- firm_panel %>%
  left_join(intensity_base, by = "nace4d") %>%
  mutate(intensity_base = coalesce(intensity_base, 0)) %>%
  left_join(eua_prices, by = "year")

# Bartik-style shock: pre-determined sector exposure x aggregate EUA.
# Rescale so coefficients are readable: shock in units of "% carbon cost share x
# EUR/tCO2". intensity_base has a median of ~5e-6, mean ~3e-4, max 5e-3; EUA
# ranges 0-80. Multiplying by 100 gives shock in units where 1 = 1 pp of
# baseline carbon cost share, per EUR of EUA.
firm_panel <- firm_panel %>%
  mutate(shock = intensity_base * eua_price * 100)

cat("intensity_base summary (across 4d sectors, pre-MSR carbon cost share):\n")
print(summary(unique(firm_panel[, c("nace4d", "intensity_base")])$intensity_base))

cat("\n=== Sample for regressions ===\n")
cat("firm-years:        ", nrow(firm_panel), "\n")
cat("distinct firms:    ", n_distinct(firm_panel$vat), "\n")
cat("NACE 4d sectors:   ", n_distinct(firm_panel$nace4d), "\n")
cat("Years:             ", min(firm_panel$year), "-", max(firm_panel$year), "\n")
cat("ETS firm-years:    ", sum(firm_panel$is_ets == 1), "\n")
cat("Non-ETS firm-years:", sum(firm_panel$is_ets == 0), "\n\n")

###############################################################################
# REGRESSION
#
# log(real_rev)_{i,s,t} = beta * ETS_i * intensity_base_s * EUA_t
#                       + gamma * ETS_i * EUA_t
#                       + alpha_i + alpha_{s,t}
#                       + epsilon
#
# - alpha_i (firm FE) absorbs ETS status, firm-invariant sector, time-invariant
#   scale.
# - alpha_{s,t} (NACE 4d x year FE) absorbs intensity_base_s * EUA_t main effect
#   and all sector-year macro variation (crucially, EUA_t itself).
# - beta: within a 4d sector-year, how much more does an ETS firm's log real
#   revenue move with shock_{s,t} than a non-ETS firm's. Under reallocation,
#   beta < 0.
# - gamma: common ETS-vs-non-ETS time trend proportional to EUA_t; not of
#   primary interest but keep it unconfounded.
# Standard errors clustered on NACE 4d.
###############################################################################

m_main <- feols(
  log_real_rev ~ is_ets:shock + is_ets:eua_price
  | vat + nace4d^year,
  cluster = ~ nace4d,
  data = firm_panel
)

cat("\n=== Main spec: log(real_rev) ~ ETS:shock + ETS:EUA | firm + 4d*year ===\n")
print(summary(m_main))

# Robustness 1: swap firm FE for 4d FE (identifies off cross-firm within sector,
# not within firm over time). Expect different magnitudes because ETS firms
# are systematically larger.
m_sectorFE <- feols(
  log_real_rev ~ is_ets + is_ets:shock + is_ets:eua_price
  | nace4d + year,
  cluster = ~ nace4d,
  data = firm_panel
)

cat("\n=== Robustness: 4d + year FE (no firm FE) ===\n")
print(summary(m_sectorFE))

# Robustness 2: first differences at annual horizon
firm_panel <- firm_panel %>%
  group_by(vat) %>%
  arrange(year, .by_group = TRUE) %>%
  mutate(d_log_real_rev = log_real_rev - lag(log_real_rev),
         d_shock = shock - lag(shock),
         d_eua = eua_price - lag(eua_price)) %>%
  ungroup()

m_fd <- feols(
  d_log_real_rev ~ is_ets:d_shock + is_ets:d_eua
  | vat + nace4d^year,
  cluster = ~ nace4d,
  data = firm_panel %>% filter(!is.na(d_log_real_rev))
)

cat("\n=== Robustness: first differences ===\n")
print(summary(m_fd))

# Simpler spec: just the ETS x EUA interaction (no sector heterogeneity).
# Tests whether ETS firms broadly respond differently from non-ETS as EUA rises,
# independent of sector dirtiness.
m_simple <- feols(
  log_real_rev ~ is_ets:eua_price
  | vat + nace4d^year,
  cluster = ~ nace4d,
  data = firm_panel
)

cat("\n=== Simpler spec: log(real_rev) ~ ETS:EUA | firm + 4d*year ===\n")
print(summary(m_simple))

# ---- Save a compact output table ----
out_path <- file.path(OUTPUT_TAB, "phase0_ets_vs_nonets_reallocation.txt")
sink(out_path)
cat("=== Main spec: log(real_rev) ~ ETS x shock + ETS x EUA | firm + 4d*year ===\n")
print(summary(m_main))
cat("\n=== Robustness 4d+year FE (no firm FE) ===\n")
print(summary(m_sectorFE))
cat("\n=== Robustness first differences ===\n")
print(summary(m_fd))
cat("\n=== Simpler spec: ETS x EUA only ===\n")
print(summary(m_simple))
sink()

cat("\nSaved:", out_path, "\n")
