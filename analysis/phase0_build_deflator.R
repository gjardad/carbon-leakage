###############################################################################
# phase0_build_deflator.R
#
# PURPOSE:
#   Build a unified annual PPI deflator at the finest available NACE level,
#   re-indexed to 2005 = 100.
#
#   Strategy:
#     2005-2009: Eurostat NACE 2-digit domestic PPI
#     2010-2024: Statbel NACE 4-digit domestic PPI (chain-linked at 2010)
#     For NACE 4-digit codes missing from Statbel (incl. 18, 30): Eurostat
#     2-digit (or aggregates C16-C18, C29-C30) for the full period.
#
#   Eurostat comes in three base years (2010, 2015, 2021). We chain-link
#   them into a single 2005=100 series.
#
# DATA:
#   - NBB_data/raw/Statbel/TABEL_WEBSITE_AANGEVERS_EN.xlsx
#   - NBB_data/raw/Eurostat/sts_inppd_a__custom_21089145_linear.csv
#
# OUTPUT:
#   - NBB_data/processed/deflator_nace4d_2005base.RData
###############################################################################

rm(list = ls())

library(dplyr)
library(tidyr)
library(readxl)
library(stringr)

# ---- Paths ----
nbb_data  <- "c:/Users/jota_/Documents/NBB_data"
raw_data  <- file.path(nbb_data, "raw")
proc_data <- file.path(nbb_data, "processed")
dir.create(proc_data, showWarnings = FALSE, recursive = TRUE)

base_year <- 2005
link_year <- 2010  # where Eurostat 2d and Statbel 4d overlap

###############################################################################
# STEP 1: Parse Statbel NACE 4-digit PPI (domestic market, 2010=100)
###############################################################################

statbel_file <- file.path(raw_data, "Statbel",
                          "TABEL_WEBSITE_AANGEVERS_EN.xlsx")

d <- read_excel(statbel_file, sheet = "Domestic market", col_names = FALSE)

names(d) <- c("nace4d_raw", "label_or_year",
              "Jan","Feb","Mar","Apr","May","Jun",
              "Jul","Aug","Sep","Oct","Nov","Dec","Annual")

d <- d %>%
  mutate(nace4d = ifelse(!is.na(nace4d_raw), as.character(nace4d_raw), NA_character_)) %>%
  tidyr::fill(nace4d, .direction = "down") %>%
  mutate(year = suppressWarnings(as.integer(label_or_year))) %>%
  filter(!is.na(year)) %>%
  mutate(across(c(Jan:Dec, Annual), as.numeric)) %>%
  mutate(ppi_annual = ifelse(!is.na(Annual), Annual,
                             rowMeans(pick(Jan:Dec), na.rm = TRUE)))

ppi_statbel <- d %>%
  select(nace4d, year, ppi_statbel = ppi_annual) %>%
  filter(!is.na(ppi_statbel)) %>%
  mutate(nace4d = str_pad(nace4d, width = 4, side = "left", pad = "0"),
         nace2d = str_sub(nace4d, 1, 2))

cat("Statbel PPI:", n_distinct(ppi_statbel$nace4d), "NACE 4d sectors,",
    min(ppi_statbel$year), "-", max(ppi_statbel$year), "\n")

###############################################################################
# STEP 2: Parse Eurostat PPI — build a continuous NACE 2-digit series
#         by chain-linking across base years (2010, 2015, 2021)
###############################################################################

eurostat_file <- file.path(raw_data, "Eurostat",
                           "sts_inppd_a__custom_21089145_linear.csv")
eu_raw <- read.csv(eurostat_file, stringsAsFactors = FALSE)

# --- 2a. Extract clean 2-digit series with base year tags ---
eu_2d <- eu_raw %>%
  filter(str_detect(nace_r2, "^[A-Z][0-9]{2}:")) %>%
  mutate(
    nace2d = str_extract(nace_r2, "[0-9]{2}"),
    year   = as.integer(TIME_PERIOD),
    ppi    = as.numeric(OBS_VALUE),
    base   = case_when(
      str_detect(unit, "2010") ~ "b2010",
      str_detect(unit, "2015") ~ "b2015",
      str_detect(unit, "2021") ~ "b2021"
    )
  ) %>%
  filter(!is.na(ppi), !is.na(base)) %>%
  select(nace2d, year, ppi, base)

# --- 2b. Also extract aggregates for NACE 18 and 30 fallback ---
eu_agg <- eu_raw %>%
  filter(str_detect(nace_r2, "C16-C18|C29_C30")) %>%
  mutate(
    nace2d = case_when(
      str_detect(nace_r2, "C16-C18") ~ "18",
      str_detect(nace_r2, "C29_C30") ~ "30"
    ),
    year = as.integer(TIME_PERIOD),
    ppi  = as.numeric(OBS_VALUE),
    base = case_when(
      str_detect(unit, "2010") ~ "b2010",
      str_detect(unit, "2015") ~ "b2015",
      str_detect(unit, "2021") ~ "b2021"
    )
  ) %>%
  filter(!is.na(ppi), !is.na(base)) %>%
  select(nace2d, year, ppi, base)

# For NACE 18 and 30: replace their (incomplete) 2-digit series with the aggregates
eu_2d <- eu_2d %>%
  filter(!(nace2d %in% c("18", "30"))) %>%
  bind_rows(eu_agg)

# --- 2c. Chain-link across base years into a single 2005=100 series ---
#
# Strategy per sector:
#   1. Start with b2010 series (longest history, 1981-2017)
#   2. Extend to 2018+ by chain-linking b2015 at 2017
#   3. If b2015 doesn't reach far enough, chain-link b2021 at the overlap
#   4. Re-index everything to 2005 = 100

chain_link_sector <- function(df) {
  # df has columns: year, ppi, base for one nace2d

  # Pivot wide: one column per base year
  wide <- df %>%
    pivot_wider(names_from = base, values_from = ppi, names_prefix = "ppi_")

  # Start with b2010 as the anchor
  if ("ppi_b2010" %in% names(wide)) {
    wide$ppi_chain <- wide$ppi_b2010
  } else {
    wide$ppi_chain <- NA_real_
  }

  # Chain-link b2015 at the latest overlapping year with b2010
  if ("ppi_b2015" %in% names(wide)) {
    overlap_15 <- wide %>% filter(!is.na(ppi_chain), !is.na(ppi_b2015)) %>%
      filter(year == max(year))
    if (nrow(overlap_15) > 0) {
      ratio_15 <- overlap_15$ppi_chain / overlap_15$ppi_b2015
      wide <- wide %>%
        mutate(ppi_chain = ifelse(is.na(ppi_chain) & !is.na(ppi_b2015),
                                  ppi_b2015 * ratio_15, ppi_chain))
    }
  }

  # Chain-link b2021 at the latest overlapping year with current chain
  if ("ppi_b2021" %in% names(wide)) {
    overlap_21 <- wide %>% filter(!is.na(ppi_chain), !is.na(ppi_b2021)) %>%
      filter(year == max(year))
    if (nrow(overlap_21) > 0) {
      ratio_21 <- overlap_21$ppi_chain / overlap_21$ppi_b2021
      wide <- wide %>%
        mutate(ppi_chain = ifelse(is.na(ppi_chain) & !is.na(ppi_b2021),
                                  ppi_b2021 * ratio_21, ppi_chain))
    }
  }

  wide %>% select(year, ppi_chain) %>% filter(!is.na(ppi_chain))
}

ppi_eurostat <- eu_2d %>%
  group_by(nace2d) %>%
  group_modify(~ chain_link_sector(.x)) %>%
  ungroup() %>%
  rename(ppi_2010base = ppi_chain)

# Re-index to 2005 = 100
base_vals <- ppi_eurostat %>%
  filter(year == base_year) %>%
  select(nace2d, base_val = ppi_2010base)

ppi_eurostat <- ppi_eurostat %>%
  left_join(base_vals, by = "nace2d") %>%
  mutate(ppi_2005 = ppi_2010base / base_val * 100) %>%
  filter(!is.na(ppi_2005), year >= base_year) %>%
  select(nace2d, year, ppi_2005)

# --- 2e. Fill gaps by linear interpolation (NACE 18, 30: gap in 2018-2020) ---
#     See DATA_CLEANING.md, Assumption 4.
ppi_eurostat <- ppi_eurostat %>%
  group_by(nace2d) %>%
  arrange(nace2d, year) %>%
  # Complete the year sequence so interpolation has rows to fill
  complete(year = seq(base_year, max(ppi_eurostat$year))) %>%
  mutate(ppi_2005 = approx(year, ppi_2005, year, rule = 1)$y) %>%
  ungroup() %>%
  filter(!is.na(ppi_2005))

cat("Eurostat chained + interpolated:", n_distinct(ppi_eurostat$nace2d), "NACE 2d sectors,",
    min(ppi_eurostat$year), "-", max(ppi_eurostat$year), "\n")

# Check coverage
cat("\n=== Eurostat 2d year coverage ===\n")
print(as.data.frame(
  ppi_eurostat %>% group_by(nace2d) %>%
    summarise(min_yr = min(year), max_yr = max(year), n = n(), .groups = "drop") %>%
    arrange(nace2d)
))

###############################################################################
# STEP 3: Chain-link Statbel 4-digit to Eurostat 2-digit at 2010
###############################################################################

eurostat_at_link <- ppi_eurostat %>%
  filter(year == link_year) %>%
  select(nace2d, eurostat_link_val = ppi_2005)

statbel_at_link <- ppi_statbel %>%
  filter(year == link_year) %>%
  select(nace4d, nace2d, statbel_link_val = ppi_statbel)

ppi_statbel_chained <- ppi_statbel %>%
  filter(year >= link_year) %>%
  left_join(statbel_at_link %>% select(nace4d, statbel_link_val), by = "nace4d") %>%
  left_join(eurostat_at_link, by = "nace2d") %>%
  mutate(ppi = (ppi_statbel / statbel_link_val) * eurostat_link_val) %>%
  filter(!is.na(ppi)) %>%
  select(nace4d, nace2d, year, ppi) %>%
  mutate(ppi_source = "statbel_4d_chained")

cat("Statbel chained:", n_distinct(ppi_statbel_chained$nace4d), "sectors,",
    nrow(ppi_statbel_chained), "obs\n")

###############################################################################
# STEP 4: Build unified deflator
###############################################################################

# Pre-2010: map Statbel nace4d codes to Eurostat 2-digit
nace4d_to_2d <- ppi_statbel %>% distinct(nace4d, nace2d)

deflator_pre2010 <- nace4d_to_2d %>%
  cross_join(tibble(year = base_year:(link_year - 1))) %>%
  left_join(ppi_eurostat %>% select(nace2d, year, ppi = ppi_2005),
            by = c("nace2d", "year")) %>%
  filter(!is.na(ppi)) %>%
  mutate(ppi_source = "eurostat_2d") %>%
  select(nace4d, nace2d, year, ppi, ppi_source)

# Combine
deflator <- bind_rows(deflator_pre2010, ppi_statbel_chained) %>%
  arrange(nace4d, year)

# 2-digit fallback for firms whose nace4d isn't in Statbel
deflator_2d_only <- ppi_eurostat %>%
  filter(year >= base_year) %>%
  select(nace2d, year, ppi = ppi_2005) %>%
  mutate(ppi_source = "eurostat_2d")

###############################################################################
# STEP 5: Validate and save
###############################################################################

cat("\n=== Deflator summary ===\n")
cat("NACE 4-digit sectors:", n_distinct(deflator$nace4d), "\n")
cat("NACE 2-digit fallback sectors:", n_distinct(deflator_2d_only$nace2d), "\n")
cat("Year range:", min(deflator$year), "-", max(deflator$year), "\n")
cat("Total obs:", nrow(deflator), "\n")
cat("Source breakdown:\n")
print(table(deflator$ppi_source))

# Spot checks
cat("\n=== Spot check: NACE 2410 (basic iron & steel) ===\n")
print(as.data.frame(deflator %>% filter(nace4d == "2410") %>% select(-nace2d)))

cat("\n=== Spot check: NACE 2351 (cement) ===\n")
print(as.data.frame(deflator %>% filter(nace4d == "2351") %>% select(-nace2d)))

cat("\n=== Spot check: Eurostat 2d fallback for NACE 18 ===\n")
print(as.data.frame(deflator_2d_only %>% filter(nace2d == "18")))

cat("\n=== Spot check: Eurostat 2d fallback for NACE 30 ===\n")
print(as.data.frame(deflator_2d_only %>% filter(nace2d == "30")))

# Save
save(deflator, deflator_2d_only,
     file = file.path(proc_data, "deflator_nace4d_2005base.RData"))
cat("\nSaved to:", file.path(proc_data, "deflator_nace4d_2005base.RData"), "\n")
