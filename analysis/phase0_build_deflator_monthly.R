###############################################################################
# phase0_build_deflator_monthly.R
#
# PURPOSE:
#   Build a monthly Belgian PPI panel at the finest available NACE level,
#   re-indexed to 2005 = 100.
#
#   Parallels phase0_build_deflator.R but keeps monthly granularity. The
#   annual version averages monthly values to yearly; this script skips
#   that aggregation.
#
#   Strategy:
#     2000-01 to 2009-12: Eurostat NACE 2-digit domestic monthly PPI (BE,
#                         from sts_inppd_m). For most regulated NACE 2d the
#                         underlying I10 series goes back to 1981; we extend
#                         the panel to 2000-01 to provide pre-ETS observations
#                         needed for CMdG-style event-study replication.
#     2010-01 to 2024-12: Statbel NACE 4-digit domestic monthly PPI
#                         (chain-linked to Eurostat at 2010-01).
#
#   Eurostat comes in three base years (2010, 2015, 2021); chain-linked
#   at monthly frequency. Statbel domestic file starts in 2010.
#
# DATA:
#   - NBB_data/raw/Statbel/TABEL_WEBSITE_AANGEVERS_EN.xlsx
#   - Eurostat sts_inppd_m (downloaded via `eurostat` package)
#
# OUTPUT:
#   - NBB_data/processed/deflator_nace4d_2005base_monthly.RData
#     data.frame(nace4d, nace2d, year, month, date, ppi, ppi_source)
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readxl)
  library(stringr)
  library(lubridate)
  library(eurostat)
})

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

base_year   <- 2005                          # 2005 annual avg = 100
lower_bound <- as.Date("1981-01-01")         # earliest date in panel (Eurostat I10 starts 1981-01 for most NACE 2d manufacturing sectors)
link_date   <- as.Date("2010-01-01")         # month where Eurostat 2d meets Statbel 4d

###############################################################################
# STEP 1: Parse Statbel NACE 4-digit MONTHLY PPI
###############################################################################

statbel_file <- file.path(RAW_DATA, "Statbel",
                          "TABEL_WEBSITE_AANGEVERS_EN.xlsx")

d <- read_excel(statbel_file, sheet = "Domestic market", col_names = FALSE)
names(d) <- c("nace4d_raw", "label_or_year",
              "Jan","Feb","Mar","Apr","May","Jun",
              "Jul","Aug","Sep","Oct","Nov","Dec","Annual")

d <- d %>%
  mutate(nace4d = ifelse(!is.na(nace4d_raw),
                         as.character(nace4d_raw), NA_character_)) %>%
  fill(nace4d, .direction = "down") %>%
  mutate(year = suppressWarnings(as.integer(label_or_year))) %>%
  filter(!is.na(year)) %>%
  mutate(across(c(Jan:Dec), as.numeric))

ppi_statbel_mly <- d %>%
  select(nace4d, year, Jan:Dec) %>%
  pivot_longer(cols = Jan:Dec, names_to = "month_abbr",
               values_to = "ppi_statbel") %>%
  mutate(month = match(month_abbr, month.abb),
         date  = as.Date(sprintf("%d-%02d-01", year, month))) %>%
  select(-month_abbr) %>%
  filter(!is.na(ppi_statbel)) %>%
  mutate(nace4d = str_pad(nace4d, width = 4, side = "left", pad = "0"),
         nace2d = str_sub(nace4d, 1, 2))

cat(sprintf("Statbel monthly: %d obs, %d NACE 4d sectors, %s to %s\n",
            nrow(ppi_statbel_mly),
            n_distinct(ppi_statbel_mly$nace4d),
            format(min(ppi_statbel_mly$date)),
            format(max(ppi_statbel_mly$date))))

###############################################################################
# STEP 2: Download Eurostat MONTHLY PPI for Belgium, NACE 2-digit
###############################################################################
# sts_inppd_m = short-term industrial producer price index (monthly)
# indic_bt = "PRIN" = domestic output price index
# s_adj    = "NSA"  = not seasonally adjusted
# unit     = varies: "I10", "I15", "I21" (base 2010, 2015, 2021)
#
# The `eurostat` package's JSON endpoint fails silently for this dataset
# (likely response too large), so we download the bulk TSV directly from
# Eurostat's dissemination API and parse it here.

eu_file <- file.path(RAW_DATA, "Eurostat", "sts_inppd_m_BE.tsv.gz")
if (!file.exists(eu_file)) {
  cat("\nDownloading Eurostat sts_inppd_m (bulk TSV, BE filter) ...\n")
  url <- "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/sts_inppd_m?format=TSV&compressed=true&geo=BE"
  options(timeout = 600)
  download.file(url, destfile = eu_file, mode = "wb", quiet = FALSE)
}
cat(sprintf("Eurostat TSV size: %.1f MB\n", file.size(eu_file) / 1e6))

# Eurostat bulk TSV format: first column is dot-separated dimension tuple
# (freq.indic_bt.nace_r2.s_adj.unit.geo), then one column per TIME_PERIOD
# (X1975.01, X1975.02, ...). Parse dimensions then pivot long.
eu_wide <- read.delim(gzfile(eu_file), stringsAsFactors = FALSE,
                      check.names = FALSE, na.strings = c(":", ": ", ""))
dim_col <- names(eu_wide)[1]
cat(sprintf("First-col label: %s\n", dim_col))
# The dim_col header has some whitespace after TIME_PERIOD; strip it
cat(sprintf("Total rows (dimension combos): %d\n", nrow(eu_wide)))

eu_long <- eu_wide %>%
  rename(dims = !!sym(dim_col)) %>%
  separate(dims,
           into = c("freq", "indic_bt", "nace_r2", "s_adj", "unit", "geo"),
           sep = ",", extra = "drop", fill = "right") %>%
  filter(indic_bt == "PRC_PRR_DOM", s_adj == "NSA") %>%
  pivot_longer(cols = -c(freq, indic_bt, nace_r2, s_adj, unit, geo),
               names_to = "period", values_to = "ppi_raw") %>%
  mutate(
    period = str_trim(period),
    # period like "1975-01" or "1975M01" depending on Eurostat format
    year   = suppressWarnings(as.integer(str_sub(period, 1, 4))),
    month  = suppressWarnings(as.integer(str_sub(period, 6, 7)))
  ) %>%
  filter(!is.na(year), !is.na(month)) %>%
  mutate(
    date = as.Date(sprintf("%d-%02d-01", year, month)),
    ppi  = suppressWarnings(as.numeric(str_remove_all(ppi_raw, "[^0-9.-]")))
  ) %>%
  filter(!is.na(ppi))

cat(sprintf("Eurostat long after filter + pivot: %d obs\n", nrow(eu_long)))
cat("Unique geo codes:", paste(unique(eu_long$geo), collapse = ", "), "\n")
cat("Unique unit codes:", paste(unique(eu_long$unit), collapse = ", "), "\n")
cat("First 20 nace_r2 sorted:",
    paste(head(sort(unique(eu_long$nace_r2)), 20), collapse = ", "), "\n")
cat("N distinct nace_r2:", n_distinct(eu_long$nace_r2), "\n")
cat("Has 'C10'?:", "C10" %in% eu_long$nace_r2, "\n")
cat("Has 'C24'?:", "C24" %in% eu_long$nace_r2, "\n")

# Restrict to Belgium geo
eu_long <- eu_long %>% filter(geo == "BE")
cat(sprintf("After geo=BE filter: %d obs\n", nrow(eu_long)))
cat("After BE filter, has 'C10'?:", "C10" %in% eu_long$nace_r2, "\n")

# Extract 2-digit NACE codes (plus NACE18 / NACE30 aggregates for sectors
# Eurostat doesn't publish at 2-digit separately)
eu_2d <- eu_long %>%
  filter(str_detect(nace_r2, "^C[0-9]{2}$") |
         nace_r2 %in% c("C16-C18", "C16_C17_C18", "C29_C30", "C29-C30")) %>%
  mutate(
    nace2d = case_when(
      str_detect(nace_r2, "C16-C18|C16_C17_C18") ~ "18",
      str_detect(nace_r2, "C29[-_]C30")          ~ "30",
      TRUE                                       ~ str_extract(nace_r2, "[0-9]{2}")
    ),
    base = case_when(
      unit == "I10" | str_detect(unit, "2010") ~ "b2010",
      unit == "I15" | str_detect(unit, "2015") ~ "b2015",
      unit == "I21" | str_detect(unit, "2021") ~ "b2021"
    )
  ) %>%
  filter(!is.na(base)) %>%
  select(nace2d, date, ppi, base)

cat(sprintf("\nEurostat 2d monthly: %d obs, %d NACE 2d sectors, %s to %s\n",
            nrow(eu_2d), n_distinct(eu_2d$nace2d),
            format(min(eu_2d$date)), format(max(eu_2d$date))))

# Collapse duplicates within (nace2d, date, base)
eu_2d <- eu_2d %>%
  group_by(nace2d, date, base) %>%
  summarise(ppi = first(ppi), .groups = "drop")

###############################################################################
# STEP 3: Chain-link Eurostat across base years (2010 -> 2015 -> 2021),
#         at MONTHLY frequency
###############################################################################

chain_link_monthly <- function(df) {
  # df has columns: date, ppi, base for one nace2d
  wide <- df %>%
    pivot_wider(names_from = base, values_from = ppi, names_prefix = "ppi_") %>%
    arrange(date)

  # Anchor on b2010
  if ("ppi_b2010" %in% names(wide)) {
    wide$ppi_chain <- wide$ppi_b2010
  } else {
    wide$ppi_chain <- NA_real_
  }

  # Chain-link b2015 at the latest overlap month with b2010
  if ("ppi_b2015" %in% names(wide)) {
    overlap_15 <- wide %>%
      filter(!is.na(ppi_chain), !is.na(ppi_b2015)) %>%
      filter(date == max(date))
    if (nrow(overlap_15) > 0) {
      ratio_15 <- overlap_15$ppi_chain / overlap_15$ppi_b2015
      wide <- wide %>%
        mutate(ppi_chain = ifelse(is.na(ppi_chain) & !is.na(ppi_b2015),
                                  ppi_b2015 * ratio_15, ppi_chain))
    }
  }

  # Chain-link b2021 at the latest overlap month with current chain
  if ("ppi_b2021" %in% names(wide)) {
    overlap_21 <- wide %>%
      filter(!is.na(ppi_chain), !is.na(ppi_b2021)) %>%
      filter(date == max(date))
    if (nrow(overlap_21) > 0) {
      ratio_21 <- overlap_21$ppi_chain / overlap_21$ppi_b2021
      wide <- wide %>%
        mutate(ppi_chain = ifelse(is.na(ppi_chain) & !is.na(ppi_b2021),
                                  ppi_b2021 * ratio_21, ppi_chain))
    }
  }

  wide %>% select(date, ppi_chain) %>% filter(!is.na(ppi_chain))
}

ppi_eurostat_mly <- eu_2d %>%
  group_by(nace2d) %>%
  group_modify(~ chain_link_monthly(.x)) %>%
  ungroup() %>%
  rename(ppi_2010base = ppi_chain)

# Re-index to 2005 annual average = 100
base_vals <- ppi_eurostat_mly %>%
  filter(year(date) == base_year) %>%
  group_by(nace2d) %>%
  summarise(base_val = mean(ppi_2010base, na.rm = TRUE), .groups = "drop")

ppi_eurostat_mly <- ppi_eurostat_mly %>%
  left_join(base_vals, by = "nace2d") %>%
  mutate(ppi_2005 = ppi_2010base / base_val * 100) %>%
  filter(!is.na(ppi_2005), date >= lower_bound) %>%
  select(nace2d, date, ppi_2005)

cat(sprintf("\nEurostat chained monthly 2005-base: %d obs, %d NACE 2d sectors, %s to %s\n",
            nrow(ppi_eurostat_mly), n_distinct(ppi_eurostat_mly$nace2d),
            format(min(ppi_eurostat_mly$date)),
            format(max(ppi_eurostat_mly$date))))

###############################################################################
# STEP 4: Chain-link Statbel 4-digit to Eurostat 2-digit using 2010 ANNUAL
#         AVERAGES (not Jan 2010 alone). This preserves annual-average
#         consistency with the annual deflator.
###############################################################################

link_year <- 2010

statbel_2010_annual <- ppi_statbel_mly %>%
  filter(year == link_year) %>%
  group_by(nace4d, nace2d) %>%
  summarise(statbel_link_val = mean(ppi_statbel, na.rm = TRUE),
            n_months_2010 = n(), .groups = "drop") %>%
  filter(n_months_2010 == 12)   # require all 12 months for a clean link

eurostat_2010_annual <- ppi_eurostat_mly %>%
  filter(year(date) == link_year) %>%
  group_by(nace2d) %>%
  summarise(eurostat_link_val = mean(ppi_2005, na.rm = TRUE),
            n_months_2010 = n(), .groups = "drop") %>%
  filter(n_months_2010 == 12) %>%
  select(nace2d, eurostat_link_val)

ppi_statbel_chained <- ppi_statbel_mly %>%
  filter(date >= as.Date("2010-01-01")) %>%
  left_join(statbel_2010_annual %>% select(nace4d, statbel_link_val),
            by = "nace4d") %>%
  left_join(eurostat_2010_annual, by = "nace2d") %>%
  mutate(ppi = (ppi_statbel / statbel_link_val) * eurostat_link_val,
         ppi_source = "statbel_4d_chained") %>%
  filter(!is.na(ppi)) %>%
  select(nace4d, nace2d, date, year, month, ppi, ppi_source)

cat(sprintf("\nStatbel chained monthly: %d obs, %d NACE 4d sectors\n",
            nrow(ppi_statbel_chained),
            n_distinct(ppi_statbel_chained$nace4d)))

###############################################################################
# STEP 5: Pre-2010 fill using Eurostat 2-digit at monthly frequency
###############################################################################

nace4d_to_2d <- ppi_statbel_mly %>% distinct(nace4d, nace2d)

# Calendar grid of `lower_bound` through 2009-12 (extended pre-Statbel period)
pre2010_grid <- expand.grid(
  nace4d = nace4d_to_2d$nace4d,
  date   = seq(lower_bound, as.Date("2009-12-01"), by = "month"),
  stringsAsFactors = FALSE
) %>%
  as_tibble() %>%
  left_join(nace4d_to_2d, by = "nace4d") %>%
  left_join(ppi_eurostat_mly %>% rename(ppi = ppi_2005),
            by = c("nace2d", "date")) %>%
  filter(!is.na(ppi)) %>%
  mutate(year  = year(date),
         month = month(date),
         ppi_source = "eurostat_2d") %>%
  select(nace4d, nace2d, date, year, month, ppi, ppi_source)

cat(sprintf("\nPre-2010 Eurostat fill: %d obs, %d NACE 4d sectors\n",
            nrow(pre2010_grid),
            n_distinct(pre2010_grid$nace4d)))

###############################################################################
# STEP 6: Combine + 2-digit fallback series
###############################################################################

deflator_monthly <- bind_rows(pre2010_grid, ppi_statbel_chained) %>%
  arrange(nace4d, date)

deflator_2d_only_monthly <- ppi_eurostat_mly %>%
  filter(date >= lower_bound) %>%
  mutate(year = year(date), month = month(date),
         ppi = ppi_2005, ppi_source = "eurostat_2d") %>%
  select(nace2d, date, year, month, ppi, ppi_source)

###############################################################################
# STEP 7: Validate and save
###############################################################################

cat("\n=== Monthly deflator summary ===\n")
cat(sprintf("NACE 4-digit sectors: %d\n", n_distinct(deflator_monthly$nace4d)))
cat(sprintf("NACE 2-digit fallback sectors: %d\n",
            n_distinct(deflator_2d_only_monthly$nace2d)))
cat(sprintf("Date range: %s to %s\n",
            format(min(deflator_monthly$date)),
            format(max(deflator_monthly$date))))
cat(sprintf("Total obs: %d\n", nrow(deflator_monthly)))
cat("Source breakdown:\n")
print(table(deflator_monthly$ppi_source))

# Annual-average coverage check: do the monthly values average to roughly
# what the annual deflator produces?
cat("\n=== Annual-average consistency check (NACE 2410, basic iron & steel) ===\n")
monthly_check <- deflator_monthly %>%
  filter(nace4d == "2410") %>%
  group_by(year) %>%
  summarise(monthly_avg = mean(ppi, na.rm = TRUE), n_months = n(),
            .groups = "drop")
print(as.data.frame(monthly_check))

# Compare to the annual deflator if it exists
annual_file <- file.path(PROC_DATA, "deflator_nace4d_2005base.RData")
if (file.exists(annual_file)) {
  env_a <- new.env()
  load(annual_file, envir = env_a)
  annual_2410 <- env_a$deflator %>%
    filter(nace4d == "2410") %>%
    select(year, annual_ppi = ppi)
  comparison <- monthly_check %>% left_join(annual_2410, by = "year")
  cat("\nComparison monthly-avg vs annual deflator for NACE 2410:\n")
  print(as.data.frame(comparison))
}

cat("\n=== Monthly spot check: NACE 2410, 2020 (Phase IV start) ===\n")
print(as.data.frame(deflator_monthly %>%
                      filter(nace4d == "2410", year == 2020) %>%
                      select(date, ppi, ppi_source)))

# Save
save(deflator_monthly, deflator_2d_only_monthly,
     file = file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))
cat(sprintf("\nSaved: %s\n",
            file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData")))
