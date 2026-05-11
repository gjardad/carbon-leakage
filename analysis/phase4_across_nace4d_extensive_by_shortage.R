###############################################################################
# phase4_across_nace4d_extensive_by_shortage.R
#
# PURPOSE
#   Extensive-margin twin of phase4_across_nace4d_intensive_by_shortage.R.
#   Two outcomes, both restricted to the high-shortage ETS-NACE4d set
#   (sectors with positive net shortage on 2008-12 firm_exposure aggregates):
#
#     A) Share of buyers buying from at least one HIGH-shortage ETS-NACE4d
#        seller in year t, plotted alongside the same share for LOW-shortage
#        ETS-NACE4d. Direct analog of plot #1 at the population level.
#
#     B) Mean count of distinct ETS-NACE4d sectors per buyer (high vs low).
#        Buyer-level breadth measure: captures portfolio narrowing/widening
#        that the 0/1 indicator misses when most buyers touch some ETS sector.
#
#   Sector definition is identical to phase4_across_nace4d_intensive_by_shortage.R:
#     high-shortage = NACE4d with omega_n > 0 on pre-period 2008-12,
#                     where omega_n = sum(shortage_ft) / sum(total_cost_ft).
#     low-shortage  = ETS-treated NACE4d with omega_n <= 0 (and >= 2 firm-yrs
#                     of pre-period coverage).
#
# OUTPUTS
#   - phase4_across_nace4d_extensive_by_shortage_share.{png,pdf}
#   - phase4_across_nace4d_extensive_by_shortage_count.{png,pdf}
#   - phase4_across_nace4d_extensive_by_shortage.csv
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
# 2. High-shortage vs low-shortage NACE4d set (pre-period 2008-12)
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

high_set <- nace4d_ranked[omega_nace4d > 0,  unique(nace4d)]
low_set  <- nace4d_ranked[omega_nace4d <= 0, unique(nace4d)]
cat(sprintf("  high-shortage ETS-NACE4d (omega > 0): %d\n", length(high_set)))
cat(sprintf("  low-shortage  ETS-NACE4d (omega <= 0): %d\n", length(low_set)))

# ---------------------------------------------------------------------------
# 3. Tag B2B sellers
# ---------------------------------------------------------------------------
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b[, category := fifelse(is.na(seller_nace4d), "missing",
                  fifelse(seller_nace4d %in% high_set, "high",
                  fifelse(seller_nace4d %in% low_set,  "low",
                                                       "other")))]

# ---------------------------------------------------------------------------
# 4. Buyer-year aggregates per category (any-seller + sector-count)
# ---------------------------------------------------------------------------
cat("\nComputing buyer-year extensive-margin metrics...\n")

# n_active_buyers per year (denominator)
yr_active <- b2b[, .(n_active = uniqueN(buyer)), by = year]

# For each (buyer, year, category): does the buyer have any seller in that
# category, and how many distinct sector-NACE4d in that category?
by_cat <- b2b[category %in% c("high", "low"),
              .(any_seller = 1L,
                n_sectors  = uniqueN(seller_nace4d)),
              by = .(buyer, year, category)]

pop_share <- by_cat[, .(n_buyers_active = uniqueN(buyer)),
                    by = .(year, category)]
pop_share <- merge(pop_share, yr_active, by = "year", all.x = TRUE)
pop_share[, share_buyers := n_buyers_active / n_active]

mean_count <- by_cat[, .(mean_n_sectors = mean(n_sectors),
                         median_n_sectors = median(n_sectors),
                         n_buyers_with_any = .N),
                     by = .(year, category)]

agg <- merge(pop_share, mean_count, by = c("year", "category"))
setorder(agg, category, year)

fwrite(agg,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_extensive_by_shortage.csv"))

cat("\nShare of buyers with any seller, by category x year:\n")
print(dcast(agg, year ~ category, value.var = "share_buyers"))
cat("\nMean count of distinct sector-NACE4d per buyer-with-any:\n")
print(dcast(agg, year ~ category, value.var = "mean_n_sectors"))

# ---------------------------------------------------------------------------
# 5. Plot A: share of buyers (population-level)
# ---------------------------------------------------------------------------
plot_dt <- copy(agg)
plot_dt[, category := factor(category, levels = c("high", "low"),
                             labels = c("High-shortage ETS-NACE4d",
                                        "Low-shortage ETS-NACE4d"))]

cat_colors <- c("High-shortage ETS-NACE4d" = "#b22222",
                "Low-shortage ETS-NACE4d"  = "#1f78b4")

base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom")

pA <- ggplot(plot_dt, aes(x = year, y = share_buyers, color = category)) +
  geom_line(linewidth = 0.95) +
  geom_point(size = 1.4) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = cat_colors, name = NULL) +
  labs(title    = "Across-NACE4d extensive margin: share of buyers purchasing from each shortage bin",
       subtitle = "Buyer with at least one seller in the bin. ETS-NACE4d split by positive vs <=0 pre-period (2008-12) shortage.",
       x = NULL, y = "Share of active buyers") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_shortage_share.png"),
       pA, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_shortage_share.pdf"),
       pA, width = 9, height = 5)

# ---------------------------------------------------------------------------
# 6. Plot B: mean count of distinct sector-NACE4d per buyer
# ---------------------------------------------------------------------------
pB <- ggplot(plot_dt, aes(x = year, y = mean_n_sectors, color = category)) +
  geom_line(linewidth = 0.95) +
  geom_point(size = 1.4) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, NA)) +
  scale_color_manual(values = cat_colors, name = NULL) +
  labs(title    = "Across-NACE4d extensive margin: distinct sector-NACE4d per buyer, by shortage bin",
       subtitle = "Mean across buyers with at least one seller in the bin. ETS-NACE4d split by positive vs <=0 pre-period (2008-12) shortage.",
       x = NULL, y = "Distinct sector-NACE4d sources per buyer") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_shortage_count.png"),
       pB, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_by_shortage_count.pdf"),
       pB, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
