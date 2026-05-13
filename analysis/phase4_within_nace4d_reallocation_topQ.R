###############################################################################
# phase4_within_nace4d_reallocation_topQ.R
#
# PURPOSE
#   Heterogeneity addendum to phase4_within_nace4d_reallocation_plots.R.
#   For each (buyer, NACE4d, treatment-period) cell -- already identified
#   in the main script -- compute the interval-period cost shock the cell's
#   top-omega supplier imposes on the buyer:
#
#       shock_cell = omega_{i, interval} * x_{ij, interval}
#
#   where omega_{i, interval} is the interval ratio-of-averages we already
#   used to identify the top supplier, and
#       x_{ij, interval} = sum_t in interval [spend(j, i, t)]
#                        / sum_t in interval [total_cost(j, t)]
#   with total_cost = (revenue - value_added) + wage_bill from the AA panel.
#
#   Within each treatment period, identify the top-quartile cells by
#   shock_cell. Plot the raw within-NACE4d expenditure share evolution
#   (mean across cells, 95% bootstrap CI) for top-Q vs all-cells, for both
#   the top-omega and the bottom-omega supplier in each cell.
#
# OUTPUTS (output_local/figures/, output_local/tables/)
#   - phase4_within_nace4d_reallocation_topQ_buyertotal.{png,pdf}
#         Top quartile only (2 lines: top-omega + bottom-omega supplier)
#   - phase4_within_nace4d_reallocation_allcells_buyertotal.{png,pdf}
#         All cells (2 lines: top-omega + bottom-omega supplier)
#   - phase4_within_nace4d_reallocation_topQ_cell_shocks.csv
#   - phase4_within_nace4d_reallocation_topQ_pooled_buyertotal.csv
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

YEAR_LO <- 2002L  # B2B panel starts in 2002
YEAR_HI <- 2022L
N_BOOT  <- 1000L

INTERVALS <- list(
  "treat_2005" = list(years = c(2005L),         norm_year = 2004L, treat_year = 2005L),
  "treat_2017" = list(years = c(2015L, 2016L),  norm_year = 2016L, treat_year = 2017L)
)

# ---------------------------------------------------------------------------
# 1. Load the cell panel produced by the main script
# ---------------------------------------------------------------------------
cat("Loading cell panel + b2b + AA...\n")

panel_path <- file.path(OUTPUT_TAB,
                        "phase4_within_nace4d_reallocation_panel.csv")
if (!file.exists(panel_path))
  stop("Run phase4_within_nace4d_reallocation_plots.R first to produce ",
       panel_path)

panel <- fread(panel_path,
               colClasses = list(character = c("seller_nace4d", "version",
                                               "buyer", "top_supplier",
                                               "bottom_supplier")))
cat(sprintf("  panel rows: %d, cells: %d\n", nrow(panel),
            uniqueN(panel[, .(version, buyer, seller_nace4d)])))

# B2B (raw spend by year) for numerators
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
             year, sales)]

# AA key vars: buyer total cost
load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample_key_variables)[, .(
  vat = as.character(vat),
  year = as.integer(year),
  revenue,
  value_added,
  wage_bill
)]
rm(df_annual_accounts_selected_sample_key_variables)
aa[, total_cost := (revenue - value_added) + wage_bill]
buyer_tc <- aa[!is.na(total_cost) & total_cost > 0,
               .(buyer = vat, year, buyer_total_cost = total_cost)]

# ---------------------------------------------------------------------------
# 2. Compute interval-aggregated x_ij and cell-level shocks
# ---------------------------------------------------------------------------
cat("\nComputing interval-aggregated x_ij and cell shocks...\n")

cells <- unique(panel[, .(version, buyer, seller_nace4d, top_supplier, omega)])

shock_list <- list()
for (label in names(INTERVALS)) {
  yrs <- INTERVALS[[label]]$years

  ce <- cells[version == label]
  if (nrow(ce) == 0) next

  # Numerator: sum_t spend(j, top_supplier, t) over interval
  num <- b2b[year %in% yrs,
             .(seller, buyer, year, sales)]
  setnames(num, "seller", "top_supplier")
  num <- num[, .(num_spend = sum(sales)),
             by = .(buyer, top_supplier)]
  ce <- merge(ce, num, by = c("buyer", "top_supplier"), all.x = TRUE)
  ce[is.na(num_spend), num_spend := 0]

  # Buyer-total-cost denominator over interval
  bt <- buyer_tc[year %in% yrs,
                 .(sum_buyer_tc = sum(buyer_total_cost),
                   n_yr_tc      = .N),
                 by = buyer]
  ce <- merge(ce, bt, by = "buyer", all.x = TRUE)
  ce[, x_buyertotal := ifelse(!is.na(sum_buyer_tc) & sum_buyer_tc > 0,
                              num_spend / sum_buyer_tc, NA_real_)]

  ce[, shock_buyertotal := omega * x_buyertotal]

  shock_list[[label]] <- ce
}

cell_shocks <- rbindlist(shock_list, use.names = TRUE, fill = TRUE)
fwrite(cell_shocks,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_reallocation_topQ_cell_shocks.csv"))

# ---------------------------------------------------------------------------
# 3. Top-quartile flag per version
# ---------------------------------------------------------------------------
flag_topQ <- function(dt, shock_col, flag_col) {
  dt[, (flag_col) := NA]
  for (v in unique(dt$version)) {
    idx <- which(dt$version == v & !is.na(dt[[shock_col]]))
    if (length(idx) == 0) next
    cutoff <- quantile(dt[[shock_col]][idx], 0.75, names = FALSE)
    dt[idx, (flag_col) := dt[[shock_col]][idx] >= cutoff]
  }
  invisible(dt)
}
flag_topQ(cell_shocks, "shock_buyertotal", "topQ_buyertotal")

cat("\nTop-quartile cell counts per version:\n")
print(cell_shocks[, .(
  n_total           = .N,
  n_with_shock     = sum(!is.na(shock_buyertotal)),
  n_topQ_buyertotal = sum(topQ_buyertotal, na.rm = TRUE)
), by = version])

# ---------------------------------------------------------------------------
# 4. Aggregate raw share over years for top-omega and bottom-omega supplier,
#    all-cells and top-Q.
# ---------------------------------------------------------------------------
boot_ci <- function(x, stat = mean, n_boot = N_BOOT, alpha = 0.05) {
  x <- x[!is.na(x)]
  if (length(x) < 5L) return(list(lo = NA_real_, hi = NA_real_))
  m <- length(x)
  draws <- replicate(n_boot, stat(x[sample.int(m, m, replace = TRUE)]))
  q <- quantile(draws, c(alpha / 2, 1 - alpha / 2), names = FALSE)
  list(lo = q[1], hi = q[2])
}

# Attach the topQ flag to the year-level panel
panel_a <- merge(panel,
                 cell_shocks[!is.na(shock_buyertotal),
                             .(version, buyer, seller_nace4d,
                               topQ_buyertotal)],
                 by = c("version", "buyer", "seller_nace4d"),
                 all.x = FALSE)

# Long-format: one row per cell-year-supplier_role (top vs bottom)
panel_long <- rbind(
  panel_a[!is.na(share),
          .(version, treat_year, norm_year, year, buyer, seller_nace4d,
            topQ = topQ_buyertotal,
            supplier_role = "Top-omega supplier",
            cell_share = share)],
  panel_a[!is.na(bottom_share),
          .(version, treat_year, norm_year, year, buyer, seller_nace4d,
            topQ = topQ_buyertotal,
            supplier_role = "Bottom-omega supplier",
            cell_share = bottom_share)]
)

agg_supplier <- function(d) {
  d[, group := ifelse(topQ, "Top quartile", "Other (Q1-Q3)")]
  all_d <- copy(d)[, group := "All cells"]
  rbind(all_d, d)[,
    {
      ci <- boot_ci(cell_share, stat = mean)
      .(mean_share = mean(cell_share),
        n_cells   = .N,
        ci_lo     = ci$lo,
        ci_hi     = ci$hi)
    },
    by = .(version, treat_year, norm_year, year, supplier_role, group)
  ]
}

pooled_a <- agg_supplier(panel_long)
setorder(pooled_a, version, supplier_role, group, year)
fwrite(pooled_a,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_reallocation_topQ_pooled_buyertotal.csv"))

# ---------------------------------------------------------------------------
# 5. Plot
# ---------------------------------------------------------------------------
version_labels <- c(
  "treat_2005" = "EU ETS start, 2005 (omega from 2005)",
  "treat_2017" = "MSR, 2017 (omega from 2015-16)"
)

base_theme <- theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"),
        panel.grid.minor = element_blank(),
        legend.position = "bottom",
        legend.box = "vertical")

treat_lines <- data.table(
  version_lab = factor(version_labels, levels = version_labels),
  treat_year = sapply(INTERVALS, `[[`, "treat_year"),
  norm_year  = sapply(INTERVALS, `[[`, "norm_year")
)

# 2 separate plots:
#   topQ plot     -- top-omega + bottom-omega, top quartile only
#   allcells plot -- top-omega + bottom-omega, all cells

make_two_line_plot <- function(d, group_keep, title, subtitle) {
  d2 <- copy(d)[group == group_keep]
  d2[, version_lab := factor(version, levels = names(version_labels),
                             labels = version_labels)]
  d2[, supplier_role := factor(supplier_role,
                               levels = c("Top-omega supplier",
                                          "Bottom-omega supplier"))]
  ggplot(d2, aes(x = year, y = mean_share,
                 color = supplier_role, fill = supplier_role)) +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.18, color = NA) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 1.1) +
    geom_vline(data = treat_lines,
               aes(xintercept = norm_year + 0.5),
               linetype = "dashed", color = "grey30",
               inherit.aes = FALSE) +
    geom_vline(data = treat_lines,
               aes(xintercept = treat_year - 0.5),
               linetype = "dashed", color = "firebrick",
               inherit.aes = FALSE) +
    facet_wrap(~ version_lab, ncol = 1, scales = "free_y") +
    scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
    scale_y_continuous(limits = c(0, 1),
                       labels = scales::percent_format(accuracy = 1)) +
    scale_color_manual(values = c("Top-omega supplier" = "firebrick",
                                  "Bottom-omega supplier" = "navy"),
                       name = NULL) +
    scale_fill_manual(values = c("Top-omega supplier" = "firebrick",
                                 "Bottom-omega supplier" = "navy"),
                      name = NULL) +
    labs(title = title, subtitle = subtitle,
         x = NULL,
         y = "Share of buyer's NACE4d spend") +
    base_theme
}

p_topQ <- make_two_line_plot(
  pooled_a, "Top quartile",
  "Top-quartile cells by supplier cost shock (top-omega + bottom-omega supplier)",
  "Cost shock = omega_i,interval x spend(j,i,interval) / buyer-j total cost(interval).\nMean of raw within-NACE4d expenditure share across top-quartile cells; 95% bootstrap CI."
)
p_all <- make_two_line_plot(
  pooled_a, "All cells",
  "All cells (top-omega + bottom-omega supplier)",
  "Mean of raw within-NACE4d expenditure share across all multi-supplier cells; 95% bootstrap CI."
)

ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_topQ_buyertotal.png"),
       p_topQ, width = 9, height = 10, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_topQ_buyertotal.pdf"),
       p_topQ, width = 9, height = 10)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_allcells_buyertotal.png"),
       p_all, width = 9, height = 10, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_allcells_buyertotal.pdf"),
       p_all, width = 9, height = 10)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
