###############################################################################
# phase4_aggregate_ppi_lp_lagaug.R
#
# PURPOSE:
#   Re-run the aggregate Belgian-PPI local projection (no sector / no ω
#   interaction) but with Plagborg-Moller-Wolf lag-augmentation: 6 lags of
#   aggregate log-PPI on the RHS. Asks whether the apparent negative-tail
#   issue in phase3_passthrough_aggregate_lp.R disappears once LHS
#   persistence is controlled for.
#
# SPEC at horizon h:
#   log(PPI_agg)_{m+h} - log(PPI_agg)_{m-1}
#     = α_h + γ_h · CPShock_m
#       + Σ_{j=1..6} φ_{h,j} · log(PPI_agg)_{m-j}
#       + ε_{m, h}
#
#   Aggregate PPI: equally-weighted geometric mean of NACE 4-digit PPI.
#   Estimator: time-series LP, Newey-West SE with lag = h + 1.
#   Three sample windows: 2005m1-2019m12, 2008m1-2019m12, 2013m1-2019m12.
#   Horizons h = 0, 1, ..., 36.
#
# OUTPUT:
#   ${OUTPUT_TAB}/phase4_aggregate_ppi_lp_lagaug{,_phase2plus,_phase3plus}.csv
#   ${OUTPUT_FIG}/phase4_aggregate_ppi_lp_lagaug{,_phase2plus,_phase3plus}.{pdf,png}
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readxl)
  library(lubridate); library(sandwich); library(lmtest); library(ggplot2)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

H_MAX     <- 24L
HORIZONS  <- 0:H_MAX
P_LAGS    <- 6L

# ---- 1. Aggregate PPI: equally-weighted geometric mean of NACE 4d log-PPI ----
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))

agg <- deflator_monthly %>%
  filter(!is.na(ppi), ppi > 0) %>%
  mutate(log_ppi = log(ppi)) %>%
  group_by(date) %>%
  summarise(log_ppi_agg = mean(log_ppi, na.rm = TRUE), .groups = "drop") %>%
  arrange(date)
cat(sprintf("Aggregate PPI: %d months, %s to %s\n",
            nrow(agg), format(min(agg$date)), format(max(agg$date))))

# ---- 2. Känzig CPShock monthly ----
xlsx_path <- file.path(RAW_DATA, "carbonPolicyShocks.xlsx")
cps_raw <- read_excel(xlsx_path, sheet = "Monthly")
cps <- cps_raw %>%
  mutate(year  = as.integer(substr(Date, 1, 4)),
         month = as.integer(substr(Date, 6, 7)),
         date  = as.Date(sprintf("%d-%02d-01", year, month))) %>%
  transmute(date, cps_shock = Shock)

ts_full <- agg %>% inner_join(cps, by = "date") %>% arrange(date)
for (j in 1:P_LAGS) {
  ts_full[[paste0("log_ppi_lag", j)]] <- dplyr::lag(ts_full$log_ppi_agg, j)
}
ts_full$log_ppi_lag1 <- dplyr::lag(ts_full$log_ppi_agg, 1)
for (h in HORIZONS) {
  ts_full[[paste0("log_ppi_lead", h)]] <-
    sapply(seq_len(nrow(ts_full)),
           function(i) if ((i + h) <= nrow(ts_full))
             ts_full$log_ppi_agg[i + h] else NA_real_)
}
lag_terms <- paste(paste0("log_ppi_lag", 1:P_LAGS), collapse = " + ")

run_window <- function(start_date, end_date, label, slug) {
  cat(sprintf("\n========== %s ==========\n", label))

  run_lp_h <- function(h) {
    lhs_col <- paste0("log_ppi_lead", h)
    dat <- ts_full %>%
      transmute(y = .data[[lhs_col]] - log_ppi_lag1,
                cps_shock,
                date,
                log_ppi_lag1, log_ppi_lag2, log_ppi_lag3,
                log_ppi_lag4, log_ppi_lag5, log_ppi_lag6) %>%
      filter(date >= start_date, date <= end_date,
             !is.na(y), !is.na(cps_shock), !is.na(log_ppi_lag6))
    if (nrow(dat) < P_LAGS + 5) return(NULL)
    frm <- as.formula(sprintf("y ~ cps_shock + %s", lag_terms))
    m <- lm(frm, data = dat)
    nw <- NeweyWest(m, lag = h + 1, prewhite = FALSE, adjust = TRUE)
    ct <- coeftest(m, vcov. = nw)
    data.frame(h     = h,
               coef  = ct["cps_shock", 1],
               se    = ct["cps_shock", 2],
               n     = nobs(m))
  }

  res <- bind_rows(lapply(HORIZONS, run_lp_h)) %>%
    mutate(t_stat = coef / se,
           lo68   = coef - 1.000 * se,
           hi68   = coef + 1.000 * se,
           lo90   = coef - 1.645 * se,
           hi90   = coef + 1.645 * se,
           lo95   = coef - 1.96  * se,
           hi95   = coef + 1.96  * se)

  cat("Coefficients (rounded):\n")
  print(res %>% mutate(across(c(coef, se, t_stat, lo68, hi68, lo90, hi90, lo95, hi95),
                              ~ round(.x, 5))) %>%
        select(h, coef, se, t_stat, lo90, hi90, lo95, hi95, n))

  csv_path <- file.path(OUTPUT_TAB,
                        sprintf("phase4_aggregate_ppi_lp_lagaug%s.csv", slug))
  write.csv(res, csv_path, row.names = FALSE)
  cat(sprintf("Saved CSV: %s\n", csv_path))

  p <- ggplot(res, aes(x = h, y = coef)) +
    geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
    geom_ribbon(aes(ymin = lo90, ymax = hi90), fill = "grey80", alpha = 0.6) +
    geom_ribbon(aes(ymin = lo68, ymax = hi68), fill = "grey55", alpha = 0.6) +
    geom_line(colour = "black", linewidth = 0.7) +
    scale_x_continuous(breaks = seq(0, H_MAX, by = 3)) +
    labs(x = "Horizon h (months)",
         y = expression(hat(gamma)[h]),
         title = NULL, subtitle = NULL) +
    theme_minimal(base_size = 11) +
    theme(panel.grid = element_blank(),
          axis.line = element_line(colour = "black"),
          axis.ticks = element_line(colour = "black"))
  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_aggregate_ppi_lp_lagaug%s.pdf", slug)),
         p, width = 8, height = 4.2)
  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_aggregate_ppi_lp_lagaug%s.png", slug)),
         p, width = 8, height = 4.2, dpi = 200)
  cat(sprintf("Saved figure: phase4_aggregate_ppi_lp_lagaug%s.{pdf,png}\n", slug))

  invisible(res)
}

# ---- 3. Run three windows ----
res_full <- run_window(as.Date("2005-01-01"), as.Date("2019-12-01"),
                       "2005m1-2019m12 (full)", "")
res_p2   <- run_window(as.Date("2008-01-01"), as.Date("2019-12-01"),
                       "2008m1-2019m12 (Phase II onward)", "_phase2plus")
res_p3   <- run_window(as.Date("2013-01-01"), as.Date("2019-12-01"),
                       "2013m1-2019m12 (Phase III only)", "_phase3plus")

cat("\nDone.\n")
