###############################################################################
# phase4_within_nace4d_descriptive_trajectory_2017_activeAtT.R
#
# PURPOSE
#   Companion to phase4_within_nace4d_descriptive_trajectory_2017.R that
#   strips out the mechanical contribution of differential attrition between
#   top and bot suppliers to the year-by-year mean within-cell expenditure
#   share trajectory.
#
# WHY
#   The raw trajectory averages the within-cell expenditure share across cells
#   at each year, with dead pairs (zero sales at year t) contributing zero.
#   Because top suppliers survive at slightly higher rates than bot-pool
#   members, the dead-as-zero contribution pulls down the mean bot share more
#   than the mean top share, generating a visible post-2017 widening of the
#   top-bot gap that is mechanical, not behavioural. Column 2 of Table 4
#   (the DiD with age + age x top fixed effects) absorbs this differential
#   and shrinks the headline coefficient by a factor of four. This figure
#   gives a visual analog of that result.
#
# METHOD
#   Same sample construction as the raw trajectory (present-in-2010-14).
#     - Top trajectory at year t: mean over cells of the top supplier's share,
#       restricted to cells where the top supplier is alive at t (positive
#       sales to the buyer at t).
#     - Bot trajectory at year t: mean over cells of the cell's bot-pool
#       mean share, where the bot-pool mean at year t is computed only over
#       alive bot-pool members; cells with no alive bot-pool member at t
#       are dropped from the year-t average.
#
#   The total-buyer-NACE-4d-spend denominator is unchanged: it includes all
#   purchases the buyer makes from suppliers in the NACE 4-digit, alive or
#   not. We are only changing the numerator's contribution rule.
#
# OUTPUTS
#   - phase4_within_nace4d_descriptive_trajectory_2017_activeAtT.{pdf,png}
#   - phase4_within_nace4d_descriptive_trajectory_2017_activeAtT.csv
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

set.seed(20260526)

YEAR_LO    <- 2002L
YEAR_HI    <- 2022L
PRE_WINDOW <- 2010L:2014L
OMEGA_WIN  <- c(2015L, 2016L)
TREAT_YEAR <- 2017L

# ---------------------------------------------------------------------------
# Load data (identical to phase4_within_nace4d_descriptive_trajectory_2017.R)
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
# Build present-in-2010-14 sample with top + bot pool (identical)
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
# Build trajectories with ACTIVE-AT-T restriction
#
# Key change vs the raw trajectory script: bot/top pair-years with sales==0
# (dead at year t) are dropped from the per-cell mean rather than included
# as zero contributions.
# ---------------------------------------------------------------------------
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

# ---- Top trajectory: only cells where top is alive at year t -------------
top_panel <- top_sup[, .(year = YEAR_LO:YEAR_HI),
                     by = .(buyer, seller_nace4d, top_supplier)]
setnames(top_panel, "top_supplier", "seller")
top_panel <- merge(top_panel, yr_denom,
                   by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
top_panel <- merge(top_panel, yr_sales,
                   by = c("buyer", "seller_nace4d", "seller", "year"),
                   all.x = TRUE)
# Drop dead top observations (no positive sales at year t)
top_panel <- top_panel[!is.na(sales) & sales > 0]
top_panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                              total_buyer_nace4d_spend <= 0,
                            NA_real_, sales / total_buyer_nace4d_spend)]
top_panel[, role := "top"]
top_panel <- top_panel[!is.na(share),
                       .(buyer, seller_nace4d, year, role, share)]

# ---- Bot trajectory: mean over alive bot pool members per cell-year ------
bot_panel_long <- bot_pool[, .(year = YEAR_LO:YEAR_HI),
                            by = .(buyer, seller_nace4d, seller)]
bot_panel_long <- merge(bot_panel_long, yr_denom,
                        by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
bot_panel_long <- merge(bot_panel_long, yr_sales,
                        by = c("buyer", "seller_nace4d", "seller", "year"),
                        all.x = TRUE)
# Drop dead bot members at year t before computing per-cell mean
bot_panel_long <- bot_panel_long[!is.na(sales) & sales > 0]
bot_panel_long[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                                   total_buyer_nace4d_spend <= 0,
                                 NA_real_, sales / total_buyer_nace4d_spend)]
bot_panel <- bot_panel_long[!is.na(share),
                            .(share = mean(share)),
                            by = .(buyer, seller_nace4d, year)]
bot_panel[, role := "bot"]
bot_panel <- bot_panel[, .(buyer, seller_nace4d, year, role, share)]

# Only keep cells where both top and bot are at least once observable on the
# alive panel (mirrors the raw-trajectory script's intersection)
panel <- rbind(top_panel, bot_panel)
panel[, cell_id := paste(buyer, seller_nace4d)]
common <- intersect(
  top_panel[, unique(paste(buyer, seller_nace4d))],
  bot_panel[, unique(paste(buyer, seller_nace4d))]
)
panel <- panel[cell_id %in% common]
cat(sprintf("  Cells with both top and bot observable on the alive panel: %d\n",
            length(common)))

# ---------------------------------------------------------------------------
# Aggregate to mean trajectory + 95% bands
# ---------------------------------------------------------------------------
traj <- panel[, .(mean_share = mean(share),
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
       "phase4_within_nace4d_descriptive_trajectory_2017_activeAtT.csv"))

cat("\n--- Active-at-t mean within-cell expenditure share ---\n")
print(dcast(traj[, .(role, year, mean_share)],
            year ~ role, value.var = "mean_share"))

# ---------------------------------------------------------------------------
# Plot (2012-2022 window, mirror of the raw trajectory figure used in paper)
# ---------------------------------------------------------------------------
g <- ggplot(traj[year >= 2012L],
            aes(x = year, y = mean_share,
                color = role_label, fill = role_label)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.6) +
  geom_vline(xintercept = TREAT_YEAR - 0.5,
             linetype = "dashed", color = "firebrick") +
  scale_x_continuous(breaks = seq(2012L, YEAR_HI, by = 1)) +
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
       "phase4_within_nace4d_descriptive_trajectory_2017_activeAtT.png"),
       g, width = 9, height = 5.5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_descriptive_trajectory_2017_activeAtT.pdf"),
       g, width = 9, height = 5.5)

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")
