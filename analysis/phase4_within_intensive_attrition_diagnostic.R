###############################################################################
# phase4_within_intensive_attrition_diagnostic.R
#
# PURPOSE
#   Test whether top-ω and ω=0 suppliers have structurally different attrition
#   rates in the pre-policy window 2010-2016. If yes, the attrition-driven
#   widening of the top-bot gap we observe in the Hybrid B + portfolio bot
#   trajectory cannot be MSR-driven by construction, and the conditional-PT
#   assumption underpinning the symmetric survivorship filter is grounded.
#
#   Method: stacked cohorts within 2010-2016 (entirely pre-policy).
#     For each base year t in 2010-2014, take all (buyer, NACE-4d, seller)
#     pairs in the Hybrid B cell pool that are active at t. Classify each
#     pair as either:
#       top  -- the seller is the highest-omega supplier in its cell
#                (omega measured 2015-16)
#       bot  -- the seller has omega=0 in 2015-16 and is in its cell's pool
#     For each horizon h = 1, 2, ..., (2016 - t), check if the pair is
#     active at year t + h (positive sales).
#
#     Stack all cohorts and compute:
#       S(role, h) = mean over (cohort, pair) of 1[active at t+h]
#
#     Bands: cluster-bootstrap on seller (so the same seller appearing
#     in multiple cohorts / cells is treated as one draw).
#
#   No post-policy data enters the horizons. Any divergence between
#   S(top, h) and S(bot, h) is by construction structural, not MSR-driven.
#
# DEPENDENCIES (same as phase4_within_intensive_pretrend_hybridB_final.R)
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

YEAR_LO    <- 2002L
YEAR_HI    <- 2022L
PRE_WINDOW <- 2010L:2014L
OMEGA_WIN  <- c(2015L, 2016L)
COHORT_YRS <- 2010L:2014L
HORIZON_HI <- 2016L
B_BOOT     <- 500L           # cluster-bootstrap iterations
SEED_BOOT  <- 20260518L

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
# Hybrid B pool (same construction as the trajectory scripts)
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

# Role assignment within each cell
setorder(pool, buyer, seller_nace4d, -omega_anchor, -pre_sales, seller)
pool[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
pool[, role := fcase(
  rk == 1L,                           "top",     # highest omega in cell
  omega_anchor == 0,                  "bot",     # any omega=0 supplier
  default = NA_character_
)]
pool <- pool[!is.na(role)]
cat(sprintf("  Pool size: %d pairs (%d top, %d bot)\n",
            nrow(pool),
            nrow(pool[role == "top"]),
            nrow(pool[role == "bot"])))

# ---------------------------------------------------------------------------
# Pair-year activity matrix on 2010-2016 (positive sales == active)
# ---------------------------------------------------------------------------
pair_active <- b2b[year %between% c(min(COHORT_YRS), HORIZON_HI),
                   .(buyer, seller_nace4d, seller, year)]
pair_active[, active := 1L]

pair_active <- merge(pool[, .(buyer, seller_nace4d, seller, role)],
                     pair_active,
                     by = c("buyer", "seller_nace4d", "seller"),
                     all.x = TRUE)
pair_active <- pair_active[!is.na(year)]

# ---------------------------------------------------------------------------
# Stacked-cohort survival
# ---------------------------------------------------------------------------
cat("Building stacked cohorts...\n")
cohorts <- list()
for (t0 in COHORT_YRS) {
  base <- pair_active[year == t0,
                      .(buyer, seller_nace4d, seller, role)]
  if (nrow(base) == 0L) next
  for (h in seq_len(HORIZON_HI - t0)) {
    surv_year <- t0 + h
    surv <- pair_active[year == surv_year,
                        .(buyer, seller_nace4d, seller, alive = 1L)]
    df <- merge(base, surv,
                by = c("buyer", "seller_nace4d", "seller"), all.x = TRUE)
    df[is.na(alive), alive := 0L]
    df[, cohort_year := t0]
    df[, horizon := h]
    cohorts[[length(cohorts) + 1L]] <- df
  }
}
surv_long <- rbindlist(cohorts, use.names = TRUE)
cat(sprintf("  Stacked cohort rows: %s\n",
            format(nrow(surv_long), big.mark = ",")))

# Point estimates: S(role, h) = mean(alive | role, horizon)
surv_pt <- surv_long[, .(survival   = mean(alive),
                          n_pairs    = .N,
                          n_sellers  = uniqueN(seller)),
                     by = .(role, horizon)]

cat("\n--- Survival rate by role × horizon (pooled across cohorts) ---\n")
print(dcast(surv_pt, horizon ~ role,
            value.var = c("survival", "n_pairs", "n_sellers")))

# ---------------------------------------------------------------------------
# Cluster-bootstrap on seller for CIs (B_BOOT iterations)
# ---------------------------------------------------------------------------
cat(sprintf("Bootstrapping CIs (cluster on seller, B = %d)...\n", B_BOOT))
sellers_all <- unique(surv_long$seller)
n_s <- length(sellers_all)
set.seed(SEED_BOOT)

boot_rows <- vector("list", B_BOOT)
for (b in seq_len(B_BOOT)) {
  draw <- sample(sellers_all, n_s, replace = TRUE)
  draw_tbl <- data.table(seller = draw, draw_id = seq_along(draw))
  # match each drawn seller back to all their rows
  sub <- merge(surv_long, draw_tbl, by = "seller", allow.cartesian = TRUE)
  boot_rows[[b]] <- sub[, .(survival = mean(alive)),
                       by = .(role, horizon)][, b_iter := b]
  if (b %% 50L == 0L) cat(sprintf("  bootstrap %d / %d\n", b, B_BOOT))
}
boot_df <- rbindlist(boot_rows, use.names = TRUE)

bands <- boot_df[, .(lo = quantile(survival, 0.025),
                     hi = quantile(survival, 0.975)),
                 by = .(role, horizon)]
surv_pt <- merge(surv_pt, bands, by = c("role", "horizon"))

fwrite(surv_pt, file.path(OUTPUT_TAB,
       "phase4_within_intensive_attrition_pre_policy_survival.csv"))

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
            aes(x = horizon, y = survival,
                color = role_label, fill = role_label)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, color = NA) +
  geom_line(linewidth = 1.0) +
  geom_point(size = 2) +
  scale_x_continuous(breaks = 1:(HORIZON_HI - min(COHORT_YRS))) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                     limits = c(0, 1)) +
  scale_color_manual(values = c("Most exposed supplier" = "firebrick",
                                 "Least exposed (ω=0)"  = "navy"),
                     name = NULL) +
  scale_fill_manual(values = c("Most exposed supplier" = "firebrick",
                                "Least exposed (ω=0)"  = "navy"),
                    name = NULL) +
  labs(x = "Years after cohort base year (pre-policy window 2010-2016)",
       y = "Survival rate (pair active at cohort + h)") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title       = element_text(size = 18),
        axis.title.x     = element_text(margin = margin(t = 14)),
        axis.title.y     = element_text(margin = margin(r = 14)),
        axis.text        = element_text(size = 16),
        legend.position  = "bottom",
        legend.text      = element_text(size = 16))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_attrition_pre_policy_survival.png"),
       g, width = 8, height = 6, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_attrition_pre_policy_survival.pdf"),
       g, width = 8, height = 6)

# ---------------------------------------------------------------------------
# Diagnostic table: per-cohort survival (so you can verify the pooling)
# ---------------------------------------------------------------------------
per_cohort <- surv_long[, .(survival = mean(alive),
                            n_pairs  = .N),
                        by = .(role, cohort_year, horizon)]
fwrite(per_cohort, file.path(OUTPUT_TAB,
       "phase4_within_intensive_attrition_per_cohort_survival.csv"))

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")
