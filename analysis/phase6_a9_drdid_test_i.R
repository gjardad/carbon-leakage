# =============================================================================
# R6 — Doubly-robust DiD (Sant'Anna & Zhao 2020) for Test I. Plan ref: §R6.
#
# Test I's pre-period leads point uniformly the wrong way (positive in every
# post-2015 year), making conditional parallel trends the natural relaxation
# rather than unconditional PT. The doubly-robust estimator is consistent if
# *either* the propensity-score model OR the outcome-trend model is correctly
# specified — a strictly weaker requirement than the OLS spec.
#
# Spec (DRIPW form, the headline DRDID variant in Sant'Anna-Zhao 2020):
#   - Outcome: share_{b,n,t}
#   - Treatment: regulated_n (binary, time-invariant; ETS-regulated NACE-4d)
#   - Conditioning X: (i) buyer's pre-shock buyer_reg_exposure (= total
#     spending in regulated NACE-4d in 2010-14, normalized by total inputs),
#     (ii) NACE-2d sector dummy (NACE-4d's first 2 digits),
#     (iii) pre-shock log total inputs (mean over 2010-14)
#   - Pre vs post: 2014 (pre) vs 2018 (post; mid-post-period, avoiding 2020
#     COVID disruption and 2021+ Phase IV).
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

YEAR_LO <- 2005L; YEAR_HI <- 2022L
PRE_YEAR  <- 2014L
POST_YEAR <- 2018L
PRE_LO    <- 2010L
PRE_HI    <- 2014L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)

source(file.path(REPO_DIR, "analysis/phase6_panel_builders.R"))
panel_i <- build_test_i_panel()

# ---------------------------------------------------------------------------
# Build conditioning X at the (buyer, NACE-4d) cell level.
# ---------------------------------------------------------------------------
panel_i[, nace2d := substr(nace4d, 1, 2)]

# Buyer's pre-shock total exposure to regulated NACE-4d categories.
buyer_reg <- panel_i[year %between% c(PRE_LO, PRE_HI),
                      .(reg_spend     = sum(spend_bn * nace_regulated_dummy),
                        total_inputs  = first(inputs_VAT_total)),
                      by = .(buyer, year)]
buyer_reg[, reg_share := reg_spend / total_inputs]
buyer_reg_avg <- buyer_reg[, .(buyer_reg_exposure = mean(reg_share, na.rm = TRUE),
                                buyer_log_inputs   = log(mean(total_inputs,
                                                              na.rm = TRUE))),
                            by = buyer]

# Reduce to (buyer, nace4d) pairs observed in both pre and post years.
panel_2y <- panel_i[year %in% c(PRE_YEAR, POST_YEAR)]
panel_2y[, period := ifelse(year == PRE_YEAR, 0L, 1L)]

# Filter cells with both pre & post obs (drdid requires balanced)
ct <- panel_2y[, .N, by = .(buyer, nace4d)]
keep <- ct[N == 2L]
panel_2y <- panel_2y[keep, on = c("buyer", "nace4d")]
cat(sprintf("DRDID 2-year panel: %d obs across %d cells (need both pre & post)\n",
            nrow(panel_2y), uniqueN(paste(panel_2y$buyer, panel_2y$nace4d))))

panel_2y <- merge(panel_2y, buyer_reg_avg, by = "buyer", all.x = TRUE)
panel_2y[is.na(buyer_reg_exposure), buyer_reg_exposure := 0]
panel_2y[is.na(buyer_log_inputs),   buyer_log_inputs   := mean(buyer_log_inputs, na.rm = TRUE)]
# Encode NACE-2d as numeric for drdid
panel_2y[, nace2d_id := as.integer(factor(nace2d))]
panel_2y[, cell_id   := .GRP, by = .(buyer, nace4d)]

# ---------------------------------------------------------------------------
# Run drdid_panel (panel data, 2 periods, doubly-robust)
# ---------------------------------------------------------------------------
# DRDID expects:
#   yname     - outcome column
#   tname     - period column (must be the smaller value = pre)
#   idname    - id column (cell-level)
#   dname     - treatment indicator (1 if treated; here regulated_n)
#   xformla   - covariate formula
cat(sprintf("Calling drdid() on %d obs (%d cells × 2 periods)...\n",
            nrow(panel_2y), uniqueN(panel_2y$cell_id)))
flush.console()
t0 <- Sys.time()
res <- tryCatch(
  drdid(yname    = "share",
        tname    = "year",
        idname   = "cell_id",
        dname    = "nace_regulated_dummy",
        xformla  = ~ buyer_reg_exposure + buyer_log_inputs + factor(nace2d_id),
        data     = panel_2y,
        panel    = TRUE,
        estMethod = "imp",
        boot     = FALSE),    # analytical SE; bootstrap too slow on local-1
  error = function(e) {cat("DRDID error:", conditionMessage(e), "\n"); NULL})
cat(sprintf("DRDID elapsed: %s\n", format(Sys.time() - t0)))
flush.console()

if (!is.null(res)) {
  cat("\nDRDID result:\n"); print(res)
  out <- data.table(
    estimator = "DRDID-imp (Sant'Anna-Zhao 2020)",
    att       = res$ATT,
    se        = res$se,
    boot_se   = if (!is.null(res$se.boot)) res$se.boot else NA_real_,
    pre_year  = PRE_YEAR,
    post_year = POST_YEAR
  )
} else {
  out <- data.table(estimator = "DRDID-imp", att = NA_real_,
                    se = NA_real_, pre_year = PRE_YEAR, post_year = POST_YEAR)
}
fwrite(out, file.path(OUT_TAB, "phase6_a9_drdid_test_i.csv"))
cat("\nWritten phase6_a9_drdid_test_i.csv\n")
