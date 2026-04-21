###############################################################################
# phase3_eua_prices.R
#
# PURPOSE:
#   Build an annual EUA (EU Allowance) spot-price series covering 2005-2023,
#   from ICAP weekly/daily data for 2010-2025, and hard-coded Phase I/II values
#   for 2005-2009. Saves a tidy data frame for downstream phase3 scripts.
#
# DATA:
#   NBB_data/raw/icap_euets_price_2005_26.csv
#     Two primary-market price columns:
#       cols 1-6:   date, fx_eur, fx_usd, ccy, primary_market (2005-2018)
#       cols 7-12:  date-aligned block for 2019+ (primary_market = col 10)
#
#   For 2005-2009 the ICAP data is sparse / missing, so we use the annual means
#   that were already curated in the existing phase1/phase2 scripts.
#
# OUTPUT:
#   data/processed/phase3_eua_prices.RData  (eua_prices_annual)
###############################################################################

rm(list = ls())

library(dplyr)
library(readr)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

icap_file <- file.path(RAW_DATA, "icap_euets_price_2005_26.csv")

# ---- Read ICAP file (skip 2-row header) ----
# Column layout (indices are 1-based):
#   1: Date
#   2: fx EUR/EUR      (pre-2019 block)
#   3: fx EUR/USD
#   4: Market currency
#   5: Primary Market price (EUR/tCO2), 2005-2018
#   6: spacer
#   7: fx EUR/EUR      (from-2019 block)
#   8: fx EUR/USD
#   9: Market currency
#  10: Primary Market price, 2019+
#  11: Secondary Market price, 2019+
#  12: spacer
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
  mutate(year = as.integer(format(date, "%Y")),
         price = coalesce(price_pre2019, price_from2019, price_secondary)) %>%
  filter(!is.na(price), !is.na(year))

cat("ICAP daily/weekly obs:", nrow(icap), "\n")
cat("Years covered:", min(icap$year), "-", max(icap$year), "\n")

icap_annual <- icap %>%
  group_by(year) %>%
  summarise(eua_price_icap = mean(price, na.rm = TRUE),
            n_obs = n(),
            .groups = "drop")

cat("\n=== ICAP annual mean prices ===\n")
print(as.data.frame(icap_annual))

# ---- Curated Phase I/II values (2005-2009) from prior scripts ----
# Sources: ECX/Bluenext historical, as documented in the literature
# (Ellerman et al. 2010; Martin, Muuls, Wagner 2016).
curated_early <- data.frame(
  year = 2005:2009,
  eua_price_curated = c(22, 18, 0.7, 22, 13)
)

# ---- Build unified series ----
eua_prices_annual <- data.frame(year = 2005:2023) %>%
  left_join(icap_annual, by = "year") %>%
  left_join(curated_early, by = "year") %>%
  mutate(
    eua_price = ifelse(year <= 2009 | is.na(eua_price_icap),
                       eua_price_curated, eua_price_icap),
    source = case_when(
      year <= 2009 ~ "curated (ECX/Bluenext, Phase I/II)",
      !is.na(eua_price_icap) ~ "ICAP annual mean",
      TRUE ~ NA_character_
    )
  ) %>%
  select(year, eua_price, source, eua_price_icap, eua_price_curated, n_obs)

cat("\n=== Unified annual EUA price series 2005-2023 ===\n")
print(eua_prices_annual)

# Phase labels (helper for downstream)
eua_prices_annual <- eua_prices_annual %>%
  mutate(phase = case_when(
    year %in% 2005:2007 ~ "Phase I",
    year %in% 2008:2012 ~ "Phase II",
    year %in% 2013:2020 ~ "Phase III",
    year >= 2021        ~ "Phase IV"
  ))

# ---- Save ----
save(eua_prices_annual, file = file.path(OUT_DATA, "phase3_eua_prices.RData"))
cat("\nSaved to:", file.path(OUT_DATA, "phase3_eua_prices.RData"), "\n")
cat("Done.\n")
