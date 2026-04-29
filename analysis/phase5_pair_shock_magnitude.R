###############################################################################
# phase5_pair_shock_magnitude.R
#
# PURPOSE:
#   Plan A, Moments 2 and 4 (per SHOCK_AND_SUBSTITUTION_PLAN.md).
#
#   Moment 2 -- ETS-seller-level cost-share for the sellers in the B2B
#               leakage test sample. Same `firm_cost_share_{j,t}` as Moment 1
#               (same-year, descriptive), restricted to ETS sellers that appear
#               in the binary B2B panel built in
#               analysis/phase3_build_b2b_cmdj_panel.R.
#
#   Moment 4 -- Pair-level shock magnitude. Joins firm_cost_share to the
#               (seller × buyer × year) B2B panel and computes:
#
#                 pair_shock_{j,b,t} = firm_cost_share_{j,t}
#                                      x (seller j's share of buyer b's spend
#                                         on input-NACE 4d in year t)
#
#               This is the buyer's share-weighted exposure to the seller's
#               cost shock. It is the right magnitude to ask "would buyer b
#               have a meaningful incentive to switch away from seller j?"
#
# INPUT:
#   data/processed/phase3_firm_exposure.RData       (firm_exposure)
#   ${PROC_DATA}/b2b_cmdj_panel.RData                (panel; balanced 2005-22)
#
# OUTPUT:
#   output/tables/phase5_moment2_b2b_seller_distribution.csv
#   output/tables/phase5_moment2_b2b_seller_by_nace2d_phase4.csv
#   output/tables/phase5_moment4_pair_shock_distribution.csv
#   output/tables/phase5_moment4_pair_shock_by_buyer_nace2d_phase4.csv
#   output/tables/phase5_pair_shock_summary.txt
#   output/figures/phase5_moment4_pair_shock_distribution.pdf
#
# CAVEATS:
#   - Drops the 3 contaminated VAT hashes (NACE 20, 24) from 2021+ per
#     MEMORY.md project_nace24_eutl_break_post2020.md.
#   - Pair-shock is computed on ACTIVE pair-years only (corr_sales > 0).
#     The denominator (buyer's total spend on input-NACE 4d in year t) is
#     summed over ALL sellers in the balanced panel; balanced zeros
#     contribute 0 so that's fine.
#   - "Buyer's input-NACE 4d spend" uses the seller's NACE 4d as the unit;
#     this matches how "core-input pair" is defined in the B2B sample.
###############################################################################

rm(list = ls())

library(dplyr)
library(tidyr)
library(ggplot2)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load ----
cat("Loading firm-year exposure panel and B2B panel...\n")
load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))   # firm_exposure
load(file.path(PROC_DATA, "b2b_cmdj_panel.RData"))        # panel

# ---- Drop contaminated VATs from 2021+ (firm_exposure side) ----
contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
firm_exposure <- firm_exposure %>%
  filter(!(vat %in% contaminated_vats & year >= 2021))

# Also drop these contaminated rows from the B2B panel side (when they appear
# as sellers, post-2020 their seller-level cost share is artefactually high).
n_panel_drop <- panel %>%
  filter(seller %in% contaminated_vats, year >= 2021) %>%
  nrow()
panel <- panel %>%
  filter(!(seller %in% contaminated_vats & year >= 2021))
cat(sprintf("Dropped %d B2B rows for contaminated sellers, year >= 2021.\n",
            n_panel_drop))

# ---- Fine-grained phase column (for both sides) ----
add_phase5 <- function(df) {
  df %>% mutate(phase5 = factor(case_when(
      year %in% 2005:2007 ~ "I",
      year %in% 2008:2012 ~ "II",
      year %in% 2013:2017 ~ "III pre-MSR",
      year %in% 2018:2020 ~ "III post-MSR",
      year >= 2021        ~ "IV",
      TRUE                ~ NA_character_
    ),
    levels = c("I", "II", "III pre-MSR", "III post-MSR", "IV"))
  )
}
firm_exposure <- add_phase5(firm_exposure)
panel         <- add_phase5(panel)

# ===========================================================================
# Moment 2 -- cost-share distribution at the ETS sellers in the B2B sample
# ===========================================================================
#
# Sample: ETS sellers (seller_is_ets == 1) appearing in the binary B2B
# panel. For each (seller, year) of those sellers we look up the same-year
# `cost_share_total` from firm_exposure.
# ===========================================================================
cat("\n=== Moment 2: cost-share at ETS sellers in the B2B sample ===\n")

ets_sellers_in_b2b <- panel %>%
  filter(seller_is_ets == 1) %>%
  distinct(seller) %>%
  pull(seller)

cat(sprintf("ETS sellers appearing in B2B panel: %d\n",
            length(ets_sellers_in_b2b)))

# Pull their firm_exposure rows (note: firm_exposure uses `vat` to identify
# the firm, panel uses `seller`).
m2_panel <- firm_exposure %>%
  filter(vat %in% ets_sellers_in_b2b, !is.na(cost_share_total))

cat(sprintf("Firm-year obs for these sellers (cost share defined): %d\n",
            nrow(m2_panel)))

moment2 <- m2_panel %>%
  group_by(phase5) %>%
  summarise(
    n_firm_years     = n(),
    n_distinct_firms = n_distinct(vat),
    pct_pos_shortage = 100 * mean(shortage > 0),
    p25  = quantile(cost_share_total, 0.25, na.rm = TRUE),
    p50  = quantile(cost_share_total, 0.50, na.rm = TRUE),
    p75  = quantile(cost_share_total, 0.75, na.rm = TRUE),
    p90  = quantile(cost_share_total, 0.90, na.rm = TRUE),
    p99  = quantile(cost_share_total, 0.99, na.rm = TRUE),
    mean = mean(cost_share_total, na.rm = TRUE),
    sales_wmean = sum(cost_share_total * revenue, na.rm = TRUE) /
                  sum(revenue * !is.na(cost_share_total), na.rm = TRUE),
    .groups = "drop"
  )

print(as.data.frame(moment2), digits = 4)

write.csv(moment2,
          file.path(OUTPUT_TAB, "phase5_moment2_b2b_seller_distribution.csv"),
          row.names = FALSE)
cat("Saved:", file.path(OUTPUT_TAB, "phase5_moment2_b2b_seller_distribution.csv"), "\n")

# Phase IV split by NACE 2d (sales-weighted = important here)
moment2_nace <- m2_panel %>%
  filter(phase5 == "IV") %>%
  group_by(nace2d) %>%
  summarise(
    n_firm_years     = n(),
    n_distinct_firms = n_distinct(vat),
    p50  = quantile(cost_share_total, 0.50, na.rm = TRUE),
    p90  = quantile(cost_share_total, 0.90, na.rm = TRUE),
    p99  = quantile(cost_share_total, 0.99, na.rm = TRUE),
    mean = mean(cost_share_total, na.rm = TRUE),
    sales_wmean = sum(cost_share_total * revenue, na.rm = TRUE) /
                  sum(revenue * !is.na(cost_share_total), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(p90))

print(as.data.frame(moment2_nace), digits = 4)

write.csv(moment2_nace,
          file.path(OUTPUT_TAB, "phase5_moment2_b2b_seller_by_nace2d_phase4.csv"),
          row.names = FALSE)
cat("Saved:", file.path(OUTPUT_TAB, "phase5_moment2_b2b_seller_by_nace2d_phase4.csv"), "\n")

# ===========================================================================
# Moment 4 -- pair-level shock
# ===========================================================================
#
#   pair_shock_{j,b,t} = firm_cost_share_{j,t}
#                       x (corr_sales_{j,b,t} / sum_{j' in same nace4d as j} corr_sales_{j',b,t})
#
# Steps:
#   1. Compute buyer-input-spend = sum of corr_sales over (buyer, seller_nace4d, year)
#      across the balanced panel. (Balanced zeros add 0 -- safe.)
#   2. Pair share = corr_sales / buyer-input-spend.
#   3. Join firm_cost_share_{j,t} from firm_exposure (cost_share_total) on
#      (vat = seller, year).
#   4. pair_shock = cost_share_total * pair_share.
#   5. Restrict to ACTIVE pair-years (corr_sales > 0) for the distribution
#      table; we report only over genuine economic relationships.
# ===========================================================================
cat("\n=== Moment 4: pair-level shock distribution ===\n")

# Step 1: buyer × seller_nace4d × year spend total
buyer_spend <- panel %>%
  group_by(buyer, seller_nace4d, year) %>%
  summarise(buyer_input_spend = sum(corr_sales, na.rm = TRUE),
            .groups = "drop")

# Step 2: pair share
panel_share <- panel %>%
  left_join(buyer_spend, by = c("buyer", "seller_nace4d", "year")) %>%
  mutate(pair_share = ifelse(buyer_input_spend > 0,
                             corr_sales / buyer_input_spend, NA_real_))

# Step 3a: load buyer's total declared input bill (inputs_VAT) per buyer-year
# This is the denominator for pair_shock_total (option (c)) and the input
# to buyer_total_shock (option (a) = sum of pair_shock_total across j).
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
buyer_inputs <- df_annual_accounts_more_selected_sample %>%
  rename(buyer = vat_ano) %>%
  filter(!is.na(inputs_VAT), inputs_VAT > 0) %>%
  select(buyer, year, inputs_VAT_total = inputs_VAT)
rm(df_annual_accounts_more_selected_sample)

# Step 3b: join firm_cost_share_{j,t} and buyer's total inputs
panel_shock <- panel_share %>%
  left_join(firm_exposure %>%
              select(vat, year, cost_share_total),
            by = c("seller" = "vat", "year")) %>%
  left_join(buyer_inputs, by = c("buyer", "year")) %>%
  mutate(
    # ETS cost-share with NA -> 0 for pair-shock products
    fcs = ifelse(seller_is_ets == 1 & !is.na(cost_share_total),
                 cost_share_total, 0),
    # (b) pair_shock at NACE-4d denominator -- existing
    pair_shock = ifelse(seller_is_ets == 1, fcs * pair_share, 0),
    # (c) pair_shock at total-inputs denominator -- new
    #     = firm_cost_share x corr_sales / inputs_VAT
    #     NA when inputs_VAT is missing (allows clean filtering)
    pair_shock_total = ifelse(seller_is_ets == 1 & !is.na(inputs_VAT_total) &
                              inputs_VAT_total > 0,
                              fcs * corr_sales / inputs_VAT_total,
                              NA_real_)
  )

# Diagnostic: how many treated cells, how many active
cat(sprintf("Total panel rows: %d\n", nrow(panel_shock)))
cat(sprintf("Active rows (corr_sales > 0): %d\n",
            sum(panel_shock$corr_sales > 0)))
cat(sprintf("Active treated rows (active + ETS seller): %d\n",
            sum(panel_shock$corr_sales > 0 & panel_shock$seller_is_ets == 1)))

# Step 5: distribution over active pairs by phase
m4_active <- panel_shock %>% filter(corr_sales > 0)

moment4 <- m4_active %>%
  group_by(phase5) %>%
  summarise(
    n_pair_years    = n(),
    n_treated_pairs = sum(seller_is_ets == 1),
    n_zero_shock    = sum(pair_shock == 0),
    p50  = quantile(pair_shock, 0.50, na.rm = TRUE),
    p75  = quantile(pair_shock, 0.75, na.rm = TRUE),
    p90  = quantile(pair_shock, 0.90, na.rm = TRUE),
    p95  = quantile(pair_shock, 0.95, na.rm = TRUE),
    p99  = quantile(pair_shock, 0.99, na.rm = TRUE),
    mean = mean(pair_shock, na.rm = TRUE),
    sales_wmean = sum(pair_shock * corr_sales, na.rm = TRUE) /
                  sum(corr_sales, na.rm = TRUE),
    .groups = "drop"
  )

cat("\nDistribution over ALL active pair-years (most are zero shock):\n")
print(as.data.frame(moment4), digits = 4)

# Distribution restricted to TREATED (ETS seller) pair-years -- this is
# where the upper-tail action is and where the leakage incentive could exist
moment4_treated <- m4_active %>%
  filter(seller_is_ets == 1) %>%
  group_by(phase5) %>%
  summarise(
    n_treated_pairs = n(),
    p50  = quantile(pair_shock, 0.50, na.rm = TRUE),
    p75  = quantile(pair_shock, 0.75, na.rm = TRUE),
    p90  = quantile(pair_shock, 0.90, na.rm = TRUE),
    p95  = quantile(pair_shock, 0.95, na.rm = TRUE),
    p99  = quantile(pair_shock, 0.99, na.rm = TRUE),
    mean = mean(pair_shock, na.rm = TRUE),
    sales_wmean = sum(pair_shock * corr_sales, na.rm = TRUE) /
                  sum(corr_sales, na.rm = TRUE),
    .groups = "drop"
  )

cat("\nDistribution over TREATED active pair-years (ETS seller only):\n")
print(as.data.frame(moment4_treated), digits = 4)

# Combine for the headline CSV
moment4_full <- bind_rows(
  moment4 %>% mutate(sample = "all_active"),
  moment4_treated %>% mutate(sample = "ets_seller_active",
                              n_pair_years = n_treated_pairs,
                              n_zero_shock = NA_integer_) %>%
    select(phase5, sample, n_pair_years, n_zero_shock, p50, p75, p90, p95, p99, mean, sales_wmean)
) %>%
  select(phase5, sample, everything())

write.csv(moment4_full,
          file.path(OUTPUT_TAB, "phase5_moment4_pair_shock_distribution.csv"),
          row.names = FALSE)
cat("Saved:", file.path(OUTPUT_TAB, "phase5_moment4_pair_shock_distribution.csv"), "\n")

# ===========================================================================
# Moment 4(c) -- pair_shock_total: pair-shock at TOTAL-inputs denominator
# ===========================================================================
#
#   pair_shock_total_{j,b,t} = firm_cost_share_{j,t} × corr_sales_{j,b,t} / inputs_VAT_{b,t}
#
# Apples-to-apples comparator with sigma_share = sd(Δlog(inputs/revenue)).
# Tells us "how much does this seller's carbon shock raise the buyer's
# TOTAL input bill?", which can be compared directly to the noise floor
# of buyer's total input cost variation.
# ===========================================================================
cat("\n=== Moment 4(c): pair_shock_total (denominator = total inputs_VAT) ===\n")

m4c_treated <- panel_shock %>%
  filter(corr_sales > 0, seller_is_ets == 1, !is.na(pair_shock_total))

cat(sprintf("Treated active pair-years with inputs_VAT defined: %d / %d\n",
            nrow(m4c_treated),
            sum(panel_shock$corr_sales > 0 & panel_shock$seller_is_ets == 1)))

moment4c_treated <- m4c_treated %>%
  group_by(phase5) %>%
  summarise(
    n_treated_pairs = n(),
    p50  = quantile(pair_shock_total, 0.50, na.rm = TRUE),
    p75  = quantile(pair_shock_total, 0.75, na.rm = TRUE),
    p90  = quantile(pair_shock_total, 0.90, na.rm = TRUE),
    p95  = quantile(pair_shock_total, 0.95, na.rm = TRUE),
    p99  = quantile(pair_shock_total, 0.99, na.rm = TRUE),
    mean = mean(pair_shock_total, na.rm = TRUE),
    sales_wmean = sum(pair_shock_total * corr_sales, na.rm = TRUE) /
                  sum(corr_sales, na.rm = TRUE),
    .groups = "drop"
  )

cat("\nDistribution of pair_shock_total over TREATED active pair-years:\n")
print(as.data.frame(moment4c_treated), digits = 4)

write.csv(moment4c_treated,
          file.path(OUTPUT_TAB, "phase5_moment4c_pair_shock_total_distribution.csv"),
          row.names = FALSE)

# Phase IV by buyer NACE 2d
moment4c_buyer_nace <- m4c_treated %>%
  filter(phase5 == "IV") %>%
  group_by(buyer_nace2d) %>%
  summarise(
    n_treated_pairs = n(),
    p50  = quantile(pair_shock_total, 0.50, na.rm = TRUE),
    p90  = quantile(pair_shock_total, 0.90, na.rm = TRUE),
    p95  = quantile(pair_shock_total, 0.95, na.rm = TRUE),
    p99  = quantile(pair_shock_total, 0.99, na.rm = TRUE),
    mean = mean(pair_shock_total, na.rm = TRUE),
    sales_wmean = sum(pair_shock_total * corr_sales, na.rm = TRUE) /
                  sum(corr_sales, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(p90))

cat("\npair_shock_total (TREATED, Phase IV) by BUYER NACE 2d:\n")
print(as.data.frame(moment4c_buyer_nace), digits = 4)

write.csv(moment4c_buyer_nace,
          file.path(OUTPUT_TAB, "phase5_moment4c_pair_shock_total_by_buyer_nace2d_phase4.csv"),
          row.names = FALSE)

# ===========================================================================
# Moment 4(a) -- buyer_total_shock: per-buyer aggregate (sum over j)
# ===========================================================================
#
#   buyer_total_shock_{b,t} = sum_j (pair_shock_total_{j,b,t})
#                           = sum_j firm_cost_share_j × corr_sales_{j,b,t} / inputs_VAT_{b,t}
#
# Buyer's total ETS exposure across ALL their ETS sellers, as fraction of
# total input bill. Aggregates across the buyer's substitution decisions --
# less informative for substitution per se, useful for macro cost-burden.
# ===========================================================================
cat("\n=== Moment 4(a): buyer_total_shock (sum across buyer's ETS sellers) ===\n")

# Sum pair_shock_total across all the buyer's pairs (treated + non-treated;
# non-treated contribute 0 because firm_cost_share=0 -> pair_shock_total=0).
# Restrict to active pairs (corr_sales > 0) only.
buyer_year_total <- panel_shock %>%
  filter(corr_sales > 0, !is.na(pair_shock_total) | seller_is_ets == 0) %>%
  group_by(buyer, year, phase5) %>%
  summarise(buyer_total_shock = sum(pair_shock_total, na.rm = TRUE),
            n_pairs = n(),
            n_treated_pairs = sum(seller_is_ets == 1),
            .groups = "drop") %>%
  filter(!is.na(buyer_total_shock))

cat(sprintf("Buyer-year cells with buyer_total_shock defined: %d\n",
            nrow(buyer_year_total)))

moment4a <- buyer_year_total %>%
  group_by(phase5) %>%
  summarise(
    n_buyers       = n(),
    p50  = quantile(buyer_total_shock, 0.50, na.rm = TRUE),
    p75  = quantile(buyer_total_shock, 0.75, na.rm = TRUE),
    p90  = quantile(buyer_total_shock, 0.90, na.rm = TRUE),
    p95  = quantile(buyer_total_shock, 0.95, na.rm = TRUE),
    p99  = quantile(buyer_total_shock, 0.99, na.rm = TRUE),
    mean = mean(buyer_total_shock, na.rm = TRUE),
    .groups = "drop"
  )

cat("\nDistribution of buyer_total_shock by phase:\n")
print(as.data.frame(moment4a), digits = 4)

write.csv(moment4a,
          file.path(OUTPUT_TAB, "phase5_moment4a_buyer_total_shock_distribution.csv"),
          row.names = FALSE)

# Phase IV by buyer NACE 2d (treated sellers only) -- which downstream
# sectors actually face meaningful exposure?
moment4_buyer_nace <- m4_active %>%
  filter(seller_is_ets == 1, phase5 == "IV") %>%
  group_by(buyer_nace2d) %>%
  summarise(
    n_treated_pairs = n(),
    p50  = quantile(pair_shock, 0.50, na.rm = TRUE),
    p90  = quantile(pair_shock, 0.90, na.rm = TRUE),
    p95  = quantile(pair_shock, 0.95, na.rm = TRUE),
    p99  = quantile(pair_shock, 0.99, na.rm = TRUE),
    mean = mean(pair_shock, na.rm = TRUE),
    sales_wmean = sum(pair_shock * corr_sales, na.rm = TRUE) /
                  sum(corr_sales, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(p90))

cat("\nPair-shock distribution (TREATED, Phase IV) by BUYER NACE 2d:\n")
print(as.data.frame(moment4_buyer_nace), digits = 4)

write.csv(moment4_buyer_nace,
          file.path(OUTPUT_TAB, "phase5_moment4_pair_shock_by_buyer_nace2d_phase4.csv"),
          row.names = FALSE)
cat("Saved:", file.path(OUTPUT_TAB, "phase5_moment4_pair_shock_by_buyer_nace2d_phase4.csv"), "\n")

# ===========================================================================
# Figure -- pair-shock distribution by phase (treated only; log scale)
# ===========================================================================
cat("\n=== Figure: pair-shock histograms by phase (treated) ===\n")

plot_data <- m4_active %>%
  filter(seller_is_ets == 1, pair_shock > 0) %>%
  group_by(phase5) %>%
  mutate(p99_within = quantile(pair_shock, 0.99, na.rm = TRUE),
         x_plot     = pmin(pair_shock, p99_within)) %>%
  ungroup()

p_hist <- ggplot(plot_data, aes(x = x_plot)) +
  geom_histogram(bins = 50, fill = "darkorange", alpha = 0.85) +
  facet_wrap(~ phase5, scales = "free", ncol = 2) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 0.01)) +
  labs(
    title    = "Pair-level shock distribution by ETS phase",
    subtitle = paste0("pair_shock = firm_cost_share x seller's share of buyer's input-NACE4d spend. ",
                      "Active treated pairs only. Winsorized at p99 within phase."),
    x        = "Pair-level cost-shock exposure (% of buyer's input-NACE4d bill)",
    y        = "Number of pair-years"
  ) +
  theme_minimal(base_size = 11) +
  theme(strip.background = element_rect(fill = "grey92", colour = NA),
        plot.title.position = "plot")

ggsave(file.path(OUTPUT_FIG, "phase5_moment4_pair_shock_distribution.pdf"),
       p_hist, width = 9, height = 6)
cat("Saved:", file.path(OUTPUT_FIG, "phase5_moment4_pair_shock_distribution.pdf"), "\n")

# ===========================================================================
# Combined readable summary
# ===========================================================================
sink(file.path(OUTPUT_TAB, "phase5_pair_shock_summary.txt"))

cat("================================================================\n")
cat("Plan A -- Pair-level shock magnitude\n")
cat("Moments 2 and 4 from SHOCK_AND_SUBSTITUTION_PLAN.md\n")
cat("Generated by analysis/phase5_pair_shock_magnitude.R\n")
cat("================================================================\n\n")

cat("Moment 2: cost-share at the ETS sellers in the B2B sample\n")
cat(sprintf("  ETS sellers in B2B panel: %d\n",
            length(ets_sellers_in_b2b)))
cat(sprintf("  Firm-year obs (cost share defined): %d\n\n", nrow(m2_panel)))

cat("--------------------------------------------------------------\n")
cat("Moment 2.A -- by phase\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(moment2), digits = 4)
cat("\n")

cat("--------------------------------------------------------------\n")
cat("Moment 2.B -- Phase IV only, by NACE 2d (B2B-sample sellers)\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(moment2_nace), digits = 4)
cat("\n")

cat("Moment 4: pair-level shock\n")
cat("  pair_shock_{j,b,t} = firm_cost_share_{j,t}\n")
cat("                     * (seller j's share of buyer b's input-NACE4d spend in t)\n\n")

cat("--------------------------------------------------------------\n")
cat("Moment 4.A -- distribution over ALL active pair-years\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(moment4), digits = 4)
cat("\n")

cat("--------------------------------------------------------------\n")
cat("Moment 4.B -- distribution over TREATED active pair-years\n")
cat("    (ETS sellers only; this is where the leakage incentive lives)\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(moment4_treated), digits = 4)
cat("\n")

cat("--------------------------------------------------------------\n")
cat("Moment 4.C -- Phase IV TREATED, by BUYER NACE 2d\n")
cat("    (which downstream buyers face meaningful exposure?)\n")
cat("--------------------------------------------------------------\n")
print(as.data.frame(moment4_buyer_nace), digits = 4)
cat("\n")

cat("================================================================\n")
cat("Verdict reading:\n")
cat("  Plan A's headline question: at the p90 TREATED active pair in\n")
cat("  Phase IV, what fraction of the buyer's input bill is exposed?\n")
cat("  See moment4_treated row for phase5 == 'IV', column p90.\n")
cat("    > 5%  -> shock is real; B2B null is informative.\n")
cat("    1-5%  -> shock is moderate; flag in paper.\n")
cat("    < 1%  -> shock is small; reframe paper around Phase IV only\n")
cat("            or pivot the research question.\n")
cat("================================================================\n")

sink()
cat("Saved:", file.path(OUTPUT_TAB, "phase5_pair_shock_summary.txt"), "\n")

cat("\nDone.\n")
