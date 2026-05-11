###############################################################################
# phase4_across_nace4d_intensive_by_shortage.R
#
# PURPOSE
#   Heterogeneity #1 on across-NACE4d intensive margin: split ETS-treated
#   NACE4d into high-shortage vs low-shortage sectors, and plot the buyer-year
#   share of B2B expenditure on each category over time.
#
#   The sector-level shortage metric captures BOTH emission intensity AND
#   free-allocation generosity in a single dimension:
#
#       omega_nace4d = sum_{firms f in N, years t in pre-period} shortage_ft
#                    / sum_{firms f in N, years t in pre-period} total_cost_ft
#
#   where shortage_ft = verified emissions - free allowances (in tCO2) and
#   total_cost_ft = (revenue - value_added) + wage_bill, both from
#   firm_exposure. The pre-period is 2008-2012 (Phase II; tight caps so
#   shortage actually differentiates sectors, but still pre-2013 auctioning).
#   Phase I (2005-07) is unsuitable as a ranking period because over-allocation
#   pushes most NACE4d to zero shortage. NACE4d with <2 firm-years of pre-
#   period coverage are dropped from the ranking (instead of auto-assigned),
#   on the grounds that they likely entered EUTL via Phase III activity
#   expansion or NACE-code reassignment and aren't natively ETS-treated.
#   ETS-NACE4d that pass the coverage filter are split at the median omega.
#
#   For each (buyer j, year t) we then compute three shares (mean across
#   buyers per year, with 95% bootstrap CI):
#       share_jt^high_ets = spend(j, high-shortage ETS-NACE4d, t) / total_jt
#       share_jt^low_ets  = spend(j, low-shortage  ETS-NACE4d, t) / total_jt
#       share_jt^non_ets  = spend(j, non-ETS-NACE4d, t) / total_jt
#   (the three sum to 1 modulo NA sellers; non-ETS is implicit).
#
#   NOTE on the NACE 20/24 EUTL 2021+ break: the 3 affected VATs only matter
#   for post-2020 EUTL aggregates. The sector ranking here uses 2005-2007
#   firm_exposure, well before the break -- so the exclusion is irrelevant.
#
# OUTPUTS (output_<machine>/figures/, output_<machine>/tables/)
#   - phase4_across_nace4d_intensive_by_shortage.{png,pdf}
#   - phase4_across_nace4d_intensive_by_shortage.csv
#   - phase4_across_nace4d_intensive_by_shortage_nace4d_ranking.csv
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

YEAR_LO     <- 2005L
YEAR_HI     <- 2022L
PRE_YEARS   <- 2008L:2012L
MIN_FIRM_YRS_PRE <- 2L
N_BOOT      <- 1000L

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

ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d) & ets_treated_nace4d != ""]
cat(sprintf("  ETS-treated NACE4d (any year): %d\n", length(ets_treated_nace4d)))

# ---------------------------------------------------------------------------
# 2. NACE4d-level shortage ranking from pre-period firm_exposure
# ---------------------------------------------------------------------------
cat("\nBuilding NACE4d-level shortage ranking on pre-period",
    paste(range(PRE_YEARS), collapse = "-"), "...\n")

fe_pre <- fe[year %in% PRE_YEARS &
             !is.na(shortage) & !is.na(total_cost) & total_cost > 0]
cat(sprintf("  firm-year rows in pre-period: %d (%d unique firms, %d NACE4d)\n",
            nrow(fe_pre), uniqueN(fe_pre$vat), uniqueN(fe_pre$nace4d)))

nace4d_shortage <- fe_pre[, .(
  n_firms_pre   = uniqueN(vat),
  n_obs_pre     = .N,
  sum_shortage  = sum(shortage),
  sum_totalcost = sum(total_cost)
), by = nace4d]
nace4d_shortage[, omega_nace4d := sum_shortage / sum_totalcost]
nace4d_shortage <- nace4d_shortage[!is.na(omega_nace4d)]

# Require minimum pre-period coverage. NACE4d failing this filter are
# dropped from the ETS-treated set entirely (i.e. they fall into non_ets
# for this analysis); they likely entered EUTL via Phase III activity
# expansion or NACE-code reassignment and were not natively treated when
# our analysis window opens.
nace4d_ranked <- nace4d_shortage[n_obs_pre >= MIN_FIRM_YRS_PRE]
ets_dropped <- setdiff(ets_treated_nace4d, nace4d_ranked$nace4d)
cat(sprintf("  ETS-NACE4d kept in ranking: %d (dropped %d for <%d firm-years)\n",
            nrow(nace4d_ranked), length(ets_dropped), MIN_FIRM_YRS_PRE))

# Positive-vs-zero split: NACE4d with strictly positive net shortage in
# the pre-period had real net EUA cost; the rest had free allowances >=
# verified emissions (no incremental EUA cost). A median split is
# uninformative because >50% of NACE4d sit at exactly zero shortage.
nace4d_ranked[, shortage_bin := fifelse(omega_nace4d > 0,
                                        "high_ets", "low_ets")]
cat(sprintf("  positive-shortage threshold: omega_nace4d > 0\n"))
cat(sprintf("  omega_nace4d quantiles (positive-omega NACE4d only):\n"))
print(quantile(nace4d_ranked[omega_nace4d > 0, omega_nace4d],
               probs = c(0, .1, .25, .5, .75, .9, 1), na.rm = TRUE))

setorder(nace4d_ranked, -omega_nace4d)
fwrite(nace4d_ranked,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_intensive_by_shortage_nace4d_ranking.csv"))
cat(sprintf("  high_ets NACE4d: %d, low_ets NACE4d: %d\n",
            sum(nace4d_ranked$shortage_bin == "high_ets"),
            sum(nace4d_ranked$shortage_bin == "low_ets")))

high_set <- nace4d_ranked[shortage_bin == "high_ets", unique(nace4d)]
low_set  <- nace4d_ranked[shortage_bin == "low_ets",  unique(nace4d)]

# ---------------------------------------------------------------------------
# 3. Tag every B2B row with seller's NACE4d category
# ---------------------------------------------------------------------------
cat("\nTagging B2B sellers...\n")

seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b[, category := fifelse(is.na(seller_nace4d), "missing",
                  fifelse(seller_nace4d %in% high_set, "high_ets",
                  fifelse(seller_nace4d %in% low_set,  "low_ets",
                                                      "non_ets")))]

cat("  B2B-row distribution by category:\n")
print(b2b[, .(.N, sales = sum(sales)), by = category])

# ---------------------------------------------------------------------------
# 4. Buyer-year shares per category
# ---------------------------------------------------------------------------
cat("\nComputing buyer-year shares...\n")

buyer_year <- dcast(
  b2b[category != "missing"],
  buyer + year ~ category,
  value.var = "sales", fun.aggregate = sum, fill = 0
)
# Guarantee columns even if a category is empty
for (col in c("high_ets", "low_ets", "non_ets")) {
  if (!col %in% names(buyer_year)) buyer_year[, (col) := 0]
}
buyer_year[, total := high_ets + low_ets + non_ets]
buyer_year <- buyer_year[total > 0]
for (col in c("high_ets", "low_ets", "non_ets")) {
  buyer_year[, paste0("share_", col) := get(col) / total]
}

cat(sprintf("  buyer-year rows: %d (%d unique buyers)\n",
            nrow(buyer_year), uniqueN(buyer_year$buyer)))

# ---------------------------------------------------------------------------
# 5. Per-year mean + 95% bootstrap CI, plus aggregate
# ---------------------------------------------------------------------------
boot_ci <- function(x, n_boot = N_BOOT, alpha = 0.05) {
  x <- x[!is.na(x)]
  if (length(x) < 5L) return(list(lo = NA_real_, hi = NA_real_))
  m <- length(x)
  draws <- replicate(n_boot, mean(x[sample.int(m, m, replace = TRUE)]))
  q <- quantile(draws, c(alpha / 2, 1 - alpha / 2), names = FALSE)
  list(lo = q[1], hi = q[2])
}

pooled_list <- list()
for (cat_lab in c("high_ets", "low_ets", "non_ets")) {
  share_col <- paste0("share_", cat_lab)
  spend_col <- cat_lab
  agg <- buyer_year[, {
    ci <- boot_ci(get(share_col))
    .(n_buyers       = .N,
      mean_share     = mean(get(share_col), na.rm = TRUE),
      aggregate_share = sum(get(spend_col)) / sum(total),
      ci_lo          = ci$lo,
      ci_hi          = ci$hi)
  }, by = year]
  agg[, category := cat_lab]
  pooled_list[[cat_lab]] <- agg
}
pooled <- rbindlist(pooled_list)
setorder(pooled, category, year)

fwrite(pooled,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_intensive_by_shortage.csv"))

cat("\nYear-level summary (mean across buyers):\n")
print(dcast(pooled, year ~ category, value.var = "mean_share"))
cat("\nYear-level summary (aggregate sum/sum):\n")
print(dcast(pooled, year ~ category, value.var = "aggregate_share"))

# ---------------------------------------------------------------------------
# 6. Plot
# ---------------------------------------------------------------------------
plot_dt <- copy(pooled)
plot_dt[, category := factor(category,
                             levels = c("high_ets", "low_ets", "non_ets"),
                             labels = c("High-shortage ETS-NACE4d",
                                        "Low-shortage ETS-NACE4d",
                                        "Non-ETS-NACE4d"))]

cat_colors <- c("High-shortage ETS-NACE4d" = "#b22222",
                "Low-shortage ETS-NACE4d"  = "#1f78b4",
                "Non-ETS-NACE4d"           = "#525252")

base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom")

p <- ggplot(plot_dt, aes(x = year, color = category, fill = category)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi),
              alpha = 0.18, color = NA) +
  geom_line(aes(y = mean_share), linewidth = 0.95) +
  geom_point(aes(y = mean_share), size = 1.4) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, NA),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = cat_colors, name = NULL) +
  scale_fill_manual (values = cat_colors, name = NULL) +
  labs(title    = "Across-NACE4d intensive margin: buyer expenditure share by sector shortage bin",
       subtitle = sprintf("ETS-NACE4d split by pre-period (2008-12) net shortage > 0 vs <= 0. Mean across buyers (95%% bootstrap CI)."),
       x = NULL,
       y = "Share of buyer's B2B expenditure") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_intensive_by_shortage.png"),
       p, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_intensive_by_shortage.pdf"),
       p, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
