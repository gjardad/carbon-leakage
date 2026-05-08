###############################################################################
# phase4_within_nace4d_extensive_margin.R
#
# PURPOSE
#   Plot, by year, the share of buyers active in ETS-treated NACE4d sectors
#   who buy from at least one ETS-treated firm in the same NACE4d.
#
#   For each year t:
#       n_buyers_in_ets_nace =
#         number of distinct buyers who bought from any supplier in an
#         ETS-treated NACE4d in year t
#       n_buyers_in_ets_firm =
#         number of distinct buyers among the above who also bought from
#         at least one ETS-regulated firm (i.e., a supplier in EUTL/in_sample
#         in `firm_year_belgian_euets`) in that same year
#       share_t = n_buyers_in_ets_firm / n_buyers_in_ets_nace
#
#   The numerator is the buyer's choice within the set of suppliers it
#   transacts with in ETS-treated NACE4d: did the buyer pick at least one
#   regulated supplier, or did it pick only non-regulated ones?
#
#   "ETS-treated firm" = appears in `firm_year_belgian_euets` (in_sample == 1)
#   in year t. (Year-specific membership; alternative ever-in-EUTL membership
#   is also computed for diagnostic comparison and saved in the CSV.)
#
# OUTPUTS (output_<machine>/figures/, output_<machine>/tables/)
#   - phase4_within_nace4d_extensive_margin.{png,pdf}
#   - phase4_within_nace4d_extensive_margin.csv
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
fe <- as.data.table(firm_exposure)
rm(firm_exposure)
ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]

# Year-specific ETS firm set (firm has a row in firm_exposure -- which is
# already filtered to in_sample == 1 -- in year t)
ets_firm_year <- unique(fe[, .(seller = as.character(vat), year)])
ets_firm_year[, ets_firm_in_year := 1L]

# Ever-in-EUTL set (for diagnostic alternative)
ets_firm_ever <- unique(fe[, .(seller = as.character(vat))])
ets_vats_all  <- ets_firm_ever$seller

cat(sprintf("  ETS-treated NACE4d: %d; firm-years in EUTL/in_sample: %d; ever-in-EUTL: %d\n",
            length(ets_treated_nace4d), nrow(ets_firm_year), length(ets_vats_all)))

# ---------------------------------------------------------------------------
# 2. Tag b2b rows with seller NACE4d, ETS-NACE4d flag, ETS-firm flag
# ---------------------------------------------------------------------------
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b[, ets_nace := as.integer(!is.na(seller_nace4d) &
                             seller_nace4d %in% ets_treated_nace4d)]

# ETS firm in year t
b2b <- merge(b2b, ets_firm_year, by = c("seller", "year"), all.x = TRUE)
b2b[is.na(ets_firm_in_year), ets_firm_in_year := 0L]

# Ever-in-EUTL
b2b[, ets_firm_ever := as.integer(seller %in% ets_vats_all)]

# ---------------------------------------------------------------------------
# 3. Per-year within-NACE4d extensive margin
# ---------------------------------------------------------------------------
cat("\nComputing per-year within-NACE4d extensive margin...\n")

# Restrict to b2b rows where the supplier is in an ETS-treated NACE4d
b2b_ets_nace <- b2b[ets_nace == 1L]

per_year <- b2b_ets_nace[, .(
  n_buyers_in_ets_nace        = uniqueN(buyer),
  n_buyers_in_ets_firm_year   = uniqueN(buyer[ets_firm_in_year == 1L]),
  n_buyers_in_ets_firm_ever   = uniqueN(buyer[ets_firm_ever == 1L])
), by = year]

per_year[, share_year := n_buyers_in_ets_firm_year / n_buyers_in_ets_nace]
per_year[, share_ever := n_buyers_in_ets_firm_ever / n_buyers_in_ets_nace]
setorder(per_year, year)

print(per_year[, .(year,
                   n_in_ets_nace      = n_buyers_in_ets_nace,
                   n_buy_ets_firm_yr  = n_buyers_in_ets_firm_year,
                   n_buy_ets_firm_evr = n_buyers_in_ets_firm_ever,
                   share_year_in_yr   = round(share_year, 3),
                   share_ever_in_yr   = round(share_ever, 3))])

fwrite(per_year,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_extensive_margin.csv"))

# ---------------------------------------------------------------------------
# 4. Plot
# ---------------------------------------------------------------------------
base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom")

p <- ggplot(per_year, aes(x = year)) +
  geom_line(aes(y = share_year, color = "ETS firm in year t"),
            linewidth = 0.95) +
  geom_point(aes(y = share_year, color = "ETS firm in year t"), size = 1.4) +
  geom_line(aes(y = share_ever, color = "ETS firm ever (any year)"),
            linetype = "dashed", linewidth = 0.85) +
  geom_point(aes(y = share_ever, color = "ETS firm ever (any year)"),
             shape = 17, size = 1.3) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = c("ETS firm in year t" = "steelblue",
                                "ETS firm ever (any year)" = "firebrick"),
                     name = NULL) +
  labs(title = "Within-NACE4d extensive margin: share of buyers (in ETS-treated NACE4d) buying from an ETS-treated firm",
       subtitle = "Conditional on buying from at least one supplier in an ETS-treated NACE4d. Two definitions of 'ETS firm'.",
       x = NULL,
       y = "Share of buyers in ETS-NACE4d that buy from an ETS firm") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_extensive_margin.png"),
       p, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_extensive_margin.pdf"),
       p, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
