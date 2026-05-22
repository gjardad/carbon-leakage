###############################################################################
# phase4_within_intensive_sector_coverage.R
#
# PURPOSE
#   Sector-composition table for the within-NACE-4d intensive-margin DiD
#   sample. For each NACE 4-digit sector represented among the SELLERS in
#   the present-in-2010-14 sample, report:
#     - count of unique suppliers in the sample (top + bot pool combined)
#     - count of unique (buyer, seller) pairs in the sample
#     - pre-period emissions of sample sellers (kt CO2e, 2010-2014 sum)
#     - total Belgian EUTL emissions in the sector (kt CO2e, 2010-2014 sum)
#     - %% emissions coverage = sample emissions / sector EUTL emissions
#     - pre-period revenue of sample sellers (EUR millions, 2010-2014 sum)
#     - total sector revenue (EUR millions, 2010-2014 sum)
#     - %% revenue coverage = sample revenue / sector revenue
#
#   Sectors are sorted by sample emissions descending.
#
# OUTPUTS
#   - phase4_within_intensive_sector_coverage.tex (sortable .tex table)
#   - phase4_within_intensive_sector_coverage.csv (machine-readable copy)
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(xtable)
})

set.seed(20260521)

PRE_WINDOW <- 2010L:2014L
OMEGA_WIN  <- c(2015L, 2016L)

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
b2b <- b2b[!is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year),
             sales)]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat    = as.character(vat_ano),
  year   = as.integer(year),
  nace4d = substr(nace5d, 1, 4))]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))
aa_kv <- as.data.table(df_annual_accounts_selected_sample_key_variables)[, .(
  vat = as.character(vat), year = as.integer(year), revenue)]
rm(df_annual_accounts_selected_sample_key_variables)

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(vat = as.character(vat),
                                       year, shortage, emissions,
                                       total_cost)]
rm(firm_exposure)
fe[, omega_sh := ifelse(!is.na(total_cost) & total_cost > 0,
                        pmax(shortage, 0) / total_cost, NA_real_)]

# Attach seller NACE4d to b2b (b2b's nace4d is the SELLER's nace4d)
b2b_with_nace <- merge(b2b, aa, by.x = c("seller", "year"), by.y = c("vat", "year"),
                       all.x = TRUE)
setnames(b2b_with_nace, "nace4d", "seller_nace4d")
b2b_with_nace <- b2b_with_nace[!is.na(seller_nace4d) & seller_nace4d != ""]

# ---------------------------------------------------------------------------
# Build the present-in-2010-14 sample (same construction as the DiD scripts)
# ---------------------------------------------------------------------------
cat("Building present-in-2010-14 sample...\n")
pre_active <- b2b_with_nace[year %in% PRE_WINDOW,
                  .(pre_sales = sum(sales)),
                  by = .(buyer, seller_nace4d, seller)]
omega_window_active <- b2b_with_nace[year %in% OMEGA_WIN,
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

# All sample pairs = top (rk == 1 by omega) + bot pool (omega == cell_min)
setorder(pool, buyer, seller_nace4d, -omega_anchor, -pre_sales, seller)
pool[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
sample_pairs <- pool[rk == 1L | omega_anchor == cell_min_omega,
                     .(buyer, seller_nace4d, seller)]
cat(sprintf("  Sample: %d (buyer, seller) pairs across %d sellers and %d sectors\n",
            nrow(sample_pairs),
            uniqueN(sample_pairs$seller),
            uniqueN(sample_pairs$seller_nace4d)))

sellers_in_sample <- unique(sample_pairs$seller)

# ---------------------------------------------------------------------------
# Per-seller summaries (pre-period 2010-2014)
# ---------------------------------------------------------------------------
cat("Computing per-seller pre-period emissions and revenue...\n")

# Emissions per seller (pre-period sum, in tCO2e)
em_pre <- fe[year %in% PRE_WINDOW,
             .(total_em = sum(emissions, na.rm = TRUE)),
             by = vat]

# Revenue per seller (pre-period sum, in EUR)
rev_pre <- aa_kv[year %in% PRE_WINDOW,
                 .(total_rev = sum(revenue, na.rm = TRUE)),
                 by = vat]

# Universe of (vat, nace4d) -- using the most-frequent nace4d per vat in 2010-14
nace_by_vat <- aa[year %in% PRE_WINDOW, .(vat, nace4d)]
nace_by_vat <- nace_by_vat[, .N, by = .(vat, nace4d)]
setorder(nace_by_vat, vat, -N)
nace_by_vat <- nace_by_vat[, .(nace4d = nace4d[1L]), by = vat]

# ---------------------------------------------------------------------------
# Aggregate by sector
# ---------------------------------------------------------------------------
cat("Aggregating by NACE 4-digit sector...\n")

# Sample sellers' NACE4d (use the seller_nace4d associated with the sample;
# fall back to nace_by_vat in case a seller appears in multiple NACE4d cells)
sample_sellers <- unique(sample_pairs[, .(seller, seller_nace4d)])
# A few sellers may appear in cells for multiple NACE4d -- attribute each
# (seller, nace4d) pair to the sector of THAT cell.
sample_sectors <- sample_pairs[, .(
  n_pairs    = .N,
  n_suppliers = uniqueN(seller)
), by = seller_nace4d]
setnames(sample_sectors, "seller_nace4d", "nace4d")

# Sample emissions and revenue: sum over (seller, year) for sample sellers
em_sample <- em_pre[vat %in% sellers_in_sample]
em_sample <- merge(em_sample, nace_by_vat, by = "vat", all.x = TRUE)
em_sample_sector <- em_sample[!is.na(nace4d),
                              .(sample_em_tco2 = sum(total_em, na.rm = TRUE)),
                              by = nace4d]

rev_sample <- rev_pre[vat %in% sellers_in_sample]
rev_sample <- merge(rev_sample, nace_by_vat, by = "vat", all.x = TRUE)
rev_sample_sector <- rev_sample[!is.na(nace4d),
                                .(sample_rev_eur = sum(total_rev, na.rm = TRUE)),
                                by = nace4d]

# Universe: total EUTL emissions per sector
em_universe <- merge(em_pre, nace_by_vat, by = "vat", all.x = TRUE)
em_universe_sector <- em_universe[!is.na(nace4d),
                                  .(total_em_tco2 = sum(total_em, na.rm = TRUE)),
                                  by = nace4d]

# Universe: total Annual Accounts revenue per sector
rev_universe <- merge(rev_pre, nace_by_vat, by = "vat", all.x = TRUE)
rev_universe_sector <- rev_universe[!is.na(nace4d),
                                    .(total_rev_eur = sum(total_rev, na.rm = TRUE)),
                                    by = nace4d]

# Merge everything onto the sample-sector table
tbl <- sample_sectors
tbl <- merge(tbl, em_sample_sector, by = "nace4d", all.x = TRUE)
tbl <- merge(tbl, em_universe_sector, by = "nace4d", all.x = TRUE)
tbl <- merge(tbl, rev_sample_sector, by = "nace4d", all.x = TRUE)
tbl <- merge(tbl, rev_universe_sector, by = "nace4d", all.x = TRUE)

tbl[is.na(sample_em_tco2),  sample_em_tco2  := 0]
tbl[is.na(total_em_tco2),   total_em_tco2   := 0]
tbl[is.na(sample_rev_eur),  sample_rev_eur  := 0]
tbl[is.na(total_rev_eur),   total_rev_eur   := 0]

# Coverage percentages
tbl[, pct_em  := ifelse(total_em_tco2  > 0, 100 * sample_em_tco2  / total_em_tco2,  NA_real_)]
tbl[, pct_rev := ifelse(total_rev_eur > 0, 100 * sample_rev_eur / total_rev_eur, NA_real_)]

# Display units: kt for emissions, EUR millions for revenue
tbl[, sample_em_kt  := sample_em_tco2  / 1e3]
tbl[, total_em_kt   := total_em_tco2   / 1e3]
tbl[, sample_rev_m  := sample_rev_eur  / 1e6]
tbl[, total_rev_m   := total_rev_eur   / 1e6]

setorder(tbl, -sample_em_kt, -n_suppliers)

# Final column order
tbl_out <- tbl[, .(`NACE 4d` = nace4d,
                   `Suppliers` = n_suppliers,
                   `Pairs` = n_pairs,
                   `Sample emissions (kt CO2e)`     = round(sample_em_kt,  1),
                   `Sector ETS emissions (kt CO2e)` = round(total_em_kt,   1),
                   `\\% emissions covered`           = round(pct_em,        1),
                   `Sample revenue (EUR mn)`        = round(sample_rev_m,  1),
                   `Sector revenue (EUR mn)`        = round(total_rev_m,   1),
                   `\\% revenue covered`             = round(pct_rev,       1))]

cat("\n--- Sector coverage table (head) ---\n")
print(head(tbl_out, 15))

# Totals row
totals <- data.table(
  `NACE 4d` = "Total",
  `Suppliers` = uniqueN(sample_pairs$seller),
  `Pairs` = nrow(sample_pairs),
  `Sample emissions (kt CO2e)`     = round(sum(tbl$sample_em_kt, na.rm = TRUE), 1),
  `Sector ETS emissions (kt CO2e)` = round(sum(tbl$total_em_kt, na.rm = TRUE), 1),
  `\\% emissions covered`           = ifelse(sum(tbl$total_em_kt, na.rm = TRUE) > 0,
                                       round(100 * sum(tbl$sample_em_kt, na.rm = TRUE) /
                                                   sum(tbl$total_em_kt,  na.rm = TRUE), 1),
                                       NA_real_),
  `Sample revenue (EUR mn)`        = round(sum(tbl$sample_rev_m, na.rm = TRUE), 1),
  `Sector revenue (EUR mn)`        = round(sum(tbl$total_rev_m, na.rm = TRUE), 1),
  `\\% revenue covered`             = ifelse(sum(tbl$total_rev_m, na.rm = TRUE) > 0,
                                       round(100 * sum(tbl$sample_rev_m, na.rm = TRUE) /
                                                   sum(tbl$total_rev_m,  na.rm = TRUE), 1),
                                       NA_real_)
)
tbl_out <- rbind(tbl_out, totals, use.names = TRUE)

# ---------------------------------------------------------------------------
# CSV + tex output
# ---------------------------------------------------------------------------
fwrite(tbl_out, file.path(OUTPUT_TAB,
       "phase4_within_intensive_sector_coverage.csv"))

xt <- xtable(tbl_out,
             caption = paste("Sectoral composition of the suppliers in the",
                             "within-NACE-4d intensive-margin DiD sample.",
                             "For each NACE 4-digit sector represented",
                             "among the sample's sellers (top + bot pool",
                             "combined): count of unique suppliers; count",
                             "of unique (buyer, seller) pairs; pre-period",
                             "(2010-2014) sum of emissions for the sample's",
                             "sellers in that sector; pre-period sum of",
                             "emissions for ALL Belgian EUTL-registered firms",
                             "in that sector (universe); coverage ratio.",
                             "Same for revenue (Annual Accounts). Sorted by",
                             "sample emissions descending. Totals in the last row."),
             label   = "tab:phase4_within_intensive_sector_coverage",
             align   = c("l", "l", "r", "r", "r", "r", "r", "r", "r", "r"))
print(xt,
      file               = file.path(OUTPUT_TAB,
                                     "phase4_within_intensive_sector_coverage.tex"),
      include.rownames   = FALSE,
      booktabs           = TRUE,
      sanitize.colnames.function = identity,
      sanitize.text.function     = identity,
      caption.placement  = "top",
      tabular.environment = "longtable",
      floating           = FALSE)

cat("\nDone.\n  tables:", OUTPUT_TAB, "\n")
