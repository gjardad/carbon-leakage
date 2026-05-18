###############################################################################
# phase4_within_intensive_pretrend_hybridB_final.R
#
# PURPOSE
#   Build the Hybrid B + portfolio-bot construction for BOTH treatment
#   periods (τ=2005 and τ=2017) of the within-NACE4d intensive margin:
#
#     Cell sample (Hybrid B): buyer-seller pair active in at least one year
#       of the pre-window (2002-2004 for τ=2005; 2010-2014 for τ=2017).
#       Cell qualifies if >= 2 such suppliers in (buyer, seller_nace4d)
#       AND at least one of them has omega-anchor > 0.
#
#     Top = single supplier with the highest omega in the anchor window
#           (2005 itself for τ=2005; 2015-16 for τ=2017). Sales tiebreaker
#           is empirically irrelevant: top ties are 0% of cells.
#
#     Bot (portfolio average) = for each cell-year, the MEAN across all
#           omega=0 suppliers in the cell's pre-window pool of their
#           individual within-cell shares (sales_{s,b,n,t} / total_{b,n,t}).
#           Eliminates the 32% bot-tiebreaker arbitrariness present in the
#           original 2015-16 anchor (where 1/3 of cells had multiple omega=0
#           suppliers tied at the bot, decided by minimum sales).
#
#   Outputs:
#     - 2-panel trajectory figure (one panel per τ) mirroring the production
#       phase4_within_nace4d_intensive_allcells_topbot_trajectory.pdf layout.
#     - Sample-size diagnostic per year per panel.
#     - CSV with trajectory + sample-size + tiebreaker prevalence.
#
# RUN ON RMD
#   1. git pull on RMD (this script and the diagnostic + hybrid intermediates
#      are committed).
#   2. Rscript analysis/phase4_within_intensive_pretrend_hybridB_final.R
#      -- this writes to output_rmd/figures and output_rmd/tables.
#   3. git status, then commit + push the RMD outputs so local-1 can review.
#   4. We compare the RMD 2-panel figure to the production trajectory and
#      decide on the production update of phase4_within_intensive_figures.R
#      + phase4_within_intensive_did_mht.R.
#
# DIDID NOTE (not addressed here)
#   This prototype produces trajectories only. The DiD ripple is deferred:
#   bot is now a per-cell average across multiple omega=0 suppliers, so the
#   cell-by-role panel for the DiD must collapse all omega=0 suppliers to
#   one synthetic "bot" row per cell-year before clustering. The regression
#   spec (share ~ i(post, top) | cell_role_id + year, cluster = cell) stays
#   the same.
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

# Two treatment events, each with its own pre-window (cell sample) and
# omega-anchor window (top/bot ranking).
#   τ=2005: pre-window 2002-2004 (the B2B data starts in 2002 and the EU ETS
#           did not exist before 2005 -- the pre-window is unambiguously
#           pre-policy). Omega anchored on 2005 (the first year of EUTL
#           records). Treatment year = 2005.
#   τ=2017: pre-window 2010-2014 (well before MSR discussions). Omega
#           anchored on 2015-2016. Treatment year = 2017.
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
# Build Hybrid B cells + top + bot-portfolio panel for one interval
# ---------------------------------------------------------------------------
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

build_interval <- function(label, pre_window, omega_win, treat_year,
                            display_label) {
  cat(sprintf("\n--- %s ---\n  pre-window: %s\n  omega-anchor: %s\n",
              label, paste(range(pre_window), collapse = "-"),
              paste(omega_win, collapse = ", ")))

  # 1. Hybrid B pool: pairs active in >=1 year of pre-window
  pre_active <- b2b[year %in% pre_window,
                    .(pre_sales = sum(sales)),
                    by = .(buyer, seller_nace4d, seller)]

  # 2. Attach omega-anchor (mean over omega_win)
  omega_byvat <- fe[year %in% omega_win,
                    .(omega_anchor = mean(omega_sh, na.rm = TRUE)),
                    by = vat]
  pre_active <- merge(pre_active, omega_byvat,
                      by.x = "seller", by.y = "vat", all.x = TRUE)
  pre_active[is.na(omega_anchor), omega_anchor := 0]

  # 3. Cell qualification
  cell_ok <- pre_active[, .(n = .N, max_omega = max(omega_anchor)),
                        by = .(buyer, seller_nace4d)][n >= 2L & max_omega > 0]
  pool <- merge(pre_active, cell_ok[, .(buyer, seller_nace4d)],
                by = c("buyer", "seller_nace4d"))
  cat(sprintf("  Hybrid B cells: %d\n", nrow(cell_ok)))

  # 4. Top = highest omega (sales tiebreaker; empirically irrelevant at top)
  setorder(pool, buyer, seller_nace4d, -omega_anchor, -pre_sales, seller)
  pool[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
  top_sup <- pool[rk == 1L, .(buyer, seller_nace4d,
                              top_supplier = seller,
                              omega_top    = omega_anchor)]
  bot_pool <- pool[omega_anchor == 0,
                   .(buyer, seller_nace4d, seller)]
  cat(sprintf("  omega=0 suppliers: %d (mean %.2f per cell)\n",
              nrow(bot_pool), nrow(bot_pool) / nrow(cell_ok)))

  # 5. Top trajectory: one row per cell-year
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

  # 6. Bot trajectory: mean over omega=0 suppliers per cell-year
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

  # Restrict to cells that have both top and bot trajectories observable
  common <- intersect(
    top_panel[!is.na(share), unique(paste(buyer, seller_nace4d))],
    bot_panel[!is.na(share), unique(paste(buyer, seller_nace4d))]
  )
  panel <- panel[cell_id %in% common]
  cat(sprintf("  cells with both top and bot observable: %d\n", length(common)))

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
# 2-panel trajectory figure (mirrors the production layout)
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
  role == "bot", "Least exposed supplier (ω=0 portfolio)"
)]
traj[, role_label := factor(role_label,
                            levels = c("Most exposed supplier",
                                       "Least exposed supplier (ω=0 portfolio)"))]

fwrite(traj, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_topbot_hybridB_trajectory.csv"))

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
               "Least exposed supplier (ω=0 portfolio)" = "navy"),
    name = NULL) +
  scale_fill_manual(
    values = c("Most exposed supplier" = "firebrick",
               "Least exposed supplier (ω=0 portfolio)" = "navy"),
    name = NULL) +
  labs(x = NULL, y = "Mean within-cell expenditure share") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 22, margin = margin(r = 18)),
        axis.text        = element_text(size = 18),
        strip.text       = element_text(face = "bold", size = 16),
        legend.position  = "bottom",
        legend.text      = element_text(size = 16))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_topbot_hybridB_trajectory.png"),
       g, width = 9, height = 8, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_topbot_hybridB_trajectory.pdf"),
       g, width = 9, height = 8)

# Sample-size companion (one trace per version+role)
ss <- panels[, .(
  n_with_observed = sum(!is.na(share))
), by = .(version, version_label, treat_year, year, role)]
ss[, role_label := fcase(
  role == "top", "Most exposed supplier",
  role == "bot", "Least exposed (ω=0 portfolio)"
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
               "Least exposed (ω=0 portfolio)" = "navy"),
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
       "phase4_within_nace4d_intensive_topbot_hybridB_samplesize.png"),
       g_ss, width = 9, height = 7, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_topbot_hybridB_samplesize.pdf"),
       g_ss, width = 9, height = 7)

fwrite(ss, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_topbot_hybridB_samplesize.csv"))

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")
