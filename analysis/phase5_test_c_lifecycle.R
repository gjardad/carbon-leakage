###############################################################################
# phase5_test_c_lifecycle.R
#
# Test C of Plan B: descriptive life-cycle moments on Belgian B2B, analogous
# to Heise (2024 AER) Figures 1a and 2a-b.
#
# Purpose: establish whether Belgian B2B exhibits Heise-type relational
# dynamics. If life-cycle is essentially flat, the stickiness narrative is
# weak regardless of A/B/G outcomes -- concentration / shock-too-small are
# more parsimonious explanations.
#
# Three moments (descriptive, no regression):
#
#   C1 -- Distribution of pair lengths and trade-value share by length bucket.
#         Heise Figure 1a analog.
#         Pair length = last_year_pair - first_year_pair + 1.
#         For pairs still active in 2022 (right-censored), report length so far
#         AND a separate "censored vs completed" tabulation.
#
#   C2 -- Within total-duration cohort, mean log(corr_sales) by relationship
#         year, normalized to year 1.
#         Heise Figure 2a analog. A hump (rising then falling) signals
#         relational dynamics; flat = pure scale persistence.
#
#   C3 -- Break-up hazard by pair age.
#         Heise Figure 2b analog.
#         hazard(τ) = P(pair last observed in year t | active in year t,
#                       pair_age = τ at year t).
#         Computed only on pairs whose end year is observable (drop right-
#         censored pairs still active in 2022 from numerator -- but include
#         them in denominator until their final observed year).
#
# Caveats:
#   - B2B starts 2002; pairs with first_year_pair == 2002 are LEFT-censored
#     (true age may be older). Show all moments separately for left-censored
#     vs non-left-censored pairs so pre-2002 pairs don't contaminate the
#     life-cycle estimates.
#   - Trade volume = corr_sales (per-year EUR aggregate per pair).
#   - Heise records product-line counts inside each pair; Belgian B2B does
#     not. So the product-count moment is omitted (flagged in plan).
#
# Output:
#   output/tables/phase5_test_c_pair_length_distribution.csv
#   output/tables/phase5_test_c_trade_volume_lifecycle.csv
#   output/tables/phase5_test_c_breakup_hazard.csv
#   output/figures/phase5_test_c_lifecycle.pdf  -- 3-panel figure
###############################################################################

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("ggplot2", quietly = TRUE))
  install.packages("ggplot2", repos = "https://cloud.r-project.org")
if (!requireNamespace("patchwork", quietly = TRUE))
  install.packages("patchwork", repos = "https://cloud.r-project.org")

library(data.table)
library(haven)
library(ggplot2)
library(patchwork)

B2B_FIRST_YEAR <- 2002L
B2B_LAST_YEAR  <- 2022L

# ---------------------------------------------------------------------------
# 1. Load raw B2B + pair-age
# ---------------------------------------------------------------------------
b2b_path <- file.path(RAW_DATA, "NBB", "B2B_ANO.dta")
cat("Loading raw B2B from:", b2b_path, "\n")
b2b <- as.data.table(read_dta(b2b_path,
                              col_select = c("vat_i_ano", "vat_j_ano",
                                             "year", "corr_sales_ij")))
setnames(b2b,
         c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         c("seller", "buyer", "corr_sales"))
b2b <- b2b[!is.na(corr_sales) & corr_sales > 0]
b2b[, year := as.integer(year)]
cat("Active pair-year rows:", nrow(b2b), "\n")

load(file.path(PROC_DATA, "b2b_pair_age.RData"))   # pair_age
b2b <- merge(b2b, pair_age, by = c("seller", "buyer"), all.x = TRUE)
b2b[, pair_age_t := year - first_year_pair]

# ---------------------------------------------------------------------------
# 2. Per-pair summary: length, last year, censoring
# ---------------------------------------------------------------------------
pair_summary <- b2b[, .(
  first_year      = min(year),
  last_year       = max(year),
  n_active_years  = uniqueN(year),
  total_corr_sales = sum(corr_sales),
  mean_corr_sales  = mean(corr_sales)
), by = .(seller, buyer)]

pair_summary[, length_obs   := last_year - first_year + 1L]
pair_summary[, is_left_censored  := as.integer(first_year == B2B_FIRST_YEAR)]
pair_summary[, is_right_censored := as.integer(last_year == B2B_LAST_YEAR)]

cat(sprintf("Total pairs: %d\n", nrow(pair_summary)))
cat(sprintf("Left-censored (first_year=2002):  %d (%.1f%%)\n",
            sum(pair_summary$is_left_censored),
            100 * mean(pair_summary$is_left_censored)))
cat(sprintf("Right-censored (last_year=2022):  %d (%.1f%%)\n",
            sum(pair_summary$is_right_censored),
            100 * mean(pair_summary$is_right_censored)))

# ---------------------------------------------------------------------------
# C1 -- Pair-length distribution by bucket (% of pairs, % of trade)
# ---------------------------------------------------------------------------
cat("\n=== C1: pair-length distribution by bucket ===\n")
length_buckets <- function(L) {
  cut(L,
      breaks = c(0, 1, 3, 5, 10, 21),
      labels = c("1y", "2-3y", "4-5y", "6-10y", "11-21y"),
      right  = TRUE,
      include.lowest = TRUE)
}
pair_summary[, length_bucket := length_buckets(length_obs)]

c1_full <- pair_summary[, .(
  n_pairs          = .N,
  share_of_pairs   = .N / nrow(pair_summary),
  total_trade      = sum(total_corr_sales),
  share_of_trade   = sum(total_corr_sales) / sum(pair_summary$total_corr_sales)
), by = length_bucket][order(length_bucket)]

c1_no_lc <- pair_summary[is_left_censored == 0L, .(
  n_pairs          = .N,
  share_of_pairs   = .N / sum(pair_summary$is_left_censored == 0L),
  total_trade      = sum(total_corr_sales),
  share_of_trade   = sum(total_corr_sales) /
                     sum(pair_summary[is_left_censored == 0L, total_corr_sales])
), by = length_bucket][order(length_bucket)]

c1_no_lc[, sample := "non-left-censored"]
c1_full[,  sample := "all_pairs"]
c1_combined <- rbindlist(list(c1_full, c1_no_lc), use.names = TRUE)
setcolorder(c1_combined, c("sample", "length_bucket"))
print(c1_combined)
fwrite(c1_combined,
       file.path(OUTPUT_TAB, "phase5_test_c_pair_length_distribution.csv"))

# ---------------------------------------------------------------------------
# C2 -- Trade-volume life-cycle within total-duration cohort
# ---------------------------------------------------------------------------
cat("\n=== C2: trade-volume life-cycle (mean log corr_sales by pair_age) ===\n")
# For each non-left-censored pair, compute log(corr_sales) at each pair_age_t,
# normalized to age 0 (year of formation).
b2b_clean <- b2b[is_left_censored == 0L]
b2b_clean[, log_sales := log(corr_sales)]

# Normalize: subtract the pair's own log_sales at age 0.
sales_age0 <- b2b_clean[pair_age_t == 0L,
                        .(seller, buyer, log_sales_age0 = log_sales)]
b2b_clean <- merge(b2b_clean, sales_age0,
                   by = c("seller", "buyer"), all.x = TRUE)
b2b_clean[, dlog := log_sales - log_sales_age0]

# Total-duration cohort: bucket on length_obs.
b2b_clean <- merge(b2b_clean,
                   pair_summary[, .(seller, buyer, length_obs, length_bucket)],
                   by = c("seller", "buyer"), all.x = TRUE)

c2 <- b2b_clean[!is.na(dlog) & length_bucket %in% c("4-5y", "6-10y", "11-21y"),
                .(mean_dlog   = mean(dlog),
                  n_pairs     = .N,
                  median_dlog = median(dlog)),
                by = .(length_bucket, pair_age_t)][order(length_bucket, pair_age_t)]
print(c2)
fwrite(c2, file.path(OUTPUT_TAB, "phase5_test_c_trade_volume_lifecycle.csv"))

# ---------------------------------------------------------------------------
# C3 -- Break-up hazard by pair age
# ---------------------------------------------------------------------------
cat("\n=== C3: break-up hazard by pair age ===\n")
# At each year a pair is active, define:
#   active_now = 1
#   dies_now   = 1 if year == last_year_pair AND last_year_pair < B2B_LAST_YEAR
#   (i.e., pair is observed to terminate; right-censored last-year-2022 pairs
#    are excluded from the numerator but kept in the denominator until their
#    final observed year).
b2b <- merge(b2b,
             pair_summary[, .(seller, buyer, last_year, is_right_censored)],
             by = c("seller", "buyer"), all.x = TRUE)
b2b[, dies_t := as.integer(year == last_year & is_right_censored == 0L)]

# Hazard at age τ = sum dies_t over all pairs with pair_age_t == τ /
#                  total active pair-years at pair_age_t == τ
hazard_dt <- b2b[is_left_censored == 0L,
                 .(active = .N, deaths = sum(dies_t)),
                 by = pair_age_t][order(pair_age_t)]
hazard_dt[, hazard := deaths / active]
hazard_dt <- hazard_dt[active >= 50L]
print(hazard_dt)
fwrite(hazard_dt, file.path(OUTPUT_TAB, "phase5_test_c_breakup_hazard.csv"))

# ---------------------------------------------------------------------------
# Three-panel figure
# ---------------------------------------------------------------------------
p1 <- ggplot(c1_no_lc,
             aes(x = length_bucket)) +
  geom_col(aes(y = share_of_pairs, fill = "share of pairs"),
           position = position_dodge(width = 0.8), width = 0.35) +
  geom_col(aes(y = share_of_trade, fill = "share of trade"),
           position = position_nudge(x = 0.4), width = 0.35) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_fill_manual(values = c("share of pairs" = "steelblue",
                                "share of trade" = "darkorange")) +
  labs(title = "C1: pair-length distribution (non-left-censored)",
       x = "Observed pair length",
       y = NULL, fill = NULL) +
  theme_minimal(base_size = 11)

p2 <- ggplot(c2[length_bucket != "1y"],
             aes(x = pair_age_t, y = mean_dlog, colour = length_bucket)) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 1.2) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  labs(title = "C2: log trade volume life-cycle",
       subtitle = "Within total-duration cohort, mean log(corr_sales) - log(corr_sales at age 0)",
       x = "Relationship age (years since first observed)",
       y = "Mean delta log(corr_sales)",
       colour = "Total duration") +
  theme_minimal(base_size = 11)

p3 <- ggplot(hazard_dt[pair_age_t <= 15L],
             aes(x = pair_age_t, y = hazard)) +
  geom_line(linewidth = 0.7, colour = "firebrick") +
  geom_point(size = 1.2, colour = "firebrick") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(title = "C3: break-up hazard by pair age",
       subtitle = "Hazard = P(pair ends in year t | active in year t, age=tau).  Excludes left-censored pairs.",
       x = "Relationship age", y = "Hazard rate") +
  theme_minimal(base_size = 11)

combined <- p1 / p2 / p3 +
  plot_annotation(
    title = "Test C: Heise (2024) life-cycle moments on Belgian B2B",
    subtitle = sprintf("Active pair-years: %d. Pairs (non-LC): %d.",
                       nrow(b2b), pair_summary[is_left_censored == 0L, .N]))

ggsave(file.path(OUTPUT_FIG, "phase5_test_c_lifecycle.pdf"),
       combined, width = 9, height = 11)
cat(sprintf("\nSaved: %s\n",
            file.path(OUTPUT_FIG, "phase5_test_c_lifecycle.pdf")))

cat("\nTest C complete.\n")
