###############################################################################
# phase4_within_intensive_attrition_calendar_did_sample.R
#
# PURPOSE
#   Calendar-time survival rate of buyer-seller pairs in the PRESENT-IN-
#   2010-14 sample (the same sample that powers the within-NACE-4d
#   intensive-margin DiD in phase4_within_intensive_did.R), separately for
#   top-omega and bot-pool sellers, tracked across 2011-2022.
#
#   WHY THIS FIGURE
#     The age-stratified attrition figure in phase4_within_intensive_
#     attrition_did.R shows a large level jump in survival rates between
#     pre-2017 and post-2017 observations at the same age. The jump is a
#     sample-construction artifact: the present-in-2010-14 sample requires
#     pairs to be alive in some year of 2015-16, which mechanically inflates
#     alive rates for observations inside or near that window (all PRE
#     observations) and leaves POST observations untouched. The calendar-
#     time view avoids the artifact: it shows smooth attrition over time,
#     with top and bot lines close together throughout the panel.
#
#   METHOD (staggered cohorts, mirror of phase4_within_intensive_attrition_
#   calendar.R but on the DiD sample, not Hybrid B):
#     For each pair in the present-in-2010-14 sample, t_start = first year
#     of positive sales in 2010-2014. Tracking starts one year after t_start,
#     floored at 2011. For each calendar year cy in 2011-2022:
#       denominator(cy) = pairs with t_start <= cy - 1 (eligible by cy)
#       numerator(cy)   = pairs in the denominator with positive sales at cy
#       survival(role, cy) = numerator / denominator within role
#     The denominator grows monotonically from 2011 to 2015 (all cohorts
#     eligible from 2015 onward), so pre-2017 vs post-2017 comparison is on
#     a stable denominator from 2015 onward.
#
#   Bootstrap CIs are cluster-bootstrapped on seller.
#
# OUTPUTS
#   - phase4_within_intensive_attrition_calendar_did_sample.{pdf,png}
#   - phase4_within_intensive_attrition_calendar_did_sample_survival.csv
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

YEAR_LO       <- 2002L
YEAR_HI       <- 2022L
PRE_WINDOW    <- 2010L:2014L
OMEGA_WIN     <- c(2015L, 2016L)
CAL_RANGE     <- 2011L:2022L
TREAT_YEAR    <- 2017L
B_BOOT        <- 500L
SEED_BOOT     <- 20260526L

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

# ---------------------------------------------------------------------------
# Build present-in-2010-14 sample with role assignment
# (identical to phase4_within_intensive_attrition_did.R)
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
pool[, role := fcase(
  rk == 1L,                       "top",
  omega_anchor == cell_min_omega, "bot",
  default                         = NA_character_
)]
pairs_with_role <- pool[!is.na(role),
                        .(buyer, seller_nace4d, seller, role)]
cat(sprintf("  Pairs: %d (%d top, %d bot)\n",
            nrow(pairs_with_role),
            pairs_with_role[role == "top", .N],
            pairs_with_role[role == "bot", .N]))

# t_start per pair = first year of positive sales in 2010-14
t_start_dt <- b2b[year %in% PRE_WINDOW,
                  .(t_start = min(year)),
                  by = .(buyer, seller_nace4d, seller)]
pairs_with_role <- merge(pairs_with_role, t_start_dt,
                         by = c("buyer", "seller_nace4d", "seller"))

# ---------------------------------------------------------------------------
# Build calendar-year panel: one row per (pair, calendar_year) for cy >=
# t_start, with active = 1 if positive sales at cy
# ---------------------------------------------------------------------------
cat("Building calendar-year alive panel...\n")
cal_long <- pairs_with_role[, .(calendar_year = CAL_RANGE),
                            by = .(buyer, seller_nace4d, seller, role, t_start)]
cal_long <- cal_long[calendar_year >= t_start + 1L]  # tracking starts t+1

b2b_active <- b2b[, .(buyer, seller_nace4d, seller,
                      calendar_year = year, active = 1L)]
cal_long <- merge(cal_long, b2b_active,
                  by = c("buyer", "seller_nace4d", "seller", "calendar_year"),
                  all.x = TRUE)
cal_long[is.na(active), active := 0L]

# Point estimates: mean active per (role, calendar_year)
surv_pt <- cal_long[, .(survival = mean(active),
                        n_pairs  = .N,
                        n_sellers = uniqueN(seller)),
                    by = .(role, calendar_year)]
setorder(surv_pt, role, calendar_year)
cat("\n--- Calendar-time survival rates ---\n")
print(dcast(surv_pt[, .(role, calendar_year, survival)],
            calendar_year ~ role, value.var = "survival"))

# ---------------------------------------------------------------------------
# Cluster-bootstrap CIs on seller
# ---------------------------------------------------------------------------
cat(sprintf("\nBootstrapping CIs (B = %d, clustered on seller)...\n", B_BOOT))
sellers_all <- unique(cal_long$seller)
n_s <- length(sellers_all)
set.seed(SEED_BOOT)

boot_rows <- vector("list", B_BOOT)
for (b in seq_len(B_BOOT)) {
  draw <- sample(sellers_all, n_s, replace = TRUE)
  draw_tbl <- data.table(seller = draw, draw_id = seq_along(draw))
  sub <- merge(cal_long, draw_tbl, by = "seller", allow.cartesian = TRUE)
  boot_rows[[b]] <- sub[, .(survival = mean(active)),
                       by = .(role, calendar_year)][, b_iter := b]
  if (b %% 100L == 0L) cat(sprintf("  bootstrap %d / %d\n", b, B_BOOT))
}
boot_df <- rbindlist(boot_rows, use.names = TRUE)

bands <- boot_df[, .(lo = quantile(survival, 0.025),
                     hi = quantile(survival, 0.975)),
                 by = .(role, calendar_year)]
surv_pt <- merge(surv_pt, bands, by = c("role", "calendar_year"))

fwrite(surv_pt, file.path(OUTPUT_TAB,
       "phase4_within_intensive_attrition_calendar_did_sample_survival.csv"))

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------
surv_pt[, role_label := fcase(
  role == "top", "Most exposed supplier",
  role == "bot", "Least exposed supplier"
)]
surv_pt[, role_label := factor(role_label,
                               levels = c("Most exposed supplier",
                                          "Least exposed supplier"))]

g <- ggplot(surv_pt,
            aes(x = calendar_year, y = survival,
                color = role_label, fill = role_label)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, color = NA) +
  geom_line(linewidth = 1.0) +
  geom_point(size = 2) +
  geom_vline(xintercept = TREAT_YEAR - 0.5,
             linetype = "dashed", color = "firebrick") +
  scale_x_continuous(breaks = seq(min(CAL_RANGE), max(CAL_RANGE), by = 1)) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                     limits = c(0, 1)) +
  scale_color_manual(values = c("Most exposed supplier" = "firebrick",
                                "Least exposed supplier" = "navy"),
                     name = NULL) +
  scale_fill_manual(values = c("Most exposed supplier" = "firebrick",
                               "Least exposed supplier" = "navy"),
                    name = NULL) +
  labs(x = NULL,
       y = "Survival rate (eligible pairs with positive sales that year)") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 18, margin = margin(r = 14)),
        axis.text        = element_text(size = 16),
        axis.text.x      = element_text(angle = 45, hjust = 1),
        legend.position  = "bottom",
        legend.text      = element_text(size = 16))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_attrition_calendar_did_sample.png"),
       g, width = 9, height = 6, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_attrition_calendar_did_sample.pdf"),
       g, width = 9, height = 6)

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")
