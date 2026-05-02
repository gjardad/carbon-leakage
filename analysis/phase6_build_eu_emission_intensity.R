# =============================================================================
# Build (NACE 2d × EU country × year) emission intensity from Eurostat.
#
# Required for C3 (within-EU substitution toward less emission-intensive
# sources). Two Eurostat datasets:
#
#   - ENV_AC_AINAH_R2: Air emissions accounts by NACE 64 industry, EU member
#     states, 2008+ (kg CO2-equivalent per industry per year)
#   - NAMA_10_A64: Gross value added by NACE 64, EU member states, 2008+
#     (EUR per industry per year)
#
# Emission intensity = emissions / gross value added.
# Aggregate NACE 64 to NACE 2d by mapping each NACE 64 to its parent 2-digit.
#
# Both datasets are publicly available via the Eurostat REST API or the
# eurostat R package. This script downloads them and outputs a tidy CSV.
#
# Output:
#   ${OUT_DATA}/eu_emission_intensity_by_country_nace2d.csv
#     columns: year, country_iso2, nace2d, emissions_kgco2e, gva_eur,
#              emission_intensity (kg CO2e / EUR)
#
# This script needs internet access. Run on local-1 (or any machine with
# internet) before running phase6_c3_within_EU_emission_intensity.R.
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("eurostat", quietly = TRUE)) {
  install.packages("eurostat", repos = "https://cloud.r-project.org")
}
suppressPackageStartupMessages({
  library(data.table); library(eurostat)
})

# ---------------------------------------------------------------------------
# 1. Air emissions by NACE 64 (ENV_AC_AINAH_R2)
# ---------------------------------------------------------------------------
cat("Downloading ENV_AC_AINAH_R2 (air emissions by NACE 64)...\n")
emm <- as.data.table(get_eurostat("env_ac_ainah_r2",
                                   filters = list(airpol = "CO2",
                                                   unit   = "T")))  # tonnes
setnames(emm, c("geo", "TIME_PERIOD", "values"), c("country_iso2", "year", "emissions_t"))
emm[, year := as.integer(format(year, "%Y"))]
emm <- emm[!is.na(emissions_t) & nchar(country_iso2) == 2L]
emm[, emissions_kgco2e := emissions_t * 1000]
emm[, c("airpol", "unit", "emissions_t", "freq") := NULL]
setnames(emm, "nace_r2", "nace64")

# ---------------------------------------------------------------------------
# 2. Gross value added by NACE 64 (NAMA_10_A64), current prices, EUR
# ---------------------------------------------------------------------------
cat("Downloading NAMA_10_A64 (GVA by NACE 64)...\n")
gva <- as.data.table(get_eurostat("nama_10_a64",
                                   filters = list(na_item = "B1G",
                                                   unit    = "CP_MEUR")))  # current prices, M EUR
setnames(gva, c("geo", "TIME_PERIOD", "values"), c("country_iso2", "year", "gva_meur"))
gva[, year := as.integer(format(year, "%Y"))]
gva <- gva[!is.na(gva_meur) & nchar(country_iso2) == 2L]
gva[, gva_eur := gva_meur * 1e6]
gva[, c("na_item", "unit", "gva_meur", "freq") := NULL]
setnames(gva, "nace_r2", "nace64")

# ---------------------------------------------------------------------------
# 3. Merge, derive NACE 2d, compute intensity
# ---------------------------------------------------------------------------
df <- merge(emm, gva, by = c("country_iso2", "year", "nace64"))

# NACE 64 codes are e.g. "C24" = NACE 2d 24, "C20-C21" = aggregate range.
# Keep only the granular codes (single-2-digit), drop aggregates.
df[, nace2d := suppressWarnings(as.integer(substr(nace64, 2, 3)))]
df <- df[!is.na(nace2d)]

# Aggregate any sub-divisions to NACE 2d.
agg <- df[, .(emissions_kgco2e = sum(emissions_kgco2e),
              gva_eur          = sum(gva_eur)),
           by = .(country_iso2, year, nace2d)]
agg[, emission_intensity := emissions_kgco2e / gva_eur]

agg <- agg[is.finite(emission_intensity) & emission_intensity > 0]

cat(sprintf("Output: %d (country × year × NACE 2d) cells\n", nrow(agg)))
cat(sprintf("Years: %d-%d, %d countries, %d NACE 2d sectors\n",
            min(agg$year), max(agg$year),
            uniqueN(agg$country_iso2), uniqueN(agg$nace2d)))
print(quantile(agg$emission_intensity, c(0.1, 0.5, 0.9, 0.99)))

fwrite(agg, file.path(OUT_DATA, "eu_emission_intensity_by_country_nace2d.csv"))
cat("Wrote", file.path(OUT_DATA, "eu_emission_intensity_by_country_nace2d.csv"), "\n")
