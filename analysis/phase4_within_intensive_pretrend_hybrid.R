###############################################################################
# phase4_within_intensive_pretrend_hybrid.R
#
# PURPOSE
#   Follow-up to phase4_within_intensive_pretrend_diagnostic.R. Builds the
#   "Hybrid A" and "Hybrid B" anchors that decouple two concerns:
#     1. Cell SAMPLE = buyer-seller pair active in a stable 2010-2014 window
#        (eliminates the mechanical relationship-formation climb toward 2015-16).
#     2. Top-omega / bot-omega RANKING = computed at 2015-16 (the moment the
#        MSR price hits), restricted to suppliers that meet (1).
#
#   Also documents:
#     (i)  Tiebreaker prevalence: how often is sales the tiebreaker in the
#          original 2015-16 anchor? Bot is .SD[.N] of suppliers ordered
#          (-omega, -sales, seller) -- among many omega=0 ties, the bot is
#          the smallest-sales omega=0 supplier. We count cells with bot
#          ties to estimate the relevance of this artifact.
#     (ii) Hybrid A trajectory (2010-2014 continuous, ranked on 2015-16 omega)
#          Hybrid B trajectory (2010-2014 ANY year, ranked on 2015-16 omega)
#          Cell counts per year for each.
#
# DEPENDENCIES
#   Same as phase4_within_intensive_pretrend_diagnostic.R
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

YEAR_LO         <- 2002L
YEAR_HI         <- 2022L
PRE_WINDOW      <- 2010L:2014L     # stable pre-anchor window for the cell sample
OMEGA_WINDOW    <- c(2015L, 2016L) # ranking window
TREAT_YEAR      <- 2017L

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
# (i) Tiebreaker prevalence in the original 2015-16 anchor
# ---------------------------------------------------------------------------
cat("\n[i] Tiebreaker prevalence in the 2015-16 anchor...\n")

# 2015-16 seller-year aggregation (the original anchor)
seller_orig <- b2b[year %in% OMEGA_WINDOW,
                   .(int_sales = sum(sales)),
                   by = .(buyer, seller_nace4d, seller)]
fe_omega    <- fe[year %in% OMEGA_WINDOW,
                  .(int_omega = mean(omega_sh, na.rm = TRUE)),
                  by = vat]
seller_orig <- merge(seller_orig, fe_omega,
                     by.x = "seller", by.y = "vat", all.x = TRUE)
seller_orig[is.na(int_omega), int_omega := 0]

# Cells with >=2 suppliers and at least one omega > 0
cell_ok <- seller_orig[, .(n = .N, max_omega = max(int_omega)),
                       by = .(buyer, seller_nace4d)][n >= 2L & max_omega > 0]
sc <- merge(seller_orig, cell_ok[, .(buyer, seller_nace4d)],
            by = c("buyer", "seller_nace4d"))

# For each cell, count how many suppliers tie at min(omega) and at max(omega)
tiebreak <- sc[, .(
  n_suppliers      = .N,
  min_omega        = min(int_omega),
  max_omega        = max(int_omega),
  n_tied_at_min    = sum(int_omega == min(int_omega)),
  n_tied_at_max    = sum(int_omega == max(int_omega))
), by = .(buyer, seller_nace4d)]

cat("\n  Distribution of n_tied_at_min (bot tie count):\n")
print(tiebreak[, .N, by = n_tied_at_min][order(n_tied_at_min)])
cat("\n  Distribution of n_tied_at_max (top tie count):\n")
print(tiebreak[, .N, by = n_tied_at_max][order(n_tied_at_max)])

cat(sprintf("\n  Cells where bot is decided by tiebreaker (n_tied_at_min >= 2): %d / %d (%.1f%%)\n",
            tiebreak[n_tied_at_min >= 2L, .N],
            tiebreak[, .N],
            100 * tiebreak[n_tied_at_min >= 2L, .N] / tiebreak[, .N]))
cat(sprintf("  Cells where top is decided by tiebreaker (n_tied_at_max >= 2): %d / %d (%.1f%%)\n",
            tiebreak[n_tied_at_max >= 2L, .N],
            tiebreak[, .N],
            100 * tiebreak[n_tied_at_max >= 2L, .N] / tiebreak[, .N]))

fwrite(tiebreak, file.path(OUTPUT_TAB,
       "phase4_within_intensive_pretrend_tiebreaker_prevalence.csv"))

# ---------------------------------------------------------------------------
# (ii) Hybrid A and Hybrid B cell construction
# ---------------------------------------------------------------------------
cat("\n[ii] Hybrid A / Hybrid B cell construction...\n")
cat("  Pre-window:", min(PRE_WINDOW), "-", max(PRE_WINDOW), "\n")
cat("  Omega window:", paste(OMEGA_WINDOW, collapse = ", "), "\n")

# Pre-window buyer-seller activity flags
pre_active <- b2b[year %in% PRE_WINDOW,
                  .(n_years_active = uniqueN(year),
                    pre_sales      = sum(sales)),
                  by = .(buyer, seller_nace4d, seller)]
n_pre_yrs <- length(PRE_WINDOW)

# Hybrid A flag = active in EVERY year of the pre-window
pre_active[, hybrid_a := n_years_active == n_pre_yrs]
# Hybrid B flag = active in ANY year of the pre-window (automatically true here
# since this row exists only if the pair had sales in some pre-window year)
pre_active[, hybrid_b := TRUE]

# Attach 2015-16 omega
omega_byvat <- fe[year %in% OMEGA_WINDOW,
                  .(omega_anchor = mean(omega_sh, na.rm = TRUE)),
                  by = vat]
pre_active <- merge(pre_active, omega_byvat,
                    by.x = "seller", by.y = "vat", all.x = TRUE)
pre_active[is.na(omega_anchor), omega_anchor := 0]

build_hybrid_cells <- function(active_dt, flag_col) {
  pool <- active_dt[get(flag_col) == TRUE]

  # Require >= 2 suppliers and at least one with omega > 0 in 2015-16
  cell_ok <- pool[, .(n = .N, max_omega = max(omega_anchor)),
                  by = .(buyer, seller_nace4d)][n >= 2L & max_omega > 0]
  pool <- merge(pool, cell_ok[, .(buyer, seller_nace4d)],
                by = c("buyer", "seller_nace4d"))

  # Top / bot from the 2015-16 omega ranking within the pre-window-active pool.
  # Tiebreaker: -pre_sales then seller (so top is highest-sales within ties,
  # bot is lowest-sales within ties; we will also report a no-sales-tiebreaker
  # variant below to assess sensitivity).
  setorder(pool, buyer, seller_nace4d, -omega_anchor, -pre_sales, seller)
  pool[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
  top_sup <- pool[rk == 1L,
                  .(buyer, seller_nace4d, top_supplier = seller,
                    omega_top = omega_anchor, pre_sales_top = pre_sales)]
  bot_sup <- pool[, .SD[.N], by = .(buyer, seller_nace4d)][,
                  .(buyer, seller_nace4d, bot_supplier = seller,
                    omega_bot = omega_anchor, pre_sales_bot = pre_sales)]
  cells <- merge(top_sup, bot_sup, by = c("buyer", "seller_nace4d"))
  cells
}

cells_a <- build_hybrid_cells(pre_active, "hybrid_a")
cells_b <- build_hybrid_cells(pre_active, "hybrid_b")
cat("  Hybrid A (continuous 2010-14): ", nrow(cells_a), " cells\n")
cat("  Hybrid B (any year 2010-14)  : ", nrow(cells_b), " cells\n")

# ---------------------------------------------------------------------------
# (iii) Long panel + trajectory mean for each hybrid
# ---------------------------------------------------------------------------
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

build_long <- function(cells_dt, label) {
  long <- rbind(
    cells_dt[, .(buyer, seller_nace4d, seller = top_supplier,
                 supplier_role = "top")],
    cells_dt[, .(buyer, seller_nace4d, seller = bot_supplier,
                 supplier_role = "bot")]
  )
  panel <- long[, .(year = YEAR_LO:YEAR_HI),
                by = .(buyer, seller_nace4d, seller, supplier_role)]
  panel <- merge(panel, yr_denom,
                 by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
  panel <- merge(panel, yr_sales,
                 by = c("buyer", "seller_nace4d", "seller", "year"),
                 all.x = TRUE)
  panel[is.na(sales), sales := 0]
  panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                            total_buyer_nace4d_spend <= 0,
                          NA_real_, sales / total_buyer_nace4d_spend)]
  panel[, hybrid := label]
  panel[]
}

panel_a <- build_long(cells_a, "Hybrid A (cells continuous 2010-14)")
panel_b <- build_long(cells_b, "Hybrid B (cells any-year 2010-14)")
panels  <- rbind(panel_a, panel_b)

traj <- panels[!is.na(share),
               .(mean_share = mean(share),
                 se_share   = sd(share) / sqrt(.N),
                 n_cells    = .N),
               by = .(hybrid, year, supplier_role)]
traj[, lo := mean_share - 1.96 * se_share]
traj[, hi := mean_share + 1.96 * se_share]
traj[, role_label := fcase(
  supplier_role == "top", "Most exposed supplier",
  supplier_role == "bot", "Least exposed supplier"
)]
traj[, role_label := factor(role_label,
                            levels = c("Most exposed supplier",
                                       "Least exposed supplier"))]

fwrite(traj, file.path(OUTPUT_TAB,
       "phase4_within_intensive_pretrend_hybrid_trajectory.csv"))

# Trajectory plot, both hybrids stacked
g_traj <- ggplot(traj,
                 aes(x = year, y = mean_share,
                     color = role_label, fill = role_label)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.4) +
  geom_vline(xintercept = TREAT_YEAR - 0.5,
             linetype = "dashed", color = "firebrick") +
  facet_wrap(~ hybrid, ncol = 1, scales = "free_y") +
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

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_pretrend_hybrid_trajectory.png"),
       g_traj, width = 9, height = 8, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_pretrend_hybrid_trajectory.pdf"),
       g_traj, width = 9, height = 8)

# Sample-size diagnostic per hybrid: n_cells contributing each year
sample_size <- panels[, .(
  n_with_observed = sum(!is.na(share)),
  n_with_positive = sum(!is.na(share) & share > 0)
), by = .(hybrid, year, supplier_role)]
fwrite(sample_size, file.path(OUTPUT_TAB,
       "phase4_within_intensive_pretrend_hybrid_sample_size.csv"))

ss_long <- melt(sample_size, id.vars = c("hybrid", "year", "supplier_role"),
                measure.vars = c("n_with_observed", "n_with_positive"),
                variable.name = "metric", value.name = "n_cells")
ss_long[, role_label := fcase(
  supplier_role == "top", "Most exposed supplier",
  supplier_role == "bot", "Least exposed supplier"
)]
ss_long[, metric_label := fcase(
  metric == "n_with_observed", "Cells with NACE-4d sourcing (denominator > 0)",
  metric == "n_with_positive", "Cells with positive sales from this seller"
)]

g_ss <- ggplot(ss_long,
               aes(x = year, y = n_cells,
                   color = role_label, linetype = metric_label)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.2) +
  facet_wrap(~ hybrid, ncol = 1, scales = "free_y") +
  scale_color_manual(values = c("Most exposed supplier"  = "firebrick",
                                 "Least exposed supplier" = "navy"),
                     name = NULL) +
  scale_linetype_manual(values = c(
    "Cells with NACE-4d sourcing (denominator > 0)" = "solid",
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
        legend.text      = element_text(size = 12),
        legend.box       = "vertical")

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_pretrend_hybrid_sample_size.png"),
       g_ss, width = 10, height = 8, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_pretrend_hybrid_sample_size.pdf"),
       g_ss, width = 10, height = 8)

cat("\nDone. Hybrid A/B trajectories and sample-size figures written.\n")
cat("  figures: ", OUTPUT_FIG, "\n")
cat("  tables : ", OUTPUT_TAB, "\n")
