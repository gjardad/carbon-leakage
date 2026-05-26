# =============================================================================
# phase6_cdgm_table1_postmsr.R
#
# Post-MSR sub-split of the CdGM Table 1 import-share replication (paper §5.2.1).
#
# WHY THIS SCRIPT EXISTS
# ----------------------
# CdGM's window ends in 2019, when the EUA price was ~EUR 25. The entire EUA
# spike to EUR 90+ happens in 2020-2022 -- a window France's data never sees.
# Our exact Table 1 replication (phase2_cdgm_table1.R) also stops at 2019, so
# the strongest objection to our null is: "you tested leakage in a window where
# the carbon price was too low to bite." This script answers that by running
# CdGM Eq.(1) on the EXTENDED 2000-2022 customs panel with the post-2012 period
# sub-split, isolating the price-binding sub-windows.
#
# Identical to phase2_cdgm_table1.R / phase6_cdgm_table1_corrected.R in every
# other respect: non-ETS-source-country sample restriction, share + probability
# outcomes, six FE columns, two-way (firm + country) clustering, and the
# optional `treat x year_centered` trend control.
#
# TWO PHASE SCHEMES
# -----------------
#   nested  : p1=2005-08, p2=2009-12, p3=2013-19, p4=2020-22
#             p1/p2/p3 are CdGM's EXACT bins, so on the 2000-2019 subsample the
#             nested no-trend coefficients reproduce phase2_cdgm_table1 (a
#             built-in regression test). p4 is the new EUA-spike window.
#   finer   : p1=2005-08, p2=2009-12, p3_early=2013-17, p3_late=2018-19,
#             p4=2020-22. Splits the post-2012 period along the EUA price
#             ladder (P3 low ~EUR 5-8 | 2018-19 ~EUR 16-25 | P4 ~EUR 25-90+).
#             The 2018 split mirrors the B1 buyer-supplier finding, where the
#             post-2018 differential was the binding episode (INTERNATIONAL_
#             MARGIN_FINDINGS.md sec 8.2).
#
# DECISION RULE (for the paper headline)
# --------------------------------------
#   - p4 (2020-22) coef ~ 0 or wrong-signed  => the null is robust in the
#     window where the price actually binds. Kills the "wrong window" objection
#     and makes the null genuinely surprising. STRONG outcome.
#   - p4 coef negative & significant          => leakage appears once the price
#     is high enough; headline shifts to "leakage only at high carbon prices,
#     invisible in France's pre-2020 window."
#
# VENUE: real coefficients need the extended panel, which lives on RMD. On
# local-1 the script falls back to the 2000-2019 panel and the p4 (2020-22)
# bins are empty -- the script detects this and prints a clear RMD-pending
# warning, but still exercises the full code path for correctness.
#
# Outputs (per paths.R: output_local/ on local-1, output_rmd/ on RMD):
#   tables/phase6_cdgm_postmsr_share.csv  -- share, both schemes x {trend, no-trend} x 6 cols
#   tables/phase6_cdgm_postmsr_prob.csv   -- probability, same layout
#   tables/phase6_cdgm_postmsr_nested.tex -- paper-ready: nested phases, col(5), share + prob
#   tables/phase6_cdgm_postmsr_finer.tex  -- paper-ready: finer post-2012 split, col(5)
# The .csv files are gitignored (output_*/tables/*.csv); the .tex files are NOT,
# so the .tex tables are the artifacts to commit, push, and \input into the paper.
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE))
  install.packages("fixest", repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({
  library(data.table); library(fixest)
})

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Load panel. Prefer the 2000-2022 extended panel (the whole point of this
#    script); fall back to the 2000-2019 CdGM-window panel; fall back to mock.
#    Mirrors the loader in phase2_cdgm_figure2.R.
# ---------------------------------------------------------------------------
ext_rdata <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
reg_dta   <- file.path(PROC_DATA, "customs_import_panel_regulated.dta")
reg_rdata <- file.path(PROC_DATA, "customs_import_panel_regulated.RData")
mock_path <- file.path(PROC_DATA, "mock_customs_import_panel_regulated.RData")

USE_MOCK <- FALSE
USING_EXTENDED <- FALSE
if (file.exists(ext_rdata)) {
  cat("USING EXTENDED CUSTOMS PANEL (2000-2022).\n")
  load(ext_rdata); d <- as.data.table(panel); USING_EXTENDED <- TRUE
} else if (file.exists(reg_dta)) {
  cat("WARNING: extended panel not found; using CdGM-window panel (2000-2019, dta).\n")
  if (!requireNamespace("haven", quietly = TRUE))
    install.packages("haven", repos = "https://cloud.r-project.org")
  d <- as.data.table(haven::read_dta(reg_dta))
} else if (file.exists(reg_rdata)) {
  cat("WARNING: extended panel not found; using CdGM-window panel (2000-2019, RData).\n")
  load(reg_rdata); d <- as.data.table(panel)
} else {
  cat("USING MOCK CUSTOMS PANEL (local 1, no real panel found).\n")
  USE_MOCK <- TRUE; load(mock_path); d <- as.data.table(panel)
}
cat("Panel rows (full):", nrow(d), "  year span:",
    min(d$year), "-", max(d$year), "\n")

# ---------------------------------------------------------------------------
# 2. Sample restriction + outcomes (identical to phase2_cdgm_table1.R).
# ---------------------------------------------------------------------------
# CdGM-EXACT: restrict regression sample to non-ETS source countries.
d <- d[is_non_ets_country == 1L]
cat("Panel rows (non-ETS only):", nrow(d), "\n")

# Drop Switzerland: Swiss-recorded import value is a trading-hub invoicing
# artifact (consignment, not origin) that inflates the extra-EU share and the
# firm-year share denominator, biasing the regulated x phase coefficients
# negative post-2016. See phase6_cdgm_intrastat_break_diagnostic.R.
d <- d[partner_iso2 != "CH"]
cat("Dropped Switzerland (CH). Rows now:", nrow(d), "\n")

# Window: extended panel spans through 2022; keep everything 2000+ it offers.
d <- d[year >= 2000L]

# Outcome A: within-(firm, year) share over this (non-ETS) subsample.
d[, total_value_ft := sum(value), by = .(vat, year)]
d[, share := ifelse(total_value_ft > 0, value / total_value_ft, 0)]
# Outcome B: probability of positive value.
d[, prob_active := as.integer(value > 0)]

# ---------------------------------------------------------------------------
# 3. Treatment indicators for both phase schemes.
#    treat = is_regulated_product within the non-ETS subsample (CdGM convention).
# ---------------------------------------------------------------------------
d[, treat := is_regulated_product]

# nested scheme (CdGM bins + new p4)
d[, treat_p1 := treat * as.integer(year %between% c(2005L, 2008L))]
d[, treat_p2 := treat * as.integer(year %between% c(2009L, 2012L))]
d[, treat_p3 := treat * as.integer(year %between% c(2013L, 2019L))]
d[, treat_p4 := treat * as.integer(year %between% c(2020L, 2022L))]

# finer scheme (post-2012 split along the EUA price ladder)
d[, treat_p3e := treat * as.integer(year %between% c(2013L, 2017L))]  # low EUA
d[, treat_p3l := treat * as.integer(year %between% c(2018L, 2019L))]  # EUA ramp
# (treat_p4 reused as 2020-22 for the finer scheme too)

# continuous trend control (year_centered at 2014, matching phase6_cdgm_table1_corrected.R)
d[, year_centered := year - 2014L]
d[, treat_yearc := treat * year_centered]

# ---------------------------------------------------------------------------
# 4. FE / cluster id strings (identical to phase2_cdgm_table1.R).
# ---------------------------------------------------------------------------
d[, prod_country      := paste(cn8, partner_iso2, sep = "_")]
d[, firm_prod_country := paste(vat, cn8, partner_iso2, sep = "_")]
d[, country_year      := paste(partner_iso2, year, sep = "_")]
d[, sector_year       := paste(buyer_nace2d, year, sep = "_")]
d[, year_etsfirm      := paste(year, is_ets_firm, sep = "_")]

# ---------------------------------------------------------------------------
# 5. Diagnostics: is the post-2019 window actually populated?
# ---------------------------------------------------------------------------
n_p4_treat <- d[year %between% c(2020L, 2022L) & treat == 1L & value > 0, .N]
POST2019_EMPTY <- (max(d$year) < 2020L) || (n_p4_treat == 0L)
cat(sprintf("\nPost-2019 window: max year = %d; regulated non-ETS cells 2020-22 with value>0 = %d\n",
            max(d$year), n_p4_treat))
if (POST2019_EMPTY) {
  cat("************************************************************\n")
  cat("* RMD-PENDING: the 2020-2022 (p4) window is EMPTY on this   *\n")
  cat("* machine (no extended panel). p4 coefficients are NOT      *\n")
  cat("* estimable here. The code path below still runs for        *\n")
  cat("* correctness; ship to RMD with customs_import_panel_       *\n")
  cat("* extended.RData for the real p4 / finer-split numbers.     *\n")
  cat("************************************************************\n")
}

# ---------------------------------------------------------------------------
# Speed switch. TEX_ONLY = TRUE fits only the 8 preferred-FE col(5) models the
# paper .tex tables need (~fast). FALSE additionally runs the full
# 6-FE-column sweep across both schemes and writes the (gitignored) .csv files
# plus the console robustness print + reproduction check.
# ---------------------------------------------------------------------------
TEX_ONLY <- TRUE
mock_tag <- if (USE_MOCK) "_MOCK" else if (!USING_EXTENDED) "_NOEXT" else ""

# ---------------------------------------------------------------------------
# 6. Estimation engine. Runs the six CdGM FE columns for a given RHS term set
#    and outcome, returns tidy coefficients with two-way clustered SE.
# ---------------------------------------------------------------------------
FE_SPECS <- list(
  col1 = "prod_country + year",
  col2 = "firm_prod_country + year",
  col3 = "firm_prod_country + country_year",
  col4 = "firm_prod_country + sector_year",
  col5 = "firm_prod_country + country_year + sector_year",
  col6 = "firm_prod_country + year_etsfirm"
)

run_block <- function(outcome, rhs_terms, scheme_label, trend_flag) {
  rbindlist(lapply(names(FE_SPECS), function(cn) {
    fm <- as.formula(sprintf("%s ~ %s | %s",
                             outcome, rhs_terms, FE_SPECS[[cn]]))
    m <- tryCatch(
      feols(fm, data = d, cluster = ~ vat + partner_iso2),
      error = function(e) { cat(sprintf("  [%s %s trend=%d] FAILED: %s\n",
                                         scheme_label, cn, trend_flag,
                                         conditionMessage(e))); NULL })
    if (is.null(m)) return(NULL)
    tab <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
    setnames(tab, c("term", "estimate", "se", "tval", "pval"))
    tab <- tab[grepl("^treat_", term)]
    tab[, `:=`(outcome = outcome, scheme = scheme_label,
               trend = trend_flag, col = cn, nobs = m$nobs)]
    tab[, .(outcome, scheme, trend, col, term, estimate, se, tval, pval, nobs)]
  }))
}

# RHS term sets for each scheme x trend combination.
rhs_nested      <- "treat_p1 + treat_p2 + treat_p3 + treat_p4"
rhs_nested_tr   <- paste(rhs_nested, "+ treat_yearc")
rhs_finer       <- "treat_p1 + treat_p2 + treat_p3e + treat_p3l + treat_p4"
rhs_finer_tr    <- paste(rhs_finer, "+ treat_yearc")

run_outcome <- function(outcome) {
  rbindlist(list(
    run_block(outcome, rhs_nested,    "nested", 0L),
    run_block(outcome, rhs_nested_tr, "nested", 1L),
    run_block(outcome, rhs_finer,     "finer",  0L),
    run_block(outcome, rhs_finer_tr,  "finer",  1L)
  ))
}

# ---------------------------------------------------------------------------
# 7. Full 6-FE-column sweep + tidy CSVs (skipped under TEX_ONLY).
# ---------------------------------------------------------------------------
share_out <- NULL
if (!TEX_ONLY) {
  cat("\n===== PANEL A: SHARE =====\n")
  share_out <- run_outcome("share")
  print(share_out)

  cat("\n===== PANEL B: PROBABILITY =====\n")
  prob_out <- run_outcome("prob_active")
  print(prob_out)

  out_share <- file.path(OUT_TAB, sprintf("phase6_cdgm_postmsr_share%s.csv", mock_tag))
  out_prob  <- file.path(OUT_TAB, sprintf("phase6_cdgm_postmsr_prob%s.csv",  mock_tag))
  fwrite(share_out, out_share)
  fwrite(prob_out,  out_prob)
  cat("\nShare saved:", out_share, "\n")
  cat("Prob  saved:", out_prob,  "\n")
} else {
  cat("\nTEX_ONLY = TRUE: skipping the 6-FE-column sweep + CSVs; fitting only\n")
  cat("the col(5) models the paper .tex tables need.\n")
}

# ---------------------------------------------------------------------------
# 7b. Paper-ready LaTeX tables (.tex). Unlike the CSVs above, output_*/tables/
#     *.tex is NOT gitignored -- these are the artifacts to commit/push and to
#     \input directly into the paper. Built with fixest::etable to match the
#     house table style. Preferred FE col(5) only; columns (1)-(2) = import
#     share, (3)-(4) = sourcing probability; even columns add the trend control.
# ---------------------------------------------------------------------------
fe5  <- "firm_prod_country + country_year + sector_year"
fit5 <- function(outcome, rhs)
  feols(as.formula(sprintf("%s ~ %s | %s", outcome, rhs, fe5)),
        data = d, cluster = ~ vat + partner_iso2)

tex_dict <- c(
  treat_p1    = "Phase 1 (2005--08)",
  treat_p2    = "Phase 2 (2009--12)",
  treat_p3    = "Phase 3 (2013--19)",
  treat_p3e   = "Phase 3a (2013--17)",
  treat_p3l   = "Phase 3b (2018--19)",
  treat_p4    = "Phase IV (2020--22)",
  treat_yearc = "Regulated $\\times$ linear trend",
  firm_prod_country = "Firm $\\times$ product $\\times$ country",
  country_year      = "Country $\\times$ year",
  sector_year       = "Sector $\\times$ year",
  share             = "Import share",
  prob_active       = "Sourcing prob."
)

stars <- function(p) ifelse(is.na(p), "", ifelse(p < .001, "***",
                     ifelse(p < .01, "**", ifelse(p < .05, "*",
                     ifelse(p < .1, ".", "")))))

# Echo the price-window coefficients (share, col(5)) so the decision number is
# visible on the console even under TEX_ONLY.
print_key <- function(m, lab) {
  ct <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
  setnames(ct, c("term", "estimate", "se", "tval", "pval"))
  for (tm in intersect(c("treat_p3", "treat_p3l", "treat_p4"), ct$term)) {
    r <- ct[term == tm]
    cat(sprintf("    %-5s %-9s b=%+.5f  se=%.5f  p=%.4f %s\n",
                lab, tm, r$estimate, r$se, r$pval, stars(r$pval)))
  }
}

write_postmsr_tex <- function(rhs, rhs_tr, file, title, label, scheme_name) {
  ms0 <- fit5("share", rhs);       ms1 <- fit5("share", rhs_tr)
  mp0 <- fit5("prob_active", rhs); mp1 <- fit5("prob_active", rhs_tr)
  etable(ms0, ms1, mp0, mp1,
         tex = TRUE, file = file, replace = TRUE,
         title = title, label = label, dict = tex_dict,
         fitstat = ~ n,
         extralines = list("Trend control" = c("No", "Yes", "No", "Yes")),
         digits = "r4")
  cat("LaTeX table saved:", file, "\n")
  cat(sprintf("  [%s] share col(5) price-window coefficients:\n", scheme_name))
  print_key(ms0, "naive"); print_key(ms1, "trend")
}

tex_nested <- file.path(OUT_TAB, sprintf("phase6_cdgm_postmsr_nested%s.tex", mock_tag))
tex_finer  <- file.path(OUT_TAB, sprintf("phase6_cdgm_postmsr_finer%s.tex",  mock_tag))

tryCatch({
  write_postmsr_tex(
    rhs_nested, rhs_nested_tr, tex_nested,
    paste("Belgian import switching, CdGM specification through the post-MSR window.",
          "Columns (1)--(2): import share; (3)--(4): probability of sourcing.",
          "Even columns add a regulated-product $\\times$ linear-trend control.",
          "Preferred fixed effects throughout; two-way clustered on firm and country.",
          "France benchmark (CdGM 2024), Phase~3 import share: $+0.121$ (0.029)."),
    "tab:cdgm_postmsr_nested", "nested")
  write_postmsr_tex(
    rhs_finer, rhs_finer_tr, tex_finer,
    paste("Belgian import switching, post-2012 period split along the EUA price ladder:",
          "Phase 3a (2013--17, low price); Phase 3b (2018--19, ramp); Phase IV (2020--22, spike).",
          "Columns (1)--(2): import share; (3)--(4): probability of sourcing.",
          "Even columns add a regulated-product $\\times$ linear-trend control.",
          "Two-way clustered on firm and country."),
    "tab:cdgm_postmsr_finer", "finer")
}, error = function(e)
  cat("WARNING: etable LaTeX generation failed:", conditionMessage(e),
      "\n(CSV outputs above are unaffected.)\n"))

# ---------------------------------------------------------------------------
# 8. Decision rule, and (only when the full sweep ran) the reproduction check.
# ---------------------------------------------------------------------------
cat("\n---------------------------------------------------------\n")
cat("DECISION RULE (p4 = 2020-22, the EUA-spike window):\n")
cat("  p4 ~ 0 / wrong-signed  => null robust where price binds (STRONG).\n")
cat("  p4 negative & sig      => leakage appears at high carbon prices.\n")
cat("CdGM France benchmark (their Phase 3, 2013-19): share +0.121*** .\n")
if (POST2019_EMPTY)
  cat("\nNOTE: p4 is empty on this machine -> the rule applies to the RMD run.\n")

if (!TEX_ONLY) {
  cat("\n--- Reproduction check vs phase2_cdgm_table1 (nested, no-trend, col5) ---\n")
  cat("    Compare p1/p2/p3 against output/tables/phase2_cdgm_table1_A.csv:\n")
  print(share_out[scheme == "nested" & trend == 0L & col == "col5" &
                    term %in% c("treat_p1", "treat_p2", "treat_p3"),
                  .(term, estimate = round(estimate, 5), se = round(se, 5))])
}
