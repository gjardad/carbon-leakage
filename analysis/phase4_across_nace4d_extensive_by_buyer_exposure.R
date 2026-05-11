###############################################################################
# phase4_across_nace4d_extensive_by_buyer_exposure.R
#
# PURPOSE
#   Extensive-margin twin of phase4_across_nace4d_intensive_by_buyer_exposure.R.
#   Two outcomes per (buyer pre-period exposure quartile, year):
#
#     A) Share of buyers in the quartile that buy from at least one
#        high-shortage ETS-NACE4d seller in year t.
#     B) Mean count of distinct high-shortage ETS-NACE4d sectors per buyer
#        in the quartile (zero-filled for buyers who buy from none).
#
#   Buyer exposure quartiles follow plot #2 exactly: Q0 (zero pre-period
#   exposure point mass) + tertiles of strictly-positive exposure (Q1/Q2/Q3).
#   Pre-period = 2008-2012; high-shortage ETS-NACE4d = sectors with positive
#   2008-12 omega.
#
#   The pre-period values for Q0/Q3 are mechanical by construction; the
#   informative comparison is the post-period evolution of Q3 (high-exposure
#   buyers) -- if reallocation is happening, Q3's share/count should fall.
#
# OUTPUTS
#   - phase4_across_nace4d_extensive_by_buyer_exposure_share.{png,pdf}
#   - phase4_across_nace4d_extensive_by_buyer_exposure_count.{png,pdf}
#   - phase4_across_nace4d_extensive_by_buyer_exposure.csv
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
# 2. High-shortage ETS-NACE4d set
# ---------------------------------------------------------------------------
fe_pre <- fe[year %in% PRE_YEARS &
             !is.na(shortage) & !is.na(total_cost) & total_cost > 0]
nace4d_shortage <- fe_pre[, .(n_obs_pre     = .N,
                              sum_shortage  = sum(shortage),
                              sum_totalcost = sum(total_cost)), by = nace4d]
nace4d_shortage[, omega_nace4d := sum_shortage / sum_totalcost]
high_set <- nace4d_shortage[n_obs_pre >= MIN_FIRM_YRS_PRE & omega_nace4d > 0,
                            unique(nace4d)]
cat(sprintf("  high-shortage ETS-NACE4d: %d\n", length(high_set)))

seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b[, is_high := as.integer(!is.na(seller_nace4d) & seller_nace4d %in% high_set)]

# ---------------------------------------------------------------------------
# 3. Buyer pre-period exposure -> quartile (same as plot #2 intensive)
# ---------------------------------------------------------------------------
buyer_pre <- b2b[year %in% PRE_YEARS, .(
  pre_spend_high = sum(sales * is_high),
  pre_spend_tot  = sum(sales)
), by = buyer]
buyer_pre <- buyer_pre[pre_spend_tot > 0]
buyer_pre[, expo := pre_spend_high / pre_spend_tot]

buyer_pre[, expo_q := NA_integer_]
buyer_pre[expo == 0, expo_q := 0L]
pos_breaks <- quantile(buyer_pre[expo > 0, expo], probs = c(0, 1/3, 2/3, 1),
                       na.rm = TRUE)
buyer_pre[expo > 0,
          expo_q := as.integer(cut(expo, breaks = pos_breaks,
                                   include.lowest = TRUE, labels = FALSE))]
buyer_pre[, expo_lab := factor(expo_q,
                               levels = 0:3,
                               labels = c("Q0 (zero expo)",
                                          "Q1 (low expo)",
                                          "Q2 (mid expo)",
                                          "Q3 (high expo)"))]
cat("  buyers per quartile:\n")
print(buyer_pre[, .N, by = expo_lab][order(expo_lab)])

# ---------------------------------------------------------------------------
# 4. Buyer-year aggregates: any-high + count-of-distinct-high
# ---------------------------------------------------------------------------
buyer_year <- b2b[, .(
  has_any_high    = max(is_high),
  n_high_sectors  = uniqueN(seller_nace4d[is_high == 1L])
), by = .(buyer, year)]
buyer_year <- merge(buyer_year, buyer_pre[, .(buyer, expo_lab)], by = "buyer")

# Per-quartile per-year aggregates: share with any + mean count
pooled <- buyer_year[, .(
  n_buyers       = .N,
  share_buyers   = mean(has_any_high),
  mean_n_high    = mean(n_high_sectors),
  median_n_high  = median(n_high_sectors)
), by = .(expo_lab, year)]
setorder(pooled, expo_lab, year)

fwrite(pooled,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_extensive_by_buyer_exposure.csv"))

cat("\nShare of buyers with any high-shortage seller, by quartile x year:\n")
print(dcast(pooled, year ~ expo_lab, value.var = "share_buyers"))

# ---------------------------------------------------------------------------
# 5. Plot A: share of buyers
# ---------------------------------------------------------------------------
quartile_colors <- c("Q0 (zero expo)"  = "#cccccc",
                     "Q1 (low expo)"   = "#fdbb84",
                     "Q2 (mid expo)"   = "#e34a33",
                     "Q3 (high expo)"  = "#b30000")

base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom")

pA <- ggplot(pooled, aes(x = year, y = share_buyers, color = expo_lab)) +
  geom_line(linewidth = 0.85) +
  geom_point(size = 1.2) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = quartile_colors,
                     name = "Pre-period exposure quartile") +
  labs(title    = "Across-NACE4d extensive margin: share of buyers with any high-shortage ETS-NACE4d seller, by exposure quartile",
       subtitle = "Buyers binned by 2008-12 share of B2B spend on high-shortage ETS-NACE4d.",
       x = NULL, y = "Share of buyers with any high-shortage seller") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_buyer_exposure_share.png"),
       pA, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_buyer_exposure_share.pdf"),
       pA, width = 9, height = 5)

# ---------------------------------------------------------------------------
# 6. Plot B: mean count of distinct high-shortage NACE4d
# ---------------------------------------------------------------------------
pB <- ggplot(pooled, aes(x = year, y = mean_n_high, color = expo_lab)) +
  geom_line(linewidth = 0.85) +
  geom_point(size = 1.2) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, NA)) +
  scale_color_manual(values = quartile_colors,
                     name = "Pre-period exposure quartile") +
  labs(title    = "Across-NACE4d extensive margin: distinct high-shortage ETS-NACE4d per buyer, by exposure quartile",
       subtitle = "Mean count of distinct high-shortage ETS-NACE4d sectors per buyer (zero-filled for buyers with none).",
       x = NULL, y = "Mean count of high-shortage ETS-NACE4d per buyer") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_buyer_exposure_count.png"),
       pB, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_buyer_exposure_count.pdf"),
       pB, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
