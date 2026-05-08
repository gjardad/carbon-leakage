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
# ω_{s, t(m)} = (gross_emissions × EUA) / total_cost at sector s, year t-1
#               (where t is the calendar year of month m). Predetermined,
#               updates annually. Coalesced to zero for non-ETS sectors so
#               they remain in the panel and contribute to FE estimation.
#
# Post-hoc elasticity normalisation:
#   Following Käenzig: report γ_h as the panel-LP coefficient, then express
#   in elasticity units via the aggregate impact response of EUA prices to
#   a unit CPShock. β_h = γ_h / R_bar with R_bar = mean R_h over h ∈ [12,24]
#   (the mid-horizon window where the EUA IRF is well-identified).
#
# SAMPLE WINDOWS (two runs in this script):
#   1. 2008m1--2019m12, ω = emissions/cost  — HEADLINE (excludes Phase I,
#      where Phase I 2007 EUA-near-zero attenuates sectoral PPI response per
#      CPShock and dilutes γ_h). Writes phase3_passthrough_iv_*_phase2plus.{
#      pdf,png,csv} — referenced as Figure 3 in §4 of the paper.
#   2. 2013m1--2019m12, ω = emissions/cost  — Phase III only. Appendix
#      robustness; statistically equivalent to the headline (mean |z| = 0.54
#      across horizons) but with ~1.7× wider confidence bands due to the
#      smaller sample (84 vs 144 months; 479 vs 821 sector-year cells with
#      ω > 0).
#
#   Both end at 2019m12 to match Käenzig's VAR closure and avoid COVID +
#   2021-22 gas-price confounders.
#
# OMEGA DEFINITION (UPDATED):
#   ω is now a PHYSICAL emissions intensity (tCO2 per EUR of cost), with
#   NO contemporaneous EUA factor. Rationale: in Phase I (2007) and parts
#   of Phase II, EUA prices collapsed to near zero, so the previous
#   carbon-cost-share definition (emissions × EUA / cost) collapsed across
#   all sectors and lost cross-sectional identifying variation. Removing
#   the EUA factor preserves cross-sectional ω-variation across all years.
#   The EUA-price channel still enters the regression — but only through
#   the CPShock interaction, not through ω.
#
# β NORMALIZATION:
#   Under Shephard's lemma at full pass-through, ΔlogPPI = ω_old × ΔlogEUA
#   = ω_new × EUA × ΔlogEUA. Empirically R̄ = E[ΔlogEUA / CPShock], so
#   γ × CPShock = ω_new × EUA × R̄ × CPShock at full pass-through, giving
#   γ ≈ E[EUA] × R̄. We therefore define
#       β_h = γ_h / (R̄_ref × E[EUA_in_sample])
#   so β_h = 1 corresponds to full Shephard's-lemma pass-through, matching
#   the interpretation under the previous ω convention.
#
#   R̄_ref is a STRUCTURAL REFERENCE, not the in-sample R̄. Reason: on long
#   samples that include Phase I (2007 overallocation crash from €30 to €0)
#   and Phase II (2008-09 financial-crisis collapse from €25 to €8), the
#   aggregate first stage Δlog EUA on CPShock is dominated by non-CPShock
#   structural breaks; in-sample R̄ collapses or flips sign. The panel-LP
#   γ_h is unaffected by these breaks because year-month FE absorb them,
#   but the elasticity normalization needs a stable denominator. We use
#   R̄_ref = mean R_h over h ∈ [12,24] estimated on the 2013m1-2019m12
#   post-MSR window, where the first stage is strong (consistent with the
#   ~0.092 published R̄ on 2010m1-2019m12 and Käenzig's ~10% peak EUA IRF).
#
# CPShock series:
#   Käenzig (2023) refined event-day surprise, VAR-identified Shock column
#   (sign-normalised so a unit shock → upward EUA price move on impact).
#
# INPUT:
#   ${PROC_DATA}/deflator_nace4d_2005base_monthly.RData  (deflator_monthly)
#   ${RAW_DATA}/European Union Carbon Permits Allowance (EUA) Yearly
#               Futures Historical Data.csv             (daily EUA, 2005+)
#   ${RAW_DATA}/carbonPolicyShocks.xlsx                  (Käenzig CPShock,
#                                                         Monthly sheet)
#   ${OUT_DATA}/phase3_sector_omega_rolling.RData        (sector_omega_rolling)
#
# OUTPUT (two sets):
#   ${OUTPUT_FIG}/phase3_passthrough_iv{suffix}.pdf       (β_h)
#   ${OUTPUT_FIG}/phase3_passthrough_iv_gamma{suffix}.pdf (γ_h)
#   ${OUTPUT_FIG}/phase3_passthrough_iv_Rh{suffix}.pdf    (R_h)
#   ${OUTPUT_TAB}/phase3_passthrough_iv{suffix}.csv
#     where suffix ∈ {"_phase2plus", "_phase3plus"}.
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

MIN_DATE <- as.Date("2008-01-01")  # earliest run start; ω uses t-1 = 2007
END_DATE <- as.Date("2019-12-01")
H_MAX    <- 36L
P_LAGS   <- 6L
horizons <- 0:H_MAX

###############################################################################
# 1. Monthly EUA from new daily front-year futures CSV (2005-04-25+)
###############################################################################
eua_file <- file.path(
  RAW_DATA,
  "European Union Carbon Permits Allowance (EUA) Yearly Futures Historical Data.csv"
)
eua_raw <- read_csv(
  eua_file,
  col_types = cols(
    Date  = col_date(format = "%m/%d/%Y"),
    Price = col_double(),
    .default = col_character()
  )
)

eua_monthly <- eua_raw %>%
  rename(date = Date, price = Price) %>%
  filter(!is.na(date), !is.na(price)) %>%
  mutate(year = year(date), month = month(date)) %>%
  group_by(year, month) %>%
  summarise(eua_price = mean(price), n_days = n(), .groups = "drop") %>%
  mutate(date = as.Date(sprintf("%d-%02d-01", year, month)),
         log_eua = log(eua_price)) %>%
  arrange(date)

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
  filter(date >= MIN_DATE & date <= END_DATE)

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
# 4. Build the union monthly panel (filtered per-window inside run_window)
###############################################################################
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))

panel_full <- deflator_monthly %>%
  filter(date >= MIN_DATE, date <= END_DATE) %>%
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

cat(sprintf("\nUnion panel (%s-%s): %d rows, %d sectors\n",
            format(MIN_DATE, "%Ym%m"), format(END_DATE, "%Ym%m"),
            nrow(panel_full), n_distinct(panel_full$nace4d)))

###############################################################################
# 5a. Estimate R̄_ref once on the 2013m1-2019m12 post-MSR window.
#     This is the aggregate EUA-IRF, run on the cleanest window for the
#     first-stage; reused as the normalization denominator for all panel-LP
#     runs below.
###############################################################################
estimate_R_bar <- function(start_date, end_date) {
  ts <- panel_full %>%
    filter(date >= start_date, date <= end_date) %>%
    distinct(date, log_eua, cps) %>% arrange(date)
  for (j in 1:P_LAGS) ts[[paste0("log_eua_lag", j)]] <- dplyr::lag(ts$log_eua, j)
  ts$log_eua_lag1 <- dplyr::lag(ts$log_eua, 1)
  for (h in horizons) {
    ts[[paste0("log_eua_lead", h)]] <-
      sapply(seq_len(nrow(ts)),
             function(i) if ((i + h) <= nrow(ts)) ts$log_eua[i + h] else NA_real_)
  }
  eua_lag_terms <- paste(paste0("log_eua_lag", 1:P_LAGS), collapse = " + ")
  R_path <- do.call(rbind, lapply(horizons, function(h) {
    lhs_col <- paste0("log_eua_lead", h)
    dat <- ts %>%
      transmute(y_eua = .data[[lhs_col]] - log_eua_lag1, cps,
                log_eua_lag1, log_eua_lag2, log_eua_lag3,
                log_eua_lag4, log_eua_lag5, log_eua_lag6) %>%
      filter(!is.na(y_eua), !is.na(log_eua_lag6))
    frm <- as.formula(sprintf("y_eua ~ cps + %s", eua_lag_terms))
    m <- feols(frm, data = dat, vcov = "hetero")
    ct <- coeftable(m)
    data.frame(h = h, R = ct["cps", 1], R_se = ct["cps", 2])
  }))
  list(R_bar    = mean(R_path$R[R_path$h %in% 12:24], na.rm = TRUE),
       R_bar_se = sqrt(mean(R_path$R_se[R_path$h %in% 12:24]^2, na.rm = TRUE) /
                       sum(R_path$h %in% 12:24)),
       R_path   = R_path)
}

REF_WINDOW <- list(start = as.Date("2013-01-01"), end = END_DATE,
                   label = "2013m1-2019m12 (post-MSR)")
ref_R <- estimate_R_bar(REF_WINDOW$start, REF_WINDOW$end)
R_BAR_REF    <- ref_R$R_bar
R_BAR_REF_SE <- ref_R$R_bar_se
cat(sprintf("\n--- Reference R̄ for normalization ---\n"))
cat(sprintf("Window: %s\n", REF_WINDOW$label))
cat(sprintf("R̄_ref (mean R_h over h=12..24): %.4f  (s.e. %.4f)\n",
            R_BAR_REF, R_BAR_REF_SE))

###############################################################################
# 5b. Window-runner: rebuilds lags/leads inside each window, runs the
#    panel-LP, computes the in-sample R̄ for diagnostic purposes, and
#    converts γ_h into β_h using the FIXED R̄_ref (not the in-sample R̄).
#
#    omega_var: "omega_gross" (main, emissions/cost) or "omega_short"
#               (robustness, shortage/cost).
###############################################################################
run_window <- function(start_date, suffix, win_label, omega_var = "omega_gross") {
  cat(sprintf("\n\n========== %s (%s onward, ω = %s) ==========\n",
              win_label, format(start_date), omega_var))

  panel_w <- panel_full %>% filter(date >= start_date)

  # Lags of log_ppi (rebuilt within the window so pre-window obs do not enter
  # as either LHS or as lagged-control RHS)
  panel_w <- panel_w %>%
    group_by(nace4d) %>% arrange(date) %>%
    mutate(log_ppi_lag1 = dplyr::lag(log_ppi, 1)) %>%
    ungroup()
  for (j in 1:P_LAGS) {
    panel_w[[paste0("log_ppi_lag", j)]] <-
      ave(panel_w$log_ppi, panel_w$nace4d,
          FUN = function(x) c(rep(NA_real_, j), head(x, length(x) - j)))
  }
  for (h in horizons) {
    panel_w[[paste0("log_ppi_lead", h)]] <-
      ave(panel_w$log_ppi, panel_w$nace4d,
          FUN = function(x) {
            n <- length(x); out <- rep(NA_real_, n)
            for (i in seq_len(n)) if ((i + h) <= n) out[i] <- x[i + h]
            out
          })
  }
  panel_w$omega_active <- panel_w[[omega_var]]
  panel_w <- panel_w %>% mutate(omega_cps = omega_active * cps)

  # In-sample mean EUA price (LEVEL, not log) — used to normalise β so that
  # β = 1 corresponds to full Shephard's-lemma pass-through under the new ω
  # convention (ω = emissions/cost; old ω = ω × EUA, so multiplying β by
  # mean(EUA) recovers the old units).
  eua_mean <- mean(exp(panel_w$log_eua), na.rm = TRUE)

  cat(sprintf("Panel: %d rows, %d sectors, %s to %s\n",
              nrow(panel_w), n_distinct(panel_w$nace4d),
              format(min(panel_w$date)), format(max(panel_w$date))))
  cat(sprintf("In-sample mean EUA price: %.2f EUR/tCO2\n", eua_mean))

  # ---- Panel-LP ----
  lag_terms <- paste(paste0("log_ppi_lag", 1:P_LAGS), collapse = " + ")
  run_lp <- function(h) {
    lhs_col <- paste0("log_ppi_lead", h)
    dat <- panel_w %>%
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
    data.frame(h = h,
               gamma = ct["omega_cps", 1],
               se    = ct["omega_cps", 2],
               n     = m$nobs)
  }
  gamma_path <- do.call(rbind, lapply(horizons, run_lp)) %>%
    mutate(t_stat = gamma / se,
           lo95   = gamma - 1.96 * se,
           hi95   = gamma + 1.96 * se)

  # ---- Aggregate EUA-IRF (R_h) ----
  ts <- panel_w %>% distinct(date, log_eua, cps) %>% arrange(date)
  for (j in 1:P_LAGS) {
    ts[[paste0("log_eua_lag", j)]] <- dplyr::lag(ts$log_eua, j)
  }
  ts$log_eua_lag1 <- dplyr::lag(ts$log_eua, 1)
  for (h in horizons) {
    ts[[paste0("log_eua_lead", h)]] <-
      sapply(seq_len(nrow(ts)),
             function(i) if ((i + h) <= nrow(ts)) ts$log_eua[i + h] else NA_real_)
  }
  eua_lag_terms <- paste(paste0("log_eua_lag", 1:P_LAGS), collapse = " + ")
  run_R_lp <- function(h) {
    lhs_col <- paste0("log_eua_lead", h)
    dat <- ts %>%
      transmute(
        y_eua = .data[[lhs_col]] - log_eua_lag1,
        cps,
        log_eua_lag1, log_eua_lag2, log_eua_lag3,
        log_eua_lag4, log_eua_lag5, log_eua_lag6
      ) %>%
      filter(!is.na(y_eua), !is.na(log_eua_lag6))
    frm <- as.formula(sprintf("y_eua ~ cps + %s", eua_lag_terms))
    m <- feols(frm, data = dat, vcov = "hetero")
    ct <- coeftable(m)
    data.frame(h = h, R = ct["cps", 1], R_se = ct["cps", 2], n_R = m$nobs)
  }
  R_path <- do.call(rbind, lapply(horizons, run_R_lp))
  gamma_path <- gamma_path %>% left_join(R_path, by = "h")

  R_bar_in    <- mean(gamma_path$R[gamma_path$h %in% 12:24], na.rm = TRUE)
  R_bar_in_se <- sqrt(mean(gamma_path$R_se[gamma_path$h %in% 12:24]^2,
                           na.rm = TRUE) / sum(gamma_path$h %in% 12:24))
  cat(sprintf("In-sample R̄ (h=12..24): %.4f (s.e. %.4f)  [diagnostic only]\n",
              R_bar_in, R_bar_in_se))
  cat(sprintf("Using R̄_ref = %.4f from 2013m1-2019m12 for β normalization\n",
              R_BAR_REF))

  # ---- γ_h: panel-LP coefficient on (ω × CPShock), the SECTORAL IRF.
  # Units: log-PPI per (tCO2/EUR) per unit CPShock. The cumulative log-PPI
  # response of sector s at horizon h to a unit CPShock is γ_h × ω_s. ----
  gamma_path <- gamma_path %>%
    mutate(gamma_lo68 = gamma - 1.000 * se,
           gamma_hi68 = gamma + 1.000 * se,
           gamma_lo90 = gamma - 1.645 * se,
           gamma_hi90 = gamma + 1.645 * se,
           gamma_lo95 = gamma - 1.96  * se,
           gamma_hi95 = gamma + 1.96  * se,
           # R_h confidence intervals (aggregate first stage)
           R_lo68 = R - 1.000 * R_se,
           R_hi68 = R + 1.000 * R_se,
           R_lo90 = R - 1.645 * R_se,
           R_hi90 = R + 1.645 * R_se,
           R_lo95 = R - 1.96  * R_se,
           R_hi95 = R + 1.96  * R_se)

  # β_h = γ_h / (R̄_ref × E[EUA]) — fixed structural reference, see header.
  # β = 1 corresponds to full Shephard's-lemma pass-through.
  norm    <- R_BAR_REF * eua_mean
  norm_se <- R_BAR_REF_SE * eua_mean
  gamma_path <- gamma_path %>%
    mutate(beta      = gamma / norm,
           beta_se   = sqrt((se / norm)^2 + (gamma * norm_se / norm^2)^2),
           beta_lo68 = beta - 1.000 * beta_se,
           beta_hi68 = beta + 1.000 * beta_se,
           beta_lo90 = beta - 1.645 * beta_se,
           beta_hi90 = beta + 1.645 * beta_se,
           beta_lo95 = beta - 1.96  * beta_se,
           beta_hi95 = beta + 1.96  * beta_se)

  csv_path <- file.path(OUTPUT_TAB,
                        sprintf("phase3_passthrough_iv%s.csv", suffix))
  write.csv(gamma_path, csv_path, row.names = FALSE)

  # ---- Plotting helper ----
  irf_plot <- function(df, point_col, lo90_col, hi90_col, lo68_col, hi68_col,
                       y_label, hline_y = 0) {
    df_ <- df
    df_$y_pt <- df_[[point_col]]
    df_$y_lo90 <- df_[[lo90_col]]; df_$y_hi90 <- df_[[hi90_col]]
    df_$y_lo68 <- df_[[lo68_col]]; df_$y_hi68 <- df_[[hi68_col]]
    y_lo <- min(df_$y_lo90, na.rm = TRUE)
    y_hi <- max(df_$y_hi90, na.rm = TRUE)
    y_range <- y_hi - y_lo
    y_lo_plot <- y_lo - 0.05 * y_range
    y_hi_plot <- y_hi + 0.05 * y_range
    ggplot(df_, aes(x = h, y = y_pt)) +
      geom_hline(yintercept = hline_y, colour = "grey60", linewidth = 0.3) +
      geom_ribbon(aes(ymin = y_lo90, ymax = y_hi90),
                  fill = "steelblue", alpha = 0.18) +
      geom_ribbon(aes(ymin = y_lo68, ymax = y_hi68),
                  fill = "steelblue", alpha = 0.40) +
      geom_line(colour = "black", linewidth = 0.7) +
      scale_x_continuous(breaks = seq(0, H_MAX, by = 6),
                         expand = c(0.005, 0.005)) +
      scale_y_continuous(limits = c(y_lo_plot, y_hi_plot), expand = c(0, 0)) +
      labs(x = "Months", y = y_label) +
      theme_minimal(base_size = 13) +
      theme(panel.grid = element_blank(),
            axis.line = element_line(colour = "black"),
            axis.ticks = element_line(colour = "black"),
            axis.text = element_text(size = 13, colour = "black"),
            axis.title = element_text(size = 14))
  }

  save_irf <- function(p, basename) {
    pdf_path <- file.path(OUTPUT_FIG, paste0(basename, ".pdf"))
    png_path <- file.path(OUTPUT_FIG, paste0(basename, ".png"))
    ggsave(pdf_path, p, width = 6, height = 3.5)
    ggsave(png_path, p, width = 6, height = 3.5, dpi = 300)
  }

  # β_h: pass-through elasticity (existing main figure)
  p_beta <- irf_plot(gamma_path, "beta", "beta_lo90", "beta_hi90",
                     "beta_lo68", "beta_hi68", "Pass-through")
  save_irf(p_beta, sprintf("phase3_passthrough_iv%s", suffix))

  # γ_h: sectoral panel-LP coefficient on (ω × CPShock). Units: log-PPI per
  # (tCO2/EUR) per unit CPShock.
  p_gamma <- irf_plot(gamma_path, "gamma", "gamma_lo90", "gamma_hi90",
                      "gamma_lo68", "gamma_hi68",
                      expression(gamma[h]))
  save_irf(p_gamma, sprintf("phase3_passthrough_iv_gamma%s", suffix))

  # R_h: aggregate first-stage IRF — cumulative log-EUA response per unit
  # CPShock. Reference horizontal line at R̄_ref (post-MSR average over h=12..24).
  p_R <- irf_plot(gamma_path, "R", "R_lo90", "R_hi90", "R_lo68", "R_hi68",
                  expression(R[h]), hline_y = 0) +
         geom_hline(yintercept = R_BAR_REF, colour = "firebrick",
                    linetype = "dashed", linewidth = 0.4)
  save_irf(p_R, sprintf("phase3_passthrough_iv_Rh%s", suffix))

  cat(sprintf("Saved figures: phase3_passthrough_iv%s.{pdf,png}\n", suffix))
  cat(sprintf("               phase3_passthrough_iv_gamma%s.{pdf,png}\n", suffix))
  cat(sprintf("               phase3_passthrough_iv_Rh%s.{pdf,png}\n", suffix))
  cat(sprintf("Saved CSV    : phase3_passthrough_iv%s.csv\n", suffix))

  list(label = win_label,
       start = start_date,
       omega_var = omega_var,
       n_sectors_active = n_distinct(panel_w$nace4d[panel_w$omega_active > 0]),
       eua_mean = eua_mean,
       R_bar_in = R_bar_in,
       R_bar_ref = R_BAR_REF,
       gamma_h0  = gamma_path$gamma[gamma_path$h == 0],
       gamma_h12 = gamma_path$gamma[gamma_path$h == 12],
       gamma_h24 = gamma_path$gamma[gamma_path$h == 24],
       gamma_h36 = gamma_path$gamma[gamma_path$h == 36],
       beta_h0   = gamma_path$beta[gamma_path$h == 0],
       beta_h12  = gamma_path$beta[gamma_path$h == 12],
       beta_h24  = gamma_path$beta[gamma_path$h == 24],
       beta_h36  = gamma_path$beta[gamma_path$h == 36])
}

###############################################################################
# 6. Run the two configurations
#    - Headline: 2008m1-2019m12 with ω = emissions/cost
#    - Appendix robustness: 2013m1-2019m12 with ω = emissions/cost
###############################################################################
RUNS <- list(
  list(start = as.Date("2008-01-01"),
       suffix = "_phase2plus",
       omega_var = "omega_gross",
       label = "2008m1-2019m12, ω=emissions/cost (HEADLINE)"),
  list(start = as.Date("2013-01-01"),
       suffix = "_phase3plus",
       omega_var = "omega_gross",
       label = "2013m1-2019m12, ω=emissions/cost (Phase III only)")
)

results <- lapply(RUNS, function(r) run_window(r$start, r$suffix, r$label, r$omega_var))

###############################################################################
# 7. Summary comparison across configurations
###############################################################################
cat("\n\n========== CONFIGURATION COMPARISON ==========\n")
cat(sprintf("R̄_ref (fixed denominator from 2013m1-2019m12): %.4f\n", R_BAR_REF))
cat("\n--- γ_h (panel-LP coefficient on ω × CPShock) ---\n")
gamma_df <- do.call(rbind, lapply(results, function(r) {
  data.frame(label     = r$label,
             n_sec_pos = r$n_sectors_active,
             gamma_h0  = round(r$gamma_h0,  4),
             gamma_h12 = round(r$gamma_h12, 4),
             gamma_h24 = round(r$gamma_h24, 4),
             gamma_h36 = round(r$gamma_h36, 4))
}))
print(gamma_df, row.names = FALSE)

cat("\n--- β_h = γ_h / (R̄_ref × E[EUA]) ---\n")
beta_df <- do.call(rbind, lapply(results, function(r) {
  data.frame(label     = r$label,
             EUA_mean  = round(r$eua_mean, 2),
             R_bar_in  = round(r$R_bar_in, 4),
             beta_h0   = round(r$beta_h0,  3),
             beta_h12  = round(r$beta_h12, 3),
             beta_h24  = round(r$beta_h24, 3),
             beta_h36  = round(r$beta_h36, 3))
}))
print(beta_df, row.names = FALSE)
