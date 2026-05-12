# =============================================================================
# Trend-corrected CdGM Table 1 (paper §5.2.1, addressing the same concern that
# motivated phase6_b1_corrected on the buyer-supplier specification).
#
# The original phase2_cdgm_table1.R reports CdGM's Phase-φ binary specification
# without a continuous-time trend control. On the buyer-supplier B1 spec we
# found that adding a `pair_exposure_EU × year_centered` continuous trend
# control flipped the headline coefficient by an order of magnitude and changed
# the sign on Belgium. The natural follow-up question is: does the CdGM
# specification ALSO have a hidden linear trend that the Phase-φ binaries
# don't absorb?
#
# Spec extension. CdGM's original equation:
#   y_{f,p,i,t} = β_1 · 1[reg]_p × 1[t ∈ Phase 1]
#               + β_2 · 1[reg]_p × 1[t ∈ Phase 2]
#               + β_3 · 1[reg]_p × 1[t ∈ Phase 3]
#               + α_{f,p,i} + δ_{i,t} + δ_{s,t} + ε
#
# We add a single continuous-trend term:
#   ... + τ · 1[reg]_p × year_centered_t
#
# year_centered_t = t - 2014. The Phase-φ coefficients now identify level
# shifts (over each phase window) net of any linear regulated-vs-unregulated
# trend. τ tells us how fast regulated and unregulated products were
# diverging on the y outcome before and outside the Phase boundaries.
#
# Same panel, same six FE columns, same two-way clustering as the original
# phase2_cdgm_table1.R. Same outcomes (share + probability).
#
# Sample window: 2000-2019 to match CdGM exactly. The extended panel through
# 2022 is NOT used here — that extension is for the buyer-supplier spec
# (phase6_b1_corrected) where comparability with CdGM France isn't a goal.
#
# Outputs:
#   ${OUT_TAB}/phase6_cdgm_corrected_A.csv  — share, 6 columns × (3 phases + 1 trend)
#   ${OUT_TAB}/phase6_cdgm_corrected_B.csv  — prob,  6 columns × (3 phases + 1 trend)
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

# ---------------------------------------------------------------------------
# 1. Load customs panel — same as phase2_cdgm_table1.R
# ---------------------------------------------------------------------------
USE_MOCK <- !file.exists(file.path(PROC_DATA, "customs_import_panel_regulated.dta"))
if (USE_MOCK) {
  cat("USING MOCK CUSTOMS PANEL.\n")
  load(file.path(PROC_DATA, "mock_customs_import_panel_regulated.RData"))
  d <- as.data.table(panel)
} else {
  cat("USING REAL CUSTOMS PANEL.\n")
  if (!requireNamespace("haven", quietly = TRUE))
    install.packages("haven", repos = "https://cloud.r-project.org")
  d <- as.data.table(haven::read_dta(
    file.path(PROC_DATA, "customs_import_panel_regulated.dta")))
}
cat("Panel rows (full):", nrow(d), "\n")

# CdGM-EXACT: restrict regression sample to non-ETS source countries.
d <- d[is_non_ets_country == 1L]
cat("Panel rows (non-ETS only):", nrow(d), "\n")

# Sample window: 2000-2019 to match CdGM exactly.
d <- d[year %between% c(2000L, 2019L)]

# Outcomes.
d[, total_value_ft := sum(value), by = .(vat, year)]
d[, share := ifelse(total_value_ft > 0, value / total_value_ft, 0)]
d[, prob_active := as.integer(value > 0)]

# Phase indicators.
d[, phase_p1 := as.integer(year %between% c(2005L, 2008L))]
d[, phase_p2 := as.integer(year %between% c(2009L, 2012L))]
d[, phase_p3 := as.integer(year %between% c(2013L, 2019L))]
d[, treat := is_regulated_product]
d[, treat_p1 := treat * phase_p1]
d[, treat_p2 := treat * phase_p2]
d[, treat_p3 := treat * phase_p3]

# NEW: continuous trend interaction.
d[, year_centered := year - 2014L]
d[, treat_yearc := treat * year_centered]

# IDs for clustering and FE.
d[, prod_country     := paste(cn8, partner_iso2, sep = "_")]
d[, firm_prod_country := paste(vat, cn8, partner_iso2, sep = "_")]
d[, country_year     := paste(partner_iso2, year, sep = "_")]
d[, sector_year      := paste(buyer_nace2d, year, sep = "_")]
d[, year_etsfirm     := paste(year, is_ets_firm, sep = "_")]

# Helper: extract trend AND phase coefficients with two-way clustered SE.
extract_coefs <- function(model, label) {
  tab <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(tab, c("term", "estimate", "se", "tval", "pval"))
  tab <- tab[grepl("treat_p[123]|treat_yearc", term)]
  tab[, spec := label]
  tab[, .(spec, term, estimate, se, tval, pval)]
}

# ---------------------------------------------------------------------------
# 2. Panel A — SHARE
# ---------------------------------------------------------------------------
cat("\n===== PANEL A: SHARE, trend-corrected =====\n")
A_specs <- list(
  c1 = feols(share ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               prod_country + year,
             cluster = ~ vat + partner_iso2, data = d),
  c2 = feols(share ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               firm_prod_country + year,
             cluster = ~ vat + partner_iso2, data = d),
  c3 = feols(share ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               firm_prod_country + country_year,
             cluster = ~ vat + partner_iso2, data = d),
  c4 = feols(share ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               firm_prod_country + sector_year,
             cluster = ~ vat + partner_iso2, data = d),
  c5 = feols(share ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               firm_prod_country + country_year + sector_year,
             cluster = ~ vat + partner_iso2, data = d),
  c6 = feols(share ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               firm_prod_country + year_etsfirm,
             cluster = ~ vat + partner_iso2, data = d)
)
A_out <- rbindlist(lapply(seq_along(A_specs), function(i) {
  extract_coefs(A_specs[[i]], paste0("col", i))
}))
cat("\n--- Panel A (share, trend-corrected) ---\n")
print(A_out)

# ---------------------------------------------------------------------------
# 3. Panel B — PROBABILITY
# ---------------------------------------------------------------------------
cat("\n===== PANEL B: PROBABILITY, trend-corrected =====\n")
B_specs <- list(
  c1 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               prod_country + year,
             cluster = ~ vat + partner_iso2, data = d),
  c2 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               firm_prod_country + year,
             cluster = ~ vat + partner_iso2, data = d),
  c3 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               firm_prod_country + country_year,
             cluster = ~ vat + partner_iso2, data = d),
  c4 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               firm_prod_country + sector_year,
             cluster = ~ vat + partner_iso2, data = d),
  c5 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               firm_prod_country + country_year + sector_year,
             cluster = ~ vat + partner_iso2, data = d),
  c6 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 + treat_yearc |
               firm_prod_country + year_etsfirm,
             cluster = ~ vat + partner_iso2, data = d)
)
B_out <- rbindlist(lapply(seq_along(B_specs), function(i) {
  extract_coefs(B_specs[[i]], paste0("col", i))
}))
cat("\n--- Panel B (prob, trend-corrected) ---\n")
print(B_out)

# ---------------------------------------------------------------------------
# 4. Save
# ---------------------------------------------------------------------------
out_A <- file.path(OUT_TAB,
                    ifelse(USE_MOCK, "phase6_cdgm_corrected_A_MOCK.csv",
                                      "phase6_cdgm_corrected_A.csv"))
out_B <- file.path(OUT_TAB,
                    ifelse(USE_MOCK, "phase6_cdgm_corrected_B_MOCK.csv",
                                      "phase6_cdgm_corrected_B.csv"))
fwrite(A_out, out_A)
fwrite(B_out, out_B)
cat("\nPanel A saved:", out_A, "\n")
cat("Panel B saved:", out_B, "\n")

# ---------------------------------------------------------------------------
# 5. Side-by-side comparison printer (most informative output for paper)
# ---------------------------------------------------------------------------
cat("\n=========================================================\n")
cat("INTERPRETATION GUIDE\n")
cat("=========================================================\n")
cat("Each Phase-φ coefficient β_φ now identifies the LEVEL SHIFT\n")
cat("over that phase window relative to pre-2005, NET of the linear\n")
cat("regulated-vs-unregulated trend (captured by treat_yearc).\n\n")
cat("Compare against the original (no-trend) phase2_cdgm_table1 results\n")
cat("(local-1 col 5 reference: Phase 3 share -0.0024**).\n\n")
cat("- If treat_yearc is small / insignificant: original headline is\n")
cat("  trend-robust. The Phase-φ coefficients should be similar to the\n")
cat("  no-trend version.\n")
cat("- If treat_yearc is large: original headline conflates a linear\n")
cat("  trend with the Phase coefficients, and the trend-corrected\n")
cat("  Phase coefficients are the correct headline.\n")
