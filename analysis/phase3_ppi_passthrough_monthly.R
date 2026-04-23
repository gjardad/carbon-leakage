###############################################################################
# phase3_ppi_passthrough_monthly.R
#
# PURPOSE:
#   Panel-LP analog of Kaenzig's (2025 JMP) HICP spec, adapted to Belgian
#   NACE4d monthly PPI with sector × base-intensity interaction.
#
#   Kaenzig runs time-series LPs on aggregate euro-area HICP. We run a
#   panel-LP on Belgian sector-level PPI interacted with a pre-period
#   shortage-intensity measure, so that sector FE and year-month FE absorb
#   all level/time confounders; identification comes from within-month
#   cross-sector variation.
#
#   Spec:
#     log(PPI_{s,m+h}) - log(PPI_{s,m-1}) =
#         gamma_h * (CPShock_m * intensity_base_s) + alpha_s + delta_m + eps
#
#   Running with BOTH Shock (VAR-identified) and Surprise (raw event-day)
#   RHS variables, in parallel with the annual S7-shk / S7 specs.
#
#   Sample: 2005-01 to 2019-12 (CPShock coverage).
#   Horizons: h = 0, 1, 3, 6, 12, 24 months.
#
# INPUT:
#   NBB_data/processed/deflator_nace4d_2005base_monthly.RData
#   NBB_data/raw/carbonPolicyShocks.xlsx (Monthly sheet)
#   data/processed/phase3_sector_exposure.RData (for intensity_base via 2013-16 mean)
#
# OUTPUT:
#   output/tables/phase3_ppi_passthrough_monthly.txt
#   output/figures/phase3_ppi_lp_monthly.pdf
#   data/processed/phase3_ppi_passthrough_monthly.RData (coefficient store)
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readxl)
  library(lubridate)
  library(fixest)
  library(ggplot2)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

###############################################################################
# 1. Load monthly PPI
###############################################################################
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))
cat(sprintf("Monthly PPI: %d obs, %d NACE4d, %s to %s\n",
            nrow(deflator_monthly),
            n_distinct(deflator_monthly$nace4d),
            format(min(deflator_monthly$date)),
            format(max(deflator_monthly$date))))

###############################################################################
# 2. Load monthly CPShock (Kaenzig 2005-2019 + our Phase IV rebuild 2020-2024)
###############################################################################
# Kaenzig monthly series (2005-2019): Surprise (refined event-day, electricity-
# scaled) and Shock (VAR-identified structural).
xlsx_path <- file.path(RAW_DATA, "carbonPolicyShocks.xlsx")
cps_raw <- read_excel(xlsx_path, sheet = "Monthly")
cps_kanzig <- cps_raw %>%
  mutate(year  = as.integer(substr(Date, 1, 4)),
         month = as.integer(substr(Date, 6, 7)),
         date  = as.Date(sprintf("%d-%02d-01", year, month))) %>%
  transmute(date, year, month,
            cpshock_surprise = Surprise,
            cpshock_shock    = Shock)
cat(sprintf("Kaenzig CPShock monthly: %d obs, %s to %s\n",
            nrow(cps_kanzig),
            format(min(cps_kanzig$date)), format(max(cps_kanzig$date))))

# Phase IV monthly series (2020-2024): aggregate daily log-return surprises
# from phase3_build_cpshock_phase4.R to monthly.
load(file.path(OUT_DATA, "cpshock_phase4_annual.RData"))
# cpshock_phase4_events has one row per event with cps_logret.
cps_phase4_monthly <- cpshock_phase4_events %>%
  filter(!is.na(cps_logret)) %>%
  mutate(year  = year(date_d),
         month = month(date_d),
         date  = as.Date(sprintf("%d-%02d-01", year, month))) %>%
  group_by(date, year, month) %>%
  summarise(cpshock_p4 = sum(cps_logret), .groups = "drop")

# Fill in months in 2020-2024 with no events = 0 (censored proxy, like Kaenzig)
all_months_p4 <- tibble(date = seq(as.Date("2020-01-01"),
                                   as.Date("2024-12-01"), by = "month"))
cps_phase4_monthly <- all_months_p4 %>%
  left_join(cps_phase4_monthly, by = "date") %>%
  mutate(year       = year(date),
         month      = month(date),
         cpshock_p4 = coalesce(cpshock_p4, 0))
cat(sprintf("Phase IV CPShock monthly: %d months, %s to %s; %d nonzero\n",
            nrow(cps_phase4_monthly),
            format(min(cps_phase4_monthly$date)),
            format(max(cps_phase4_monthly$date)),
            sum(cps_phase4_monthly$cpshock_p4 != 0)))

# Use the Kaenzig monthly Surprise for 2005-2019 in the Phase 3 panel.
cps <- cps_kanzig  # retain name for backward compatibility within the script

###############################################################################
# 3. Compute base-period intensity per sector (2013–2016 mean of exposure_alt)
###############################################################################
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))

intensity_base_df <- sector_exposure %>%
  filter(year %in% 2013:2016) %>%
  group_by(nace4d) %>%
  summarise(intensity_base = mean(exposure_alt_total, na.rm = TRUE),
            .groups = "drop")

cat(sprintf("Sectors with intensity_base > 0: %d\n",
            sum(intensity_base_df$intensity_base > 0, na.rm = TRUE)))

# Identify ever-ETS sectors for the ETS-only sample
ets_sectors <- sector_exposure %>%
  filter(!is.na(n_ets_firms), n_ets_firms > 0) %>%
  distinct(nace4d) %>%
  pull(nace4d)
cat(sprintf("Ever-ETS sectors: %d\n", length(ets_sectors)))

###############################################################################
# 4. Build monthly panel: PPI + CPShock + intensity_base
###############################################################################
panel_m <- deflator_monthly %>%
  filter(date >= as.Date("2005-01-01"),
         date <= as.Date("2019-12-01")) %>%
  left_join(cps %>% select(date, cpshock_surprise, cpshock_shock),
            by = "date") %>%
  left_join(intensity_base_df, by = "nace4d") %>%
  mutate(
    intensity_base      = coalesce(intensity_base, 0),
    log_ppi             = log(ppi),
    cpshock_x_int       = cpshock_surprise * intensity_base,
    cpshock_shk_x_int   = cpshock_shock    * intensity_base,
    year_month          = format(date, "%Y-%m")
  )

cat(sprintf("\nMonthly panel: %d obs, %d NACE4d, %s to %s\n",
            nrow(panel_m), n_distinct(panel_m$nace4d),
            format(min(panel_m$date)), format(max(panel_m$date))))
cat(sprintf("Sectors with intensity_base > 0 in panel: %d\n",
            sum(panel_m %>% distinct(nace4d, intensity_base) %>%
                  pull(intensity_base) > 0)))

###############################################################################
# 5. LP at horizons h = 0, 1, 3, 6, 12, 24 months
###############################################################################

horizons <- c(0, 1, 3, 6, 12, 24)

# Build leads and the cumulative LHS: log_ppi_{m+h} - log_ppi_{m-1}
panel_m <- panel_m %>% arrange(nace4d, date)

for (h in horizons) {
  col_name <- paste0("dlog_ppi_h", h)
  panel_m[[col_name]] <- ave(panel_m$log_ppi, panel_m$nace4d,
                             FUN = function(x) {
                               # lead by h, lag by 1
                               n <- length(x)
                               out <- rep(NA_real_, n)
                               for (i in seq_len(n)) {
                                 if ((i + h) <= n && (i - 1) >= 1) {
                                   out[i] <- x[i + h] - x[i - 1]
                                 }
                               }
                               out
                             })
}

cat("\nLHS variable counts (non-NA):\n")
for (h in horizons) {
  col <- paste0("dlog_ppi_h", h)
  cat(sprintf("  h = %2d: %d\n", h, sum(!is.na(panel_m[[col]]))))
}

# Run LP for a given RHS variable and sample restriction
run_lp_monthly <- function(rhs_var, sample_label, sample_filter) {
  results <- data.frame()
  for (h in horizons) {
    lhs_col <- paste0("dlog_ppi_h", h)
    dat <- panel_m %>% filter(!is.na(.data[[lhs_col]]))
    if (sample_filter == "ets") dat <- dat %>% filter(nace4d %in% ets_sectors)
    frm <- as.formula(sprintf("%s ~ %s | nace4d + year_month",
                              lhs_col, rhs_var))
    m <- feols(frm, data = dat, cluster = ~nace4d)
    ct <- coeftable(m)
    if (rhs_var %in% rownames(ct)) {
      r <- ct[rhs_var, ]
      results <- rbind(results, data.frame(
        rhs     = rhs_var,
        sample  = sample_label,
        h       = h,
        coef    = r[1], se = r[2],
        lo95    = r[1] - 1.96 * r[2],
        hi95    = r[1] + 1.96 * r[2],
        n       = m$nobs
      ))
    }
  }
  results
}

cat("\n================================================================\n")
cat(" Panel-LP specs (monthly): PPI response to CPShock × intensity\n")
cat("================================================================\n")

# Shock-based (primary, following Kaenzig Appendix C.6)
lp_all_shk <- run_lp_monthly("cpshock_shk_x_int", "all",       "all")
lp_ets_shk <- run_lp_monthly("cpshock_shk_x_int", "ETS-only",  "ets")

# Surprise-based (robustness, following Kaenzig Appendix C.5)
lp_all_srp <- run_lp_monthly("cpshock_x_int",     "all",       "all")
lp_ets_srp <- run_lp_monthly("cpshock_x_int",     "ETS-only",  "ets")

cat("\n--- Shock-based, all sectors ---\n");      print(lp_all_shk)
cat("\n--- Shock-based, ETS-only ---\n");         print(lp_ets_shk)
cat("\n--- Surprise-based, all sectors ---\n");   print(lp_all_srp)
cat("\n--- Surprise-based, ETS-only ---\n");      print(lp_ets_srp)

lp_results <- bind_rows(
  lp_all_shk %>% mutate(rhs_label = "Shock × intensity"),
  lp_ets_shk %>% mutate(rhs_label = "Shock × intensity"),
  lp_all_srp %>% mutate(rhs_label = "Surprise × intensity"),
  lp_ets_srp %>% mutate(rhs_label = "Surprise × intensity")
)

###############################################################################
# 5b. Phase IV extension: S12b on 2020-2024 monthly panel
#     Uses our rebuilt log-return surprise (no Shock column available).
###############################################################################

cat("\n================================================================\n")
cat(" S12b — Phase IV monthly panel-LP  (2020m1-2024m12)\n")
cat("================================================================\n")

panel_p4 <- deflator_monthly %>%
  filter(date >= as.Date("2020-01-01"),
         date <= as.Date("2024-12-01")) %>%
  left_join(cps_phase4_monthly %>% select(date, cpshock_p4), by = "date") %>%
  left_join(intensity_base_df, by = "nace4d") %>%
  mutate(intensity_base = coalesce(intensity_base, 0),
         log_ppi        = log(ppi),
         cpshock_p4_x_int = cpshock_p4 * intensity_base,
         year_month     = format(date, "%Y-%m"))

cat(sprintf("Phase IV monthly panel: %d obs, %d sectors, %s to %s\n",
            nrow(panel_p4), n_distinct(panel_p4$nace4d),
            format(min(panel_p4$date)), format(max(panel_p4$date))))

# LHS: cumulative change from month m-1 to m+h
panel_p4 <- panel_p4 %>% arrange(nace4d, date)
for (h in horizons) {
  col_name <- paste0("dlog_ppi_h", h)
  panel_p4[[col_name]] <- ave(panel_p4$log_ppi, panel_p4$nace4d,
                              FUN = function(x) {
                                n <- length(x)
                                out <- rep(NA_real_, n)
                                for (i in seq_len(n)) {
                                  if ((i + h) <= n && (i - 1) >= 1) {
                                    out[i] <- x[i + h] - x[i - 1]
                                  }
                                }
                                out
                              })
}

run_lp_p4 <- function(sample_label, sample_filter) {
  results <- data.frame()
  for (h in horizons) {
    lhs_col <- paste0("dlog_ppi_h", h)
    dat <- panel_p4 %>% filter(!is.na(.data[[lhs_col]]))
    if (sample_filter == "ets") dat <- dat %>% filter(nace4d %in% ets_sectors)
    frm <- as.formula(sprintf("%s ~ cpshock_p4_x_int | nace4d + year_month",
                              lhs_col))
    m <- feols(frm, data = dat, cluster = ~nace4d)
    ct <- coeftable(m)
    if ("cpshock_p4_x_int" %in% rownames(ct)) {
      r <- ct["cpshock_p4_x_int", ]
      results <- rbind(results, data.frame(
        rhs     = "cpshock_p4_x_int",
        sample  = sample_label,
        h       = h,
        coef    = r[1], se = r[2],
        lo95    = r[1] - 1.96 * r[2],
        hi95    = r[1] + 1.96 * r[2],
        n       = m$nobs
      ))
    }
  }
  results
}

lp_p4_all <- run_lp_p4("all",      "all")
lp_p4_ets <- run_lp_p4("ETS-only", "ets")

cat("\n--- S12b Phase IV, all sectors (log-return CPShock × intensity) ---\n")
print(lp_p4_all)
cat("\n--- S12b Phase IV, ETS-only ---\n")
print(lp_p4_ets)

lp_results_p4 <- bind_rows(
  lp_p4_all %>% mutate(rhs_label = "Phase IV log-return × intensity"),
  lp_p4_ets %>% mutate(rhs_label = "Phase IV log-return × intensity")
)

###############################################################################
# 6. Save and plot
###############################################################################

sink(file.path(OUTPUT_TAB, "phase3_ppi_passthrough_monthly.txt"))
cat("================================================================\n")
cat(" Monthly panel-LP: Belgian NACE4d PPI on CPShock × intensity\n")
cat("================================================================\n\n")
cat("Sample: 2005-01 to 2019-12 (Kaenzig CPShock coverage)\n")
cat("Spec  : log(PPI_{s,m+h}) - log(PPI_{s,m-1}) = gamma_h * (CPShock_m * intensity_base_s) + alpha_s + delta_m + eps\n")
cat("FE    : nace4d + year_month  |  SE clustered on nace4d\n\n")
cat("intensity_base_s = mean exposure_alt over 2013-16 (pre-MSR, post-auctioning)\n\n")

cat("\n--- All sectors, Shock RHS ---\n");      print(lp_all_shk)
cat("\n--- ETS-only, Shock RHS ---\n");         print(lp_ets_shk)
cat("\n--- All sectors, Surprise RHS ---\n");   print(lp_all_srp)
cat("\n--- ETS-only, Surprise RHS ---\n");      print(lp_ets_srp)

cat("\n\nAnnual-spec comparison (from phase3_ppi_passthrough.R):\n")
cat("  S7a-shk (annual, h=0, all):      +1.28 (SE 1.72)\n")
cat("  S7d-shk cumulative (annual):    +9.22 (SE 3.68), p=0.012\n")
cat("  S10-shk LP h=1yr (all):         +5.09 (SE 1.71), t=2.98\n")
cat("  S10-shk LP h=2yr (all):         +4.77 (SE 1.19), t=4.00\n")

cat("\n\n=== S12b Phase IV extension, 2020m1-2024m12 ===\n")
cat("RHS = our log-return surprise (from 45 BKR events), NOT Kaenzig's series\n")
cat("Different scaling from S12 2005-2019 (electricity-scaled Surprise or Shock),\n")
cat("so coefficient magnitudes are NOT directly comparable across periods.\n\n")
cat("--- All sectors ---\n"); print(lp_p4_all)
cat("\n--- ETS only ---\n"); print(lp_p4_ets)
sink()

save(lp_results, lp_results_p4,
     file = file.path(OUT_DATA, "phase3_ppi_passthrough_monthly.RData"))
cat("\nSaved results to:",
    file.path(OUT_DATA, "phase3_ppi_passthrough_monthly.RData"), "\n")

# ---- IRF plot ----
plt_df <- lp_results
plt_df$sample_rhs <- paste(plt_df$sample, plt_df$rhs_label, sep = ", ")

p <- ggplot(plt_df, aes(x = h, y = coef, color = sample_rhs, fill = sample_rhs,
                        group = sample_rhs)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  geom_ribbon(aes(ymin = lo95, ymax = hi95), alpha = 0.15, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.2) +
  facet_wrap(~ rhs_label, scales = "free_y") +
  labs(title = "Monthly panel-LP: log(PPI) response to CPShock × base intensity",
       subtitle = "2005m1-2019m12, NACE4d + year-month FE, clustered-on-sector SE",
       x = "Horizon (months since shock)", y = expression(gamma[h]),
       color = NULL, fill = NULL) +
  theme_bw(base_size = 10) +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold"))

ggsave(file.path(OUTPUT_FIG, "phase3_ppi_lp_monthly.pdf"),
       p, width = 10, height = 5.5)
cat("Plot saved to:", file.path(OUTPUT_FIG, "phase3_ppi_lp_monthly.pdf"), "\n")

# ---- Phase IV IRF plot ----
plt_p4 <- lp_results_p4
plt_p4$sample_rhs <- paste(plt_p4$sample, plt_p4$rhs_label, sep = ", ")
p_p4 <- ggplot(plt_p4, aes(x = h, y = coef, color = sample, fill = sample)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  geom_ribbon(aes(ymin = lo95, ymax = hi95), alpha = 0.15, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.2) +
  scale_color_manual(values = c("all" = "#08306b", "ETS-only" = "#cb181d")) +
  scale_fill_manual(values  = c("all" = "#3182bd", "ETS-only" = "#fb6a4a")) +
  labs(title = "S12b Phase IV panel-LP: log(PPI) response to monthly log-return CPShock × intensity",
       subtitle = "2020m1-2024m12, NACE4d + year-month FE, clustered-on-sector SE. RHS is our log-return rebuild (not Kaenzig's series).",
       x = "Horizon (months since shock)", y = expression(gamma[h]),
       color = NULL, fill = NULL) +
  theme_bw(base_size = 10) +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold"))
ggsave(file.path(OUTPUT_FIG, "phase3_ppi_lp_monthly_phase4.pdf"),
       p_p4, width = 8, height = 5)
cat("Phase IV plot saved to:",
    file.path(OUTPUT_FIG, "phase3_ppi_lp_monthly_phase4.pdf"), "\n")

cat("\nDone.\n")
