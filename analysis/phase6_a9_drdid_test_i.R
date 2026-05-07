# =============================================================================
# R6 — Doubly-robust DiD (Sant'Anna & Zhao 2020) for Test I. Plan ref: §R6.
#
# Test I's pre-period leads point uniformly the wrong way (positive in every
# post-2015 year), making conditional parallel trends the natural relaxation
# rather than unconditional PT. The doubly-robust estimator is consistent if
# *either* the propensity-score model OR the outcome-trend model is correctly
# specified — a strictly weaker requirement than the OLS spec.
#
# Spec.
#   - Outcome: share_{b,n,t}
#   - Treatment: regulated_n (binary, time-invariant; ETS-regulated NACE-4d)
#   - Conditioning X: (i) buyer's pre-shock buyer_reg_exposure (= total
#     spending in regulated NACE-4d in 2010-14, normalized by total inputs),
#     (ii) pre-shock log total inputs (mean over 2010-14)
#   - Pre vs post: 2014 (pre) vs 2018 (post; mid-post-period, avoiding 2020
#     COVID disruption and 2021+ Phase IV).
#   - estMethod = "trad" — the original Heckman-style doubly-robust estimator
#     (Sant'Anna-Zhao 2020 §3.1). Much faster than "imp" (which uses an IPT
#     iterative solver that scales poorly with sample size + #covariates).
#     Both estimators target the same ATT under DR consistency; "trad" gives
#     up some semi-parametric efficiency for tractability on large panels.
#
# Optimised panel-build: loads only the year ranges actually needed (2010-14
# for the conditioning vars + 2014 & 2018 for the DRDID panel), not the full
# 2005-2022 panel — saves a lot of joining on the full RMD sample.
#
# Outputs:
#   ${OUT_TAB}/phase6_a9_drdid_test_i.csv
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(DRDID)
})

PRE_YEAR  <- 2014L
POST_YEAR <- 2018L
PRE_LO    <- 2010L
PRE_HI    <- 2014L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)

cat("[R6] Loading B2B + annual accounts (years 2010-2018 only)...\n"); flush.console()
t0 <- Sys.time()
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)[, .(seller = vat_i_ano,
                                                  buyer  = vat_j_ano,
                                                  year   = as.integer(year),
                                                  corr_sales = corr_sales_ij)]
rm(df_b2b_selected_sample)
b2b <- b2b[year %between% c(PRE_LO, POST_YEAR) &
             !is.na(corr_sales) & corr_sales > 0]
cat(sprintf("  b2b rows (years %d-%d): %d (%.1fs)\n",
            PRE_LO, POST_YEAR, nrow(b2b),
            as.numeric(difftime(Sys.time(), t0, units = "secs")))); flush.console()

t0 <- Sys.time()
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_more_selected_sample)[
  , .(vat = vat_ano, year = as.integer(year), nace5d, inputs_VAT)]
rm(df_annual_accounts_more_selected_sample)
aa <- aa[year %between% c(PRE_LO, POST_YEAR)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
seller_nace <- unique(aa[, .(seller = vat, year, seller_nace4d = nace4d)])
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]
buyer_inputs <- unique(aa[!is.na(inputs_VAT) & inputs_VAT > 0,
                           .(buyer = vat, year,
                              inputs_VAT_total = inputs_VAT)])
cat(sprintf("  annual_accounts merged (%.1fs)\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs")))); flush.console()

cat("[R6] Building nace_exposure + nace_regulated_dummy from pre-shock window...\n")
flush.console()
t0 <- Sys.time()
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]
load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
b2b <- merge(b2b, cost_share_regressor[, .(seller = vat,
                                            fcs_reg = firm_cost_share_regressor)],
             by = "seller", all.x = TRUE)
b2b[is.na(fcs_reg), fcs_reg := 0]
contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
b2b <- b2b[!(seller %in% contaminated_vats & year >= 2021L)]
ets_with_fcs <- cost_share_regressor$vat
b2b <- b2b[!(seller_is_ets == 1L & !(seller %in% ets_with_fcs))]

b2b_pre <- b2b[year %between% c(PRE_LO, PRE_HI)]
seller_pre <- b2b_pre[, .(sales_pre = sum(corr_sales),
                           fcs_seller = max(fcs_reg)),
                       by = .(seller, seller_nace4d)]
nace_exp <- seller_pre[, .(
  total_sales_pre        = sum(sales_pre),
  weighted_fcs_numerator = sum(sales_pre * fcs_seller)
), by = seller_nace4d]
nace_exp[, nace_exposure := weighted_fcs_numerator / total_sales_pre]
nace_exp[, nace_regulated_dummy := as.integer(nace_exposure > 0)]
setnames(nace_exp, "seller_nace4d", "nace4d")
cat(sprintf("  pre-shock nace_exp built (%d NACE-4d, %.1fs)\n",
            nrow(nace_exp),
            as.numeric(difftime(Sys.time(), t0, units = "secs")))); flush.console()

cat("[R6] Building cell-year panel and 2-period DRDID panel...\n")
flush.console()
t0 <- Sys.time()
buyer_year_nace <- b2b[, .(spend_bn = sum(corr_sales)),
                       by = .(buyer, nace4d = seller_nace4d, year)]
panel_i <- merge(buyer_year_nace, buyer_inputs,
                 by = c("buyer", "year"), all.x = FALSE)
panel_i <- merge(panel_i, nace_exp[, .(nace4d, nace_exposure,
                                         nace_regulated_dummy)],
                 by = "nace4d", all.x = TRUE)
panel_i <- panel_i[!is.na(nace_exposure)]
panel_i[, share := spend_bn / inputs_VAT_total]
cat(sprintf("  cell-year panel: %d rows (%.1fs)\n",
            nrow(panel_i),
            as.numeric(difftime(Sys.time(), t0, units = "secs")))); flush.console()

# Buyer pre-shock conditioning vars.
t0 <- Sys.time()
buyer_reg <- panel_i[year %between% c(PRE_LO, PRE_HI),
                      .(reg_spend = sum(spend_bn * nace_regulated_dummy),
                        total_inputs = first(inputs_VAT_total)),
                      by = .(buyer, year)]
buyer_reg[, reg_share := reg_spend / total_inputs]
buyer_reg_avg <- buyer_reg[, .(buyer_reg_exposure = mean(reg_share, na.rm = TRUE),
                                buyer_log_inputs   = log(mean(total_inputs,
                                                              na.rm = TRUE))),
                            by = buyer]
cat(sprintf("  buyer pre-shock vars: %d buyers (%.1fs)\n",
            nrow(buyer_reg_avg),
            as.numeric(difftime(Sys.time(), t0, units = "secs")))); flush.console()

# 2-period DRDID panel (pre = 2014, post = 2018).
panel_2y <- panel_i[year %in% c(PRE_YEAR, POST_YEAR)]
ct <- panel_2y[, .N, by = .(buyer, nace4d)]
keep <- ct[N == 2L]
panel_2y <- panel_2y[keep, on = c("buyer", "nace4d")]
panel_2y <- merge(panel_2y, buyer_reg_avg, by = "buyer", all.x = TRUE)
panel_2y[is.na(buyer_reg_exposure), buyer_reg_exposure := 0]
panel_2y[is.na(buyer_log_inputs),
         buyer_log_inputs   := mean(buyer_log_inputs, na.rm = TRUE)]
panel_2y[, cell_id := .GRP, by = .(buyer, nace4d)]
cat(sprintf("DRDID 2-year panel: %d obs across %d cells (need both pre & post)\n",
            nrow(panel_2y), uniqueN(panel_2y$cell_id))); flush.console()

# ---------------------------------------------------------------------------
# Run drdid (panel, 2 periods, "trad" estMethod for speed on large samples).
# ---------------------------------------------------------------------------
cat(sprintf("Calling drdid(estMethod='trad') on %d obs ...\n",
            nrow(panel_2y))); flush.console()
t0 <- Sys.time()
res <- tryCatch(
  drdid(yname     = "share",
        tname     = "year",
        idname    = "cell_id",
        dname     = "nace_regulated_dummy",
        xformla   = ~ buyer_reg_exposure + buyer_log_inputs,
        data      = panel_2y,
        panel     = TRUE,
        estMethod = "trad",
        boot      = FALSE),
  error = function(e) {cat("DRDID error:", conditionMessage(e), "\n"); NULL})
cat(sprintf("DRDID elapsed: %s\n", format(Sys.time() - t0))); flush.console()

if (!is.null(res)) {
  cat("\nDRDID result:\n"); print(res)
  out <- data.table(
    estimator = "DRDID-trad (Sant'Anna-Zhao 2020 §3.1)",
    att       = res$ATT,
    se        = res$se,
    boot_se   = if (!is.null(res$se.boot)) res$se.boot else NA_real_,
    pre_year  = PRE_YEAR,
    post_year = POST_YEAR
  )
} else {
  out <- data.table(estimator = "DRDID-trad", att = NA_real_,
                    se = NA_real_, pre_year = PRE_YEAR, post_year = POST_YEAR)
}
fwrite(out, file.path(OUT_TAB, "phase6_a9_drdid_test_i.csv"))
cat("\nWritten phase6_a9_drdid_test_i.csv\n")
