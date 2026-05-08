###############################################################################
# phase3_passthrough_aggregate_lp.R
#
# PURPOSE:
#   Run the Käenzig (2023) reduced-form local projection on aggregate
#   Belgian PPI (substituting PPI for HICP). NO ω interaction, NO sectoral
#   structure — this is the direct PPI analog of Käenzig's HICP IRF and the
#   right benchmark for "is there ANY pass-through" before adding cross-
#   sectional heterogeneity.
#
# SPEC (matches phase3_replicate_kanzig_hicp.R, with PPI substituted for HICP):
#
#   log(PPI_agg)_{m+h} - log(PPI_agg)_{m-1} = α_h + γ_h · CPShock_m + ε_{m,h}
#
#   Aggregate PPI: equally-weighted geometric mean of NACE 4-digit PPI.
#   (Equal weights match Käenzig's "average sector" interpretation; a
#   sales-weighted aggregate would be closer to GDP-deflator analog.)
#
#   Estimator: time-series LP. Newey-West SE with lag = h + 1.
#
# WINDOWS (three sample windows for sensitivity):
#   1. 2005m1-2019m12 — full Käenzig window (matches HICP replication).
#   2. 2008m1-2019m12 — excludes Phase I.
#   3. 2013m1-2019m12 — Phase III only.
#
# INPUT:
#   ${PROC_DATA}/deflator_nace4d_2005base_monthly.RData
#   ${RAW_DATA}/carbonPolicyShocks.xlsx  (Monthly sheet)
#
# OUTPUT:
#   ${OUTPUT_FIG}/phase3_aggregate_ppi_lp{,_phase2plus,_phase3plus}.{pdf,png}
#   ${OUTPUT_TAB}/phase3_aggregate_ppi_lp{,_phase2plus,_phase3plus}.csv
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

H_MAX <- 36L
horizons <- 0:H_MAX

###############################################################################
# 1. Load + aggregate PPI
###############################################################################
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))

# Equally-weighted aggregate: mean of log(PPI) across NACE 4d sectors per month.
agg <- deflator_monthly %>%
  filter(!is.na(ppi), ppi > 0) %>%
  mutate(log_ppi = log(ppi)) %>%
  group_by(date) %>%
  summarise(log_ppi_agg = mean(log_ppi),
            n_sectors   = dplyr::n(), .groups = "drop") %>%
  arrange(date)

cat(sprintf("Aggregate PPI: %d months, %s to %s, sectors per month: %d-%d\n",
            nrow(agg),
            format(min(agg$date)), format(max(agg$date)),
            min(agg$n_sectors), max(agg$n_sectors)))

###############################################################################
# 2. Käenzig CPShock series (Shock column)
###############################################################################
cps <- read_excel(file.path(RAW_DATA, "carbonPolicyShocks.xlsx"),
                  sheet = "Monthly") %>%
  mutate(year  = as.integer(substr(Date, 1, 4)),
         month = as.integer(substr(Date, 6, 7)),
         date  = as.Date(sprintf("%d-%02d-01", year, month))) %>%
  transmute(date, cps = Shock)

###############################################################################
# 3. Merge
###############################################################################
df <- agg %>%
  left_join(cps, by = "date") %>%
  mutate(cps = coalesce(cps, 0)) %>%
  arrange(date)

###############################################################################
# 4. LP runner: y_{m+h} - y_{m-1} ~ CPShock_m, NW SE with lag = h+1.
#    Returns IRF coefficients with 68/90/95 bands.
###############################################################################
run_lp <- function(df_in, h_max = H_MAX) {
  out <- list()
  df_in <- df_in %>% arrange(date)
  df_in$panel_id <- 1L
  df_in$time_idx <- seq_len(nrow(df_in))
  for (h in 0:h_max) {
    tmp <- df_in
    tmp$y_lhs <- dplyr::lead(tmp$log_ppi_agg, h) - dplyr::lag(tmp$log_ppi_agg, 1)
    m <- feols(y_lhs ~ cps, data = tmp,
               panel.id = ~panel_id + time_idx,
               vcov = NW(lag = h + 1))
    ct <- coeftable(m)
    if ("cps" %in% rownames(ct)) {
      r <- ct["cps", ]
      out[[length(out) + 1]] <- data.frame(
        h     = h,
        coef  = r[1],
        se    = r[2],
        lo68  = r[1] - 1.000 * r[2],
        hi68  = r[1] + 1.000 * r[2],
        lo90  = r[1] - 1.645 * r[2],
        hi90  = r[1] + 1.645 * r[2],
        lo95  = r[1] - 1.96  * r[2],
        hi95  = r[1] + 1.96  * r[2],
        n     = m$nobs
      )
    }
  }
  do.call(rbind, out)
}

###############################################################################
# 5. Plot helper
###############################################################################
plot_irf <- function(d, title_suffix) {
  y_lo <- min(d$lo90, na.rm = TRUE); y_hi <- max(d$hi90, na.rm = TRUE)
  y_range <- y_hi - y_lo
  ggplot(d, aes(x = h, y = 100 * coef)) +
    geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
    geom_ribbon(aes(ymin = 100 * lo90, ymax = 100 * hi90),
                fill = "steelblue", alpha = 0.18) +
    geom_ribbon(aes(ymin = 100 * lo68, ymax = 100 * hi68),
                fill = "steelblue", alpha = 0.40) +
    geom_line(colour = "black", linewidth = 0.7) +
    scale_x_continuous(breaks = seq(0, H_MAX, by = 6), expand = c(0.005, 0.005)) +
    scale_y_continuous(limits = c(100 * (y_lo - 0.05 * y_range),
                                  100 * (y_hi + 0.05 * y_range)),
                       expand = c(0, 0)) +
    labs(x = "Months", y = "% PPI response per unit CPShock",
         subtitle = title_suffix) +
    theme_minimal(base_size = 12) +
    theme(panel.grid = element_blank(),
          axis.line = element_line(colour = "black"),
          axis.ticks = element_line(colour = "black"))
}

###############################################################################
# 6. Run on each window
###############################################################################
WINDOWS <- list(
  list(start = as.Date("2005-01-01"), end = as.Date("2019-12-01"),
       suffix = "",            label = "2005m1-2019m12 (Phase I-III)"),
  list(start = as.Date("2008-01-01"), end = as.Date("2019-12-01"),
       suffix = "_phase2plus", label = "2008m1-2019m12 (excl. Phase I)"),
  list(start = as.Date("2013-01-01"), end = as.Date("2019-12-01"),
       suffix = "_phase3plus", label = "2013m1-2019m12 (Phase III only)")
)

for (w in WINDOWS) {
  cat(sprintf("\n\n========== AGGREGATE PPI LP, %s ==========\n", w$label))
  d_w <- df %>% filter(date >= w$start, date <= w$end)
  cat(sprintf("Sample: %d months\n", nrow(d_w)))
  cat(sprintf("CPShock non-zero months: %d/%d\n",
              sum(d_w$cps != 0), nrow(d_w)))

  irf <- run_lp(d_w)
  cat("\nIRF (selected horizons, in % per unit CPShock):\n")
  print(irf %>% filter(h %in% c(0, 3, 6, 9, 12, 18, 24, 30, 36)) %>%
        mutate(coef_pct = round(100 * coef, 3),
               se_pct = round(100 * se, 3),
               lo90_pct = round(100 * lo90, 3),
               hi90_pct = round(100 * hi90, 3)) %>%
        select(h, coef_pct, se_pct, lo90_pct, hi90_pct, n),
        row.names = FALSE)

  csv_path <- file.path(OUTPUT_TAB,
                        sprintf("phase3_aggregate_ppi_lp%s.csv", w$suffix))
  write.csv(irf, csv_path, row.names = FALSE)

  p <- plot_irf(irf, w$label)
  pdf_path <- file.path(OUTPUT_FIG,
                        sprintf("phase3_aggregate_ppi_lp%s.pdf", w$suffix))
  png_path <- file.path(OUTPUT_FIG,
                        sprintf("phase3_aggregate_ppi_lp%s.png", w$suffix))
  ggsave(pdf_path, p, width = 6.5, height = 3.5)
  ggsave(png_path, p, width = 6.5, height = 3.5, dpi = 300)
  cat(sprintf("Saved: %s\n", basename(pdf_path)))

  # Sign-stability summary
  n_pos <- sum(irf$coef > 0); n_neg <- sum(irf$coef < 0)
  n_pos_sig68 <- sum(irf$coef > 0 & irf$lo68 > 0)
  n_neg_sig68 <- sum(irf$coef < 0 & irf$hi68 < 0)
  cat(sprintf("Sign stability: %d positive, %d negative; sig at 68%%: %d pos, %d neg\n",
              n_pos, n_neg, n_pos_sig68, n_neg_sig68))
}
