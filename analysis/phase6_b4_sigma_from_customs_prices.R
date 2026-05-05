# =============================================================================
# B4 (paper §5.2.5) — σ from observed customs prices
#
# Structural CES with EU and non-EU as the two arms, identified via observed
# customs unit-values:
#
#   log(s_{f,p,EU,t} / s_{f,p,nonEU,t})
#     = (1 - σ) · log(p_{p,EU,t} / p_{p,nonEU,t}) + α_{f,p} + δ_t + ε
#
# The relative-price ratio is endogenous (relative quantities and prices are
# jointly determined). Identification via shift-share IV: HS6-specific carbon
# intensity × Känzig structural carbon-policy shock (CPShock_t) acts as a
# relative-price shifter that affects EU prices through the carbon-policy
# channel (and non-EU prices only through the §B3-bounded pass-through).
#
# IV first stage:
#   log(p_EU / p_nonEU)_{p,t} = π · (carbon_intensity_p × CPShock_t)
#                              + α_p + δ_t + ε
#
# Prerequisites:
#   - customs_import_panel_extended.RData (preserves quantity)
#   - Känzig CPShock series (annual aggregation), expected at
#     ${PROC_DATA}/cpshock_annual.RData with columns (year, cpshock).
#   - HS6 carbon intensity, expected at
#     ${REPO_DIR}/data/concordances/hs6_carbon_intensity.csv
#     with columns (hs6, carbon_intensity).
#
# If any of the above is missing, the script reports what's missing and exits.
#
# Outputs:
#   ${OUT_TAB}/phase6_b4_sigma_first_stage.csv
#   ${OUT_TAB}/phase6_b4_sigma_iv.csv
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest)
})

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Inputs
# ---------------------------------------------------------------------------
ext_path <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
cps_path <- file.path(OUT_DATA, "cpshock_annual.RData")    # repo data/processed/, not NBB
ci_path  <- file.path(OUT_DATA, "hs6_carbon_intensity.csv") # built by phase6_build_hs6_carbon_intensity.R

missing_ok <- TRUE
for (p in c(ext_path, cps_path, ci_path)) {
  if (!file.exists(p)) {
    cat("MISSING:", p, "\n")
    missing_ok <- FALSE
  }
}
if (!missing_ok) {
  cat("\nB4 cannot run without all three inputs. Build them first:\n")
  cat("  - phase6_build_customs_panel_extended.R\n")
  cat("  - cpshock_annual: aggregate Känzig CPS series to annual\n")
  cat("  - hs6_carbon_intensity: per-HS6 carbon intensity (kg CO2 / EUR or similar)\n")
  quit(status = 1)
}

load(ext_path); panel <- as.data.table(panel)
load(cps_path)  # expects object `cpshock_annual` with cols year, cpshock
ci <- fread(ci_path)

# ---------------------------------------------------------------------------
# 2. Build (importer × HS6 × bloc × year) panel with prices and shares
# ---------------------------------------------------------------------------
reg <- panel[is_regulated_product == 1L &
              !is.na(value) & value > 0 &
              !is.na(quantity) & quantity > 0]
reg[, hs6 := substr(cn8, 1, 6)]
reg[, source_eu := 1L - is_non_ets_country]

# Aggregate to (importer × HS6 × bloc × year).
agg <- reg[, .(value = sum(value), quantity = sum(quantity)),
           by = .(vat, hs6, source_eu, year)]
agg[, p_unit := value / quantity]

# Reshape to wide: EU and non-EU side-by-side.
w <- dcast(agg, vat + hs6 + year ~ source_eu,
           value.var = c("value", "quantity", "p_unit"),
           fill = NA)
setnames(w, c("value_0", "value_1"), c("value_nonEU", "value_EU"))
setnames(w, c("quantity_0", "quantity_1"), c("quantity_nonEU", "quantity_EU"))
setnames(w, c("p_unit_0", "p_unit_1"), c("p_nonEU", "p_EU"))

w <- w[!is.na(value_EU) & !is.na(value_nonEU) &
        value_EU > 0 & value_nonEU > 0 &
        !is.na(p_EU) & !is.na(p_nonEU)]

w[, total := value_EU + value_nonEU]
w[, s_EU := value_EU / total]
w[, s_nonEU := value_nonEU / total]
w[, log_share_ratio := log(s_EU / s_nonEU)]
w[, log_price_ratio := log(p_EU / p_nonEU)]

cat(sprintf("Cell-years with both blocs: %d (importers: %d, HS6: %d)\n",
            nrow(w), uniqueN(w$vat), uniqueN(w$hs6)))

# ---------------------------------------------------------------------------
# 3. Build the IV: HS6 carbon intensity × CPShock
# ---------------------------------------------------------------------------
w <- merge(w, cpshock_annual[, .(year, cpshock)], by = "year", all.x = TRUE)
w <- merge(w, ci[, .(hs6, carbon_intensity)], by = "hs6", all.x = TRUE)
w <- w[!is.na(cpshock) & !is.na(carbon_intensity)]
w[, iv := carbon_intensity * cpshock]

cat(sprintf("After IV merge: %d cell-years\n", nrow(w)))

# ---------------------------------------------------------------------------
# 4. First stage: log(p_EU / p_nonEU) on (carbon_intensity × CPShock)
# ---------------------------------------------------------------------------
fs <- tryCatch(
  feols(log_price_ratio ~ iv | vat^hs6 + year,
        data = w, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(fs)) {
  cat("First stage:\n"); print(fs)
  ct_fs <- as.data.table(coeftable(fs), keep.rownames = "term")
  setnames(ct_fs, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  ct_fs[, F_stat := fitstat(fs, "ivf1")$ivf1]
  fwrite(ct_fs, file.path(OUT_TAB, "phase6_b4_sigma_first_stage.csv"))
}

# ---------------------------------------------------------------------------
# 5. IV regression of relative shares on relative prices
# ---------------------------------------------------------------------------
m_iv <- tryCatch(
  feols(log_share_ratio ~ 1 | vat^hs6 + year | log_price_ratio ~ iv,
        data = w, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_iv)) {
  cat("IV results:\n"); print(m_iv)
  ct_iv <- as.data.table(coeftable(m_iv), keep.rownames = "term")
  setnames(ct_iv, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))

  # Map coefficient on log_price_ratio to σ:
  #   coef = (1 - σ)  =>  σ = 1 - coef
  coef_lpr <- ct_iv[grepl("log_price_ratio", term), est][1]
  se_lpr   <- ct_iv[grepl("log_price_ratio", term), se][1]
  if (length(coef_lpr) == 1L && !is.na(coef_lpr)) {
    sigma_hat <- 1 - coef_lpr
    sigma_lo  <- 1 - (coef_lpr + 1.96 * se_lpr)
    sigma_hi  <- 1 - (coef_lpr - 1.96 * se_lpr)
    ct_iv[, sigma_hat := NA_real_]
    ct_iv[grepl("log_price_ratio", term), sigma_hat := sigma_hat]
    ct_iv[grepl("log_price_ratio", term), sigma_ci_lo := sigma_lo]
    ct_iv[grepl("log_price_ratio", term), sigma_ci_hi := sigma_hi]
    cat(sprintf("\nImplied σ = %.3f, 95%% CI [%.3f, %.3f]\n",
                sigma_hat, sigma_lo, sigma_hi))
  }
  fwrite(ct_iv, file.path(OUT_TAB, "phase6_b4_sigma_iv.csv"))
}

# OLS comparison.
m_ols <- tryCatch(
  feols(log_share_ratio ~ log_price_ratio | vat^hs6 + year,
        data = w, cluster = c("vat", "hs6"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_ols)) {
  cat("\nOLS comparison:\n"); print(m_ols)
}
