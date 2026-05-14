###############################################################################
# phase5_shock_benchmark_ets_nace_share.R
#
# PURPOSE:
#   ETS-NACE4d level-share variance benchmark for the carbon shock.
#
#   Builds a noise floor for the carbon shock IN THE SAME UNITS as the shock
#   itself (percentage points of total input cost), restricted to the input
#   margin that is actually exposed to ETS regulation.
#
# CONTRAST WITH phase5_shock_benchmarks.R:
#   - Unit of variance: (buyer, NACE4d, year), not (buyer, year).
#   - Denominator: total declared input cost inputs_VAT, not revenue.
#   - Statistic: sd_t( Δ share_{b,n,t} ) -- LEVEL first-differences of the
#     share, not Δlog. Reasons:
#       (i)  handles zero-spending years natively (no log of zero);
#       (ii) same units as the carbon shock (pp of total input cost), so
#            direct shock/sigma comparison;
#       (iii) the mechanical share-size dependence cancels: small-share
#            cells have small sigma AND contribute small shock, so the
#            shock-to-noise ratio is invariant to share size.
#   - Subset: ETS-treated NACE4d = NACE4d with >=1 EUTL-matched firm ever
#            (canonical project definition); buyers must have bought from
#            >=1 such NACE4d at some point in the window.
#
# DEMAND-STRIPPING:
#   Δ share = Δ( spending_{b,n,t} / total_input_cost_{b,t} ). A proportional
#   firm-level expansion scales numerator and denominator together and
#   leaves Δshare unchanged in expectation. Same logic as the existing
#   sigma_share but in level rather than log space.
#
# WINDOWS:
#   - 2005-2012 (strict pre-Phase-3 -- EUA price ~ 0; clean noise floor)
#   - 2005-2019 (pre-Phase-4 -- matches existing sigma_share convention)
#
# INPUTS:
#   ${PROC_DATA}/annual_accounts_more_selected_sample.RData
#   ${PROC_DATA}/b2b_cdgm_panel.RData
#   ${PROC_DATA}/firm_year_belgian_euets.RData
#
# OUTPUTS:
#   output/tables/phase5_moment5_ets_nace_share_distribution.csv
#   output/tables/phase5_moment5_ets_nace_share_by_nace4d.csv
#   output/tables/phase5_moment5_ets_nace_share_by_share_quintile.csv
#   output/tables/phase5_moment5_ets_nace_share_summary.txt
###############################################################################

rm(list = ls())

library(dplyr)
library(stringr)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load ----
cat("Loading annual accounts (inputs_VAT, nace5d)...\n")
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- df_annual_accounts_more_selected_sample
rm(df_annual_accounts_more_selected_sample)

cat("Loading B2B panel (buyer-seller-year flows)...\n")
# Filename varies by machine: RMD has b2b_cdgm_panel.RData; some local
# copies have b2b_cmdj_panel.RData. Both expose the same `panel` object.
panel_candidates <- c("b2b_cdgm_panel.RData", "b2b_cmdj_panel.RData")
panel_path <- panel_candidates[file.exists(file.path(PROC_DATA, panel_candidates))][1]
if (is.na(panel_path))
  stop("No B2B panel file found in PROC_DATA. Tried: ",
       paste(panel_candidates, collapse = ", "))
cat("  Using:", panel_path, "\n")
load(file.path(PROC_DATA, panel_path))

cat("Loading EUTL firm-year (Belgian EU-ETS installations)...\n")
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))

# ===========================================================================
# ETS-treated NACE4d set: NACE4d with >=1 EUTL-matched firm (ever).
# ===========================================================================
ets_treated_nace4d <- firm_year_belgian_euets %>%
  filter(!is.na(nace5d)) %>%
  mutate(nace4d = str_sub(as.character(nace5d), 1, 4)) %>%
  distinct(nace4d) %>%
  pull(nace4d)

cat(sprintf("ETS-treated NACE4d sectors (>=1 EUTL firm ever): %d\n",
            length(ets_treated_nace4d)))

# ===========================================================================
# Buyer denominator: total declared input cost (inputs_VAT)
# ===========================================================================
buyer_inputs <- aa %>%
  rename(vat = vat_ano) %>%
  select(vat, year, inputs_VAT) %>%
  filter(!is.na(inputs_VAT), inputs_VAT > 0)

cat(sprintf("Buyer-year obs with positive inputs_VAT: %d\n", nrow(buyer_inputs)))

# ===========================================================================
# Buyer x NACE4d x year spending panel (aggregate B2B by seller_nace4d)
# Restrict to ETS-treated NACE4d.
# ===========================================================================
buyer_nace_spend_ets <- panel %>%
  filter(corr_sales > 0, !is.na(seller_nace4d),
         seller_nace4d %in% ets_treated_nace4d) %>%
  group_by(buyer, seller_nace4d, year) %>%
  summarise(nace_spend = sum(corr_sales, na.rm = TRUE),
            buyer_nace2d = first(buyer_nace2d),
            .groups = "drop") %>%
  rename(vat = buyer, nace4d = seller_nace4d)

cat(sprintf("(buyer x ETS-NACE4d x year) cells with positive spend: %d\n",
            nrow(buyer_nace_spend_ets)))
cat(sprintf("  Distinct buyers exposed to >=1 ETS NACE4d: %d\n",
            n_distinct(buyer_nace_spend_ets$vat)))
cat(sprintf("  Distinct (buyer, ETS-NACE4d) pairs: %d\n",
            nrow(distinct(buyer_nace_spend_ets, vat, nace4d))))

# ===========================================================================
# Balanced (buyer, NACE4d, year) panel:
#   - Every year where buyer has inputs_VAT > 0.
#   - For each (buyer, NACE4d) pair seen at least once, fill missing years
#     with nace_spend = 0 (share = 0). Captures the "stopped buying from
#     that sector" margin -- crucial for variance, since zero years are
#     part of normal variation.
# ===========================================================================
buyer_nace_pairs <- buyer_nace_spend_ets %>%
  distinct(vat, nace4d, buyer_nace2d)

buyer_nace_balanced <- buyer_inputs %>%
  inner_join(buyer_nace_pairs, by = "vat",
             relationship = "many-to-many") %>%
  left_join(buyer_nace_spend_ets %>% select(vat, nace4d, year, nace_spend),
            by = c("vat", "nace4d", "year")) %>%
  mutate(nace_spend = if_else(is.na(nace_spend), 0, nace_spend),
         share = nace_spend / inputs_VAT)

cat(sprintf("Balanced (buyer, ETS-NACE4d, year) panel rows: %d\n",
            nrow(buyer_nace_balanced)))

# ===========================================================================
# First-differences of share, consec years
# ===========================================================================
buyer_nace_diffs <- buyer_nace_balanced %>%
  arrange(vat, nace4d, year) %>%
  group_by(vat, nace4d) %>%
  mutate(dshare = share - lag(share),
         dyear  = year - lag(year)) %>%
  ungroup() %>%
  filter(!is.na(dshare), dyear == 1)

cat(sprintf("(buyer x NACE4d) consec-year diffs: %d\n",
            nrow(buyer_nace_diffs)))

# ===========================================================================
# sigma_{b,n} per (buyer, NACE4d) cell, two windows.
# Also track mean spending and mean share over the window for weighting
# and quintile binning.
# ===========================================================================
compute_sigma <- function(diffs_df, panel_df, year_min, year_max, min_n) {
  shares <- panel_df %>%
    filter(year >= year_min, year <= year_max) %>%
    group_by(vat, nace4d, buyer_nace2d) %>%
    summarise(mean_share = mean(share, na.rm = TRUE),
              mean_spend = mean(nace_spend, na.rm = TRUE),
              .groups = "drop")

  diffs_df %>%
    filter(year >= year_min, year <= year_max) %>%
    group_by(vat, nace4d, buyer_nace2d) %>%
    summarise(n_diffs = n(),
              sigma = sd(dshare, na.rm = TRUE),
              .groups = "drop") %>%
    filter(n_diffs >= min_n, !is.na(sigma)) %>%
    left_join(shares, by = c("vat", "nace4d", "buyer_nace2d"))
}

sigma_strict <- compute_sigma(buyer_nace_diffs, buyer_nace_balanced,
                              2005, 2012, min_n = 3)
sigma_pre4   <- compute_sigma(buyer_nace_diffs, buyer_nace_balanced,
                              2005, 2019, min_n = 5)

cat(sprintf("(buyer x NACE4d) cells with sigma (2005-2012, n_diffs>=3): %d\n",
            nrow(sigma_strict)))
cat(sprintf("(buyer x NACE4d) cells with sigma (2005-2019, n_diffs>=5): %d\n",
            nrow(sigma_pre4)))

# ===========================================================================
# Weighted quantile helper
# ===========================================================================
wtd_quantile <- function(x, w, probs) {
  ok <- !is.na(x) & !is.na(w) & w > 0
  x <- x[ok]; w <- w[ok]
  if (length(x) == 0) return(rep(NA_real_, length(probs)))
  o <- order(x); x <- x[o]; w <- w[o]
  cum <- cumsum(w) / sum(w)
  approx(cum, x, xout = probs, ties = "ordered", rule = 2)$y
}

qtab <- function(df, label, weight_col = NULL) {
  probs <- c(.10, .25, .50, .75, .90, .95)
  if (is.null(weight_col)) {
    q <- quantile(df$sigma, probs, na.rm = TRUE)
    data.frame(window = label, weighting = "unweighted",
               n_cells = nrow(df),
               p10 = q[1], p25 = q[2], p50 = q[3], p75 = q[4],
               p90 = q[5], p95 = q[6],
               mean = mean(df$sigma, na.rm = TRUE))
  } else {
    w <- df[[weight_col]]
    q <- wtd_quantile(df$sigma, w, probs)
    data.frame(window = label,
               weighting = paste0("weighted_by_", weight_col),
               n_cells = nrow(df),
               p10 = q[1], p25 = q[2], p50 = q[3], p75 = q[4],
               p90 = q[5], p95 = q[6],
               mean = weighted.mean(df$sigma, w, na.rm = TRUE))
  }
}

dist_table <- bind_rows(
  qtab(sigma_strict, "2005-2012 (pre-Phase-3)"),
  qtab(sigma_strict, "2005-2012 (pre-Phase-3)", weight_col = "mean_spend"),
  qtab(sigma_pre4,   "2005-2019 (pre-Phase-4)"),
  qtab(sigma_pre4,   "2005-2019 (pre-Phase-4)", weight_col = "mean_spend")
)

cat("\n=== Distribution of sigma_{b,n} across (buyer, ETS-NACE4d) cells ===\n")
cat("Units: pp of total input cost; statistic: sd_t(Δshare).\n")
print(as.data.frame(dist_table), digits = 4)

write.csv(dist_table,
          file.path(OUTPUT_TAB,
                    "phase5_moment5_ets_nace_share_distribution.csv"),
          row.names = FALSE)

# ---- By NACE4d ----
by_nace_table <- sigma_strict %>%
  group_by(nace4d) %>%
  summarise(n_cells = n(),
            p25 = quantile(sigma, .25, na.rm = TRUE),
            p50 = quantile(sigma, .50, na.rm = TRUE),
            p75 = quantile(sigma, .75, na.rm = TRUE),
            p90 = quantile(sigma, .90, na.rm = TRUE),
            mean_sigma = mean(sigma, na.rm = TRUE),
            mean_share = mean(mean_share, na.rm = TRUE),
            .groups = "drop") %>%
  arrange(desc(p50))

cat("\n=== sigma by ETS-NACE4d (2005-2012) ===\n")
print(as.data.frame(by_nace_table), digits = 4)

write.csv(by_nace_table,
          file.path(OUTPUT_TAB,
                    "phase5_moment5_ets_nace_share_by_nace4d.csv"),
          row.names = FALSE)

# ---- By mean-share quintile (transparency for the share-size dependence) ----
by_quintile <- sigma_strict %>%
  filter(mean_share > 0) %>%
  mutate(share_q = ntile(mean_share, 5)) %>%
  group_by(share_q) %>%
  summarise(n_cells = n(),
            share_lo = min(mean_share),
            share_hi = max(mean_share),
            mean_share = mean(mean_share),
            sigma_p25 = quantile(sigma, .25, na.rm = TRUE),
            sigma_p50 = quantile(sigma, .50, na.rm = TRUE),
            sigma_p75 = quantile(sigma, .75, na.rm = TRUE),
            sigma_mean = mean(sigma, na.rm = TRUE),
            .groups = "drop")

cat("\n=== sigma by mean-share quintile (2005-2012) ===\n")
cat("sigma scales with share; shock/sigma is roughly invariant.\n")
print(as.data.frame(by_quintile), digits = 4)

write.csv(by_quintile,
          file.path(OUTPUT_TAB,
                    "phase5_moment5_ets_nace_share_by_share_quintile.csv"),
          row.names = FALSE)

# ===========================================================================
# Combined readable summary
# ===========================================================================
sink(file.path(OUTPUT_TAB, "phase5_moment5_ets_nace_share_summary.txt"))

cat("================================================================\n")
cat("ETS-NACE4d level-share variance benchmark\n")
cat("Generated by analysis/phase5_shock_benchmark_ets_nace_share.R\n")
cat("================================================================\n\n")

cat("Statistic: sigma_{b,n} = sd_t( Δ share_{b,n,t} )\n")
cat("  share_{b,n,t} = spending_{b,n,t} / inputs_VAT_{b,t}\n")
cat("  Δ = first-difference (level), consecutive years\n")
cat("  Units: percentage points of buyer's total input cost\n\n")

cat("Sample:\n")
cat(sprintf("  ETS-treated NACE4d sectors: %d (>=1 EUTL firm ever)\n",
            length(ets_treated_nace4d)))
cat(sprintf("  Buyers exposed to >=1 ETS NACE4d: %d\n",
            n_distinct(buyer_nace_spend_ets$vat)))
cat(sprintf("  (buyer, ETS-NACE4d) cells with sigma, 2005-2012: %d\n",
            nrow(sigma_strict)))
cat(sprintf("  (buyer, ETS-NACE4d) cells with sigma, 2005-2019: %d\n\n",
            nrow(sigma_pre4)))

cat("----------------------------------------------------------------\n")
cat("Cross-cell distribution of sigma_{b,n}\n")
cat("  Unweighted (each cell counted once) and weighted by mean\n")
cat("  spending in the cell (big-spend cells dominate the summary,\n")
cat("  matching how the shock itself is weighted).\n")
cat("----------------------------------------------------------------\n")
print(as.data.frame(dist_table), digits = 4)
cat("\n")

cat("----------------------------------------------------------------\n")
cat("sigma by ETS-NACE4d sector (2005-2012)\n")
cat("----------------------------------------------------------------\n")
print(as.data.frame(by_nace_table), digits = 4)
cat("\n")

cat("----------------------------------------------------------------\n")
cat("sigma by mean-share quintile (2005-2012)\n")
cat("  sigma scales with the level of share, as expected. The carbon\n")
cat("  shock also scales with share, so shock/sigma is approximately\n")
cat("  invariant across quintiles -- the relevant comparison object.\n")
cat("----------------------------------------------------------------\n")
print(as.data.frame(by_quintile), digits = 4)
cat("\n")

cat("================================================================\n")
cat("Reading: compare median(sigma) -- spending-weighted -- against the\n")
cat("median carbon shock magnitude (also in pp of total input cost).\n")
cat("Ratio shock/sigma answers 'how many sd's of normal variation is\n")
cat("the carbon shock?'.\n")
cat("================================================================\n")

sink()

cat("\nSaved summary to",
    file.path(OUTPUT_TAB, "phase5_moment5_ets_nace_share_summary.txt"), "\n")
cat("Done.\n")
