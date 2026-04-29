###############################################################################
# phase6_eyeball_e3_reduced_form.R
#
# PURPOSE:
#   Eyeball E3 from CHINA_SHOCK_DIAGNOSTICS_PLAN.md.
#
#   E1 showed the China shifter has cross-product variation. E2 showed the
#   shifter transmits to Belgian unit values (F = 195, slope per pp ≈ -1.3%).
#   E3 asks: do Belgian buyers actually reroute sourcing in response?
#
#   Three reduced-form scatters at the input-NACE-4d × year level:
#
#   Version A (absolute B2B level):
#     Δlog(domestic B2B sales from Belgian sellers in NACE 4d n) ~ ΔChinaShare_n
#     Expected slope: NEGATIVE. Caveat: doesn't normalize by total Belgian
#     buyer expenditure on NACE 4d n -- common GDP growth shows up in
#     intercept, but a within-NACE-4d substitution visible only as a share
#     would be missed.
#
#   Version A2 (share-of-expenditure, the cleaner version):
#     Δ(Belgian-seller share of Belgian-buyer expenditure on NACE 4d n)
#     where Belgian-seller share = b2b_sales / (b2b_sales + v_total_be_imports).
#     Expected slope: NEGATIVE. This is the substantive substitution outcome:
#     does the Belgian-source share of input expenditure fall when China
#     shocks the category?
#
#   Version B (mechanical sanity check via direct imports):
#     Δ(China share of Belgian imports of NACE 4d n) ~ ΔChinaShare_n
#     Expected slope: POSITIVE. China shock → Belgian imports tilt toward
#     China.
#
#   Identification: same EU-26-excl-Belgium shifter from E1, aggregated from
#   HS6 to NACE 4d via cn8_to_nace4d.csv (weighted by 2002 EU-26 trade value).
#
# INPUT:
#   data/processed/phase6_china_shifter_2002_2012.RData (HS6 × ΔChinaShare)
#   data/processed/phase6_belgian_unit_values.RData      (uv_panel: HS6 × yr × source)
#   data/concordances/cn8_to_nace4d.csv                  (CN8 → NACE 4d mapping)
#   $DATA_DIR/processed/b2b_selected_sample.RData
#   $DATA_DIR/processed/annual_accounts_selected_sample_key_variables.RData
#
# OUTPUT:
#   data/processed/phase6_e3_reduced_form_data.RData
#   output/figures/phase6_eyeball_e3_reduced_form.pdf
#   output/tables/phase6_eyeball_e3_summary.csv
#   output/tables/phase6_eyeball_e3_summary.txt
#
# CAVEATS:
#   - B2B is downsampled on local-1; for paper-quality numbers re-run on RMD.
#     Eyeball-level direction and rough magnitude should hold on the sample.
#   - HS6 -> NACE 4d concordance: use cn8_to_nace4d.csv year=2002, drop CN8s
#     with NA NACE assignment. nace4d field used (the canonical single
#     assignment, not nace4d_all).
#   - 3 contaminated VAT hashes (NACE 20/24, post-2020) per MEMORY.md: not
#     binding here since we use 2002 and 2012, both pre-2021. No drop.
#   - 2002 is the first B2B year — left-censoring not load-bearing for an
#     aggregated NACE-4d outcome but flagged.
#   - Currency mismatch: B2B corr_sales in EUR, BACI v in thousand USD. For
#     Version A2 (share computation that mixes both) we convert BACI USD to
#     EUR using ECB annual-average rates: 2002 EUR/USD = 0.9456,
#     2012 EUR/USD = 1.2848. These are public ECB reference rates; precise
#     daily rates would shift A2 marginally but not change the slope sign or
#     order-of-magnitude.
###############################################################################

rm(list = ls())

library(data.table)
library(ggplot2)
library(scales)
library(patchwork)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load shifter (HS6) and Belgian-from-China import values (HS6 × year) ----
load(file.path(OUT_DATA, "phase6_china_shifter_2002_2012.RData"))
# china_shifter_hs6: k, china_share_2002, china_share_2012, delta_china_share,
#   value_total_2002, value_china_2002, value_total_2012, value_china_2012,
#   importance_weight, headline_keep, ...
load(file.path(OUT_DATA, "phase6_belgian_unit_values.RData"))
# uv_panel: k, year, uv_china, v_china_be, uv_nonchina, v_nonchina_be

cat("HS6 shifter rows:", nrow(china_shifter_hs6), "\n")
cat("UV panel rows   :", nrow(uv_panel), "\n")

# ---- Build HS6 -> NACE 4d map from cn8_to_nace4d.csv (year = 2002) ----
cn_map <- fread(file.path(REPO_DIR, "data", "concordances", "cn8_to_nace4d.csv"))
cn_map <- cn_map[year == 2002 & !is.na(nace4d)]
cn_map[, cn8_padded := formatC(cn8, width = 8, flag = "0")]
cn_map[, k := substr(cn8_padded, 1, 6)]   # HS6 from CN8

# Each HS6 may have multiple CN8 children with potentially different NACE 4d
# assignments. Take the modal NACE 4d per HS6 (ties broken arbitrarily).
hs6_nace_modal <- cn_map[, .N, by = .(k, nace4d)][
  order(k, -N), .SD[1], by = k][, .(k, nace4d)]

cat(sprintf("HS6 codes mapped to a NACE 4d: %d (out of %d in shifter)\n",
            nrow(hs6_nace_modal), nrow(china_shifter_hs6)))

# ---- Aggregate shifter to NACE 4d ----
shifter_h <- china_shifter_hs6[hs6_nace_modal, on = "k", nomatch = 0]

# Trade-weighted mean of ΔChinaShare across HS6 children of each NACE 4d
shifter_nace <- shifter_h[
  , .(delta_china_share = sum(delta_china_share * value_total_2002, na.rm = TRUE) /
                          sum(value_total_2002, na.rm = TRUE),
      value_total_2002 = sum(value_total_2002, na.rm = TRUE),
      n_hs6            = .N),
  by = nace4d
]

cat(sprintf("NACE 4d cells in shifter: %d (mean HS6 per NACE 4d: %.1f)\n",
            nrow(shifter_nace), mean(shifter_nace$n_hs6)))

# ---- Version A: B2B sales by seller NACE 4d × year ----
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))

# Convert to data.table
b2b <- as.data.table(df_b2b_selected_sample)
aa  <- as.data.table(df_annual_accounts_selected_sample_key_variables)
rm(df_b2b_selected_sample, df_annual_accounts_selected_sample_key_variables)

# Seller NACE 4d in years 2002 and 2012
# nace5d is stored as character (5-digit string). Truncate to 4 chars for
# NACE 4d. Result kept as integer for clean joins to the concordance.
seller_nace <- aa[year %in% c(2002, 2012) & !is.na(nace5d) & nchar(nace5d) >= 4,
                  .(vat, year, nace4d_seller = as.integer(substr(nace5d, 1, 4)))]
seller_nace <- unique(seller_nace, by = c("vat", "year"))

cat(sprintf("Seller-year NACE rows: %d\n", nrow(seller_nace)))

# Filter B2B to 2002 and 2012, attach seller NACE 4d
b2b <- b2b[year %in% c(2002, 2012)]
b2b <- merge(b2b, seller_nace,
             by.x = c("vat_i_ano", "year"), by.y = c("vat", "year"))

cat(sprintf("B2B rows with seller NACE attached, 2002 and 2012: %d\n", nrow(b2b)))

# Aggregate sales by seller NACE 4d × year
b2b_agg <- b2b[, .(b2b_sales = sum(corr_sales_ij, na.rm = TRUE)),
                by = .(nace4d_seller, year)]

b2b_a <- dcast(b2b_agg, nace4d_seller ~ year, value.var = "b2b_sales")
setnames(b2b_a, c("nace4d_seller", "2002", "2012"),
         c("nace4d", "b2b_sales_2002", "b2b_sales_2012"))
b2b_a[, dlog_b2b_sales := log(b2b_sales_2012) - log(b2b_sales_2002)]

cat(sprintf("NACE 4d cells with B2B sales in both 2002 and 2012: %d\n",
            sum(!is.na(b2b_a$dlog_b2b_sales))))

# ---- Version B: Δ(China's share of Belgian imports), by NACE 4d × year ----
# Outcome is a share-on-share regression rather than log-on-log:
#   china_share_BE_n,t = v_china_be_n,t / (v_china_be_n,t + v_nonchina_be_n,t)
#   delta_BE_n         = china_share_BE_n,2012 - china_share_BE_n,2002
# This avoids a log-of-base mechanical artefact: Δlog(absolute Chinese
# imports) is dominated by the 2002 baseline level (categories with
# small base in 2002 have huge Δlog regardless of ΔChinaShare). A share
# outcome regressed on a share shifter is the apples-to-apples reduced form.
imports_h <- uv_panel[year %in% c(2002, 2012),
                       .(k, year, v_china_be, v_nonchina_be)]
imports_h <- imports_h[hs6_nace_modal, on = "k", nomatch = 0]

imports_agg <- imports_h[, .(v_china_be    = sum(v_china_be,    na.rm = TRUE),
                              v_nonchina_be = sum(v_nonchina_be, na.rm = TRUE)),
                          by = .(nace4d, year)]
imports_agg[, v_total_be := v_china_be + v_nonchina_be]
imports_agg <- imports_agg[v_total_be > 0]
imports_agg[, china_share_be := v_china_be / v_total_be]

imports_b <- dcast(imports_agg, nace4d ~ year,
                   value.var = c("china_share_be", "v_total_be"))
setnames(imports_b,
         c("china_share_be_2002", "china_share_be_2012",
           "v_total_be_2002",     "v_total_be_2012"),
         c("china_share_be_2002", "china_share_be_2012",
           "v_total_be_2002",     "v_total_be_2012"))
imports_b[, delta_china_share_be := china_share_be_2012 - china_share_be_2002]

cat(sprintf("NACE 4d cells with Belgian imports in both years: %d\n",
            sum(!is.na(imports_b$delta_china_share_be))))

# ---- Version A2: Belgian-seller share of Belgian-buyer expenditure ----
# Need to put B2B (EUR) and BACI imports (thousand USD) on the same currency
# scale. Convert BACI USD -> EUR using ECB annual-average rates.
usd_per_eur <- c("2002" = 0.9456, "2012" = 1.2848)

imports_eur <- imports_agg[, .(nace4d, year,
                                v_total_be_eur = v_total_be * 1000 /
                                                  usd_per_eur[as.character(year)])]
imports_eur_wide <- dcast(imports_eur, nace4d ~ year,
                          value.var = "v_total_be_eur")
setnames(imports_eur_wide, c("2002", "2012"),
         c("v_total_be_eur_2002", "v_total_be_eur_2012"))

share_data <- merge(b2b_a[, .(nace4d, b2b_sales_2002, b2b_sales_2012)],
                    imports_eur_wide, by = "nace4d", all = FALSE)
share_data[, total_exp_2002 := b2b_sales_2002 + v_total_be_eur_2002]
share_data[, total_exp_2012 := b2b_sales_2012 + v_total_be_eur_2012]
share_data <- share_data[total_exp_2002 > 0 & total_exp_2012 > 0]
share_data[, belgian_seller_share_2002 := b2b_sales_2002 / total_exp_2002]
share_data[, belgian_seller_share_2012 := b2b_sales_2012 / total_exp_2012]
share_data[, delta_belgian_seller_share :=
              belgian_seller_share_2012 - belgian_seller_share_2002]

cat(sprintf("NACE 4d cells with Belgian-seller share computable: %d\n",
            sum(!is.na(share_data$delta_belgian_seller_share))))

# ---- Merge and assemble regression dataset ----
e3 <- merge(shifter_nace, b2b_a[, .(nace4d, dlog_b2b_sales)],
            by = "nace4d", all.x = TRUE)
e3 <- merge(e3, share_data[, .(nace4d, delta_belgian_seller_share,
                                belgian_seller_share_2002,
                                belgian_seller_share_2012)],
            by = "nace4d", all.x = TRUE)
e3 <- merge(e3, imports_b[, .(nace4d, delta_china_share_be,
                                  china_share_be_2002, china_share_be_2012)],
            by = "nace4d", all.x = TRUE)

# Importance weights: 2002 EU-26 trade value, normalized to sum to 1
e3[, importance_weight := value_total_2002 / sum(value_total_2002)]

# Trim 1% tails of the outcome within each version (P&R convention)
trim_outcome <- function(dt, col) {
  x <- dt[is.finite(get(col)), get(col)]
  if (length(x) > 50) {
    lo <- quantile(x, 0.01, na.rm = TRUE)
    hi <- quantile(x, 0.99, na.rm = TRUE)
    dt[!is.finite(get(col)), (col) := NA]
    dt[!is.na(get(col)) & (get(col) < lo | get(col) > hi), (col) := NA]
  }
  dt
}
e3 <- trim_outcome(e3, "dlog_b2b_sales")
e3 <- trim_outcome(e3, "delta_belgian_seller_share")
e3 <- trim_outcome(e3, "delta_china_share_be")

# ---- WLS regressions ----
run_reg <- function(dt, ycol, label) {
  d <- dt[!is.na(get(ycol)) & !is.na(delta_china_share) &
          !is.na(importance_weight) & importance_weight > 0]
  if (nrow(d) < 30) {
    return(data.table(spec = label, n = nrow(d),
                       beta = NA_real_, se = NA_real_, t_stat = NA_real_,
                       p_value = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
                       f_stat = NA_real_, r2 = NA_real_))
  }
  fit <- lm(as.formula(sprintf("%s ~ delta_china_share", ycol)),
            data = d, weights = d$importance_weight)
  s   <- summary(fit)
  ci  <- confint(fit, "delta_china_share", level = 0.95)
  data.table(
    spec     = label,
    n        = nrow(d),
    beta     = unname(coef(fit)["delta_china_share"]),
    se       = unname(s$coefficients["delta_china_share", "Std. Error"]),
    t_stat   = unname(s$coefficients["delta_china_share", "t value"]),
    p_value  = unname(s$coefficients["delta_china_share", "Pr(>|t|)"]),
    ci_lo    = ci[1],
    ci_hi    = ci[2],
    f_stat   = unname(s$fstatistic["value"]),
    r2       = unname(s$r.squared)
  )
}

res_a  <- run_reg(e3, "dlog_b2b_sales",
                  "Version A:  domestic B2B sales (level)")
res_a2 <- run_reg(e3, "delta_belgian_seller_share",
                  "Version A2: Belgian-seller share of expenditure")
res_b  <- run_reg(e3, "delta_china_share_be",
                  "Version B:  China share of Belgian imports")
results <- rbindlist(list(res_a, res_a2, res_b))
print(results, digits = 4)

fwrite(results, file.path(OUTPUT_TAB, "phase6_eyeball_e3_summary.csv"))
cat("Saved:", file.path(OUTPUT_TAB, "phase6_eyeball_e3_summary.csv"), "\n")

# ---- Side-by-side scatter ----
make_panel <- function(dt, ycol, title_text, slope, fstat, n) {
  d <- dt[!is.na(get(ycol)) & is.finite(get(ycol)) & !is.na(delta_china_share)]
  ggplot(d, aes(x = delta_china_share, y = get(ycol),
                size = importance_weight)) +
    geom_point(alpha = 0.5, colour = "steelblue") +
    geom_smooth(aes(weight = importance_weight),
                method = "lm", se = TRUE, colour = "tomato",
                linewidth = 0.8, show.legend = FALSE) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey40") +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey40") +
    scale_x_continuous(labels = percent_format(accuracy = 1)) +
    scale_size_continuous(guide = "none", range = c(0.6, 5)) +
    labs(
      title    = title_text,
      subtitle = sprintf("Slope = %.3f, F = %.1f, N = %d NACE 4d", slope, fstat, n),
      x        = "Delta-ChinaShare 2002->2012 (NACE-4d-aggregated)",
      y        = "Delta log(outcome) 2002->2012"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title.position = "plot")
}

p_a  <- make_panel(e3, "dlog_b2b_sales",
                   "A: Delta-log B2B sales (level)",
                   res_a$beta, res_a$f_stat, res_a$n)
p_a2 <- make_panel(e3, "delta_belgian_seller_share",
                   "A2: Delta Belgian-seller share of expenditure",
                   res_a2$beta, res_a2$f_stat, res_a2$n)
p_b  <- make_panel(e3, "delta_china_share_be",
                   "B: Delta China share of Belgian imports",
                   res_b$beta, res_b$f_stat, res_b$n)

p_combined <- (p_a | p_a2 | p_b) +
  plot_annotation(
    title    = "Eyeball E3 -- Reduced-form: do Belgian buyers reroute? (2002 -> 2012)",
    subtitle = "One observation per input-NACE-4d. Trade-weighted (2002 EU-26 import value). 1% tails of outcome trimmed.",
    caption  = "Source: BACI HS02 V202601 + B2B + Annual Accounts. Eyeball E3, CHINA_SHOCK_DIAGNOSTICS_PLAN.md."
  ) & theme(plot.title.position = "plot")

ggsave(file.path(OUTPUT_FIG, "phase6_eyeball_e3_reduced_form.pdf"),
       p_combined, width = 16, height = 6)
cat("Saved:", file.path(OUTPUT_FIG, "phase6_eyeball_e3_reduced_form.pdf"), "\n")

# ---- Save intermediate data ----
save(e3, shifter_nace, b2b_a, imports_b, imports_agg, share_data,
     hs6_nace_modal, results,
     file = file.path(OUT_DATA, "phase6_e3_reduced_form_data.RData"))
cat("Saved:", file.path(OUT_DATA, "phase6_e3_reduced_form_data.RData"), "\n")

# ---- Readable summary ----
sink(file.path(OUTPUT_TAB, "phase6_eyeball_e3_summary.txt"))

cat("================================================================\n")
cat("Eyeball E3 -- Reduced-form: do Belgian buyers reroute?\n")
cat("Generated by analysis/phase6_eyeball_e3_reduced_form.R\n")
cat("================================================================\n\n")

cat("Setup:\n")
cat("  Unit: input-NACE-4d. ChinaShare aggregated from HS6 via\n")
cat("        cn8_to_nace4d.csv (year=2002), trade-weighted by 2002 EU-26 value.\n")
cat("  Horizon: 2002 -> 2012 (10-yr LR window, P&R-comparable).\n")
cat("  WLS, weights = NACE-4d's 2002 EU-26 import value.\n")
cat("  1% tails of each outcome trimmed.\n\n")

cat("Version A -- absolute B2B sales by Belgian sellers in NACE 4d n:\n")
cat("  Outcome: Delta log(sum_{seller in NACE 4d n} corr_sales_ij)\n")
cat("  Expected slope: NEGATIVE (buyers reroute away from Belgian sellers).\n")
cat("  Caveat: doesn't normalize by total Belgian buyer expenditure.\n\n")

cat("Version A2 -- Belgian-seller share of buyer expenditure on NACE 4d n:\n")
cat("  Outcome: Delta(belgian_seller_share) where\n")
cat("    belgian_seller_share_n,t = b2b_sales_n,t /\n")
cat("                               (b2b_sales_n,t + v_total_be_imports_n,t)\n")
cat("  Expected slope: NEGATIVE. Cleaner than A: directly measures whether the\n")
cat("    Belgian-source share of input expenditure falls when the category is\n")
cat("    China-shocked.\n")
cat("  Currency: BACI USD converted to EUR via ECB annual mean rates\n")
cat("    (2002: 0.9456; 2012: 1.2848 USD per EUR).\n\n")

cat("Version B -- China's share of Belgian imports in NACE 4d n:\n")
cat("  Outcome: Delta(china_share_BE_n) where\n")
cat("    china_share_BE_n,t = v_China->BE,n,t / v_total->BE,n,t\n")
cat("  Expected slope: POSITIVE (buyers tilt imports toward China).\n\n")

cat("Sample:\n")
cat(sprintf("  HS6 in shifter: %d\n", nrow(china_shifter_hs6)))
cat(sprintf("  HS6 mapped to a NACE 4d: %d\n", nrow(hs6_nace_modal)))
cat(sprintf("  NACE 4d cells in shifter: %d\n", nrow(shifter_nace)))
cat(sprintf("  NACE 4d cells in regression A: %d\n", res_a$n))
cat(sprintf("  NACE 4d cells in regression B: %d\n", res_b$n))
cat("\n")

cat("Results:\n")
print(results, digits = 4)
cat("\n")

cat("================================================================\n")
cat("Verdict (joint reading; A2 is the load-bearing domestic-substitution test)\n")
cat(sprintf("  Version A  (level)        : beta = %.4f, F = %.1f, p = %.4g, N = %d\n",
            res_a$beta,  res_a$f_stat,  res_a$p_value,  res_a$n))
cat(sprintf("  Version A2 (share)        : beta = %.4f, F = %.1f, p = %.4g, N = %d\n",
            res_a2$beta, res_a2$f_stat, res_a2$p_value, res_a2$n))
cat(sprintf("  Version B  (import share) : beta = %.4f, F = %.1f, p = %.4g, N = %d\n",
            res_b$beta,  res_b$f_stat,  res_b$p_value,  res_b$n))
cat("\n")

a2_neg_sig <- !is.na(res_a2$beta) && res_a2$beta < 0 && res_a2$p_value < 0.05
a2_null    <- !is.na(res_a2$p_value) && res_a2$p_value >= 0.10
b_pos_sig  <- !is.na(res_b$beta)  && res_b$beta  > 0 && res_b$p_value  < 0.05

if (a2_neg_sig && b_pos_sig) {
  cat("  PASS (substitution): A2 significantly negative, B significantly positive.\n")
  cat("        Belgian buyers reroute away from Belgian sellers (Belgian-source\n")
  cat("        share of expenditure falls) and toward direct Chinese imports.\n")
  cat("        Project moves to E4 and full D1/D2.\n")
} else if (a2_null && b_pos_sig) {
  cat("  PARTIAL (LR-null on domestic side): import margin alive (B positive)\n")
  cat("           but Belgian-source expenditure share does not fall (A2 null).\n")
  cat("           This is the LR analog of the carbon-leakage null -- itself\n")
  cat("           a finding. Project pivots to writing the LR-null paper.\n")
} else if (!a2_neg_sig && !b_pos_sig) {
  cat("  FAIL: neither A2 nor B shows the expected substitution sign. Either\n")
  cat("        the China shock doesn't drive substitution at the NACE-4d\n")
  cat("        level, or the aggregation washed out the signal.\n")
  cat("        Investigate before D1.\n")
} else {
  cat("  MIXED: signs partial / weak. Inspect figures and check whether the\n")
  cat("         pattern is concentrated in specific NACE 2d sectors before\n")
  cat("         deciding next step.\n")
}
cat("================================================================\n")

sink()
cat("Saved:", file.path(OUTPUT_TAB, "phase6_eyeball_e3_summary.txt"), "\n")

cat("\nDone.\n")
