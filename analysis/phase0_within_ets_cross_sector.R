###############################################################################
# phase0_within_ets_cross_sector.R
#
# Within-ETS cross-sector output response. Tests whether ETS firms in sectors
# with higher pre-MSR carbon-cost exposure see larger real revenue declines as
# EUA price rises, compared to ETS firms in less exposed sectors.
#
# Spec:
#   log(real_rev)_{i,s,t} = beta * (intensity_base_s * EUA_t)
#                         + alpha_i + delta_t
#                         + epsilon
# - firm FE: absorbs firm size, firm-invariant sector characteristics
#   (intensity_base_s is firm-fixed once sector is fixed).
# - year FE: absorbs all macro shocks common across firms in year t, including
#   the main effect of EUA_t.
# - beta is identified from the interaction: (firm's intensity_base deviation
#   from the ETS-firm-year-avg intensity) x (year's EUA deviation from avg).
# - ETS firms only; 3 contaminated VATs excluded; intensity_base from
#   2013-16 mean of sector carbon cost share (same as phase0_ets_vs_nonets).
# - Run across three sample windows: full 2005-2022, Phase 3 onward 2013-2022,
#   post-base 2017-2022.
#
# Key caveat (documented in the paper note): this design has no non-ETS control
# group, so beta is vulnerable to sector-level omitted variables that correlate
# with both intensity_base and EUA (e.g., energy-price co-movement with EUA
# that hits energy-intensive sectors harder). The ETS-vs-non-ETS spec in
# phase0_ets_vs_nonets_reallocation.R is identification-cleaner for the
# reallocation question; this spec here is the across-ETS-sectors cut asked
# for separately.
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

# ---- Load data ----
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData"))
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))

# ---- Build ETS firm panel with real revenue, intensity_base, and EUA ----
ets_panel <- firm_year_belgian_euets %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(!is.na(nace4d), !is.na(revenue), revenue > 0,
         !(vat %in% contaminated_vats)) %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = coalesce(ppi, ppi_2d)) %>%
  select(-ppi_2d) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_revenue = revenue / ppi * 100,
         log_real_rev = log(real_revenue))

intensity_base <- sector_exposure %>%
  filter(year %in% 2013:2016) %>%
  group_by(nace4d) %>%
  summarise(intensity_base = mean(exposure_alt_total, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(intensity_base = coalesce(intensity_base, 0))

ets_panel <- ets_panel %>%
  left_join(intensity_base, by = "nace4d") %>%
  mutate(intensity_base = coalesce(intensity_base, 0)) %>%
  left_join(eua_prices, by = "year") %>%
  mutate(shock = intensity_base * eua_price * 100)

# ---- Add CPShock-based shifters ----
# cpshock_surprise: sum of Kanzig's daily event-day surprises in each year
# cpshock_shock: VAR-identified structural response (from cpshock_surprise IV)
# Both orthogonal to contemporaneous macro/energy news by Kanzig's identification.
# Coverage ends 2019.
load(file.path(OUT_DATA, "cpshock_annual.RData"))

ets_panel <- ets_panel %>%
  left_join(cpshock_annual %>% select(year, cpshock_surprise, cpshock_shock),
            by = "year") %>%
  mutate(cpshock_surprise = coalesce(cpshock_surprise, 0),
         cpshock_shock    = coalesce(cpshock_shock, 0),
         shock_cps_surprise = intensity_base * cpshock_surprise * 100,
         shock_cps_shock    = intensity_base * cpshock_shock * 100)

cat("\n=== Kanzig CPShock coverage ===\n")
print(ets_panel %>%
  distinct(year, cpshock_surprise, cpshock_shock) %>%
  arrange(year) %>% head(20))

cat("=== Within-ETS cross-sector panel ===\n")
cat("firm-years:      ", nrow(ets_panel), "\n")
cat("distinct firms:  ", n_distinct(ets_panel$vat), "\n")
cat("NACE 4d sectors: ", n_distinct(ets_panel$nace4d), "\n")
cat("intensity_base summary (ETS firm-years):\n")
print(summary(ets_panel$intensity_base))

# ---- Run main spec across three sample windows ----
windows <- list(
  full     = list(label = "A: 2005-2022 (full)",           lo = 2005, hi = 2022),
  phase3   = list(label = "B: 2013-2022 (Phase 3 onward)", lo = 2013, hi = 2022),
  post2016 = list(label = "C: 2017-2022 (post-base)",      lo = 2017, hi = 2022)
)

run_within_ets <- function(df, w) {
  df_w <- df %>% filter(year >= w$lo, year <= w$hi)
  cat("\n===", w$label, "| n =", nrow(df_w),
      "| firms =", n_distinct(df_w$vat), "===\n")
  m <- feols(
    log_real_rev ~ shock
    | vat + year,
    cluster = ~ nace4d,
    data = df_w
  )
  print(summary(m))
  m
}

m_full     <- run_within_ets(ets_panel, windows$full)
m_phase3   <- run_within_ets(ets_panel, windows$phase3)
m_post2016 <- run_within_ets(ets_panel, windows$post2016)

# ---- Robustness: sector-year FE at NACE 2d level (sector-year FE at 4d would
# absorb the treatment since intensity_base is 4d-fixed) ----
cat("\n=== Robustness: 2d * year FE (tests whether 4d-level variation survives
after removing coarser sector-year macro) ===\n")
m_2dyear_full <- feols(
  log_real_rev ~ shock
  | vat + nace2d^year,
  cluster = ~ nace4d,
  data = ets_panel
)
print(summary(m_2dyear_full))

# ---- CPShock-based identification (orthogonal to energy/macro confounders) ----
# Kanzig coverage ends 2019, so the CPShock regressions use years <= 2019.
windows_cps <- list(
  full_cps   = list(label = "CPS-A: 2005-2019 (full CPShock coverage)",
                    lo = 2005, hi = 2019),
  phase3_cps = list(label = "CPS-B: 2013-2019 (Phase 3, CPShock coverage)",
                    lo = 2013, hi = 2019)
)

run_cps <- function(df, w, signal) {
  df_w <- df %>% filter(year >= w$lo, year <= w$hi)
  cat("\n===", w$label, "| Signal:", signal, "| n =", nrow(df_w),
      "| firms =", n_distinct(df_w$vat), "===\n")
  fml <- as.formula(paste0("log_real_rev ~ ", signal, " | vat + year"))
  m <- feols(fml, cluster = ~ nace4d, data = df_w)
  print(summary(m))
  m
}

m_surprise_full   <- run_cps(ets_panel, windows_cps$full_cps,   "shock_cps_surprise")
m_surprise_phase3 <- run_cps(ets_panel, windows_cps$phase3_cps, "shock_cps_surprise")
m_shock_full      <- run_cps(ets_panel, windows_cps$full_cps,   "shock_cps_shock")
m_shock_phase3    <- run_cps(ets_panel, windows_cps$phase3_cps, "shock_cps_shock")

# ---- Summary ----
extract_beta <- function(m, label, varname) {
  co <- coef(m)[varname]
  se <- sqrt(diag(vcov(m)))[varname]
  t <- co / se
  p <- 2 * pt(abs(t), df = m$nobs, lower.tail = FALSE)
  tibble(spec = label, n_obs = m$nobs, beta = co, se = se, t = t, p = p)
}

summary_tbl <- bind_rows(
  extract_beta(m_full,            windows$full$label,            "shock"),
  extract_beta(m_phase3,          windows$phase3$label,          "shock"),
  extract_beta(m_post2016,        windows$post2016$label,        "shock"),
  extract_beta(m_2dyear_full,     "Full panel, 2d x year FE",    "shock"),
  extract_beta(m_surprise_full,   "CPS-A surprise (2005-19)",    "shock_cps_surprise"),
  extract_beta(m_surprise_phase3, "CPS-B surprise (2013-19)",    "shock_cps_surprise"),
  extract_beta(m_shock_full,      "CPS-A shock (2005-19)",       "shock_cps_shock"),
  extract_beta(m_shock_phase3,    "CPS-B shock (2013-19)",       "shock_cps_shock")
)

cat("\n=== Summary: coefficient on shock = 100 * intensity_base_s * EUA_t ===\n")
print(as.data.frame(summary_tbl %>%
  mutate(beta = round(beta, 4), se = round(se, 4), t = round(t, 2), p = round(p, 3))))

# ---- Save ----
out_path <- file.path(OUTPUT_TAB, "phase0_within_ets_cross_sector.txt")
sink(out_path)
cat("=== Within-ETS cross-sector: log(real_rev) ~ shock | firm + year ===\n")
cat("\n=== Window A: 2005-2022 (full) ===\n"); print(summary(m_full))
cat("\n=== Window B: 2013-2022 (Phase 3 onward) ===\n"); print(summary(m_phase3))
cat("\n=== Window C: 2017-2022 (post-base) ===\n"); print(summary(m_post2016))
cat("\n=== Robustness: 2d x year FE, full panel ===\n"); print(summary(m_2dyear_full))
cat("\n=== CPShock surprise, 2005-2019 ===\n"); print(summary(m_surprise_full))
cat("\n=== CPShock surprise, 2013-2019 ===\n"); print(summary(m_surprise_phase3))
cat("\n=== CPShock shock, 2005-2019 ===\n"); print(summary(m_shock_full))
cat("\n=== CPShock shock, 2013-2019 ===\n"); print(summary(m_shock_phase3))
cat("\n=== Summary across specs ===\n")
print(as.data.frame(summary_tbl %>%
  mutate(beta = round(beta, 4), se = round(se, 4), t = round(t, 2), p = round(p, 3))))
sink()

write.csv(summary_tbl,
          file.path(OUTPUT_TAB, "phase0_within_ets_cross_sector.csv"),
          row.names = FALSE)

cat("\nSaved:", out_path, "\n")
