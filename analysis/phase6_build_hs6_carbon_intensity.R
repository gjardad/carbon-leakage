# =============================================================================
# Build HS6-level carbon intensity for B4 IV.
#
# Approach: average emission intensity (kg CO2 / EUR revenue) across Belgian
# ETS firms in each NACE 4d, weighted by firm revenue. Then map HS6 -> NACE 4d
# via the existing cn8_to_nace4d.csv concordance (collapsed to HS6).
#
# This is a Belgian-data proxy for HS6-level carbon intensity. For a more
# granular cross-country measure (used in C3), see
# phase6_c3_within_EU_emission_intensity.R which expects external Eurostat
# inputs.
#
# Input:
#   ${PROC_DATA}/firm_year_belgian_euets.RData   (vat, year, emissions, revenue, ...)
#   data/concordances/cn8_to_nace4d.csv
#
# Output:
#   ${OUT_DATA}/hs6_carbon_intensity.csv    (hs6, carbon_intensity)
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({ library(data.table) })

PRE_LO <- 2010L; PRE_HI <- 2014L

# 1. NACE 4d emission intensity from Belgian ETS firms.
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets <- as.data.table(firm_year_belgian_euets)

# Restrict to firms with positive emissions and revenue in pre-shock window.
# Schema has nace5d, not nace4d; derive.
ets[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
e_pre <- ets[year %between% c(PRE_LO, PRE_HI) &
               !is.na(emissions) & emissions > 0 &
               !is.na(revenue)   & revenue > 0,
             .(vat, year, emissions, revenue, nace4d)]

# Sum-weighted (kg CO2 / EUR revenue) per NACE 4d.
ci_n4 <- e_pre[, .(emissions_total = sum(emissions),
                    revenue_total  = sum(revenue)),
                by = nace4d]
ci_n4[, carbon_intensity_nace4d := emissions_total / revenue_total]
cat("NACE 4d coverage:", nrow(ci_n4), "sectors\n")

# 2. CN8 -> NACE 4d concordance, collapsed to HS6.
bridge <- fread(file.path(REPO_DIR, "data", "concordances", "cn8_to_nace4d.csv"),
                colClasses = list(character = c("cn8", "nace4d")))
bridge[, nace4d := sprintf("%04d", as.integer(nace4d))]
bridge[, hs6 := substr(cn8, 1, 6)]

# For each HS6, take the most-frequent NACE 4d mapping (mode).
hs6_n4 <- bridge[!is.na(nace4d), .N, by = .(hs6, nace4d)]
setorder(hs6_n4, hs6, -N)
hs6_n4 <- hs6_n4[, .SD[1L], by = hs6][, .(hs6, nace4d)]

# 3. Merge.
hs6_ci <- merge(hs6_n4, ci_n4[, .(nace4d, carbon_intensity = carbon_intensity_nace4d)],
                 by = "nace4d", all.x = TRUE)
hs6_ci <- hs6_ci[!is.na(carbon_intensity), .(hs6, carbon_intensity)]

cat("HS6 codes with carbon intensity assigned:", nrow(hs6_ci), "\n")
print(quantile(hs6_ci$carbon_intensity, c(0.1, 0.5, 0.9, 0.99), na.rm = TRUE))

fwrite(hs6_ci, file.path(OUT_DATA, "hs6_carbon_intensity.csv"))
cat("Wrote", file.path(OUT_DATA, "hs6_carbon_intensity.csv"), "\n")
