###############################################################################
# phase4_ppi_did_2017.R
#
# PURPOSE:
#   Diff-in-diff regressions of Belgian NACE 4-digit log-PPI on three
#   pre-treatment exposure measures interacted with a post-2017 dummy:
#     (A) binary Treated_s × Post_t   (CdGM-broad NACE 2d set)
#     (B) ω_emissions_s × Post_t      (ω built on 2015–2016 emissions/cost)
#     (C) ω_shortage_s  × Post_t      (ω built on 2015–2016 shortage/cost)
#
# SPEC (each regression separately):
#   log(PPI_{s,m}) = β · X_s · Post_m + α_s + δ_m + ε_{s,m}
#   Post_m = 1 if year(m) >= 2017.  α_s = NACE 4d FE; δ_m = year-month FE.
#   X_s ∈ { Treated_s, ω_emissions_s, ω_shortage_s }, time-invariant.
#   Standard errors clustered on NACE 4-digit.
#
# DATA FILTERS (matches phase4_ppi_2017_treatment_plots.R):
#   - PPI: pure 4-digit Statbel (deflator_monthly with ppi_source ==
#     "statbel_4d_chained") plus NACE 1920, 3510, 3520 from the older
#     Statbel file (2015+).
#   - Manufacturing + utilities: NACE 2d ∈ {10..33, 35}.
#   - ω: emissions, shortage, and total cost from sector_exposure on
#     2015–2016, with NACE Rev 2 utility codes (3511, 3522) re-mapped to
#     Statbel-BEL (3510, 3520) so utilities match the PPI panel.
#
# SAMPLE WINDOWS:
#   Headline: 2010m1–2022m12 (matches plots).
#   Robustness: 2010m1–2019m12 (pre-COVID, no Ukraine energy spike).
#
# OUTPUT:
#   ${OUTPUT_TAB}/phase4_ppi_did_2017.csv  (all six coefficients)
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readxl); library(stringr)
  library(lubridate); library(fixest)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

TREAT_YEAR <- 2017
TREATED_2D <- c("17", "19", "20", "23", "24", "25", "35")

# ---- 1. Load main pure-4d PPI panel ----
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))

ppi_main <- deflator_monthly %>%
  filter(!is.na(ppi), ppi > 0,
         ppi_source == "statbel_4d_chained",
         date >= as.Date("2010-01-01"), date <= as.Date("2022-12-01")) %>%
  mutate(year = year(date),
         nace2d = str_pad(nace2d, 2, pad = "0"))

# ---- 2. Append NACE 1920, 3510, 3520 from old Statbel (2015+) ----
old_file <- file.path(RAW_DATA, "Statbel",
                      "Statbel_TABEL_WEBSITE_AANGEVERS_2021_EN.xlsx")
TARGET_4D <- c("1920", "3510", "3520")
d_old <- read_excel(old_file, sheet = "Domestic market", col_names = FALSE)
names(d_old) <- c("nace4d_raw", "label_or_year",
                  "Jan","Feb","Mar","Apr","May","Jun",
                  "Jul","Aug","Sep","Oct","Nov","Dec","Annual")
d_old <- d_old %>%
  mutate(nace4d = ifelse(!is.na(nace4d_raw),
                         as.character(nace4d_raw), NA_character_)) %>%
  tidyr::fill(nace4d, .direction = "down") %>%
  mutate(year = suppressWarnings(as.integer(label_or_year))) %>%
  filter(!is.na(year), nace4d %in% TARGET_4D) %>%
  mutate(across(c(Jan:Dec), as.numeric)) %>%
  select(nace4d, year, Jan:Dec) %>%
  pivot_longer(cols = Jan:Dec, names_to = "month_abbr", values_to = "ppi") %>%
  mutate(month  = match(month_abbr, month.abb),
         date   = as.Date(sprintf("%d-%02d-01", year, month)),
         nace2d = str_sub(str_pad(nace4d, 4, pad = "0"), 1, 2),
         ppi_source = "statbel_4d_old_file") %>%
  filter(!is.na(ppi), ppi > 0,
         date >= as.Date("2010-01-01"), date <= as.Date("2022-12-01")) %>%
  select(nace4d, nace2d, date, year, month, ppi, ppi_source)

ppi <- bind_rows(ppi_main, d_old) %>%
  filter(as.integer(nace2d) %in% c(10:33, 35)) %>%
  mutate(log_ppi    = log(ppi),
         post       = as.integer(year >= TREAT_YEAR),
         year_month = format(date, "%Y-%m"),
         treated_d  = as.integer(nace2d %in% TREATED_2D))

cat(sprintf("PPI panel: %d obs, %d sectors, %s to %s\n",
            nrow(ppi), n_distinct(ppi$nace4d),
            format(min(ppi$date)), format(max(ppi$date))))
cat(sprintf("  Treated sectors: %d  /  Untreated: %d\n",
            n_distinct(ppi$nace4d[ppi$treated_d == 1]),
            n_distinct(ppi$nace4d[ppi$treated_d == 0])))
cat(sprintf("  Pre-2017 months: %d  /  Post-2017 months: %d\n",
            n_distinct(ppi$year_month[ppi$post == 0]),
            n_distinct(ppi$year_month[ppi$post == 1])))

# ---- 3. ω measures on 2015-2016 ----
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))
manuf_set <- c(sprintf("%02d", 10:33), "35")

exposure <- sector_exposure %>%
  mutate(nace2d = str_sub(str_pad(nace4d, 4, pad = "0"), 1, 2)) %>%
  filter(nace2d %in% manuf_set,
         !is.na(total_cost_denom), total_cost_denom > 0) %>%
  mutate(nace4d = case_when(
    str_detect(nace4d, "^351[1-4]$") ~ "3510",
    str_detect(nace4d, "^352[1-3]$") ~ "3520",
    TRUE                              ~ nace4d
  )) %>%
  group_by(nace4d, year, nace2d) %>%
  summarise(total_emissions  = sum(total_emissions,  na.rm = TRUE),
            total_shortage   = sum(total_shortage,   na.rm = TRUE),
            total_cost_denom = sum(total_cost_denom, na.rm = TRUE),
            .groups = "drop")

omega_avg <- function(df, num_col, yrs = 2015:2016) {
  df %>% filter(year %in% yrs, !is.na(.data[[num_col]])) %>%
    group_by(nace4d) %>%
    summarise(num = sum(.data[[num_col]], na.rm = TRUE),
              den = sum(total_cost_denom, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(omega = num / den) %>% select(nace4d, omega)
}

omega_em_15_16 <- omega_avg(exposure, "total_emissions") %>%
  rename(omega_em = omega)
omega_sh_15_16 <- omega_avg(exposure, "total_shortage") %>%
  rename(omega_sh = omega)

ppi <- ppi %>%
  left_join(omega_em_15_16, by = "nace4d") %>%
  left_join(omega_sh_15_16, by = "nace4d") %>%
  mutate(omega_em = coalesce(omega_em, 0),
         omega_sh = coalesce(omega_sh, 0))

cat(sprintf("\nNACE 4d sectors with omega_em > 0: %d  (max %.4f)\n",
            sum(omega_em_15_16$omega_em > 0, na.rm = TRUE),
            max(omega_em_15_16$omega_em, na.rm = TRUE)))
cat(sprintf("NACE 4d sectors with omega_sh > 0: %d  (max %.4f)\n",
            sum(omega_sh_15_16$omega_sh > 0, na.rm = TRUE),
            max(omega_sh_15_16$omega_sh, na.rm = TRUE)))

# Cross-sectional SD of each X_s across the unique NACE 4d sectors that
# enter the regression panel. Sectors without ω (no EUTL data) carry zero,
# so they contribute to the cross-sectional dispersion just as the
# regression sees them.
xsec <- ppi %>% distinct(nace4d, .keep_all = TRUE) %>%
  select(nace4d, treated_d, omega_em, omega_sh)
sd_treated <- sd(xsec$treated_d)
sd_omega_em <- sd(xsec$omega_em)
sd_omega_sh <- sd(xsec$omega_sh)
cat(sprintf("\nCross-sectional SDs (across %d NACE 4d in panel):\n", nrow(xsec)))
cat(sprintf("  SD(Treated) = %.4f\n", sd_treated))
cat(sprintf("  SD(ω^em)    = %.6e\n", sd_omega_em))
cat(sprintf("  SD(ω^sh)    = %.6e\n", sd_omega_sh))

# ---- 4. Run the three DiD specs on each window ----
run_specs <- function(panel, win_label) {
  cat(sprintf("\n========== %s (n_obs = %d, n_sectors = %d) ==========\n",
              win_label, nrow(panel), n_distinct(panel$nace4d)))

  m_A <- feols(log_ppi ~ I(treated_d * post) | nace4d + year_month,
               data = panel, cluster = ~nace4d)
  m_B <- feols(log_ppi ~ I(omega_em  * post) | nace4d + year_month,
               data = panel, cluster = ~nace4d)
  m_C <- feols(log_ppi ~ I(omega_sh  * post) | nace4d + year_month,
               data = panel, cluster = ~nace4d)

  out <- bind_rows(
    data.frame(spec = "(A) Treated × Post",
               coef = coef(m_A)[1], se = se(m_A)[1],
               sd_X = sd_treated,  n = m_A$nobs),
    data.frame(spec = "(B) omega_emissions × Post",
               coef = coef(m_B)[1], se = se(m_B)[1],
               sd_X = sd_omega_em, n = m_B$nobs),
    data.frame(spec = "(C) omega_shortage  × Post",
               coef = coef(m_C)[1], se = se(m_C)[1],
               sd_X = sd_omega_sh, n = m_C$nobs)
  )
  out$window <- win_label
  out$t_stat <- out$coef / out$se
  out$lo90   <- out$coef - 1.645 * out$se
  out$hi90   <- out$coef + 1.645 * out$se
  out$lo95   <- out$coef - 1.96  * out$se
  out$hi95   <- out$coef + 1.96  * out$se
  # Standardized: β × SD(X), with the same t-stat (SE × SD).
  out$std_coef <- out$coef * out$sd_X
  out$std_se   <- out$se   * out$sd_X
  out$std_lo90 <- out$lo90 * out$sd_X
  out$std_hi90 <- out$hi90 * out$sd_X
  out$std_lo95 <- out$lo95 * out$sd_X
  out$std_hi95 <- out$hi95 * out$sd_X
  cat("\nResults (raw):\n")
  print(out %>% mutate(across(c(coef, se, t_stat, lo90, hi90, lo95, hi95),
                              ~ round(.x, 4))) %>%
        select(spec, coef, se, t_stat, lo90, hi90, n))
  cat("\nResults (β × SD(X), with the same t-stat):\n")
  print(out %>% mutate(across(c(std_coef, std_se, std_lo90, std_hi90,
                                std_lo95, std_hi95, sd_X),
                              ~ signif(.x, 4))) %>%
        select(spec, sd_X, std_coef, std_se, t_stat, std_lo90, std_hi90, n))
  out
}

panel_22 <- ppi
panel_19 <- ppi %>% filter(date <= as.Date("2019-12-01"))

res_22 <- run_specs(panel_22, "2010m1-2022m12 (headline)")
res_19 <- run_specs(panel_19, "2010m1-2019m12 (pre-COVID, pre-energy-crisis)")

# ---- 5. Save and summarise ----
all_res <- bind_rows(res_22, res_19) %>%
  select(window, spec, sd_X,
         coef, se, t_stat, lo90, hi90, lo95, hi95,
         std_coef, std_se, std_lo90, std_hi90, std_lo95, std_hi95, n)

write.csv(all_res, file.path(OUTPUT_TAB, "phase4_ppi_did_2017.csv"),
          row.names = FALSE)
cat(sprintf("\nSaved: %s\n",
            file.path(OUTPUT_TAB, "phase4_ppi_did_2017.csv")))

cat("\n========== SUMMARY ==========\n")
cat("Coefficient interpretation:\n")
cat("  (A) Treated × Post: log-PPI difference for CdGM-broad treated\n")
cat("      sectors after 2017 vs untreated. exp(coef) - 1 = % rise.\n")
cat("  (B) omega_em × Post: per-unit-of-(tCO2/EUR) post-2017 differential.\n")
cat("      Multiply by a sector's omega_em (e.g. 0.005 for cement) for\n")
cat("      that sector's implied post-2017 PPI lift.\n")
cat("  (C) omega_sh × Post: same but using shortage instead of gross.\n")
print(all_res %>% mutate(across(c(coef, se, lo90, hi90),
                                 ~ round(.x, 4))) %>%
      select(window, spec, coef, se, lo90, hi90, n))
