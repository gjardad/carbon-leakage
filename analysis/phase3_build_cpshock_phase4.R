###############################################################################
# phase3_build_cpshock_phase4.R
#
# PURPOSE:
#   Build annual carbon policy shock series for Phase IV (2020-2024) using
#   BKR (2026) event list + ICE EUA front-month futures settlement from
#   investing.com. This is our own rebuild of the CPShock series extending
#   past Kaenzig's 2019 window.
#
# METHOD (log-return normalization, BKR Figure B.7 robustness):
#   For each event date d:
#     cps_d = log(F_d / F_{d-prev}) * 100
#   where F_{d-prev} is the last trading-day close strictly before d.
#   (If d itself has no trade data, we use the preceding trading day as d.)
#
#   Aggregate to annual:
#     CPShock_y = Σ_{event d ∈ year y} cps_d
#
#   No electricity-price scaling; this is BKR's Figure B.7 / B.3 normalization.
#   Also outputs percent-change variant (BKR Figure B.3 formula) for comparison.
#
# INPUT:
#   NBB_data/raw/investing_eua_cfi2_2020_2026.csv
#   articles/bkr_event_list.csv
#
# OUTPUT:
#   data/processed/cpshock_phase4_annual.RData
#     - cpshock_phase4_annual: data.frame(year, cpshock_logret, cpshock_pct,
#                                         n_events, n_matched)
#     - cpshock_phase4_events: data.frame(date, description, category,
#                                         F_d, F_prev, cps_logret, cps_pct)
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
})

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load daily EUA settlement (investing.com CFI2) ----
eua_path <- file.path(RAW_DATA, "investing_eua_cfi2_2020_2026.csv")
stopifnot(file.exists(eua_path))

eua_raw <- read.csv(eua_path, stringsAsFactors = FALSE, check.names = FALSE,
                    fileEncoding = "UTF-8-BOM")
names(eua_raw)[1] <- "Date"  # handle any BOM issues

# Dates are MM/DD/YYYY; prices in EUR
eua <- eua_raw %>%
  transmute(
    date  = as.Date(Date, format = "%m/%d/%Y"),
    price = as.numeric(gsub(",", "", Price))
  ) %>%
  filter(!is.na(date), !is.na(price)) %>%
  arrange(date)

cat(sprintf("EUA daily series: %d rows, %s to %s\n",
            nrow(eua), format(min(eua$date)), format(max(eua$date))))
cat(sprintf("Price range: %.2f to %.2f EUR\n",
            min(eua$price), max(eua$price)))

# ---- Load BKR event list ----
events_path <- file.path(REPO_DIR, "articles", "bkr_event_list.csv")
stopifnot(file.exists(events_path))

events <- read.csv(events_path, stringsAsFactors = FALSE) %>%
  mutate(date = as.Date(date))
cat(sprintf("\nBKR events: %d (dates %s to %s)\n",
            nrow(events), format(min(events$date)), format(max(events$date))))

# ---- For each event date, find F_d and F_{d-prev trading day} ----
# Rule:
#   F_d = settlement on event day d (or the nearest preceding trading day if
#         d itself is a holiday/weekend).
#   F_{d-prev} = settlement on the trading day strictly before F_d.
#
# This mirrors how BKR/Kaenzig handle non-trading event days.

trading_dates <- eua$date  # ascending

nearest_or_prior <- function(d, dates = trading_dates) {
  idx <- findInterval(d, dates)
  if (idx < 1) return(as.Date(NA))
  dates[idx]
}

prior_trading <- function(d, dates = trading_dates) {
  idx <- findInterval(d, dates) - 1L
  if (idx < 1) return(as.Date(NA))
  dates[idx]
}

eua_lookup <- setNames(eua$price, as.character(eua$date))

events_mapped <- events %>%
  rowwise() %>%
  mutate(
    date_d      = nearest_or_prior(date),
    date_prev   = prior_trading(date_d),
    F_d         = eua_lookup[as.character(date_d)],
    F_prev      = eua_lookup[as.character(date_prev)],
    cps_logret  = 100 * log(F_d / F_prev),
    cps_pct     = 100 * (F_d - F_prev) / F_prev
  ) %>%
  ungroup() %>%
  mutate(matched = !is.na(cps_logret))

n_matched <- sum(events_mapped$matched)
cat(sprintf("\nEvents matched to EUA prices: %d / %d\n",
            n_matched, nrow(events_mapped)))
if (n_matched < nrow(events_mapped)) {
  cat("Unmatched events:\n")
  print(events_mapped %>% filter(!matched) %>% select(no, date, description))
}

cat("\nDaily surprise summary (log-return, %):\n")
summary(events_mapped$cps_logret)
cat("\nDaily surprise summary (percent change, %):\n")
summary(events_mapped$cps_pct)

cat("\nTop 5 largest surprises (by |log-return|):\n")
print(events_mapped %>%
        arrange(desc(abs(cps_logret))) %>%
        select(no, date, description, category, F_d, F_prev, cps_logret, cps_pct) %>%
        head(5))

# ---- Aggregate to annual ----
cpshock_phase4_annual <- events_mapped %>%
  filter(matched) %>%
  mutate(year = year(date_d)) %>%
  group_by(year) %>%
  summarise(
    cpshock_logret = sum(cps_logret),
    cpshock_pct    = sum(cps_pct),
    n_events       = n(),
    .groups = "drop"
  ) %>%
  # Fill in any calendar years in 2020-2024 with zero events
  right_join(data.frame(year = 2020:2024), by = "year") %>%
  mutate(across(c(cpshock_logret, cpshock_pct, n_events),
                ~ coalesce(.x, 0))) %>%
  arrange(year)

cat("\nAnnual CPShock series (Phase IV):\n")
print(cpshock_phase4_annual)

# ---- Save ----
cpshock_phase4_events <- events_mapped
save(cpshock_phase4_annual, cpshock_phase4_events,
     file = file.path(OUT_DATA, "cpshock_phase4_annual.RData"))
cat(sprintf("\nSaved: %s\n",
            file.path(OUT_DATA, "cpshock_phase4_annual.RData")))
