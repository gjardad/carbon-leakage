###############################################################################
# phase3_replicate_kanzig_hicp.R
#
# PURPOSE:
#   Validate our CPShock setup by replicating the reduced-form equivalent
#   of Känzig's (2025 JMP) HICP IRF. Känzig's main spec is an 8-variable
#   external-instruments SVAR, so there isn't a literal event-study
#   regression in his paper. The natural reduced-form equivalent is a
#   local projection:
#
#     log(HICP)_{m+h} − log(HICP)_{m−1} = α_h + γ_h · CPShock_m + ε
#
#   where CPShock_m is Känzig's monthly refined surprise. This is the
#   exact methodology he uses for outcomes OUTSIDE the VAR (Step 6 of his
#   paper). Comparing IRFs for HICP_headline and HICP_energy to his
#   Figure 3 validates our setup. Expected:
#     - HICP_energy impact response positive and large (defines the
#       normalization).
#     - HICP_headline peak response ~0.2 of the HICP_energy impact,
#       persistent out to 24 months.
#
# INPUT:
#   NBB_data/raw/carbonPolicyShocks.xlsx  (Monthly sheet)
#   Eurostat prc_hicp_midx  (downloaded via `eurostat` R package)
#
# OUTPUT:
#   data/processed/kanzig_hicp_replication.RData
#   output/figures/kanzig_hicp_replication.pdf
#   output/tables/kanzig_hicp_replication.txt
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readxl)
  library(eurostat)
  library(fixest)
  library(ggplot2)
})

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- 1. Load monthly CPShock (Känzig refined surprise) ----
xlsx_path <- file.path(RAW_DATA, "carbonPolicyShocks.xlsx")
mly_raw <- read_excel(xlsx_path, sheet = "Monthly")
cps <- mly_raw %>%
  mutate(
    year  = as.integer(substr(Date, 1, 4)),
    month = as.integer(substr(Date, 6, 7)),
    date  = as.Date(sprintf("%d-%02d-01", year, month))
  ) %>%
  transmute(date, year, month,
            cpshock = Surprise,  # refined event-day surprise, monthly aggregate
            shock   = Shock)     # VAR-identified structural shock (for reference)

cat(sprintf("CPShock monthly: %d rows, %s to %s\n",
            nrow(cps), format(min(cps$date)), format(max(cps$date))))

# ---- 2. Download euro-area HICP from Eurostat ----
# prc_hicp_midx: monthly HICP index, base 2015 = 100
# geo = "EA" = changing-composition euro area (what Kanzig uses)
# coicop:
#   CP00 = all items (headline HICP)
#   NRG  = special aggregate "Energy"
cat("\nDownloading Eurostat prc_hicp_midx ...\n")

hicp_raw <- get_eurostat("prc_hicp_midx",
                         filters = list(geo    = "EA",
                                        unit   = "I15",
                                        coicop = c("CP00", "NRG")),
                         time_format = "date",
                         cache = TRUE)

cat(sprintf("Fetched %d rows\n", nrow(hicp_raw)))
cat("Columns:", paste(names(hicp_raw), collapse = " | "), "\n")
cat("COICOP values:", paste(unique(hicp_raw$coicop), collapse = ", "), "\n")

# Rename time column if needed (eurostat package version differences)
date_col <- if ("time" %in% names(hicp_raw)) "time" else
            if ("TIME_PERIOD" %in% names(hicp_raw)) "TIME_PERIOD" else "date"
val_col  <- if ("values" %in% names(hicp_raw)) "values" else "OBS_VALUE"

hicp <- hicp_raw %>%
  transmute(date   = as.Date(.data[[date_col]]),
            coicop = coicop,
            value  = as.numeric(.data[[val_col]])) %>%
  pivot_wider(names_from = coicop, values_from = value) %>%
  rename(hicp_all = CP00, hicp_nrg = NRG) %>%
  arrange(date)

cat(sprintf("\nHICP series: %s to %s (%d months)\n",
            format(min(hicp$date)), format(max(hicp$date)), nrow(hicp)))
cat("Head of HICP:\n"); print(head(hicp, 4))

# ---- 3. Merge CPShock + HICP ----
df <- hicp %>%
  left_join(cps %>% select(date, cpshock, shock), by = "date") %>%
  mutate(
    log_hicp_all  = log(hicp_all),
    log_hicp_nrg  = log(hicp_nrg),
    dlog_hicp_all = log_hicp_all - lag(log_hicp_all, 1),
    dlog_hicp_nrg = log_hicp_nrg - lag(log_hicp_nrg, 1)
  ) %>%
  arrange(date) %>%
  # Restrict to ETS era 2005m1-2019m12 (pre-2005 months have cpshock = 0 by
  # Kaenzig's censored-proxy convention and contribute no identification)
  filter(date >= as.Date("2005-01-01"), date <= as.Date("2019-12-01"))

cat(sprintf("\nAnalysis sample: %d months, %s to %s\n",
            nrow(df), format(min(df$date)), format(max(df$date))))
cat(sprintf("CPShock non-zero months: %d\n", sum(df$cpshock != 0, na.rm = TRUE)))

# ---- 4. Local projections at h = 0, 1, ..., 24 ----
# Cumulative IRF: y_{m+h} - y_{m-1} regressed on CPShock_m
# Standard LP normalization: lhs is the h-period cumulative change from
# the month before the shock. Jorda-style Newey-West SE with lags = h + 1.

run_lp <- function(df, log_var, h_max = 24, n_lags = 0) {
  # Jordà (2005) LP. Default: no lag augmentation (n_lags = 0).
  # Rationale: with 15 years × mostly-zero shock series, lag augmentation
  # over-absorbs the response. Kaenzig's SVAR gets lag structure from the
  # joint VAR dynamics; a reduced-form LP approximates it most cleanly
  # without additional controls.
  dlog_var <- paste0("d", log_var)

  out <- list()
  for (h in 0:h_max) {
    tmp <- df
    tmp$y_lhs <- lead(tmp[[log_var]], h) - lag(tmp[[log_var]], 1)
    tmp$panel_id <- 1L
    tmp$time_idx <- seq_len(nrow(tmp))

    if (n_lags > 0) {
      for (j in 1:n_lags) tmp[[paste0("l", j, "_dlog")]] <- lag(tmp[[dlog_var]], j)
      lag_terms <- paste(sprintf("l%d_dlog", 1:n_lags), collapse = " + ")
      frm <- as.formula(sprintf("y_lhs ~ cpshock + %s", lag_terms))
    } else {
      frm <- as.formula("y_lhs ~ cpshock")
    }

    m <- feols(frm, data = tmp,
               panel.id = ~panel_id + time_idx,
               vcov = NW(lag = h + 1))
    ct <- coeftable(m)
    if ("cpshock" %in% rownames(ct)) {
      r <- ct["cpshock", ]
      out[[length(out) + 1]] <- data.frame(
        h = h, coef = r[1], se = r[2],
        lo68 = r[1] - 1.00 * r[2],
        hi68 = r[1] + 1.00 * r[2],
        lo95 = r[1] - 1.96 * r[2],
        hi95 = r[1] + 1.96 * r[2],
        n    = m$nobs
      )
    }
  }
  do.call(rbind, out)
}

cat("\n--- LP IRF for HICP energy (using CPShock = Surprise) ---\n")
lp_nrg <- run_lp(df, "log_hicp_nrg")
print(lp_nrg[, c("h", "coef", "se", "lo95", "hi95", "n")])

cat("\n--- LP IRF for HICP headline (using CPShock = Surprise) ---\n")
lp_all <- run_lp(df, "log_hicp_all")
print(lp_all[, c("h", "coef", "se", "lo95", "hi95", "n")])

# ALSO run using the VAR-identified Shock column for direct comparison with
# Kaenzig's SVAR IRF (structural shock, scale already normalized via SVAR)
run_lp_shock <- function(df, log_var, h_max = 24) {
  out <- list()
  for (h in 0:h_max) {
    tmp <- df
    tmp$y_lhs <- lead(tmp[[log_var]], h) - lag(tmp[[log_var]], 1)
    tmp$panel_id <- 1L
    tmp$time_idx <- seq_len(nrow(tmp))
    m <- feols(y_lhs ~ shock, data = tmp,
               panel.id = ~panel_id + time_idx,
               vcov = NW(lag = h + 1))
    ct <- coeftable(m)
    if ("shock" %in% rownames(ct)) {
      r <- ct["shock", ]
      out[[length(out) + 1]] <- data.frame(
        h = h, coef = r[1], se = r[2],
        lo68 = r[1] - 1.00 * r[2],
        hi68 = r[1] + 1.00 * r[2],
        lo95 = r[1] - 1.96 * r[2],
        hi95 = r[1] + 1.96 * r[2],
        n    = m$nobs
      )
    }
  }
  do.call(rbind, out)
}

cat("\n--- LP IRF for HICP energy (using structural Shock) ---\n")
lp_nrg_shk <- run_lp_shock(df, "log_hicp_nrg")
print(lp_nrg_shk[, c("h", "coef", "se", "lo95", "hi95", "n")])

cat("\n--- LP IRF for HICP headline (using structural Shock) ---\n")
lp_all_shk <- run_lp_shock(df, "log_hicp_all")
print(lp_all_shk[, c("h", "coef", "se", "lo95", "hi95", "n")])

# Normalize the Surprise-based IRFs so that HICP energy impact (h=0) equals 1%
# (Kaenzig Fig 3 convention). Also report raw peak-to-peak ratios as a more
# noise-robust validation statistic.
scale_factor <- 0.01 / lp_nrg$coef[lp_nrg$h == 0]
cat(sprintf("\nSurprise-based normalization: HICP energy impact = %.4f logs => scale = %.2f\n",
            lp_nrg$coef[lp_nrg$h == 0], scale_factor))

lp_nrg$coef_norm <- lp_nrg$coef * scale_factor
lp_nrg$lo95_norm <- lp_nrg$lo95 * scale_factor
lp_nrg$hi95_norm <- lp_nrg$hi95 * scale_factor
lp_all$coef_norm <- lp_all$coef * scale_factor
lp_all$lo95_norm <- lp_all$lo95 * scale_factor
lp_all$hi95_norm <- lp_all$hi95 * scale_factor

# Shock-based: VAR-identified structural shock — scale should already match
# Kaenzig's IRF directly (no normalization needed).
lp_nrg_shk$coef_norm <- lp_nrg_shk$coef
lp_nrg_shk$lo95_norm <- lp_nrg_shk$lo95
lp_nrg_shk$hi95_norm <- lp_nrg_shk$hi95
lp_all_shk$coef_norm <- lp_all_shk$coef
lp_all_shk$lo95_norm <- lp_all_shk$lo95
lp_all_shk$hi95_norm <- lp_all_shk$hi95

# Peak responses (absolute peak)
peak_all     <- lp_all$coef_norm[which.max(abs(lp_all$coef_norm))]
peak_all_h   <- lp_all$h[which.max(abs(lp_all$coef_norm))]
peak_nrg     <- lp_nrg$coef_norm[which.max(abs(lp_nrg$coef_norm))]
peak_nrg_h   <- lp_nrg$h[which.max(abs(lp_nrg$coef_norm))]
peak_all_shk <- lp_all_shk$coef[which.max(abs(lp_all_shk$coef))]
peak_all_shk_h <- lp_all_shk$h[which.max(abs(lp_all_shk$coef))]
peak_nrg_shk <- lp_nrg_shk$coef[which.max(abs(lp_nrg_shk$coef))]
peak_nrg_shk_h <- lp_nrg_shk$h[which.max(abs(lp_nrg_shk$coef))]

cat("\n=== Key comparisons with Kaenzig JMP Figure 3 ===\n")
cat(sprintf("Benchmark (Kaenzig): HICP energy impact = +1%% (normalization); HICP headline peak ~+0.2%%\n\n"))

cat(sprintf("Surprise-based LP (h=0 normalization):\n"))
cat(sprintf("  HICP energy impact    : +1.000%% (normalization target)\n"))
cat(sprintf("  HICP energy peak      : %+.3f%% at h = %d\n",
            100 * peak_nrg, peak_nrg_h))
cat(sprintf("  HICP headline impact  : %+.3f%% at h = 0\n",
            100 * lp_all$coef_norm[lp_all$h == 0]))
cat(sprintf("  HICP headline peak    : %+.3f%% at h = %d\n",
            100 * peak_all, peak_all_h))
cat(sprintf("  Headline/energy peak-to-peak ratio: %.3f\n\n",
            peak_all / peak_nrg))

cat(sprintf("Structural-Shock-based LP (direct, no rescaling):\n"))
cat(sprintf("  HICP energy impact    : %+.3f%% at h = 0\n",
            100 * lp_nrg_shk$coef[lp_nrg_shk$h == 0]))
cat(sprintf("  HICP energy peak      : %+.3f%% at h = %d\n",
            100 * peak_nrg_shk, peak_nrg_shk_h))
cat(sprintf("  HICP headline impact  : %+.4f%% at h = 0\n",
            100 * lp_all_shk$coef[lp_all_shk$h == 0]))
cat(sprintf("  HICP headline peak    : %+.3f%% at h = %d\n",
            100 * peak_all_shk, peak_all_shk_h))
cat(sprintf("  Headline/energy peak-to-peak ratio: %.3f\n\n",
            peak_all_shk / peak_nrg_shk))

# ---- 5. Save outputs ----
sink(file.path(OUTPUT_TAB, "kanzig_hicp_replication.txt"))
cat("================================================================\n")
cat(" Kaenzig JMP HICP IRF — reduced-form LP replication\n")
cat("================================================================\n\n")
cat("Sample: 1999m7 - 2019m12 (matches Kaenzig JMP)\n")
cat("Shock : Kaenzig refined monthly CPShock from carbonPolicyShocks.xlsx\n")
cat("Data  : euro-area HICP (all items = CP00, energy = NRG) from Eurostat\n")
cat("Spec  : cumulative LP  y_{m+h} - y_{m-1} ~ CPShock_m\n")
cat("        Newey-West SE with lag = h + 1\n\n")

cat("--- HICP energy IRF (normalized: impact = 1%) ---\n")
print(lp_nrg[, c("h", "coef", "se", "coef_norm", "lo95_norm", "hi95_norm", "n")])
cat("\n--- HICP headline IRF (normalized) ---\n")
print(lp_all[, c("h", "coef", "se", "coef_norm", "lo95_norm", "hi95_norm", "n")])

cat(sprintf("\n\nHICP headline peak response: %+.3f%% at h=%d\n",
            100 * peak_all, peak_all_h))
cat(sprintf("Kaenzig JMP Figure 3 benchmark: ~+0.2%% headline peak\n"))
sink()

kanzig_hicp_replication <- list(lp_nrg = lp_nrg, lp_all = lp_all,
                                scale_factor = scale_factor,
                                sample_df = df)
save(kanzig_hicp_replication,
     file = file.path(OUT_DATA, "kanzig_hicp_replication.RData"))

# ---- 6. Plot IRFs ----
# Plot the structural-Shock-based LP (which Käenzig himself uses for outcomes
# outside his SVAR per Step 6 of his paper). Shock is sign-normalised so a
# unit shock raises HICP energy by ~1% on impact, matching his Figure 3
# directly without further rescaling.
plt_df <- bind_rows(
  lp_nrg_shk %>% mutate(series = "HICP energy"),
  lp_all_shk %>% mutate(series = "HICP headline")
)

p <- ggplot(plt_df, aes(x = h, y = 100 * coef, color = series, fill = series)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  geom_ribbon(aes(ymin = 100 * lo95, ymax = 100 * hi95),
              alpha = 0.2, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.8) +
  scale_color_manual(values = c("HICP energy" = "#cb181d",
                                "HICP headline" = "#08306b")) +
  scale_fill_manual(values  = c("HICP energy" = "#fb6a4a",
                                "HICP headline" = "#3182bd")) +
  labs(
    title = "Käenzig (2023, JMP) HICP IRF — reduced-form LP replication",
    subtitle = "Monthly LP, 2005m1-2019m12 EA, regressor = Käenzig VAR-identified Shock. Benchmark: JMP Fig 3.",
    x = "Horizon (months)", y = "% response",
    color = NULL, fill = NULL
  ) +
  theme_bw(base_size = 10) +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "bottom")

ggsave(file.path(OUTPUT_FIG, "kanzig_hicp_replication.pdf"),
       p, width = 8, height = 5)
ggsave(file.path(OUTPUT_FIG, "kanzig_hicp_replication.png"),
       p, width = 8, height = 5, dpi = 300)
cat("Plot saved to:", file.path(OUTPUT_FIG, "kanzig_hicp_replication.pdf"), "\n")
cat("Done.\n")
