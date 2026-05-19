###############################################################################
# phase4_within_intensive_attrition_calendar.R
#
# PURPOSE
#   Calendar-year survival rate of buyer-seller pairs in the Hybrid B cell
#   pool, separately for top-ω and ω=0 suppliers, tracked across 2011-2022.
#   Companion to phase4_within_intensive_attrition_diagnostic.R (which does
#   the pre-policy-only stacked-cohort version).
#
#   Method (staggered cohorts):
#     For each Hybrid B pool pair, t_start = first year of positive sales
#     in 2010-2014 (Hybrid B requires activity in that window). Tracking
#     starts one year after t_start, with the floor at 2011.
#     For each calendar year cy in 2011-2022:
#       denominator(cy) = pairs with t_start <= cy - 1 (eligible by cy)
#       numerator(cy)   = pairs in the denominator with positive sales at cy
#       survival(role, cy) = numerator / denominator within role
#     Note: denominator grows monotonically from 2011 (only 2010-starters)
#     to 2015 (all pairs eligible) and stays fixed thereafter. So pre-2017
#     vs post-2017 comparison is on a stable denominator from 2015 onward.
#
#     If the gap and its slope are the same in 2011-2016 as in 2017-2022,
#     the attrition difference between top and bot is structural and not
#     caused by the MSR price hike. If the gap widens or the top pulls
#     away from the bot after 2017, the MSR has caused differential
#     attrition and the conditional-PT assumption underpinning the
#     symmetric survivorship filter is questionable.
#
#   Bootstrap CIs are cluster-bootstrapped on seller.
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

YEAR_LO       <- 2002L
YEAR_HI       <- 2022L
PRE_WINDOW    <- 2010L:2014L
OMEGA_WIN     <- c(2015L, 2016L)
START_RANGE   <- 2010L:2014L      # pre-window for first-active-year
CAL_RANGE     <- 2011L:2022L      # calendar years to track
TREAT_YEAR    <- 2017L
B_BOOT        <- 500L
SEED_BOOT     <- 20260518L

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
# Hybrid B pool + role assignment
# ---------------------------------------------------------------------------
cat("Building Hybrid B pool + role assignment...\n")
pre_active <- b2b[year %in% PRE_WINDOW,
                  .(pre_sales = sum(sales)),
                  by = .(buyer, seller_nace4d, seller)]
omega_byvat <- fe[year %in% OMEGA_WIN,
                  .(omega_anchor = mean(omega_sh, na.rm = TRUE)),
                  by = vat]
pre_active <- merge(pre_active, omega_byvat,
                    by.x = "seller", by.y = "vat", all.x = TRUE)
pre_active[is.na(omega_anchor), omega_anchor := 0]

cell_ok <- pre_active[, .(n = .N, max_omega = max(omega_anchor)),
                      by = .(buyer, seller_nace4d)][n >= 2L & max_omega > 0]
pool <- merge(pre_active, cell_ok[, .(buyer, seller_nace4d)],
              by = c("buyer", "seller_nace4d"))

setorder(pool, buyer, seller_nace4d, -omega_anchor, -pre_sales, seller)
pool[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
pool[, role := fcase(
  rk == 1L,           "top",
  omega_anchor == 0,  "bot",
  default = NA_character_
)]
pool <- pool[!is.na(role)]

# ---------------------------------------------------------------------------
# Per-pair t_start: first year of positive sales in 2010-2014
# ---------------------------------------------------------------------------
t_start <- b2b[year %in% START_RANGE,
               .(t_start = min(year)),
               by = .(buyer, seller_nace4d, seller)]
cohort <- merge(pool[, .(buyer, seller_nace4d, seller, role)],
                t_start,
                by = c("buyer", "seller_nace4d", "seller"))
cat(sprintf("  Hybrid B pool pairs with a t_start in 2010-14: %d (%d top, %d bot)\n",
            nrow(cohort),
            cohort[role == "top", .N],
            cohort[role == "bot", .N]))
cat("  t_start distribution:\n")
print(cohort[, .N, by = .(role, t_start)][order(role, t_start)])

# ---------------------------------------------------------------------------
# Staggered calendar-year survival
#   For each calendar year cy:
#     denominator = pairs with t_start <= cy - 1
#     numerator   = pairs in denominator with positive sales at cy
# ---------------------------------------------------------------------------
cat("Computing staggered calendar-year survival...\n")
calendar_rows <- list()
for (cy in CAL_RANGE) {
  elig <- cohort[t_start <= cy - 1L]
  if (nrow(elig) == 0L) next
  active_cy <- b2b[year == cy & sales > 0,
                   .(buyer, seller_nace4d, seller, active = 1L)]
  df <- merge(elig, active_cy,
              by = c("buyer", "seller_nace4d", "seller"), all.x = TRUE)
  df[is.na(active), active := 0L]
  df[, calendar_year := cy]
  calendar_rows[[as.character(cy)]] <- df
}
cal_long <- rbindlist(calendar_rows, use.names = TRUE)

# Point estimates
surv_pt <- cal_long[, .(survival   = mean(active),
                         n_pairs    = .N,
                         n_sellers  = uniqueN(seller)),
                    by = .(role, calendar_year)]

cat("\n--- Calendar-year survival rate by role ---\n")
print(dcast(surv_pt, calendar_year ~ role, value.var = "survival"))

# ---------------------------------------------------------------------------
# Bootstrap (cluster on seller)
# ---------------------------------------------------------------------------
cat(sprintf("\nBootstrapping CIs (cluster on seller, B = %d)...\n", B_BOOT))
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
  if (b %% 50L == 0L) cat(sprintf("  bootstrap %d / %d\n", b, B_BOOT))
}
boot_df <- rbindlist(boot_rows, use.names = TRUE)

bands <- boot_df[, .(lo = quantile(survival, 0.025),
                     hi = quantile(survival, 0.975)),
                 by = .(role, calendar_year)]
surv_pt <- merge(surv_pt, bands, by = c("role", "calendar_year"))

fwrite(surv_pt, file.path(OUTPUT_TAB,
       "phase4_within_intensive_attrition_calendar_survival.csv"))

# ---------------------------------------------------------------------------
# Pre/post-2017 gap test: difference in (top - bot) survival levels and
# differences in (top - bot) slopes between the two halves of the window.
# This is a quick numeric summary; the figure is the main artifact.
# ---------------------------------------------------------------------------
gap_dt <- dcast(surv_pt[, .(role, calendar_year, survival)],
                calendar_year ~ role, value.var = "survival")
setnames(gap_dt, c("calendar_year", "bot", "top"),
                  c("calendar_year", "survival_bot", "survival_top"))
gap_dt[, gap_top_minus_bot := survival_top - survival_bot]
gap_dt[, period := fifelse(calendar_year < TREAT_YEAR, "pre", "post")]
period_summary <- gap_dt[, .(
  mean_gap          = mean(gap_top_minus_bot),
  mean_survival_top = mean(survival_top),
  mean_survival_bot = mean(survival_bot),
  n_years           = .N
), by = period]

cat("\n--- Pre vs post 2017 summary ---\n")
print(period_summary)
fwrite(gap_dt, file.path(OUTPUT_TAB,
       "phase4_within_intensive_attrition_calendar_gap.csv"))

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------
surv_pt[, role_label := fcase(
  role == "top", "Most exposed supplier",
  role == "bot", "Least exposed (ω=0)"
)]
surv_pt[, role_label := factor(role_label,
                               levels = c("Most exposed supplier",
                                          "Least exposed (ω=0)"))]

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
                                 "Least exposed (ω=0)"  = "navy"),
                     name = NULL) +
  scale_fill_manual(values = c("Most exposed supplier" = "firebrick",
                                "Least exposed (ω=0)"  = "navy"),
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
       "phase4_within_intensive_attrition_calendar_survival.png"),
       g, width = 9, height = 6, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_attrition_calendar_survival.pdf"),
       g, width = 9, height = 6)

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")
