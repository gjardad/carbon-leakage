# =============================================================================
# B3 (paper §5.2.4) — Non-EU supplier price response
#
# Tests whether non-EU exporters of regulated products adjust their FOB
# unit-value prices in response to the EU ETS:
#
#   log p^{unit}_{p,i,t} = β · regulated_p × 1[t ≥ 2015] + α_{p,i} + δ_{i,t} + ε
#
# where p^{unit} = value / quantity, computed at the HS6 × source-country ×
# year level (collapsed across importers). Sample restricted to non-ETS source
# countries (per CMdG identifying logic).
#
# Identification: HS6 × source-country FE absorbs persistent quality
# differences; source-country × year FE absorbs global price trends and
# country-specific currency / cost dynamics. Identifying variation: regulated-
# vs-unregulated HS6 within the same (source country, year), pre vs. post 2015.
#
# Prerequisites: customs_import_panel_extended.RData (preserves quantity).
# Will fail informatively if quantity is missing.
#
# Outputs:
#   ${OUT_TAB}/phase6_b3_nonEU_price_response.csv
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest)
})

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)

ext_path <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
if (!file.exists(ext_path)) {
  stop("customs_import_panel_extended.RData not found. Run phase6_build_customs_panel_extended.R first.")
}
load(ext_path)
panel <- as.data.table(panel)

if (!"quantity" %in% names(panel)) {
  stop("quantity column missing from extended panel. The build script did not preserve it.")
}

cat(sprintf("Loaded %d rows, %d-%d, %.1f%% have positive quantity\n",
            nrow(panel), min(panel$year), max(panel$year),
            100 * mean(!is.na(panel$quantity) & panel$quantity > 0)))

# Restrict to non-ETS source countries.
d <- panel[is_non_ets_country == 1L]

# Need positive value AND positive quantity to compute unit value.
d <- d[!is.na(value) & value > 0 & !is.na(quantity) & quantity > 0]
d[, hs6 := substr(cn8, 1, 6)]

# Aggregate to (HS6 × source country × year): sum value and quantity, then ratio.
agg <- d[, .(value = sum(value), quantity = sum(quantity)),
         by = .(hs6, partner_iso2, year, is_regulated_product)]
agg[, log_unit_value := log(value / quantity)]
agg[, post := as.integer(year >= 2015L)]

cat(sprintf("Aggregated cell-years for B3: %d\n", nrow(agg)))

# ---------------------------------------------------------------------------
# B3 main spec: HS6 × country FE + country × year FE
# ---------------------------------------------------------------------------
m_b3 <- tryCatch(
  feols(log_unit_value ~ is_regulated_product:post |
                          hs6^partner_iso2 + partner_iso2^year,
        data = agg, cluster = c("hs6", "partner_iso2"), notes = FALSE),
  error = function(e) { cat("ERROR:", conditionMessage(e), "\n"); NULL })

if (!is.null(m_b3)) {
  ct <- as.data.table(coeftable(m_b3), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  fwrite(ct, file.path(OUT_TAB, "phase6_b3_nonEU_price_response.csv"))
  cat("B3 main spec:\n"); print(ct[, .(est, se, pval)])
}

# Robustness: triple-difference with HS6 × country × year FE absorbed and
# regulated × post identifying off year-by-year movements. Effectively the
# same as adding HS6 × year FE on top.
m_b3_rob <- tryCatch(
  feols(log_unit_value ~ is_regulated_product:post |
                          hs6^partner_iso2 + partner_iso2^year + hs6^year,
        data = agg, cluster = c("hs6", "partner_iso2"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_b3_rob)) {
  ct2 <- as.data.table(coeftable(m_b3_rob), keep.rownames = "term")
  setnames(ct2, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  cat("\nB3 with HS6×year FE (robustness):\n")
  print(ct2[, .(est, se, pval)])
}

# Year-by-year coefficients for an event-study version.
agg[, year_f := factor(year, levels = sort(unique(agg$year)))]
ref_year <- min(agg$year[agg$year >= 2014L])  # closest pre-cutoff year available
m_b3_es <- tryCatch(
  feols(log_unit_value ~ i(year_f, is_regulated_product, ref = as.character(ref_year)) |
                          hs6^partner_iso2 + partner_iso2^year,
        data = agg, cluster = c("hs6", "partner_iso2"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_b3_es)) {
  ct3 <- as.data.table(coeftable(m_b3_es), keep.rownames = "term")
  ct3[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  setnames(ct3, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  ct3 <- ct3[!is.na(year), .(year, est, se, tval, pval)]
  fwrite(ct3, file.path(OUT_TAB, "phase6_b3_nonEU_price_eventstudy.csv"))
  cat("\nB3 event study coefficients written to phase6_b3_nonEU_price_eventstudy.csv\n")
}
