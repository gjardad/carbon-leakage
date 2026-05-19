###############################################################################
# phase4_within_intensive_attrition_did.R
#
# PURPOSE
#   Survival DiD with age fixed effects on the present-in-2010-14 sample.
#   Tests whether top-omega and lowest-omega suppliers have differential
#   post-2017 attrition AFTER controlling for the age of the relationship.
#
#   Sample: same as phase4_within_intensive_pretrend_present_in_2010_14.R
#     - Pair active in some year of 2010-14 AND some year of 2015-16.
#     - Cell has >= 2 suppliers, max_omega > 0, min_omega < max_omega.
#     - top = highest-omega supplier in cell.
#     - bot pool = all suppliers tied at cell's min omega.
#
#   Alive panel: for each pair p in {top, bot pool} and each year t in
#     (t_start_p, ..., 2022), an indicator alive_{p,t} = 1[positive sales].
#     t_start_p = first year of positive sales in the pre-window 2010-14.
#     age_{p,t} = t - t_start_p.
#
#   Regression (LP model on the alive indicator):
#
#     alive_{p,t} = alpha_{cell, role} + delta_age + lambda_year
#                 + gamma * (post_t * group_top_p) + epsilon_{p,t}
#
#     post_t       = 1[t >= 2017]
#     group_top_p  = 1 if pair is top
#     Clustered on seller.
#
#   gamma identifies the differential change in survival probability
#   for top vs bot after 2017, holding cell, role, age, and year fixed.
#
#   gamma is identified from variation across (age, year) cells with both
#   pre- and post-2017 observations. In this sample those are ages 3-6
#   (cohort 2010-14 gives ages 1-2 pre only, ages 7+ post only).
#
#   Visual companion: age-stratified survival rates, separately by group
#   and by pre/post period.
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(fixest)
})

set.seed(20260519)

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

# ---------------------------------------------------------------------------
# Build present-in-2010-14 sample with role assignment
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

# ---------------------------------------------------------------------------
# Find t_start per pair (first year of positive sales in 2010-14)
# ---------------------------------------------------------------------------
t_start_dt <- b2b[year %in% PRE_WINDOW,
                   .(t_start = min(year)),
                   by = .(buyer, seller_nace4d, seller)]
pairs_with_role <- merge(pairs_with_role, t_start_dt,
                         by = c("buyer", "seller_nace4d", "seller"))
cat("  t_start distribution by role:\n")
print(pairs_with_role[, .N, by = .(role, t_start)][order(role, t_start)])

# ---------------------------------------------------------------------------
# Build long alive panel
# ---------------------------------------------------------------------------
cat("Building long alive panel...\n")
panel <- pairs_with_role[, .(year = (t_start + 1L):YEAR_HI),
                          by = .(buyer, seller_nace4d, seller, role, t_start)]
panel[, age := year - t_start]

# Merge in alive indicator
b2b_active <- b2b[, .(buyer, seller_nace4d, seller, year, alive = 1L)]
panel <- merge(panel, b2b_active,
               by = c("buyer", "seller_nace4d", "seller", "year"),
               all.x = TRUE)
panel[is.na(alive), alive := 0L]

panel[, group_top    := as.integer(role == "top")]
panel[, post         := as.integer(year >= TREAT_YEAR)]
panel[, post_top     := post * group_top]
panel[, cell_role_id := paste(buyer, seller_nace4d, role, sep = "::")]
cat(sprintf("  Long panel rows: %s\n",
            format(nrow(panel), big.mark = ",")))

# ---------------------------------------------------------------------------
# Survival DiD regression
# ---------------------------------------------------------------------------
cat("\nRunning survival DiD regression (LP model, alive on post:top)...\n")
mod <- feols(alive ~ post_top | cell_role_id + age + year,
             data = panel, cluster = ~ seller, notes = FALSE)
cat("\n--- Regression summary ---\n")
print(summary(mod))

# Write the coefficient table
coef_tbl <- as.data.table(coeftable(mod))
coef_tbl[, term := "post_top"]
fwrite(coef_tbl, file.path(OUTPUT_TAB,
       "phase4_within_intensive_attrition_did_coef.csv"))

# A version WITHOUT age FE -- so the user can see how much age controls move γ
cat("\n--- Same regression without age FE (for comparison) ---\n")
mod_noage <- feols(alive ~ post_top | cell_role_id + year,
                   data = panel, cluster = ~ seller, notes = FALSE)
print(summary(mod_noage))

# ---------------------------------------------------------------------------
# Age-stratified survival, by role and period
# ---------------------------------------------------------------------------
cat("\nBuilding age-stratified survival figure...\n")
panel[, period := fifelse(year < TREAT_YEAR, "pre", "post")]
panel[, period := factor(period, levels = c("pre", "post"))]

age_stratified <- panel[, .(survival = mean(alive),
                             n_pairs  = .N),
                        by = .(role, age, period)]
age_stratified[, role_label := fcase(
  role == "top", "Most exposed supplier",
  role == "bot", "Least exposed supplier"
)]
age_stratified[, period_label := fcase(
  period == "pre",  "Pre-policy (year < 2017)",
  period == "post", "Post-policy (year >= 2017)"
)]
fwrite(age_stratified, file.path(OUTPUT_TAB,
       "phase4_within_intensive_attrition_did_age_stratified.csv"))

cat("--- Age-stratified survival rates ---\n")
print(dcast(age_stratified,
            age + role ~ period, value.var = "survival"))

g <- ggplot(age_stratified,
            aes(x = age, y = survival,
                color = role_label, linetype = period_label,
                shape = period_label)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  scale_x_continuous(breaks = seq(1, 12, by = 1)) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                     limits = c(0, 1)) +
  scale_color_manual(values = c("Most exposed supplier" = "firebrick",
                                 "Least exposed supplier" = "navy"),
                     name = NULL) +
  scale_linetype_manual(values = c("Pre-policy (year < 2017)"  = "solid",
                                    "Post-policy (year >= 2017)" = "dashed"),
                         name = NULL) +
  scale_shape_manual(values = c("Pre-policy (year < 2017)"  = 16,
                                 "Post-policy (year >= 2017)" = 17),
                      name = NULL) +
  labs(x = "Age of buyer-seller relationship (years since first observed)",
       y = "Survival rate (positive sales at this age)") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title       = element_text(size = 18),
        axis.title.x     = element_text(margin = margin(t = 14)),
        axis.title.y     = element_text(margin = margin(r = 14)),
        axis.text        = element_text(size = 16),
        legend.position  = "bottom",
        legend.text      = element_text(size = 14),
        legend.box       = "vertical")

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_attrition_did_age_stratified.png"),
       g, width = 9, height = 6.5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_attrition_did_age_stratified.pdf"),
       g, width = 9, height = 6.5)

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")
