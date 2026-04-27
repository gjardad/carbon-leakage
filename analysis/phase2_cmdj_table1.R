# phase2_cmdj_table1.R
#
# Replicates CMdG Table 1 ("Imports of regulated vs. unregulated inputs from
# non-ETS countries"). PPML diff-in-diff at firm x product x source-country x
# year, phase-aggregated. Six FE-column specifications. Two outcomes.
#
# Spec (CMdG Eq 1, phase-aggregated):
#   y_{f,p,i,t} = exp[ b_1 * 1(non_ets_country)_i * 1(regulated)_p * 1(t in 2005-08)
#                    + b_2 * 1(non_ets_country)_i * 1(regulated)_p * 1(t in 2009-12)
#                    + b_3 * 1(non_ets_country)_i * 1(regulated)_p * 1(t in 2013-19)
#                    + FE ]
#
# Outcomes:
#   Panel A: share_{f,p,i,t} = value / sum_{p,i}(value | f,t)  (intensive margin)
#   Panel B: prob_{f,p,i,t}  = 1(value > 0)                    (extensive margin)
#
# 6 FE columns:
#   (1) product^country + year
#   (2) firm^product^country + year
#   (3) firm^product^country + country^year
#   (4) firm^product^country + sector^year
#   (5) firm^product^country + country^year + sector^year
#   (6) firm^product^country + year^is_ets_firm
#
# Cluster SE: two-way firm + country.
#
# Inputs:
#   * RMD: ${PROC_NBB}/customs_import_panel_regulated.dta
#   * local 1: NBB_data/processed/mock_customs_import_panel_regulated.RData
#
# Outputs:
#   * output/tables/phase2_cmdj_table1_A.csv  (share, 6 columns x 3 phases)
#   * output/tables/phase2_cmdj_table1_B.csv  (prob,  6 columns x 3 phases)

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
cat("Panel rows:", nrow(d), "\n")

# Outcome A: share within (firm, year) over the regression sample.
# Per CMdG p. 13, the denominator is the firm's total imports in year t over
# the regression sample (regulated-intensive buyers, core inputs, non-capital).
d[, total_value_ft := sum(value), by = .(vat, year)]
d[, share := ifelse(total_value_ft > 0, value / total_value_ft, 0)]

# Outcome B: probability of positive value.
d[, prob_active := as.integer(value > 0)]

# Treatment: regulated_product x non_ets_country, by phase.
d[, phase := fcase(
  year < 2005L, "pre",
  year <= 2008L, "p1",
  year <= 2012L, "p2",
  year <= 2019L, "p3",
  default = "post"
)]
d[, phase := factor(phase, levels = c("pre", "p1", "p2", "p3", "post"))]
d[, phase_p1 := as.integer(phase == "p1")]
d[, phase_p2 := as.integer(phase == "p2")]
d[, phase_p3 := as.integer(phase == "p3")]
d[, treat := is_regulated_product * is_non_ets_country]
d[, treat_p1 := treat * phase_p1]
d[, treat_p2 := treat * phase_p2]
d[, treat_p3 := treat * phase_p3]

# IDs for clustering and FE.
d[, prod_country := paste(cn8, partner_iso2, sep = "_")]
d[, firm_prod_country := paste(vat, cn8, partner_iso2, sep = "_")]
d[, country_year := paste(partner_iso2, year, sep = "_")]
d[, sector_year := paste(buyer_nace2d, year, sep = "_")]
d[, year_etsfirm := paste(year, is_ets_firm, sep = "_")]

# Restrict to 2000-2019 (CMdG sample).
d <- d[year %between% c(2000L, 2019L)]

# Helper: extract phase coefficients with two-way clustered SE.
extract_phase_coefs <- function(model, label) {
  tab <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(tab, c("term", "estimate", "se", "tval", "pval"))
  tab <- tab[grepl("treat_p[123]", term)]
  tab[, spec := label]
  tab[, .(spec, term, estimate, se, tval, pval)]
}

# ----- Panel A: SHARE (intensive margin) -----
# Use OLS (linear) for the share regression to mirror CMdG Table 1, Panel A.
cat("\n===== PANEL A: SHARE (intensive margin) =====\n")
A_specs <- list(
  c1 = feols(share ~ treat_p1 + treat_p2 + treat_p3 | prod_country + year,
             cluster = ~ vat + partner_iso2, data = d),
  c2 = feols(share ~ treat_p1 + treat_p2 + treat_p3 | firm_prod_country + year,
             cluster = ~ vat + partner_iso2, data = d),
  c3 = feols(share ~ treat_p1 + treat_p2 + treat_p3 | firm_prod_country + country_year,
             cluster = ~ vat + partner_iso2, data = d),
  c4 = feols(share ~ treat_p1 + treat_p2 + treat_p3 | firm_prod_country + sector_year,
             cluster = ~ vat + partner_iso2, data = d),
  c5 = feols(share ~ treat_p1 + treat_p2 + treat_p3 |
               firm_prod_country + country_year + sector_year,
             cluster = ~ vat + partner_iso2, data = d),
  c6 = feols(share ~ treat_p1 + treat_p2 + treat_p3 |
               firm_prod_country + year_etsfirm,
             cluster = ~ vat + partner_iso2, data = d)
)
A_out <- rbindlist(lapply(seq_along(A_specs), function(i) {
  extract_phase_coefs(A_specs[[i]], paste0("col", i))
}))
cat("\n--- Panel A coefficients ---\n")
print(A_out)

# ----- Panel B: PROBABILITY (extensive margin) -----
# Use OLS LPM mirroring CMdG.
cat("\n===== PANEL B: PROBABILITY (extensive margin) =====\n")
B_specs <- list(
  c1 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 | prod_country + year,
             cluster = ~ vat + partner_iso2, data = d),
  c2 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 | firm_prod_country + year,
             cluster = ~ vat + partner_iso2, data = d),
  c3 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 | firm_prod_country + country_year,
             cluster = ~ vat + partner_iso2, data = d),
  c4 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 | firm_prod_country + sector_year,
             cluster = ~ vat + partner_iso2, data = d),
  c5 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 |
               firm_prod_country + country_year + sector_year,
             cluster = ~ vat + partner_iso2, data = d),
  c6 = feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 |
               firm_prod_country + year_etsfirm,
             cluster = ~ vat + partner_iso2, data = d)
)
B_out <- rbindlist(lapply(seq_along(B_specs), function(i) {
  extract_phase_coefs(B_specs[[i]], paste0("col", i))
}))
cat("\n--- Panel B coefficients ---\n")
print(B_out)

# Save outputs.
tab_dir <- file.path(REPO_DIR, "output", "tables")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
out_A <- file.path(tab_dir,
                   ifelse(USE_MOCK, "phase2_cmdj_table1_A_MOCK.csv",
                                     "phase2_cmdj_table1_A.csv"))
out_B <- file.path(tab_dir,
                   ifelse(USE_MOCK, "phase2_cmdj_table1_B_MOCK.csv",
                                     "phase2_cmdj_table1_B.csv"))
fwrite(A_out, out_A)
fwrite(B_out, out_B)
cat("\nPanel A saved:", out_A, "\n")
cat("Panel B saved:", out_B, "\n")

# Quick CMdG benchmark check.
cat("\nCMdG benchmark (Table 1 col (5)): Phase 3 share ~+0.121 (SE 0.029); ",
    "prob ~+0.071 (SE 0.015).\n")
