# =============================================================================
# A2 (paper §5.1.4) — HTE on across-category margin (Test I)
#
# Two heterogeneity dimensions:
#   (a) Horizon-h LP analog of Test I:
#         share_{b,n,t+h} - share_{b,n,t-1}
#           = γ_h · regulated_n × 1[t = 2014] + α_{b,n} + δ_{b,t+h} + ε
#   (b) Buyer-level quartile splits on
#         buyer_reg_exposure_b = Σ_n regulated_n × pre-shock share_{b,n}
#       (the buyer's pre-shock total expenditure share in regulated categories).
#       Category-level quartiles are degenerate (most NACE-4d codes have
#       nace_exposure = 0); the buyer-level cut is the right HTE dimension.
#
# Two-way clustering: buyer + NACE 4-digit. Sample is large (~5.7M cells x 18
# years on the full panel; smaller on local-1 downsampled).
#
# Outputs:
#   ${OUT_TAB}/phase6_a2_horizon_lp.csv
#   ${OUT_TAB}/phase6_a2_buyer_quartile.csv
#   ${OUT_FIG}/phase6_a2_horizon_irf.pdf
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2)
})

YEAR_LO <- 2005L; YEAR_HI <- 2022L
ANCHOR  <- 2014L
H_LO <- -9L; H_HI <- +7L
NSHARE_LO <- 2010L; NSHARE_HI <- 2014L

OUT_TAB <- file.path(REPO_DIR, "output_local", "tables")
OUT_FIG <- file.path(REPO_DIR, "output_local", "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Build buyer × NACE-4d × year panel (mirrors phase5_test_i_*.R)
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

# ETS roster.
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)

# Aggregate to buyer × NACE-4d × year.
cell_yr <- b2b[, .(spend_in_n = sum(corr_sales)),
               by = .(buyer, seller_nace4d, year)]
buyer_yr <- b2b[, .(total_spend = sum(corr_sales)), by = .(buyer, year)]
cell_yr <- merge(cell_yr, buyer_yr, by = c("buyer", "year"))
cell_yr[, share := spend_in_n / total_spend]

# Regulated category flag.
nace_with_ets <- unique(b2b[seller %in% ets_vats, seller_nace4d])
cell_yr[, regulated_n := as.integer(seller_nace4d %in% nace_with_ets)]

# ---------------------------------------------------------------------------
# 2. (a) Horizon-h event study
# ---------------------------------------------------------------------------
cell_yr[, year_f := factor(year, levels = (ANCHOR + H_LO):(ANCHOR + H_HI))]

cat("Horizon LP, full panel (Test I)\n")
m_a <- tryCatch(
  feols(share ~ i(year_f, regulated_n, ref = as.character(ANCHOR - 1L)) |
                  buyer^seller_nace4d + buyer^year,
        data = cell_yr, cluster = c("buyer", "seller_nace4d"), notes = FALSE),
  error = function(e) { cat("ERROR:", conditionMessage(e), "\n"); NULL })

if (!is.null(m_a)) {
  ct <- as.data.table(coeftable(m_a), keep.rownames = "term")
  ct[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  ct[, h := year - ANCHOR]
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  out_a <- ct[!is.na(h), .(h, est, se, tval, pval)]
  fwrite(out_a, file.path(OUT_TAB, "phase6_a2_horizon_lp.csv"))
  cat("Wrote", file.path(OUT_TAB, "phase6_a2_horizon_lp.csv"), "\n")

  out_a[, ci_lo := est - 1.96 * se]; out_a[, ci_hi := est + 1.96 * se]
  p <- ggplot(out_a, aes(x = h, y = est, ymin = ci_lo, ymax = ci_hi)) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_vline(xintercept = 0, linetype = "dotted") +
    geom_ribbon(alpha = 0.2) + geom_line() + geom_point() +
    scale_x_continuous(breaks = seq(H_LO, H_HI, 1)) +
    labs(title = "A2: across-category substitution, horizon LP",
         subtitle = sprintf("Reference year %d. 95%% CIs.", ANCHOR - 1L),
         x = "Horizon h", y = expression(gamma[h])) + theme_bw()
  ggsave(file.path(OUT_FIG, "phase6_a2_horizon_irf.pdf"), p, width = 8, height = 5)
}

# ---------------------------------------------------------------------------
# 3. (b) Buyer-level exposure quartile splits
# ---------------------------------------------------------------------------
# buyer_reg_exposure_b = Σ_n regulated_n × pre-shock share_{b,n}
pre <- cell_yr[year %between% c(NSHARE_LO, NSHARE_HI),
               .(share_pre = mean(share, na.rm = TRUE)),
               by = .(buyer, seller_nace4d, regulated_n)]
buyer_exp <- pre[regulated_n == 1L,
                  .(buyer_reg_exposure = sum(share_pre, na.rm = TRUE)),
                  by = buyer]

cell_yr <- merge(cell_yr, buyer_exp, by = "buyer", all.x = TRUE)
cell_yr[is.na(buyer_reg_exposure), buyer_reg_exposure := 0]

qs <- quantile(unique(cell_yr[, .(buyer, buyer_reg_exposure)])$buyer_reg_exposure,
               c(0.25, 0.5, 0.75), na.rm = TRUE)
cat("\nBuyer reg-exposure quartile cutpoints:\n")
print(round(qs, 4))

cell_yr[, exp_q := fcase(
  buyer_reg_exposure <  qs[1], "Q1",
  buyer_reg_exposure <  qs[2], "Q2",
  buyer_reg_exposure <  qs[3], "Q3",
  buyer_reg_exposure >= qs[3], "Q4",
  default = NA_character_)]

results <- list()
for (q in c("Q1", "Q2", "Q3", "Q4", "all")) {
  cat(sprintf("Quartile %s ", q))
  sub <- if (q == "all") cell_yr else cell_yr[exp_q == q]
  cat(sprintf("(n_cells = %d)\n", uniqueN(sub[, .(buyer, seller_nace4d)])))
  sub[, post := as.integer(year >= 2015L)]
  m <- tryCatch(
    feols(share ~ regulated_n:post | buyer^seller_nace4d + buyer^year,
          data = sub, cluster = c("buyer", "seller_nace4d"), notes = FALSE),
    error = function(e) NULL)
  if (!is.null(m)) {
    ct <- as.data.table(coeftable(m), keep.rownames = "term")
    setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
             c("est", "se", "tval", "pval"))
    ct[, quartile := q]
    results[[q]] <- ct[, .(quartile, term, est, se, tval, pval)]
  }
}

if (length(results) > 0) {
  out_b <- rbindlist(results)
  fwrite(out_b, file.path(OUT_TAB, "phase6_a2_buyer_quartile.csv"))
  cat("Wrote", file.path(OUT_TAB, "phase6_a2_buyer_quartile.csv"), "\n")
  print(out_b)
}
