###############################################################################
# phase4_within_intensive_pretrend_present_in_2010_14.R
#
# PURPOSE
#   Within-NACE-4d intensive-margin trajectory under the sample:
#     (buyer, seller) pair active in some year of the pre-window (2010-14
#     for tau=2017; 2002-04 for tau=2005) AND active in some year of the
#     omega-measurement window (2015-16 for tau=2017; 2005 for tau=2005).
#
#   Compared to phase4_within_intensive_pretrend_hybridB_final.R, this
#   spec adds the requirement that the pair exist at the moment exposure
#   is measured (so the supplier is a real candidate for substitution
#   when the price shock hits), and generalizes the bot definition from
#   "omega = 0 only" to "lowest-omega supplier(s) in the cell" -- which
#   is omega = 0 in most cells but accommodates cells where every supplier
#   is regulated.
#
#   Cell qualification:
#     - >= 2 distinct suppliers in the pool (active in both windows)
#     - max_omega > 0  (at least one regulated supplier in 2015-16)
#     - min_omega < max_omega  (a meaningful within-cell exposure gap)
#
#   Top: single supplier with the highest 2015-16 omega in the cell
#        (pre-sales tiebreaker; empirically irrelevant since top-end ties
#         are 0% of cells under shortage-based omega).
#   Bot (portfolio): mean across all suppliers tied at the cell's MIN omega
#        of their individual within-cell shares.
#
#   Outputs:
#     - 2-panel trajectory figure (tau=2005, tau=2017)
#     - Sample-size diagnostic per year per panel
#     - CSV with trajectory data
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

set.seed(20260519)

YEAR_LO <- 2002L
YEAR_HI <- 2022L

# Pre-window AND omega-window per treatment. Pairs must be active in BOTH.
#   tau=2005: pre-window 2002-04 (unambiguously pre-policy). Omega anchored
#             on 2005 itself. Pair must be active in 2002-04 AND in 2005.
#   tau=2017: pre-window 2010-14. Omega anchored on 2015-16. Pair must be
#             active in 2010-14 AND in 2015-16.
INTERVALS <- list(
  "treat_2005" = list(pre_window = 2002L:2004L,
                      omega_win  = c(2005L),
                      treat_year = 2005L,
                      label      = "2005 Treatment"),
  "treat_2017" = list(pre_window = 2010L:2014L,
                      omega_win  = c(2015L, 2016L),
                      treat_year = 2017L,
                      label      = "2017 Treatment")
)

# ---------------------------------------------------------------------------
# Load data
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
  vat = as.character(vat_ano), year = as.integer(year),
  nace4d = substr(nace5d, 1, 4))]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

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
# Cell + role construction for one interval
# ---------------------------------------------------------------------------
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

build_interval <- function(label, pre_window, omega_win, treat_year,
                            display_label) {
  cat(sprintf("\n--- %s ---\n  pre-window: %s\n  omega-window: %s\n",
              label,
              paste(range(pre_window), collapse = "-"),
              paste(omega_win, collapse = ", ")))

  # 1. Pairs active in pre-window
  pre_active <- b2b[year %in% pre_window,
                    .(pre_sales = sum(sales)),
                    by = .(buyer, seller_nace4d, seller)]

  # 2. Pairs active in omega-window
  omega_window_active <- b2b[year %in% omega_win,
                              .(omega_win_sales = sum(sales)),
                              by = .(buyer, seller_nace4d, seller)]

  # 3. Intersection -- pairs active in BOTH windows
  pool_pairs <- merge(pre_active, omega_window_active,
                      by = c("buyer", "seller_nace4d", "seller"))
  cat(sprintf("  Pairs active in both windows: %d\n", nrow(pool_pairs)))

  # 4. Attach firm-level omega measured at the omega window
  omega_byvat <- fe[year %in% omega_win,
                    .(omega_anchor = mean(omega_sh, na.rm = TRUE)),
                    by = vat]
  pool_pairs <- merge(pool_pairs, omega_byvat,
                      by.x = "seller", by.y = "vat", all.x = TRUE)
  pool_pairs[is.na(omega_anchor), omega_anchor := 0]

  # 5. Cell qualification: >=2 suppliers, max_omega > 0, min_omega < max_omega
  cell_summary <- pool_pairs[, .(n = .N,
                                 max_omega = max(omega_anchor),
                                 min_omega = min(omega_anchor)),
                             by = .(buyer, seller_nace4d)]
  cell_ok <- cell_summary[n >= 2L & max_omega > 0 & min_omega < max_omega]
  pool <- merge(pool_pairs, cell_ok[, .(buyer, seller_nace4d)],
                by = c("buyer", "seller_nace4d"))
  cat(sprintf("  Qualifying cells: %d\n", nrow(cell_ok)))

  # 6. Role assignment within each cell
  pool[, cell_min_omega := min(omega_anchor), by = .(buyer, seller_nace4d)]
  pool[, cell_max_omega := max(omega_anchor), by = .(buyer, seller_nace4d)]

  setorder(pool, buyer, seller_nace4d, -omega_anchor, -pre_sales, seller)
  pool[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
  top_sup <- pool[rk == 1L,
                  .(buyer, seller_nace4d,
                    top_supplier = seller,
                    omega_top    = omega_anchor)]
  # Bot pool: all suppliers with omega == cell min. Since min < max in every
  # qualifying cell, the top supplier (omega = max) is automatically excluded.
  bot_pool <- pool[omega_anchor == cell_min_omega,
                   .(buyer, seller_nace4d, seller,
                     omega_bot = omega_anchor)]
  cat(sprintf("  Bot pool size (lowest-omega suppliers): %d (mean %.2f per cell)\n",
              nrow(bot_pool), nrow(bot_pool) / nrow(cell_ok)))
  cat(sprintf("  Cells with min_omega = 0: %d / %d (%.1f%%)\n",
              cell_ok[min_omega == 0, .N], nrow(cell_ok),
              100 * cell_ok[min_omega == 0, .N] / nrow(cell_ok)))

  # 7. Top trajectory: one row per cell-year
  top_panel <- top_sup[, .(year = YEAR_LO:YEAR_HI),
                       by = .(buyer, seller_nace4d, top_supplier)]
  setnames(top_panel, "top_supplier", "seller")
  top_panel <- merge(top_panel, yr_denom,
                     by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
  top_panel <- merge(top_panel, yr_sales,
                     by = c("buyer", "seller_nace4d", "seller", "year"),
                     all.x = TRUE)
  top_panel[is.na(sales), sales := 0]
  top_panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                                total_buyer_nace4d_spend <= 0,
                              NA_real_, sales / total_buyer_nace4d_spend)]
  top_panel[, role := "top"]
  top_panel <- top_panel[, .(buyer, seller_nace4d, year, role, share)]

  # 8. Bot trajectory: mean over bot pool members per cell-year
  bot_panel_long <- bot_pool[, .(year = YEAR_LO:YEAR_HI),
                              by = .(buyer, seller_nace4d, seller)]
  bot_panel_long <- merge(bot_panel_long, yr_denom,
                          by = c("buyer", "seller_nace4d", "year"),
                          all.x = TRUE)
  bot_panel_long <- merge(bot_panel_long, yr_sales,
                          by = c("buyer", "seller_nace4d", "seller", "year"),
                          all.x = TRUE)
  bot_panel_long[is.na(sales), sales := 0]
  bot_panel_long[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                                     total_buyer_nace4d_spend <= 0,
                                   NA_real_, sales / total_buyer_nace4d_spend)]
  bot_panel <- bot_panel_long[!is.na(share),
                              .(share = mean(share)),
                              by = .(buyer, seller_nace4d, year)]
  bot_panel[, role := "bot"]
  bot_panel <- bot_panel[, .(buyer, seller_nace4d, year, role, share)]

  panel <- rbind(top_panel, bot_panel)
  panel[, cell_id := paste(buyer, seller_nace4d)]

  # Restrict to cells where both top and bot have observable share
  common <- intersect(
    top_panel[!is.na(share), unique(paste(buyer, seller_nace4d))],
    bot_panel[!is.na(share), unique(paste(buyer, seller_nace4d))]
  )
  panel <- panel[cell_id %in% common]
  cat(sprintf("  Cells with both top and bot trajectories observable: %d\n",
              length(common)))

  panel[, version       := label]
  panel[, version_label := display_label]
  panel[, treat_year    := treat_year]
  panel[]
}

# Run for each interval
panels <- rbindlist(lapply(names(INTERVALS), function(lab) {
  iv <- INTERVALS[[lab]]
  build_interval(lab, iv$pre_window, iv$omega_win, iv$treat_year, iv$label)
}), use.names = TRUE)

# ---------------------------------------------------------------------------
# 2-panel trajectory figure
# ---------------------------------------------------------------------------
cat("\nBuilding 2-panel trajectory figure...\n")
traj <- panels[!is.na(share),
               .(mean_share = mean(share),
                 se_share   = sd(share) / sqrt(.N),
                 n_cells    = .N),
               by = .(version, version_label, treat_year, year, role)]
traj[, lo := mean_share - 1.96 * se_share]
traj[, hi := mean_share + 1.96 * se_share]
traj[, role_label := fcase(
  role == "top", "Most exposed supplier",
  role == "bot", "Least exposed supplier"
)]
traj[, role_label := factor(role_label,
                            levels = c("Most exposed supplier",
                                       "Least exposed supplier"))]

fwrite(traj, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_topbot_present_in_2010_14_trajectory.csv"))

treat_lines <- unique(traj[, .(version_label, treat_year)])

g <- ggplot(traj,
            aes(x = year, y = mean_share,
                color = role_label, fill = role_label)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.4) +
  geom_vline(data = treat_lines,
             aes(xintercept = treat_year - 0.5),
             linetype = "dashed", color = "firebrick", inherit.aes = FALSE) +
  facet_wrap(~ version_label, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_color_manual(
    values = c("Most exposed supplier" = "firebrick",
               "Least exposed supplier" = "navy"),
    name = NULL) +
  scale_fill_manual(
    values = c("Most exposed supplier" = "firebrick",
               "Least exposed supplier" = "navy"),
    name = NULL) +
  labs(x = NULL, y = "Mean within-cell expenditure share") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 22, margin = margin(r = 18)),
        axis.text        = element_text(size = 18),
        strip.text       = element_text(face = "bold", size = 16),
        legend.position  = "bottom",
        legend.text      = element_text(size = 15))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_topbot_present_in_2010_14_trajectory.png"),
       g, width = 9, height = 8, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_topbot_present_in_2010_14_trajectory.pdf"),
       g, width = 9, height = 8)

# Sample-size companion
ss <- panels[, .(n_with_observed = sum(!is.na(share))),
             by = .(version, version_label, treat_year, year, role)]
ss[, role_label := fcase(
  role == "top", "Most exposed supplier",
  role == "bot", "Least exposed supplier"
)]

g_ss <- ggplot(ss, aes(x = year, y = n_with_observed, color = role_label)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.4) +
  geom_vline(data = treat_lines,
             aes(xintercept = treat_year - 0.5),
             linetype = "dashed", color = "firebrick", inherit.aes = FALSE) +
  facet_wrap(~ version_label, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_color_manual(
    values = c("Most exposed supplier" = "firebrick",
               "Least exposed supplier" = "navy"),
    name = NULL) +
  labs(x = NULL, y = "Number of cells (NACE-4d spend > 0 that year)") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 18, margin = margin(r = 18)),
        axis.text        = element_text(size = 14),
        strip.text       = element_text(face = "bold", size = 14),
        legend.position  = "bottom",
        legend.text      = element_text(size = 14))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_topbot_present_in_2010_14_samplesize.png"),
       g_ss, width = 9, height = 7, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_topbot_present_in_2010_14_samplesize.pdf"),
       g_ss, width = 9, height = 7)

fwrite(ss, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_topbot_present_in_2010_14_samplesize.csv"))

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")
