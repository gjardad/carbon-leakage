###############################################################################
# phase4_new_relationships_omega_rank_diagnostics.R
#
# PURPOSE
#   Diagnostics for the new-supplier omega-rank result (within-NACE4d
#   extensive margin). Asks three sanity questions before treating the
#   pre/post-2013 rank drop as a clean leakage signal:
#
#     (1) Sample-size sanity per year
#           - total b2b pairs (buyer-seller-year cells)
#           - new pairs (first observed in year, year > min-year)
#           - new pairs IN ETS-treated NACE4d
#           - new pairs in ETS NACE4d with a matchable ETS-firm supplier
#             (this is the sample that enters the rank plot)
#           - distinct buyers, suppliers, supplier NACE4d sectors per year
#
#     (2) Leave-one-NACE4d-out
#           - For each ETS-treated NACE4d N, drop ALL new pairs whose
#             supplier is in N and recompute the yearly mean-rank
#             trajectory. Plot all 80-odd trajectories overlaid on the
#             main line. If the result is driven by one or two large
#             NACE4d (e.g. 3511 electricity), those LOO trajectories
#             should visibly diverge.
#           - Also report the 2013 pre/post diff for each LOO trajectory.
#
#     (3) Leave-one-buyer-out (top buyers)
#           - For the top-K buyers by total number of new pairs in the
#             sample, drop each and recompute. Same plot + diff table.
#
#   Uses Def 2 (emissions/total_cost) as the headline because Def 2 is
#   the structural carbon-burden measure (independent of free-allocation
#   rule revisions); Def 1 is run in parallel for completeness.
#
# OUTPUTS
#   - phase4_new_relationships_omega_rank_cellcounts.{png,pdf,csv}
#   - phase4_new_relationships_omega_rank_loo_nace4d.{png,pdf}
#   - phase4_new_relationships_omega_rank_loo_nace4d_2013diff.csv
#   - phase4_new_relationships_omega_rank_loo_buyer.{png,pdf}
#   - phase4_new_relationships_omega_rank_loo_buyer_2013diff.csv
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

set.seed(20260511)

YEAR_LO <- 2005L
YEAR_HI <- 2022L
EVENT_YEARS <- c(2008L, 2013L, 2017L)
PRE_POST_WINDOW <- 5L
TOP_K_BUYERS <- 10L

# ---------------------------------------------------------------------------
# 1. Load data (mirrors the headline script)
# ---------------------------------------------------------------------------
cat("Loading data...\n")

load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b_full <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(sales) & sales > 0,
                .(seller = as.character(seller),
                  buyer  = as.character(buyer),
                  year   = as.integer(year))]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano),
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(
  vat = as.character(vat),
  year = as.integer(year),
  emissions, allocated_free, shortage, total_cost,
  nace4d = as.character(nace4d)
)]
rm(firm_exposure)

fe[, omega1 := ifelse(!is.na(shortage) & !is.na(total_cost) & total_cost > 0,
                      shortage / total_cost, NA_real_)]
fe[, omega2 := ifelse(!is.na(emissions) & !is.na(total_cost) & total_cost > 0,
                      emissions / total_cost, NA_real_)]

ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]

# B2B with supplier NACE4d (some sellers may have no AA row in some years)
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b_full <- merge(b2b_full, seller_nace, by = c("seller", "year"), all.x = TRUE)

# ---------------------------------------------------------------------------
# 2. Cell counts per year
# ---------------------------------------------------------------------------
cat("\nBuilding per-year cell counts...\n")

# First-year-observed table for every (buyer, seller) pair seen in the panel
first_year <- b2b_full[, .(year_first = min(year)), by = .(buyer, seller)]

# All b2b pairs (year-by-year activity), restricted to ETS-NACE4d sellers
b2b_ets <- b2b_full[!is.na(seller_nace4d) & seller_nace4d %in% ets_treated_nace4d]

# New pairs (year-of-first-observation > YEAR_LO) within ETS-NACE4d
new_pairs <- merge(first_year[year_first > YEAR_LO],
                   b2b_ets[, .(buyer, seller, year, seller_nace4d)],
                   by.x = c("buyer", "seller", "year_first"),
                   by.y = c("buyer", "seller", "year"))

# Compute rank panels for both omega defs (within-NACE4d, within-year)
compute_rank <- function(omega_col) {
  d <- fe[!is.na(get(omega_col)),
          .(vat, year, nace4d, omega = get(omega_col))]
  d[, rank := frank(omega, ties.method = "average") / .N,
    by = .(nace4d, year)]
  d[, .(seller = vat, year, seller_nace4d = nace4d, rank)]
}
rank2 <- compute_rank("omega2")
rank1 <- compute_rank("omega1")

# Sample that enters the rank plot (Def 2)
in_plot2 <- merge(new_pairs, rank2,
                  by.x = c("seller", "year_first", "seller_nace4d"),
                  by.y = c("seller", "year",       "seller_nace4d"))
in_plot1 <- merge(new_pairs, rank1,
                  by.x = c("seller", "year_first", "seller_nace4d"),
                  by.y = c("seller", "year",       "seller_nace4d"))

# Per-year counts
counts <- merge(
  b2b_full[, .(n_b2b_pairs_all = .N), by = year],
  b2b_ets [, .(n_b2b_pairs_ets = .N), by = year],
  by = "year", all = TRUE
)
counts <- merge(counts,
                new_pairs[, .(n_new_pairs_ets = .N), by = .(year = year_first)],
                by = "year", all.x = TRUE)
counts <- merge(counts,
                in_plot1[, .(n_in_plot_def1 = .N), by = .(year = year_first)],
                by = "year", all.x = TRUE)
counts <- merge(counts,
                in_plot2[, .(n_in_plot_def2 = .N), by = .(year = year_first)],
                by = "year", all.x = TRUE)
counts <- merge(counts,
                in_plot2[, .(n_distinct_buyers   = uniqueN(buyer),
                             n_distinct_sellers  = uniqueN(seller),
                             n_distinct_nace4d   = uniqueN(seller_nace4d)),
                         by = .(year = year_first)],
                by = "year", all.x = TRUE)
for (col in setdiff(names(counts), "year")) {
  counts[is.na(get(col)), (col) := 0L]
}
setorder(counts, year)

fwrite(counts,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_cellcounts.csv"))

cat("\nPer-year cell counts:\n")
print(counts)

# Plot: log-scale stacked-like view of the funnel from all b2b pairs to
# the in-plot Def 2 sample.
counts_long <- melt(
  counts,
  id.vars = "year",
  measure.vars = c("n_b2b_pairs_all", "n_b2b_pairs_ets",
                   "n_new_pairs_ets", "n_in_plot_def2"),
  variable.name = "metric", value.name = "n")
counts_long[, metric := factor(metric,
  levels = c("n_b2b_pairs_all", "n_b2b_pairs_ets",
             "n_new_pairs_ets", "n_in_plot_def2"),
  labels = c("All B2B pairs",
             "B2B pairs in ETS-NACE4d",
             "New pairs in ETS-NACE4d",
             "New pairs in plot (Def 2)"))]

base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom")

p_counts <- ggplot(counts_long[n > 0],
                   aes(x = year, y = n, color = metric)) +
  geom_line(linewidth = 0.85) +
  geom_point(size = 1.2) +
  scale_y_log10(labels = scales::comma_format()) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  geom_vline(xintercept = EVENT_YEARS - 0.5,
             linetype = "dashed", color = "firebrick", alpha = 0.4) +
  labs(title    = "Sample funnel per year: from total B2B pairs to in-plot Def 2 new relationships",
       subtitle = "Log-scale count. Vertical dashes = ETS event years (2008/2013/2017).",
       x = NULL, y = "Count (log scale)") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_cellcounts.png"),
       p_counts, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_cellcounts.pdf"),
       p_counts, width = 9, height = 5)

# ---------------------------------------------------------------------------
# 3. Leave-one-NACE4d-out (Def 2)
# ---------------------------------------------------------------------------
cat("\nLeave-one-NACE4d-out (Def 2)...\n")

# Per-year main-line mean rank
mainline_d2 <- in_plot2[, .(mean_rank = mean(rank),
                            n_obs    = .N), by = .(year_first)]
setorder(mainline_d2, year_first)

loo_nace4d_list <- list()
nace4ds <- unique(in_plot2$seller_nace4d)
for (N in nace4ds) {
  d <- in_plot2[seller_nace4d != N]
  if (nrow(d) == 0L) next
  yr <- d[, .(mean_rank = mean(rank), n_obs = .N), by = year_first]
  yr[, dropped_nace4d := N]
  loo_nace4d_list[[N]] <- yr
}
loo_nace4d <- rbindlist(loo_nace4d_list, use.names = TRUE)
setorder(loo_nace4d, dropped_nace4d, year_first)

# 2013 pre/post diff per dropped NACE4d
event_year <- 2013L
loo_2013 <- loo_nace4d[, {
  pre  <- mean_rank[year_first >= event_year - PRE_POST_WINDOW &
                    year_first <  event_year]
  post <- mean_rank[year_first >= event_year &
                    year_first <= event_year + PRE_POST_WINDOW - 1L]
  .(mean_pre = mean(pre), mean_post = mean(post),
    diff_2013 = mean(post) - mean(pre))
}, by = dropped_nace4d]

# Reference: full-sample (no drop) diff at 2013
full_pre  <- mainline_d2[year_first >= event_year - PRE_POST_WINDOW &
                         year_first <  event_year, mean_rank]
full_post <- mainline_d2[year_first >= event_year &
                         year_first <= event_year + PRE_POST_WINDOW - 1L,
                         mean_rank]
full_diff_2013 <- mean(full_post) - mean(full_pre)
cat(sprintf("  full-sample 2013 pre/post diff (mean of yearly means): %.3f\n",
            full_diff_2013))

setorder(loo_2013, diff_2013)
fwrite(loo_2013,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_loo_nace4d_2013diff.csv"))

cat("\nTop / bottom NACE4d by sensitivity of the 2013 pre/post diff (Def 2):\n")
cat("(diff_2013 = mean rank in 2013-17 minus mean rank in 2008-12,\n",
    " excluding the listed NACE4d. Compare to full-sample diff =",
    round(full_diff_2013, 3), ").\n", sep = "")
print(head(loo_2013, 5))
cat("---\n")
print(tail(loo_2013, 5))

# Plot all LOO trajectories overlaid on the main line
p_loo_nace4d <- ggplot() +
  geom_line(data = loo_nace4d,
            aes(x = year_first, y = mean_rank, group = dropped_nace4d),
            color = "grey60", alpha = 0.35, linewidth = 0.3) +
  geom_line(data = mainline_d2,
            aes(x = year_first, y = mean_rank),
            color = "steelblue", linewidth = 0.95) +
  geom_point(data = mainline_d2,
             aes(x = year_first, y = mean_rank),
             color = "steelblue", size = 1.4) +
  geom_hline(yintercept = 0.5, linetype = "dotted", color = "grey30") +
  geom_vline(xintercept = EVENT_YEARS - 0.5,
             linetype = "dashed", color = "firebrick") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::number_format(accuracy = 0.01)) +
  labs(title    = sprintf("Leave-one-NACE4d-out: new-supplier omega rank (Def 2: emissions/cost), %d trajectories", length(nace4ds)),
       subtitle = "Each grey line = recompute dropping one supplier-NACE4d. Blue = main full-sample line. If grey lines diverge from blue at any year, that year is sensitive to one NACE4d.",
       x = NULL, y = "Mean omega percentile rank within NACE4d (ETS firms)") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_loo_nace4d.png"),
       p_loo_nace4d, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_loo_nace4d.pdf"),
       p_loo_nace4d, width = 9, height = 5)

# ---------------------------------------------------------------------------
# 4. Leave-one-buyer-out for top-K buyers by number of new pairs (Def 2)
# ---------------------------------------------------------------------------
cat("\nLeave-one-buyer-out (top", TOP_K_BUYERS, "by n_new_pairs)...\n")

buyer_n <- in_plot2[, .(n_new_pairs = .N), by = buyer]
setorder(buyer_n, -n_new_pairs)
top_buyers <- buyer_n[1:min(TOP_K_BUYERS, nrow(buyer_n)), buyer]

loo_buyer_list <- list()
for (b in top_buyers) {
  d <- in_plot2[buyer != b]
  yr <- d[, .(mean_rank = mean(rank), n_obs = .N), by = year_first]
  yr[, dropped_buyer := b]
  loo_buyer_list[[b]] <- yr
}
loo_buyer <- rbindlist(loo_buyer_list, use.names = TRUE)
setorder(loo_buyer, dropped_buyer, year_first)

loo_buyer_2013 <- loo_buyer[, {
  pre  <- mean_rank[year_first >= event_year - PRE_POST_WINDOW &
                    year_first <  event_year]
  post <- mean_rank[year_first >= event_year &
                    year_first <= event_year + PRE_POST_WINDOW - 1L]
  .(mean_pre = mean(pre), mean_post = mean(post),
    diff_2013 = mean(post) - mean(pre))
}, by = dropped_buyer]

# Attach n_new_pairs for context
loo_buyer_2013 <- merge(loo_buyer_2013,
                        buyer_n[, .(dropped_buyer = buyer, n_new_pairs)],
                        by = "dropped_buyer", all.x = TRUE)
setorder(loo_buyer_2013, diff_2013)

fwrite(loo_buyer_2013,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_loo_buyer_2013diff.csv"))

cat("\nTop-K buyer leave-one-out 2013 pre/post diff (Def 2):\n")
cat("(buyer VAT hashes truncated for readability; full hash in CSV.)\n")
loo_buyer_2013[, dropped_buyer_short := substr(dropped_buyer, 1, 10)]
print(loo_buyer_2013[, .(dropped_buyer_short, n_new_pairs,
                         pre   = round(mean_pre,  3),
                         post  = round(mean_post, 3),
                         diff  = round(diff_2013, 3))])

# Plot overlay
p_loo_buyer <- ggplot() +
  geom_line(data = loo_buyer,
            aes(x = year_first, y = mean_rank, group = dropped_buyer),
            color = "grey60", alpha = 0.5, linewidth = 0.4) +
  geom_line(data = mainline_d2,
            aes(x = year_first, y = mean_rank),
            color = "steelblue", linewidth = 0.95) +
  geom_point(data = mainline_d2,
             aes(x = year_first, y = mean_rank),
             color = "steelblue", size = 1.4) +
  geom_hline(yintercept = 0.5, linetype = "dotted", color = "grey30") +
  geom_vline(xintercept = EVENT_YEARS - 0.5,
             linetype = "dashed", color = "firebrick") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::number_format(accuracy = 0.01)) +
  labs(title    = sprintf("Leave-one-buyer-out: new-supplier omega rank (Def 2: emissions/cost), top %d buyers", TOP_K_BUYERS),
       subtitle = "Each grey line = recompute dropping one of the top-K buyers (by # new pairs). Blue = main full-sample line.",
       x = NULL, y = "Mean omega percentile rank within NACE4d (ETS firms)") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_loo_buyer.png"),
       p_loo_buyer, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_loo_buyer.pdf"),
       p_loo_buyer, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
