# =============================================================================
# C3 (paper §5.2.8) — Within-EU substitution toward less emission-intensive sources
#
# Tests whether Belgian importers shift their EU sourcing toward less-carbon-
# intensive EU source countries within regulated products. The substitution
# margin is across-country WITHIN the EU bloc, controlling for the across-bloc
# margin in B1.
#
# Specification: importer × HS6 × EU-source-country × year panel.
#
#   share_{f,p,c,t} = β · low_intensity_{p,c} × Post + α_{f,p} + δ_{c,t} + ε
#
# Where:
#   share_{f,p,c,t} = importer's share of EU-bloc spending in HS6 p going to
#                    source country c (denominator is EU-bloc-only).
#   low_intensity_{p,c} = 1 if country c's emission intensity for the NACE
#                        2-digit corresponding to p is in the bottom tercile
#                        across EU source countries with positive trade.
#                        Time-invariant (computed on pre-shock period).
#
# Continuous-treatment alternative: log emission intensity instead of the
# tercile dummy. Plus an event-study version with low_intensity × year_f.
#
# Inputs:
#   ${PROC_DATA}/customs_import_panel_extended.RData (or fallback to 2019 panel)
#   ${OUT_DATA}/eu_emission_intensity_by_country_nace2d.csv
#       (built by phase6_build_eu_emission_intensity.R)
#   data/concordances/cn8_to_nace4d.csv
#
# Outputs:
#   ${OUT_TAB}/phase6_c3_within_eu_intensity.csv
#   ${OUT_TAB}/phase6_c3_within_eu_intensity_eventstudy.csv
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest)
})

NSHARE_LO <- 2010L; NSHARE_HI <- 2014L
ANCHOR <- 2014L; H_LO <- -9L; H_HI <- +7L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Inputs
# ---------------------------------------------------------------------------
ei_path <- file.path(OUT_DATA, "eu_emission_intensity_by_country_nace2d.csv")
if (!file.exists(ei_path)) {
  cat("MISSING:", ei_path, "\n")
  cat("Run phase6_build_eu_emission_intensity.R first (needs internet).\n")
  quit(status = 1)
}

ext_path <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
if (file.exists(ext_path)) {
  load(ext_path); cat("Using extended customs panel.\n")
} else {
  cat("WARNING: extended panel not found; using 2000-2019 panel.\n")
  load(file.path(PROC_DATA, "customs_import_panel_regulated.RData"))
}
panel <- as.data.table(panel)
ei <- fread(ei_path)

# ---------------------------------------------------------------------------
# 2. Restrict to regulated products imported from EU sources
# ---------------------------------------------------------------------------
reg_eu <- panel[is_regulated_product == 1L &
                 is_non_ets_country == 0L &       # EU sources only
                 !is.na(value) & value > 0]
reg_eu[, hs6 := substr(cn8, 1, 6)]

# Map HS6 to NACE 2d via the existing CN8 -> NACE 4d concordance.
bridge <- fread(file.path(REPO_DIR, "data", "concordances", "cn8_to_nace4d.csv"),
                colClasses = list(character = c("cn8", "nace4d")))
bridge[, nace4d := sprintf("%04d", as.integer(nace4d))]
bridge[, hs6 := substr(cn8, 1, 6)]
bridge[, nace2d := suppressWarnings(as.integer(substr(nace4d, 1, 2)))]
hs6_n2 <- unique(bridge[!is.na(nace2d), .N, by = .(hs6, nace2d)])
setorder(hs6_n2, hs6, -N)
hs6_n2 <- hs6_n2[, .SD[1L], by = hs6][, .(hs6, nace2d)]

reg_eu <- merge(reg_eu, hs6_n2, by = "hs6")

# ---------------------------------------------------------------------------
# 3. Merge in country × NACE 2d emission intensity (pre-shock average)
# ---------------------------------------------------------------------------
ei_pre <- ei[year %between% c(NSHARE_LO, NSHARE_HI),
              .(emission_intensity_pre = mean(emission_intensity, na.rm = TRUE)),
              by = .(country_iso2, nace2d)]
setnames(ei_pre, "country_iso2", "partner_iso2")

reg_eu <- merge(reg_eu, ei_pre, by = c("partner_iso2", "nace2d"), all.x = TRUE)

# Country-NACE 2d cells without Eurostat coverage are dropped (small EU
# countries may have missing sectoral data).
reg_eu_have_ei <- reg_eu[!is.na(emission_intensity_pre)]
cat(sprintf("Imports rows with EI: %d / %d\n", nrow(reg_eu_have_ei), nrow(reg_eu)))

# ---------------------------------------------------------------------------
# 4. Within-EU shares per (importer, HS6, country, year)
# ---------------------------------------------------------------------------
agg <- reg_eu_have_ei[, .(value = sum(value)),
                       by = .(vat, hs6, partner_iso2, year, nace2d, emission_intensity_pre)]
totals <- agg[, .(total_eu = sum(value)),
              by = .(vat, hs6, year)]
agg <- merge(agg, totals, by = c("vat", "hs6", "year"))
agg[, share_eu_country := value / total_eu]

# ---------------------------------------------------------------------------
# 5. Low-intensity tercile (time-invariant, computed within HS6 across EU
#    countries on the pre-shock window).
# ---------------------------------------------------------------------------
hs6_terciles <- agg[year %between% c(NSHARE_LO, NSHARE_HI),
                     .(ei = mean(emission_intensity_pre, na.rm = TRUE)),
                     by = .(hs6, partner_iso2)]
hs6_terciles[, ei_tercile := cut(ei, breaks = quantile(ei, c(0, 1/3, 2/3, 1), na.rm = TRUE),
                                  labels = c("low", "mid", "high"),
                                  include.lowest = TRUE),
              by = hs6]
hs6_terciles[, low_intensity := as.integer(ei_tercile == "low")]

agg <- merge(agg,
              hs6_terciles[, .(hs6, partner_iso2, low_intensity, ei_pre = ei)],
              by = c("hs6", "partner_iso2"))
agg[, post := as.integer(year >= 2015L)]

cat(sprintf("Cell-years for C3: %d\n", nrow(agg)))

# ---------------------------------------------------------------------------
# 6. C3 main spec: low_intensity × Post
# ---------------------------------------------------------------------------
m_c3 <- tryCatch(
  feols(share_eu_country ~ low_intensity:post |
                            vat^hs6^partner_iso2 + partner_iso2^year,
        data = agg, cluster = c("vat", "partner_iso2"), notes = FALSE),
  error = function(e) { cat("ERROR:", conditionMessage(e), "\n"); NULL })
if (!is.null(m_c3)) {
  ct <- as.data.table(coeftable(m_c3), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  fwrite(ct, file.path(OUT_TAB, "phase6_c3_within_eu_intensity.csv"))
  cat("C3 main spec:\n"); print(ct[, .(est, se, pval)])
}

# Continuous: log emission intensity.
agg[, log_ei := log(ei_pre)]
m_c3c <- tryCatch(
  feols(share_eu_country ~ log_ei:post |
                            vat^hs6^partner_iso2 + partner_iso2^year,
        data = agg, cluster = c("vat", "partner_iso2"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_c3c)) {
  ct2 <- as.data.table(coeftable(m_c3c), keep.rownames = "term")
  setnames(ct2, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  cat("C3 continuous spec (log emission intensity):\n"); print(ct2[, .(est, se, pval)])
}

# Event study with low_intensity × year_f.
H_HI_eff <- min(H_HI, max(agg$year) - ANCHOR)
agg[, year_f := factor(year, levels = (ANCHOR + H_LO):(ANCHOR + H_HI_eff))]
m_c3_es <- tryCatch(
  feols(share_eu_country ~ i(year_f, low_intensity, ref = as.character(ANCHOR - 1L)) |
                            vat^hs6^partner_iso2 + partner_iso2^year,
        data = agg, cluster = c("vat", "partner_iso2"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_c3_es)) {
  ct3 <- as.data.table(coeftable(m_c3_es), keep.rownames = "term")
  ct3[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  ct3[, h := year - ANCHOR]
  setnames(ct3, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  fwrite(ct3[!is.na(h), .(h, est, se, tval, pval)],
         file.path(OUT_TAB, "phase6_c3_within_eu_intensity_eventstudy.csv"))
}
