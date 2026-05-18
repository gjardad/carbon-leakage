###############################################################################
# phase4_within_intensive_pretrend_diagnostic.R
#
# PURPOSE
#   Diagnose the post-2014 widening between the top-omega and bottom-omega
#   trajectories in the 2017-treatment panel of the within-NACE4d intensive
#   margin. Four diagnostics, all reusing the cell-building logic of
#   phase4_within_intensive_figures.R:
#
#     (a) n_cells per year by role -- composition check. Plots how many
#         (buyer, NACE4d) cells contribute to the mean each year for top
#         and bot, decomposed into:
#           - n_with_observed_share   (denominator buyer-NACE4d > 0)
#           - n_with_positive_share   (seller sold to buyer that year)
#     (b) Always-active subsample -- restrict to cells where both the top
#         and the bot supplier have positive sales in EVERY year 2005-2022,
#         and a softer cut requiring positive sales in 2010 only. Re-plot.
#     (c) Outlier trim -- drop the top 1% and top 5% of cells by absolute
#         (top - bot) share change 2014 -> 2017. Re-plot.
#     (d) Earlier anchor window -- redefine the 2017 cells using 2005-2007
#         sourcing patterns (instead of 2015-2016), recompute omega over
#         2005-2007 and refollow top/bot suppliers forward. Eliminates the
#         2015-16 anchor selection that mechanically pins the top supplier's
#         share to its 2015-16 level.
#
# All outputs go to OUTPUT_FIG / OUTPUT_TAB with a `_pretrend_` infix and
# are CSV-backed so the diagnostic numbers are auditable.
#
# DEPENDENCIES
#   - b2b_selected_sample.RData
#   - annual_accounts_selected_sample.RData
#   - annual_accounts_selected_sample_key_variables.RData
#   - phase3_firm_exposure.RData
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

set.seed(20260518)

YEAR_LO <- 2002L
YEAR_HI <- 2022L

INTERVALS <- list(
  "treat_2005"        = list(years = c(2005L),                 treat_year = 2005L),
  "treat_2017"        = list(years = c(2015L, 2016L),          treat_year = 2017L),
  "treat_2017_anchor2005" = list(years = c(2005L, 2006L, 2007L), treat_year = 2017L)
)

# ---------------------------------------------------------------------------
# 1. Load data (same as the main figure script)
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
  vat   = as.character(vat_ano),
  year  = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))
aa_kv <- as.data.table(df_annual_accounts_selected_sample_key_variables)[, .(
  vat = as.character(vat),
  year = as.integer(year),
  revenue, value_added, wage_bill
)]
rm(df_annual_accounts_selected_sample_key_variables)
aa_kv[, total_cost := (revenue - value_added) + wage_bill]
buyer_tc <- aa_kv[!is.na(total_cost) & total_cost > 0,
                  .(buyer = vat, year, buyer_total_cost = total_cost)]

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(vat = as.character(vat),
                                       year, shortage, total_cost)]
rm(firm_exposure)
fe[, omega_sh := ifelse(!is.na(total_cost) & total_cost > 0,
                        pmax(shortage, 0) / total_cost, NA_real_)]

b2b <- merge(b2b, aa, by.x = c("seller", "year"), by.y = c("vat", "year"),
             all.x = TRUE)
setnames(b2b, "nace4d", "seller_nace4d")
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d != ""]
b2b[, total_buyer_nace4d_spend := sum(sales),
    by = .(buyer, seller_nace4d, year)]

# ---------------------------------------------------------------------------
# 2. Cell-building (shortage-based omega only -- the headline definition)
# ---------------------------------------------------------------------------
build_cells_interval <- function(version_label, years, treat_year) {
  seller_int <- b2b[year %in% years,
                    .(int_sales = sum(sales)),
                    by = .(buyer, seller_nace4d, seller)]
  fe_int <- fe[year %in% years,
               .(int_omega = mean(omega_sh, na.rm = TRUE)),
               by = .(vat)]
  seller_int <- merge(seller_int, fe_int,
                      by.x = "seller", by.y = "vat", all.x = TRUE)
  seller_int[is.na(int_omega), int_omega := 0]

  setorder(seller_int, buyer, seller_nace4d, -int_omega, -int_sales, seller)
  seller_int[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
  cell_summary <- seller_int[, .(n_suppliers = .N,
                                 max_omega   = max(int_omega, na.rm = TRUE)),
                             by = .(buyer, seller_nace4d)]
  cell_summary <- cell_summary[n_suppliers >= 2L & max_omega > 0]

  cells <- merge(seller_int, cell_summary[, .(buyer, seller_nace4d)],
                 by = c("buyer", "seller_nace4d"))
  top_sup <- cells[rk == 1, .(buyer, seller_nace4d,
                              top_supplier = seller,
                              omega_top = int_omega,
                              top_sales = int_sales)]
  bot_sup <- cells[, .SD[.N], by = .(buyer, seller_nace4d)][,
                  .(buyer, seller_nace4d,
                    bot_supplier = seller,
                    omega_bot = int_omega,
                    bot_sales = int_sales)]
  cells_top_bot <- merge(top_sup, bot_sup, by = c("buyer", "seller_nace4d"))
  cells_top_bot[, version := version_label]
  cells_top_bot[, treat_year := treat_year]
  cells_top_bot[]
}

cells_all <- rbindlist(lapply(names(INTERVALS), function(lab) {
  iv <- INTERVALS[[lab]]
  build_cells_interval(lab, iv$years, iv$treat_year)
}), use.names = TRUE, fill = TRUE)

cat("Cells per version:\n")
print(cells_all[, .N, by = version])

# ---------------------------------------------------------------------------
# 3. Long panel: one row per (buyer, NACE4d, role, year) for each version
# ---------------------------------------------------------------------------
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

build_long <- function(cells_dt) {
  long <- rbind(
    cells_dt[, .(buyer, seller_nace4d, version, treat_year,
                 seller = top_supplier, supplier_role = "top")],
    cells_dt[, .(buyer, seller_nace4d, version, treat_year,
                 seller = bot_supplier, supplier_role = "bot")]
  )
  panel <- long[, .(year = YEAR_LO:YEAR_HI),
                by = .(buyer, seller_nace4d, version, treat_year,
                       seller, supplier_role)]
  panel <- merge(panel, yr_denom,
                 by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
  panel <- merge(panel, yr_sales,
                 by = c("buyer", "seller_nace4d", "seller", "year"),
                 all.x = TRUE)
  panel[is.na(sales), sales := 0]
  panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                            total_buyer_nace4d_spend <= 0,
                          NA_real_, sales / total_buyer_nace4d_spend)]
  panel[]
}

panel_all <- build_long(cells_all)

# ---------------------------------------------------------------------------
# 4. Helper: trajectory plot from a panel subset
# ---------------------------------------------------------------------------
traj_from_panel <- function(p, label) {
  t <- p[!is.na(share),
         .(mean_share = mean(share),
           se_share   = sd(share) / sqrt(.N),
           n_cells    = .N),
         by = .(version, year, supplier_role)]
  t[, lo := mean_share - 1.96 * se_share]
  t[, hi := mean_share + 1.96 * se_share]
  t[, role_label := fcase(
    supplier_role == "top", "Most exposed supplier",
    supplier_role == "bot", "Least exposed supplier"
  )]
  t[, role_label := factor(role_label,
                           levels = c("Most exposed supplier",
                                      "Least exposed supplier"))]
  t[, version_label := fcase(
    version == "treat_2005",            "2005 Treatment",
    version == "treat_2017",            "2017 Treatment",
    version == "treat_2017_anchor2005", "2017 Treatment (cells anchored on 2005-07)"
  )]
  t[, diagnostic := label]
  t[]
}

plot_traj <- function(t, file_base, treat_lines) {
  g <- ggplot(t, aes(x = year, y = mean_share,
                     color = role_label, fill = role_label)) +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, color = NA) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 1.4) +
    geom_vline(data = treat_lines,
               aes(xintercept = treat_year - 0.5),
               linetype = "dashed", color = "firebrick", inherit.aes = FALSE) +
    facet_wrap(~ version_label, ncol = 1, scales = "free_y") +
    scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
    scale_color_manual(values = c("Most exposed supplier"  = "firebrick",
                                   "Least exposed supplier" = "navy"),
                       name = NULL) +
    scale_fill_manual(values = c("Most exposed supplier"  = "firebrick",
                                  "Least exposed supplier" = "navy"),
                      name = NULL) +
    labs(x = NULL, y = "Mean within-cell expenditure share") +
    theme_classic(base_size = 15) +
    theme(panel.grid       = element_blank(),
          axis.title.y     = element_text(size = 22, margin = margin(r = 18)),
          axis.text        = element_text(size = 18),
          strip.text       = element_text(face = "bold", size = 16),
          legend.position  = "bottom",
          legend.text      = element_text(size = 18))
  n_panels <- length(unique(t$version_label))
  ggsave(file.path(OUTPUT_FIG, paste0(file_base, ".png")), g,
         width = 9, height = 4 * n_panels, dpi = 200)
  ggsave(file.path(OUTPUT_FIG, paste0(file_base, ".pdf")), g,
         width = 9, height = 4 * n_panels)
}

# ---------------------------------------------------------------------------
# (a) n_cells per year by role -- composition check
# ---------------------------------------------------------------------------
cat("\n[a] Composition check: n_cells per year by role...\n")
comp <- panel_all[, .(
  n_total            = .N,
  n_with_observed    = sum(!is.na(share)),
  n_with_positive    = sum(!is.na(share) & share > 0)
), by = .(version, year, supplier_role)]
fwrite(comp, file.path(OUTPUT_TAB,
       "phase4_within_intensive_pretrend_composition.csv"))

comp_long <- melt(comp,
                  id.vars = c("version", "year", "supplier_role"),
                  measure.vars = c("n_with_observed", "n_with_positive"),
                  variable.name = "metric", value.name = "n_cells")
comp_long[, role_label := fcase(
  supplier_role == "top", "Most exposed supplier",
  supplier_role == "bot", "Least exposed supplier"
)]
comp_long[, version_label := fcase(
  version == "treat_2005",            "2005 Treatment",
  version == "treat_2017",            "2017 Treatment",
  version == "treat_2017_anchor2005", "2017 Treatment (anchor 2005-07)"
)]
comp_long[, metric_label := fcase(
  metric == "n_with_observed", "Cells with NACE-4d sourcing (denominator > 0)",
  metric == "n_with_positive", "Cells with positive sales from this seller"
)]

g_comp <- ggplot(comp_long,
                 aes(x = year, y = n_cells,
                     color = role_label, linetype = metric_label)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.2) +
  facet_wrap(~ version_label, ncol = 1, scales = "free_y") +
  scale_color_manual(values = c("Most exposed supplier"  = "firebrick",
                                 "Least exposed supplier" = "navy"),
                     name = NULL) +
  scale_linetype_manual(values = c("Cells with NACE-4d sourcing (denominator > 0)" = "solid",
                                    "Cells with positive sales from this seller"   = "dashed"),
                        name = NULL) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  labs(x = NULL, y = "Number of cells") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 22, margin = margin(r = 18)),
        axis.text        = element_text(size = 18),
        strip.text       = element_text(face = "bold", size = 16),
        legend.position  = "bottom",
        legend.text      = element_text(size = 13),
        legend.box       = "vertical")

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_pretrend_a_composition.png"),
       g_comp, width = 10, height = 10, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_pretrend_a_composition.pdf"),
       g_comp, width = 10, height = 10)

# ---------------------------------------------------------------------------
# (b) Always-active subsample
#     Two flavors:
#       b1: both top and bot have positive sales in EVERY year 2005-2022
#       b2: both top and bot have positive sales in 2010
# ---------------------------------------------------------------------------
cat("\n[b] Always-active subsample...\n")
# Reshape to (cell, year, role) with positive-sales indicator
has_sales <- panel_all[, .(buyer, seller_nace4d, version, supplier_role, year,
                            has_pos = !is.na(share) & share > 0)]

# Flag: for each cell, do top AND bot both have positive sales in every year 2005-2022?
b1_flag <- has_sales[year %between% c(2005L, 2022L),
                     .(all_pos = all(has_pos)),
                     by = .(buyer, seller_nace4d, version, supplier_role)]
b1_wide <- dcast(b1_flag, buyer + seller_nace4d + version ~ supplier_role,
                 value.var = "all_pos")
b1_keep <- b1_wide[top == TRUE & bot == TRUE,
                   .(buyer, seller_nace4d, version, keep_b1 = TRUE)]

# Flag: both top and bot positive in 2010
b2_flag <- has_sales[year == 2010L,
                     .(pos_2010 = any(has_pos)),
                     by = .(buyer, seller_nace4d, version, supplier_role)]
b2_wide <- dcast(b2_flag, buyer + seller_nace4d + version ~ supplier_role,
                 value.var = "pos_2010")
b2_keep <- b2_wide[top == TRUE & bot == TRUE,
                   .(buyer, seller_nace4d, version, keep_b2 = TRUE)]

cat("  always-active 2005-2022 cells:\n")
print(b1_keep[, .N, by = version])
cat("  positive-in-2010 cells:\n")
print(b2_keep[, .N, by = version])

panel_b1 <- merge(panel_all, b1_keep,
                  by = c("buyer", "seller_nace4d", "version"))
panel_b2 <- merge(panel_all, b2_keep,
                  by = c("buyer", "seller_nace4d", "version"))

t_b1 <- traj_from_panel(panel_b1, "b1_always_active")
t_b2 <- traj_from_panel(panel_b2, "b2_active_in_2010")
fwrite(t_b1, file.path(OUTPUT_TAB,
       "phase4_within_intensive_pretrend_b1_always_active.csv"))
fwrite(t_b2, file.path(OUTPUT_TAB,
       "phase4_within_intensive_pretrend_b2_active_in_2010.csv"))

treat_lines_all <- data.table(
  version_label = c("2005 Treatment",
                    "2017 Treatment",
                    "2017 Treatment (cells anchored on 2005-07)"),
  treat_year    = c(2005, 2017, 2017)
)

plot_traj(t_b1, "phase4_within_intensive_pretrend_b1_always_active",
          treat_lines_all)
plot_traj(t_b2, "phase4_within_intensive_pretrend_b2_active_in_2010",
          treat_lines_all)

# ---------------------------------------------------------------------------
# (c) Outlier trim: drop top 1% and 5% by |top - bot| share change 2014->2017
# ---------------------------------------------------------------------------
cat("\n[c] Outlier trim...\n")
# Cell-level (top - bot) share at 2014 and 2017
share_1417 <- panel_all[year %in% c(2014L, 2017L),
                         .(buyer, seller_nace4d, version, supplier_role,
                           year, share)]
share_1417_w <- dcast(share_1417,
                      buyer + seller_nace4d + version + year ~ supplier_role,
                      value.var = "share")
share_1417_w[, top_bot := top - bot]
delta <- dcast(share_1417_w,
               buyer + seller_nace4d + version ~ year,
               value.var = "top_bot")
setnames(delta, c("2014", "2017"), c("gap_2014", "gap_2017"))
delta[, d_gap := gap_2017 - gap_2014]
delta_valid <- delta[!is.na(d_gap)]

trim_at <- function(p_keep) {
  out <- delta_valid[, {
    thr <- quantile(abs(d_gap), p_keep, na.rm = TRUE)
    .SD[abs(d_gap) <= thr, .(buyer, seller_nace4d)]
  }, by = version]
  out
}
keep_99 <- trim_at(0.99)
keep_95 <- trim_at(0.95)

panel_c99 <- merge(panel_all, keep_99,
                   by = c("buyer", "seller_nace4d", "version"))
panel_c95 <- merge(panel_all, keep_95,
                   by = c("buyer", "seller_nace4d", "version"))

t_c99 <- traj_from_panel(panel_c99, "c_trim_top1pct")
t_c95 <- traj_from_panel(panel_c95, "c_trim_top5pct")
fwrite(t_c99, file.path(OUTPUT_TAB,
       "phase4_within_intensive_pretrend_c_trim_top1pct.csv"))
fwrite(t_c95, file.path(OUTPUT_TAB,
       "phase4_within_intensive_pretrend_c_trim_top5pct.csv"))

plot_traj(t_c99, "phase4_within_intensive_pretrend_c_trim_top1pct",
          treat_lines_all)
plot_traj(t_c95, "phase4_within_intensive_pretrend_c_trim_top5pct",
          treat_lines_all)

# ---------------------------------------------------------------------------
# (d) Earlier-anchor 2017 cells (omega + cell membership from 2005-07).
#     Already built into INTERVALS as "treat_2017_anchor2005". Plot the
#     trajectory for just that version alongside the original "treat_2017".
# ---------------------------------------------------------------------------
cat("\n[d] Earlier-anchor (2005-07) version of 2017 cells...\n")
panel_d <- panel_all[version %in% c("treat_2017", "treat_2017_anchor2005")]
t_d <- traj_from_panel(panel_d, "d_anchor_2005")
fwrite(t_d, file.path(OUTPUT_TAB,
       "phase4_within_intensive_pretrend_d_anchor_2005.csv"))
plot_traj(t_d, "phase4_within_intensive_pretrend_d_anchor_2005",
          treat_lines_all[version_label %in% unique(t_d$version_label)])

# ---------------------------------------------------------------------------
# Console summary
# ---------------------------------------------------------------------------
cat("\n=== Summary of cell counts ===\n")
summary_tbl <- rbind(
  cells_all[, .(diagnostic = "baseline", n_cells = .N), by = version],
  b1_keep[, .(diagnostic = "b1_always_active", n_cells = .N), by = version],
  b2_keep[, .(diagnostic = "b2_active_in_2010", n_cells = .N), by = version],
  keep_99[, .(diagnostic = "c_trim_top1pct", n_cells = .N), by = version],
  keep_95[, .(diagnostic = "c_trim_top5pct", n_cells = .N), by = version]
)
print(summary_tbl)
fwrite(summary_tbl, file.path(OUTPUT_TAB,
       "phase4_within_intensive_pretrend_cell_counts.csv"))

cat("\nDone. Outputs:\n  figures: ", OUTPUT_FIG,
    "\n  tables : ", OUTPUT_TAB, "\n")
