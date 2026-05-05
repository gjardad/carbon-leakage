# =============================================================================
# A3 + A4 (paper §5.1.6 / §5.1.7) — Phase II event-study with 2008 cutoff and
# horizon-h LP for short-run vs long-run effects.
#
# Prerequisites: phase6_attach_firm_cost_share_phase2.R has been run, so
# firm_cost_share_flavors.RData contains cost_share_regressor_phase2.
#
# Specification: same Test H and Test I structure as the headline 2015-cutoff
# specs but with cutoff = 2008 and the Phase II regressor.
#
# A3 = level event-study (Test H + Test I form)
# A4 = horizon-h LP, h ∈ {0, ..., 11} years post-2008
#
# Sample window: 2003-2019 to keep a clean window away from the post-2019
# Covid + Phase IV contamination.
#
# Outputs:
#   ${OUT_TAB}/phase6_a3_phase2_test_h_levels.csv
#   ${OUT_TAB}/phase6_a3_phase2_test_i_levels.csv
#   ${OUT_TAB}/phase6_a4_phase2_test_h_horizon.csv
#   ${OUT_TAB}/phase6_a4_phase2_test_i_horizon.csv
#   ${OUT_FIG}/phase6_a4_phase2_horizon_irf.pdf
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2)
})

YEAR_LO <- 2003L; YEAR_HI <- 2019L
ANCHOR  <- 2007L                 # year before the 2008 cutoff
H_LO <- -4L; H_HI <- +11L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Load B2B + Phase II cost share
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)[, .(seller = vat_i_ano,
                                                  buyer  = vat_j_ano,
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

load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
if (!exists("cost_share_regressor_phase2")) {
  stop("cost_share_regressor_phase2 not found. Run phase6_attach_firm_cost_share_phase2.R first.")
}
b2b <- merge(b2b,
             cost_share_regressor_phase2[, .(seller = vat,
                                              fcs_p2 = firm_cost_share_regressor_phase2)],
             by = "seller", all.x = TRUE)
b2b[is.na(fcs_p2), fcs_p2 := 0]

# ---------------------------------------------------------------------------
# 2. Test H Phase II: build cell panel and run level + horizon LP
# ---------------------------------------------------------------------------
cell_yr <- b2b[, .(n_active = .N,
                   n_ets = sum(seller_is_ets == 1L),
                   total_sales = sum(corr_sales)),
               by = .(buyer, seller_nace4d, year)]

ets_in_cell <- unique(b2b[seller_is_ets == 1L,
                          .(buyer, seller_nace4d, seller, fcs_p2)])
setorder(ets_in_cell, buyer, seller_nace4d, -fcs_p2, seller)
j_star <- ets_in_cell[, .SD[1L], by = .(buyer, seller_nace4d)]
setnames(j_star, c("seller", "fcs_p2"), c("j_star", "fcs_j_star"))

j_star_b2b <- merge(b2b[, .(buyer, seller_nace4d, year, seller, corr_sales)],
                    j_star, by = c("buyer", "seller_nace4d"))
j_star_b2b <- j_star_b2b[seller == j_star]
j_star_sales <- j_star_b2b[, .(buyer, seller_nace4d, year,
                                corr_sales_j_star = corr_sales)]

panel_h <- cell_yr[n_active >= 2L]
panel_h <- merge(panel_h, j_star, by = c("buyer", "seller_nace4d"))
panel_h <- merge(panel_h, j_star_sales,
                 by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
panel_h[is.na(corr_sales_j_star), corr_sales_j_star := 0]
panel_h[, share_top := 100 * corr_sales_j_star / total_sales]
panel_h[, post := as.integer(year >= 2008L)]

cat(sprintf("Test H Phase II: %d cells x years (n_cells = %d)\n",
            nrow(panel_h), uniqueN(panel_h[, .(buyer, seller_nace4d)])))

# Level (Phase II Test H).
m_h_lvl <- tryCatch(feols(share_top ~ fcs_j_star:post | buyer^seller_nace4d + seller_nace4d^year,
                           data = panel_h,
                           cluster = c("buyer", "seller_nace4d"), notes = FALSE),
                    error = function(e) NULL)
if (!is.null(m_h_lvl)) {
  ct <- as.data.table(coeftable(m_h_lvl), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  fwrite(ct, file.path(OUT_TAB, "phase6_a3_phase2_test_h_levels.csv"))
  cat("Phase II Test H level: ", capture.output(print(ct[, .(est, se, pval)])), "\n")
}

# Horizon LP (Phase II Test H).
panel_h[, year_f := factor(year, levels = (ANCHOR + H_LO):(ANCHOR + H_HI))]
m_h_hor <- tryCatch(
  feols(share_top ~ i(year_f, fcs_j_star, ref = as.character(ANCHOR)) |
                      buyer^seller_nace4d + seller_nace4d^year,
        data = panel_h, cluster = c("buyer", "seller_nace4d"), notes = FALSE),
  error = function(e) NULL)
hor_h <- NULL
if (!is.null(m_h_hor)) {
  ct <- as.data.table(coeftable(m_h_hor), keep.rownames = "term")
  ct[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  ct[, h := year - ANCHOR]
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  hor_h <- ct[!is.na(h), .(test = "H_phase2", h, est, se, tval, pval)]
  fwrite(hor_h, file.path(OUT_TAB, "phase6_a4_phase2_test_h_horizon.csv"))
}

# ---------------------------------------------------------------------------
# 3. Test I Phase II: across-category panel
# ---------------------------------------------------------------------------
cell_i <- b2b[, .(spend_in_n = sum(corr_sales)), by = .(buyer, seller_nace4d, year)]
buyer_yr <- b2b[, .(total = sum(corr_sales)), by = .(buyer, year)]
cell_i <- merge(cell_i, buyer_yr, by = c("buyer", "year"))
cell_i[, share := spend_in_n / total]
nace_with_ets_p2 <- unique(b2b[seller_is_ets == 1L & fcs_p2 > 0, seller_nace4d])
cell_i[, regulated_n := as.integer(seller_nace4d %in% nace_with_ets_p2)]
cell_i[, post := as.integer(year >= 2008L)]

# Level.
m_i_lvl <- tryCatch(
  feols(share ~ regulated_n:post | buyer^seller_nace4d + buyer^year,
        data = cell_i, cluster = c("buyer", "seller_nace4d"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_i_lvl)) {
  ct <- as.data.table(coeftable(m_i_lvl), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  fwrite(ct, file.path(OUT_TAB, "phase6_a3_phase2_test_i_levels.csv"))
}

# Horizon LP.
cell_i[, year_f := factor(year, levels = (ANCHOR + H_LO):(ANCHOR + H_HI))]
m_i_hor <- tryCatch(
  feols(share ~ i(year_f, regulated_n, ref = as.character(ANCHOR)) |
                  buyer^seller_nace4d + buyer^year,
        data = cell_i, cluster = c("buyer", "seller_nace4d"), notes = FALSE),
  error = function(e) NULL)
hor_i <- NULL
if (!is.null(m_i_hor)) {
  ct <- as.data.table(coeftable(m_i_hor), keep.rownames = "term")
  ct[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  ct[, h := year - ANCHOR]
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  hor_i <- ct[!is.na(h), .(test = "I_phase2", h, est, se, tval, pval)]
  fwrite(hor_i, file.path(OUT_TAB, "phase6_a4_phase2_test_i_horizon.csv"))
}

# ---------------------------------------------------------------------------
# 4. IRF figure (combined)
# ---------------------------------------------------------------------------
all_hor <- rbindlist(list(hor_h, hor_i), use.names = TRUE, fill = TRUE)
if (nrow(all_hor) > 0L) {
  all_hor[, ci_lo := est - 1.96 * se]; all_hor[, ci_hi := est + 1.96 * se]
  p <- ggplot(all_hor, aes(x = h, y = est, ymin = ci_lo, ymax = ci_hi,
                            color = test, fill = test)) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_vline(xintercept = 0, linetype = "dotted") +
    geom_ribbon(alpha = 0.15, color = NA) + geom_line() + geom_point() +
    facet_wrap(~ test, scales = "free_y") +
    scale_x_continuous(breaks = seq(H_LO, H_HI, 2)) +
    labs(title = "A4: Phase II event-study, horizon-h LP",
         subtitle = sprintf("Cutoff = 2008. Reference year = %d. 95%% CIs.", ANCHOR),
         x = "Horizon h", y = expression(gamma[h])) +
    theme_bw() + theme(legend.position = "none")
  ggsave(file.path(OUT_FIG, "phase6_a4_phase2_horizon_irf.pdf"), p,
         width = 10, height = 5)
  cat("Wrote", file.path(OUT_FIG, "phase6_a4_phase2_horizon_irf.pdf"), "\n")
}

cat("\nDone. Phase II level + horizon estimates saved.\n")
