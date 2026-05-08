###############################################################################
# phase4_across_nace4d_extensive_margin.R
#
# PURPOSE
#   Plot, by year, the share of B2B-active buyers that purchase from at least
#   one supplier in an ETS-treated NACE4d sector.
#
#   For each year t:
#       n_buyers_active   = number of distinct buyers active in B2B in year t
#       n_buyers_ets_nace = number of distinct buyers who bought from
#                           at least one supplier in an ETS-treated NACE4d
#       share_t           = n_buyers_ets_nace / n_buyers_active
#
#   ETS-treated NACE4d = NACE4d that contains at least one in-sample firm in
#   `firm_exposure` (the same definition used in the within-NACE4d work).
#
# OUTPUTS (output_<machine>/figures/, output_<machine>/tables/)
#   - phase4_across_nace4d_extensive_margin.{png,pdf}
#   - phase4_across_nace4d_extensive_margin.csv
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

YEAR_LO <- 2005L
YEAR_HI <- 2022L

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
ets_treated_nace4d <- unique(as.data.table(firm_exposure)$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]
rm(firm_exposure)
cat(sprintf("  ETS-treated NACE4d: %d\n", length(ets_treated_nace4d)))

seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b[, ets_nace := as.integer(!is.na(seller_nace4d) &
                             seller_nace4d %in% ets_treated_nace4d)]

# ---------------------------------------------------------------------------
# 2. Per-year extensive margin
# ---------------------------------------------------------------------------
cat("\nComputing per-year extensive margin...\n")

per_year <- b2b[, .(
  n_buyers_active   = uniqueN(buyer),
  n_buyers_ets_nace = uniqueN(buyer[ets_nace == 1L])
), by = year]
per_year[, share_buyers_ets_nace := n_buyers_ets_nace / n_buyers_active]
setorder(per_year, year)

print(per_year[, .(year, n_buyers_active, n_buyers_ets_nace,
                   share = round(share_buyers_ets_nace, 3))])

fwrite(per_year,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_extensive_margin.csv"))

# ---------------------------------------------------------------------------
# 3. Plot
# ---------------------------------------------------------------------------
base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

p <- ggplot(per_year, aes(x = year, y = share_buyers_ets_nace)) +
  geom_line(color = "steelblue", linewidth = 0.95) +
  geom_point(color = "steelblue", size = 1.4) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::percent_format(accuracy = 1)) +
  labs(title = "Across-NACE4d extensive margin: share of buyers purchasing from ETS-treated NACE4d sectors",
       subtitle = "Share of B2B-active buyers in year t that bought from at least one supplier in an ETS-treated NACE4d.",
       x = NULL,
       y = "Share of active buyers") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_margin.png"),
       p, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_margin.pdf"),
       p, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
