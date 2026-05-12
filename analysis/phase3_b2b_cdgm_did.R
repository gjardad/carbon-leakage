# phase3_b2b_cdgm_did.R
#
# B2B CdGM-style diff-in-diff: do Belgian buyers shift purchases away from
# regulated-NACE ETS-domestic sellers post-2005?
#
# Spec (parallels Phase 2 Table 1):
#   y_{j,b,t} = b_1 * TREAT_j * 1(t in 2005-08)
#             + b_2 * TREAT_j * 1(t in 2009-12)
#             + b_3 * TREAT_j * 1(t in 2013-19) + FE
#   TREAT_j = is_ets_seller * is_regulated_nace_seller (Spec C, full sample)
#
# Outcomes:
#   Panel A (intensive): share_{j,b,t} = corr_sales_{j,b,t} / sum_{j' in same
#     seller_NACE2d}(corr_sales_{j',b,t}). Buyer's share of purchases (within
#     the seller-NACE) going to seller j.
#   Panel B (extensive): pair_active_{j,b,t} = 1(corr_sales > 0).
#
# Six FE columns paralleling Phase 2 Table 1:
#   col1: seller_nace4d^year
#   col2: seller^buyer + year
#   col3: seller^buyer + seller_nace4d^year
#   col4: seller^buyer + buyer_nace4d^year
#   col5: seller^buyer + seller_nace4d^year + buyer_nace4d^year
#   col6: seller^buyer + year^buyer_is_ets    (NB: in Phase 2 this was
#         year^is_ets_firm; here we substitute buyer_is_ets as the analog)
#
# Cluster SE: two-way seller + buyer.
#
# Plus a control-group robustness mirror of Phase 2:
#   A. CdGM baseline (sample = ETS sellers only). Treat = regulated NACE.
#   B. Within-regulated-NACE (sample = regulated NACE sellers only).
#      Treat = ETS seller.
#   C. Full sample, treat = ETS x regulated_NACE.
#   D. Full sample, triple difference.
#
# Sign expectation under leakage hypothesis: NEGATIVE coefficients (treated
# sellers lose buyer share post-2005).
#
# Outputs:
#   output/tables/phase3_b2b_cdgm_table_A.csv  (share, 6 cols x 3 phases)
#   output/tables/phase3_b2b_cdgm_table_B.csv  (prob, 6 cols x 3 phases)
#   output/tables/phase3_b2b_cdgm_robustness.csv  (4 specs x 2 panels x 3 phases)

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE)) install.packages("fixest", repos = "https://cloud.r-project.org")
library(data.table)
library(fixest)

panel_path <- file.path(PROC_DATA, "b2b_cdgm_panel.RData")
load(panel_path)
d <- as.data.table(panel)
cat("B2B panel rows:", nrow(d), "\n")

# Restrict to 2000-2019 for CdGM-comparable phases.
d <- d[year %between% c(2005L, 2019L)]

# Buyer ETS flag for col(6) FE.
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
d[, buyer_is_ets := as.integer(buyer %in% ets_vats)]

# Phase indicators.
d[, phase_p1 := as.integer(year %between% c(2005L, 2008L))]
d[, phase_p2 := as.integer(year %between% c(2009L, 2012L))]
d[, phase_p3 := as.integer(year %between% c(2013L, 2019L))]

# Outcome A: share within (buyer, seller_nace4d, year).
# Buyer's share of purchases from seller_nace4d going to this specific seller.
d[, total_buyer_sn4d_t := sum(corr_sales),
  by = .(buyer, seller_nace4d, year)]
d[, share := ifelse(total_buyer_sn4d_t > 0,
                    corr_sales / total_buyer_sn4d_t, 0)]

# Outcome B: pair active.
d[, prob_active := as.integer(corr_sales > 0)]

# FE keys.
d[, seller_buyer  := paste(seller, buyer, sep = "_")]
d[, sn4d_year     := paste(seller_nace4d, year, sep = "_")]
d[, bn4d_year     := paste(buyer_nace4d,  year, sep = "_")]
d[, year_buyerets := paste(year, buyer_is_ets, sep = "_")]

# Treatment.
d[, treat := seller_is_ets * seller_is_regulated_nace]
d[, treat_p1 := treat * phase_p1]
d[, treat_p2 := treat * phase_p2]
d[, treat_p3 := treat * phase_p3]

# ---------------------------------------------------------------------------
# Six-column Table (Spec C: treat = ETS x regulated_NACE on full sample)
# ---------------------------------------------------------------------------
extract_phase <- function(model, label) {
  tab <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(tab, c("term", "estimate", "se", "tval", "pval"))
  tab <- tab[grepl("treat_p[123]", term)]
  tab[, spec := label]
  tab[, .(spec, term, estimate, se, tval, pval)]
}

run_six_cols <- function(outcome, label) {
  forms <- list(
    col1 = sprintf("%s ~ treat_p1 + treat_p2 + treat_p3 | sn4d_year", outcome),
    col2 = sprintf("%s ~ treat_p1 + treat_p2 + treat_p3 | seller_buyer + year", outcome),
    col3 = sprintf("%s ~ treat_p1 + treat_p2 + treat_p3 | seller_buyer + sn4d_year", outcome),
    col4 = sprintf("%s ~ treat_p1 + treat_p2 + treat_p3 | seller_buyer + bn4d_year", outcome),
    col5 = sprintf("%s ~ treat_p1 + treat_p2 + treat_p3 | seller_buyer + sn4d_year + bn4d_year", outcome),
    col6 = sprintf("%s ~ treat_p1 + treat_p2 + treat_p3 | seller_buyer + year_buyerets", outcome)
  )
  out <- list()
  for (nm in names(forms)) {
    m <- feols(as.formula(forms[[nm]]),
               cluster = ~ seller + buyer, data = d)
    out[[nm]] <- extract_phase(m, nm)
  }
  rbindlist(out)
}

cat("\n===== PANEL A: SHARE =====\n")
A_out <- run_six_cols("share", "share")
print(A_out)

cat("\n===== PANEL B: PROBABILITY =====\n")
B_out <- run_six_cols("prob_active", "prob")
print(B_out)

tab_dir <- file.path(REPO_DIR, "output", "tables")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
fwrite(A_out, file.path(tab_dir, "phase3_b2b_cdgm_table_A.csv"))
fwrite(B_out, file.path(tab_dir, "phase3_b2b_cdgm_table_B.csv"))

# ---------------------------------------------------------------------------
# Control-group robustness (col 5 FE, 4 specs)
# ---------------------------------------------------------------------------
cat("\n===== Robustness across control groups (col(5) FE) =====\n")

extract_phase_long <- function(model, label, panel_lab) {
  tab <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(tab, c("term", "estimate", "se", "tval", "pval"))
  tab <- tab[grepl("treat_p[123]", term)]
  tab[, spec := label]
  tab[, panel := panel_lab]
  tab[, phase := fcase(grepl("p1", term), "Phase 1 (2005-08)",
                       grepl("p2", term), "Phase 2 (2009-12)",
                       grepl("p3", term), "Phase 3 (2013-19)")]
  tab[, .(panel, spec, phase, estimate, se, tval, pval)]
}

results <- list()

# Spec A -- CdGM baseline analog: sample = ETS sellers only, treat = regulated NACE.
# IMPORTANT: in this subsample, regulated_NACE is determined by seller_nace4d
# (a NACE 2d property propagated to NACE 4d), so sn4d_year FE would mechanically
# absorb the treatment. Drop sn4d_year for this spec; keep buyer-side
# bn4d_year and pair-level seller_buyer.
cat("\n----- Spec A: ETS sellers only, treat = regulated_NACE -----\n")
dA <- d[seller_is_ets == 1L]
dA[, treat_p1 := seller_is_regulated_nace * phase_p1]
dA[, treat_p2 := seller_is_regulated_nace * phase_p2]
dA[, treat_p3 := seller_is_regulated_nace * phase_p3]
mA_share <- feols(share ~ treat_p1 + treat_p2 + treat_p3 |
                    seller_buyer + bn4d_year,
                  cluster = ~ seller + buyer, data = dA)
mA_prob <- feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 |
                   seller_buyer + bn4d_year,
                 cluster = ~ seller + buyer, data = dA)
results[["A_share"]] <- extract_phase_long(mA_share, "A: vs unreg in ETS sellers", "Share")
results[["A_prob"]]  <- extract_phase_long(mA_prob,  "A: vs unreg in ETS sellers", "Prob")

# Spec B -- within-regulated_NACE: sample = regulated_NACE sellers, treat = ETS seller.
cat("\n----- Spec B: regulated_NACE sellers only, treat = is_ets_seller -----\n")
dB <- d[seller_is_regulated_nace == 1L]
dB[, treat_p1 := seller_is_ets * phase_p1]
dB[, treat_p2 := seller_is_ets * phase_p2]
dB[, treat_p3 := seller_is_ets * phase_p3]
mB_share <- feols(share ~ treat_p1 + treat_p2 + treat_p3 |
                    seller_buyer + sn4d_year + bn4d_year,
                  cluster = ~ seller + buyer, data = dB)
mB_prob <- feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 |
                   seller_buyer + sn4d_year + bn4d_year,
                 cluster = ~ seller + buyer, data = dB)
results[["B_share"]] <- extract_phase_long(mB_share, "B: vs non-ETS in reg NACE", "Share")
results[["B_prob"]]  <- extract_phase_long(mB_prob,  "B: vs non-ETS in reg NACE", "Prob")

# Spec C -- full sample, double diff: treat = ETS x regulated_NACE.
cat("\n----- Spec C: full sample, treat = ETS x regulated_NACE -----\n")
mC_share <- feols(share ~ treat_p1 + treat_p2 + treat_p3 |
                    seller_buyer + sn4d_year + bn4d_year,
                  cluster = ~ seller + buyer, data = d)
mC_prob <- feols(prob_active ~ treat_p1 + treat_p2 + treat_p3 |
                   seller_buyer + sn4d_year + bn4d_year,
                 cluster = ~ seller + buyer, data = d)
results[["C_share"]] <- extract_phase_long(mC_share, "C: vs other 3 cells (full)", "Share")
results[["C_prob"]]  <- extract_phase_long(mC_prob,  "C: vs other 3 cells (full)", "Prob")

# Spec D -- triple difference.
cat("\n----- Spec D: triple difference -----\n")
dD <- copy(d)
dD[, regp1 := seller_is_regulated_nace * phase_p1]
dD[, regp2 := seller_is_regulated_nace * phase_p2]
dD[, regp3 := seller_is_regulated_nace * phase_p3]
dD[, etsp1 := seller_is_ets * phase_p1]
dD[, etsp2 := seller_is_ets * phase_p2]
dD[, etsp3 := seller_is_ets * phase_p3]
mD_share <- feols(share ~ regp1 + regp2 + regp3 + etsp1 + etsp2 + etsp3 +
                    treat_p1 + treat_p2 + treat_p3 |
                    seller_buyer + sn4d_year + bn4d_year,
                  cluster = ~ seller + buyer, data = dD)
mD_prob <- feols(prob_active ~ regp1 + regp2 + regp3 + etsp1 + etsp2 + etsp3 +
                   treat_p1 + treat_p2 + treat_p3 |
                   seller_buyer + sn4d_year + bn4d_year,
                 cluster = ~ seller + buyer, data = dD)
results[["D_share"]] <- extract_phase_long(mD_share, "D: triple diff", "Share")
results[["D_prob"]]  <- extract_phase_long(mD_prob,  "D: triple diff", "Prob")

robust_out <- rbindlist(results)
robust_out[, ci_lo := estimate - 1.96 * se]
robust_out[, ci_hi := estimate + 1.96 * se]

cat("\n===== ROBUSTNESS SUMMARY =====\n")
cat("\n-- Panel A (Share) --\n")
print(dcast(robust_out[panel == "Share"],
            spec ~ phase, value.var = "estimate")[
  , .(spec,
      `Phase 1` = round(`Phase 1 (2005-08)`, 4),
      `Phase 2` = round(`Phase 2 (2009-12)`, 4),
      `Phase 3` = round(`Phase 3 (2013-19)`, 4))])

cat("\n-- Panel B (Probability) --\n")
print(dcast(robust_out[panel == "Prob"],
            spec ~ phase, value.var = "estimate")[
  , .(spec,
      `Phase 1` = round(`Phase 1 (2005-08)`, 4),
      `Phase 2` = round(`Phase 2 (2009-12)`, 4),
      `Phase 3` = round(`Phase 3 (2013-19)`, 4))])

fwrite(robust_out, file.path(tab_dir, "phase3_b2b_cdgm_robustness.csv"))
cat("\nRobustness saved:", file.path(tab_dir, "phase3_b2b_cdgm_robustness.csv"), "\n")

cat("\n--- Sign expectation reminder ---\n")
cat("Under the leakage hypothesis, treated sellers (ETS x regulated_NACE)\n")
cat("LOSE buyer share post-2005 -> beta < 0 in both panels.\n")
cat("Compare with cross-border result in IMPORT_LEAKAGE.md (also negative\n")
cat("for share but null/positive for probability).\n")
