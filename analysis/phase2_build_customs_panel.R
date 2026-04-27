# phase2_build_customs_panel.R
#
# Builds the regulated-intensive customs import panel for Phase 2 CMdG
# replication. R port of the original Stata draft (see git history).
#
# Per CMdG Section 3 + Supplemental Appendix p. 44:
#   1. Load raw customs imports (NBB .dta on RMD).
#   2. Restrict to imports.
#   3. Drop non-manufacturing buyer firms (NACE 2d not in 10-33).
#   4. Filter buyers by NACE 4d in regulated_intensive_nace.
#   5. Apply core-input filter: keep CN8 codes whose upstream NACE is in the
#      buyer's core-inputs set (>=10% IO share).
#   6. Drop capital goods (BEC 41, 521).
#   7. Balance the panel in (firm, CN8, partner) triplets ever observed;
#      zero-fill missing (firm, CN8, partner, year) cells.
#   8. Attach flags: is_regulated_product, is_non_ets_country, is_ets_firm.
#
# NOTE on the 3 contaminated VATs: the EUTL administrative artifact in their
# emissions/allocation series post-2020 affects ONLY emissions-based measures,
# not customs imports. We do NOT drop these firms in this build. (See git
# history for the dropped Stata version that incorrectly excluded them.)
#
# Inputs (RMD paths via paths.R):
#   * Raw customs: ${RAW_DATA}/customs/customs_import_*.dta  -- yearly OR
#                  ${RAW_DATA}/customs/customs_import_all.dta  -- single
#     Schema (CONFIRM ON FIRST RUN, may need column renames):
#       vat (string, firm ID)
#       cn8 (string, 8-digit CN code)
#       partner_iso2 (string, source country ISO2)
#       year (int)
#       value (double, EUR)
#       flow_type (1 = import / 2 = export) [optional]
#   * ${PROC_DATA}/firm_year_belgian_euets.RData -- 281 ETS firms x year
#   * ${PROC_DATA}/annual_accounts_selected_sample_key_variables.RData
#     OR equivalent .dta on RMD.
#   * data/concordances/* and data/io/* (synced from repo)
#
# Output:
#   * ${PROC_DATA}/customs_import_panel_regulated.RData
#     (also saved as .dta for compatibility if downstream Stata users want it)

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("haven", quietly = TRUE)) install.packages("haven", repos = "https://cloud.r-project.org")
library(data.table)
library(haven)

# Sample window matches CMdG.
FIRSTYEAR <- 2000L
LASTYEAR  <- 2019L

# ---------------------------------------------------------------------------
# 1. Load raw customs imports
# ---------------------------------------------------------------------------
cust_dir <- file.path(RAW_DATA, "customs")
single_path <- file.path(cust_dir, "customs_import_all.dta")
if (file.exists(single_path)) {
  cat("Loading single-file panel:", single_path, "\n")
  d <- as.data.table(read_dta(single_path))
} else {
  cat("Loading yearly customs files from:", cust_dir, "\n")
  yearly_files <- list.files(cust_dir,
                             pattern = "^customs_import_\\d{4}\\.dta$",
                             full.names = TRUE)
  stopifnot(length(yearly_files) > 0)
  d <- rbindlist(lapply(yearly_files, function(f) as.data.table(read_dta(f))),
                 fill = TRUE)
}
cat("Raw customs rows:", nrow(d), "\n")

# Optional flow-type filter (if column exists, keep imports only).
if ("flow_type" %in% names(d)) {
  d <- d[flow_type == 1L]
  d[, flow_type := NULL]
}

# Year window.
d <- d[year %between% c(FIRSTYEAR, LASTYEAR)]
cat("After flow + year filter:", nrow(d), "rows\n")

# Standardize CN8 to 8-character padded string.
d[, cn8 := sprintf("%08d", as.integer(cn8))]

# ---------------------------------------------------------------------------
# 2. Buyer NACE join (annual accounts)
# ---------------------------------------------------------------------------
aa_path_dta   <- file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.dta")
aa_path_rdata <- file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData")
if (file.exists(aa_path_dta)) {
  aa <- as.data.table(read_dta(aa_path_dta))
} else {
  load(aa_path_rdata)
  # Convention: object name in RData is df_annual_accounts or similar.
  # If different, adjust the next line accordingly.
  aa <- as.data.table(get(ls(pattern = "annual|accounts|key_var")[1]))
}
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa <- unique(aa[, .(vat, year, nace4d)])

d <- merge(d, aa, by = c("vat", "year"), all.x = TRUE)
d[, buyer_nace2d := substr(nace4d, 1, 2)]

# ---------------------------------------------------------------------------
# 3. Manufacturing filter (NACE C 10-33)
# ---------------------------------------------------------------------------
d <- d[suppressWarnings(as.integer(buyer_nace2d)) %between% c(10L, 33L)]
cat("After manufacturing filter:", nrow(d), "rows\n")

# ---------------------------------------------------------------------------
# 4. Regulated-intensive buyer NACE filter
# ---------------------------------------------------------------------------
ri <- fread(file.path(REPO_DIR, "data", "io", "regulated_intensive_nace.csv"))
ri[, nace2d := sprintf("%02d", as.integer(nace2d))]
d <- d[buyer_nace2d %in% ri$nace2d]
cat("After regulated-intensive buyer-NACE filter:", nrow(d), "rows\n")

# ---------------------------------------------------------------------------
# 5. CN8 -> upstream NACE 2d (bridge)
# ---------------------------------------------------------------------------
bridge <- fread(file.path(REPO_DIR, "data", "concordances", "cn8_to_nace4d.csv"),
                colClasses = list(character = c("cn8", "nace4d")))
bridge[, nace4d := sprintf("%04d", as.integer(nace4d))]
bridge <- unique(bridge[!is.na(nace4d), .(year, cn8, upstream_nace2d = substr(nace4d, 1, 2))])
d <- merge(d, bridge, by = c("year", "cn8"), all.x = TRUE)

# ---------------------------------------------------------------------------
# 6. Core-input filter (10% threshold)
# ---------------------------------------------------------------------------
core <- fread(file.path(REPO_DIR, "data", "io", "core_inputs_by_downstream.csv"))
core <- core[threshold == 0.10,
             .(buyer_nace2d = downstream_nace2d,
               upstream_nace2d = upstream_cpa_nace2d)]
core[, buyer_nace2d := sprintf("%02d", as.integer(buyer_nace2d))]
core[, upstream_nace2d := sprintf("%02d", as.integer(upstream_nace2d))]
core[, is_core := TRUE]
core <- unique(core)
d <- merge(d, core, by = c("buyer_nace2d", "upstream_nace2d"), all.x = TRUE)
d <- d[!is.na(is_core)]
d[, is_core := NULL]
cat("After core-input filter:", nrow(d), "rows\n")

# ---------------------------------------------------------------------------
# 7. Capital-goods filter (BEC 41, 521 dropped)
# ---------------------------------------------------------------------------
bec <- fread(file.path(REPO_DIR, "data", "concordances", "hs_to_bec.csv"),
             colClasses = list(character = "hs6"))
bec <- unique(bec[, .(hs6, is_capital)])
d[, hs6 := substr(cn8, 1, 6)]
d <- merge(d, bec, by = "hs6", all.x = TRUE)
d <- d[is_capital == FALSE | is.na(is_capital)]
d[, c("is_capital", "hs6") := NULL]
cat("After capital-goods filter:", nrow(d), "rows\n")

# ---------------------------------------------------------------------------
# 8. Regulated CN8 flag
# ---------------------------------------------------------------------------
reg <- fread(file.path(REPO_DIR, "data", "concordances", "regulated_products_cn8.csv"),
             colClasses = list(character = "cn8"))
reg <- unique(reg[, .(cn8, is_regulated_product = as.integer(is_regulated))])
d <- merge(d, reg, by = "cn8", all.x = TRUE)
d[is.na(is_regulated_product), is_regulated_product := 0L]

# ---------------------------------------------------------------------------
# 9. Country ETS-status flag
# ---------------------------------------------------------------------------
etsc <- fread(file.path(REPO_DIR, "data", "concordances", "country_ets_status.csv"))
etsc <- unique(etsc[, .(partner_iso2 = iso2, year, is_ets_country = as.integer(is_ets))])
d <- merge(d, etsc, by = c("partner_iso2", "year"), all.x = TRUE)
d[is.na(is_ets_country), is_ets_country := 0L]
d[, is_non_ets_country := 1L - is_ets_country]
d[, is_ets_country := NULL]

# ---------------------------------------------------------------------------
# 10. ETS firm flag
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_obj <- ls(pattern = "ets|euets|firm_year")[1]
ets <- as.data.table(get(ets_obj))
ets <- unique(ets[, .(vat, year)])
ets[, is_ets_firm := 1L]
d <- merge(d, ets, by = c("vat", "year"), all.x = TRUE)
d[is.na(is_ets_firm), is_ets_firm := 0L]

# Note: the 3 contaminated VAT hashes flagged for emissions/allocation
# anomalies in NACE 20/24 post-2020 are NOT dropped here. The contamination
# affects EUTL emissions data only, not customs imports. is_ets_firm remains
# correctly TRUE for these firms throughout, since they are still in EUTL.

# ---------------------------------------------------------------------------
# 11. Balance the panel (every firm x cn8 x partner triplet ever observed)
# ---------------------------------------------------------------------------
triplets <- unique(d[, .(vat, cn8, partner_iso2)])
years_dt <- data.table(year = FIRSTYEAR:LASTYEAR)
skel <- triplets[, .(year = years_dt$year), by = .(vat, cn8, partner_iso2)]

bal <- merge(skel, d,
             by = c("vat", "cn8", "partner_iso2", "year"),
             all.x = TRUE)
bal[is.na(value), value := 0]

# Propagate triplet-level attributes (cn8-level: is_regulated_product,
# upstream_nace2d, hs6 already dropped; firm-level: nace4d, buyer_nace2d).
# Take any non-NA value within the triplet; same triplet always shares cn8 and
# vat so triplet-level attributes are constant.
prop_cols <- c("nace4d", "buyer_nace2d", "is_regulated_product", "upstream_nace2d")
for (cl in prop_cols) {
  if (cl %in% names(bal)) {
    bal[, (cl) := {
      v <- get(cl)
      v_obs <- v[!is.na(v)][1]
      v[is.na(v)] <- v_obs
      v
    }, by = .(vat, cn8, partner_iso2)]
  }
}

# Time-varying: re-merge ETS country and ETS firm flags for zero-filled cells.
bal[, c("is_non_ets_country", "is_ets_firm") := NULL]
bal <- merge(bal, etsc, by = c("partner_iso2", "year"), all.x = TRUE)
bal[is.na(is_ets_country), is_ets_country := 0L]
bal[, is_non_ets_country := 1L - is_ets_country]
bal[, is_ets_country := NULL]
bal <- merge(bal, ets, by = c("vat", "year"), all.x = TRUE)
bal[is.na(is_ets_firm), is_ets_firm := 0L]

cat("After balancing + zero-fill:", nrow(bal), "rows\n")

# ---------------------------------------------------------------------------
# 12. Save
# ---------------------------------------------------------------------------
setorder(bal, vat, cn8, partner_iso2, year)
panel <- bal[, .(vat, cn8, partner_iso2, year, value,
                 nace4d, buyer_nace2d,
                 is_regulated_product, is_non_ets_country, is_ets_firm)]

out_rdata <- file.path(PROC_DATA, "customs_import_panel_regulated.RData")
out_dta   <- file.path(PROC_DATA, "customs_import_panel_regulated.dta")
save(panel, file = out_rdata)
write_dta(panel, out_dta)

cat("\n=== Build complete ===\n")
cat("Rows                        :", nrow(panel), "\n")
cat("Distinct firms              :", uniqueN(panel$vat), "\n")
cat("Distinct CN8 products       :", uniqueN(panel$cn8), "\n")
cat("Distinct partner countries  :", uniqueN(panel$partner_iso2), "\n")
cat("Years                       :", min(panel$year), "-", max(panel$year), "\n")
cat("Output (RData)              :", out_rdata, "\n")
cat("Output (dta)                :", out_dta, "\n")

cat("\n--- Sanity tabs ---\n")
cat("year x is_regulated_product:\n")
print(panel[, .N, by = .(year, is_regulated_product)][order(year, is_regulated_product)])
cat("\nbuyer_nace2d distribution:\n")
print(panel[, .N, by = buyer_nace2d][order(-N)])
