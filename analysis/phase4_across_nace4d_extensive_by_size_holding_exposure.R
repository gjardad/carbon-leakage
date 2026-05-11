###############################################################################
# phase4_across_nace4d_extensive_by_size_holding_exposure.R
#
# PURPOSE
#   Extensive-margin twin of phase4_across_nace4d_intensive_by_size_holding_
#   exposure.R. For each (exposure bin x size quartile) cell, two outcomes:
#
#     A) Share of buyers in the cell that have at least one high-shortage
#        ETS-NACE4d seller in year t.
#     B) Mean count of distinct high-shortage ETS-NACE4d sectors per buyer.
#
#   Bins follow plot #7 exactly:
#     - Exposure: Q0 (zero) + tertiles of (expo > 0), where expo is the
#       pre-period (2008-12) share of B2B spend on high-shortage ETS-NACE4d.
#     - Size: quartiles of pre-period log(total B2B spend), computed WITHIN
#       each exposure bin so cells are balanced.
#
#   Asks: holding exposure fixed, do large buyers drop high-shortage ETS
#   sources faster than small buyers?
#
# OUTPUTS
#   - phase4_across_nace4d_extensive_by_size_holding_exposure_share.{png,pdf}
#   - phase4_across_nace4d_extensive_by_size_holding_exposure_count.{png,pdf}
#   - phase4_across_nace4d_extensive_by_size_holding_exposure.csv
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
nace4d_shortage <- fe_pre[, .(n_obs_pre = .N,
                              sum_shortage = sum(shortage),
                              sum_totalcost = sum(total_cost)), by = nace4d]
nace4d_shortage[, omega_nace4d := sum_shortage / sum_totalcost]
high_set <- nace4d_shortage[n_obs_pre >= MIN_FIRM_YRS_PRE & omega_nace4d > 0,
                            unique(nace4d)]
cat(sprintf("  high-shortage ETS-NACE4d: %d\n", length(high_set)))

seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b[, is_high := as.integer(!is.na(seller_nace4d) & seller_nace4d %in% high_set)]

# ---------------------------------------------------------------------------
# 3. Pre-period exposure (high-shortage) and size
# ---------------------------------------------------------------------------
cat("\nBinning buyers...\n")
buyer_pre <- b2b[year %in% PRE_YEARS, .(
  pre_spend_high = sum(sales * is_high),
  pre_spend_tot  = sum(sales)
), by = buyer]
buyer_pre <- buyer_pre[pre_spend_tot > 0]
buyer_pre[, expo     := pre_spend_high / pre_spend_tot]
buyer_pre[, log_size := log(pre_spend_tot)]

buyer_pre[, expo_q := NA_integer_]
buyer_pre[expo == 0, expo_q := 0L]
pos_breaks <- quantile(buyer_pre[expo > 0, expo], probs = c(0, 1/3, 2/3, 1),
                       na.rm = TRUE)
buyer_pre[expo > 0,
          expo_q := as.integer(cut(expo, breaks = pos_breaks,
                                   include.lowest = TRUE, labels = FALSE))]
buyer_pre[, expo_lab := factor(expo_q,
                               levels = 0:3,
                               labels = c("Exposure: zero",
                                          "Exposure: low",
                                          "Exposure: mid",
                                          "Exposure: high"))]

# Size quartiles within each exposure bin
buyer_pre[, size_q := NA_integer_]
buyer_pre[, size_q := as.integer(cut(log_size,
                                     breaks = quantile(log_size,
                                                       probs = seq(0, 1, .25),
                                                       na.rm = TRUE),
                                     include.lowest = TRUE, labels = FALSE)),
          by = expo_q]
buyer_pre[, size_lab := factor(size_q,
                               levels = 1:4,
                               labels = c("Size Q1 (smallest)",
                                          "Size Q2", "Size Q3",
                                          "Size Q4 (largest)"))]

cat("  buyers per (exposure x size) cell:\n")
print(dcast(buyer_pre[, .N, by = .(expo_lab, size_lab)],
            expo_lab ~ size_lab, value.var = "N", fill = 0L))

# ---------------------------------------------------------------------------
# 4. Buyer-year ext outcomes
# ---------------------------------------------------------------------------
buyer_year <- b2b[, .(
  has_any_high    = max(is_high),
  n_high_sectors  = uniqueN(seller_nace4d[is_high == 1L])
), by = .(buyer, year)]
buyer_year <- merge(buyer_year, buyer_pre[, .(buyer, expo_lab, size_lab)],
                    by = "buyer")

pooled <- buyer_year[, .(
  n_buyers      = .N,
  share_buyers  = mean(has_any_high),
  mean_n_high   = mean(n_high_sectors)
), by = .(expo_lab, size_lab, year)]
setorder(pooled, expo_lab, size_lab, year)

fwrite(pooled,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_extensive_by_size_holding_exposure.csv"))

# ---------------------------------------------------------------------------
# 5. Plot A: share of buyers
# ---------------------------------------------------------------------------
size_colors <- c("Size Q1 (smallest)" = "#fdd49e",
                 "Size Q2"            = "#fdbb84",
                 "Size Q3"            = "#e34a33",
                 "Size Q4 (largest)"  = "#b30000")

base_theme <- theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom",
        strip.text       = element_text(face = "bold"))

pA <- ggplot(pooled, aes(x = year, y = share_buyers,
                         color = size_lab)) +
  geom_line(linewidth = 0.75) +
  geom_point(size = 1.0) +
  facet_wrap(~ expo_lab, ncol = 2) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 3)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = size_colors,
                     name = "Pre-period B2B-spend size quartile") +
  labs(title    = "Across-NACE4d extensive margin: share of buyers with any high-shortage ETS-NACE4d seller, by size within each exposure bin",
       subtitle = "Each panel = one pre-period exposure bin. Lines = pre-period size quartiles (computed within bin).",
       x = NULL,
       y = "Share of buyers with any high-shortage seller") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_size_holding_exposure_share.png"),
       pA, width = 10, height = 7, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_size_holding_exposure_share.pdf"),
       pA, width = 10, height = 7)

# ---------------------------------------------------------------------------
# 6. Plot B: mean count
# ---------------------------------------------------------------------------
pB <- ggplot(pooled, aes(x = year, y = mean_n_high, color = size_lab)) +
  geom_line(linewidth = 0.75) +
  geom_point(size = 1.0) +
  facet_wrap(~ expo_lab, ncol = 2) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 3)) +
  scale_y_continuous(limits = c(0, NA)) +
  scale_color_manual(values = size_colors,
                     name = "Pre-period B2B-spend size quartile") +
  labs(title    = "Across-NACE4d extensive margin: distinct high-shortage ETS-NACE4d per buyer, by size within each exposure bin",
       subtitle = "Mean count of distinct high-shortage ETS-NACE4d sectors per buyer (zero-filled when none).",
       x = NULL,
       y = "Mean count of high-shortage ETS-NACE4d per buyer") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_size_holding_exposure_count.png"),
       pB, width = 10, height = 7, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_size_holding_exposure_count.pdf"),
       pB, width = 10, height = 7)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
