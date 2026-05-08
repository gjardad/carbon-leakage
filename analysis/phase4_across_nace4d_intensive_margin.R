###############################################################################
# phase4_across_nace4d_intensive_margin.R
#
# PURPOSE
#   Plot, by year, the average buyer-level share of B2B expenditure that is
#   directed at suppliers in ETS-treated NACE4d sectors.
#
#   For each (buyer j, year t):
#       share_jt = sum_{i in ETS-NACE4d} spend(j, i, t)
#                / sum_i           spend(j, i, t)
#       (with share_jt in [0, 1]; NA if buyer has no B2B spend in year t)
#
#   ETS-treated NACE4d = NACE4d that contains at least one in-sample firm
#   in `firm_exposure` (the same definition used in the within-NACE4d work).
#
#   The plot reports the unweighted mean of share_jt across buyers per year,
#   with a 95% bootstrap CI. Also computed (saved in CSV) is the aggregate
#   share = sum_j spend on ETS-NACE4d / sum_j total spend, which weights
#   buyers by total expenditure.
#
# OUTPUTS (output_<machine>/figures/, output_<machine>/tables/)
#   - phase4_across_nace4d_intensive_margin.{png,pdf}
#   - phase4_across_nace4d_intensive_margin.csv
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

set.seed(20260508)

YEAR_LO <- 2005L
YEAR_HI <- 2022L
N_BOOT  <- 1000L

# ---------------------------------------------------------------------------
# 1. Load b2b, AA (for seller NACE4d), firm_exposure (for ETS-treated NACE4d)
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
ets_treated_nace4d <- unique(as.data.table(firm_exposure)$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]
rm(firm_exposure)
cat(sprintf("  ETS-treated NACE4d: %d\n", length(ets_treated_nace4d)))

# Attach seller NACE4d
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b[, ets_nace := as.integer(!is.na(seller_nace4d) &
                             seller_nace4d %in% ets_treated_nace4d)]

# ---------------------------------------------------------------------------
# 2. Buyer-year share of expenditure on ETS-treated NACE4d
# ---------------------------------------------------------------------------
cat("\nComputing buyer-year shares...\n")

buyer_year <- b2b[, .(
  spend_ets   = sum(sales[ets_nace == 1L]),
  spend_total = sum(sales)
), by = .(buyer, year)]

buyer_year <- buyer_year[spend_total > 0]
buyer_year[, share_ets := spend_ets / spend_total]

cat(sprintf("  buyer-year rows: %d (%d unique buyers)\n",
            nrow(buyer_year), uniqueN(buyer_year$buyer)))

# ---------------------------------------------------------------------------
# 3. Aggregate per year: mean (with bootstrap CI) and aggregate share
# ---------------------------------------------------------------------------
boot_ci <- function(x, stat = mean, n_boot = N_BOOT, alpha = 0.05) {
  x <- x[!is.na(x)]
  if (length(x) < 5L) return(list(lo = NA_real_, hi = NA_real_))
  m <- length(x)
  draws <- replicate(n_boot, stat(x[sample.int(m, m, replace = TRUE)]))
  q <- quantile(draws, c(alpha / 2, 1 - alpha / 2), names = FALSE)
  list(lo = q[1], hi = q[2])
}

pooled <- buyer_year[, {
  ci <- boot_ci(share_ets, stat = mean)
  .(n_buyers       = .N,
    mean_share     = mean(share_ets),
    median_share   = median(share_ets),
    aggregate_share = sum(spend_ets) / sum(spend_total),
    ci_lo          = ci$lo,
    ci_hi          = ci$hi)
}, by = year]
setorder(pooled, year)
fwrite(pooled,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_intensive_margin.csv"))

cat("\nYear-level summary:\n")
print(pooled[, .(year, n_buyers,
                 mean = round(mean_share, 3),
                 median = round(median_share, 3),
                 aggregate = round(aggregate_share, 3),
                 ci_lo = round(ci_lo, 3),
                 ci_hi = round(ci_hi, 3))])

# ---------------------------------------------------------------------------
# 4. Plot
# ---------------------------------------------------------------------------
base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom")

p <- ggplot(pooled, aes(x = year)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi),
              alpha = 0.2, fill = "steelblue") +
  geom_line(aes(y = mean_share, color = "Mean across buyers"),
            linewidth = 0.95) +
  geom_point(aes(y = mean_share, color = "Mean across buyers"), size = 1.4) +
  geom_line(aes(y = aggregate_share, color = "Aggregate (sum/sum)"),
            linetype = "dashed", linewidth = 0.85) +
  geom_point(aes(y = aggregate_share, color = "Aggregate (sum/sum)"),
             shape = 17, size = 1.3) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, NA),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = c("Mean across buyers" = "steelblue",
                                "Aggregate (sum/sum)" = "firebrick"),
                     name = NULL) +
  labs(title = "Across-NACE4d intensive margin: buyer expenditure share on ETS-treated NACE4d sectors",
       subtitle = "share_jt = spend on ETS-NACE4d suppliers / total B2B spend. Mean across buyers (with 95% bootstrap CI) and aggregate sum/sum.",
       x = NULL,
       y = "Share of buyer's B2B expenditure on ETS-treated NACE4d") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_intensive_margin.png"),
       p, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_intensive_margin.pdf"),
       p, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
