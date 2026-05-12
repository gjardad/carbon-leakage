# phase2_cdgm_table1_robustness.R
#
# Robustness across control-group choices. Same headline question -- "do
# Belgian firms shift sourcing of regulated products toward non-ETS countries
# post-2005?" -- under four different identification strategies.
#
# Holds the FE structure constant at the CdGM col(5) preferred spec
# (firm^product^country + country^year + sector^year), runs each panel
# (share, prob), reports phase-aggregated coefficients.
#
# Specs:
#   A. CdGM baseline (matches phase2_cdgm_table1.R).
#      Sample: non-ETS countries only.
#      Treatment: regulated x phase.
#      Implicit control: unregulated x non-ETS.
#
#   B. Within-regulated alternative (CdGM Figure 4 conceptual analog).
#      Sample: regulated products only.
#      Treatment: non-ETS x phase.
#      Implicit control: regulated x ETS.
#
#   C. Full-sample double diff.
#      Sample: full.
#      Treatment: (regulated x non-ETS) x phase.
#      Implicit control: all other three cells pooled.
#
#   D. Full-sample triple difference.
#      Sample: full.
#      Treatment: (regulated x non-ETS) x phase, with main effects of
#      (regulated x phase) and (non-ETS x phase) included.
#      Identifies the additional effect of (regulated x non-ETS x post)
#      net of trends in regulated alone and non-ETS alone.
#
# Inputs / outputs analogous to phase2_cdgm_table1.R.
# Output: output/tables/phase2_cdgm_table1_robustness.csv

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE)) install.packages("fixest", repos = "https://cloud.r-project.org")
library(data.table)
library(fixest)

USE_MOCK <- !file.exists(file.path(PROC_DATA, "customs_import_panel_regulated.dta"))

if (USE_MOCK) {
  cat("USING MOCK CUSTOMS PANEL.\n")
  load(file.path(PROC_DATA, "mock_customs_import_panel_regulated.RData"))
  d <- as.data.table(panel)
} else {
  cat("USING REAL CUSTOMS PANEL.\n")
  if (!requireNamespace("haven", quietly = TRUE)) install.packages("haven", repos = "https://cloud.r-project.org")
  d <- as.data.table(haven::read_dta(file.path(PROC_DATA, "customs_import_panel_regulated.dta")))
}
d <- d[year %between% c(2000L, 2019L)]
cat("Full panel rows:", nrow(d), "\n")

# Phase indicators (common to all specs).
d[, phase_p1 := as.integer(year %between% c(2005L, 2008L))]
d[, phase_p2 := as.integer(year %between% c(2009L, 2012L))]
d[, phase_p3 := as.integer(year %between% c(2013L, 2019L))]

# FE keys (common).
d[, firm_prod_country := paste(vat, cn8, partner_iso2, sep = "_")]
d[, country_year := paste(partner_iso2, year, sep = "_")]
d[, sector_year := paste(buyer_nace2d, year, sep = "_")]

# Per-cell share and prob (computed within whatever subsample the spec uses,
# below).

extract_phase <- function(model, label, panel_lab) {
  tab <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(tab, c("term", "estimate", "se", "tval", "pval"))
  # Match ANY p1/p2/p3-tagged treatment coefficient (specs use slightly
  # different naming).
  tab <- tab[grepl("treat_p[123]", term) | grepl("p[123]_treat", term)]
  tab[, spec := label]
  tab[, panel := panel_lab]
  tab[, phase := fcase(grepl("p1", term), "Phase 1 (2005-08)",
                       grepl("p2", term), "Phase 2 (2009-12)",
                       grepl("p3", term), "Phase 3 (2013-19)")]
  tab[, .(panel, spec, phase, estimate, se, tval, pval)]
}

results <- list()

# -------------------------------------------------------------------------
# Spec A -- CdGM baseline (sample = non-ETS only)
# -------------------------------------------------------------------------
cat("\n===== Spec A: CdGM baseline (non-ETS sample) =====\n")
dA <- copy(d[is_non_ets_country == 1L])
dA[, total_value_ft := sum(value), by = .(vat, year)]
dA[, share := ifelse(total_value_ft > 0, value / total_value_ft, 0)]
dA[, prob_active := as.integer(value > 0)]
dA[, treat_p1 := is_regulated_product * phase_p1]
dA[, treat_p2 := is_regulated_product * phase_p2]
dA[, treat_p3 := is_regulated_product * phase_p3]

mA_share <- feols(share ~ treat_p1 + treat_p2 + treat_p3 |
                    firm_prod_country + country_year + sector_year,
                  cluster = ~ vat + partner_iso2, data = dA)
mA_prob <- feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 |
                   firm_prod_country + country_year + sector_year,
                 cluster = ~ vat + partner_iso2, data = dA)
results[["A_share"]] <- extract_phase(mA_share, "A: vs unreg in non-ETS (CdGM)", "Share")
results[["A_prob"]]  <- extract_phase(mA_prob,  "A: vs unreg in non-ETS (CdGM)", "Prob")

# -------------------------------------------------------------------------
# Spec B -- within-regulated, non-ETS vs ETS (Fig 4 conceptual)
# -------------------------------------------------------------------------
cat("\n===== Spec B: within-regulated (non-ETS vs ETS) =====\n")
dB <- copy(d[is_regulated_product == 1L])
dB[, total_value_ft := sum(value), by = .(vat, year)]
dB[, share := ifelse(total_value_ft > 0, value / total_value_ft, 0)]
dB[, prob_active := as.integer(value > 0)]
dB[, treat_p1 := is_non_ets_country * phase_p1]
dB[, treat_p2 := is_non_ets_country * phase_p2]
dB[, treat_p3 := is_non_ets_country * phase_p3]

mB_share <- feols(share ~ treat_p1 + treat_p2 + treat_p3 |
                    firm_prod_country + country_year + sector_year,
                  cluster = ~ vat + partner_iso2, data = dB)
mB_prob <- feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 |
                   firm_prod_country + country_year + sector_year,
                 cluster = ~ vat + partner_iso2, data = dB)
results[["B_share"]] <- extract_phase(mB_share, "B: vs reg in ETS (Fig 4 style)", "Share")
results[["B_prob"]]  <- extract_phase(mB_prob,  "B: vs reg in ETS (Fig 4 style)", "Prob")

# -------------------------------------------------------------------------
# Spec C -- full sample double diff
# -------------------------------------------------------------------------
cat("\n===== Spec C: full sample, treat = reg x non-ETS =====\n")
dC <- copy(d)
dC[, total_value_ft := sum(value), by = .(vat, year)]
dC[, share := ifelse(total_value_ft > 0, value / total_value_ft, 0)]
dC[, prob_active := as.integer(value > 0)]
dC[, treat_p1 := is_regulated_product * is_non_ets_country * phase_p1]
dC[, treat_p2 := is_regulated_product * is_non_ets_country * phase_p2]
dC[, treat_p3 := is_regulated_product * is_non_ets_country * phase_p3]

mC_share <- feols(share ~ treat_p1 + treat_p2 + treat_p3 |
                    firm_prod_country + country_year + sector_year,
                  cluster = ~ vat + partner_iso2, data = dC)
mC_prob <- feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 |
                   firm_prod_country + country_year + sector_year,
                 cluster = ~ vat + partner_iso2, data = dC)
results[["C_share"]] <- extract_phase(mC_share, "C: vs all other 3 cells (full sample)", "Share")
results[["C_prob"]]  <- extract_phase(mC_prob,  "C: vs all other 3 cells (full sample)", "Prob")

# -------------------------------------------------------------------------
# Spec D -- full sample, triple difference
# -------------------------------------------------------------------------
cat("\n===== Spec D: triple difference =====\n")
dD <- copy(dC)
# Main-effect interactions (each absorbs a separate trend).
dD[, regp1 := is_regulated_product * phase_p1]
dD[, regp2 := is_regulated_product * phase_p2]
dD[, regp3 := is_regulated_product * phase_p3]
dD[, nep1 := is_non_ets_country * phase_p1]
dD[, nep2 := is_non_ets_country * phase_p2]
dD[, nep3 := is_non_ets_country * phase_p3]
# Triple interaction = treat_p* (already defined in dC -> dD).

mD_share <- feols(share ~ regp1 + regp2 + regp3 + nep1 + nep2 + nep3 +
                    treat_p1 + treat_p2 + treat_p3 |
                    firm_prod_country + country_year + sector_year,
                  cluster = ~ vat + partner_iso2, data = dD)
mD_prob <- feols(prob_active ~ regp1 + regp2 + regp3 + nep1 + nep2 + nep3 +
                   treat_p1 + treat_p2 + treat_p3 |
                   firm_prod_country + country_year + sector_year,
                 cluster = ~ vat + partner_iso2, data = dD)
results[["D_share"]] <- extract_phase(mD_share, "D: triple diff", "Share")
results[["D_prob"]]  <- extract_phase(mD_prob,  "D: triple diff", "Prob")

# -------------------------------------------------------------------------
# Combine and save
# -------------------------------------------------------------------------
out <- rbindlist(results)
out[, ci_lo := estimate - 1.96 * se]
out[, ci_hi := estimate + 1.96 * se]

cat("\n===== SUMMARY: control-group robustness, col(5) FE =====\n")
cat("\n-- Panel A (Share) --\n")
print(dcast(out[panel == "Share"],
            spec ~ phase, value.var = "estimate")[
  , .(spec,
      `Phase 1` = round(`Phase 1 (2005-08)`, 4),
      `Phase 2` = round(`Phase 2 (2009-12)`, 4),
      `Phase 3` = round(`Phase 3 (2013-19)`, 4))])

cat("\n-- Panel B (Probability) --\n")
print(dcast(out[panel == "Prob"],
            spec ~ phase, value.var = "estimate")[
  , .(spec,
      `Phase 1` = round(`Phase 1 (2005-08)`, 4),
      `Phase 2` = round(`Phase 2 (2009-12)`, 4),
      `Phase 3` = round(`Phase 3 (2013-19)`, 4))])

tab_dir <- file.path(REPO_DIR, "output", "tables")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(tab_dir,
                      ifelse(USE_MOCK, "phase2_cdgm_table1_robustness_MOCK.csv",
                                        "phase2_cdgm_table1_robustness.csv"))
fwrite(out, out_path)
cat("\nRobustness table saved:", out_path, "\n")
