# =============================================================================
# R3 — Pre-trend power analysis (Roth 2022, AERI). Plan ref: §R3.
#
# For each headline event-study, compute the power of the conventional pre-
# trend test against a linear differential trend large enough to deliver an
# economically-meaningful conclusion.
#
# Calibration of the alternative:
#   Test H: a linear differential trend that would deliver σ = 4 (rejection
#           of the import-substitution magnitude). Under the §5.1.1 mapping
#           σ = 1 - β / (100 ρ E[s_{j*}(1-s_E)]), with ρ = 1 and the empirical
#           E[s_{j*}(1-s_E)] = 0.068 we get
#                 β_{σ=4} = 100 * 1 * 0.068 * (1 - 4) = -20.4.
#           A linear pre-trend whose slope, extrapolated through the post-
#           period, would shift β̂_post by 20.4 in absolute value.
#   Test I: a linear differential trend that would deliver a coefficient
#           large enough to imply σ ≤ 0.5 on the across-category margin —
#           i.e., a doubling of the headline 0.032 in absolute magnitude.
#           Calibrated to slope ≈ -0.064 / 7 yr = -0.009/year.
#
# Outputs:
#   ${OUT_TAB}/phase6_a6_pretrend_power_test_h.csv
#   ${OUT_TAB}/phase6_a6_pretrend_power_test_i.csv
#   ${OUT_FIG}/phase6_a6_pretrend_power_test_h.pdf
#   ${OUT_FIG}/phase6_a6_pretrend_power_test_i.pdf
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2); library(pretrends)
})

YEAR_LO <- 2005L; YEAR_HI <- 2022L
ANCHOR  <- 2014L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

source(file.path(REPO_DIR, "analysis/phase6_panel_builders.R"))

# Helper: extract betahat + vcov as full event-plot vector (incl. ref year=0)
# in HonestDiD-/pretrends-friendly format.
fit_and_pack <- function(samp_data, treatment_col, group_re, fe_re,
                          cluster_re = ~ buyer) {
  yrs <- sort(unique(samp_data$year))
  ref_yr <- ANCHOR - 1L
  samp_data[, year_f := factor(year, levels = yrs)]
  rhs <- sprintf("i(year_f, %s, ref = '%s')", treatment_col, as.character(ref_yr))
  form <- as.formula(sprintf("%s ~ %s | %s", group_re, rhs, fe_re))
  m <- feols(form, data = samp_data, cluster = cluster_re, notes = FALSE)
  vn <- names(coef(m))
  use <- grep("^year_f::", vn)
  est <- coef(m)[use]
  v   <- vcov(m)[use, use]
  yr_int <- as.integer(sub("^year_f::([0-9]+):.*$", "\\1", vn[use]))
  ord <- order(yr_int)
  list(years = yr_int[ord], betahat = est[ord], sigma = v[ord, ord],
       ref_yr = ref_yr)
}

# tVec for pretrends should be relative-time, with referencePeriod = 0.
make_tVec <- function(years_used, ref_yr) {
  years_full <- c(years_used, ref_yr)
  years_full <- sort(years_full)
  years_full - ref_yr
}

# ---------------------------------------------------------------------------
# Test H
# ---------------------------------------------------------------------------
cat("=== Test H ===\n")
samp_h <- build_test_h_panel()
fit_h  <- fit_and_pack(
  samp_h, treatment_col = "fcs_j_star",
  group_re = "share_top",
  fe_re = "cell_str + sn4d_year",
  cluster_re = ~ buyer)
cat(sprintf("years included: %s\n",
            paste(fit_h$years, collapse = ", ")))

tVec_h <- fit_h$years - fit_h$ref_yr
post_idx_h <- which(fit_h$years >= 2015L)
pre_idx_h  <- which(fit_h$years <  fit_h$ref_yr)

# Calibrated alternative for Test H: slope that would put β̂_post at -20.4
# (the σ=4 critical β) extrapolated linearly. With reference at t=0 and post
# horizon h_post = year - 2014 starting at 1 (for 2015)... we need a slope
# γ such that γ * h_post ≈ -20.4 at h_post = 1, so γ = -20.4 (linear
# extrapolation, conservative power: exact match at h=1).
sigma_4_slope_h <- -20.4

power_h_at_sigma4 <- pretrends(
  betahat   = fit_h$betahat,
  sigma     = fit_h$sigma,
  deltatrue = sigma_4_slope_h * tVec_h,
  tVec      = tVec_h,
  referencePeriod = 0)
cat("\n[Test H] pretrends() against σ=4 alternative:\n")
print(power_h_at_sigma4$df_power)

slope_50_h <- slope_for_power(
  sigma = fit_h$sigma,
  targetPower = 0.5,
  tVec = tVec_h,
  referencePeriod = 0)
cat(sprintf("\n[Test H] slope at 50%% power = %.4f per year\n", slope_50_h))

slope_80_h <- slope_for_power(
  sigma = fit_h$sigma,
  targetPower = 0.8,
  tVec = tVec_h,
  referencePeriod = 0)
cat(sprintf("[Test H] slope at 80%% power = %.4f per year\n", slope_80_h))

out_h <- data.table(
  measure = c("power against σ=4 alternative (β=-20.4 over h=1)",
              "slope at 50% power",
              "slope at 80% power"),
  value   = c(power_h_at_sigma4$df_power$Power[1L], slope_50_h, slope_80_h)
)
fwrite(out_h, file.path(OUT_TAB, "phase6_a6_pretrend_power_test_h.csv"))

if (!is.null(power_h_at_sigma4$event_plot)) {
  ggsave(file.path(OUT_FIG, "phase6_a6_pretrend_power_test_h.pdf"),
         power_h_at_sigma4$event_plot, width = 9, height = 5)
}

# ---------------------------------------------------------------------------
# Test I
# ---------------------------------------------------------------------------
cat("\n=== Test I ===\n")
panel_i <- build_test_i_panel()
fit_i <- fit_and_pack(
  panel_i, treatment_col = "nace_regulated_dummy",
  group_re = "share",
  fe_re = "by_year + b_n",
  cluster_re = ~ buyer)
cat(sprintf("years included: %s\n",
            paste(fit_i$years, collapse = ", ")))

tVec_i <- fit_i$years - fit_i$ref_yr

# Calibrated alternative for Test I: a linear pre-trend large enough to
# produce a β̂_post equivalent to a doubling of the OLS headline (≈ 0.064)
# in absolute magnitude — would imply σ_cat ≤ 0.5 (twice the 95% CI lower
# bound). Slope = 0.064 / 7 ≈ 0.009/year (or its negative).
sigma_05_slope_i <- 0.009

power_i_at_sigma05 <- pretrends(
  betahat   = fit_i$betahat,
  sigma     = fit_i$sigma,
  deltatrue = sigma_05_slope_i * tVec_i,
  tVec      = tVec_i,
  referencePeriod = 0)
cat("\n[Test I] pretrends() against σ_cat ≤ 0.5 alternative:\n")
print(power_i_at_sigma05$df_power)

slope_50_i <- slope_for_power(
  sigma = fit_i$sigma,
  targetPower = 0.5,
  tVec = tVec_i,
  referencePeriod = 0)
slope_80_i <- slope_for_power(
  sigma = fit_i$sigma,
  targetPower = 0.8,
  tVec = tVec_i,
  referencePeriod = 0)
cat(sprintf("\n[Test I] slope at 50%% power = %.5f per year\n", slope_50_i))
cat(sprintf("[Test I] slope at 80%% power = %.5f per year\n", slope_80_i))

out_i <- data.table(
  measure = c("power against σ_cat≤0.5 alternative (slope 0.009/yr)",
              "slope at 50% power",
              "slope at 80% power"),
  value   = c(power_i_at_sigma05$df_power$Power[1L], slope_50_i, slope_80_i)
)
fwrite(out_i, file.path(OUT_TAB, "phase6_a6_pretrend_power_test_i.csv"))

if (!is.null(power_i_at_sigma05$event_plot)) {
  ggsave(file.path(OUT_FIG, "phase6_a6_pretrend_power_test_i.pdf"),
         power_i_at_sigma05$event_plot, width = 9, height = 5)
}

cat("\nDONE.\n")
