# Phase 0 Step 4 -- country x year ETS status.
#
# A country `iso2` is in the EU ETS perimeter in year `t` iff:
#   * EU-15 (BE, DE, DK, IE, EL/GR, ES, FR, IT, LU, NL, AT, PT, FI, SE) -- 2005+.
#   * UK (GB) -- 2005-2020. Out from 2021 (Brexit).
#   * EU-10 2004 accession (CY, CZ, EE, HU, LV, LT, MT, PL, SK, SI) -- 2005+
#     (they joined EU before ETS started).
#   * EU-2 2007 accession (BG, RO) -- 2007+.
#   * EU-1 2013 accession (HR) -- 2013+.
#   * EEA-EFTA (IS, LI, NO) -- 2008+.
#   * Switzerland (CH) -- separate Swiss ETS linked only from 2020. Treated as
#     non-ETS in the CMdG framework throughout.
#
# Output: data/concordances/country_ets_status.csv long form
#         (iso2, year, is_ets, accession_year, country_group).
#
# Notes:
#   * Customs data may use "EL" for Greece (EU convention) or "GR" (ISO 3166).
#     We emit BOTH "EL" and "GR" rows pointing to the same status.
#   * Customs data may use "UK" for United Kingdom (informal) or "GB" (ISO).
#     We emit both.
#   * Pre-2005 no country is ETS (ETS did not exist). The CSV records is_ets
#     only for ETS country-years; non-presence = non-ETS.

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)

out_path <- file.path(REPO_DIR, "data", "concordances", "country_ets_status.csv")

YEAR_RANGE   <- 2000:2022
ETS_START    <- 2005L
UK_LAST_YEAR <- 2020L

# --- Country definitions ---
EU15 <- list(
  AT = "Austria",         BE = "Belgium",   DE = "Germany",   DK = "Denmark",
  ES = "Spain",           FI = "Finland",   FR = "France",    IE = "Ireland",
  IT = "Italy",           LU = "Luxembourg", NL = "Netherlands",
  PT = "Portugal",        SE = "Sweden",
  GR = "Greece"   # ISO 3166 code; customs data may also use EL.
)
EU10_2004 <- list(
  CY = "Cyprus", CZ = "Czechia", EE = "Estonia",   HU = "Hungary",
  LV = "Latvia", LT = "Lithuania", MT = "Malta",   PL = "Poland",
  SK = "Slovakia", SI = "Slovenia"
)
EU2_2007 <- list(BG = "Bulgaria", RO = "Romania")
EU1_2013 <- list(HR = "Croatia")
UK_only  <- list(GB = "United Kingdom")
EEA_EFTA <- list(IS = "Iceland", LI = "Liechtenstein", NO = "Norway")

# Aliases that may appear in trade data
ALIASES <- list(
  EL = "GR",  # Greece (EU)
  UK = "GB"   # United Kingdom (informal)
)

build_country_year <- function(group_dict, accession_year, group_label,
                                last_year = max(YEAR_RANGE)) {
  rbindlist(lapply(names(group_dict), function(iso) {
    yrs <- accession_year:last_year
    yrs <- yrs[yrs %in% YEAR_RANGE]
    if (length(yrs) == 0) return(NULL)
    data.table(iso2 = iso,
               country = group_dict[[iso]],
               year = yrs,
               is_ets = TRUE,
               accession_year = accession_year,
               country_group = group_label)
  }))
}

dt <- rbindlist(list(
  build_country_year(EU15,      ETS_START, "EU-15"),
  build_country_year(EU10_2004, ETS_START, "EU-10 (2004)"),
  build_country_year(EU2_2007,  2007L,     "EU-2 (2007)"),
  build_country_year(EU1_2013,  2013L,     "EU-1 (2013)"),
  build_country_year(UK_only,   ETS_START, "UK (in until 2020)",
                     last_year = UK_LAST_YEAR),
  build_country_year(EEA_EFTA,  2008L,     "EEA-EFTA")
))

# Emit alias rows pointing to the same status
alias_rows <- rbindlist(lapply(names(ALIASES), function(alias) {
  canonical <- ALIASES[[alias]]
  rows <- dt[iso2 == canonical]
  if (nrow(rows) == 0) return(NULL)
  rows[, iso2 := alias]
  rows[, country_group := paste0(country_group, " (alias of ", canonical, ")")]
  rows
}))
dt <- rbind(dt, alias_rows)

setorder(dt, iso2, year)
fwrite(dt, out_path)

cat("Country x year ETS status:\n")
cat("  total rows                 :", nrow(dt), "\n")
cat("  distinct ISO2 codes        :", uniqueN(dt$iso2), "\n")
cat("  year range                 :", min(dt$year), "-", max(dt$year), "\n\n")

cat("Group counts (distinct ISO2):\n")
print(unique(dt[, .(iso2, country_group)])[, .N, by = country_group])

cat("\nETS country count by year:\n")
print(dt[, .(n_ets_countries = uniqueN(iso2)), by = year][order(year)])

cat("\nUK schedule check:\n")
print(dt[iso2 == "GB", .(year, is_ets)])

cat("\nWrote", out_path, "\n")
