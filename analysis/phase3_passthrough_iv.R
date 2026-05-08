###############################################################################
# phase3_passthrough_iv.R
#
# PURPOSE:
#   Estimate sector-level pass-through of EU ETS regulatory news to NACE 4d
#   PPI via Käenzig's (2023, JMP) Panel Local Projection specification with
#   lag-augmentation. Reports γ_h on (ω × CPShock) directly and the implied
#   pass-through elasticity β_h via post-hoc normalisation.
#
# SPEC (following Käenzig 2023 eq. 10):
#
#   log(PPI_{s, m+h}) - log(PPI_{s, m-1})
#       = γ_h · ω_{s, t(m)} · CPShock_m
#         + α_{s,h} + δ_{m,h}
#         + Σ_{j=1..p} β_{h,j} · log(PPI_{s, m-j})
#         + ε_{s,m,h}
#
#   Estimation: OLS with 2-way FE (sector × time). p = 6 lags. Cluster on
#   nace4d. The lag-augmentation soaks up LHS persistence without affecting
#   γ_h identification (Plagborg-Møller-Wolf 2021).
#
# ω_{s, t(m)} = trailing 2-yr (year t-1, t-2) mean of (gross_emissions × EUA)
#               / total_cost at sector s. Predetermined relative to month m,
#               updates annually. Coalesced to zero for non-ETS sectors so
#               they remain in the panel and contribute to FE estimation.
#
# Post-hoc elasticity normalisation:
#   Following Käenzig: report γ_h as the panel-LP coefficient, then express
#   in elasticity units via the aggregate impact response R_0 of EUA prices
#   to a unit CPShock. β_h = γ_h / R_0 gives the elasticity of PPI with
#   respect to a 1% EUA price change at impact, scaled by ω.
#
# SAMPLE:
#   2010m1 to 2019m12. ICAP daily EUA starts 2010m1; 2019m12 matches Käenzig's
#   original VAR sample (1999m1-2019m12) and avoids the COVID + 2021-22 gas
#   crisis confounds. Phase IV extension (BKR 2026 baseline 2013-2024) is
#   feasible in principle but introduces sectoral gas-price confounders that
#   are not absorbed by aggregate year-month FE in our cross-sectional design.
#
# CPShock series:
#   Käenzig (2023) refined event-day surprise, VAR-identified Shock column
#   (sign-normalised so a unit shock → upward EUA price move on impact).
#
# INPUT:
#   ${PROC_DATA}/deflator_nace4d_2005base_monthly.RData  (deflator_monthly)
#   ${RAW_DATA}/icap_euets_price_2005_26.csv             (daily EUA, 2010+)
#   ${RAW_DATA}/carbonPolicyShocks.xlsx                  (Käenzig CPShock,
#                                                         Monthly sheet)
#   ${OUT_DATA}/phase3_sector_omega_rolling.RData        (sector_omega_rolling)
#
# OUTPUT:
#   ${OUTPUT_FIG}/phase3_passthrough_iv.pdf
#   ${OUTPUT_FIG}/phase3_passthrough_iv.png
#   ${OUTPUT_TAB}/phase3_passthrough_iv.csv  (per-horizon γ_h, β_h, SE, n)
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readxl)
  library(readr)
  library(lubridate)
  library(fixest)
  library(ggplot2)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

###############################################################################
# 1. Monthly EUA from ICAP daily
###############################################################################
icap_file <- file.path(RAW_DATA, "icap_euets_price_2005_26.csv")
icap_raw <- read_csv(
  icap_file,
  skip = 2,
  col_names = c("date", "fx1_eur", "fx1_usd", "ccy1", "price_pre2019", "sp1",
                "fx2_eur", "fx2_usd", "ccy2", "price_from2019", "price_secondary",
                "sp2"),
  col_types = cols(
    date = col_date(format = "%Y-%m-%d"),
    price_pre2019 = col_double(),
    price_from2019 = col_double(),
    price_secondary = col_double(),
    .default = col_character()
  )
)

eua_monthly <- icap_raw %>%
  mutate(price = coalesce(price_pre2019, price_from2019, price_secondary)) %>%
  filter(!is.na(date), !is.na(price)) %>%
  mutate(year = year(date), month = month(date)) %>%
  group_by(year, month) %>%
  summarise(eua_price = mean(price), n_days = n(), .groups = "drop") %>%
  mutate(date = as.Date(sprintf("%d-%02d-01", year, month)),
         log_eua = log(eua_price))

cat(sprintf("Monthly EUA: %d months, %s to %s\n",
            nrow(eua_monthly),
            format(min(eua_monthly$date)), format(max(eua_monthly$date))))

###############################################################################
# 2. Käenzig CPShock series (Shock = VAR-identified, sign-normalised)
###############################################################################
cps <- read_excel(file.path(RAW_DATA, "carbonPolicyShocks.xlsx"),
                  sheet = "Monthly") %>%
  mutate(year  = as.integer(substr(Date, 1, 4)),
         month = as.integer(substr(Date, 6, 7)),
         date  = as.Date(sprintf("%d-%02d-01", year, month))) %>%
  transmute(date, cps = Shock) %>%
  filter(date >= as.Date("2010-01-01") & date <= as.Date("2019-12-01"))

cat(sprintf("CPShock (Shock column): %d months, %s to %s, %d non-zero\n",
            nrow(cps),
            format(min(cps$date)), format(max(cps$date)),
            sum(cps$cps != 0)))

###############################################################################
# 3. Rolling-window ω
###############################################################################
load(file.path(OUT_DATA, "phase3_sector_omega_rolling.RData"))
omega <- sector_omega_rolling %>%
  select(nace4d, year, omega_gross, omega_short, omega_free)

cat(sprintf("ω panel: %d sector-years, %d distinct NACE 4d\n",
            nrow(omega), n_distinct(omega$nace4d)))

###############################################################################
# 4. Build the monthly LP panel
###############################################################################
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))

panel_m <- deflator_monthly %>%
  filter(date >= as.Date("2010-01-01"),
         date <= as.Date("2019-12-01")) %>%
  mutate(year = year(date)) %>%
  left_join(omega, by = c("nace4d", "year")) %>%
  left_join(eua_monthly %>% select(date, log_eua), by = "date") %>%
  left_join(cps, by = "date") %>%
  mutate(
    log_ppi     = log(ppi),
    omega_gross = coalesce(omega_gross, 0),
    omega_short = coalesce(omega_short, 0),
    omega_free  = coalesce(omega_free,  0),
    cps         = coalesce(cps, 0),
    year_month  = format(date, "%Y-%m")
  ) %>%
  filter(!is.na(log_ppi)) %>%
  arrange(nace4d, date)

cat(sprintf("\nMonthly panel: %d rows, %d sectors, %s to %s\n",
            nrow(panel_m), n_distinct(panel_m$nace4d),
            format(min(panel_m$date)), format(max(panel_m$date))))
cat(sprintf("Sectors with ω_gross > 0: %d\n",
            n_distinct(panel_m$nace4d[panel_m$omega_gross > 0])))

###############################################################################
# 5. Build LHS leads, lags of log_ppi, and the regressor ω × CPShock
###############################################################################
H_MAX <- 36L
P_LAGS <- 6L                       # number of LHS lags for augmentation
horizons <- 0:H_MAX

panel_m <- panel_m %>%
  group_by(nace4d) %>%
  arrange(date) %>%
  mutate(log_ppi_lag1 = dplyr::lag(log_ppi, 1)) %>%
  ungroup()

# Lags of log_ppi for lag-augmentation
for (j in 1:P_LAGS) {
  panel_m[[paste0("log_ppi_lag", j)]] <-
    ave(panel_m$log_ppi, panel_m$nace4d,
        FUN = function(x) c(rep(NA_real_, j), head(x, length(x) - j)))
}

# Leads at each horizon
for (h in horizons) {
  panel_m[[paste0("log_ppi_lead", h)]] <-
    ave(panel_m$log_ppi, panel_m$nace4d,
        FUN = function(x) {
          n <- length(x); out <- rep(NA_real_, n)
          for (i in seq_len(n)) if ((i + h) <= n) out[i] <- x[i + h]
          out
        })
}

panel_m <- panel_m %>%
  mutate(omega_cps = omega_gross * cps)

###############################################################################
# 6. Panel-LP at each horizon (Käenzig eq. 10, lag-augmented)
###############################################################################
lag_terms <- paste(paste0("log_ppi_lag", 1:P_LAGS), collapse = " + ")

run_lp <- function(h) {
  lhs_col <- paste0("log_ppi_lead", h)
  dat <- panel_m %>%
    transmute(
      nace4d, year_month,
      y_lhs = .data[[lhs_col]] - log_ppi_lag1,
      omega_cps,
      log_ppi_lag1, log_ppi_lag2, log_ppi_lag3,
      log_ppi_lag4, log_ppi_lag5, log_ppi_lag6
    ) %>%
    filter(!is.na(y_lhs), !is.na(log_ppi_lag6))

  frm <- as.formula(sprintf("y_lhs ~ omega_cps + %s | nace4d + year_month",
                            lag_terms))
  m <- feols(frm, data = dat, cluster = ~nace4d)
  ct <- coeftable(m)
  data.frame(
    h     = h,
    gamma = ct["omega_cps", 1],
    se    = ct["omega_cps", 2],
    n     = m$nobs
  )
}

cat(sprintf("\nRunning panel-LP at horizons 0..%d (Käenzig eq. 10)...\n", H_MAX))
gamma_path <- do.call(rbind, lapply(horizons, run_lp))
gamma_path <- gamma_path %>%
  mutate(t_stat = gamma / se,
         lo95   = gamma - 1.96 * se,
         hi95   = gamma + 1.96 * se)

cat("\n=== γ_h (panel-LP, ω = ω_gross × CPShock_Shock) ===\n")
print(gamma_path %>% select(h, gamma, se, t_stat, n), digits = 3)

###############################################################################
# 7. Aggregate impact response R_0: response of Δlog EUA to a unit CPShock
###############################################################################
ts <- panel_m %>%
  distinct(date, log_eua, cps) %>%
  arrange(date) %>%
  mutate(d_log_eua = log_eua - dplyr::lag(log_eua, 1)) %>%
  filter(!is.na(d_log_eua), !is.na(cps))

m_R0 <- feols(d_log_eua ~ cps, data = ts)
ct_R0 <- coeftable(m_R0)
R0_hat <- ct_R0["cps", 1]
R0_se  <- ct_R0["cps", 2]

cat(sprintf("\nAggregate impact response R_0: Δlog EUA = %.4f × CPShock + ε  (s.e. %.4f, t = %.2f, n = %d)\n",
            R0_hat, R0_se, R0_hat / R0_se, nobs(m_R0)))

# Implied elasticity β_h = γ_h / R_0 (delta-method SE ignoring R_0 variance)
gamma_path <- gamma_path %>%
  mutate(beta      = gamma / R0_hat,
         beta_se   = abs(se / R0_hat),
         beta_lo95 = beta - 1.96 * beta_se,
         beta_hi95 = beta + 1.96 * beta_se)

cat("\n=== Implied elasticity β_h = γ_h / R_0 ===\n")
print(gamma_path %>% select(h, gamma, beta, beta_se, beta_lo95, beta_hi95) %>%
        head(15), digits = 3)

write.csv(gamma_path,
          file.path(OUTPUT_TAB, "phase3_passthrough_iv.csv"),
          row.names = FALSE)

###############################################################################
# 8. Plot γ_h (panel-LP coefficient on ω × CPShock)
#
# Note: we plot γ_h directly rather than the implied β_h = γ_h / R_0 because
# the aggregate impact response R_0 is small at the monthly level (CPShock
# explains <1% of monthly Δlog EUA variation), making β_h numerically unstable.
# Käenzig (2023) sidesteps this by reporting his IRFs in "+1% HICP energy on
# impact" units via the SVAR's structural identification, not via a raw
# monthly first stage. We follow the same convention here: γ_h is the
# panel-LP coefficient; the caption explains how to read it as a pass-through
# magnitude.
###############################################################################
y_lo <- min(gamma_path$lo95)
y_hi <- max(gamma_path$hi95)
y_range <- y_hi - y_lo
y_lo_plot <- y_lo - 0.05 * y_range
y_hi_plot <- y_hi + 0.05 * y_range

p <- ggplot(gamma_path, aes(x = h, y = gamma)) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_ribbon(aes(ymin = lo95, ymax = hi95),
              fill = "steelblue", alpha = 0.30) +
  geom_line(colour = "black", linewidth = 0.7) +
  scale_x_continuous(breaks = seq(0, H_MAX, by = 6),
                     expand = c(0.005, 0.005)) +
  scale_y_continuous(limits = c(y_lo_plot, y_hi_plot),
                     expand = c(0, 0)) +
  labs(x = "Months", y = expression(gamma[h])) +
  theme_minimal(base_size = 13) +
  theme(panel.grid = element_blank(),
        axis.line = element_line(colour = "black"),
        axis.ticks = element_line(colour = "black"),
        axis.text = element_text(size = 13, colour = "black"),
        axis.title = element_text(size = 14))

print(p)

ggsave(file.path(OUTPUT_FIG, "phase3_passthrough_iv.pdf"), p,
       width = 6, height = 3.5)
ggsave(file.path(OUTPUT_FIG, "phase3_passthrough_iv.png"), p,
       width = 6, height = 3.5, dpi = 300)

cat("\nSaved:\n  ",
    file.path(OUTPUT_FIG, "phase3_passthrough_iv.pdf"), "\n  ",
    file.path(OUTPUT_FIG, "phase3_passthrough_iv.png"), "\n  ",
    file.path(OUTPUT_TAB, "phase3_passthrough_iv.csv"), "\n")
