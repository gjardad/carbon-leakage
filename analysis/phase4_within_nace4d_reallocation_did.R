###############################################################################
# phase4_within_nace4d_reallocation_did.R
#
# PURPOSE
#   Estimate two specifications on within-NACE4d expenditure shares for each
#   ETS event year (2008, 2013, 2017):
#
#   1. REGULAR DiD (treated arm only):
#         share_ijt = alpha_ij + delta_t + beta * top_i * post_t + eps
#      Sample: cells in ETS-treated NACE4d with >=2 suppliers and >=1
#              omega>0 supplier in the interval. Two suppliers per cell:
#              top-omega and bottom-omega (existing rule).
#      beta : average post-vs-pre share gap top - bottom in treated cells.
#
#   2. TRIPLE-DiD (treated arm + placebo arm):
#         share_ijt = alpha_ij + delta_t,a
#                   + beta * top * post + gamma * top * post * treated_arm
#                   + eps
#      Treated arm: as above (top = top-omega, bottom = bottom-omega).
#      Placebo arm: cells in non-ETS-treated NACE4d with >=2 suppliers in
#                   the interval. Top = top-share supplier (by interval
#                   sales), bottom = bottom-share supplier. Selection rule
#                   has the same structural role ("most prominent" vs
#                   "least prominent") just measured on a different
#                   criterion since omega is undefined here.
#      gamma : differential post-vs-pre share gap that is specifically
#              MORE pronounced in treated cells than placebo cells.
#              Negative gamma => top-omega supplier loses share to bottom-
#              omega supplier MORE than top-share loses to bottom-share in
#              non-ETS sectors.
#
#   Cell x role FE absorbs the time-invariant top-vs-bottom level for each
#   cell. Year x arm FE absorbs aggregate trends within each arm.
#   SE clustered at the cell (buyer x NACE4d) level.
#
#   Also reports a SANITY CHECK on the comparability of the two arms:
#   share of top-omega suppliers that are also top-share within their cell,
#   share of bottom-omega suppliers that are also bottom-share, and Spearman
#   correlation of omega-rank vs share-rank within cells.
#
# OUTPUTS (output_<machine>/tables/)
#   - phase4_within_nace4d_reallocation_did_coefs.csv
#         coefficients for both specs, three versions.
#   - phase4_within_nace4d_reallocation_did_sanity.csv
#         per-version overlap stats between omega and share rankings.
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
# 1. Load b2b, AA, firm_exposure
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

# Attach seller NACE4d to b2b
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]

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
# 3. Cell construction: treated and placebo arms, per version
# ---------------------------------------------------------------------------
build_cells_for_interval <- function(label) {
  spec <- INTERVALS[[label]]
  yrs  <- spec$years

  # Suppliers a buyer transacted with during the interval (any NACE4d)
  pre <- b2b[year %in% yrs,
             .(int_sales = sum(sales)),
             by = .(buyer, seller_nace4d, seller)]
  pre <- pre[int_sales > 0]

  # Multi-supplier filter
  cn <- pre[, .(n_supp = uniqueN(seller)), by = .(buyer, seller_nace4d)]
  multi <- cn[n_supp >= 2L, .(buyer, seller_nace4d)]
  pre <- merge(pre, multi, by = c("buyer", "seller_nace4d"))

  # Tag NACE4d ETS-treatment status
  pre[, nace4d_ets_treated := as.integer(seller_nace4d %in% ets_treated_nace4d)]

  # Attach omega (only meaningful in ETS-treated NACE4d, but apply uniformly)
  pre <- merge(pre, firm_omega[[label]],
               by.x = "seller", by.y = "vat", all.x = TRUE)
  pre[is.na(omega), omega := 0]
  pre[, is_eutl := as.integer(seller %in% ets_vats_all)]

  # ---- Treated arm: ETS-NACE4d, >=1 omega>0 supplier
  cell_omega_max <- pre[, .(omega_max = max(omega)), by = .(buyer, seller_nace4d)]
  treated_keys <- merge(
    cell_omega_max[omega_max > 0, .(buyer, seller_nace4d)],
    multi, by = c("buyer", "seller_nace4d")
  )
  treated_keys <- merge(treated_keys,
                        unique(pre[nace4d_ets_treated == 1L,
                                   .(buyer, seller_nace4d)]),
                        by = c("buyer", "seller_nace4d"))
  pre_t <- pre[treated_keys, on = c("buyer", "seller_nace4d")]

  # Top = top-omega; tie-break by larger int_sales then VAT
  setorder(pre_t, buyer, seller_nace4d, -omega, -int_sales, seller)
  top_t <- pre_t[, .SD[1L], by = .(buyer, seller_nace4d)]
  setorder(pre_t, buyer, seller_nace4d, omega, -int_sales, seller)
  bot_t <- pre_t[, .SD[1L], by = .(buyer, seller_nace4d)]

  treated_long <- rbind(
    top_t[, .(buyer, seller_nace4d, supplier_role = "top",
              seller, omega, int_sales,
              arm = "treated")],
    bot_t[, .(buyer, seller_nace4d, supplier_role = "bot",
              seller, omega, int_sales,
              arm = "treated")]
  )

  # ---- Placebo arm: non-ETS-NACE4d only
  pre_p <- pre[nace4d_ets_treated == 0L]

  # Top = top-share (by interval sales); tie-break by VAT
  setorder(pre_p, buyer, seller_nace4d, -int_sales, seller)
  top_p <- pre_p[, .SD[1L], by = .(buyer, seller_nace4d)]
  setorder(pre_p, buyer, seller_nace4d, int_sales, seller)
  bot_p <- pre_p[, .SD[1L], by = .(buyer, seller_nace4d)]

  placebo_long <- rbind(
    top_p[, .(buyer, seller_nace4d, supplier_role = "top",
              seller, omega, int_sales,
              arm = "placebo")],
    bot_p[, .(buyer, seller_nace4d, supplier_role = "bot",
              seller, omega, int_sales,
              arm = "placebo")]
  )

  cells <- rbind(treated_long, placebo_long)
  cells[, version    := label]
  cells[, treat_year := spec$treat_year]
  cells
}

cell_long <- rbindlist(lapply(names(INTERVALS), build_cells_for_interval),
                       use.names = TRUE)
cat(sprintf("\nCells (one row per cell x role x version):\n"))
print(cell_long[, .(n_rows = .N,
                    n_cells = uniqueN(paste(buyer, seller_nace4d))),
                by = .(version, arm)])

# ---------------------------------------------------------------------------
# 4. Sanity check: do top-omega and top-share suppliers overlap in TREATED arm?
# ---------------------------------------------------------------------------
cat("\nSanity check: top-omega vs top-share alignment in TREATED cells\n")

sanity_per_version <- function(label) {
  spec <- INTERVALS[[label]]
  yrs  <- spec$years

  # Re-pull pre to get rank-by-share for each supplier in each treated cell
  pre <- b2b[year %in% yrs,
             .(int_sales = sum(sales)),
             by = .(buyer, seller_nace4d, seller)]
  pre <- pre[int_sales > 0]

  pre_t <- merge(
    pre,
    unique(cell_long[arm == "treated" & version == label,
                     .(buyer, seller_nace4d)]),
    by = c("buyer", "seller_nace4d")
  )
  pre_t[, rank_share_desc := frank(-int_sales, ties.method = "min"),
        by = .(buyer, seller_nace4d)]
  pre_t[, rank_share_asc  := frank( int_sales, ties.method = "min"),
        by = .(buyer, seller_nace4d)]

  # Now bring in the "is the top-omega supplier"/"is the bottom-omega supplier"
  # labels from cell_long
  cl <- cell_long[arm == "treated" & version == label,
                  .(buyer, seller_nace4d, seller,
                    omega_role = supplier_role)]
  pre_t <- merge(pre_t, cl, by = c("buyer", "seller_nace4d", "seller"),
                 all.x = TRUE)

  # For top-omega rows, check rank_share_desc == 1 (top by share too)
  top_match <- pre_t[omega_role == "top",
                     mean(rank_share_desc == 1L, na.rm = TRUE)]
  bot_match <- pre_t[omega_role == "bot",
                     mean(rank_share_asc == 1L, na.rm = TRUE)]

  # Spearman correlation between omega and int_sales within cell
  # (omega is in the merged table)
  omg <- merge(pre_t,
               firm_omega[[label]], by.x = "seller", by.y = "vat",
               all.x = TRUE)
  omg[is.na(omega), omega := 0]
  spear <- omg[, {
    if (.N < 2L) NA_real_
    else suppressWarnings(cor(omega, int_sales, method = "spearman"))
  }, by = .(buyer, seller_nace4d)]
  setnames(spear, "V1", "rho")
  spear_med <- median(spear$rho, na.rm = TRUE)
  spear_mean <- mean(spear$rho, na.rm = TRUE)

  data.table(
    version          = label,
    n_treated_cells  = uniqueN(pre_t[, paste(buyer, seller_nace4d)]),
    pct_top_omega_is_top_share = round(100 * top_match, 1),
    pct_bot_omega_is_bot_share = round(100 * bot_match, 1),
    median_spearman_omega_share = round(spear_med, 3),
    mean_spearman_omega_share   = round(spear_mean, 3)
  )
}

sanity <- rbindlist(lapply(names(INTERVALS), sanity_per_version))
print(sanity)
fwrite(sanity,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_reallocation_did_sanity.csv"))

# ---------------------------------------------------------------------------
# 5. Build cell-role-year long panel for the regressions
# ---------------------------------------------------------------------------
cat("\nBuilding cell-role-year long panel...\n")

# For each (cell, role, year), share = sales(buyer, chosen-supplier, year)
# / total_buyer_nace4d_spend(buyer, seller_nace4d, year). When the chosen
# supplier doesn't transact with the buyer in year t, sales = 0 -> share = 0.
# When the buyer doesn't transact in the NACE4d at all (denom = 0/NA),
# share is NA and the row drops out of the regression.

# Year-level supplier sales: keyed on (buyer, seller_nace4d, supplier, year)
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])

# Expand each (cell, role, supplier) over all years 2005:2022
cell_long_id <- cell_long[, .(buyer, seller_nace4d, supplier_role,
                              seller, arm, version, treat_year)]
panel <- cell_long_id[, .(year = YEAR_LO:YEAR_HI),
                      by = .(buyer, seller_nace4d, supplier_role,
                             seller, arm, version, treat_year)]
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

# Treatment indicators
panel[, top         := as.integer(supplier_role == "top")]
panel[, post        := as.integer(year >= treat_year)]
panel[, treated_arm := as.integer(arm == "treated")]

# Cell-role and year-arm IDs (factor for FEs)
panel[, cell_role_id := paste(buyer, seller_nace4d, supplier_role, sep = "::")]
panel[, year_arm_id  := paste(year, arm, sep = "::")]
panel[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]

cat(sprintf("  panel rows: %d (after dropping NA share: %d)\n",
            nrow(panel), nrow(panel[!is.na(share)])))

# ---------------------------------------------------------------------------
# 6. Regressions
# ---------------------------------------------------------------------------
results <- list()

for (label in names(INTERVALS)) {
  cat(sprintf("\n=== %s ===\n", label))

  d <- panel[version == label & !is.na(share)]
  if (nrow(d) == 0L) next

  # ---- (a) Regular DiD: treated arm only
  d_t <- d[arm == "treated"]
  fit_did <- feols(
    share ~ i(post, top, ref = 0) | cell_role_id + year,
    data = d_t,
    cluster = ~ cell_id
  )
  cat("\nRegular DiD (treated arm only):\n")
  print(summary(fit_did))

  # ---- (b) Triple DiD: both arms
  fit_triple <- feols(
    share ~ i(post, top, ref = 0)
          + i(post, top, ref = 0):treated_arm
          | cell_role_id + year_arm_id,
    data = d,
    cluster = ~ cell_id
  )
  cat("\nTriple DiD (treated + placebo arms):\n")
  print(summary(fit_triple))

  # Pull coefficients
  ct_did    <- as.data.table(coeftable(fit_did),    keep.rownames = "term")
  ct_triple <- as.data.table(coeftable(fit_triple), keep.rownames = "term")
  results[[paste0(label, "_DiD")]] <- cbind(
    version = label, spec = "regular DiD", n_obs = nobs(fit_did),
    n_treated_cells = uniqueN(d_t$cell_id),
    n_placebo_cells = 0L,
    ct_did
  )
  results[[paste0(label, "_triple")]] <- cbind(
    version = label, spec = "triple DiD", n_obs = nobs(fit_triple),
    n_treated_cells = uniqueN(d[treated_arm == 1L]$cell_id),
    n_placebo_cells = uniqueN(d[treated_arm == 0L]$cell_id),
    ct_triple
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

cat("\n\nAll coefficients saved to phase4_within_nace4d_reallocation_did_coefs.csv\n")
print(coefs[, .(version, spec, term,
                est = round(estimate, 4),
                se  = round(std_error, 4),
                p   = round(p_value, 4),
                n_obs, n_treated_cells, n_placebo_cells)])

cat("\nDone.\n")
cat("  Tables: ", OUTPUT_TAB, "\n", sep = "")
