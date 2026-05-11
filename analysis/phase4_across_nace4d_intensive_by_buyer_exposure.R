###############################################################################
# phase4_across_nace4d_intensive_by_buyer_exposure.R
#
# PURPOSE
#   Heterogeneity #2 on across-NACE4d intensive margin: bin buyers by their
#   pre-period exposure to high-shortage ETS-NACE4d, and plot the share of
#   B2B expenditure on high-shortage ETS-NACE4d over time, per quartile.
#
#   The hypothesis under leakage is that highly exposed buyers should reduce
#   their share faster than minimally exposed buyers. Pre-period = 2008-2012
#   (Phase II; same window as the sector-shortage ranking).
#
#   Buyer pre-period exposure:
#       expo_j = sum_{t in 2008-12, n in high_ets} spend(j, n, t)
#              / sum_{t in 2008-12}                spend(j, t)
#   where high_ets = NACE4d with positive pre-period net shortage (omega_n > 0),
#   defined exactly as in phase4_across_nace4d_intensive_by_shortage.R.
#
#   Buyers are partitioned into four exposure quartiles (Q1 lowest, Q4
#   highest). Buyers active in B2B but with no pre-period data are dropped
#   (cannot be ranked).
#
#   For each (quartile q, year t):
#       share_qt = mean across buyers in q of spend on high-ETS / total spend
#                  in year t
#   plotted with 95% bootstrap CI.
#
# OUTPUTS
#   - phase4_across_nace4d_intensive_by_buyer_exposure.{png,pdf}
#   - phase4_across_nace4d_intensive_by_buyer_exposure.csv
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

set.seed(20260511)

YEAR_LO          <- 2005L
YEAR_HI          <- 2022L
PRE_YEARS        <- 2008L:2012L
MIN_FIRM_YRS_PRE <- 2L
N_BOOT           <- 1000L

# ---------------------------------------------------------------------------
# 1. Load data
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
  vat = as.character(vat_ano),
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(vat = as.character(vat),
                                       year = as.integer(year),
                                       nace4d, shortage, total_cost)]
rm(firm_exposure)

# ---------------------------------------------------------------------------
# 2. NACE4d high-shortage set (same as plot #1)
# ---------------------------------------------------------------------------
cat("\nDefining high-shortage ETS-NACE4d on", paste(range(PRE_YEARS), collapse = "-"), "...\n")

fe_pre <- fe[year %in% PRE_YEARS &
             !is.na(shortage) & !is.na(total_cost) & total_cost > 0]
nace4d_shortage <- fe_pre[, .(
  n_obs_pre     = .N,
  sum_shortage  = sum(shortage),
  sum_totalcost = sum(total_cost)
), by = nace4d]
nace4d_shortage[, omega_nace4d := sum_shortage / sum_totalcost]
nace4d_ranked <- nace4d_shortage[n_obs_pre >= MIN_FIRM_YRS_PRE & !is.na(omega_nace4d)]
high_set <- nace4d_ranked[omega_nace4d > 0, unique(nace4d)]

cat(sprintf("  high-shortage ETS-NACE4d (omega > 0): %d\n", length(high_set)))

# ---------------------------------------------------------------------------
# 3. Tag B2B by seller NACE4d, mark high-shortage flag
# ---------------------------------------------------------------------------
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b[, is_high := as.integer(!is.na(seller_nace4d) & seller_nace4d %in% high_set)]

# ---------------------------------------------------------------------------
# 4. Buyer pre-period exposure -> quartile
# ---------------------------------------------------------------------------
cat("\nComputing buyer pre-period exposure...\n")
buyer_pre <- b2b[year %in% PRE_YEARS, .(
  pre_spend_high = sum(sales * is_high),
  pre_spend_tot  = sum(sales)
), by = buyer]
buyer_pre <- buyer_pre[pre_spend_tot > 0]
buyer_pre[, expo := pre_spend_high / pre_spend_tot]

# Zero-exposure buyers form a >50% point mass, so naive quartiles collapse.
# Use Q0 (zero exposure) + tertile split of strictly positive-exposure buyers.
buyer_pre[, expo_q := NA_integer_]
buyer_pre[expo == 0, expo_q := 0L]
pos_breaks <- quantile(buyer_pre[expo > 0, expo], probs = c(0, 1/3, 2/3, 1),
                       na.rm = TRUE)
buyer_pre[expo > 0,
          expo_q := as.integer(cut(expo, breaks = pos_breaks,
                                   include.lowest = TRUE, labels = FALSE))]
buyer_pre[, expo_q := factor(expo_q,
                             levels = 0:3,
                             labels = c("Q0 (zero expo)",
                                        "Q1 (low expo)",
                                        "Q2 (mid expo)",
                                        "Q3 (high expo)"))]

cat("  expo quantiles (positive-exposure buyers only):\n")
print(pos_breaks)
cat("  buyers per quartile:\n")
print(buyer_pre[, .N, by = expo_q][order(expo_q)])

# ---------------------------------------------------------------------------
# 5. Buyer-year share on high-shortage ETS-NACE4d
# ---------------------------------------------------------------------------
buyer_year <- b2b[, .(spend_high = sum(sales * is_high),
                      spend_tot  = sum(sales)),
                  by = .(buyer, year)]
buyer_year <- buyer_year[spend_tot > 0]
buyer_year[, share_high := spend_high / spend_tot]

# Attach quartile and keep only buyers with a quartile assignment
buyer_year <- merge(buyer_year, buyer_pre[, .(buyer, expo_q)], by = "buyer")

# ---------------------------------------------------------------------------
# 6. Per-quartile per-year aggregates
# ---------------------------------------------------------------------------
boot_ci <- function(x, n_boot = N_BOOT, alpha = 0.05) {
  x <- x[!is.na(x)]
  if (length(x) < 5L) return(list(lo = NA_real_, hi = NA_real_))
  m <- length(x)
  draws <- replicate(n_boot, mean(x[sample.int(m, m, replace = TRUE)]))
  q <- quantile(draws, c(alpha / 2, 1 - alpha / 2), names = FALSE)
  list(lo = q[1], hi = q[2])
}

pooled <- buyer_year[, {
  ci <- boot_ci(share_high)
  .(n_buyers       = .N,
    mean_share     = mean(share_high),
    aggregate_share = sum(spend_high) / sum(spend_tot),
    ci_lo          = ci$lo,
    ci_hi          = ci$hi)
}, by = .(expo_q, year)]
setorder(pooled, expo_q, year)

fwrite(pooled,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_intensive_by_buyer_exposure.csv"))

cat("\nMean share on high-shortage ETS, by exposure quartile x year:\n")
print(dcast(pooled, year ~ expo_q, value.var = "mean_share"))

# ---------------------------------------------------------------------------
# 7. Plot
# ---------------------------------------------------------------------------
quartile_colors <- c("Q0 (zero expo)"  = "#cccccc",
                     "Q1 (low expo)"   = "#fdbb84",
                     "Q2 (mid expo)"   = "#e34a33",
                     "Q3 (high expo)"  = "#b30000")

base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom")

p <- ggplot(pooled, aes(x = year, color = expo_q, fill = expo_q)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.15, color = NA) +
  geom_line(aes(y = mean_share), linewidth = 0.85) +
  geom_point(aes(y = mean_share), size = 1.2) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, NA),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = quartile_colors,
                     name = "Pre-period exposure quartile") +
  scale_fill_manual (values = quartile_colors,
                     name = "Pre-period exposure quartile") +
  labs(title    = "Across-NACE4d intensive margin: buyer share on high-shortage ETS-NACE4d, by exposure quartile",
       subtitle = "Buyers binned by 2008-12 share of B2B spend on high-shortage ETS-NACE4d. Mean across buyers per quartile-year (95% bootstrap CI).",
       x = NULL,
       y = "Share of buyer's B2B expenditure on high-shortage ETS-NACE4d") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_intensive_by_buyer_exposure.png"),
       p, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_intensive_by_buyer_exposure.pdf"),
       p, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
