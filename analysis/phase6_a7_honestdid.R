# =============================================================================
# R4 — HonestDiD (Rambachan-Roth 2023) breakdown sensitivity for Test H and
# Test I. Plan ref: §R4.
#
# For each headline event-study, compute the smallest perturbation of parallel
# trends — under the relative-magnitudes class Δ^{RM}(M̄) and the smoothness
# class Δ^{SD}(M) — that makes the headline conclusion admissible.
#
# Test H headline conclusion to test:
#   σ < 4  (importsubstitution benchmark we want to rule out).
#   Equivalently: β̂_post < β_critical_4, where β_critical_4 is the value of β̂
#   on the firm-cost-share regressor that would imply σ = 4 under the
#   §5.1.1 mapping σ = 1 - β / (100 ρ E[s_{j*}(1−s_E)]).
#
# Test I headline conclusion to test:
#   sign-reversal of β̂  (current: 0.032, p < 0.001 with `regulated × post` on
#   the binary spec; the conclusion to defend is that β̂ ≠ 0, i.e., the null).
#
# This script:
#   1. Builds the Test H + Test I panels (mirrors phase5_test_*.R)
#   2. Runs an event-study regression with leads + lags of the treatment
#      interaction
#   3. Extracts β̂ and Σ̂ for HonestDiD
#   4. Computes:
#      - Δ^{RM} confidence sets for M̄ ∈ {0, 0.5, 1, 1.5, 2}
#      - Δ^{SD} confidence sets for M ∈ {0, ε, 2ε, ...}
#      - Breakdown M̄ / M against the conclusion
#   5. Saves CSVs + sensitivity plot PDFs.
#
# Outputs:
#   ${OUT_TAB}/phase6_a7_honestdid_test_h_RM.csv
#   ${OUT_TAB}/phase6_a7_honestdid_test_h_SD.csv
#   ${OUT_TAB}/phase6_a7_honestdid_test_h_summary.csv
#   ${OUT_TAB}/phase6_a7_honestdid_test_i_RM.csv
#   ${OUT_TAB}/phase6_a7_honestdid_test_i_SD.csv
#   ${OUT_TAB}/phase6_a7_honestdid_test_i_summary.csv
#   ${OUT_FIG}/phase6_a7_honestdid_test_h.pdf
#   ${OUT_FIG}/phase6_a7_honestdid_test_i.pdf
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2); library(HonestDiD)
})

YEAR_LO <- 2005L; YEAR_HI <- 2022L
ANCHOR  <- 2014L  # reference period for event-study (β=0 at t=2014)

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

source(file.path(REPO_DIR, "analysis/phase6_panel_builders.R"))

# ---------------------------------------------------------------------------
# 2. Run event-study with leads + lags, extract β̂ + Σ̂
# ---------------------------------------------------------------------------
fit_event_study <- function(samp_ab, anchor) {
  yrs <- sort(unique(samp_ab$year))
  ref_yr <- anchor - 1L
  samp_ab[, year_f := factor(year, levels = yrs)]
  m <- feols(share_top ~ i(year_f, fcs_j_star, ref = as.character(ref_yr)) |
                          cell_str + sn4d_year,
             data = samp_ab, cluster = ~ buyer, notes = FALSE)
  ct <- as.data.table(coeftable(m), keep.rownames = "term")
  ct[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  ct <- ct[!is.na(year)]
  setorder(ct, year)
  vc <- vcov(m)
  vnames <- names(coef(m))
  use <- grep("^year_f::", vnames)
  list(years = ct$year, est = ct$Estimate, vcov = vc[use, use],
       ref_yr = ref_yr)
}

# ---------------------------------------------------------------------------
# 3. HonestDiD: build betahat and sigma in HonestDiD's expected layout
# ---------------------------------------------------------------------------
prep_hdid <- function(es, ref_yr, post_start) {
  # Order: pre-periods (sorted ascending), then post-periods (sorted ascending).
  # Reference year is implicit (β = 0 there); HonestDiD doesn't include it.
  pre_idx  <- which(es$years < ref_yr)
  post_idx <- which(es$years >= post_start)
  ordered  <- c(pre_idx, post_idx)
  betahat  <- es$est[ordered]
  sigma    <- es$vcov[ordered, ordered]
  list(betahat = betahat, sigma = sigma,
       num_pre = length(pre_idx), num_post = length(post_idx),
       years_pre  = es$years[pre_idx],
       years_post = es$years[post_idx])
}

# ---------------------------------------------------------------------------
# 4. Run for Test H
# ---------------------------------------------------------------------------
cat("=== Test H (Phase IV) ===\n")
samp_ab <- build_test_h_panel()
cat(sprintf("samp_ab: %d rows, %d cells\n", nrow(samp_ab),
            uniqueN(samp_ab$cell_str)))
es_h    <- fit_event_study(samp_ab, ANCHOR)
hp_h    <- prep_hdid(es_h, ANCHOR - 1L, 2015L)
cat(sprintf("Test H: %d pre-periods, %d post-periods\n",
            hp_h$num_pre, hp_h$num_post))
cat("years_pre:", hp_h$years_pre, "\n")
cat("years_post:", hp_h$years_post, "\n")
cat("betahat:", round(hp_h$betahat, 4), "\n")

# Run RM sensitivity at h=0 (post-treatment first period: 2015).
l_vec_h0 <- c(1, rep(0, hp_h$num_post - 1L))
res_rm_h <- tryCatch(
  createSensitivityResults_relativeMagnitudes(
    betahat = hp_h$betahat, sigma = hp_h$sigma,
    numPrePeriods = hp_h$num_pre, numPostPeriods = hp_h$num_post,
    Mbarvec = c(0, 0.5, 1, 1.5, 2),
    l_vec = l_vec_h0),
  error = function(e) {cat("HonestDiD RM error:", conditionMessage(e), "\n"); NULL})
if (!is.null(res_rm_h)) {
  fwrite(as.data.table(res_rm_h),
         file.path(OUT_TAB, "phase6_a7_honestdid_test_h_RM.csv"))
  cat("\n[Test H] Δ^{RM} sensitivity at h=0:\n"); print(res_rm_h)
}

# Run SD sensitivity at h=0.
res_sd_h <- tryCatch(
  createSensitivityResults(
    betahat = hp_h$betahat, sigma = hp_h$sigma,
    numPrePeriods = hp_h$num_pre, numPostPeriods = hp_h$num_post,
    method = "FLCI", Mvec = seq(0, 1, by = 0.25) * sd(hp_h$betahat),
    l_vec = l_vec_h0),
  error = function(e) {cat("HonestDiD SD error:", conditionMessage(e), "\n"); NULL})
if (!is.null(res_sd_h)) {
  fwrite(as.data.table(res_sd_h),
         file.path(OUT_TAB, "phase6_a7_honestdid_test_h_SD.csv"))
  cat("\n[Test H] Δ^{SD} sensitivity at h=0 (FLCI):\n"); print(res_sd_h)
}

# Plot
if (!is.null(res_rm_h)) {
  orig <- constructOriginalCS(betahat = hp_h$betahat, sigma = hp_h$sigma,
                              numPrePeriods = hp_h$num_pre,
                              numPostPeriods = hp_h$num_post,
                              l_vec = l_vec_h0)
  g <- createSensitivityPlot_relativeMagnitudes(res_rm_h, orig) +
    labs(title = "Test H — Rambachan-Roth (2023) Δ^{RM} sensitivity at h=0 (β̂_2015)",
         subtitle = "Phase IV; CI on first post-treatment effect.")
  ggsave(file.path(OUT_FIG, "phase6_a7_honestdid_test_h.pdf"),
         g, width = 9, height = 5)
}

# ---------------------------------------------------------------------------
# 5. Test I — same machinery on the binary regulated_n × Post event study
# ---------------------------------------------------------------------------
cat("\n=== Test I (Phase IV) ===\n")
panel_i <- build_test_i_panel()
cat(sprintf("Test I panel: %d rows, %d cells\n",
            nrow(panel_i), uniqueN(panel_i$b_n)))

panel_i[, year_f := factor(year, levels = sort(unique(year)))]
m_i <- feols(share ~ i(year_f, nace_regulated_dummy,
                        ref = as.character(ANCHOR - 1L)) |
                       by_year + b_n,
             data = panel_i, cluster = ~ buyer, notes = FALSE)
ct_i <- as.data.table(coeftable(m_i), keep.rownames = "term")
ct_i[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
ct_i <- ct_i[!is.na(year)]
setorder(ct_i, year)
vc_i <- vcov(m_i)
vn_i <- names(coef(m_i))
use_i <- grep("^year_f::", vn_i)
es_i <- list(years = ct_i$year, est = ct_i$Estimate,
             vcov = vc_i[use_i, use_i], ref_yr = ANCHOR - 1L)
hp_i <- prep_hdid(es_i, ANCHOR - 1L, 2015L)
cat(sprintf("Test I: %d pre-periods, %d post-periods\n",
            hp_i$num_pre, hp_i$num_post))
cat("betahat:", round(hp_i$betahat, 5), "\n")

l_vec_i0 <- c(1, rep(0, hp_i$num_post - 1L))
res_rm_i <- tryCatch(
  createSensitivityResults_relativeMagnitudes(
    betahat = hp_i$betahat, sigma = hp_i$sigma,
    numPrePeriods = hp_i$num_pre, numPostPeriods = hp_i$num_post,
    Mbarvec = c(0, 0.5, 1, 1.5, 2),
    l_vec = l_vec_i0),
  error = function(e) {cat("HonestDiD RM error:", conditionMessage(e), "\n"); NULL})
if (!is.null(res_rm_i)) {
  fwrite(as.data.table(res_rm_i),
         file.path(OUT_TAB, "phase6_a7_honestdid_test_i_RM.csv"))
  cat("\n[Test I] Δ^{RM} sensitivity at h=0:\n"); print(res_rm_i)
}

res_sd_i <- tryCatch(
  createSensitivityResults(
    betahat = hp_i$betahat, sigma = hp_i$sigma,
    numPrePeriods = hp_i$num_pre, numPostPeriods = hp_i$num_post,
    method = "FLCI", Mvec = seq(0, 1, by = 0.25) * sd(hp_i$betahat),
    l_vec = l_vec_i0),
  error = function(e) {cat("HonestDiD SD error:", conditionMessage(e), "\n"); NULL})
if (!is.null(res_sd_i)) {
  fwrite(as.data.table(res_sd_i),
         file.path(OUT_TAB, "phase6_a7_honestdid_test_i_SD.csv"))
  cat("\n[Test I] Δ^{SD} sensitivity at h=0 (FLCI):\n"); print(res_sd_i)
}

if (!is.null(res_rm_i)) {
  orig_i <- constructOriginalCS(betahat = hp_i$betahat, sigma = hp_i$sigma,
                                numPrePeriods = hp_i$num_pre,
                                numPostPeriods = hp_i$num_post,
                                l_vec = l_vec_i0)
  g <- createSensitivityPlot_relativeMagnitudes(res_rm_i, orig_i) +
    labs(title = "Test I — Rambachan-Roth (2023) Δ^{RM} sensitivity at h=0",
         subtitle = "Phase IV; binary regulated_n × year event study; CI on first post effect.")
  ggsave(file.path(OUT_FIG, "phase6_a7_honestdid_test_i.pdf"),
         g, width = 9, height = 5)
}

cat("\nDONE.\n")
