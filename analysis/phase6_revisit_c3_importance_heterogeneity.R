###############################################################################
# phase6_revisit_c3_importance_heterogeneity.R
#
# PURPOSE:
#   Component 3 of the China-shock revisit. Test the hypothesis that
#   substitution toward Chinese imports is concentrated in (importer i, HS6 k)
#   pairs where HS6 k is a meaningful share of importer i's input bill.
#
#   Theory: with a fixed cost F of finding/qualifying a Chinese supplier
#   for product k, importer i switches origin only if the gain from
#   switching exceeds F. The gain scales with input_share_{i,k} * Delta P,
#   so switching is concentrated in high-input_share pairs.
#
#   Test (h = 10):
#
#     dlog(ChinaShare_{i,k} / NonChinaShare_{i,k})
#       = alpha
#       + beta_high * dlog(P_China_k / P_nonChina_k) * 1{input_share high}
#       + beta_low  * dlog(P_China_k / P_nonChina_k) * 1{input_share low}
#       + gamma     * 1{input_share high}
#       + FE_NACE2d
#       + e
#
#   instrumented with delta_china_share_k * 1{high} and delta_china_share_k *
#   1{low}. Headline: H0: beta_high = beta_low (no importance heterogeneity);
#   H1 (predicted): beta_high < beta_low (so sigma_high > sigma_low).
#
#   "input_share_{i,k,2002}" is i's spending on HS6 k as a share of i's
#   total measured inputs in 2002 (B2B purchases + customs imports).
#
# INPUT:
#   data/processed/phase6_revisit_importer_hs6_panel.RData
#     (importer_hs6_panel: built by Component 1; the h=10 panel.)
#   data/processed/phase6_china_shifter_2002_2012.RData (HS6 IV, h=10)
#   data/processed/phase6_belgian_unit_values.RData     (HS6 prices, h=10)
#   ${PROC_DATA}/b2b_selected_sample.RData              (B2B purchases for denominator)
#   ${PROC_DATA}/customs_selected_sample.RData          (long-form customs, for total imports)
#
# OUTPUT:
#   data/processed/phase6_revisit_c3_results.RData
#   output/tables/phase6_revisit_c3_summary.csv
#   output/tables/phase6_revisit_c3_summary.txt
#   output/figures/phase6_revisit_c3_importance_heterogeneity.pdf
#
# CAVEATS:
#   - "Total inputs" = b2b_purchases (B2B sample, downsampled on local-1) +
#     customs_imports (selected-sample customs, restricted to AA-sample VATs).
#     On local-1 the B2B denominator is downsampled; on RMD it's the full
#     network. Neither captures unobserved imported services or capital goods.
#   - Currency: NBB customs cn_value and B2B corr_sales_ij are both nominal
#     EUR (NBB convention) -- no FX conversion needed in this script.
#     (BACI is in thousand USD but is not used here as a denominator.)
#   - Importance bins: we use median split per NACE 2d to avoid sectoral
#     composition (electronics importers all have high input_share for HS 85
#     codes but vs each other; comparison should be within-sector).
#   - Two-way interaction means TWO instruments needed for two endogenous
#     regressors (high-side and low-side relative-price interactions).
#     Sanderson-Windmeijer F reported for each.
#   - The headline test is a one-sided contrast: beta_high < beta_low.
#     Reported as a Wald test on the difference.
###############################################################################

rm(list = ls())

library(data.table)
library(fixest)
library(ggplot2)
library(scales)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

BASE_YEAR <- 2002L
END_YEAR  <- 2012L
CHINA_ISO <- c("CN", "HK")

# ---- 1. Load Component 1 panel ----
load(file.path(OUT_DATA, "phase6_revisit_importer_hs6_panel.RData"))
# importer_hs6_panel: vat x hs6 x {v_china_base, v_nonchina_base,
#                                   v_china_end, v_nonchina_end,
#                                   dlog_share_ratio, total_2002,
#                                   delta_china_share, dlog_p_*, nace2d, ...}
panel <- as.data.table(importer_hs6_panel)
cat("Component 1 panel rows:", nrow(panel), "\n")

# ---- 2. Build importer total input bill in BASE_YEAR ----
# Customs imports (all CN8, both China and non-China, from selected sample)
load(file.path(PROC_DATA, "customs_selected_sample.RData"))
cust <- as.data.table(df_customs_selected_sample)
rm(df_customs_selected_sample)
cust <- cust[year == BASE_YEAR]
imports_total <- cust[, .(imports_2002 = sum(value, na.rm = TRUE)),
                       by = vat]

# B2B purchases (i as buyer => vat_j_ano)
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b, c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
              c("vat_supplier", "vat_buyer", "corr_sales"))
b2b_purch <- b2b[year == BASE_YEAR,
                  .(b2b_purchases_2002 = sum(corr_sales, na.rm = TRUE)),
                  by = .(vat = vat_buyer)]

# Total input bill = imports + B2B purchases (in EUR; b2b is EUR, customs is EUR too)
input_total <- merge(imports_total, b2b_purch, by = "vat", all = TRUE)
input_total[is.na(imports_2002),     imports_2002 := 0]
input_total[is.na(b2b_purchases_2002), b2b_purchases_2002 := 0]
input_total[, total_inputs_2002 := imports_2002 + b2b_purchases_2002]
input_total <- input_total[total_inputs_2002 > 0]
cat("Importers with positive total inputs in 2002:", nrow(input_total), "\n")

# ---- 3. Build input_share_{i,k,2002} = total_2002 / total_inputs_2002 ----
panel <- merge(panel, input_total[, .(vat, total_inputs_2002)],
                by = "vat", all.x = FALSE)
panel[, input_share_ik := total_2002 / total_inputs_2002]
summary(panel$input_share_ik)

# ---- 4. Define importance bins WITHIN NACE 2d ----
panel[, importance_bin := ifelse(
  input_share_ik > median(input_share_ik, na.rm = TRUE),
  "high", "low"), by = nace2d]
panel[, is_high := as.integer(importance_bin == "high")]
panel[, is_low  := 1L - is_high]

cat("Importance bin counts:\n")
print(panel[, .N, by = importance_bin])

# ---- 5. Build interaction regressors and instruments ----
panel[, dlog_p_ratio_high := dlog_p_ratio * is_high]
panel[, dlog_p_ratio_low  := dlog_p_ratio * is_low]
panel[, iv_high           := delta_china_share * is_high]
panel[, iv_low            := delta_china_share * is_low]

panel_reg <- panel[!is.na(dlog_share_ratio) & !is.na(delta_china_share) &
                    !is.na(dlog_p_ratio) & !is.na(nace2d) &
                    !is.na(input_share_ik)]

# ---- 6. 2SLS with two endogenous regressors / two instruments ----
m_het <- feols(
  dlog_share_ratio ~ is_high | nace2d |
    dlog_p_ratio_high + dlog_p_ratio_low ~ iv_high + iv_low,
  data    = panel_reg,
  cluster = ~ hs6
)
print(summary(m_het))

# Linear test: H0: beta_high = beta_low
wald <- tryCatch(
  wald(m_het, "fit_dlog_p_ratio_high - fit_dlog_p_ratio_low = 0"),
  error = function(e) NULL
)

# ---- 7. Compare to a per-bin separate 2SLS for sanity ----
m_high <- feols(
  dlog_share_ratio ~ 1 | nace2d | dlog_p_ratio ~ delta_china_share,
  data    = panel_reg[importance_bin == "high"],
  cluster = ~ hs6
)
m_low <- feols(
  dlog_share_ratio ~ 1 | nace2d | dlog_p_ratio ~ delta_china_share,
  data    = panel_reg[importance_bin == "low"],
  cluster = ~ hs6
)

extract_iv <- function(m, label, endo) {
  ce <- coeftable(m)
  rn <- if (paste0("fit_", endo) %in% rownames(ce)) paste0("fit_", endo)
        else grep("^fit_", rownames(ce), value = TRUE)[1]
  est <- ce[rn, "Estimate"]
  se  <- ce[rn, "Std. Error"]
  ci  <- est + c(-1, 1) * 1.96 * se
  fs_F <- tryCatch(unname(fitstat(m, "ivf1", simplify = TRUE)["stat"]),
                    error = function(e) NA_real_)
  data.table(
    spec     = label,
    n        = nobs(m),
    beta     = est,
    se       = se,
    ci_lo    = ci[1],
    ci_hi    = ci[2],
    sigma    = 1 - est,
    sigma_lo = 1 - ci[2],
    sigma_hi = 1 - ci[1],
    f_stat   = fs_F
  )
}

results_dt <- rbindlist(list(
  extract_iv(m_het,  "Pooled w/ interaction (high)", "dlog_p_ratio_high"),
  extract_iv(m_het,  "Pooled w/ interaction (low)",  "dlog_p_ratio_low"),
  extract_iv(m_high, "Separate IV: high-importance", "dlog_p_ratio"),
  extract_iv(m_low,  "Separate IV: low-importance",  "dlog_p_ratio")
))

print(results_dt, digits = 4)
fwrite(results_dt, file.path(OUTPUT_TAB, "phase6_revisit_c3_summary.csv"))
cat("Saved:", file.path(OUTPUT_TAB, "phase6_revisit_c3_summary.csv"), "\n")

save(results_dt, m_het, m_high, m_low, panel_reg, wald,
     file = file.path(OUT_DATA, "phase6_revisit_c3_results.RData"))
cat("Saved:", file.path(OUT_DATA, "phase6_revisit_c3_results.RData"), "\n")

# ---- 8. Figure: sigma_high vs sigma_low with CIs ----
plot_dt <- results_dt[grepl("Separate IV", spec)]
plot_dt[, bin := ifelse(grepl("high", spec, ignore.case = TRUE),
                         "high importance", "low importance")]

p_het <- ggplot(plot_dt, aes(x = bin, y = sigma)) +
  geom_hline(yintercept = 1, linetype = "dashed", colour = "grey40") +
  geom_errorbar(aes(ymin = sigma_lo, ymax = sigma_hi),
                width = 0.3, colour = "steelblue") +
  geom_point(size = 4, colour = "steelblue") +
  labs(
    title    = "Component 3 -- Heterogeneity by importance of HS6 in importer's input bill",
    subtitle = "sigma estimated separately for (i,k) pairs where input_share_{i,k,2002} is above (high) vs below (low) within-NACE2d median.",
    x        = NULL,
    y        = "Implied sigma",
    caption  = "Source: BACI HS02 V202601 + Belgian customs + B2B selected sample. Component 3, ALTERNATIVE_SHOCKS_TO_ESTIMATE_ELASTICITY.md."
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.title.position = "plot",
        plot.subtitle = element_text(colour = "grey30", size = 9))

ggsave(file.path(OUTPUT_FIG, "phase6_revisit_c3_importance_heterogeneity.pdf"),
       p_het, width = 8, height = 5)
cat("Saved:", file.path(OUTPUT_FIG, "phase6_revisit_c3_importance_heterogeneity.pdf"), "\n")

# ---- 9. Readable summary ----
sink(file.path(OUTPUT_TAB, "phase6_revisit_c3_summary.txt"))

cat("================================================================\n")
cat("Component 3 -- Importance heterogeneity in China-origin sigma\n")
cat("Generated by analysis/phase6_revisit_c3_importance_heterogeneity.R\n")
cat("================================================================\n\n")

cat("Specification (pooled with interaction):\n")
cat("  dlog(ChinaShare/NonChinaShare)\n")
cat("    = alpha + beta_high * dlog(P_China/P_nonChina) * 1{high}\n")
cat("            + beta_low  * dlog(P_China/P_nonChina) * 1{low}\n")
cat("            + gamma * 1{high} + FE_NACE2d + e\n\n")
cat("  Two endogenous regressors: dlog_p_ratio_high, dlog_p_ratio_low.\n")
cat("  Two instruments         : iv_high = delta_china_share * 1{high},\n")
cat("                            iv_low  = delta_china_share * 1{low}.\n")
cat("  Importance bin: median split of input_share_{i,k,2002} within NACE 2d.\n")
cat("  input_share_{i,k,2002} = total_2002(i,k) / (imports_2002(i) + b2b_purchases_2002(i)).\n\n")

cat("Results:\n")
print(results_dt, digits = 4)
cat("\n")

cat("Wald test H0: beta_high = beta_low (pooled-with-interaction model)\n")
if (!is.null(wald)) {
  print(wald)
} else {
  cat("  (wald() failed; check model object directly.)\n")
}
cat("\n")

cat("Predicted direction: beta_high < beta_low, i.e. sigma_high > sigma_low.\n")
sep <- results_dt[grepl("Separate IV", spec)]
if (nrow(sep) == 2) {
  s_high <- sep[grepl("high", spec, ignore.case = TRUE)]
  s_low  <- sep[grepl("low",  spec, ignore.case = TRUE)]
  cat(sprintf("  sigma_high = %.2f (95%% CI [%.2f, %.2f], N = %d)\n",
              s_high$sigma, s_high$sigma_lo, s_high$sigma_hi, s_high$n))
  cat(sprintf("  sigma_low  = %.2f (95%% CI [%.2f, %.2f], N = %d)\n",
              s_low$sigma, s_low$sigma_lo, s_low$sigma_hi, s_low$n))
  if (!is.na(s_high$sigma) && !is.na(s_low$sigma)) {
    if (s_high$sigma > s_low$sigma + 0.5) {
      cat("  PASS: high-importance sigma materially exceeds low-importance.\n")
    } else if (s_high$sigma > s_low$sigma) {
      cat("  WEAK: ordering correct but gap small.\n")
    } else {
      cat("  FAIL: no importance heterogeneity in the predicted direction.\n")
    }
  }
}

cat("================================================================\n")
sink()
cat("Saved:", file.path(OUTPUT_TAB, "phase6_revisit_c3_summary.txt"), "\n")

cat("\nDone.\n")
