###############################################################################
# phase3_passthrough_lp_iv_robust.R
#
# PURPOSE:
#   Invertibility-robust LP-IV robustness for §4 Strategy 1 of the paper,
#   following Käenzig (2023, JMP) Appendix C.5 ("Relaxing the invertibility
#   requirement"), equation (13). Companion to the headline panel-LP in
#   phase3_passthrough_iv.R (which uses Käenzig's VAR-extracted Shock as RHS
#   directly, the non-IV form of his eq. 10).
#
# WHY:
#   The headline spec uses the structural Shock from Käenzig's external-
#   instruments SVAR. That identification rests on (partial) invertibility.
#   Käenzig himself reports an LP-IV alternative that is robust to non-
#   invertibility (Li-Plagborg-Møller-Wolf 2024), using the raw Surprise as
#   instrument for the endogenous EUA-driven variation. We replicate that
#   appendix exercise on our Belgian panel.
#
# SPEC (Käenzig eq. 13, panel form with sector-level cross-sectional exposure):
#
#   log(PPI_{s, m+h}) - log(PPI_{s, m-1})
#       = θ_h · ω_{s, t(m)} · ( log p^EUA_m - log p^EUA_{m-1} )
#         + sum_{j=1..6} φ_{h,j} · log PPI_{s, m-j}
#         + α_s + δ_m + ξ_{s, m, h}
#
#   2SLS:
#     endogenous   ω_{s, t(m)} · ( log p^EUA_m - log p^EUA_{m-1} )
#     instrument   ω_{s, t(m)} · CPSurprise_m
#
#   Per Käenzig: "the macroeconomic outcomes several quarters or years out are
#   affected by a myriad of other shocks, rendering the signal-to-noise ratio
#   from the relatively small carbon policy shocks too low to credibly identify
#   the effects of interest." He restricts the LP-IV horizon to 12 months. We
#   follow the same convention.
#
#   FE: nace4d + year-month. Cluster on nace4d. Lag-augmented inference per
#   Montiel-Olea & Plagborg-Møller (2021).
#
# SAMPLE:
#   2010m1 to 2019m12. Matches the headline panel-LP and Käenzig's baseline
#   VAR window.
#
# CPSurprise:
#   Käenzig (2023) refined event-day surprise (Surprise column,
#   carbonPolicyShocks.xlsx Monthly sheet). Pre-VAR object — the headline
#   uses Shock (post-VAR identified); this robustness uses Surprise (raw)
#   as instrument so the identification doesn't rely on the SVAR's
#   invertibility.
#
# INPUT:
#   ${PROC_DATA}/deflator_nace4d_2005base_monthly.RData
#   ${RAW_DATA}/icap_euets_price_2005_26.csv             (daily EUA, 2010+)
#   ${RAW_DATA}/carbonPolicyShocks.xlsx                  (Monthly sheet)
#   ${OUT_DATA}/phase3_sector_omega_rolling.RData
#
# OUTPUT:
#   ${OUTPUT_FIG}/phase3_passthrough_lp_iv_robust.pdf
#   ${OUTPUT_FIG}/phase3_passthrough_lp_iv_robust.png
#   ${OUTPUT_TAB}/phase3_passthrough_lp_iv_robust.csv
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
# 2. Käenzig CPSurprise (the raw refined event-day surprise)
###############################################################################
cps <- read_excel(file.path(RAW_DATA, "carbonPolicyShocks.xlsx"),
                  sheet = "Monthly") %>%
  mutate(year  = as.integer(substr(Date, 1, 4)),
         month = as.integer(substr(Date, 6, 7)),
         date  = as.Date(sprintf("%d-%02d-01", year, month))) %>%
  transmute(date, surprise = Surprise) %>%
  filter(date >= as.Date("2010-01-01") & date <= as.Date("2019-12-01"))

cat(sprintf("CPSurprise (Surprise column): %d months, %s to %s, %d non-zero\n",
            nrow(cps),
            format(min(cps$date)), format(max(cps$date)),
            sum(cps$surprise != 0)))

###############################################################################
# 3. Rolling 1-year ω
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
    surprise    = coalesce(surprise, 0),
    year_month  = format(date, "%Y-%m")
  ) %>%
  filter(!is.na(log_ppi), !is.na(log_eua)) %>%
  arrange(nace4d, date)

cat(sprintf("\nMonthly panel: %d rows, %d sectors, %s to %s\n",
            nrow(panel_m), n_distinct(panel_m$nace4d),
            format(min(panel_m$date)), format(max(panel_m$date))))
cat(sprintf("Sectors with ω_gross > 0: %d\n",
            n_distinct(panel_m$nace4d[panel_m$omega_gross > 0])))

###############################################################################
# 5. Build LHS leads, contemporaneous Δlog EUA, and lag controls
###############################################################################
H_MAX  <- 12L                                 # Käenzig caps LP-IV at 12 months
P_LAGS <- 6L                                  # lag augmentation
horizons <- 0:H_MAX

panel_m <- panel_m %>%
  group_by(nace4d) %>%
  arrange(date) %>%
  mutate(log_ppi_lag1 = dplyr::lag(log_ppi, 1),
         log_eua_lag1 = dplyr::lag(log_eua, 1),
         d_log_eua    = log_eua - log_eua_lag1) %>%
  ungroup()

for (j in 1:P_LAGS) {
  panel_m[[paste0("log_ppi_lag", j)]] <-
    ave(panel_m$log_ppi, panel_m$nace4d,
        FUN = function(x) c(rep(NA_real_, j), head(x, length(x) - j)))
}

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
  mutate(omega_d_log_eua = omega_gross * d_log_eua,
         omega_surprise  = omega_gross * surprise)

###############################################################################
# 6. LP-IV at each horizon h ∈ {0, ..., 12}
###############################################################################
lag_terms <- paste(paste0("log_ppi_lag", 1:P_LAGS), collapse = " + ")

run_lp_iv <- function(h) {
  lhs_col <- paste0("log_ppi_lead", h)
  dat <- panel_m %>%
    transmute(
      nace4d, year_month,
      y_lhs           = .data[[lhs_col]] - log_ppi_lag1,
      omega_d_log_eua,
      omega_surprise,
      log_ppi_lag1, log_ppi_lag2, log_ppi_lag3,
      log_ppi_lag4, log_ppi_lag5, log_ppi_lag6
    ) %>%
    filter(!is.na(y_lhs), !is.na(omega_d_log_eua), !is.na(log_ppi_lag6))

  frm <- as.formula(sprintf(
    "y_lhs ~ %s | nace4d + year_month | omega_d_log_eua ~ omega_surprise",
    lag_terms))
  m <- feols(frm, data = dat, cluster = ~nace4d)

  ct <- coeftable(m)
  fs <- fitstat(m, c("ivf"), simplify = FALSE)
  data.frame(
    h     = h,
    theta = ct["fit_omega_d_log_eua", 1],
    se    = ct["fit_omega_d_log_eua", 2],
    iv_F  = if (!is.null(fs$ivf1$stat)) fs$ivf1$stat else NA_real_,
    n     = m$nobs
  )
}

cat(sprintf("\nRunning LP-IV at horizons 0..%d (Käenzig App. C.5 form)...\n",
            H_MAX))
theta_path <- do.call(rbind, lapply(horizons, run_lp_iv))
theta_path <- theta_path %>%
  mutate(t_stat = theta / se,
         lo95   = theta - 1.96 * se,
         hi95   = theta + 1.96 * se)

cat("\n=== θ_h (LP-IV: Surprise IV for ω × Δlog EUA) ===\n")
print(theta_path %>% select(h, theta, se, t_stat, iv_F, n), digits = 3)

write.csv(theta_path,
          file.path(OUTPUT_TAB, "phase3_passthrough_lp_iv_robust.csv"),
          row.names = FALSE)

###############################################################################
# 7. Plot θ_h
###############################################################################
y_lo <- min(theta_path$lo95)
y_hi <- max(theta_path$hi95)
y_range <- y_hi - y_lo
y_lo_plot <- y_lo - 0.05 * y_range
y_hi_plot <- y_hi + 0.05 * y_range

p <- ggplot(theta_path, aes(x = h, y = theta)) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_ribbon(aes(ymin = lo95, ymax = hi95),
              fill = "steelblue", alpha = 0.30) +
  geom_line(colour = "black", linewidth = 0.7) +
  scale_x_continuous(breaks = seq(0, H_MAX, by = 2),
                     expand = c(0.005, 0.005)) +
  scale_y_continuous(limits = c(y_lo_plot, y_hi_plot),
                     expand = c(0, 0)) +
  labs(x = "Months", y = expression(theta[h])) +
  theme_minimal(base_size = 13) +
  theme(panel.grid = element_blank(),
        axis.line = element_line(colour = "black"),
        axis.ticks = element_line(colour = "black"),
        axis.text = element_text(size = 13, colour = "black"),
        axis.title = element_text(size = 14))

print(p)

ggsave(file.path(OUTPUT_FIG, "phase3_passthrough_lp_iv_robust.pdf"), p,
       width = 6, height = 3.5)
ggsave(file.path(OUTPUT_FIG, "phase3_passthrough_lp_iv_robust.png"), p,
       width = 6, height = 3.5, dpi = 300)

cat("\nSaved:\n  ",
    file.path(OUTPUT_FIG, "phase3_passthrough_lp_iv_robust.pdf"), "\n  ",
    file.path(OUTPUT_FIG, "phase3_passthrough_lp_iv_robust.png"), "\n  ",
    file.path(OUTPUT_TAB, "phase3_passthrough_lp_iv_robust.csv"), "\n")
