###############################################################################
# phase4_within_nace4d_reallocation_plots.R
#
# PURPOSE
#   Plot, for each of three policy events (2008, 2013, 2017), the evolution of
#   the buyer's expenditure share, within an ETS-treated NACE4d sector, on the
#   single supplier with the highest pre-event allowance shortage / total cost
#   ratio (omega).
#
#   For each event we:
#     1. Restrict the B2B sample to buyer-supplier pairs whose supplier sits in
#        an ETS-treated NACE4d (= NACE4d that contains at least one EU-ETS
#        firm in our `firm_exposure` panel, in_sample == 1).
#     2. Build a firm-interval omega using a 2-year ratio of averages:
#               omega_{i,interval} = sum(shortage_t) / sum(total_cost_t)
#        over the two interval years (Phase I 2006-07, Phase II 2011-12,
#        Phase III 2015-16). shortage = max(emissions - allocated_free, 0).
#        total_cost = (revenue - value_added) + wage_bill.
#        Non-ETS firms (and ETS firms with missing data in either year) get
#        omega = 0 with `is_ets = 0`.
#     3. For each (buyer, supplier-NACE4d) cell, restrict the candidate
#        supplier set to those the buyer transacted with during the interval.
#        REQUIRE >=2 distinct suppliers in that interval (single-supplier cells
#        cannot reallocate within the NACE4d, so they are uninformative).
#        Pick the one with highest omega (ties broken by largest interval
#        sales then VAT), and drop cells where the max omega is 0.
#     4. Compute the share over time of the chosen supplier in the buyer's
#        within-NACE4d expenditure. Normalize each cell's series by the mean
#        of its share over the two interval years (positive by construction).
#     5. Aggregate two ways:
#         - pooled  : unweighted mean across cells with bootstrap 95% CIs
#         - by NACE4d : facet grid showing one panel per NACE4d (heterogeneity)
#
# OUTPUTS (output_local/figures/, output_local/tables/)
#   - phase4_within_nace4d_reallocation_pooled_{2008,2013,2017}.{png,pdf}
#   - phase4_within_nace4d_reallocation_pooled_combined.{png,pdf}
#         3-panel facet: mean of NORMALIZED share (the original spec)
#   - phase4_within_nace4d_reallocation_pooled_combined_raw.{png,pdf}
#         3-panel facet: mean of RAW share, bounded [0,1]
#   - phase4_within_nace4d_reallocation_by_nace4d_{2008,2013,2017}.{png,pdf}
#   - phase4_within_nace4d_reallocation_panel.csv     (cell-year normalized data)
#   - phase4_within_nace4d_reallocation_pooled.csv    (mean of normalized)
#   - phase4_within_nace4d_reallocation_pooled_raw.csv    (mean of raw share)
#   - phase4_within_nace4d_reallocation_by_nace4d.csv (year-version-NACE4d means)
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

set.seed(20260508)

YEAR_LO <- 2005L
YEAR_HI <- 2022L

INTERVALS <- list(
  "treat_2008" = list(years = c(2006L, 2007L), norm_year = 2007L, treat_year = 2008L),
  "treat_2013" = list(years = c(2011L, 2012L), norm_year = 2012L, treat_year = 2013L),
  "treat_2017" = list(years = c(2015L, 2016L), norm_year = 2016L, treat_year = 2017L)
)

N_BOOT <- 1000L

# ---------------------------------------------------------------------------
# 1. Load data
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
           .(seller, buyer, year, sales)]
cat(sprintf("  b2b rows after year/sales filter: %d\n", nrow(b2b)))

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = vat_ano,
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(vat, year, shortage, total_cost, nace4d)]
rm(firm_exposure)

# ---------------------------------------------------------------------------
# 2. ETS-treated NACE4d set
# ---------------------------------------------------------------------------
ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]
cat(sprintf("  ETS-treated NACE4d sectors (with >=1 in-sample ETS firm): %d\n",
            length(ets_treated_nace4d)))

# ---------------------------------------------------------------------------
# 3. Attach seller NACE4d to B2B (from AA), restrict to ETS-treated NACE4d
# ---------------------------------------------------------------------------
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
n_pre <- nrow(b2b)
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d %in% ets_treated_nace4d]
cat(sprintf("  rows after restricting to ETS-treated NACE4d sellers: %d / %d\n",
            nrow(b2b), n_pre))

# Within-NACE4d denominator: total spend by (buyer, seller_nace4d, year)
b2b[, total_buyer_nace4d_spend := sum(sales),
    by = .(buyer, seller_nace4d, year)]

# ---------------------------------------------------------------------------
# 4. Firm-interval omega panel
# ---------------------------------------------------------------------------
ets_vats_all <- unique(fe$vat)

build_firm_omega <- function(yrs) {
  d <- fe[year %in% yrs & !is.na(shortage) & !is.na(total_cost) & total_cost > 0,
          .(vat, year, shortage, total_cost)]
  o <- d[, .(n_yrs = .N,
             sum_short = sum(shortage),
             sum_cost  = sum(total_cost)),
         by = vat]
  o <- o[n_yrs == 2L & sum_cost > 0]
  o[, omega := sum_short / sum_cost]
  o[, .(vat, omega)]
}

firm_omega <- list()
for (k in names(INTERVALS)) {
  firm_omega[[k]] <- build_firm_omega(INTERVALS[[k]]$years)
  cat(sprintf("  %s: ETS firms with computable omega = %d (positive: %d)\n",
              k, nrow(firm_omega[[k]]),
              sum(firm_omega[[k]]$omega > 0)))
}

# ---------------------------------------------------------------------------
# 5. For each interval: identify highest-omega supplier per (buyer, NACE4d)
#    cell, build full-panel share trajectory, normalize by interval-mean share
# ---------------------------------------------------------------------------
process_interval <- function(label) {
  spec <- INTERVALS[[label]]
  yrs  <- spec$years
  norm_year <- spec$norm_year

  # Suppliers the buyer transacted with during the interval
  pre <- b2b[year %in% yrs,
             .(int_sales = sum(sales)),
             by = .(buyer, seller_nace4d, seller)]
  pre <- pre[int_sales > 0]

  # Restrict to cells with >=2 distinct suppliers in the interval (otherwise
  # within-NACE4d reallocation is mechanically zero).
  cell_n_supp <- pre[, .(n_supp = uniqueN(seller)),
                     by = .(buyer, seller_nace4d)]
  multi_cells <- cell_n_supp[n_supp >= 2L, .(buyer, seller_nace4d)]
  pre <- merge(pre, multi_cells, by = c("buyer", "seller_nace4d"))

  # Attach interval omega; non-matching firms (non-ETS or missing) get omega = 0
  pre <- merge(pre, firm_omega[[label]], by.x = "seller", by.y = "vat",
               all.x = TRUE)
  pre[, is_ets := as.integer(seller %in% ets_vats_all)]
  pre[is.na(omega), omega := 0]

  # Within (buyer, seller_nace4d): top supplier by omega; break ties by larger
  # interval sales, then by seller VAT (deterministic).
  setorder(pre, buyer, seller_nace4d, -omega, -int_sales, seller)
  top <- pre[, .SD[1L], by = .(buyer, seller_nace4d)]

  # Drop cells where top omega == 0 (no positively-exposed supplier in the cell)
  n_cells_pre <- nrow(top)
  top <- top[omega > 0]
  cat(sprintf("  %s: multi-supplier cells = %d (kept after omega>0 from %d)\n",
              label, nrow(top), n_cells_pre))

  if (nrow(top) == 0) return(data.table())

  # Bottom supplier (lowest omega; tie-break: largest int_sales then VAT).
  # Restricted to the same cells that survive the top-supplier filter.
  setorder(pre, buyer, seller_nace4d, omega, -int_sales, seller)
  bot <- pre[, .SD[1L], by = .(buyer, seller_nace4d)]
  bot <- bot[top[, .(buyer, seller_nace4d)],
             on = c("buyer", "seller_nace4d"), nomatch = 0L]

  cells <- top[, .(buyer, seller_nace4d, top_supplier = seller, omega, is_ets)]
  bcells <- bot[, .(buyer, seller_nace4d,
                    bottom_supplier = seller,
                    bottom_omega    = omega,
                    bottom_is_ets   = is_ets)]
  cells <- merge(cells, bcells, by = c("buyer", "seller_nace4d"))

  # Expand to all years 2005:2022 per cell
  panel <- cells[, .(year = YEAR_LO:YEAR_HI),
                 by = .(buyer, seller_nace4d,
                        top_supplier, bottom_supplier,
                        omega, bottom_omega, is_ets, bottom_is_ets)]

  # Attach denominator: total_buyer_nace4d_spend in (buyer, seller_nace4d, year)
  denom <- unique(b2b[, .(buyer, seller_nace4d, year, total_buyer_nace4d_spend)])
  panel <- merge(panel, denom,
                 by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)

  # Attach numerator: sales from top_supplier to buyer in year t
  num_top <- b2b[, .(buyer, seller_nace4d, top_supplier = seller, year,
                     top_sales = sales)]
  panel <- merge(panel, num_top,
                 by = c("buyer", "seller_nace4d", "top_supplier", "year"),
                 all.x = TRUE)
  panel[is.na(top_sales), top_sales := 0]

  # Numerator for bottom_supplier
  num_bot <- b2b[, .(buyer, seller_nace4d, bottom_supplier = seller, year,
                     bottom_sales = sales)]
  panel <- merge(panel, num_bot,
                 by = c("buyer", "seller_nace4d", "bottom_supplier", "year"),
                 all.x = TRUE)
  panel[is.na(bottom_sales), bottom_sales := 0]

  # Raw within-NACE4d shares (NA when denom 0/NA, else x_sales / denom).
  # `share` keeps its meaning (top-omega supplier's share) for backward
  # compatibility with downstream scripts.
  panel[, share := ifelse(
    is.na(total_buyer_nace4d_spend) | total_buyer_nace4d_spend <= 0,
    NA_real_,
    top_sales / total_buyer_nace4d_spend
  )]
  panel[, bottom_share := ifelse(
    is.na(total_buyer_nace4d_spend) | total_buyer_nace4d_spend <= 0,
    NA_real_,
    bottom_sales / total_buyer_nace4d_spend
  )]

  # Normalization: mean of share over the interval years.
  # Positive by construction since the top supplier transacted in >=1 year of
  # the interval.
  norm_dt <- panel[year %in% yrs,
                   .(norm_val = mean(share, na.rm = TRUE)),
                   by = .(buyer, seller_nace4d)]
  panel <- merge(panel, norm_dt,
                 by = c("buyer", "seller_nace4d"), all.x = TRUE)
  panel[, normalized_share := share / norm_val]
  panel[, version := label]
  panel[, treat_year := spec$treat_year]
  panel[, norm_year := norm_year]

  panel
}

panels_list <- lapply(names(INTERVALS), process_interval)
panel_all <- rbindlist(panels_list, use.names = TRUE, fill = TRUE)
cat(sprintf("\n  Combined panel rows: %d\n", nrow(panel_all)))

# ---------------------------------------------------------------------------
# 6. Aggregate -- pooled mean with bootstrap 95% CIs
# ---------------------------------------------------------------------------
boot_ci <- function(x, stat = mean, n_boot = N_BOOT, alpha = 0.05) {
  x <- x[!is.na(x)]
  if (length(x) < 5L) return(list(lo = NA_real_, hi = NA_real_))
  m <- length(x)
  draws <- replicate(n_boot, stat(x[sample.int(m, m, replace = TRUE)]))
  q <- quantile(draws, c(alpha / 2, 1 - alpha / 2), names = FALSE)
  list(lo = q[1], hi = q[2])
}

# Mean of NORMALIZED share (original spec)
pooled <- panel_all[!is.na(normalized_share),
                    {
                      ci <- boot_ci(normalized_share, stat = mean)
                      .(mean_share = mean(normalized_share),
                        median_share = median(normalized_share),
                        n_cells = .N,
                        ci_lo = ci$lo,
                        ci_hi = ci$hi)
                    },
                    by = .(version, treat_year, norm_year, year)]
setorder(pooled, version, year)

# Mean of RAW share (bounded [0, 1]) -- option (1)
pooled_raw <- panel_all[!is.na(share),
                        {
                          ci <- boot_ci(share, stat = mean)
                          .(mean_raw_share = mean(share),
                            n_cells = .N,
                            ci_lo = ci$lo,
                            ci_hi = ci$hi)
                        },
                        by = .(version, treat_year, norm_year, year)]
setorder(pooled_raw, version, year)

# ---------------------------------------------------------------------------
# 7. Aggregate -- by-NACE4d unweighted mean (no CIs)
# ---------------------------------------------------------------------------
by_nace <- panel_all[!is.na(normalized_share),
                     .(mean_share = mean(normalized_share),
                       n_cells = .N),
                     by = .(version, treat_year, norm_year, seller_nace4d, year)]
setorder(by_nace, version, seller_nace4d, year)

# Filter out NACE4d cells with too few buyer-cell observations
# (otherwise the facet plot is dominated by single-cell noise)
nace_cell_counts <- panel_all[year == norm_year & !is.na(normalized_share),
                              .(n_cells_at_norm = uniqueN(paste(buyer, seller_nace4d))),
                              by = .(version, seller_nace4d)]
MIN_CELLS_PER_NACE4D <- 3L
nace_keep <- nace_cell_counts[n_cells_at_norm >= MIN_CELLS_PER_NACE4D,
                              .(version, seller_nace4d)]
by_nace_plot <- merge(by_nace, nace_keep,
                      by = c("version", "seller_nace4d"))
cat(sprintf("\n  By-NACE4d facets: kept NACE4d sectors with >=%d cells per version:\n",
            MIN_CELLS_PER_NACE4D))
print(nace_keep[, .N, by = version])

# ---------------------------------------------------------------------------
# 8. Save underlying data
# ---------------------------------------------------------------------------
fwrite(panel_all,
       file.path(OUTPUT_TAB, "phase4_within_nace4d_reallocation_panel.csv"))
fwrite(pooled,
       file.path(OUTPUT_TAB, "phase4_within_nace4d_reallocation_pooled.csv"))
fwrite(pooled_raw,
       file.path(OUTPUT_TAB, "phase4_within_nace4d_reallocation_pooled_raw.csv"))
fwrite(by_nace,
       file.path(OUTPUT_TAB, "phase4_within_nace4d_reallocation_by_nace4d.csv"))

# ---------------------------------------------------------------------------
# 9. Plots
# ---------------------------------------------------------------------------
version_labels <- c(
  "treat_2008" = "Treatment 2008 (omega from 2006-07, normalized at 2007)",
  "treat_2013" = "Treatment 2013 (omega from 2011-12, normalized at 2012)",
  "treat_2017" = "Treatment 2017 (omega from 2015-16, normalized at 2016)"
)

base_theme <- theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"),
        panel.grid.minor = element_blank(),
        legend.position = "none")

# 9a. Pooled -- one panel per version (separate files) and combined facet
plot_pooled_one <- function(label) {
  d <- pooled[version == label]
  spec <- INTERVALS[[label]]
  ggplot(d, aes(x = year, y = mean_share)) +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.20, fill = "steelblue") +
    geom_line(color = "steelblue", linewidth = 0.9) +
    geom_point(color = "steelblue", size = 1.3) +
    geom_hline(yintercept = 1, linetype = "dotted", color = "grey30") +
    geom_vline(xintercept = spec$norm_year + 0.5, linetype = "dashed",
               color = "grey30") +
    geom_vline(xintercept = spec$treat_year - 0.5, linetype = "dashed",
               color = "firebrick") +
    scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
    labs(title = version_labels[label],
         subtitle = sprintf("Unweighted mean across %d buyer-NACE4d cells (95%% bootstrap CI). Red dashed = treatment year.",
                            max(d$n_cells, na.rm = TRUE)),
         x = NULL,
         y = "Normalized expenditure share on top-omega supplier") +
    base_theme
}

for (label in names(INTERVALS)) {
  p <- plot_pooled_one(label)
  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_within_nace4d_reallocation_pooled_%s.png",
                           sub("treat_", "", label))),
         p, width = 8, height = 4.5, dpi = 200)
  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_within_nace4d_reallocation_pooled_%s.pdf",
                           sub("treat_", "", label))),
         p, width = 8, height = 4.5)
}

# Combined 3-panel pooled figure
pooled_lab <- copy(pooled)
pooled_lab[, version_lab := factor(version,
                                   levels = names(version_labels),
                                   labels = version_labels)]
treat_lines <- data.table(
  version_lab = factor(version_labels, levels = version_labels),
  treat_year = sapply(INTERVALS, `[[`, "treat_year"),
  norm_year  = sapply(INTERVALS, `[[`, "norm_year")
)
p_combined <- ggplot(pooled_lab, aes(x = year, y = mean_share)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.20, fill = "steelblue") +
  geom_line(color = "steelblue", linewidth = 0.9) +
  geom_point(color = "steelblue", size = 1.1) +
  geom_hline(yintercept = 1, linetype = "dotted", color = "grey30") +
  geom_vline(data = treat_lines,
             aes(xintercept = norm_year + 0.5),
             linetype = "dashed", color = "grey30") +
  geom_vline(data = treat_lines,
             aes(xintercept = treat_year - 0.5),
             linetype = "dashed", color = "firebrick") +
  facet_wrap(~ version_lab, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  labs(title = "Within-NACE4d expenditure share on the top-omega supplier",
       subtitle = "Unweighted mean across buyer-NACE4d cells; 95% bootstrap CI; red = treatment year.",
       x = NULL,
       y = "Normalized expenditure share") +
  base_theme +
  theme(legend.position = "none")
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_pooled_combined.png"),
       p_combined, width = 9, height = 9, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_pooled_combined.pdf"),
       p_combined, width = 9, height = 9)

# 9a-(1). Combined 3-panel: MEAN of RAW share (bounded [0,1])
pooled_raw_lab <- copy(pooled_raw)
pooled_raw_lab[, version_lab := factor(version,
                                       levels = names(version_labels),
                                       labels = version_labels)]
p_combined_raw <- ggplot(pooled_raw_lab, aes(x = year, y = mean_raw_share)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.20, fill = "steelblue") +
  geom_line(color = "steelblue", linewidth = 0.9) +
  geom_point(color = "steelblue", size = 1.1) +
  geom_vline(data = treat_lines,
             aes(xintercept = norm_year + 0.5),
             linetype = "dashed", color = "grey30") +
  geom_vline(data = treat_lines,
             aes(xintercept = treat_year - 0.5),
             linetype = "dashed", color = "firebrick") +
  facet_wrap(~ version_lab, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format(accuracy = 1)) +
  labs(title = "Within-NACE4d expenditure share on the top-omega supplier (RAW level)",
       subtitle = "Unweighted mean of raw share across buyer-NACE4d cells; 95% bootstrap CI; red = treatment year.",
       x = NULL,
       y = "Share of buyer's NACE4d spend on top-omega supplier") +
  base_theme +
  theme(legend.position = "none")
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_pooled_combined_raw.png"),
       p_combined_raw, width = 9, height = 9, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_pooled_combined_raw.pdf"),
       p_combined_raw, width = 9, height = 9)


# 9b. By-NACE4d facet grid (one figure per version)
plot_by_nace4d <- function(label) {
  d <- by_nace_plot[version == label]
  if (nrow(d) == 0) {
    cat(sprintf("  No NACE4d sectors meet the >=%d cell threshold for %s; skipping.\n",
                MIN_CELLS_PER_NACE4D, label))
    return(invisible(NULL))
  }
  spec <- INTERVALS[[label]]
  ggplot(d, aes(x = year, y = mean_share)) +
    geom_line(color = "steelblue", linewidth = 0.7) +
    geom_point(color = "steelblue", size = 0.9) +
    geom_hline(yintercept = 1, linetype = "dotted", color = "grey30") +
    geom_vline(xintercept = spec$norm_year + 0.5, linetype = "dashed",
               color = "grey30") +
    geom_vline(xintercept = spec$treat_year - 0.5, linetype = "dashed",
               color = "firebrick") +
    facet_wrap(~ seller_nace4d, scales = "free_y") +
    scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 4)) +
    labs(title = sprintf("Within-NACE4d expenditure share on top-omega supplier -- %s",
                         version_labels[label]),
         subtitle = sprintf("One panel per NACE4d (>=%d cells). Mean across buyer-NACE4d cells. Red = treatment year.",
                            MIN_CELLS_PER_NACE4D),
         x = NULL,
         y = "Normalized expenditure share") +
    base_theme +
    theme(axis.text.x = element_text(size = 7),
          axis.text.y = element_text(size = 7),
          strip.text = element_text(size = 8))
}

for (label in names(INTERVALS)) {
  p <- plot_by_nace4d(label)
  if (is.null(p)) next
  n_facets <- nace_keep[version == label, .N]
  width  <- max(8, 1.6 * ceiling(sqrt(n_facets)))
  height <- max(6, 1.4 * ceiling(n_facets / ceiling(sqrt(n_facets))))
  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_within_nace4d_reallocation_by_nace4d_%s.png",
                           sub("treat_", "", label))),
         p, width = width, height = height, dpi = 180, limitsize = FALSE)
  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_within_nace4d_reallocation_by_nace4d_%s.pdf",
                           sub("treat_", "", label))),
         p, width = width, height = height, limitsize = FALSE)
}

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
