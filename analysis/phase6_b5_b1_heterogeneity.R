# =============================================================================
# B5 — Heterogeneity extensions of B1 (buyer-supplier customs DiD).
#
# Two priority-A heterogeneity cuts identified in
# INTERNATIONAL_MARGIN_FINDINGS.md §4:
#
#   (1) HS6 carbon intensity:
#       Split the regulated CN8 products by HS6 emission intensity per €
#       (built in phase6_build_hs6_carbon_intensity.R from Belgian ETS firm
#       data + cn8_to_nace4d concordance). Within high-CI HS6, leakage
#       prediction is sharpest because per-€ carbon cost is highest. If
#       B1's −0.56 substitution effect is driven by high-CI products, R1
#       (aggregation hides a sub-population) gains weight over R2/R3.
#
#   (2) Pre-MSR vs post-MSR window:
#       B1 uses post = 1(year ≥ 2015), but EUA prices only spiked above
#       €40 after the Phase IV decision (2018-02). If leakage is
#       price-driven, the 2018+ subperiod should carry the action. We
#       run B1 with three variants:
#         (a) post_2015 only (B1 baseline)
#         (b) post_2018 only (MSR price-spike window)
#         (c) both post dummies in one regression (differential test)
#
# Strategy: replicate the B1 panel construction exactly from
# phase6_b1_corrected.R (build A); add HS6-CI join and post_msr dummy
# (build B); then run the heterogeneity ladder against the B1 trend-
# corrected baseline.
#
# Outputs:
#   ${OUT_TAB}/phase6_b5_hs6ci_quartile.csv          B1 by HS6-CI quartile
#   ${OUT_TAB}/phase6_b5_hs6ci_continuous.csv        B1 with HS6-CI as cts moderator
#   ${OUT_TAB}/phase6_b5_postmsr.csv                 B1 with post=2018 vs post=2015
#   ${OUT_FIG}/phase6_b5_hs6ci_quartile.pdf          one-panel quartile plot
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2)
})

ANCHOR    <- 2014L
NSHARE_LO <- 2010L; NSHARE_HI <- 2014L
POST_2015 <- 2015L
POST_2018 <- 2018L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Build B1 panel (identical to phase6_b1_corrected.R section 1)
# ---------------------------------------------------------------------------
ext_path <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
if (file.exists(ext_path)) {
  load(ext_path); cat("Using extended customs panel.\n")
} else {
  cat("WARNING: extended panel not found; using 2000-2019 panel.\n")
  load(file.path(PROC_DATA, "customs_import_panel_regulated.RData"))
}
panel <- as.data.table(panel)

reg <- panel[is_regulated_product == 1L]
reg[, source_eu := 1L - is_non_ets_country]
reg[, hs6 := substr(cn8, 1, 6)]
bloc <- reg[, .(value = sum(value, na.rm = TRUE)),
            by = .(vat, hs6, source_eu, year)]

pre <- bloc[year %between% c(NSHARE_LO, NSHARE_HI)]
fb <- pre[, .(any_eu  = any(source_eu == 1L & value > 0),
              any_non = any(source_eu == 0L & value > 0)),
          by = .(vat, hs6)]
feasible <- fb[any_eu & any_non, .(vat, hs6)]
bloc <- merge(bloc, feasible, by = c("vat", "hs6"))

pre_total <- pre[, .(total_pre = sum(value, na.rm = TRUE)), by = .(vat, hs6)]
pre_eu    <- pre[source_eu == 1L,
                  .(eu_pre = sum(value, na.rm = TRUE)), by = .(vat, hs6)]
pe <- merge(pre_total, pre_eu, by = c("vat", "hs6"), all.x = TRUE)
pe[is.na(eu_pre), eu_pre := 0]
pe[, pair_exposure_EU := fifelse(total_pre > 0, eu_pre / total_pre, NA_real_)]

bloc_yr <- dcast(bloc, vat + hs6 + year ~ source_eu, value.var = "value", fill = 0)
setnames(bloc_yr, c("0", "1"), c("non_eu", "eu"))
bloc_yr[, total := non_eu + eu]
bloc_yr[, share_eu := fifelse(total > 0, eu / total, NA_real_)]
bloc_yr <- merge(bloc_yr, pe[, .(vat, hs6, pair_exposure_EU)],
                 by = c("vat", "hs6"))
bloc_yr <- bloc_yr[!is.na(share_eu)]
bloc_yr[, post      := as.integer(year >= POST_2015)]
bloc_yr[, post_msr  := as.integer(year >= POST_2018)]
bloc_yr[, year_centered := year - ANCHOR]

cat(sprintf("\nB5 base sample: %d cell-years, %d (vat,hs6) pairs\n",
            nrow(bloc_yr), uniqueN(bloc_yr[, .(vat, hs6)])))

# ---------------------------------------------------------------------------
# 2. Join HS6 carbon intensity
# ---------------------------------------------------------------------------
hs6_ci_path <- file.path(REPO_DIR, "data", "processed",
                         "hs6_carbon_intensity.csv")
if (!file.exists(hs6_ci_path)) {
  stop("hs6_carbon_intensity.csv not found at ", hs6_ci_path,
       "\nRun analysis/phase6_build_hs6_carbon_intensity.R first.")
}
hs6_ci <- fread(hs6_ci_path,
                colClasses = list(character = "hs6", numeric = "carbon_intensity"))
bloc_yr <- merge(bloc_yr, hs6_ci, by = "hs6", all.x = TRUE)
cat(sprintf("  HS6-CI join: %d cells matched (%.1f%%), %d unmatched\n",
            sum(!is.na(bloc_yr$carbon_intensity)),
            100 * mean(!is.na(bloc_yr$carbon_intensity)),
            sum(is.na(bloc_yr$carbon_intensity))))

# Compute HS6-CI quartile breakpoints at the HS6 level (one obs per HS6),
# not at the cell-year level (so a high-volume HS6 doesn't dominate the
# quartile threshold).
hs6_unique <- unique(bloc_yr[!is.na(carbon_intensity), .(hs6, carbon_intensity)])
ci_breaks <- quantile(hs6_unique$carbon_intensity,
                      probs = seq(0, 1, 0.25), na.rm = TRUE, type = 7)
ci_breaks[1] <- ci_breaks[1] - 1e-9   # ensure inclusion of min
hs6_unique[, ci_quartile := cut(carbon_intensity, breaks = ci_breaks,
                                 labels = paste0("Q", 1:4),
                                 include.lowest = TRUE)]
bloc_yr <- merge(bloc_yr, hs6_unique[, .(hs6, ci_quartile)],
                 by = "hs6", all.x = TRUE)
cat("\n  HS6-CI quartile breakpoints (kg CO2 / EUR):\n")
print(round(ci_breaks, 6))
cat(sprintf("\n  HS6-CI quartile cell-year counts (NA = unmatched HS6):\n"))
print(bloc_yr[, .N, by = ci_quartile][order(ci_quartile)])

# ---------------------------------------------------------------------------
# 3. B1 baseline (re-run for reference)
# ---------------------------------------------------------------------------
cat("\n=== B1 baseline (re-run for reference) ===\n")
m_baseline <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:post + pair_exposure_EU:year_centered |
                    vat^hs6 + hs6^year,
        data = bloc_yr, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_baseline)) print(coeftable(m_baseline))

extract_row <- function(m, label, term_pat = "pair_exposure_EU:post$") {
  if (is.null(m)) return(NULL)
  ct <- as.data.table(coeftable(m), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  ct <- ct[grepl(term_pat, term)]
  ct[, label := label]
  ct[, n_obs := nobs(m)]
  ct
}

# ---------------------------------------------------------------------------
# 4. HS6-CI quartile split — B1 trend-corrected, per quartile
# ---------------------------------------------------------------------------
cat("\n=== HS6-CI quartile split ===\n")
quartile_levels <- c("Q1", "Q2", "Q3", "Q4")
rows_q <- list()
for (q in quartile_levels) {
  sub <- bloc_yr[ci_quartile == q]
  m_q <- tryCatch(
    feols(share_eu ~ pair_exposure_EU:post + pair_exposure_EU:year_centered |
                      vat^hs6 + hs6^year,
          data = sub, cluster = c("vat", "hs6"), notes = FALSE),
    error = function(e) {
      cat(sprintf("  [%s] feols error: %s\n", q, conditionMessage(e))); NULL })
  rows_q[[q]] <- extract_row(m_q, paste0("ci_", q))
}
# Also pool (Q1+Q2 vs Q3+Q4) since within-quartile N may be thin.
sub_lo <- bloc_yr[ci_quartile %in% c("Q1", "Q2")]
m_lo <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:post + pair_exposure_EU:year_centered |
                    vat^hs6 + hs6^year,
        data = sub_lo, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
rows_q[["lo_half"]] <- extract_row(m_lo, "ci_Q1Q2_pooled")

sub_hi <- bloc_yr[ci_quartile %in% c("Q3", "Q4")]
m_hi <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:post + pair_exposure_EU:year_centered |
                    vat^hs6 + hs6^year,
        data = sub_hi, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
rows_q[["hi_half"]] <- extract_row(m_hi, "ci_Q3Q4_pooled")

res_q <- rbindlist(Filter(Negate(is.null), rows_q), fill = TRUE)
if (nrow(res_q)) {
  fwrite(res_q, file.path(OUT_TAB, "phase6_b5_hs6ci_quartile.csv"))
  print(res_q[, .(label, term, est, se, pval, n_obs)])
}

# ---------------------------------------------------------------------------
# 5. HS6-CI continuous moderator (within-sample, single regression)
#    Triple interaction: pair_exposure_EU × post × log(carbon_intensity)
#    Use log(CI) centered at sample mean so the level coefficient on
#    pair_exposure_EU × post is interpretable at average CI.
# ---------------------------------------------------------------------------
cat("\n=== HS6-CI continuous moderator (log CI, centered) ===\n")
in_sample <- bloc_yr[!is.na(carbon_intensity) & carbon_intensity > 0]
log_ci_mean <- mean(log(in_sample$carbon_intensity))
in_sample[, log_ci_c := log(carbon_intensity) - log_ci_mean]

m_cont <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:post +
                    pair_exposure_EU:post:log_ci_c +
                    pair_exposure_EU:year_centered |
                    vat^hs6 + hs6^year,
        data = in_sample, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) { cat("  error:", conditionMessage(e), "\n"); NULL })
if (!is.null(m_cont)) {
  ct <- as.data.table(coeftable(m_cont), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  ct[, n_obs := nobs(m_cont)]
  fwrite(ct, file.path(OUT_TAB, "phase6_b5_hs6ci_continuous.csv"))
  print(ct[, .(term, est, se, pval)])
}

# ---------------------------------------------------------------------------
# 6. Pre-MSR vs post-MSR cut
#    (a) Replace post(2015) with post_msr(2018)
#    (b) Both dummies in one regression: β_post is the 2015-17 effect,
#        β_postmsr is the *additional* 2018+ effect.
# ---------------------------------------------------------------------------
cat("\n=== Pre-MSR vs post-MSR (2018 cut) ===\n")

m_msr_only <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:post_msr + pair_exposure_EU:year_centered |
                    vat^hs6 + hs6^year,
        data = bloc_yr, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)

# Both post(2015) and post_msr(2018). β on post_msr is the differential
# 2018+ effect on top of the 2015-17 baseline.
m_both <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:post + pair_exposure_EU:post_msr +
                    pair_exposure_EU:year_centered |
                    vat^hs6 + hs6^year,
        data = bloc_yr, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)

rows_msr <- list(
  extract_row(m_baseline, "baseline_post2015",
              term_pat = "pair_exposure_EU:post$"),
  extract_row(m_msr_only, "post_msr_only",
              term_pat = "pair_exposure_EU:post_msr"),
  extract_row(m_both, "both_post2015",
              term_pat = "pair_exposure_EU:post$"),
  extract_row(m_both, "both_diff_postmsr",
              term_pat = "pair_exposure_EU:post_msr")
)
res_msr <- rbindlist(Filter(Negate(is.null), rows_msr), fill = TRUE)
if (nrow(res_msr)) {
  fwrite(res_msr, file.path(OUT_TAB, "phase6_b5_postmsr.csv"))
  print(res_msr[, .(label, term, est, se, pval, n_obs)])
}

# ---------------------------------------------------------------------------
# 7. Quartile plot
# ---------------------------------------------------------------------------
if (exists("res_q") && nrow(res_q) >= 4) {
  plot_dat <- res_q[grepl("^ci_Q[1-4]$", label)]
  if (nrow(plot_dat) >= 2) {
    plot_dat[, quartile := sub("^ci_", "", label)]
    plot_dat[, ci_lo := est - 1.96 * se]
    plot_dat[, ci_hi := est + 1.96 * se]
    g_q <- ggplot(plot_dat, aes(x = quartile, y = est)) +
      geom_hline(yintercept = 0, linetype = "dashed") +
      geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.15) +
      geom_point(size = 3) +
      labs(title = "B1 substitution by HS6 carbon-intensity quartile",
           subtitle = paste("β on pair_exposure_EU × post (2015), trend-corrected.",
                            "Q1 = lowest CI, Q4 = highest. 95% CIs."),
           x = "HS6 carbon-intensity quartile",
           y = expression(beta)) +
      theme_bw()
    ggsave(file.path(OUT_FIG, "phase6_b5_hs6ci_quartile.pdf"),
           g_q, width = 7, height = 5)
    cat(sprintf("\nFigure saved: %s\n",
                file.path(OUT_FIG, "phase6_b5_hs6ci_quartile.pdf")))
  }
}

cat("\n=== B5 done ===\n")
