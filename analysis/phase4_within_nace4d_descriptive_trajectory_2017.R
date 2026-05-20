###############################################################################
# phase4_within_nace4d_descriptive_trajectory_2017.R
#
# PURPOSE
#   Single-panel (tau = 2017 only) version of the within-NACE-4d intensive-
#   margin trajectory figure produced by
#   phase4_within_intensive_pretrend_present_in_2010_14.R.
#
#   Differences from the original 2-panel figure:
#     - Only includes tau = 2017 (MSR treatment); drops tau = 2005 (EU ETS
#       launch).
#     - Simpler legend labels: "Most exposed supplier" and
#       "Least exposed supplier" (no "lowest-omega portfolio" qualifier).
#
#   Outputs:
#     - phase4_within_nace4d_descriptive_trajectory_2017.{pdf,png}
#     - phase4_within_nace4d_descriptive_trajectory_2017.csv (data backing)
#
# DEPENDENCIES
#   Same as phase4_within_intensive_pretrend_present_in_2010_14.R.
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

set.seed(20260520)

YEAR_LO    <- 2002L
YEAR_HI    <- 2022L
PRE_WINDOW <- 2010L:2014L
OMEGA_WIN  <- c(2015L, 2016L)
TREAT_YEAR <- 2017L

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
# Build present-in-2010-14 sample with top + bot pool (tau = 2017)
# ---------------------------------------------------------------------------
cat("Building present-in-2010-14 sample...\n")
pre_active <- b2b[year %in% PRE_WINDOW,
                  .(pre_sales = sum(sales)),
                  by = .(buyer, seller_nace4d, seller)]
omega_window_active <- b2b[year %in% OMEGA_WIN,
                            .(omega_win_sales = sum(sales)),
                            by = .(buyer, seller_nace4d, seller)]
pool_pairs <- merge(pre_active, omega_window_active,
                    by = c("buyer", "seller_nace4d", "seller"))

omega_byvat <- fe[year %in% OMEGA_WIN,
                  .(omega_anchor = mean(omega_sh, na.rm = TRUE)),
                  by = vat]
pool_pairs <- merge(pool_pairs, omega_byvat,
                    by.x = "seller", by.y = "vat", all.x = TRUE)
pool_pairs[is.na(omega_anchor), omega_anchor := 0]

cell_summary <- pool_pairs[, .(n = .N,
                               max_omega = max(omega_anchor),
                               min_omega = min(omega_anchor)),
                           by = .(buyer, seller_nace4d)]
cell_ok <- cell_summary[n >= 2L & max_omega > 0 & min_omega < max_omega]
pool <- merge(pool_pairs, cell_ok[, .(buyer, seller_nace4d)],
              by = c("buyer", "seller_nace4d"))

pool[, cell_min_omega := min(omega_anchor), by = .(buyer, seller_nace4d)]
setorder(pool, buyer, seller_nace4d, -omega_anchor, -pre_sales, seller)
pool[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
top_sup <- pool[rk == 1L,
                .(buyer, seller_nace4d, top_supplier = seller,
                  omega_top = omega_anchor)]
bot_pool <- pool[omega_anchor == cell_min_omega,
                 .(buyer, seller_nace4d, seller, omega_bot = omega_anchor)]
cat(sprintf("  Cells: %d. Bot pool: %d (mean %.2f per cell).\n",
            nrow(cell_ok), nrow(bot_pool),
            nrow(bot_pool) / nrow(cell_ok)))

# ---------------------------------------------------------------------------
# Build cell-role-year trajectory (top + portfolio bot)
# ---------------------------------------------------------------------------
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

# Top trajectory
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

# Bot trajectory: mean over bot pool members per cell-year
bot_panel_long <- bot_pool[, .(year = YEAR_LO:YEAR_HI),
                            by = .(buyer, seller_nace4d, seller)]
bot_panel_long <- merge(bot_panel_long, yr_denom,
                        by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
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
common <- intersect(
  top_panel[!is.na(share), unique(paste(buyer, seller_nace4d))],
  bot_panel[!is.na(share), unique(paste(buyer, seller_nace4d))]
)
panel <- panel[cell_id %in% common]
cat(sprintf("  Cells with both top and bot observable: %d\n", length(common)))

# ---------------------------------------------------------------------------
# Aggregate to mean trajectory + bands
# ---------------------------------------------------------------------------
traj <- panel[!is.na(share),
              .(mean_share = mean(share),
                se_share   = sd(share) / sqrt(.N),
                n_cells    = .N),
              by = .(year, role)]
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
       "phase4_within_nace4d_descriptive_trajectory_2017.csv"))

# ---------------------------------------------------------------------------
# Single-panel trajectory figure
# ---------------------------------------------------------------------------
g <- ggplot(traj,
            aes(x = year, y = mean_share,
                color = role_label, fill = role_label)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.6) +
  geom_vline(xintercept = TREAT_YEAR - 0.5,
             linetype = "dashed", color = "firebrick") +
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
        axis.title.y     = element_text(size = 20, margin = margin(r = 16)),
        axis.text        = element_text(size = 17),
        legend.position  = "bottom",
        legend.text      = element_text(size = 16))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_descriptive_trajectory_2017.png"),
       g, width = 9, height = 5.5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_descriptive_trajectory_2017.pdf"),
       g, width = 9, height = 5.5)

# ---------------------------------------------------------------------------
# Second version: x-axis cropped to 2012-2022
# ---------------------------------------------------------------------------
g_2012 <- g +
  scale_x_continuous(breaks = seq(2012L, YEAR_HI, by = 1),
                     limits = c(2012L, YEAR_HI))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_descriptive_trajectory_2017_2012_2022.png"),
       g_2012, width = 9, height = 5.5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_descriptive_trajectory_2017_2012_2022.pdf"),
       g_2012, width = 9, height = 5.5)

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")
