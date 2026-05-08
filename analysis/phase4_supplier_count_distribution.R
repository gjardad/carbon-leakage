###############################################################################
# phase4_supplier_count_distribution.R
#
# PURPOSE
#   For the same B2B sample used in
#   `phase4_within_nace4d_reallocation_plots.R` -- buyer-supplier pairs whose
#   supplier sits in an ETS-treated NACE4d -- describe the distribution of
#   the number of distinct suppliers a given buyer transacts with within
#   each NACE4d sector.
#
#   Two views:
#     1. By interval (2006-07, 2011-12, 2015-16): for each
#        (buyer, supplier-NACE4d) cell, count the number of distinct suppliers
#        the buyer transacted with during the 2-year interval.
#     2. By calendar year (2005-2022): same count, but year by year.
#
#   This characterizes how often "within-NACE4d reallocation" is even
#   mechanically possible (n_suppliers >= 2 cells), and how concentration
#   varies across NACE4d sectors.
#
# OUTPUTS (output_local/tables/, output_local/figures/)
#   - phase4_supplier_count_by_interval.csv         (cell-level: 1 row per
#                                                     buyer x NACE4d x interval)
#   - phase4_supplier_count_by_year.csv             (cell-level: 1 row per
#                                                     buyer x NACE4d x year)
#   - phase4_supplier_count_summary_by_interval.csv (interval x summary stats)
#   - phase4_supplier_count_summary_by_year.csv     (year x summary stats)
#   - phase4_supplier_count_summary_by_nace4d_interval.csv
#         (NACE4d x interval -- which sectors are concentrated)
#   - phase4_supplier_count_hist_by_interval.{png,pdf}
#   - phase4_supplier_count_share_multi_by_year.{png,pdf}
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

YEAR_LO <- 2005L
YEAR_HI <- 2022L

INTERVALS <- list(
  "interval_2006_07" = c(2006L, 2007L),
  "interval_2011_12" = c(2011L, 2012L),
  "interval_2015_16" = c(2015L, 2016L)
)

# ---------------------------------------------------------------------------
# 1. Load data and restrict to ETS-treated NACE4d sellers
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
cat(sprintf("  b2b rows: %d\n", nrow(b2b)))

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = vat_ano,
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
ets_treated_nace4d <- unique(as.data.table(firm_exposure)$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]
rm(firm_exposure)
cat(sprintf("  ETS-treated NACE4d: %d\n", length(ets_treated_nace4d)))

seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d %in% ets_treated_nace4d]
cat(sprintf("  rows after ETS-treated NACE4d filter: %d\n", nrow(b2b)))

# ---------------------------------------------------------------------------
# Helper: summary stats from a vector of supplier counts
# ---------------------------------------------------------------------------
summarize_counts <- function(x) {
  x <- as.numeric(x)
  data.table(
    n_cells       = length(x),
    mean_n_supp   = as.numeric(mean(x)),
    p10_n_supp    = as.numeric(quantile(x, 0.10, names = FALSE)),
    p25_n_supp    = as.numeric(quantile(x, 0.25, names = FALSE)),
    median_n_supp = as.numeric(median(x)),
    p75_n_supp    = as.numeric(quantile(x, 0.75, names = FALSE)),
    p90_n_supp    = as.numeric(quantile(x, 0.90, names = FALSE)),
    p99_n_supp    = as.numeric(quantile(x, 0.99, names = FALSE)),
    max_n_supp    = as.numeric(max(x)),
    share_eq_1    = mean(x == 1),
    share_eq_2    = mean(x == 2),
    share_3_to_5  = mean(x >= 3 & x <= 5),
    share_6_to_10 = mean(x >= 6 & x <= 10),
    share_ge_11   = mean(x >= 11),
    share_ge_2    = mean(x >= 2)
  )
}

# ---------------------------------------------------------------------------
# 2. By-interval supplier-count distribution
# ---------------------------------------------------------------------------
cat("\n=== By interval ===\n")

interval_cells_list <- list()
for (k in names(INTERVALS)) {
  yrs <- INTERVALS[[k]]
  d <- b2b[year %in% yrs,
           .(n_suppliers = uniqueN(seller),
             total_sales_in_interval = sum(sales)),
           by = .(buyer, seller_nace4d)]
  d[, interval := k]
  interval_cells_list[[k]] <- d
}
cells_interval <- rbindlist(interval_cells_list, use.names = TRUE)
fwrite(cells_interval,
       file.path(OUTPUT_TAB, "phase4_supplier_count_by_interval.csv"))

summary_interval <- cells_interval[, summarize_counts(n_suppliers), by = interval]
print(summary_interval)
fwrite(summary_interval,
       file.path(OUTPUT_TAB, "phase4_supplier_count_summary_by_interval.csv"))

# ---------------------------------------------------------------------------
# 3. By-year supplier-count distribution
# ---------------------------------------------------------------------------
cat("\n=== By year ===\n")

cells_year <- b2b[, .(n_suppliers = uniqueN(seller),
                      total_sales_in_year = sum(sales)),
                  by = .(buyer, seller_nace4d, year)]
fwrite(cells_year,
       file.path(OUTPUT_TAB, "phase4_supplier_count_by_year.csv"))

summary_year <- cells_year[, summarize_counts(n_suppliers), by = year]
setorder(summary_year, year)
print(summary_year[, .(year, n_cells, mean_n_supp = round(mean_n_supp, 2),
                       median_n_supp,
                       share_eq_1 = round(share_eq_1, 3),
                       share_ge_2 = round(share_ge_2, 3),
                       share_ge_11 = round(share_ge_11, 3))])
fwrite(summary_year,
       file.path(OUTPUT_TAB, "phase4_supplier_count_summary_by_year.csv"))

# ---------------------------------------------------------------------------
# 4. By NACE4d x interval (which sectors have many suppliers per buyer)
# ---------------------------------------------------------------------------
cat("\n=== By NACE4d x interval ===\n")

summary_nace_interval <- cells_interval[, summarize_counts(n_suppliers),
                                        by = .(interval, seller_nace4d)]
setorder(summary_nace_interval, interval, -n_cells)
fwrite(summary_nace_interval,
       file.path(OUTPUT_TAB,
                 "phase4_supplier_count_summary_by_nace4d_interval.csv"))

cat("Top 10 NACE4d sectors by # buyer-cells (interval 2015-16):\n")
print(summary_nace_interval[interval == "interval_2015_16",
                            .(seller_nace4d, n_cells,
                              mean_n_supp = round(mean_n_supp, 2),
                              median_n_supp,
                              share_ge_2 = round(share_ge_2, 3),
                              max_n_supp)][1:10])

# ---------------------------------------------------------------------------
# 5. Plots
# ---------------------------------------------------------------------------
base_theme <- theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"),
        panel.grid.minor = element_blank())

# 5a. Histogram of supplier counts by interval (bin top values)
plot_dt <- copy(cells_interval)
plot_dt[, n_supp_bin := pmin(n_suppliers, 11L)]
bin_labels <- c(as.character(1:10), "11+")
plot_dt[, n_supp_bin := factor(n_supp_bin, levels = 1:11, labels = bin_labels)]

interval_labels <- c(
  "interval_2006_07" = "2006-07",
  "interval_2011_12" = "2011-12",
  "interval_2015_16" = "2015-16"
)
plot_dt[, interval_lab := factor(interval,
                                 levels = names(interval_labels),
                                 labels = interval_labels)]

p_hist <- ggplot(plot_dt, aes(x = n_supp_bin)) +
  geom_bar(aes(y = after_stat(prop), group = 1), fill = "steelblue",
           color = "white") +
  facet_wrap(~ interval_lab, ncol = 3) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(title = "Distribution of #suppliers per buyer x ETS-treated NACE4d, by interval",
       subtitle = "Each cell = (buyer, supplier-NACE4d). Bars sum to 100% within each panel.",
       x = "Number of distinct suppliers (capped at 11+)",
       y = "Share of cells") +
  base_theme

ggsave(file.path(OUTPUT_FIG, "phase4_supplier_count_hist_by_interval.png"),
       p_hist, width = 10, height = 4, dpi = 200)
ggsave(file.path(OUTPUT_FIG, "phase4_supplier_count_hist_by_interval.pdf"),
       p_hist, width = 10, height = 4)

# 5b. Share of cells with >=2 suppliers, by year
share_multi <- summary_year[, .(year, share_ge_2)]
p_share <- ggplot(share_multi, aes(x = year, y = share_ge_2)) +
  geom_line(color = "steelblue", linewidth = 0.9) +
  geom_point(color = "steelblue", size = 1.4) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                     limits = c(0, NA)) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  labs(title = "Share of buyer x ETS-treated-NACE4d cells with >=2 suppliers in year",
       subtitle = "Single-supplier cells contribute zero to within-NACE4d reallocation by construction.",
       x = NULL,
       y = "Share of cells with >=2 suppliers") +
  base_theme

ggsave(file.path(OUTPUT_FIG, "phase4_supplier_count_share_multi_by_year.png"),
       p_share, width = 8, height = 4.5, dpi = 200)
ggsave(file.path(OUTPUT_FIG, "phase4_supplier_count_share_multi_by_year.pdf"),
       p_share, width = 8, height = 4.5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
