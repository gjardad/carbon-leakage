###############################################################################
# phase4_new_relationships_intensive_overlap.R
#
# PURPOSE
#   Reconcile the new-supplier omega-rank result (extensive-margin within
#   NACE4d, declining post-2013) with the absence of any intensive-margin
#   within-NACE4d reallocation. Two specific questions:
#
#   Q1. Are the two subsamples disjoint?
#       - Omega-rank sample: every new (buyer, seller, year_first) pair with
#         a matchable ETS-firm omega for the supplier.
#       - Intensive-margin sample: buyer-NACE4d-year cells with >=2 distinct
#         ETS-firm sellers.
#       For each new relationship, classify the buyer-NACE4d-year cell as
#       single-seller (irrelevant for intensive margin) vs multi-seller (in
#       intensive margin universe). Tabulate the share per year.
#
#   Q2. How big are new relationships within the buyer-NACE4d cell?
#       For each new relationship, compute
#         new_share_within_nace4d_jt = sales(j, new_seller, t)
#                                      / sum_{k in NACE4d N} sales(j, k, t)
#       If this share is typically small (e.g. <5%), the intensive margin is
#       insensitive to which new supplier the buyer picks -- the bulk of the
#       buyer's expenditure stays with incumbent suppliers.
#
#   Also report new-relationship sales as a share of total buyer-year B2B
#   spend, as a buyer-portfolio-level magnitude check.
#
# OUTPUTS
#   - phase4_new_relationships_intensive_overlap_counts.{png,pdf,csv}
#   - phase4_new_relationships_intensive_overlap_size.{png,pdf,csv}
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

YEAR_LO     <- 2005L
YEAR_HI     <- 2022L
EVENT_YEARS <- c(2005L, 2017L)

# ---------------------------------------------------------------------------
# 1. Load data (B2B with sales kept this time)
# ---------------------------------------------------------------------------
cat("Loading data...\n")

load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year),
             sales)]

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
  emissions, total_cost,
  nace4d = as.character(nace4d)
)]
rm(firm_exposure)
fe[, omega2 := ifelse(!is.na(emissions) & !is.na(total_cost) & total_cost > 0,
                      emissions / total_cost, NA_real_)]
fe_omega <- fe[!is.na(omega2), .(seller = vat, year, has_omega = TRUE)]

ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]

# Attach seller NACE4d, restrict to ETS-treated
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d %in% ets_treated_nace4d]

# Flag sellers with omega in year t (intensive margin requires omega-able firms)
b2b <- merge(b2b, fe_omega,
             by = c("seller", "year"), all.x = TRUE)
b2b[is.na(has_omega), has_omega := FALSE]

# ---------------------------------------------------------------------------
# 2. Per (buyer, year, seller_nace4d) cell stats
# ---------------------------------------------------------------------------
cell <- b2b[, .(
  n_sellers_in_cell        = uniqueN(seller),
  n_omega_sellers_in_cell  = uniqueN(seller[has_omega == TRUE]),
  cell_total_spend         = sum(sales),
  cell_omega_spend         = sum(sales[has_omega == TRUE])
), by = .(buyer, year, seller_nace4d)]

# Buyer-year total B2B spend (across ALL NACE4d, ETS or not -- we restricted
# earlier to ETS-NACE4d sellers, so this is total spend on ETS-NACE4d). For
# a clean denominator over the buyer's full portfolio we'd need to keep the
# non-ETS rows too; the metric here is "share of buyer's ETS-NACE4d spend
# that is in this new relationship", which is the more leakage-relevant
# denominator.
buyer_year_spend <- b2b[, .(buyer_ets_spend = sum(sales)),
                        by = .(buyer, year)]

# ---------------------------------------------------------------------------
# 3. Identify new relationships and attach cell/buyer context
# ---------------------------------------------------------------------------
first_year <- b2b[, .(year_first = min(year)), by = .(buyer, seller)]
new_rel <- first_year[year_first > YEAR_LO]

# Attach the new-relationship-year sales + supplier NACE4d + omega flag
new_rel <- merge(new_rel,
                 b2b[, .(buyer, seller, year, seller_nace4d, sales, has_omega)],
                 by.x = c("buyer", "seller", "year_first"),
                 by.y = c("buyer", "seller", "year"))
setnames(new_rel, "sales", "new_sales")

# Attach cell context (sellers and spend in the SAME buyer-NACE4d-year cell)
new_rel <- merge(new_rel,
                 cell,
                 by.x = c("buyer", "year_first", "seller_nace4d"),
                 by.y = c("buyer", "year",       "seller_nace4d"),
                 all.x = TRUE)

# Attach buyer-year total ETS-NACE4d spend
new_rel <- merge(new_rel,
                 buyer_year_spend,
                 by.x = c("buyer", "year_first"),
                 by.y = c("buyer", "year"),
                 all.x = TRUE)

# Compute shares
new_rel[, share_within_cell      := new_sales / cell_total_spend]
new_rel[, share_within_buyer_ets := new_sales / buyer_ets_spend]

# Restrict to omega-matched new relationships (the omega-rank plot universe)
new_rel_omega <- new_rel[has_omega == TRUE]

cat(sprintf("\nNew relationships in ETS-NACE4d (year > %d): %d\n", YEAR_LO, nrow(new_rel)))
cat(sprintf("  with omega-matched supplier: %d (this is the omega-rank universe)\n",
            nrow(new_rel_omega)))

# ---------------------------------------------------------------------------
# 4. Q1: Overlap with the intensive-margin universe
# ---------------------------------------------------------------------------
# Intensive margin requires the cell to have >=2 ETS-firm (omega-able) sellers.
# A "useful overlap" row is one where the cell-at-year-of-new-pair has >=2
# omega-able sellers AND one of them is the new supplier.
new_rel_omega[, in_imargin := n_omega_sellers_in_cell >= 2L]

overlap_yearly <- new_rel_omega[, .(
  n_new            = .N,
  n_single_omega   = sum(!in_imargin),
  n_multi_omega    = sum(in_imargin),
  share_in_imargin = mean(in_imargin)
), by = year_first]
setorder(overlap_yearly, year_first)

fwrite(overlap_yearly,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_intensive_overlap_counts.csv"))

cat("\nQ1: per year, share of new (omega-matched) relationships landing in cells with >=2 omega-able sellers:\n")
print(overlap_yearly)

base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom")

p_overlap <- ggplot(overlap_yearly,
                    aes(x = year_first, y = share_in_imargin)) +
  geom_line(color = "steelblue", linewidth = 0.95) +
  geom_point(color = "steelblue", size = 1.4) +
  geom_hline(yintercept = 0.5, linetype = "dotted", color = "grey30") +
  geom_vline(xintercept = EVENT_YEARS - 0.5,
             linetype = "dashed", color = "firebrick") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::percent_format(accuracy = 1)) +
  labs(title    = "Share of new (omega-matched) relationships landing in intensive-margin cells",
       subtitle = "Cell-in-intensive-margin = buyer's NACE4d-year cell has >=2 omega-able sellers. Below 1 means the omega-rank sample partially lives outside the intensive-margin universe.",
       x = NULL, y = "Share of new (omega-matched) relationships") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_intensive_overlap_counts.png"),
       p_overlap, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_intensive_overlap_counts.pdf"),
       p_overlap, width = 9, height = 5)

# ---------------------------------------------------------------------------
# 5. Q2: Size of new relationships within the buyer-NACE4d cell
# ---------------------------------------------------------------------------
# Pooled distribution
cat("\nQ2: distribution of new-relationship share within buyer-NACE4d-year cell (omega-matched sample):\n")
pooled_q <- quantile(new_rel_omega$share_within_cell,
                     probs = c(.10, .25, .50, .75, .90, .99), na.rm = TRUE)
print(round(pooled_q, 4))

cat("\nDistribution of new-relationship share within buyer's total ETS-NACE4d spend:\n")
pooled_q_buyer <- quantile(new_rel_omega$share_within_buyer_ets,
                           probs = c(.10, .25, .50, .75, .90, .99), na.rm = TRUE)
print(round(pooled_q_buyer, 4))

yearly_size <- new_rel_omega[, .(
  n_obs       = .N,
  median_cell = median(share_within_cell,      na.rm = TRUE),
  p25_cell    = quantile(share_within_cell, .25, na.rm = TRUE),
  p75_cell    = quantile(share_within_cell, .75, na.rm = TRUE),
  mean_cell   = mean(share_within_cell, na.rm = TRUE),
  median_buyer  = median(share_within_buyer_ets, na.rm = TRUE),
  mean_buyer    = mean(share_within_buyer_ets, na.rm = TRUE)
), by = year_first]
setorder(yearly_size, year_first)

fwrite(yearly_size,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_intensive_overlap_size.csv"))

cat("\nYearly summary of new-relationship size within the buyer-NACE4d cell:\n")
print(yearly_size[, .(year_first, n_obs,
                      cell_p25  = round(p25_cell, 3),
                      cell_med  = round(median_cell, 3),
                      cell_mean = round(mean_cell, 3),
                      cell_p75  = round(p75_cell, 3),
                      buyer_med = round(median_buyer, 4))])

# Plot A: yearly median + IQR of new-relationship share within cell
p_size_yearly <- ggplot(yearly_size,
                        aes(x = year_first)) +
  geom_ribbon(aes(ymin = p25_cell, ymax = p75_cell),
              alpha = 0.18, fill = "steelblue") +
  geom_line(aes(y = median_cell), color = "steelblue", linewidth = 0.95) +
  geom_point(aes(y = median_cell), color = "steelblue", size = 1.4) +
  geom_line(aes(y = mean_cell), color = "firebrick", linewidth = 0.85,
            linetype = "longdash") +
  geom_vline(xintercept = EVENT_YEARS - 0.5,
             linetype = "dashed", color = "firebrick", alpha = 0.4) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::percent_format(accuracy = 1)) +
  labs(title    = "Size of new relationships within the buyer-NACE4d-year cell",
       subtitle = "Median (blue) + IQR (shaded). Mean (red dashed). Share = new-supplier sales / buyer's total spend in that NACE4d that year.",
       x = NULL, y = "Share of buyer-NACE4d cell expenditure on the new supplier") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_intensive_overlap_size.png"),
       p_size_yearly, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_intensive_overlap_size.pdf"),
       p_size_yearly, width = 9, height = 5)

# Plot B: pooled histogram of new-relationship share within cell.
#
# Note on the binning: a large fraction of observations sit at exactly
# share = 1 (single-seller cells, where the new supplier IS the buyer's
# entire NACE4d spend that year). Default geom_histogram() uses
# closed = "left", which would silently DROP values at exactly 1.0
# from the visualization. We use closed = "right" with boundary = 0 so
# the rightmost bin (0.98, 1.00] includes the mass at 1.0. We also use
# a log10 y-axis so both the spike at 1.0 and the rest of the
# distribution are legible on one plot.
p_size_hist <- ggplot(new_rel_omega[!is.na(share_within_cell)],
                      aes(x = share_within_cell, fill = in_imargin)) +
  geom_histogram(position = "stack", binwidth = 0.02,
                 boundary = 0, closed = "right", alpha = 0.85) +
  scale_x_continuous(limits = c(-0.01, 1.01),
                     breaks = seq(0, 1, 0.2),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_y_log10(labels = scales::comma_format()) +
  scale_fill_manual(values = c("FALSE" = "#cccccc", "TRUE" = "#1f78b4"),
                    name = "Cell in intensive-margin sample (>=2 omega sellers)",
                    labels = c("No (single seller)", "Yes (>=2 sellers)")) +
  labs(title    = "Pooled distribution of new-relationship share within the buyer-NACE4d cell",
       subtitle = "All omega-matched new relationships 2006-2022 pooled. Stacked by whether the cell qualifies for the intensive-margin sample. Log y-axis.",
       x = "Share of buyer's NACE4d spend going to the new supplier",
       y = "Count of new relationships (log scale)") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_intensive_overlap_size_hist.png"),
       p_size_hist, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_intensive_overlap_size_hist.pdf"),
       p_size_hist, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
