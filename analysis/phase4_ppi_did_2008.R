###############################################################################
# phase4_ppi_did_2008.R
#
# PURPOSE:
#   Appendix (d) of the pass-through section: a Phase-II-onset placebo /
#   robustness exercise that mirrors phase4_ppi_did_2017.R but uses
#     - treatment year = 2008 (start of Phase II auctioning),
#     - ω built on 2006-2007 (Phase I, the only fully pre-Phase-II window
#       with EUTL coverage),
#     - regression sample 2000m1-2019m12.
#
# SPECS (each regression separately):
#   log(PPI_{s,m}) = β · X_s · 1{year(m) >= 2008} + α_s + δ_m + ε_{s,m}
#   X_s ∈ { Treated_s, ω^em_s (2006-07), ω^sh_s (2006-07) }, time-invariant
#   α_s = NACE 4d FE; δ_m = year-month FE; SE clustered on NACE 4-digit.
#
# DATA NOTES:
#   - Pre-2010 PPI is available only as eurostat_2d values (the 2-digit
#     PPI broadcast to every 4-digit child); 2010+ PPI is the chained
#     statbel 4-digit series. The DiD identifies β off the post-2010 4-digit
#     variation interacted with X_s; the pre-period contributes through the
#     time FE absorbing the 2-digit level.
#   - In Phase I (2005-2007), free allocation was extremely generous, so
#     fewer NACE 4-digit sectors have positive ω^sh than in 2015-16. We use
#     all sectors and let the regression see zeros where appropriate.
#
# OUTPUT:
#   ${OUTPUT_TAB}/phase4_ppi_did_2008.csv
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

TREAT_YEAR <- 2008
OMEGA_YRS  <- 2006:2007
TREATED_2D <- c("17", "19", "20", "23", "24", "25", "35")
SAMPLE_FROM <- as.Date("2000-01-01")
SAMPLE_TO   <- as.Date("2019-12-01")

# ---- 1. Monthly PPI panel (both sources) ----
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))

ppi <- deflator_monthly %>%
  filter(!is.na(ppi), ppi > 0,
         ppi_source %in% c("statbel_4d_chained", "eurostat_2d"),
         date >= SAMPLE_FROM, date <= SAMPLE_TO) %>%
  mutate(year   = year(date),
         nace2d = str_pad(nace2d, 2, pad = "0")) %>%
  filter(as.integer(nace2d) %in% c(10:33, 35)) %>%
  mutate(log_ppi    = log(ppi),
         post       = as.integer(year >= TREAT_YEAR),
         year_month = format(date, "%Y-%m"),
         treated_d  = as.integer(nace2d %in% TREATED_2D))

cat(sprintf("PPI panel: %d obs, %d sectors, %s to %s\n",
            nrow(ppi), n_distinct(ppi$nace4d),
            format(min(ppi$date)), format(max(ppi$date))))
cat(sprintf("  Sources used: %s\n",
            paste(unique(ppi$ppi_source), collapse = ", ")))
cat(sprintf("  Treated sectors: %d  /  Untreated: %d\n",
            n_distinct(ppi$nace4d[ppi$treated_d == 1]),
            n_distinct(ppi$nace4d[ppi$treated_d == 0])))

# ---- 2. ω measures on 2006-2007 ----
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

omega_avg <- function(df, num_col, yrs) {
  df %>% filter(year %in% yrs, !is.na(.data[[num_col]])) %>%
    group_by(nace4d) %>%
    summarise(num = sum(.data[[num_col]], na.rm = TRUE),
              den = sum(total_cost_denom, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(omega = num / den) %>%
    select(nace4d, omega)
}

omega_em <- omega_avg(exposure, "total_emissions", OMEGA_YRS) %>%
  rename(omega_em = omega)
omega_sh <- omega_avg(exposure, "total_shortage",  OMEGA_YRS) %>%
  rename(omega_sh = omega)

ppi <- ppi %>%
  left_join(omega_em, by = "nace4d") %>%
  left_join(omega_sh, by = "nace4d") %>%
  mutate(omega_em = coalesce(omega_em, 0),
         omega_sh = coalesce(omega_sh, 0))

cat(sprintf("\nω windows: %s\n",
            paste(range(OMEGA_YRS), collapse = "-")))
cat(sprintf("Sectors with ω^em > 0: %d  (max %.4f)\n",
            sum(omega_em$omega_em > 0, na.rm = TRUE),
            max(omega_em$omega_em, na.rm = TRUE)))
cat(sprintf("Sectors with ω^sh > 0: %d  (max %.4f)\n",
            sum(omega_sh$omega_sh > 0, na.rm = TRUE),
            max(omega_sh$omega_sh, na.rm = TRUE)))

# ---- 3. Run the three DiD specs ----
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
    data.frame(spec = "(A) Treated × Post(2008)",
               coef = coef(m_A)[1], se = se(m_A)[1], n = m_A$nobs),
    data.frame(spec = "(B) omega_em × Post(2008)",
               coef = coef(m_B)[1], se = se(m_B)[1], n = m_B$nobs),
    data.frame(spec = "(C) omega_sh × Post(2008)",
               coef = coef(m_C)[1], se = se(m_C)[1], n = m_C$nobs)
  )
  out$window <- win_label
  out$t_stat <- out$coef / out$se
  out$lo90   <- out$coef - 1.645 * out$se
  out$hi90   <- out$coef + 1.645 * out$se
  out$lo95   <- out$coef - 1.96  * out$se
  out$hi95   <- out$coef + 1.96  * out$se

  cat("\nResults:\n")
  print(out %>% mutate(across(c(coef, se, t_stat, lo90, hi90, lo95, hi95),
                              ~ round(.x, 4))) %>%
        select(spec, coef, se, t_stat, lo90, hi90, n))
  out
}

res <- run_specs(ppi, "2000m1-2019m12 (ω from 2006-07)")

# ---- 4. Save ----
out <- res %>% select(window, spec, coef, se, t_stat, lo90, hi90, lo95, hi95, n)
write.csv(out, file.path(OUTPUT_TAB, "phase4_ppi_did_2008.csv"),
          row.names = FALSE)
cat(sprintf("\nSaved: %s\n",
            file.path(OUTPUT_TAB, "phase4_ppi_did_2008.csv")))

cat("\n========== SUMMARY ==========\n")
print(out %>% mutate(across(c(coef, se, lo90, hi90), ~ round(.x, 4))) %>%
      select(window, spec, coef, se, lo90, hi90, n))
