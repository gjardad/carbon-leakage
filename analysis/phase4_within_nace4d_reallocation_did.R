###############################################################################
# phase4_within_nace4d_reallocation_did.R
#
# PURPOSE
#   For each ETS event year (2008, 2013, 2017), estimate a within-cell DiD
#   on the within-NACE4d expenditure share:
#
#       share_ijt = alpha_ij + delta_t + beta * top_i * post_t + eps
#
#   Sample: cells in ETS-treated NACE4d with >=2 distinct suppliers in the
#           interval and >=1 supplier with omega > 0. Two suppliers per cell:
#           the top-omega and bottom-omega supplier (existing rule used in
#           phase4_within_nace4d_reallocation_plots.R, ties broken by larger
#           interval sales then VAT).
#
#   The bottom-omega supplier is the within-cell control: in the great
#   majority of cells (~85-98%) it has omega = 0 (a non-EUTL firm or an EUTL
#   firm with surplus allocation in the interval). beta therefore estimates
#   how much the carbon-cost-exposed supplier's expenditure share moved
#   relative to the alternative supplier in the same buyer x NACE4d basket
#   post-treatment.
#
#   Cell x role FE absorbs the time-invariant top-vs-bottom level for each
#   cell. Year FE absorbs aggregate trends. SE clustered at the cell
#   (buyer x NACE4d) level.
#
#   Also documents, for descriptive context, the share of top-omega
#   suppliers that are also the buyer's top supplier by interval sales
#   (rank 1) and the share of bottom-omega suppliers that are the buyer's
#   bottom by interval sales -- i.e., how much the omega-based selection
#   coincides with size-based selection within cells.
#
# OUTPUTS (output_<machine>/tables/)
#   - phase4_within_nace4d_reallocation_did_coefs.csv
#   - phase4_within_nace4d_reallocation_did_sanity.csv
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
})

YEAR_LO <- 2005L
YEAR_HI <- 2022L

INTERVALS <- list(
  "treat_2008" = list(years = c(2006L, 2007L), treat_year = 2008L),
  "treat_2013" = list(years = c(2011L, 2012L), treat_year = 2013L),
  "treat_2017" = list(years = c(2015L, 2016L), treat_year = 2017L)
)

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
                                       year, shortage, total_cost,
                                       nace4d)]
rm(firm_exposure)

ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]
ets_vats_all <- unique(fe$vat)

# Attach seller NACE4d to b2b and restrict to ETS-treated NACE4d sellers
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d %in% ets_treated_nace4d]

# Within-NACE4d denominator + share
b2b[, total_buyer_nace4d_spend := sum(sales),
    by = .(buyer, seller_nace4d, year)]
b2b[, share := sales / total_buyer_nace4d_spend]

# ---------------------------------------------------------------------------
# 2. Firm-omega per interval
# ---------------------------------------------------------------------------
build_firm_omega <- function(yrs) {
  d <- fe[year %in% yrs & !is.na(shortage) & !is.na(total_cost) & total_cost > 0,
          .(vat, year, shortage, total_cost)]
  o <- d[, .(n_yrs = .N,
             sum_short = sum(shortage),
             sum_cost  = sum(total_cost)),
         by = vat]
  o <- o[n_yrs == 2L & sum_cost > 0]
  o[, omega := sum_short / sum_cost]
  o[, .(vat, omega)]
}
firm_omega <- lapply(INTERVALS, function(s) build_firm_omega(s$years))

# ---------------------------------------------------------------------------
# 3. Build treated cells: top-omega and bottom-omega per (buyer, NACE4d)
# ---------------------------------------------------------------------------
build_cells_for_interval <- function(label) {
  spec <- INTERVALS[[label]]
  yrs  <- spec$years

  pre <- b2b[year %in% yrs,
             .(int_sales = sum(sales)),
             by = .(buyer, seller_nace4d, seller)]
  pre <- pre[int_sales > 0]

  cn <- pre[, .(n_supp = uniqueN(seller)), by = .(buyer, seller_nace4d)]
  multi <- cn[n_supp >= 2L, .(buyer, seller_nace4d)]
  pre <- merge(pre, multi, by = c("buyer", "seller_nace4d"))

  pre <- merge(pre, firm_omega[[label]],
               by.x = "seller", by.y = "vat", all.x = TRUE)
  pre[is.na(omega), omega := 0]

  setorder(pre, buyer, seller_nace4d, -omega, -int_sales, seller)
  top <- pre[, .SD[1L], by = .(buyer, seller_nace4d)]
  top <- top[omega > 0]                     # require >=1 omega>0 supplier
  keys <- top[, .(buyer, seller_nace4d)]

  setorder(pre, buyer, seller_nace4d, omega, -int_sales, seller)
  bot <- pre[, .SD[1L], by = .(buyer, seller_nace4d)]
  bot <- bot[keys, on = c("buyer", "seller_nace4d"), nomatch = 0L]

  cells <- rbind(
    top[, .(buyer, seller_nace4d, supplier_role = "top",
            seller, omega, int_sales)],
    bot[, .(buyer, seller_nace4d, supplier_role = "bot",
            seller, omega, int_sales)]
  )
  cells[, version    := label]
  cells[, treat_year := spec$treat_year]
  cells
}

cell_long <- rbindlist(lapply(names(INTERVALS), build_cells_for_interval),
                       use.names = TRUE)
cat(sprintf("\nTreated cells (one row per cell x role x version):\n"))
print(cell_long[, .(n_rows = .N,
                    n_cells = uniqueN(paste(buyer, seller_nace4d))),
                by = version])

# ---------------------------------------------------------------------------
# 4. Sanity check: top-omega vs top-share alignment within cells
# ---------------------------------------------------------------------------
cat("\nSanity check: top-omega vs top-share alignment within treated cells\n")

sanity_per_version <- function(label) {
  spec <- INTERVALS[[label]]
  yrs  <- spec$years

  pre <- b2b[year %in% yrs,
             .(int_sales = sum(sales)),
             by = .(buyer, seller_nace4d, seller)]
  pre <- pre[int_sales > 0]

  pre_t <- merge(
    pre,
    unique(cell_long[version == label, .(buyer, seller_nace4d)]),
    by = c("buyer", "seller_nace4d")
  )
  pre_t[, rank_share_desc := frank(-int_sales, ties.method = "min"),
        by = .(buyer, seller_nace4d)]
  pre_t[, rank_share_asc  := frank( int_sales, ties.method = "min"),
        by = .(buyer, seller_nace4d)]

  cl <- cell_long[version == label,
                  .(buyer, seller_nace4d, seller, omega_role = supplier_role)]
  pre_t <- merge(pre_t, cl, by = c("buyer", "seller_nace4d", "seller"),
                 all.x = TRUE)

  top_match <- pre_t[omega_role == "top",
                     mean(rank_share_desc == 1L, na.rm = TRUE)]
  bot_match <- pre_t[omega_role == "bot",
                     mean(rank_share_asc == 1L, na.rm = TRUE)]

  omg <- merge(pre_t,
               firm_omega[[label]], by.x = "seller", by.y = "vat",
               all.x = TRUE)
  omg[is.na(omega), omega := 0]
  spear <- omg[, {
    if (.N < 2L) NA_real_
    else suppressWarnings(cor(omega, int_sales, method = "spearman"))
  }, by = .(buyer, seller_nace4d)]
  setnames(spear, "V1", "rho")

  data.table(
    version          = label,
    n_treated_cells  = uniqueN(pre_t[, paste(buyer, seller_nace4d)]),
    pct_top_omega_is_top_share = round(100 * top_match, 1),
    pct_bot_omega_is_bot_share = round(100 * bot_match, 1),
    median_spearman_omega_share = round(median(spear$rho, na.rm = TRUE), 3),
    mean_spearman_omega_share   = round(mean  (spear$rho, na.rm = TRUE), 3)
  )
}

sanity <- rbindlist(lapply(names(INTERVALS), sanity_per_version))
print(sanity)
fwrite(sanity,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_reallocation_did_sanity.csv"))

# ---------------------------------------------------------------------------
# 5. Cell-role-year long panel for the regression
# ---------------------------------------------------------------------------
cat("\nBuilding cell-role-year long panel...\n")

yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])

panel <- cell_long[, .(year = YEAR_LO:YEAR_HI),
                   by = .(buyer, seller_nace4d, supplier_role,
                          seller, version, treat_year)]
panel <- merge(panel, yr_denom,
               by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
panel <- merge(panel, yr_sales,
               by = c("buyer", "seller_nace4d", "seller", "year"),
               all.x = TRUE)
panel[is.na(sales), sales := 0]
panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                        total_buyer_nace4d_spend <= 0,
                        NA_real_,
                        sales / total_buyer_nace4d_spend)]

panel[, top  := as.integer(supplier_role == "top")]
panel[, post := as.integer(year >= treat_year)]
panel[, cell_role_id := paste(buyer, seller_nace4d, supplier_role, sep = "::")]
panel[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]

cat(sprintf("  panel rows: %d (after dropping NA share: %d)\n",
            nrow(panel), nrow(panel[!is.na(share)])))

# ---------------------------------------------------------------------------
# 6. Regression -- one DiD per version
# ---------------------------------------------------------------------------
results <- list()

for (label in names(INTERVALS)) {
  cat(sprintf("\n=== %s ===\n", label))

  d <- panel[version == label & !is.na(share)]
  if (nrow(d) == 0L) next

  fit_did <- feols(
    share ~ i(post, top, ref = 0) | cell_role_id + year,
    data    = d,
    cluster = ~ cell_id
  )
  print(summary(fit_did))

  ct <- as.data.table(coeftable(fit_did), keep.rownames = "term")
  results[[label]] <- cbind(
    version         = label,
    n_obs           = nobs(fit_did),
    n_treated_cells = uniqueN(d$cell_id),
    ct
  )
}

coefs <- rbindlist(results, use.names = TRUE, fill = TRUE)
setnames(coefs,
         old = c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
         new = c("estimate", "std_error", "t_stat", "p_value"),
         skip_absent = TRUE)
fwrite(coefs,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_reallocation_did_coefs.csv"))

cat("\n\nAll coefficients:\n")
print(coefs[, .(version, term,
                est = round(estimate, 4),
                se  = round(std_error, 4),
                p   = round(p_value, 4),
                n_obs, n_treated_cells)])

cat("\nDone.\n")
cat("  Tables: ", OUTPUT_TAB, "\n", sep = "")
