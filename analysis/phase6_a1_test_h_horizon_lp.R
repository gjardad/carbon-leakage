# =============================================================================
# A1 (paper §5.1.2) — HTE by time horizon, within-NACE-4d (Test H)
#
# Horizon-h local projection on the existing Test H sample. Estimates
#   share_top_{b,n,t+h} − share_top_{b,n,t-1}
#     = γ_h · pair_exposure_{b,n} × 1[t = 2014]
#     + α_{b,n} + δ_{n,t+h} + ε
# for h ∈ {-9, …, +7} relative to t = 2014 (the year-before-cutoff anchor).
#
# Equivalent event-study formulation: long-difference at horizon h, with
# pair_exposure interacted with the event-year dummy. Two-way clustering on
# buyer + supplier-NACE-4d (matching the headline in
# phase5_test_h_most_exposed_ets_supplier.R).
#
# Outputs:
#   ${OUT_DATA}/phase6_a1_horizon_lp.csv         per-horizon γ_h, s.e., n
#   ${OUT_DATA}/phase6_a1_horizon_lp_intensive.csv  same on intensive-only
#                                                    sample (j* active throughout)
#   ${REPO_DIR}/output_local/figures/phase6_a1_horizon_irf.pdf
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(ggplot2)
})

YEAR_LO <- 2005L
YEAR_HI <- 2022L
ANCHOR  <- 2014L                # year before cutoff
H_LO <- -9L                     # earliest lead (= year 2005)
H_HI <- +7L                     # latest lag (= year 2021; 2022 is NA-prone)

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Build Test H panel (mirrors phase5_test_h_most_exposed_ets_supplier.R)
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

# ETS roster + firm cost share.
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
b2b <- merge(b2b,
             cost_share_regressor[, .(seller = vat,
                                       fcs_reg = firm_cost_share_regressor)],
             by = "seller", all.x = TRUE)
b2b[is.na(fcs_reg), fcs_reg := 0]

contam <- c("68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
            "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
            "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E")
b2b <- b2b[!(seller %in% contam & year >= 2021L)]

ets_with_fcs <- cost_share_regressor$vat
b2b <- b2b[!(seller_is_ets == 1L & !(seller %in% ets_with_fcs))]

# Cell aggregation.
cell_yr <- b2b[, .(n_active_sellers = .N,
                   n_ets_sellers = sum(seller_is_ets == 1L),
                   total_sales_cell = sum(corr_sales)),
               by = .(buyer, seller_nace4d, year)]

ets_in_cell <- unique(b2b[seller_is_ets == 1L,
                          .(buyer, seller_nace4d, seller, fcs_reg)])
setorder(ets_in_cell, buyer, seller_nace4d, -fcs_reg, seller)
j_star <- ets_in_cell[, .SD[1L], by = .(buyer, seller_nace4d)]
setnames(j_star, c("seller", "fcs_reg"), c("j_star", "fcs_j_star"))

j_star_b2b <- merge(b2b[, .(buyer, seller_nace4d, year, seller, corr_sales)],
                    j_star, by = c("buyer", "seller_nace4d"))
j_star_b2b <- j_star_b2b[seller == j_star]
j_window <- j_star_b2b[, .(t_first_j_star = min(year),
                            t_last_j_star = max(year),
                            n_years_j_star_active = uniqueN(year)),
                       by = .(buyer, seller_nace4d, j_star, fcs_j_star)]
j_window[, is_intensive_only := as.integer(
  t_first_j_star == YEAR_LO & t_last_j_star == YEAR_HI &
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
panel[, share_top_pp := 100 * share_top]

# Build pair_exposure regressor (matches phase5_test_h_most_exposed_ets_supplier.R).
NSHARE_LO <- 2010L
NSHARE_HI <- 2014L

# Buyer-year total B2B inputs in pre-shock window.
buyer_total_pre <- b2b[year %between% c(NSHARE_LO, NSHARE_HI),
                        .(total_buyer_inputs_b2b = sum(corr_sales)),
                        by = .(buyer, year)]

# j*'s spending in pre-shock window.
j_star_spending_pre <- j_star_b2b[year %between% c(NSHARE_LO, NSHARE_HI),
                                   .(buyer, seller_nace4d, year,
                                     corr_sales_j_star = corr_sales)]

j_star_pre <- merge(j_star_spending_pre, buyer_total_pre,
                    by = c("buyer", "year"))
j_star_pre[, s_jstar_yr := corr_sales_j_star / total_buyer_inputs_b2b]
s_jstar <- j_star_pre[, .(s_jstar_pre = mean(s_jstar_yr, na.rm = TRUE)),
                       by = .(buyer, seller_nace4d)]

panel <- merge(panel, s_jstar, by = c("buyer", "seller_nace4d"), all.x = TRUE)
panel[is.na(s_jstar_pre), s_jstar_pre := 0]
panel[, pair_exposure := fcs_j_star * s_jstar_pre]

cat(sprintf("Panel: %d cells x years (n_cells = %d)\n",
            nrow(panel), uniqueN(panel[, .(buyer, seller_nace4d)])))

# ---------------------------------------------------------------------------
# 2. Horizon-h LP estimator
# ---------------------------------------------------------------------------
# Long-difference at horizon h:  Y_{t = ANCHOR + h} - Y_{t = ANCHOR - 1}
# regressed on pair_exposure (interacted with the post indicator implicit in
# choosing year ANCHOR + h vs. ANCHOR - 1).
#
# Equivalent event-study: regress share_top on pair_exposure x 1[year = ANCHOR + h]
# with cell + sector-year FE, separately for each h. We use the event-study form
# because it gives confidence intervals at every h relative to ANCHOR-1.

run_horizon_es <- function(panel_in, label) {
  cat(sprintf("\n=== Horizon LP, sample = %s, n_cells = %d ===\n",
              label, uniqueN(panel_in[, .(buyer, seller_nace4d)])))

  panel_in <- copy(panel_in)
  panel_in[, year_f := factor(year, levels = (ANCHOR + H_LO):(ANCHOR + H_HI))]

  fml <- share_top_pp ~ i(year_f, pair_exposure, ref = as.character(ANCHOR - 1L)) |
                          buyer^seller_nace4d + seller_nace4d^year
  m <- tryCatch(feols(fml, data = panel_in,
                      cluster = c("buyer", "seller_nace4d"), notes = FALSE),
                error = function(e) { cat("ERROR:", conditionMessage(e), "\n"); NULL })
  if (is.null(m)) return(NULL)

  ct <- as.data.table(coeftable(m), keep.rownames = "term")
  # fixest's i() generates terms like "year_f::2005:pair_exposure"; extract the year.
  ct[, year := suppressWarnings(as.integer(
    sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  ct[, h := year - ANCHOR]
  ct[, label := label]
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  ct[!is.na(h), .(label, h, est, se, tval, pval)]
}

ct_full <- run_horizon_es(panel, "full")
ct_int  <- run_horizon_es(panel[is_intensive_only == 1L], "intensive_only")

results <- rbind(ct_full, ct_int, fill = TRUE)
fwrite(results, file.path(OUT_TAB, "phase6_a1_horizon_lp.csv"))
cat("\nWrote", file.path(OUT_TAB, "phase6_a1_horizon_lp.csv"), "\n")

# ---------------------------------------------------------------------------
# 3. IRF figure
# ---------------------------------------------------------------------------
results[, ci_lo := est - 1.96 * se]
results[, ci_hi := est + 1.96 * se]

p <- ggplot(results, aes(x = h, y = est, ymin = ci_lo, ymax = ci_hi,
                          color = label, fill = label)) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_vline(xintercept = 0, linetype = "dotted") +
  geom_ribbon(alpha = 0.15, color = NA) +
  geom_line() + geom_point() +
  scale_x_continuous(breaks = seq(H_LO, H_HI, 1)) +
  labs(title = "A1: within-NACE-4d substitution, horizon LP",
       subtitle = sprintf("Reference year %d (cutoff = 2015). 95%% CIs.",
                          ANCHOR - 1L),
       x = "Horizon h (years relative to 2015 cutoff anchor 2014)",
       y = expression(gamma[h] ~ "(pp share per unit pair-exposure)"),
       color = "Sample", fill = "Sample") +
  theme_bw()

ggsave(file.path(OUT_FIG, "phase6_a1_horizon_irf.pdf"),
       p, width = 8, height = 5)
cat("Wrote", file.path(OUT_FIG, "phase6_a1_horizon_irf.pdf"), "\n")
