###############################################################################
# phase3_eua_price_timeseries_figure.R
#
# PURPOSE:
#   Generate a daily-frequency EUA price figure for §3 ("How Big Is the
#   Shock?") of the paper. Mimics the template from Känzig (2023) JMP Figure 1
#   (the EUA price time-series with phase shading), with the MSR decision
#   (2015-10-06) marked.
#
# DATA:
#   ${RAW_DATA}/European Union Carbon Permits Allowance (EUA) Yearly Futures Historical Data.csv
#     Daily settlement prices of the ECX/ICE-Endex EUA continuous front-year
#     futures contract (the Investing.com export; same series convention as
#     the Refinitiv Datastream `LECEZ` series used by Känzig 2023). Columns:
#       Date (MM/DD/YYYY), Price, Open, High, Low, Vol., Change %.
#     Coverage: 2005-04-25 onward. We trim to end-2022 to align with the
#     paper's analysis sample.
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

eua_file <- file.path(
  RAW_DATA,
  "European Union Carbon Permits Allowance (EUA) Yearly Futures Historical Data.csv"
)
if (!file.exists(eua_file)) {
  stop("EUA daily futures CSV not found at: ", eua_file)
}

eua_raw <- read_csv(
  eua_file,
  col_types = cols(
    Date  = col_date(format = "%m/%d/%Y"),
    Price = col_double(),
    .default = col_character()
  )
)

eua <- eua_raw %>%
  rename(date = Date, price = Price) %>%
  filter(!is.na(date), !is.na(price)) %>%
  arrange(date) %>%
  filter(date <= as.Date("2022-12-31"))

cat("Daily EUA price obs:", nrow(eua), "\n")
cat("Date range:", format(min(eua$date)), "to", format(max(eua$date)), "\n")
cat("Price range:", round(min(eua$price), 2), "to", round(max(eua$price), 2), "\n")

# ---- Phase boundaries + MSR event ----
x_min <- as.Date("2005-01-01")
x_max <- as.Date("2022-12-31")

phase_visible_starts <- as.Date(c("2005-01-01", "2008-01-01",
                                  "2013-01-01", "2021-01-01"))
phase_visible_ends   <- as.Date(c("2007-12-31", "2012-12-31",
                                  "2020-12-31", "2022-12-31"))
phase_visible_labels <- c("Phase I", "Phase II", "Phase III", "Phase IV")
phase_mids <- as.Date((as.numeric(phase_visible_starts) +
                       as.numeric(phase_visible_ends)) / 2,
                      origin = "1970-01-01")

# Boundary lines: Phase I→II, Phase II→III, Phase III→IV
boundary_dates <- as.Date(c("2008-01-01", "2013-01-01", "2021-01-01"))
msr_date <- as.Date("2015-10-06")  # Decision (EU) 2015/1814

phase_df <- data.frame(start = phase_visible_starts, end = phase_visible_ends,
                       mid = phase_mids, label = phase_visible_labels)

# ---- Plot ----
y_max_data <- max(eua$price)
y_max <- ceiling((y_max_data + 25) / 10) * 10   # ~25 EUR headroom
y_label_top <- y_max - 5

p <- ggplot(eua, aes(x = date, y = price)) +
  geom_vline(xintercept = boundary_dates,
             colour = "firebrick", linewidth = 0.5) +
  geom_vline(xintercept = msr_date,
             colour = "darkgreen", linewidth = 0.5, linetype = "dashed") +
  geom_line(colour = "steelblue", linewidth = 0.4) +
  geom_text(data = phase_df, aes(x = mid, y = y_label_top, label = label),
            inherit.aes = FALSE, size = 3.6) +
  annotate("text", x = as.Date("2017-01-01"), y = y_label_top - 8,
           label = "MSR", colour = "darkgreen", hjust = 0, size = 3.4) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y",
               limits = c(x_min, x_max), expand = c(0.01, 0.01)) +
  scale_y_continuous(limits = c(0, y_max),
                     breaks = seq(0, y_max, by = 20),
                     expand = c(0.01, 0.01)) +
  labs(x = NULL, y = expression("EUR / tCO"[2])) +
  theme_minimal(base_size = 11) +
  theme(panel.grid = element_blank(),
        axis.line = element_line(colour = "black"))

print(p)

ggsave(file.path(OUTPUT_FIG, "phase3_eua_price_timeseries.pdf"), p,
       width = 8, height = 3.6)
ggsave(file.path(OUTPUT_FIG, "phase3_eua_price_timeseries.png"), p,
       width = 8, height = 3.6, dpi = 300)

# ---- Verification: print well-known historical milestones ----
milestones <- list(
  list(label = "Phase I peak (Apr 2006, expected ~€30)",
       window = c("2006-04-01", "2006-04-30"), fn = max),
  list(label = "May 2006 crash trough (expected ~€10)",
       window = c("2006-05-01", "2006-05-31"), fn = min),
  list(label = "Phase I drift through 2007 (expected ~€0)",
       window = c("2007-06-01", "2007-12-31"), fn = function(x) mean(x, na.rm = TRUE)),
  list(label = "Phase II 2008 reset (expected ~€22)",
       window = c("2008-01-01", "2008-06-30"), fn = function(x) mean(x, na.rm = TRUE)),
  list(label = "2009 financial-crisis trough (expected ~€8)",
       window = c("2009-01-01", "2009-04-30"), fn = min),
  list(label = "2022 peak (expected ~€80+)",
       window = c("2022-01-01", "2022-12-31"), fn = max)
)
cat("\n--- Historical milestone check ---\n")
for (m in milestones) {
  sub <- eua %>% filter(date >= as.Date(m$window[1]),
                        date <= as.Date(m$window[2]))
  if (nrow(sub) == 0) {
    cat(sprintf("  %-55s : NO DATA\n", m$label))
  } else {
    cat(sprintf("  %-55s : %.2f EUR\n", m$label, m$fn(sub$price)))
  }
}

cat("\nSaved:\n  ",
    file.path(OUTPUT_FIG, "phase3_eua_price_timeseries.pdf"), "\n  ",
    file.path(OUTPUT_FIG, "phase3_eua_price_timeseries.png"), "\n")
