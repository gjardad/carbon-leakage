###############################################################################
# phase3_eua_price_timeseries_figure.R
#
# PURPOSE:
#   Generate a daily-frequency EUA spot price figure for §3 ("How Big Is the
#   Shock?") of the paper. Mimics the template from Känzig (2023) JMP Figure 1
#   (the EUA price time-series with phase shading), extended through 2022 and
#   with the MSR decision (2015-10-06) marked.
#
# DATA:
#   ${RAW_DATA}/icap_euets_price_2005_26.csv
#     Two primary-market price columns (parsing logic copied from
#     phase3_eua_prices.R):
#       cols 1-6:   date, fx_eur, fx_usd, ccy, primary_market (2005-2018)
#       cols 7-12:  date-aligned block for 2019+ (primary_market = col 10)
#
# OUTPUT:
#   ${OUTPUT_FIG}/phase3_eua_price_timeseries.pdf
#   ${OUTPUT_FIG}/phase3_eua_price_timeseries.png
###############################################################################

rm(list = ls())

library(dplyr)
library(readr)
library(ggplot2)

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

icap_file <- file.path(RAW_DATA, "icap_euets_price_2005_26.csv")
if (!file.exists(icap_file)) {
  stop("ICAP CSV not found at: ", icap_file,
       ". This figure requires the daily series; run on local-1.")
}

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

icap <- icap_raw %>%
  mutate(price = coalesce(price_pre2019, price_from2019, price_secondary)) %>%
  filter(!is.na(date), !is.na(price))

# Trim to end-2022. ICAP daily Primary-Market series starts 2010-01;
# Phase I (2005-07) and most of Phase II (2008-09) are not available in this
# file — we report the visible window starting 2010 in Phase II.
icap <- icap %>% filter(date <= as.Date("2022-12-31"))

cat("Daily / weekly EUA price obs:", nrow(icap), "\n")
cat("Date range:", format(min(icap$date)), "to", format(max(icap$date)), "\n")
cat("Price range:", round(min(icap$price), 2), "to", round(max(icap$price), 2), "\n")

# ---- Phase boundaries + MSR event ----
# Visible-data phases start at min(date) of icap, so phase II label is centered
# on the visible portion (2010-2012), not on the unobserved early window.
data_start <- min(icap$date)
phase_visible_starts <- as.Date(c(format(data_start), "2013-01-01", "2021-01-01"))
phase_visible_ends   <- as.Date(c("2012-12-31", "2020-12-31", "2022-12-31"))
phase_visible_labels <- c("Phase II", "Phase III", "Phase IV")
phase_mids <- as.Date((as.numeric(phase_visible_starts) +
                       as.numeric(phase_visible_ends)) / 2,
                      origin = "1970-01-01")

# Boundary lines: Phase II→III and Phase III→IV
boundary_dates <- as.Date(c("2013-01-01", "2021-01-01"))
msr_date <- as.Date("2015-10-06")  # Decision (EU) 2015/1814

phase_df <- data.frame(start = phase_visible_starts, end = phase_visible_ends,
                       mid = phase_mids, label = phase_visible_labels)

# ---- Plot ----
y_max <- ceiling(max(icap$price) / 10) * 10
y_label_top <- y_max - 2

p <- ggplot(icap, aes(x = date, y = price)) +
  # Vertical phase boundaries (Phase II→III, Phase III→IV)
  geom_vline(xintercept = boundary_dates,
             colour = "firebrick", linewidth = 0.5) +
  # MSR decision date (dashed, distinct from phase boundaries)
  geom_vline(xintercept = msr_date,
             colour = "darkgreen", linewidth = 0.5, linetype = "dashed") +
  # Daily series
  geom_line(colour = "steelblue", linewidth = 0.4) +
  # Phase labels at the top
  geom_text(data = phase_df, aes(x = mid, y = y_label_top, label = label),
            inherit.aes = FALSE, size = 3.6) +
  # MSR label
  annotate("text", x = msr_date + 90, y = y_label_top - 4,
           label = "MSR (Oct 2015)", colour = "darkgreen",
           hjust = 0, size = 3.2) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y",
               expand = c(0.01, 0.01)) +
  scale_y_continuous(limits = c(0, y_max),
                     breaks = seq(0, y_max, by = 20),
                     expand = c(0.01, 0.01)) +
  labs(x = NULL, y = expression("EUR / tCO"[2])) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_line(colour = "grey90"),
        panel.grid.major.y = element_line(colour = "grey90"),
        axis.line = element_line(colour = "black"))

print(p)

ggsave(file.path(OUTPUT_FIG, "phase3_eua_price_timeseries.pdf"), p,
       width = 8, height = 3.6)
ggsave(file.path(OUTPUT_FIG, "phase3_eua_price_timeseries.png"), p,
       width = 8, height = 3.6, dpi = 300)

cat("\nSaved:\n  ",
    file.path(OUTPUT_FIG, "phase3_eua_price_timeseries.pdf"), "\n  ",
    file.path(OUTPUT_FIG, "phase3_eua_price_timeseries.png"), "\n")
