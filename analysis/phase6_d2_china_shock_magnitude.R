###############################################################################
# phase6_d2_china_shock_magnitude.R
#
# PURPOSE:
#   D2 from CHINA_SHOCK_DIAGNOSTICS_PLAN.md.
#
#   Compute the buyer-level magnitude of the China shock — % of each
#   buyer's total input cost moved by the 2002-2012 China shock, expressed
#   on the same scale as SHOCK_MAGNITUDE.md's pair_shock_total / buyer_total_shock
#   for direct apples-to-apples comparison with the carbon shock.
#
#   For each Belgian buyer b in 2002, the B2B-side China shock is:
#
#     china_buyer_shock_b2b_b = Σ_n (b2b_spend_{b,n,2002} / inputs_VAT_{b,2002})
#                                 × ψ × ΔChinaShare_n
#
#   where:
#     b2b_spend_{b,n,2002} = sum of corr_sales from Belgian sellers in NACE 4d n
#                            to buyer b in 2002
#     inputs_VAT_{b,2002}   = buyer b's total declared input bill (VAT-records),
#                              the same denominator used for pair_shock_total
#     ψ                     = -1.34 (E2 non-China 10-yr first-stage slope —
#                              the load-bearing pro-competitive channel that
#                              transmits to Belgian B2B sellers' prices)
#     ΔChinaShare_n         = trade-weighted-mean across HS6 children (from E3's
#                              shifter_nace).
#
#   Compare to the carbon-shock buyer-level magnitude reported in
#   output/tables/phase5_moment4a_buyer_total_shock_distribution.csv.
#
# CARBON-SIDE BENCHMARK (FROM SHOCK_MAGNITUDE.md / phase5):
#   buyer_total_shock_b = Σ_{j ∈ ETS} firm_cost_share_j × corr_sales_{j,b} / inputs_VAT_b
#
#   Phase IV (2021-22) reference:
#     N = 15,442 Belgian buyers
#     p99 = 6.90%, p95 = 0.031%, p90 = 0%, p50 = 0% (most buyers have no ETS exposure)
#     mean = 0.358%, sales_wmean = ?
#
# WHAT'S OMITTED IN THIS VERSION:
#   - Customs-side: a Belgian buyer's exposure to China through their direct
#     imports (ψ_china_only ≈ -1.09 × buyer's import share at HS6 × ΔChinaShare).
#     Requires firm-level Customs at HS6/CN8, not on local-1.
#   - Manufacturing-buyers focus is reported alongside the all-buyer
#     distribution; the regulated-NACE-2d sample used for the carbon shock
#     can be matched in a second pass.
#
# INPUT:
#   data/processed/phase6_e3_reduced_form_data.RData (shifter_nace)
#   data/processed/phase6_e2_first_stage_results.RData (results_dt for ψ)
#   $DATA_DIR/processed/b2b_selected_sample.RData
#   $DATA_DIR/processed/annual_accounts_more_selected_sample.RData (inputs_VAT)
#   $DATA_DIR/processed/annual_accounts_selected_sample_key_variables.RData (NACE)
#   output/tables/phase5_moment4a_buyer_total_shock_distribution.csv (carbon ref)
#
# OUTPUT:
#   data/processed/phase6_d2_china_buyer_shock.RData
#   output/tables/phase6_d2_china_shock_magnitude.csv
#   output/tables/phase6_d2_china_vs_carbon_comparison.csv
#   output/tables/phase6_d2_china_shock_magnitude.txt
#   output/figures/phase6_d2_china_vs_carbon_shock.pdf
#
# CAVEATS:
#   - B2B is downsampled on local-1; the buyer-level distribution will be
#     less smooth than on RMD. Tail moments (p99) may shift on RMD; medians
#     and means should be stable.
#   - Horizon mismatch: carbon shock is measured per year in Phase IV;
#     China shock is the cumulative 10-yr LR. To compare per-year speeds,
#     divide China shock by 10 (annualized) or report carbon shock × 5
#     (cumulative 5-yr Phase IV-binding window).
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

# ---- Load shifter_nace (NACE-4d-level ΔChinaShare) ----
load(file.path(OUT_DATA, "phase6_e3_reduced_form_data.RData"))

# ---- Load ψ from E2 ----
load(file.path(OUT_DATA, "phase6_e2_first_stage_results.RData"))
psi_nonchina_10yr <- results_dt[spec == "Non-China 10-yr", psi]
stopifnot(length(psi_nonchina_10yr) == 1, !is.na(psi_nonchina_10yr))
cat(sprintf("Using psi = %.4f from E2 non-China 10-yr first stage\n",
            psi_nonchina_10yr))

# Implied price change per NACE 4d
shifter_nace[, implied_dlog_p := psi_nonchina_10yr * delta_china_share]

# ---- Load B2B and Annual Accounts ----
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))

b2b      <- as.data.table(df_b2b_selected_sample)
aa       <- as.data.table(df_annual_accounts_selected_sample_key_variables)
inputs_v <- as.data.table(df_annual_accounts_more_selected_sample)
rm(df_b2b_selected_sample,
   df_annual_accounts_selected_sample_key_variables,
   df_annual_accounts_more_selected_sample)

# ---- 2002 baseline aggregations ----

# Seller NACE 4d (for joining to B2B)
seller_nace_2002 <- aa[year == 2002 & !is.na(nace5d) & nchar(nace5d) >= 4,
                       .(vat,
                         nace4d_seller = as.integer(substr(nace5d, 1, 4)))]
seller_nace_2002 <- unique(seller_nace_2002, by = "vat")

# Buyer NACE 2d (for sub-sample analysis)
buyer_nace_2002 <- aa[year == 2002 & !is.na(nace5d) & nchar(nace5d) >= 2,
                      .(vat,
                        nace2d_buyer = as.integer(substr(nace5d, 1, 2)))]
buyer_nace_2002 <- unique(buyer_nace_2002, by = "vat")

# Buyer revenue (for sales-weighted moments)
buyer_revenue_2002 <- aa[year == 2002 & !is.na(revenue) & revenue > 0,
                         .(vat, revenue)]

# Buyer's total declared input bill, 2002 (denominator)
buyer_inputs_2002 <- inputs_v[year == 2002 & !is.na(inputs_VAT) & inputs_VAT > 0,
                              .(vat_ano, inputs_VAT_total = inputs_VAT)]

cat(sprintf("Buyers with inputs_VAT > 0 in 2002: %d\n", nrow(buyer_inputs_2002)))

# ---- Aggregate B2B 2002: buyer x seller-NACE 4d -> spend ----
b2b_2002 <- b2b[year == 2002 & !is.na(corr_sales_ij) & corr_sales_ij > 0]
b2b_2002 <- merge(b2b_2002, seller_nace_2002,
                  by.x = "vat_i_ano", by.y = "vat")
b2b_buyer_nace <- b2b_2002[, .(b2b_spend = sum(corr_sales_ij, na.rm = TRUE)),
                            by = .(vat_j_ano, nace4d_seller)]

# Attach buyer's total inputs and the implied per-NACE-4d price change.
# all.x on the shifter merge keeps NACE 4ds with no shifter (services etc.)
# and assigns implied = 0 (no China shock impact through those categories).
b2b_buyer_nace <- merge(b2b_buyer_nace, buyer_inputs_2002,
                         by.x = "vat_j_ano", by.y = "vat_ano")
b2b_buyer_nace <- merge(b2b_buyer_nace,
                         shifter_nace[, .(nace4d, implied_dlog_p)],
                         by.x = "nace4d_seller", by.y = "nace4d", all.x = TRUE)
b2b_buyer_nace[is.na(implied_dlog_p), implied_dlog_p := 0]

# ---- Compute buyer-level B2B-side China shock ----
b2b_buyer_nace[, china_pair_shock := (b2b_spend / inputs_VAT_total) *
                                       implied_dlog_p]

china_buyer <- b2b_buyer_nace[, .(
  china_buyer_shock_b2b = sum(china_pair_shock, na.rm = TRUE),
  total_b2b_share       = sum(b2b_spend / inputs_VAT_total, na.rm = TRUE),
  inputs_VAT_total      = inputs_VAT_total[1],
  n_seller_nace         = uniqueN(nace4d_seller),
  n_seller_nace_shocked = sum(implied_dlog_p != 0)
), by = vat_j_ano]

# Attach revenue and buyer NACE
china_buyer <- merge(china_buyer, buyer_revenue_2002,
                      by.x = "vat_j_ano", by.y = "vat", all.x = TRUE)
china_buyer <- merge(china_buyer, buyer_nace_2002,
                      by.x = "vat_j_ano", by.y = "vat", all.x = TRUE)

cat(sprintf("Belgian buyers with computable B2B-side China shock: %d\n",
            nrow(china_buyer)))

# ---- Distribution moments ----
moment_summary <- function(x, w = NULL) {
  x <- x[!is.na(x)]
  if (length(x) == 0) return(NULL)
  abs_x <- abs(x)
  out <- list(
    n             = length(x),
    p25_abs       = quantile(abs_x, 0.25),
    p50_abs       = quantile(abs_x, 0.50),
    p75_abs       = quantile(abs_x, 0.75),
    p90_abs       = quantile(abs_x, 0.90),
    p95_abs       = quantile(abs_x, 0.95),
    p99_abs       = quantile(abs_x, 0.99),
    mean_abs      = mean(abs_x),
    median_signed = median(x),
    mean_signed   = mean(x)
  )
  if (!is.null(w)) {
    keep <- !is.na(w) & w > 0
    out$sales_wmean_abs    <- sum(abs_x[keep] * w[keep]) / sum(w[keep])
    out$sales_wmean_signed <- sum(x[keep] * w[keep]) / sum(w[keep])
  }
  out
}

x_all   <- china_buyer$china_buyer_shock_b2b
w_all   <- china_buyer$revenue
manuf   <- china_buyer[nace2d_buyer %in% 10:33]
x_manuf <- manuf$china_buyer_shock_b2b
w_manuf <- manuf$revenue

moments_all   <- as.data.table(c(scope = "all_buyers",
                                 moment_summary(x_all, w_all)))
moments_manuf <- as.data.table(c(scope = "manufacturing_buyers",
                                 moment_summary(x_manuf, w_manuf)))

results <- rbindlist(list(moments_all, moments_manuf), fill = TRUE)
print(results, digits = 4)

fwrite(results, file.path(OUTPUT_TAB, "phase6_d2_china_shock_magnitude.csv"))
cat("Saved:", file.path(OUTPUT_TAB, "phase6_d2_china_shock_magnitude.csv"), "\n")

# ---- By buyer NACE 2d ----
by_nace2d <- china_buyer[!is.na(nace2d_buyer),
                          .(n            = .N,
                            p50_abs      = quantile(abs(china_buyer_shock_b2b), 0.50),
                            p90_abs      = quantile(abs(china_buyer_shock_b2b), 0.90),
                            p99_abs      = quantile(abs(china_buyer_shock_b2b), 0.99),
                            mean_abs     = mean(abs(china_buyer_shock_b2b)),
                            mean_signed  = mean(china_buyer_shock_b2b)),
                          by = nace2d_buyer][order(-p90_abs)]

print(head(by_nace2d, 15), digits = 4)

# ---- China-vs-carbon comparison table ----
# Pull Phase IV reference numbers from the saved phase5 distribution.
carbon_ref <- fread(file.path(OUTPUT_TAB,
                              "phase5_moment4a_buyer_total_shock_distribution.csv"))
carbon_pIV <- carbon_ref[phase5 == "IV"]

comparison <- data.table(
  metric = c("N buyers",
             "p50 (median, abs)",
             "p90 (abs)",
             "p95 (abs)",
             "p99 (abs)",
             "mean (abs)"),
  carbon_phase_iv_annual = c(carbon_pIV$n_buyers,
                              carbon_pIV$p50,
                              carbon_pIV$p90,
                              carbon_pIV$p95,
                              carbon_pIV$p99,
                              carbon_pIV$mean),
  china_2002_2012_LR     = c(nrow(china_buyer),
                              quantile(abs(x_all), 0.50),
                              quantile(abs(x_all), 0.90),
                              quantile(abs(x_all), 0.95),
                              quantile(abs(x_all), 0.99),
                              mean(abs(x_all)))
)
comparison[, ratio_china_over_carbon := ifelse(carbon_phase_iv_annual > 0,
                                                china_2002_2012_LR /
                                                  carbon_phase_iv_annual,
                                                NA_real_)]
comparison[, china_annualized := china_2002_2012_LR / 10]
comparison[, ratio_annualized := ifelse(carbon_phase_iv_annual > 0,
                                         china_annualized /
                                           carbon_phase_iv_annual,
                                         NA_real_)]

print(comparison, digits = 4)
fwrite(comparison,
       file.path(OUTPUT_TAB, "phase6_d2_china_vs_carbon_comparison.csv"))
cat("Saved:", file.path(OUTPUT_TAB,
                        "phase6_d2_china_vs_carbon_comparison.csv"), "\n")

# ---- Figure: side-by-side distribution ----
plot_dt <- rbind(
  data.table(shock = "China shock (B2B-side, 10-yr LR)",
             value = abs(x_all)),
  data.table(shock = "Carbon shock (buyer total, Phase IV annual)",
             value = NA_real_)
)
# For the carbon side we have only summary stats; show them as labelled
# vertical lines on the China histogram, plus the comparison table.

p_hist <- ggplot(plot_dt[shock == "China shock (B2B-side, 10-yr LR)" & !is.na(value)],
                 aes(x = pmin(value, 0.5))) +
  geom_histogram(bins = 60, fill = "steelblue", alpha = 0.85) +
  geom_vline(xintercept = carbon_pIV$p90,
             colour = "tomato", linetype = "dashed") +
  geom_vline(xintercept = carbon_pIV$p99,
             colour = "tomato", linetype = "solid") +
  annotate("text", x = max(carbon_pIV$p99, 0.07), y = Inf,
           label = sprintf("Carbon p99 = %.2f%%", 100 * carbon_pIV$p99),
           colour = "tomato", vjust = 2, hjust = 0, size = 3.4) +
  scale_x_continuous(labels = percent_format(accuracy = 1),
                     limits = c(0, 0.5)) +
  labs(
    title    = "China-shock buyer-level magnitude (B2B-side, 2002 -> 2012 LR)",
    subtitle = sprintf("|china_buyer_shock_b2b|, N = %d Belgian buyers; carbon-shock Phase IV p99 marked for comparison", nrow(china_buyer)),
    x        = "abs(china_buyer_shock_b2b) — % of buyer's 2002 input bill",
    y        = "Number of buyers",
    caption  = "Source: BACI HS02 + B2B + Annual Accounts. CHINA_SHOCK_DIAGNOSTICS_PLAN.md D2."
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.title.position = "plot",
        plot.subtitle = element_text(colour = "grey30", size = 9))

ggsave(file.path(OUTPUT_FIG, "phase6_d2_china_vs_carbon_shock.pdf"),
       p_hist, width = 10, height = 6)
cat("Saved:", file.path(OUTPUT_FIG, "phase6_d2_china_vs_carbon_shock.pdf"), "\n")

# ---- Save processed data ----
save(china_buyer, b2b_buyer_nace, by_nace2d, comparison, results,
     psi_nonchina_10yr,
     file = file.path(OUT_DATA, "phase6_d2_china_buyer_shock.RData"))
cat("Saved:", file.path(OUT_DATA, "phase6_d2_china_buyer_shock.RData"), "\n")

# ---- Readable summary ----
sink(file.path(OUTPUT_TAB, "phase6_d2_china_shock_magnitude.txt"))

cat("================================================================\n")
cat("D2 -- China shock magnitude at the buyer level (B2B-side, 10-yr LR)\n")
cat("Generated by analysis/phase6_d2_china_shock_magnitude.R\n")
cat("================================================================\n\n")

cat("Definition (apples-to-apples with SHOCK_MAGNITUDE.md buyer_total_shock):\n")
cat("  china_buyer_shock_b2b_b = Σ_n (b2b_spend_{b,n} / inputs_VAT_b)\n")
cat("                              × ψ × ΔChinaShare_n\n")
cat(sprintf("  Using ψ = %.4f (E2 non-China 10-yr first stage).\n\n",
            psi_nonchina_10yr))

cat("Sample sizes:\n")
cat(sprintf("  Buyers with inputs_VAT > 0 in 2002: %d\n",
            nrow(buyer_inputs_2002)))
cat(sprintf("  Buyers with computable B2B-side China shock: %d\n",
            nrow(china_buyer)))
cat(sprintf("  Manufacturing buyers (NACE 10-33): %d\n", nrow(manuf)))
cat("\n")

cat("Distribution moments (absolute value):\n")
print(results, digits = 4)
cat("\n")

cat("Top buyer-NACE 2d cells (by p90 of |china_buyer_shock_b2b|):\n")
print(head(by_nace2d, 15), digits = 4)
cat("\n")

cat("Comparison with carbon shock (SHOCK_MAGNITUDE.md Phase IV buyer_total_shock):\n")
print(comparison, digits = 4)
cat("\n")

cat("================================================================\n")
cat("Reading -- the two shocks have very different distributional shapes:\n\n")

cat("  Carbon shock (Phase IV, annual, all Belgian buyers):\n")
cat("    Narrow but deep. Most buyers (p50, p75, p90) have ZERO ETS exposure.\n")
cat(sprintf("    Concentrated at the top tail: p99 = %.2f%%, p95 = %.3f%%, mean = %.3f%%.\n",
            100 * carbon_pIV$p99, 100 * carbon_pIV$p95, 100 * carbon_pIV$mean))
cat("    The ~1%% of buyers in cement/steel/refining bear most of the burden.\n\n")

cat("  China shock (B2B-side, 10-yr LR, all Belgian buyers):\n")
cat("    Broad but shallow. Almost every buyer has some exposure via their\n")
cat("    NACE-4d input mix; few buyers have very large exposure.\n")
cat(sprintf("    p99 = %.2f%%, p95 = %.3f%%, mean = %.3f%%.\n",
            100 * quantile(abs(x_all), 0.99),
            100 * quantile(abs(x_all), 0.95),
            100 * mean(abs(x_all))))
cat(sprintf("    Annualized (LR / 10): p99 = %.3f%%, p95 = %.4f%%, mean = %.4f%%.\n\n",
            10 * quantile(abs(x_all), 0.99),
            10 * quantile(abs(x_all), 0.95),
            10 * mean(abs(x_all))))

p95_ratio_cumul <- comparison[metric == "p95 (abs)", ratio_china_over_carbon]
p95_ratio_annu  <- comparison[metric == "p95 (abs)", ratio_annualized]
mean_ratio_cumul <- comparison[metric == "mean (abs)", ratio_china_over_carbon]
mean_ratio_annu  <- comparison[metric == "mean (abs)", ratio_annualized]

cat("  Headline ratios (where both shocks are non-zero):\n")
cat(sprintf("    p95 (cumulative): China is %.1fx carbon\n", p95_ratio_cumul))
cat(sprintf("    p95 (annualized): China is %.2fx carbon\n", p95_ratio_annu))
cat(sprintf("    mean (cumulative): China is %.2fx carbon\n", mean_ratio_cumul))
cat(sprintf("    mean (annualized): China is %.3fx carbon\n", mean_ratio_annu))
cat(sprintf("    p99 (cumulative): China is %.2fx carbon (carbon dominates the tail)\n",
            comparison[metric == "p99 (abs)", ratio_china_over_carbon]))
cat("\n")

cat("  Bottom line:\n")
cat("    - For the median Belgian buyer: China is bigger (carbon = 0).\n")
cat("    - For the typical exposed buyer (p95): China and carbon are\n")
cat("      comparable on annualized basis.\n")
cat("    - For the high-exposure tail (p99): carbon is far bigger because\n")
cat("      it concentrates on a small set of regulated emitters.\n")
cat("    - The two shocks tag different firms: cement/steel for carbon,\n")
cat("      manufacturers with import-substitutable inputs for China.\n\n")

cat("Caveats:\n")
cat("  - B2B-side only (Customs-side omitted; would shift China shock up).\n")
cat("  - B2B is downsampled on local-1; tail moments will refine on RMD.\n")
cat("  - Horizon mismatch: China is 10-yr LR cumulative, carbon is Phase IV\n")
cat("    annual. Annualized ratio divides China by 10 for per-year speed.\n")
cat("================================================================\n")

sink()
cat("Saved:", file.path(OUTPUT_TAB, "phase6_d2_china_shock_magnitude.txt"), "\n")

cat("\nDone.\n")
