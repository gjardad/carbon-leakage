# =============================================================================
# Trend-corrected Test I (paper §5.1.5) — binary-treatment analog of the
# pre-trend correction. The continuous-treatment Test I.2 spec already
# reports the trend slope and is robust to the trend (treat_year is reported
# alongside treat_post in the existing run); see
# phase5_test_i_cross_nace_substitution.R for that result.
#
# What's missing: the trend-corrected version of the BINARY treatment
# specification, which is the headline (I.3). The binary spec uses
# buyer × year FE that absorbs all buyer-year scale variation and so is
# robust by construction to a buyer-level pre-trend. But the
# regulated-vs-unregulated DIFFERENTIAL could itself have a pre-trend that
# the binary spec doesn't absorb. We test this by adding
# `regulated_n × year_centered` to I.3 and seeing whether β on `regulated_n
# × Post` moves.
#
# Spec.
#   share_{b,n,t}
#     = β · regulated_n × Post_t
#     + γ · regulated_n × year_centered_t   (NEW: trend control)
#     + α_{b,n} (cell FE) + δ_{b,t} (buyer-year FE) + ε
#
# Same panel as phase5_test_i_cross_nace_substitution.R. Same cluster (buyer).
# Sample: 5.7M cell-years.
#
# Outputs:
#   ${OUT_TAB}/phase6_test_i_corrected.csv  — naive vs trend-corrected
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest)
})

YEAR_LO   <- 2005L
YEAR_HI   <- 2022L
POST_FROM <- 2015L
ANCHOR    <- 2014L
PRE_LO    <- 2010L
PRE_HI    <- 2014L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Load b2b + annual accounts (mirrors phase5_test_i_cross_nace_substitution.R)
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)[, .(seller = vat_i_ano,
                                                  buyer  = vat_j_ano,
                                                  year,
                                                  corr_sales = corr_sales_ij)]
rm(df_b2b_selected_sample)
b2b[, year := as.integer(year)]
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) &
             !is.na(corr_sales) & corr_sales > 0]

load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_more_selected_sample)[
  , .(vat = vat_ano, year, nace5d, inputs_VAT)]
rm(df_annual_accounts_more_selected_sample)
aa[, year := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
seller_nace <- unique(aa[, .(seller = vat, year, seller_nace4d = nace4d)])
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]

buyer_inputs <- unique(aa[!is.na(inputs_VAT) & inputs_VAT > 0,
                           .(buyer = vat, year, inputs_VAT_total = inputs_VAT)])

load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
b2b <- merge(b2b,
             cost_share_regressor[, .(seller = vat,
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

# ---------------------------------------------------------------------------
# 2. nace_exposure (continuous) and nace_regulated_dummy (binary)
# ---------------------------------------------------------------------------
b2b_pre <- b2b[year %between% c(PRE_LO, PRE_HI)]
seller_pre <- b2b_pre[, .(sales_pre = sum(corr_sales),
                           fcs_seller = max(fcs_reg)),
                       by = .(seller, seller_nace4d)]
nace_exposure <- seller_pre[, .(
  total_sales_pre        = sum(sales_pre),
  weighted_fcs_numerator = sum(sales_pre * fcs_seller)
), by = seller_nace4d]
nace_exposure[, nace_exposure := weighted_fcs_numerator / total_sales_pre]
nace_exposure[, nace_regulated_dummy := as.integer(nace_exposure > 0)]
setnames(nace_exposure, "seller_nace4d", "nace4d")

# ---------------------------------------------------------------------------
# 3. Build cell panel: (buyer × NACE 4d × year) spending
# ---------------------------------------------------------------------------
buyer_year_nace <- b2b[, .(spend_bn = sum(corr_sales)),
                       by = .(buyer, nace4d = seller_nace4d, year)]
panel <- merge(buyer_year_nace, buyer_inputs,
               by = c("buyer", "year"), all.x = FALSE)
panel <- merge(panel, nace_exposure[, .(nace4d, nace_exposure,
                                         nace_regulated_dummy)],
               by = "nace4d", all.x = TRUE)
panel <- panel[!is.na(nace_exposure)]

panel[, share := spend_bn / inputs_VAT_total]
panel[, post := as.integer(year >= POST_FROM)]
panel[, year_centered := year - ANCHOR]
panel[, regulated_post     := nace_regulated_dummy * post]
panel[, regulated_yearc    := nace_regulated_dummy * year_centered]
panel[, by_year := paste(buyer, year, sep = "_")]
panel[, b_n     := paste(buyer, nace4d, sep = "_")]

cat(sprintf("Test I sample: %d cell-years across %d cells\n",
            nrow(panel), uniqueN(panel$b_n)))

# ---------------------------------------------------------------------------
# 4. Two specifications
# ---------------------------------------------------------------------------
specs <- list()

# (a) Original I.3 — naive binary regulated × Post.
m_naive <- tryCatch(
  feols(share ~ regulated_post | by_year + b_n,
        data = panel, cluster = ~ buyer, notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_naive)) {
  ct <- as.data.table(coeftable(m_naive), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"), c("estimate", "se", "tval", "pval"))
  ct[, spec := "I.3 naive (no trend control)"]
  specs[["naive"]] <- ct
}

# (b) Trend-corrected: add regulated × year_centered.
m_trend <- tryCatch(
  feols(share ~ regulated_post + regulated_yearc | by_year + b_n,
        data = panel, cluster = ~ buyer, notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_trend)) {
  ct <- as.data.table(coeftable(m_trend), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"), c("estimate", "se", "tval", "pval"))
  ct[, spec := "I.3 trend-corrected"]
  specs[["trend"]] <- ct
}

results <- rbindlist(specs, use.names = TRUE, fill = TRUE)
fwrite(results, file.path(OUT_TAB, "phase6_test_i_corrected.csv"))
cat("\nTest I.3 specifications side-by-side:\n")
print(results[, .(spec, term, estimate, se, pval)])
