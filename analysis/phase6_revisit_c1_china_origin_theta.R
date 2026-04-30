###############################################################################
# phase6_revisit_c1_china_origin_theta.R
#
# PURPOSE:
#   Component 1 of the China-shock revisit
#   (ALTERNATIVE_SHOCKS_TO_ESTIMATE_ELASTICITY.md, "Revisiting the China shock"
#   section). Estimate the Armington elasticity of substitution sigma across
#   origins for HS6 product k, among Belgian importers.
#
#   Structural form (CES across origins):
#     ChinaShare_{i,k} / NonChinaShare_{i,k}  proportional to
#       (P^China_k / P^non-China_k)^(1 - sigma)
#
#   Long-difference 2SLS at h = 10 (2002 -> 2012):
#     dlog (ChinaShare_{i,k} / NonChinaShare_{i,k})
#       = alpha + (1 - sigma) * dlog (P^China_k / P^non-China_k)
#         + FE_{NACE2d_i}  +  e_{i,k}
#     instrumented with the BACI shifter delta_china_share_k_EU26 from E1.
#
#   Two robustness specs are reported alongside the headline:
#     (R1) "asymmetric": only China-side price as endogenous regressor,
#          non-China price absorbed by HS6 FE. Closer to BLP's setup.
#     (R2) "reduced form only": just regress dlog share-ratio on the IV.
#          Useful when the second stage is noisy.
#
#   This script BUILDS the importer x HS6 x year master panel that
#   Components 2 and 3 will reuse (cached as
#     OUT_DATA/phase6_revisit_importer_hs6_panel.RData).
#
# INPUT:
#   data/processed/phase6_china_shifter_2002_2012.RData
#     china_shifter_hs6: HS6 x {china_share_2002, china_share_2012,
#                                delta_china_share, value_total_2002, ...}
#   data/processed/phase6_belgian_unit_values.RData
#     uv_panel: HS6 x year x {uv_china, uv_nonchina, v_china_be, v_nonchina_be}
#   ${PROC_DATA}/customs_selected_sample_china.RData
#     df_customs_selected_sample_china: vat x hs6 x year x source x value,
#     where source in {china, nonchina}. Built by
#     analysis/phase6_build_customs_selected_sample.R from raw customs +
#     AA-selected-sample VATs.
#   ${PROC_DATA}/annual_accounts_selected_sample_key_variables.RData
#     df_annual_accounts_selected_sample_key_variables: vat, year, nace5d, ...
#     for importer NACE2d (used as a fixed effect).
#
# OUTPUT:
#   data/processed/phase6_revisit_importer_hs6_panel.RData
#     importer_hs6_panel: vat x hs6 x year x {v_china, v_nonchina,
#                                              china_share, log_share_ratio}
#     importer_baseline:  vat x {nace2d, total_imports_2002}
#   data/processed/phase6_revisit_c1_results.RData
#   output/tables/phase6_revisit_c1_summary.csv
#   output/tables/phase6_revisit_c1_summary.txt
#   output/figures/phase6_revisit_c1_first_and_second_stage.pdf
#
# CAVEATS:
#   - Customs raw is RMD-only in production. On local-1 the path resolves to
#     the downsampled real-customs file at NBB_data/raw/NBB/import_export_ANO.dta
#     -- prototyping numbers will differ from RMD final numbers.
#   - Sample restriction (intensive margin): keep (vat, hs6) cells with
#     v_china > 0 AND v_nonchina > 0 in BOTH endpoints. Extensive-margin
#     transitions handled separately in the IHS robustness (Component 1b,
#     not in this script).
#   - Origin definition: China = partner_iso2 in {"CN", "HK"} (Hong Kong
#     re-exports, BLP convention -- can switch to CN-only as robustness).
#   - 1% tails of dlog(P) trimmed within HS6 (P&R / E2 convention).
#   - Belgium importers' selection: importers != Belgian-firm population.
#     This caveat is the central scope statement in the paper.
#   - Sigma sign convention: beta = (1 - sigma) on log(P_China/P_nonChina).
#     beta < 0 => sigma > 1 (substitutes), beta > 0 => sigma < 1 (complements).
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

# ---- Tunables ----
BASE_YEAR <- 2002L
END_YEAR  <- 2012L          # h = 10 headline
CHINA_ISO <- c("CN", "HK")  # Hong Kong included as China-source by default
TRIM_PCT  <- 0.01

# ---- 1. Load BACI shifter (from E1) and BACI EU-aggregate prices (from E2) ----
load(file.path(OUT_DATA, "phase6_china_shifter_2002_2012.RData"))
# china_shifter_hs6: k, china_share_2002, china_share_2012, delta_china_share, ...
load(file.path(OUT_DATA, "phase6_belgian_unit_values.RData"))
# uv_panel: k, year, uv_china, uv_nonchina, v_china_be, v_nonchina_be

cat("HS6 shifter rows :", nrow(china_shifter_hs6), "\n")
cat("UV panel rows    :", nrow(uv_panel), "\n")

# ---- 2. Build HS6-level price changes from BACI uv_panel ----
build_price_panel <- function(end_year) {
  base <- uv_panel[year == BASE_YEAR,
                   .(k, uv_china_base = uv_china, uv_nonchina_base = uv_nonchina)]
  endd <- uv_panel[year == end_year,
                   .(k, uv_china_end = uv_china, uv_nonchina_end = uv_nonchina)]
  pp <- merge(base, endd, by = "k")
  pp[uv_china_base > 0 & uv_china_end > 0,
     dlog_p_china := log(uv_china_end) - log(uv_china_base)]
  pp[uv_nonchina_base > 0 & uv_nonchina_end > 0,
     dlog_p_nonchina := log(uv_nonchina_end) - log(uv_nonchina_base)]
  pp[, dlog_p_ratio := dlog_p_china - dlog_p_nonchina]
  pp[, end_year := end_year]
  pp
}
price_panel_h10 <- build_price_panel(END_YEAR)

# Trim 1% tails of price changes (E2 convention)
trim_tails <- function(dt, col) {
  x <- dt[[col]]
  if (sum(!is.na(x)) > 50) {
    lo <- quantile(x, TRIM_PCT,     na.rm = TRUE)
    hi <- quantile(x, 1 - TRIM_PCT, na.rm = TRUE)
    dt[!is.na(get(col)) & (get(col) < lo | get(col) > hi), (col) := NA]
  }
  dt
}
for (col in c("dlog_p_china", "dlog_p_nonchina", "dlog_p_ratio")) {
  price_panel_h10 <- trim_tails(price_panel_h10, col)
}

# ---- 3. Load customs selected sample (china-vs-nonchina, pre-aggregated) ----
load(file.path(PROC_DATA, "customs_selected_sample_china.RData"))
cust <- as.data.table(df_customs_selected_sample_china)
rm(df_customs_selected_sample_china)
cust <- cust[year %in% c(BASE_YEAR, END_YEAR)]

# Reshape wide: v_china, v_nonchina
cust_w <- dcast(cust, vat + hs6 + year ~ source,
                value.var = "value", fill = 0)
setnames(cust_w, c("china", "nonchina"), c("v_china", "v_nonchina"))
cat("Importer x HS6 x year rows:", nrow(cust_w), "\n")

# Long-difference panel: keep (vat, hs6) with both endpoints
cust_w_base <- cust_w[year == BASE_YEAR,
                      .(vat, hs6, v_china_base = v_china,
                        v_nonchina_base = v_nonchina)]
cust_w_end  <- cust_w[year == END_YEAR,
                      .(vat, hs6, v_china_end = v_china,
                        v_nonchina_end = v_nonchina)]
panel_h10 <- merge(cust_w_base, cust_w_end, by = c("vat", "hs6"))
cat("(vat, hs6) cells with both endpoints:", nrow(panel_h10), "\n")

# Intensive-margin restriction: positive China and non-China imports in both years
panel_h10 <- panel_h10[
  v_china_base > 0 & v_china_end > 0 &
  v_nonchina_base > 0 & v_nonchina_end > 0
]
cat("After intensive-margin restriction:", nrow(panel_h10), "\n")

# Outcome: dlog (ChinaShare / NonChinaShare) = dlog (v_china / v_nonchina)
panel_h10[, dlog_share_ratio :=
            (log(v_china_end) - log(v_nonchina_end)) -
            (log(v_china_base) - log(v_nonchina_base))]

# Importance weight: total spending on HS6 k by importer i in 2002
# (used for cell weights; will also feed Component 3)
panel_h10[, total_2002 := v_china_base + v_nonchina_base]

# Trim 1% tails of the outcome
panel_h10 <- trim_tails(panel_h10, "dlog_share_ratio")

# ---- 4. Importer NACE2d FE join (selected-sample annual accounts) ----
load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample_key_variables)
rm(df_annual_accounts_selected_sample_key_variables)
aa <- aa[year == BASE_YEAR,
         .(vat,
           nace4d = substr(sprintf("%05d", as.integer(nace5d)), 1, 4))]
aa[, nace2d := substr(nace4d, 1, 2)]
aa <- unique(aa[, .(vat, nace2d, nace4d)])

# Inner-join: restrict customs panel to importers in the selected sample.
# This is the canonical sample frame used elsewhere in the project (Phase 3,
# network_exposure_regs_*, etc.).
panel_h10 <- merge(panel_h10, aa, by = "vat", all.x = FALSE)
cat("After restriction to selected-sample importers:",
    nrow(panel_h10), "(vat, hs6) cells\n")

# ---- 5. Merge with HS6 IV (BACI shifter) and HS6 prices ----
shifter_h10 <- china_shifter_hs6[, .(k, delta_china_share, importance_weight)]
setnames(shifter_h10, "k", "hs6")
panel_h10 <- merge(panel_h10, shifter_h10, by = "hs6", all.x = FALSE)

setnames(price_panel_h10, "k", "hs6")
panel_h10 <- merge(panel_h10,
                    price_panel_h10[, .(hs6, dlog_p_china, dlog_p_nonchina, dlog_p_ratio)],
                    by = "hs6", all.x = TRUE)

cat("Final h=10 panel rows for 2SLS:",
    sum(!is.na(panel_h10$dlog_share_ratio) &
        !is.na(panel_h10$dlog_p_ratio) &
        !is.na(panel_h10$delta_china_share)),
    "\n")

# ---- 6. 2SLS regressions ----
panel_reg <- panel_h10[!is.na(dlog_share_ratio) & !is.na(delta_china_share) &
                        !is.na(dlog_p_ratio) & !is.na(nace2d)]

# Headline: relative-price form, NACE2d FE, IV = BACI shifter
m_iv <- feols(
  dlog_share_ratio ~ 1 | nace2d | dlog_p_ratio ~ delta_china_share,
  data    = panel_reg,
  cluster = ~ hs6
)

# Asymmetric (R1): China-side price only, instrumented by IV; non-China price as control
m_iv_asym <- feols(
  dlog_share_ratio ~ dlog_p_nonchina | nace2d |
    dlog_p_china ~ delta_china_share,
  data    = panel_reg[!is.na(dlog_p_china) & !is.na(dlog_p_nonchina)],
  cluster = ~ hs6
)

# Reduced form (R2): outcome on IV directly
m_rf <- feols(
  dlog_share_ratio ~ delta_china_share | nace2d,
  data    = panel_reg,
  cluster = ~ hs6
)

# First stage (explicit, for diagnostics)
m_fs <- feols(
  dlog_p_ratio ~ delta_china_share | nace2d,
  data    = panel_reg,
  cluster = ~ hs6
)

# ---- 7. Extract results into a tidy table ----
extract_iv <- function(m, label, endo) {
  ce <- coeftable(m)
  rn <- if (paste0("fit_", endo) %in% rownames(ce)) paste0("fit_", endo) else endo
  if (!rn %in% rownames(ce)) rn <- grep("^fit_", rownames(ce), value = TRUE)[1]
  est <- ce[rn, "Estimate"]
  se  <- ce[rn, "Std. Error"]
  ci  <- est + c(-1, 1) * 1.96 * se
  data.table(
    spec    = label,
    n       = nobs(m),
    beta    = est,
    se      = se,
    ci_lo   = ci[1],
    ci_hi   = ci[2],
    sigma   = 1 - est,
    sigma_lo = 1 - ci[2],
    sigma_hi = 1 - ci[1]
  )
}

extract_ols <- function(m, label, var) {
  ce <- coeftable(m)
  est <- ce[var, "Estimate"]
  se  <- ce[var, "Std. Error"]
  data.table(spec = label, n = nobs(m), beta = est, se = se,
             ci_lo = est - 1.96 * se, ci_hi = est + 1.96 * se,
             sigma = NA_real_, sigma_lo = NA_real_, sigma_hi = NA_real_)
}

results_dt <- rbindlist(list(
  extract_iv(m_iv,      "IV: relative-price form (headline)", "dlog_p_ratio"),
  extract_iv(m_iv_asym, "IV: asymmetric (China-side only)",   "dlog_p_china"),
  extract_ols(m_rf,     "Reduced form (outcome on IV)",       "delta_china_share"),
  extract_ols(m_fs,     "First stage (price-ratio on IV)",    "delta_china_share")
), fill = TRUE)

# First-stage F from the IV model. fitstat() returns a length-4 named vector
# (stat, p, df1, df2); we only want the F statistic itself.
fs_F_iv <- tryCatch(
  unname(fitstat(m_iv, "ivf1", simplify = TRUE)["stat"]),
  error = function(e) NA_real_
)
results_dt[spec == "IV: relative-price form (headline)", f_stat := fs_F_iv]

print(results_dt, digits = 4)

fwrite(results_dt, file.path(OUTPUT_TAB, "phase6_revisit_c1_summary.csv"))
cat("Saved:", file.path(OUTPUT_TAB, "phase6_revisit_c1_summary.csv"), "\n")

save(panel_h10, panel_reg, results_dt,
     m_iv, m_iv_asym, m_rf, m_fs,
     file = file.path(OUT_DATA, "phase6_revisit_c1_results.RData"))
cat("Saved:", file.path(OUT_DATA, "phase6_revisit_c1_results.RData"), "\n")

# Save the master importer x hs6 panel for Components 2 and 3 to reuse
importer_hs6_panel <- panel_h10
importer_baseline  <- aa
save(importer_hs6_panel, importer_baseline, price_panel_h10,
     file = file.path(OUT_DATA, "phase6_revisit_importer_hs6_panel.RData"))
cat("Saved:", file.path(OUT_DATA, "phase6_revisit_importer_hs6_panel.RData"), "\n")

# ---- 8. Diagnostic figure: first stage + reduced form bin-scatters ----
make_binscatter <- function(dt, x, y, label) {
  d <- dt[!is.na(get(x)) & !is.na(get(y))]
  if (nrow(d) < 50) return(data.table())
  qb <- unique(quantile(d[[x]], probs = seq(0, 1, length.out = 41), na.rm = TRUE))
  d[, bin := cut(get(x), breaks = qb, include.lowest = TRUE)]
  out <- d[, .(x = mean(get(x), na.rm = TRUE),
                y = mean(get(y), na.rm = TRUE),
                n = .N), by = bin][!is.na(x) & !is.na(y)]
  out[, panel := label]
  out
}

bs_fs <- make_binscatter(panel_reg, "delta_china_share", "dlog_p_ratio",
                          "First stage: dlog(P_China/P_nonChina) on IV")
bs_rf <- make_binscatter(panel_reg, "delta_china_share", "dlog_share_ratio",
                          "Reduced form: dlog(ChinaShare/NonChinaShare) on IV")
bs <- rbind(bs_fs, bs_rf)

p_diag <- ggplot(bs, aes(x = x, y = y, size = n)) +
  geom_point(alpha = 0.6, colour = "steelblue") +
  geom_smooth(method = "lm", se = TRUE, colour = "darkred", linewidth = 0.7) +
  facet_wrap(~ panel, scales = "free_y") +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_size_continuous(guide = "none", range = c(1, 5)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey40") +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey40") +
  labs(
    title    = sprintf("Component 1 -- 2SLS at h = %d (%d -> %d)",
                       END_YEAR - BASE_YEAR, BASE_YEAR, END_YEAR),
    subtitle = sprintf("First-stage F = %.1f. Headline IV beta = %.3f (sigma = %.2f, 95%% CI [%.2f, %.2f]).",
                       results_dt[spec == "IV: relative-price form (headline)", f_stat],
                       results_dt[spec == "IV: relative-price form (headline)", beta],
                       results_dt[spec == "IV: relative-price form (headline)", sigma],
                       results_dt[spec == "IV: relative-price form (headline)", sigma_lo],
                       results_dt[spec == "IV: relative-price form (headline)", sigma_hi]),
    x        = "Delta-ChinaShare_k (BACI EU26-excl-BE), 2002 -> 2012",
    y        = NULL,
    caption  = "Source: BACI HS02 V202601 + Belgian customs. Component 1, ALTERNATIVE_SHOCKS_TO_ESTIMATE_ELASTICITY.md."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        plot.title.position = "plot",
        plot.subtitle = element_text(colour = "grey30", size = 9))

ggsave(file.path(OUTPUT_FIG, "phase6_revisit_c1_first_and_second_stage.pdf"),
       p_diag, width = 11, height = 5)
cat("Saved:", file.path(OUTPUT_FIG, "phase6_revisit_c1_first_and_second_stage.pdf"), "\n")

# ---- 9. Readable summary ----
sink(file.path(OUTPUT_TAB, "phase6_revisit_c1_summary.txt"))

cat("================================================================\n")
cat("Component 1 -- China-origin Armington elasticity, h = 10\n")
cat("Generated by analysis/phase6_revisit_c1_china_origin_theta.R\n")
cat("================================================================\n\n")

cat("Specification:\n")
cat("  dlog(ChinaShare_{i,k} / NonChinaShare_{i,k})\n")
cat("    = alpha + (1 - sigma) * dlog(P^China_k / P^non-China_k)\n")
cat("      + FE_{NACE2d_i} + e\n\n")
cat("  IV: delta_china_share_k (BACI EU26-excl-BE, 2002 -> 2012, from E1).\n\n")
cat("  Sample: Belgian customs importers with positive China and non-China\n")
cat("  imports of HS6 k in both endpoints. Excludes self-imports (BE).\n")
cat("  China origin: ", paste(CHINA_ISO, collapse = " + "), "\n", sep = "")
cat("  Trim: 1% tails of dlog(P_ratio) and dlog(share_ratio).\n\n")

cat("Results:\n")
print(results_dt, digits = 4)
cat("\n")

cat("Reading the headline:\n")
hdr <- results_dt[spec == "IV: relative-price form (headline)"]
cat(sprintf("  beta on dlog(P_China/P_nonChina) = %.3f (SE %.3f)\n",
            hdr$beta, hdr$se))
cat(sprintf("  Implied sigma = 1 - beta            = %.2f (95%% CI [%.2f, %.2f])\n",
            hdr$sigma, hdr$sigma_lo, hdr$sigma_hi))
cat(sprintf("  First-stage F                      = %.1f\n", hdr$f_stat))
cat("\n")
cat("Sanity checks vs literature (long-run import-origin sigma):\n")
cat("  BLP (2022) LR trade elasticity: -1.75 to -2.25 (their epsilon^h>=7).\n")
cat("    epsilon = 1 - sigma in our notation, so their sigma in [2.75, 3.25].\n")
cat("  AIK (2014) median sigma across HS-6: ~3.5 (US importers).\n")
cat("  Pure CES with sigma = 1: log(China/nonChina) shares move 1-for-1\n")
cat("    in opposite direction to log(P_China/P_nonChina). Our beta should\n")
cat("    therefore be NEGATIVE (sigma > 1) for substitutes.\n\n")

cat("Files:\n")
cat("  data/processed/phase6_revisit_importer_hs6_panel.RData (Components 2/3)\n")
cat("  data/processed/phase6_revisit_c1_results.RData         (this script)\n")
cat("  output/figures/phase6_revisit_c1_first_and_second_stage.pdf\n")
cat("  output/tables/phase6_revisit_c1_summary.csv\n")
cat("================================================================\n")
sink()
cat("Saved:", file.path(OUTPUT_TAB, "phase6_revisit_c1_summary.txt"), "\n")

cat("\nDone.\n")
