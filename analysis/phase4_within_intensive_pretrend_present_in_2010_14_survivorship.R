###############################################################################
# phase4_within_intensive_pretrend_present_in_2010_14_survivorship.R
#
# PURPOSE
#   Survivorship robustness for the "present in 2010-14 AND 2015-16" sample
#   (see phase4_within_intensive_pretrend_present_in_2010_14.R for the
#   sample-construction details).
#
#   The post-2014 within-cell trajectory may still be biased by differential
#   attrition between the most-exposed supplier and the lowest-omega
#   portfolio. We re-run the tau=2017 specification under three variants:
#
#     1. Baseline (no survivorship filter).
#     2. Bot-only filter: bot pool restricted to lowest-omega suppliers
#        with positive sales to the buyer in SURVIVE_YEAR (= 2018).
#        Top unchanged.
#     3. Symmetric filter: BOTH top and bot restricted to surviving SURVIVE_YEAR.
#        Holds the relationship-attrition channel constant across roles.
#
#   Variant 3 is the cleaner economic test. Variant 2 is shown so the
#   asymmetric-filter selection artifact (bot selected on durability)
#   can be seen directly. Variant 1 is the unfiltered headline.
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

YEAR_LO      <- 2002L
YEAR_HI      <- 2022L
PRE_WINDOW   <- 2010L:2014L
OMEGA_WIN    <- c(2015L, 2016L)
TREAT_YEAR   <- 2017L
SURVIVE_YEAR <- 2018L

# ---------------------------------------------------------------------------
# Load data (same as the main present-in-2010-14 script)
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
# Build cells + top + bot pool (present-in-2010-14 sample, lowest-omega bot)
# ---------------------------------------------------------------------------
cat("Building present-in-2010-14 sample + role assignment...\n")
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
                .(buyer, seller_nace4d,
                  top_supplier = seller,
                  omega_top    = omega_anchor)]
bot_pool <- pool[omega_anchor == cell_min_omega,
                 .(buyer, seller_nace4d, seller,
                   omega_bot = omega_anchor)]
cat(sprintf("  Cells: %d  |  bot pool: %d  |  top: %d\n",
            nrow(cell_ok), nrow(bot_pool), nrow(top_sup)))

# ---------------------------------------------------------------------------
# Survivorship filter: positive sales to the buyer in SURVIVE_YEAR
# ---------------------------------------------------------------------------
cat(sprintf("Applying survivorship filter (positive sales in %d)...\n",
            SURVIVE_YEAR))
survive_pairs <- b2b[year == SURVIVE_YEAR & sales > 0,
                     .(buyer, seller_nace4d, seller)]
survive_pairs[, surviving := TRUE]

bot_pool_surv <- merge(bot_pool, survive_pairs,
                       by = c("buyer", "seller_nace4d", "seller"))
top_sup_surv <- merge(top_sup,
                      survive_pairs[, .(buyer, seller_nace4d, seller)],
                      by.x = c("buyer", "seller_nace4d", "top_supplier"),
                      by.y = c("buyer", "seller_nace4d", "seller"))
cat(sprintf("  Bot lowest-omega suppliers surviving to %d : %d / %d (%.1f%%)\n",
            SURVIVE_YEAR, nrow(bot_pool_surv), nrow(bot_pool),
            100 * nrow(bot_pool_surv) / nrow(bot_pool)))
cat(sprintf("  Top suppliers surviving to %d             : %d / %d (%.1f%%)\n",
            SURVIVE_YEAR, nrow(top_sup_surv), nrow(top_sup),
            100 * nrow(top_sup_surv) / nrow(top_sup)))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

top_trajectory <- function(top_dt) {
  panel <- top_dt[, .(year = YEAR_LO:YEAR_HI),
                  by = .(buyer, seller_nace4d, top_supplier)]
  setnames(panel, "top_supplier", "seller")
  panel <- merge(panel, yr_denom,
                 by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
  panel <- merge(panel, yr_sales,
                 by = c("buyer", "seller_nace4d", "seller", "year"),
                 all.x = TRUE)
  panel[is.na(sales), sales := 0]
  panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                            total_buyer_nace4d_spend <= 0,
                          NA_real_, sales / total_buyer_nace4d_spend)]
  panel[, role := "top"]
  panel[, .(buyer, seller_nace4d, year, role, share)]
}

bot_trajectory <- function(bot_dt) {
  panel_long <- bot_dt[, .(year = YEAR_LO:YEAR_HI),
                       by = .(buyer, seller_nace4d, seller)]
  panel_long <- merge(panel_long, yr_denom,
                      by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
  panel_long <- merge(panel_long, yr_sales,
                      by = c("buyer", "seller_nace4d", "seller", "year"),
                      all.x = TRUE)
  panel_long[is.na(sales), sales := 0]
  panel_long[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                                 total_buyer_nace4d_spend <= 0,
                               NA_real_, sales / total_buyer_nace4d_spend)]
  panel <- panel_long[!is.na(share),
                      .(share = mean(share)),
                      by = .(buyer, seller_nace4d, year)]
  panel[, role := "bot"]
  panel[, .(buyer, seller_nace4d, year, role, share)]
}

build_variant <- function(variant_label, top_dt, bot_dt) {
  top_p <- top_trajectory(top_dt)
  bot_p <- bot_trajectory(bot_dt)
  panel <- rbind(top_p, bot_p)
  panel[, cell_id := paste(buyer, seller_nace4d)]
  common <- intersect(
    top_p[!is.na(share), unique(paste(buyer, seller_nace4d))],
    bot_p[!is.na(share), unique(paste(buyer, seller_nace4d))]
  )
  panel <- panel[cell_id %in% common]
  panel[, variant := variant_label]
  cat(sprintf("  [%s] cells with both trajectories observable: %d\n",
              variant_label, length(common)))
  panel[]
}

# ---------------------------------------------------------------------------
# Build the three variants
# ---------------------------------------------------------------------------
cat("\nBuilding variant 1: baseline (no survivorship filter)...\n")
v_base <- build_variant("Baseline (no survivorship filter)",
                         top_sup, bot_pool)
cat(sprintf("Building variant 2: bot-only survivorship to %d...\n",
            SURVIVE_YEAR))
v_bot  <- build_variant(sprintf("Bot lowest-ω survives to %d", SURVIVE_YEAR),
                         top_sup, bot_pool_surv)
cat(sprintf("Building variant 3: symmetric survivorship to %d...\n",
            SURVIVE_YEAR))
v_both <- build_variant(sprintf("Top and bot survive to %d", SURVIVE_YEAR),
                         top_sup_surv, bot_pool_surv)

panels <- rbind(v_base, v_bot, v_both)
panels[, variant := factor(variant, levels = c(
  "Baseline (no survivorship filter)",
  sprintf("Bot lowest-ω survives to %d", SURVIVE_YEAR),
  sprintf("Top and bot survive to %d", SURVIVE_YEAR)
))]

# ---------------------------------------------------------------------------
# Trajectory figure (3 facets)
# ---------------------------------------------------------------------------
traj <- panels[!is.na(share),
               .(mean_share = mean(share),
                 se_share   = sd(share) / sqrt(.N),
                 n_cells    = .N),
               by = .(variant, year, role)]
traj[, lo := mean_share - 1.96 * se_share]
traj[, hi := mean_share + 1.96 * se_share]
traj[, role_label := fcase(
  role == "top", "Most exposed supplier",
  role == "bot", "Least exposed supplier (lowest-ω portfolio)"
)]
traj[, role_label := factor(role_label,
                            levels = c("Most exposed supplier",
                                       "Least exposed supplier (lowest-ω portfolio)"))]

fwrite(traj, file.path(OUTPUT_TAB,
       "phase4_within_intensive_present_in_2010_14_survivorship_trajectory.csv"))

g <- ggplot(traj,
            aes(x = year, y = mean_share,
                color = role_label, fill = role_label)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.4) +
  geom_vline(xintercept = TREAT_YEAR - 0.5,
             linetype = "dashed", color = "firebrick") +
  facet_wrap(~ variant, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_color_manual(
    values = c("Most exposed supplier" = "firebrick",
               "Least exposed supplier (lowest-ω portfolio)" = "navy"),
    name = NULL) +
  scale_fill_manual(
    values = c("Most exposed supplier" = "firebrick",
               "Least exposed supplier (lowest-ω portfolio)" = "navy"),
    name = NULL) +
  labs(x = NULL, y = "Mean within-cell expenditure share") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 20, margin = margin(r = 18)),
        axis.text        = element_text(size = 14),
        strip.text       = element_text(face = "bold", size = 14),
        legend.position  = "bottom",
        legend.text      = element_text(size = 14))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_present_in_2010_14_survivorship_trajectory.png"),
       g, width = 9, height = 11, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_present_in_2010_14_survivorship_trajectory.pdf"),
       g, width = 9, height = 11)

# Sample-size companion
ss <- panels[, .(n_with_observed = sum(!is.na(share))),
             by = .(variant, year, role)]
fwrite(ss, file.path(OUTPUT_TAB,
       "phase4_within_intensive_present_in_2010_14_survivorship_samplesize.csv"))

g_ss <- ggplot(ss, aes(x = year, y = n_with_observed,
                       color = role)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.2) +
  geom_vline(xintercept = TREAT_YEAR - 0.5,
             linetype = "dashed", color = "firebrick") +
  facet_wrap(~ variant, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_color_manual(values = c("top" = "firebrick", "bot" = "navy"),
                     labels = c("top" = "Most exposed",
                                "bot" = "Least exposed"),
                     name = NULL) +
  labs(x = NULL, y = "Number of cells (NACE-4d spend > 0 that year)") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 18, margin = margin(r = 18)),
        axis.text        = element_text(size = 13),
        strip.text       = element_text(face = "bold", size = 14),
        legend.position  = "bottom",
        legend.text      = element_text(size = 14))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_present_in_2010_14_survivorship_samplesize.png"),
       g_ss, width = 9, height = 11, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_present_in_2010_14_survivorship_samplesize.pdf"),
       g_ss, width = 9, height = 11)

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")
