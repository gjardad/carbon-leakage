# =============================================================================
# Trend-corrected Test H (paper §5.1.1) — belt-and-braces analog of
# phase6_b1_corrected.R for the within-NACE-4d, across-supplier
# specification.
#
# Motivation. Test H's pre-trend has been tested via the augmented
# specification that adds `pair_exposure × year_centered` on the UP4 sample
# (trend slope = -3.12/year, s.e. 3.90, p = 0.42 — flat). We expect the
# trend-corrected β on the firm-cost-share regressor to be essentially
# unchanged from the naive β. This script confirms it directly.
#
# After the B1 finding (where the trend control flipped β from +0.033 to
# -0.560), it's worth running the same side-by-side comparison on Test H
# even though the existing test suggests it'll be a non-event.
#
# Spec.
#   share_top_{b,n,t}
#     = β · fcs_j_star_{b,n} × Post_t
#     + γ · fcs_j_star_{b,n} × year_centered_t   (NEW: trend control)
#     + α_{b,n} (cell FE) + δ_{n,t} (sector × year FE) + ε
#
# Same panel construction as phase5_test_h_most_exposed_ets_supplier.R
# (samp_ab — j* active during its tenure window). Same cluster (buyer).
#
# Outputs:
#   ${OUT_TAB}/phase6_test_h_corrected.csv        — naive / trend-corrected
#                                                    / shorter / shorter+trend
#   ${OUT_TAB}/phase6_test_h_eventstudy_naive.csv
#   ${OUT_TAB}/phase6_test_h_eventstudy_detrended.csv
#   ${OUT_FIG}/phase6_test_h_eventstudy_naive.pdf
#   ${OUT_FIG}/phase6_test_h_eventstudy_detrended.pdf
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2)
})

YEAR_LO   <- 2005L
YEAR_HI   <- 2022L
POST_FROM <- 2015L
ANCHOR    <- 2014L
H_LO      <- -9L
H_HI      <- +7L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Replicate samp_ab from phase5_test_h_most_exposed_ets_supplier.R
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)[, .(seller = vat_i_ano,
                                                  buyer = vat_j_ano,
                                                  year,
                                                  corr_sales = corr_sales_ij)]
rm(df_b2b_selected_sample)
b2b[, year := as.integer(year)]
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(corr_sales) & corr_sales > 0]

load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_more_selected_sample)[
  , .(vat = vat_ano, year, nace5d)]
rm(df_annual_accounts_more_selected_sample)
aa[, year := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa <- unique(aa[, .(vat, year, nace4d)])

seller_nace <- copy(aa); setnames(seller_nace, c("vat", "nace4d"),
                                  c("seller", "seller_nace4d"))
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]

# ETS roster + firm cost share
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
b2b <- b2b[!(seller %in% contaminated_vats & year >= 2021L)]

load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
b2b <- merge(b2b,
             cost_share_regressor[, .(seller = vat,
                                       fcs_reg = firm_cost_share_regressor)],
             by = "seller", all.x = TRUE)
b2b[is.na(fcs_reg), fcs_reg := 0]
ets_with_fcs <- cost_share_regressor$vat
b2b <- b2b[!(seller_is_ets == 1L & !(seller %in% ets_with_fcs))]

# Cell-year aggregation
setkey(b2b, buyer, seller_nace4d, year)
cell_yr <- b2b[, .(n_active_sellers = .N,
                   n_ets_sellers    = sum(seller_is_ets == 1L),
                   total_sales_cell = sum(corr_sales)),
               by = .(buyer, seller_nace4d, year)]

# Identify j* per cell (max-fcs ETS seller ever active in cell)
ets_in_cell <- unique(b2b[seller_is_ets == 1L,
                          .(buyer, seller_nace4d, seller, fcs_reg)])
setorder(ets_in_cell, buyer, seller_nace4d, -fcs_reg, seller)
j_star <- ets_in_cell[, .SD[1L], by = .(buyer, seller_nace4d)]
setnames(j_star, c("seller", "fcs_reg"), c("j_star", "fcs_j_star"))

j_star_b2b <- merge(b2b[, .(buyer, seller_nace4d, year, seller, corr_sales)],
                    j_star, by = c("buyer", "seller_nace4d"))
j_star_b2b <- j_star_b2b[seller == j_star]
j_window <- j_star_b2b[, .(t_first_j_star = min(year),
                            t_last_j_star  = max(year),
                            n_years_j_star_active = uniqueN(year)),
                       by = .(buyer, seller_nace4d, j_star, fcs_j_star)]
j_window[, is_type_a := as.integer(
  t_first_j_star == YEAR_LO &
  t_last_j_star  == YEAR_HI &
  n_years_j_star_active == (YEAR_HI - YEAR_LO + 1L))]

j_star_sales <- j_star_b2b[, .(buyer, seller_nace4d, year,
                                corr_sales_j_star = corr_sales)]
setkey(j_star_sales, buyer, seller_nace4d, year)

panel <- cell_yr[n_active_sellers >= 2L]
panel <- merge(panel, j_window, by = c("buyer", "seller_nace4d"))
panel <- merge(panel, j_star_sales,
               by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
panel[is.na(corr_sales_j_star), corr_sales_j_star := 0]
panel[, share_top := corr_sales_j_star / total_sales_cell]

# samp_ab: spec (a+b) — j* active during its tenure window
samp_ab <- panel[is_type_a == 1L |
                   (year >= t_first_j_star & year <= t_last_j_star)]

samp_ab[, post := as.integer(year >= POST_FROM)]
samp_ab[, year_centered := year - ANCHOR]
samp_ab[, cell      := paste(buyer, seller_nace4d, sep = "_")]
samp_ab[, sn4d_year := paste(seller_nace4d, year, sep = "_")]

cat(sprintf("Test H sample: %d cell-years across %d cells\n",
            nrow(samp_ab), uniqueN(samp_ab[, .(buyer, seller_nace4d)])))

# ---------------------------------------------------------------------------
# 2. Four side-by-side specifications
# ---------------------------------------------------------------------------
specs <- list()

# (a) Naive Test H (no trend control, fcs_j_star × Post).
m_naive <- tryCatch(
  feols(share_top ~ fcs_j_star:post | cell + sn4d_year,
        data = samp_ab, cluster = ~ buyer, notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_naive)) {
  ct <- as.data.table(coeftable(m_naive), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("estimate", "se", "tval", "pval"))
  ct[, spec := "naive (no trend control)"]
  specs[["naive"]] <- ct
}

# (b) Trend-corrected.
m_trend <- tryCatch(
  feols(share_top ~ fcs_j_star:post + fcs_j_star:year_centered |
                     cell + sn4d_year,
        data = samp_ab, cluster = ~ buyer, notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_trend)) {
  ct <- as.data.table(coeftable(m_trend), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"), c("estimate", "se", "tval", "pval"))
  ct[, spec := "trend-corrected"]
  specs[["trend"]] <- ct
}

# (c) Shorter pre-period (2010+).
sub <- samp_ab[year %between% c(2010L, max(samp_ab$year))]
m_short <- tryCatch(
  feols(share_top ~ fcs_j_star:post | cell + sn4d_year,
        data = sub, cluster = ~ buyer, notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_short)) {
  ct <- as.data.table(coeftable(m_short), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"), c("estimate", "se", "tval", "pval"))
  ct[, spec := "shorter pre-period (2010+)"]
  specs[["short"]] <- ct
}

# (d) Shorter + trend.
m_short_trend <- tryCatch(
  feols(share_top ~ fcs_j_star:post + fcs_j_star:year_centered |
                     cell + sn4d_year,
        data = sub, cluster = ~ buyer, notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_short_trend)) {
  ct <- as.data.table(coeftable(m_short_trend), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"), c("estimate", "se", "tval", "pval"))
  ct[, spec := "shorter + trend"]
  specs[["short_trend"]] <- ct
}

results <- rbindlist(specs, use.names = TRUE, fill = TRUE)
fwrite(results, file.path(OUT_TAB, "phase6_test_h_corrected.csv"))
cat("\nTest H specifications side-by-side:\n")
print(results[, .(spec, term, estimate, se, pval)])

# ---------------------------------------------------------------------------
# 3. Naive event study (with red dotted line = pre-period linear extrapolation)
# ---------------------------------------------------------------------------
H_HI_eff <- min(H_HI, max(samp_ab$year) - ANCHOR)
H_LO_eff <- max(H_LO, min(samp_ab$year) - ANCHOR)
samp_ab[, year_f := factor(year, levels = (ANCHOR + H_LO_eff):(ANCHOR + H_HI_eff))]

extract_es_table <- function(m) {
  ct <- as.data.table(coeftable(m), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  ct[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  ct[, h := year - ANCHOR]
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
    g <- g + geom_abline(slope = slope_overlay, intercept = 0,
                         linetype = "dotted", color = "red")
  }
  g
}

m_es_naive <- tryCatch(
  feols(share_top ~ i(year_f, fcs_j_star, ref = as.character(ANCHOR - 1L)) |
                     cell + sn4d_year,
        data = samp_ab, cluster = ~ buyer, notes = FALSE),
  error = function(e) NULL)

if (!is.null(m_es_naive)) {
  out_es_naive <- extract_es_table(m_es_naive)
  fwrite(out_es_naive, file.path(OUT_TAB, "phase6_test_h_eventstudy_naive.csv"))
  pre_h <- out_es_naive[h < 0]
  trend_fit <- lm(est ~ h, data = pre_h, weights = 1 / pre_h$se^2)
  pre_slope <- coef(trend_fit)["h"]
  g_naive <- plot_es(out_es_naive,
    title = "Test H event study, naive (no pre-trend control)",
    subtitle = sprintf("Reference year %d. 95%% CIs. Red dotted = linear pre-trend extrapolation (slope %.3f).",
                       ANCHOR - 1L, pre_slope),
    slope_overlay = pre_slope)
  ggsave(file.path(OUT_FIG, "phase6_test_h_eventstudy_naive.pdf"),
         g_naive, width = 10, height = 5)
}

# ---------------------------------------------------------------------------
# 4. De-trended event study
# ---------------------------------------------------------------------------
pre_only <- samp_ab[year <= ANCHOR]
m_pre_trend <- tryCatch(
  feols(share_top ~ fcs_j_star:year_centered | cell + sn4d_year,
        data = pre_only, cluster = ~ buyer, notes = FALSE),
  error = function(e) NULL)

if (!is.null(m_pre_trend)) {
  gamma_pre <- coef(m_pre_trend)["fcs_j_star:year_centered"]
  cat(sprintf("\nPre-period linear-trend slope (γ̂_pre) = %.4f per year\n",
              gamma_pre))

  samp_ab[, share_top_detrended := share_top - gamma_pre * fcs_j_star * year_centered]

  m_es_det <- tryCatch(
    feols(share_top_detrended ~ i(year_f, fcs_j_star, ref = as.character(ANCHOR - 1L)) |
                                 cell + sn4d_year,
          data = samp_ab, cluster = ~ buyer, notes = FALSE),
    error = function(e) NULL)

  if (!is.null(m_es_det)) {
    out_es_det <- extract_es_table(m_es_det)
    fwrite(out_es_det, file.path(OUT_TAB, "phase6_test_h_eventstudy_detrended.csv"))
    g_det <- plot_es(out_es_det,
      title = "Test H event study, de-trended (pre-period linear trend subtracted)",
      subtitle = sprintf("Reference year %d. 95%% CIs. Outcome residualized; trend slope %.4f estimated on pre-period only.",
                         ANCHOR - 1L, gamma_pre))
    ggsave(file.path(OUT_FIG, "phase6_test_h_eventstudy_detrended.pdf"),
           g_det, width = 10, height = 5)
  }
}
