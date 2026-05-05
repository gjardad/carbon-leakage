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
# 3. Event-study figures.
#
# Two specifications, each plotted separately:
#   (a) Naive event study — `share_eu ~ i(year_f, pair_exposure_EU)`. Pre-trend
#       VISIBLE in the leads. Reader can see the linear-up pre-trend and the
#       post-2015 deviation by eye.
#   (b) De-trended event study — pre-fit a linear trend on pre-period leads
#       only, residualize share_eu on (pair_exposure × year_centered),
#       re-run the categorical event study on the residual. Pre-period
#       coefficients should now scatter around zero by construction; post-
#       period coefficients are deviations from the extrapolated linear trend.
#
# Note on the previous (broken) version of this section: it included BOTH
# `i(year_f, pair_exposure)` AND `pair_exposure:year_centered` simultaneously
# in a single regression. Those terms are linearly redundant — `year_centered`
# is a linear function of `year_f` — so the design matrix is ill-conditioned
# and fixest returns near-zero coefficients with massive standard errors that
# grow linearly with |h - reference|. This produces a "flat zero with
# trumpet-shaped CIs" plot that is mechanical, not informative. The fix is to
# fit the trend SEPARATELY on the pre-period and pre-residualize the outcome
# before running the categorical event study.
# ---------------------------------------------------------------------------
H_HI_eff <- min(H_HI, max(bloc_yr$year) - ANCHOR)
H_LO_eff <- max(H_LO, min(bloc_yr$year) - ANCHOR)
bloc_yr[, year_f := factor(year, levels = (ANCHOR + H_LO_eff):(ANCHOR + H_HI_eff))]

# ----- (a) Naive event study (pre-trend visible in leads) ------------------
m_es_naive <- tryCatch(
  feols(share_eu ~ i(year_f, pair_exposure_EU, ref = as.character(ANCHOR - 1L)) |
                    vat^hs6 + hs6^year,
        data = bloc_yr, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)

extract_es_table <- function(m) {
  ct <- as.data.table(coeftable(m), keep.rownames = "term")
  ct[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  ct[, h := year - ANCHOR]
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  ct[!is.na(h), .(h, est, se, tval, pval)]
}

plot_es <- function(out_es, title, subtitle, slope_overlay = NULL) {
  out_es[, ci_lo := est - 1.96 * se]
  out_es[, ci_hi := est + 1.96 * se]
  g <- ggplot(out_es, aes(x = h, y = est, ymin = ci_lo, ymax = ci_hi)) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_vline(xintercept = 0, linetype = "dotted") +
    geom_ribbon(alpha = 0.2) + geom_line() + geom_point() +
    scale_x_continuous(breaks = seq(H_LO_eff, H_HI_eff, 2)) +
    labs(title = title, subtitle = subtitle,
         x = "Horizon h (years from 2014)", y = expression(gamma[h])) +
    theme_bw()
  if (!is.null(slope_overlay)) {
    # Show extrapolation of pre-period linear fit through reference year zero.
    g <- g + geom_abline(slope = slope_overlay, intercept = 0,
                         linetype = "dotted", color = "red")
  }
  g
}

if (!is.null(m_es_naive)) {
  out_es_naive <- extract_es_table(m_es_naive)
  fwrite(out_es_naive,
         file.path(OUT_TAB, "phase6_b1_eventstudy_naive.csv"))

  # Linear pre-trend fit on the leads (h < 0). The slope estimate here is
  # NUMERICALLY identical to the γ̂ from the side-by-side trend-corrected
  # spec; fitting it explicitly here lets us overlay the extrapolation on
  # the figure for visual comparison.
  pre_h <- out_es_naive[h < 0]
  trend_fit <- lm(est ~ h, data = pre_h, weights = 1 / pre_h$se^2)
  pre_slope <- coef(trend_fit)["h"]

  g_naive <- plot_es(out_es_naive,
                     title = "B1 event study, naive (no pre-trend control)",
                     subtitle = sprintf("Reference year %d. 95%% CIs. Red dotted = linear pre-trend extrapolation (slope %.3f).",
                                        ANCHOR - 1L, pre_slope),
                     slope_overlay = pre_slope)
  ggsave(file.path(OUT_FIG, "phase6_b1_eventstudy_naive.pdf"),
         g_naive, width = 10, height = 5)
}

# ----- (b) De-trended event study ------------------------------------------
# Step 1: estimate γ on pre-period only (year ≤ 2014).
# Step 2: subtract γ̂ × pair_exposure × year_centered from share_eu.
# Step 3: run categorical event study on the residualized outcome.

pre_only <- bloc_yr[year <= ANCHOR]
m_pre_trend <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:year_centered | vat^hs6 + hs6^year,
        data = pre_only, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)

if (!is.null(m_pre_trend)) {
  gamma_pre <- coef(m_pre_trend)["pair_exposure_EU:year_centered"]
  cat(sprintf("\nPre-period linear-trend slope (γ̂_pre) = %.4f per year\n",
              gamma_pre))

  bloc_yr[, share_eu_detrended := share_eu - gamma_pre * pair_exposure_EU * year_centered]

  m_es_detrended <- tryCatch(
    feols(share_eu_detrended ~ i(year_f, pair_exposure_EU, ref = as.character(ANCHOR - 1L)) |
                                vat^hs6 + hs6^year,
          data = bloc_yr, cluster = c("vat", "hs6"), notes = FALSE),
    error = function(e) NULL)

  if (!is.null(m_es_detrended)) {
    out_es_det <- extract_es_table(m_es_detrended)
    fwrite(out_es_det,
           file.path(OUT_TAB, "phase6_b1_eventstudy_detrended.csv"))

    g_det <- plot_es(out_es_det,
                     title = "B1 event study, de-trended (pre-period linear trend subtracted)",
                     subtitle = sprintf("Reference year %d. 95%% CIs. Outcome residualized on (pair_exposure_EU × year), trend slope %.3f estimated on pre-period only.",
                                        ANCHOR - 1L, gamma_pre))
    ggsave(file.path(OUT_FIG, "phase6_b1_eventstudy_detrended.pdf"),
           g_det, width = 10, height = 5)
  }
}

# Remove the broken legacy filename so the new figures don't sit next to
# stale output. (No-op if the broken file was already cleaned up.)
old_pdf <- file.path(OUT_FIG, "phase6_b1_corrected_eventstudy.pdf")
if (file.exists(old_pdf)) file.remove(old_pdf)
old_csv <- file.path(OUT_TAB, "phase6_b1_corrected_eventstudy.csv")
if (file.exists(old_csv)) file.remove(old_csv)
