# =============================================================================
# B1 corrected — addresses the pre-trend identified in phase6_c2.
#
# C2 found a strong pre-trend on the EU-share regression (β = +0.073/year,
# p < 10^-50 on local-1). The naive B1 specification:
#
#     share_eu_{f,p,t} = β · pair_exposure_EU × Post + α_{f,p} + δ_{p,t} + ε
#
# attributes the pre-existing trend to the post-2015 dummy, generating a
# spuriously positive β. We address this with two corrections:
#
#   (1) Linear-trend control:
#       Add pair_exposure_EU × year_centered as a continuous control. The
#       remaining β identifies the LEVEL SHIFT at 2015 net of any linear
#       trend that was already in motion. This is the same correction Test H
#       used in the within-country setting (where the trend was
#       insignificant; here it is large).
#
#   (2) Shorter pre-period:
#       Restrict to 2010-2022 only. This drops the early-2000s and
#       financial-crisis years where the pre-trend is most pronounced and
#       is plausibly driven by EU enlargement absorption (2004, 2007 waves).
#
# Outputs:
#   ${OUT_TAB}/phase6_b1_corrected.csv  — naive vs. trend-corrected vs.
#                                          shorter-window estimates
#   ${OUT_TAB}/phase6_b1_corrected_eventstudy.csv  — event study with the
#                                          trend-detrended specification
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2)
})

ANCHOR  <- 2014L
H_LO <- -14L; H_HI <- +7L
NSHARE_LO <- 2010L; NSHARE_HI <- 2014L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Build same panel as B1 (importer × HS6 × bloc × year, with shares and
#    pre-shock pair_exposure_EU)
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
fb <- pre[, .(any_eu = any(source_eu == 1L & value > 0),
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
bloc_yr[, post := as.integer(year >= 2015L)]
bloc_yr[, year_centered := year - ANCHOR]

cat(sprintf("Sample: %d cell-years\n", nrow(bloc_yr)))

# ---------------------------------------------------------------------------
# 2. Three specifications
# ---------------------------------------------------------------------------
specs <- list()

# (a) Naive B1 (no pre-trend control).
m_naive <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:post | vat^hs6 + hs6^year,
        data = bloc_yr, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_naive)) {
  ct <- as.data.table(coeftable(m_naive), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  ct[, spec := "naive (no trend control)"]
  specs[["naive"]] <- ct
}

# (b) Trend-corrected: pair_exposure × year_centered as a continuous control.
#     β on pair_exposure × Post identifies the LEVEL SHIFT net of the
#     pre-existing linear trend.
m_trend <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:post + pair_exposure_EU:year_centered |
                    vat^hs6 + hs6^year,
        data = bloc_yr, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_trend)) {
  ct <- as.data.table(coeftable(m_trend), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  ct[, spec := "trend-corrected"]
  specs[["trend"]] <- ct
}

# (c) Shorter pre-period (2010-2022).
sub <- bloc_yr[year %between% c(2010L, max(bloc_yr$year))]
m_short <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:post | vat^hs6 + hs6^year,
        data = sub, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_short)) {
  ct <- as.data.table(coeftable(m_short), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  ct[, spec := "shorter pre-period (2010+)"]
  specs[["short"]] <- ct
}

# (d) Trend-corrected on shorter pre-period (belt-and-braces).
m_short_trend <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:post + pair_exposure_EU:year_centered |
                    vat^hs6 + hs6^year,
        data = sub, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_short_trend)) {
  ct <- as.data.table(coeftable(m_short_trend), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  ct[, spec := "shorter + trend"]
  specs[["short_trend"]] <- ct
}

results <- rbindlist(specs, use.names = TRUE, fill = TRUE)
fwrite(results, file.path(OUT_TAB, "phase6_b1_corrected.csv"))
cat("\nB1 specifications side-by-side:\n")
print(results[, .(spec, term, est, se, pval)])

# ---------------------------------------------------------------------------
# 3. Detrended event study: residualize share_eu against pair_exposure × year
#    on 2000-2014 only, then plot post-period coefficients
# ---------------------------------------------------------------------------
H_HI_eff <- min(H_HI, max(bloc_yr$year) - ANCHOR)
H_LO_eff <- max(H_LO, min(bloc_yr$year) - ANCHOR)
bloc_yr[, year_f := factor(year, levels = (ANCHOR + H_LO_eff):(ANCHOR + H_HI_eff))]

# Event study with trend-detrending: include pair_exposure × year_centered as
# a continuous control, identifying year-by-year deviations from the linear
# trend.
m_es <- tryCatch(
  feols(share_eu ~ i(year_f, pair_exposure_EU, ref = as.character(ANCHOR - 1L)) +
                    pair_exposure_EU:year_centered |
                    vat^hs6 + hs6^year,
        data = bloc_yr, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_es)) {
  ct_es <- as.data.table(coeftable(m_es), keep.rownames = "term")
  ct_es[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  ct_es[, h := year - ANCHOR]
  setnames(ct_es, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  out_es <- ct_es[!is.na(h), .(h, est, se, tval, pval)]
  fwrite(out_es, file.path(OUT_TAB, "phase6_b1_corrected_eventstudy.csv"))

  out_es[, ci_lo := est - 1.96 * se]; out_es[, ci_hi := est + 1.96 * se]
  p <- ggplot(out_es, aes(x = h, y = est, ymin = ci_lo, ymax = ci_hi)) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_vline(xintercept = 0, linetype = "dotted") +
    geom_ribbon(alpha = 0.2) + geom_line() + geom_point() +
    scale_x_continuous(breaks = seq(H_LO_eff, H_HI_eff, 2)) +
    labs(title = "B1 corrected: trend-detrended event study",
         subtitle = sprintf("Reference year %d. 95%% CIs. Pre-existing linear trend partialled out.",
                            ANCHOR - 1L),
         x = "Horizon h", y = expression(gamma[h])) + theme_bw()
  ggsave(file.path(OUT_FIG, "phase6_b1_corrected_eventstudy.pdf"),
         p, width = 10, height = 5)
}
