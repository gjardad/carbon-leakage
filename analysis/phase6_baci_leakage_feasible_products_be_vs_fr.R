###############################################################################
# phase6_baci_leakage_feasible_products_be_vs_fr.R
#
# PURPOSE
#   Compare the set of "intensive-margin-feasible" leakage products between
#   Belgium and France in the two treatment years (2005, 2017).
#
#   A regulated HS6 product is intensive-margin-feasible for an importer if it
#   is sourced from BOTH an EU-ETS country and a non-ETS country: only then can
#   a buyer reallocate value from a regulated (EU) source to an unregulated
#   (non-EU) one without forming a new relationship. Two bloc-sourcing
#   thresholds:
#     (>0)   : positive import value from each bloc.
#     (>1%)  : each bloc supplies > 1% of the product's total imports.
#
# DATA (all public; runs on local-1, no NBB confidential data)
#   - ${RAW_DATA}/BACI_HS02_V202601/  (bilateral trade, HS6, HS2002 nomenclature)
#   - data/concordances/regulated_products_cn8.csv  (HS6 -> is_regulated)
#   - data/concordances/country_ets_status.csv      (iso2 x year -> is_ets)
#
# OUTPUT
#   ${OUTPUT_TAB}/phase6_baci_leakage_feasible_be_vs_fr_summary.csv
#   ${OUTPUT_TAB}/phase6_baci_leakage_feasible_be_vs_fr_products.csv
###############################################################################

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)

BACI_DIR  <- file.path(RAW_DATA, "BACI_HS02_V202601")
YEARS     <- c(2005L, 2017L)
IMPORTERS <- c(BE = 56L, FR = 251L)   # BACI numeric codes

# ---- Concordances ----
cc  <- fread(file.path(BACI_DIR, "country_codes_V202601.csv"))
ets <- fread(file.path(REPO_DIR, "data", "concordances", "country_ets_status.csv"))
reg <- fread(file.path(REPO_DIR, "data", "concordances", "regulated_products_cn8.csv"),
             colClasses = list(character = "hs6"))
reg[, is_regulated := as.logical(is_regulated)]
reg_hs6 <- reg[, .(is_regulated = any(is_regulated, na.rm = TRUE)), by = hs6]

res <- list()
for (yr in YEARS) {
  d <- fread(file.path(BACI_DIR, sprintf("BACI_HS02_Y%d_V202601.csv", yr)))
  d <- d[j %in% IMPORTERS]
  d[, k := sprintf("%06d", as.integer(k))]
  d[, importer := names(IMPORTERS)[match(j, IMPORTERS)]]

  # exporter ETS status in year yr (non-listed exporters = non-ETS)
  d <- merge(d, cc[, .(i = country_code, exp_iso2 = country_iso2)], by = "i", all.x = TRUE)
  ets_yr <- ets[year == yr, .(exp_iso2 = iso2, is_ets = as.logical(is_ets))]
  d <- merge(d, ets_yr, by = "exp_iso2", all.x = TRUE)
  d[is.na(is_ets), is_ets := FALSE]

  # coverage diagnostic: share of this importer-year's import value whose HS6
  # is present in the regulated concordance at all (gauges HS-vintage match)
  d <- merge(d, reg_hs6, by.x = "k", by.y = "hs6", all.x = TRUE)
  cov <- d[, .(matched_valshare = sum(v[!is.na(is_regulated)]) / sum(v)), by = importer]
  cat(sprintf("\n[%d] HS6 concordance value-coverage:  BE=%.3f  FR=%.3f\n", yr,
              cov[importer=="BE", matched_valshare], cov[importer=="FR", matched_valshare]))
  d[is.na(is_regulated), is_regulated := FALSE]

  # regulated products only; aggregate to importer x HS6
  prod <- d[is_regulated == TRUE,
            .(v_tot = sum(v),
              v_ets = sum(v[is_ets]),
              v_non = sum(v[!is_ets])),
            by = .(importer, k)]
  prod <- prod[v_tot > 0]
  prod[, `:=`(sh_ets = v_ets / v_tot, sh_non = v_non / v_tot)]
  prod[, feasible_any   := v_ets > 0 & v_non > 0]
  prod[, feasible_1pct  := sh_ets > 0.01 & sh_non > 0.01]
  prod[, feasible_5pct  := sh_ets > 0.05 & sh_non > 0.05]
  prod[, feasible_10pct := sh_ets > 0.10 & sh_non > 0.10]
  prod[, year := yr]
  res[[as.character(yr)]] <- prod
}
allprod <- rbindlist(res)

# ---- Summary: counts and value shares ----
summ <- allprod[, .(
    n_regulated      = .N,
    n_feas_any       = sum(feasible_any),
    n_feas_1pct      = sum(feasible_1pct),
    n_feas_5pct      = sum(feasible_5pct),
    n_feas_10pct     = sum(feasible_10pct),
    valsh_feas_any   = sum(v_tot[feasible_any]) / sum(v_tot),
    valsh_feas_1pct  = sum(v_tot[feasible_1pct]) / sum(v_tot),
    valsh_feas_5pct  = sum(v_tot[feasible_5pct]) / sum(v_tot),
    valsh_feas_10pct = sum(v_tot[feasible_10pct]) / sum(v_tot)
  ), by = .(year, importer)][order(year, importer)]

cat("\n===== Intensive-margin-feasible regulated products: BE vs FR =====\n")
print(summ, digits = 3)

# ---- BE vs FR set overlap ----
cat("\n===== BE vs FR feasible-set overlap =====\n")
for (yr in YEARS) for (thr in c("feasible_any", "feasible_1pct", "feasible_5pct", "feasible_10pct")) {
  be <- allprod[importer=="BE" & year==yr & get(thr), unique(k)]
  fr <- allprod[importer=="FR" & year==yr & get(thr), unique(k)]
  inter <- length(intersect(be, fr)); uni <- length(union(be, fr))
  cat(sprintf("  %d  %-13s  BE=%4d  FR=%4d  common=%4d  Jaccard=%.2f  FR-only=%4d  BE-only=%4d\n",
              yr, thr, length(be), length(fr), inter, ifelse(uni>0, inter/uni, NA),
              length(setdiff(fr, be)), length(setdiff(be, fr))))
}

fwrite(summ,    file.path(OUTPUT_TAB, "phase6_baci_leakage_feasible_be_vs_fr_summary.csv"))
fwrite(allprod, file.path(OUTPUT_TAB, "phase6_baci_leakage_feasible_be_vs_fr_products.csv"))
cat(sprintf("\nWrote: %s\n", file.path(OUTPUT_TAB, "phase6_baci_leakage_feasible_be_vs_fr_summary.csv")))
