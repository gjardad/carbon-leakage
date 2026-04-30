###############################################################################
# phase6_build_customs_selected_sample.R
#
# PURPOSE:
#   One-time builder for the customs counterpart of the "selected sample"
#   convention used elsewhere in the project (b2b_selected_sample.RData,
#   annual_accounts_selected_sample_*.RData).
#
#   Reads raw NBB customs (import_export_ANO.dta), restricts to imports by
#   firms in the annual-accounts selected sample, and writes a compact
#   importer x CN8 x partner_iso2 x year panel. Also writes a smaller
#   importer x HS6 x source x year aggregate where source in {china, nonchina}
#   (the form Components 1, 2, 3 of the China-shock revisit consume).
#
#   This builder runs once and feeds:
#     phase6_revisit_c1_china_origin_theta.R
#     phase6_revisit_c2_local_projections.R
#     phase6_revisit_c3_importance_heterogeneity.R
#
#   It can be re-run on RMD (full annual-accounts sample) or local-1
#   (downsampled annual-accounts sample) without code changes -- the AA
#   sample frame controls the importer set.
#
# INPUT:
#   ${RAW_DATA}/NBB/import_export_ANO.dta
#     vat_ano, year, cncode (CN8), country (partner_iso2), cn_value, flow.
#   ${PROC_DATA}/annual_accounts_selected_sample_key_variables.RData
#     df_annual_accounts_selected_sample_key_variables: vat, year, nace5d, ...
#
# OUTPUT:
#   ${PROC_DATA}/customs_selected_sample.RData
#     df_customs_selected_sample: vat, year, cn8, hs6, partner_iso2, value
#       Long-form, one row per (importer, year, CN8, origin). Imports only.
#   ${PROC_DATA}/customs_selected_sample_china.RData
#     df_customs_selected_sample_china: vat, hs6, year, source, value
#       Source-collapsed (china vs nonchina) for the revisit pipeline.
#
# CAVEATS:
#   - Imports only (flow == "I"). Exports excluded -- if you need exports,
#     add a parallel builder rather than mixing.
#   - Self-imports (partner_iso2 == "BE") dropped defensively; should be empty
#     in the raw NBB extract anyway.
#   - China origin = {CN, HK}. HK included by BLP convention to capture
#     re-exported Chinese product. CN-only is recoverable downstream by
#     filtering partner_iso2 in the long-form file.
#   - VAT sample frame = anyone in the AA selected sample IN ANY YEAR.
#     Importers that appear in customs but not in AA are dropped. This
#     matches the rest of the project (Phase 3, network_exposure_regs_*).
#   - We DO NOT apply: NACE filters, capital-goods filters, regulated-
#     intensive filters, or core-input filters here. Those belong in the
#     downstream analysis script (and the regulated-intensive customs panel
#     already exists separately as customs_import_panel_regulated.RData).
###############################################################################

rm(list = ls())

library(data.table)
library(haven)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

CHINA_ISO <- c("CN", "HK")

# ---- 1. Sample frame: VATs in the AA selected sample (any year) ----
load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample_key_variables)
rm(df_annual_accounts_selected_sample_key_variables)

sample_vats <- unique(aa$vat)
cat("Annual-accounts selected sample: ",
    length(sample_vats), " unique VATs across ",
    length(unique(aa$year)), " years (",
    min(aa$year), "-", max(aa$year), ")\n", sep = "")

# ---- 2. Load raw customs, restrict to imports x sample VATs ----
customs_path <- file.path(RAW_DATA, "NBB", "import_export_ANO.dta")
stopifnot(file.exists(customs_path))
cat("Loading customs:", customs_path, "\n")
d <- as.data.table(read_dta(customs_path))
cat("Raw customs rows:", format(nrow(d), big.mark = ","), "\n")

setnames(d,
         c("vat_ano", "cncode", "country", "cn_value"),
         c("vat",     "cn8",    "partner_iso2", "value"))

# Imports only
d <- d[flow == "I"]
d[, flow := NULL]
cat("After flow == 'I' filter:", format(nrow(d), big.mark = ","), "\n")

# Restrict to selected-sample VATs (the canonical project sample frame)
d <- d[vat %in% sample_vats]
cat("After VAT-in-AA-selected-sample filter:",
    format(nrow(d), big.mark = ","), "\n")

# Drop self-imports if any
d <- d[partner_iso2 != "BE"]

# Standardize fields
d[, cn8  := sprintf("%08d", as.integer(cn8))]
d[, hs6  := substr(cn8, 1, 6)]
d[, year := as.integer(year)]
d[, value := as.numeric(value)]

# ---- 3. Long-form output ----
df_customs_selected_sample <- d[, .(vat, year, cn8, hs6, partner_iso2, value)]
setorder(df_customs_selected_sample, vat, year, cn8, partner_iso2)

cat("Long-form rows:",
    format(nrow(df_customs_selected_sample), big.mark = ","), "\n")
cat("Distinct importers in customs sample: ",
    length(unique(df_customs_selected_sample$vat)), "\n")
cat("Year range: ",
    min(df_customs_selected_sample$year), "-",
    max(df_customs_selected_sample$year), "\n", sep = "")

save(df_customs_selected_sample,
     file = file.path(PROC_DATA, "customs_selected_sample.RData"))
cat("Saved:", file.path(PROC_DATA, "customs_selected_sample.RData"), "\n")

# ---- 4. China-vs-non-China collapsed output ----
d[, source := ifelse(partner_iso2 %in% CHINA_ISO, "china", "nonchina")]
df_customs_selected_sample_china <- d[
  , .(value = sum(value, na.rm = TRUE)),
  by = .(vat, hs6, year, source)
]
setorder(df_customs_selected_sample_china, vat, year, hs6, source)

cat("China-collapsed rows:",
    format(nrow(df_customs_selected_sample_china), big.mark = ","), "\n")

save(df_customs_selected_sample_china,
     file = file.path(PROC_DATA, "customs_selected_sample_china.RData"))
cat("Saved:", file.path(PROC_DATA, "customs_selected_sample_china.RData"), "\n")

# ---- 5. Sanity-check summary printed to stdout ----
cat("\n--- Sanity checks ---\n")
cat("China-side import value share, by year:\n")
share_by_year <- df_customs_selected_sample_china[
  , .(china = sum(value[source == "china"], na.rm = TRUE),
      total = sum(value, na.rm = TRUE)),
  by = year
][, .(year, china_share = china / total)][order(year)]
print(share_by_year[year %in% c(2002, 2005, 2008, 2012, 2015, 2018, 2022)],
      digits = 4)

cat("\nDone.\n")
