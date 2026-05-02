# =============================================================================
# B1 + B2 (paper §5.2.2 / §5.2.3) — Buyer-supplier customs analysis with HTE.
#
# Test-H analog on customs: for each (Belgian importer × HS6 regulated product)
# cell with positive imports from at least one EU and one non-EU source in some
# pre-shock year, regress the importer's share-going-to-most-exposed-EU-source
# on (pair_exposure_EU × Post).
#
# Prerequisites: phase6_build_customs_panel_extended.R has been run, so
# customs_import_panel_extended.RData exists and covers 2000-2022 with both
# blocs. Falls back to customs_import_panel_regulated.RData (2000-2019) if the
# extended panel is unavailable; in that case horizons truncate at h = 4.
#
# Outputs:
#   ${OUT_TAB}/phase6_b1_buyer_supplier_levels.csv
#   ${OUT_TAB}/phase6_b2_horizon_lp.csv
#   ${OUT_TAB}/phase6_b2_quartile_split.csv
#   ${OUT_FIG}/phase6_b2_horizon_irf.pdf
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2)
})

ANCHOR  <- 2014L
H_LO <- -9L; H_HI <- +7L
NSHARE_LO <- 2010L; NSHARE_HI <- 2014L

OUT_TAB <- file.path(REPO_DIR, "output_local", "tables")
OUT_FIG <- file.path(REPO_DIR, "output_local", "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Load customs panel (prefer extended)
# ---------------------------------------------------------------------------
ext_path <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
if (file.exists(ext_path)) {
  load(ext_path); cat("Loaded extended customs panel.\n")
} else {
  cat("WARNING: extended panel not found; using 2000-2019 panel.\n")
  load(file.path(PROC_DATA, "customs_import_panel_regulated.RData"))
}
panel <- as.data.table(panel)
cat(sprintf("Customs rows: %d, year range %d-%d\n",
            nrow(panel), min(panel$year), max(panel$year)))

# Restrict to regulated products (the substitution margin we care about).
reg <- panel[is_regulated_product == 1L]

# Aggregate to (importer, HS6, source-bloc, year) — collapsing across
# countries within each bloc (EU vs. non-EU). Bloc = is_non_ets_country
# inverted: source_eu = 1 - is_non_ets_country.
reg[, source_eu := 1L - is_non_ets_country]
reg[, hs6 := substr(cn8, 1, 6)]

bloc <- reg[, .(value = sum(value, na.rm = TRUE)),
            by = .(vat, hs6, source_eu, year)]

# (importer × HS6) cells with positive imports from BOTH blocs in some
# pre-shock year — substitution-feasible cells.
pre <- bloc[year %between% c(NSHARE_LO, NSHARE_HI)]
fb <- pre[, .(any_eu = any(source_eu == 1L & value > 0),
              any_non = any(source_eu == 0L & value > 0)),
          by = .(vat, hs6)]
feasible <- fb[any_eu & any_non, .(vat, hs6)]
cat(sprintf("Feasible (importer × HS6) cells: %d\n", nrow(feasible)))

bloc <- merge(bloc, feasible, by = c("vat", "hs6"))

# ---------------------------------------------------------------------------
# 2. Build pair_exposure_EU = pre-shock EU share at the importer × HS6 level.
# ---------------------------------------------------------------------------
pre_total <- pre[, .(total_pre = sum(value, na.rm = TRUE)), by = .(vat, hs6)]
pre_eu    <- pre[source_eu == 1L,
                  .(eu_pre = sum(value, na.rm = TRUE)), by = .(vat, hs6)]
pe <- merge(pre_total, pre_eu, by = c("vat", "hs6"), all.x = TRUE)
pe[is.na(eu_pre), eu_pre := 0]
pe[, pair_exposure_EU := fifelse(total_pre > 0, eu_pre / total_pre, NA_real_)]

# Cell-year share-top: importer's share going to the EU bloc (collapse across
# multiple EU source countries; we treat the bloc as the comparable arm).
bloc_yr <- dcast(bloc, vat + hs6 + year ~ source_eu, value.var = "value",
                  fill = 0)
setnames(bloc_yr, c("0", "1"), c("non_eu", "eu"))
bloc_yr[, total := non_eu + eu]
bloc_yr[, share_eu := fifelse(total > 0, eu / total, NA_real_)]
bloc_yr <- merge(bloc_yr, pe[, .(vat, hs6, pair_exposure_EU)],
                 by = c("vat", "hs6"))
bloc_yr <- bloc_yr[!is.na(share_eu)]
bloc_yr[, post := as.integer(year >= 2015L)]

cat(sprintf("Cell-years for B1: %d\n", nrow(bloc_yr)))

# ---------------------------------------------------------------------------
# 3. B1 — Headline level regression
# ---------------------------------------------------------------------------
m_b1 <- tryCatch(
  feols(share_eu ~ pair_exposure_EU:post | vat^hs6 + hs6^year,
        data = bloc_yr, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_b1)) {
  ct <- as.data.table(coeftable(m_b1), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  fwrite(ct, file.path(OUT_TAB, "phase6_b1_buyer_supplier_levels.csv"))
  cat("B1 headline:\n"); print(ct[, .(est, se, pval)])
}

# ---------------------------------------------------------------------------
# 4. B2 — Horizon-h LP
# ---------------------------------------------------------------------------
H_HI_eff <- min(H_HI, max(bloc_yr$year) - ANCHOR)
bloc_yr[, year_f := factor(year, levels = (ANCHOR + H_LO):(ANCHOR + H_HI_eff))]
m_b2_hor <- tryCatch(
  feols(share_eu ~ i(year_f, pair_exposure_EU, ref = as.character(ANCHOR - 1L)) |
                    vat^hs6 + hs6^year,
        data = bloc_yr, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_b2_hor)) {
  ct <- as.data.table(coeftable(m_b2_hor), keep.rownames = "term")
  ct[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  ct[, h := year - ANCHOR]
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  hor <- ct[!is.na(h), .(h, est, se, tval, pval)]
  fwrite(hor, file.path(OUT_TAB, "phase6_b2_horizon_lp.csv"))

  hor[, ci_lo := est - 1.96 * se]; hor[, ci_hi := est + 1.96 * se]
  p <- ggplot(hor, aes(x = h, y = est, ymin = ci_lo, ymax = ci_hi)) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_vline(xintercept = 0, linetype = "dotted") +
    geom_ribbon(alpha = 0.2) + geom_line() + geom_point() +
    scale_x_continuous(breaks = seq(H_LO, H_HI_eff, 1)) +
    labs(title = "B2: customs buyer-supplier substitution, horizon LP",
         subtitle = sprintf("Reference year %d (cutoff = 2015). 95%% CIs.",
                            ANCHOR - 1L),
         x = "Horizon h", y = expression(gamma[h])) + theme_bw()
  ggsave(file.path(OUT_FIG, "phase6_b2_horizon_irf.pdf"),
         p, width = 8, height = 5)
}

# ---------------------------------------------------------------------------
# 5. B2 (b) — Quartile split on pair_exposure_EU
# ---------------------------------------------------------------------------
qs <- quantile(unique(bloc_yr[, .(vat, hs6, pair_exposure_EU)])$pair_exposure_EU,
               c(0.25, 0.5, 0.75), na.rm = TRUE)
cat("\npair_exposure_EU quartile cutpoints:\n"); print(round(qs, 4))

bloc_yr[, exp_q := fcase(
  pair_exposure_EU <  qs[1], "Q1",
  pair_exposure_EU <  qs[2], "Q2",
  pair_exposure_EU <  qs[3], "Q3",
  pair_exposure_EU >= qs[3], "Q4",
  default = NA_character_)]

results <- list()
for (q in c("Q1", "Q2", "Q3", "Q4", "all")) {
  sub <- if (q == "all") bloc_yr else bloc_yr[exp_q == q]
  m <- tryCatch(
    feols(share_eu ~ pair_exposure_EU:post | vat^hs6 + hs6^year,
          data = sub, cluster = c("vat", "hs6"), notes = FALSE),
    error = function(e) NULL)
  if (!is.null(m)) {
    ct <- as.data.table(coeftable(m), keep.rownames = "term")
    setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
             c("est", "se", "tval", "pval"))
    ct[, quartile := q]
    results[[q]] <- ct[, .(quartile, term, est, se, tval, pval)]
  }
}
if (length(results) > 0L) {
  out_q <- rbindlist(results)
  fwrite(out_q, file.path(OUT_TAB, "phase6_b2_quartile_split.csv"))
  print(out_q)
}
