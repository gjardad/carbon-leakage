# =============================================================================
# Build extended customs panel (2000-2022) preserving quantity, for paper §5.2.
#
# Modifies phase2_build_customs_panel.R in two ways:
#   (1) preserve quantity (kg) alongside value (EUR)
#   (2) extend LASTYEAR to 2022 (the existing build hardcoded 2019 to match CMdG;
#       buyer-supplier analyses in §5.2.2-§5.2.5 want the Phase IV window)
#
# Both EU and non-EU source country rows are kept (with is_non_ets_country as
# a flag); the CMdG-replication sample restriction is applied at regression
# time, not at the build stage. This is unchanged from phase2_build_customs_panel.R.
#
# All other filters (manufacturing buyer, regulated-intensive NACE, core-input,
# capital-goods drop, etc.) and FE/concordance joins are identical to phase2.
#
# Output:
#   ${PROC_DATA}/customs_import_panel_extended.RData (does NOT overwrite
#   the existing CMdG-replication panel)
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("haven", quietly = TRUE)) install.packages("haven", repos = "https://cloud.r-project.org")
library(data.table)
library(haven)

# Extended sample window: 2000-2022 (vs. 2019 in phase2_build_customs_panel.R).
FIRSTYEAR <- 2000L
LASTYEAR  <- 2022L

# ---------------------------------------------------------------------------
# 1. Load raw customs imports (preserve cn_weight)
# ---------------------------------------------------------------------------
customs_path <- file.path(RAW_DATA, "NBB", "import_export_ANO.dta")
cat("Loading:", customs_path, "\n")
d <- as.data.table(read_dta(customs_path))
cat("Raw customs rows:", nrow(d), "\n")

# Diagnostic: check raw schema for quantity column.
cat("Raw column names: ", paste(names(d), collapse = ", "), "\n")
qty_candidates <- intersect(c("cn_weight", "cn_quantity", "weight", "quantity"),
                            names(d))
if (length(qty_candidates) == 0L) {
  stop("ERROR: no quantity column found in raw customs file. Schema may have changed.")
}
qty_col <- qty_candidates[1]
cat("Using quantity column:", qty_col, "\n")

# Canonical column names: include quantity now.
setnames(d,
         c("vat_ano", "cncode", "country", "cn_value", qty_col),
         c("vat",     "cn8",    "partner_iso2", "value", "quantity"))

# Filter to imports only.
d <- d[flow == "I"]
d[, flow := NULL]

# Year window.
d <- d[year %between% c(FIRSTYEAR, LASTYEAR)]
cat("After flow + year filter:", nrow(d), "rows\n")

# Standardize CN8 padding and year type.
d[, cn8 := sprintf("%08d", as.integer(cn8))]
d[, year := as.integer(year)]

# Diagnostic: quantity-non-NA fraction in the raw data.
cat(sprintf("Non-NA quantity fraction: %.1f%%\n",
            100 * mean(!is.na(d$quantity) & d$quantity > 0)))

# ---------------------------------------------------------------------------
# 2-10. Identical filters and joins as phase2_build_customs_panel.R
# ---------------------------------------------------------------------------
# Buyer NACE join.
aa_path <- file.path(RAW_DATA, "NBB", "Annual_Accounts_MASTER_ANO.dta")
aa <- as.data.table(read_dta(aa_path,
                             col_select = c("vat_ano", "year", "nace5d")))
setnames(aa, "vat_ano", "vat")
aa[, year := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa <- unique(aa[, .(vat, year, nace4d)])

d <- merge(d, aa, by = c("vat", "year"), all.x = TRUE)
d[, buyer_nace2d := substr(nace4d, 1, 2)]

# Manufacturing filter.
d <- d[suppressWarnings(as.integer(buyer_nace2d)) %between% c(10L, 33L)]

# Regulated-intensive buyer NACE filter.
ri <- fread(file.path(REPO_DIR, "data", "io", "regulated_intensive_nace.csv"))
ri[, nace2d := sprintf("%02d", as.integer(nace2d))]
d <- d[buyer_nace2d %in% ri$nace2d]

# CN8 -> upstream NACE 2d.
bridge <- fread(file.path(REPO_DIR, "data", "concordances", "cn8_to_nace4d.csv"),
                colClasses = list(character = c("cn8", "nace4d")))
bridge[, nace4d := sprintf("%04d", as.integer(nace4d))]
bridge <- unique(bridge[!is.na(nace4d), .(year, cn8, upstream_nace2d = substr(nace4d, 1, 2))])
d <- merge(d, bridge, by = c("year", "cn8"), all.x = TRUE)

# Core-input filter (10%).
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

# Capital-goods filter.
bec <- fread(file.path(REPO_DIR, "data", "concordances", "hs_to_bec.csv"),
             colClasses = list(character = "hs6"))
bec <- unique(bec[, .(hs6, is_capital)])
d[, hs6 := substr(cn8, 1, 6)]
d <- merge(d, bec, by = "hs6", all.x = TRUE)
d <- d[is_capital == FALSE | is.na(is_capital)]
d[, c("is_capital", "hs6") := NULL]
cat("After capital-goods filter:", nrow(d), "rows\n")

# Regulated CN8 flag.
reg <- fread(file.path(REPO_DIR, "data", "concordances", "regulated_products_cn8.csv"),
             colClasses = list(character = "cn8"))
reg <- unique(reg[, .(cn8, is_regulated_product = as.integer(is_regulated))])
d <- merge(d, reg, by = "cn8", all.x = TRUE)
d[is.na(is_regulated_product), is_regulated_product := 0L]

# Country ETS-status flag.
etsc <- fread(file.path(REPO_DIR, "data", "concordances", "country_ets_status.csv"))
etsc <- unique(etsc[, .(partner_iso2 = iso2, year, is_ets_country = as.integer(is_ets))])
d <- merge(d, etsc, by = c("partner_iso2", "year"), all.x = TRUE)
d[is.na(is_ets_country), is_ets_country := 0L]
d[, is_non_ets_country := 1L - is_ets_country]
d[, is_ets_country := NULL]

# ETS firm flag.
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets <- as.data.table(firm_year_belgian_euets)
ets <- unique(ets[!is.na(vat), .(vat, year)])
ets[, year := as.integer(year)]
ets[, is_ets_firm := 1L]
d <- merge(d, ets, by = c("vat", "year"), all.x = TRUE)
d[is.na(is_ets_firm), is_ets_firm := 0L]

# ---------------------------------------------------------------------------
# 11. Balance the panel; zero-fill missing cells (value=0, quantity=NA)
# ---------------------------------------------------------------------------
# Quantity is NA for zero-filled cells (no transaction took place; quantity
# is undefined, not zero). Value is set to 0 to match the CMdG convention.

triplets <- unique(d[, .(vat, cn8, partner_iso2)])
years_dt <- data.table(year = FIRSTYEAR:LASTYEAR)
skel <- triplets[, .(year = years_dt$year), by = .(vat, cn8, partner_iso2)]

bal <- merge(skel, d,
             by = c("vat", "cn8", "partner_iso2", "year"),
             all.x = TRUE)
bal[is.na(value), value := 0]
# Leave quantity as NA in zero-fill rows.

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

bal[, c("is_non_ets_country", "is_ets_firm") := NULL]
bal <- merge(bal, etsc, by = c("partner_iso2", "year"), all.x = TRUE)
bal[is.na(is_ets_country), is_ets_country := 0L]
bal[, is_non_ets_country := 1L - is_ets_country]
bal[, is_ets_country := NULL]
bal <- merge(bal, ets, by = c("vat", "year"), all.x = TRUE)
bal[is.na(is_ets_firm), is_ets_firm := 0L]

cat("After balancing + zero-fill:", nrow(bal), "rows\n")

# ---------------------------------------------------------------------------
# 12. Save (extended panel, preserves quantity)
# ---------------------------------------------------------------------------
setorder(bal, vat, cn8, partner_iso2, year)
panel <- bal[, .(vat, cn8, partner_iso2, year, value, quantity,
                 nace4d, buyer_nace2d,
                 is_regulated_product, is_non_ets_country, is_ets_firm)]

out_rdata <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
save(panel, file = out_rdata)

cat("\n=== Build complete ===\n")
cat("Rows                       :", nrow(panel), "\n")
cat("Distinct firms             :", uniqueN(panel$vat), "\n")
cat("Distinct CN8 products      :", uniqueN(panel$cn8), "\n")
cat("Distinct partner countries :", uniqueN(panel$partner_iso2), "\n")
cat("Years                      :", min(panel$year), "-", max(panel$year), "\n")
cat("Output                     :", out_rdata, "\n")

cat("\n--- Quantity coverage diagnostics ---\n")
nonzero <- panel[value > 0]
cat(sprintf("Non-zero-value rows: %d\n", nrow(nonzero)))
cat(sprintf("  with non-NA positive quantity: %d (%.1f%%)\n",
            sum(!is.na(nonzero$quantity) & nonzero$quantity > 0),
            100 * mean(!is.na(nonzero$quantity) & nonzero$quantity > 0)))
cat("\nBy regulated subset (non-zero-value rows):\n")
print(nonzero[, .(n = .N,
                   pct_with_qty = 100 * mean(!is.na(quantity) & quantity > 0)),
              by = is_regulated_product])
