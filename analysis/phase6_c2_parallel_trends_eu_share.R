# =============================================================================
# C2 (paper §5.2.7) — Parallel-trends investigation for the EU-share increase
#
# B1 found that EU-share goes UP for EU-dependent buyers post-2015 (β > 0).
# This is wrong-signed for substitution toward non-EU sources, which would be
# the leakage prediction. Two interpretations:
#
#   (a) Causal: Belgian buyers consolidate to EU sources because the EU ETS
#       affects all EU producers symmetrically and intra-EU trade is
#       cheaper/faster than non-EU sourcing.
#
#   (b) Confounding: a pre-existing trend toward EU consolidation (Brexit
#       2016+, post-Covid supply-chain shortening 2020+, EU enlargement
#       absorption) is mistaken for a 2015-policy effect.
#
# We test (a) vs (b) with three diagnostics:
#
#   1. Pre-trend regression: regress share_eu on (pair_exposure_EU × year)
#      over 2000-2014 only. A non-zero pre-trend coefficient suggests the
#      effect we attribute to 2015 is a continuation of a pre-existing trend.
#
#   2. Event-study with full set of leads: plot year-by-year coefficients
#      with reference 2014. If pre-period coefficients (2000-2013) trend
#      toward the post-2015 sign, parallel-trends fails.
#
#   3. Trends-in-treated test: Pre-period interaction with linear time trend
#      vs. just intercept-shifted comparison.
#
#   4. Decomposition by exposure quartile: plot raw share_eu trajectories
#      separately for Q1/Q2/Q3/Q4 of pair_exposure_EU. If the post-2015
#      uptick is sharp and absent pre-2015, the causal reading is supported;
#      if it's gradual and continues a pre-existing trend, confounding is
#      more plausible.
#
# Outputs:
#   ${OUT_TAB}/phase6_c2_pre_trend_test.csv
#   ${OUT_TAB}/phase6_c2_eventstudy.csv
#   ${OUT_FIG}/phase6_c2_eventstudy.pdf
#   ${OUT_FIG}/phase6_c2_quartile_trajectories.pdf
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

OUT_TAB <- file.path(REPO_DIR, "output_local", "tables")
OUT_FIG <- file.path(REPO_DIR, "output_local", "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Build the same C2 dataset as B1 (importer × HS6 × year, with bloc shares
#    and pre-shock pair_exposure_EU).
# ---------------------------------------------------------------------------
ext_path <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
if (file.exists(ext_path)) {
  load(ext_path)
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

cat(sprintf("Sample: %d cell-years\n", nrow(bloc_yr)))

# ---------------------------------------------------------------------------
# 2. Pre-trend regression on 2000-2014 only.
# ---------------------------------------------------------------------------
pre_only <- bloc_yr[year %between% c(2000L, 2014L)]
pre_only[, year_centered := year - 2014L]

m_pretrend <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:year_centered |
                    vat^hs6 + hs6^year,
        data = pre_only, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) { cat("ERROR:", conditionMessage(e), "\n"); NULL })
if (!is.null(m_pretrend)) {
  ct <- as.data.table(coeftable(m_pretrend), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  fwrite(ct, file.path(OUT_TAB, "phase6_c2_pre_trend_test.csv"))
  cat("Pre-trend test (2000-2014):\n"); print(ct[, .(est, se, pval)])
  if (nrow(ct) > 0L && abs(ct$est[1]) / max(ct$se[1], 1e-9) > 1.96) {
    cat("WARNING: pre-trend is statistically significant. Causal reading of B1 is suspect.\n")
  }
}

# ---------------------------------------------------------------------------
# 3. Event study with full set of leads.
# ---------------------------------------------------------------------------
H_HI_eff <- min(H_HI, max(bloc_yr$year) - ANCHOR)
H_LO_eff <- max(H_LO, min(bloc_yr$year) - ANCHOR)
bloc_yr[, year_f := factor(year, levels = (ANCHOR + H_LO_eff):(ANCHOR + H_HI_eff))]

m_es <- tryCatch(
  feols(share_eu ~ i(year_f, pair_exposure_EU, ref = as.character(ANCHOR - 1L)) |
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
  fwrite(out_es, file.path(OUT_TAB, "phase6_c2_eventstudy.csv"))

  out_es[, ci_lo := est - 1.96 * se]; out_es[, ci_hi := est + 1.96 * se]
  p <- ggplot(out_es, aes(x = h, y = est, ymin = ci_lo, ymax = ci_hi)) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_vline(xintercept = 0, linetype = "dotted") +
    geom_ribbon(alpha = 0.2) + geom_line() + geom_point() +
    scale_x_continuous(breaks = seq(H_LO_eff, H_HI_eff, 2)) +
    labs(title = "C2: EU-share event study, full leads (2000-)",
         subtitle = sprintf("Reference year %d. 95%% CIs.", ANCHOR - 1L),
         x = "Horizon h", y = expression(gamma[h])) + theme_bw()
  ggsave(file.path(OUT_FIG, "phase6_c2_eventstudy.pdf"), p, width = 10, height = 5)
}

# ---------------------------------------------------------------------------
# 4. Quartile trajectories: raw share_eu mean per year by exposure quartile.
# ---------------------------------------------------------------------------
qs <- quantile(unique(bloc_yr[, .(vat, hs6, pair_exposure_EU)])$pair_exposure_EU,
               c(0.25, 0.5, 0.75), na.rm = TRUE)
bloc_yr[, exp_q := fcase(
  pair_exposure_EU <  qs[1], "Q1 (least EU)",
  pair_exposure_EU <  qs[2], "Q2",
  pair_exposure_EU <  qs[3], "Q3",
  pair_exposure_EU >= qs[3], "Q4 (most EU)",
  default = NA_character_)]

traj <- bloc_yr[!is.na(exp_q),
                 .(mean_share_eu = mean(share_eu, na.rm = TRUE),
                   se_share_eu = sd(share_eu, na.rm = TRUE) / sqrt(.N),
                   n = .N),
                 by = .(year, exp_q)]
traj[, ci_lo := mean_share_eu - 1.96 * se_share_eu]
traj[, ci_hi := mean_share_eu + 1.96 * se_share_eu]

p <- ggplot(traj, aes(x = year, y = mean_share_eu, ymin = ci_lo, ymax = ci_hi,
                       color = exp_q, fill = exp_q)) +
  geom_vline(xintercept = 2014.5, linetype = "dotted") +
  geom_ribbon(alpha = 0.15, color = NA) + geom_line() + geom_point() +
  labs(title = "C2: raw share_eu trajectories by pre-shock pair_exposure_EU quartile",
       subtitle = "Vertical line = 2015 cutoff. Quartile splits are time-invariant (pre-shock).",
       x = "Year", y = expression("Mean share_eu (within quartile)"),
       color = "Quartile", fill = "Quartile") + theme_bw()
ggsave(file.path(OUT_FIG, "phase6_c2_quartile_trajectories.pdf"),
       p, width = 10, height = 6)
fwrite(traj, file.path(OUT_TAB, "phase6_c2_quartile_trajectories.csv"))
cat("Wrote phase6_c2_* outputs.\n")
