# =============================================================================
# Compute average within-cell ETS share s_{E_n} on the Test H sample.
#
# Purpose:
#   The CES sigma-mapping in the paper currently uses (1 - s_{j*}) as the
#   denominator scaling for the within-NACE-4d test. The cleaner mapping uses
#   (1 - s_{E_n}), where s_{E_n} is the *total* ETS share of pre-shock spending
#   within the cell (b, n) -- i.e., the share of spending that absorbs the EUA
#   pass-through, including but not limited to j*. This script computes the
#   distribution of s_{E_n} across Test H cells so we can substitute the
#   corrected denominator into the headline sigma bound.
#
# Test H sample selection (matching phase5_test_h_most_exposed_ets_supplier.R):
#   - cell = (buyer, seller_nace4d) pair
#   - cell has >= 1 ETS seller (so j* exists)
#   - cell has n_active_sellers >= 2 in at least one year (substitution feasible)
#
# Output:
#   - mean and quantiles of s_{E_n} across cells
#   - sales-weighted mean (weighted by total pre-shock cell spend)
#   - Q4-of-pre-shock-NACE-4d-expenditure-share split (the "most-favorable
#     subset" we headline in discussion.tex)
# =============================================================================

# Path bootstrap.
REPO_DIR <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
  error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
})

YEAR_LO <- 2005L
YEAR_HI <- 2022L
NSHARE_LO <- 2010L
NSHARE_HI <- 2014L

# ---------------------------------------------------------------------------
# 1. Load b2b panel and ETS roster (mirrors test_h script setup)
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)[, .(seller = vat_i_ano,
                                                  buyer  = vat_j_ano,
                                                  year,
                                                  corr_sales = corr_sales_ij)]
rm(df_b2b_selected_sample)
b2b[, year := as.integer(year)]
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) &
             !is.na(corr_sales) & corr_sales > 0]

# Seller NACE 4d (from annual accounts, year-specific classification).
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_more_selected_sample)[
  , .(vat = vat_ano, year, nace5d)]
rm(df_annual_accounts_more_selected_sample)
aa[, year := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa <- unique(aa[, .(vat, year, nace4d)])
seller_nace <- copy(aa)
setnames(seller_nace, c("vat", "nace4d"), c("seller", "seller_nace4d"))
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]

# ETS roster.
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats_set <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats_set)]

# Drop contaminated VATs from 2021+ (consistent with paper).
contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
b2b <- b2b[!(seller %in% contaminated_vats & year >= 2021L)]

# ---------------------------------------------------------------------------
# 2. Cell-year aggregation
# ---------------------------------------------------------------------------
cell_yr <- b2b[, .(n_active_sellers = .N,
                   n_ets_sellers    = sum(seller_is_ets == 1L),
                   total_sales_cell = sum(corr_sales),
                   ets_sales_cell   = sum(corr_sales * seller_is_ets)),
               by = .(buyer, seller_nace4d, year)]

# ---------------------------------------------------------------------------
# 3. Test H sample: cells with >= 1 ETS seller (any year) AND >= 2 sellers
#    in at least one year
# ---------------------------------------------------------------------------
cells_with_ets <- unique(cell_yr[n_ets_sellers > 0L, .(buyer, seller_nace4d)])
cells_with_2plus <- unique(cell_yr[n_active_sellers >= 2L,
                                    .(buyer, seller_nace4d)])
test_h_cells <- merge(cells_with_ets, cells_with_2plus,
                      by = c("buyer", "seller_nace4d"))
cat(sprintf("Test H cells (>=1 ETS seller AND >=2 sellers in some year): %d\n",
            nrow(test_h_cells)))

# ---------------------------------------------------------------------------
# 4. Cell-level pre-shock ETS share s_{E_n}
# ---------------------------------------------------------------------------
# Two specifications -- both reported:
#   (a) cell-level mean over 2010-2014:
#         s_{E_n} = mean_{t in 2010-14} (ets_sales_cell_t / total_sales_cell_t)
#   (b) cell-level pooled (sum-then-divide):
#         s_{E_n} = sum_{t in 2010-14} ets_sales_cell_t / sum total_sales_cell_t
# ---------------------------------------------------------------------------
pre <- cell_yr[year %between% c(NSHARE_LO, NSHARE_HI)]
pre <- merge(pre, test_h_cells, by = c("buyer", "seller_nace4d"))

# Spec (a): mean of yearly ratios.
pre[, ets_share_yr := fifelse(total_sales_cell > 0,
                               ets_sales_cell / total_sales_cell, NA_real_)]
s_E_n_a <- pre[!is.na(ets_share_yr),
               .(s_E_n_meanyr = mean(ets_share_yr),
                 cell_pre_total_sales = sum(total_sales_cell)),
               by = .(buyer, seller_nace4d)]

# Spec (b): pooled.
s_E_n_b <- pre[, .(ets_pool = sum(ets_sales_cell),
                    total_pool = sum(total_sales_cell)),
                by = .(buyer, seller_nace4d)]
s_E_n_b[, s_E_n_pooled := fifelse(total_pool > 0, ets_pool / total_pool, NA_real_)]

s_E_n <- merge(s_E_n_a, s_E_n_b[, .(buyer, seller_nace4d, s_E_n_pooled)],
                by = c("buyer", "seller_nace4d"))

cat(sprintf("Cells with s_{E_n} computable (pre-shock %d-%d): %d\n",
            NSHARE_LO, NSHARE_HI, nrow(s_E_n)))

# ---------------------------------------------------------------------------
# 5. Distribution
# ---------------------------------------------------------------------------
cat("\nUnweighted distribution of s_{E_n} (mean of yearly ratios):\n")
print(round(quantile(s_E_n$s_E_n_meanyr,
                     c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95),
                     na.rm = TRUE), 4))
cat(sprintf("Mean: %.4f\n", mean(s_E_n$s_E_n_meanyr, na.rm = TRUE)))

cat("\nUnweighted distribution of s_{E_n} (pooled):\n")
print(round(quantile(s_E_n$s_E_n_pooled,
                     c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95),
                     na.rm = TRUE), 4))
cat(sprintf("Mean: %.4f\n", mean(s_E_n$s_E_n_pooled, na.rm = TRUE)))

# Sales-weighted mean.
s_E_n[, w := cell_pre_total_sales / sum(cell_pre_total_sales, na.rm = TRUE)]
cat(sprintf("\nSales-weighted mean of s_{E_n} (mean-of-yearly): %.4f\n",
            sum(s_E_n$s_E_n_meanyr * s_E_n$w, na.rm = TRUE)))

# ---------------------------------------------------------------------------
# 6. Q4-of-pre-shock-NACE-4d-expenditure-share split
#    (the headline subset in discussion.tex)
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
buyer_inputs <- as.data.table(df_annual_accounts_more_selected_sample)[
  !is.na(inputs_VAT) & inputs_VAT > 0,
  .(buyer = vat_ano, year, inputs_VAT_total = inputs_VAT)]
rm(df_annual_accounts_more_selected_sample)

cell_sales_pre <- cell_yr[year %between% c(NSHARE_LO, NSHARE_HI),
                           .(buyer, seller_nace4d, year,
                             sales_cell = total_sales_cell)]
cell_sales_pre <- merge(cell_sales_pre, buyer_inputs,
                         by = c("buyer", "year"), all.x = FALSE)
cell_sales_pre[, nace_share_yr := sales_cell / inputs_VAT_total]
nace_share_pre <- cell_sales_pre[, .(nace_share_pre = mean(nace_share_yr)),
                                  by = .(buyer, seller_nace4d)]

s_E_n <- merge(s_E_n, nace_share_pre,
                by = c("buyer", "seller_nace4d"), all.x = FALSE)
qs <- quantile(s_E_n$nace_share_pre, c(0.25, 0.5, 0.75), na.rm = TRUE)
cat("\nnace_share_pre quartile cutpoints (Q1/Q2/Q3):\n")
print(round(qs, 4))

s_E_n[, nshare_q := fifelse(
  nace_share_pre <  qs[1], "Q1",
  fifelse(nace_share_pre <  qs[2], "Q2",
          fifelse(nace_share_pre <  qs[3], "Q3", "Q4")))]

cat("\ns_{E_n} (mean-of-yearly) by nace_share_pre quartile:\n")
print(s_E_n[, .(n_cells = .N,
                 mean_s_E_n   = mean(s_E_n_meanyr, na.rm = TRUE),
                 median_s_E_n = median(s_E_n_meanyr, na.rm = TRUE),
                 sw_mean_s_E_n = sum(s_E_n_meanyr * cell_pre_total_sales, na.rm = TRUE)
                                  / sum(cell_pre_total_sales, na.rm = TRUE)),
            by = nshare_q][order(nshare_q)])

# ---------------------------------------------------------------------------
# 7. Save for downstream use
# ---------------------------------------------------------------------------
fwrite(s_E_n,
       file.path(REPO_DIR, "output_local", "tables", "s_E_n_test_h_cells.csv"))
cat(sprintf("\nWrote s_E_n distribution to %s\n",
            file.path("output_local/tables", "s_E_n_test_h_cells.csv")))

# ---------------------------------------------------------------------------
# 8. Compute s_{j*} per cell (j*'s pre-shock share within the cell), and the
#    joint moment E[s_{j*} * (1 - s_{E_n})] which is the exact denominator
#    that the CES sigma-mapping needs.
# ---------------------------------------------------------------------------
ets_in_cell <- unique(b2b[seller_is_ets == 1L,
                          .(buyer, seller_nace4d, seller, year, corr_sales)])
# Pre-shock ETS sales per (b, n, j) cell:
ets_pre <- ets_in_cell[year %between% c(NSHARE_LO, NSHARE_HI),
                        .(j_sales_pre = sum(corr_sales)),
                        by = .(buyer, seller_nace4d, seller)]
# Pick j* = max-pre-shock-sales ETS seller per cell (a stand-in for max-fcs).
setorder(ets_pre, buyer, seller_nace4d, -j_sales_pre)
j_star_pre <- ets_pre[, .SD[1L], by = .(buyer, seller_nace4d)]
setnames(j_star_pre, "j_sales_pre", "j_star_pre_sales")

# Cell pre-shock total sales (across all sellers).
cell_pre_total <- pre[, .(cell_pre_total = sum(total_sales_cell)),
                       by = .(buyer, seller_nace4d)]

j_star_pre <- merge(j_star_pre, cell_pre_total,
                     by = c("buyer", "seller_nace4d"))
j_star_pre[, s_j_star := fifelse(cell_pre_total > 0,
                                  j_star_pre_sales / cell_pre_total,
                                  NA_real_)]

s_E_n_full <- merge(s_E_n[, .(buyer, seller_nace4d, s_E_n = s_E_n_meanyr,
                               cell_pre_total_sales, nshare_q)],
                     j_star_pre[, .(buyer, seller_nace4d, s_j_star)],
                     by = c("buyer", "seller_nace4d"), all.x = FALSE)

s_E_n_full[, dprod := s_j_star * (1 - s_E_n)]

cat("\n--- Joint moment for CES sigma-mapping ---\n")
cat(sprintf("E[s_{j*}] (unweighted, full Test H):             %.4f\n",
            mean(s_E_n_full$s_j_star, na.rm = TRUE)))
cat(sprintf("E[(1 - s_{E_n})] (unweighted):                   %.4f\n",
            1 - mean(s_E_n_full$s_E_n, na.rm = TRUE)))
cat(sprintf("E[s_{j*} * (1 - s_{E_n})] (unweighted):          %.4f\n",
            mean(s_E_n_full$dprod, na.rm = TRUE)))
cat(sprintf("E[s_{j*} * (1 - s_{E_n})] (sales-weighted):      %.4f\n",
            with(s_E_n_full,
                 sum(dprod * cell_pre_total_sales, na.rm = TRUE)
                  / sum(cell_pre_total_sales, na.rm = TRUE))))

cat("\nBy nace_share_pre quartile (sales-weighted E[s_{j*}*(1-s_{E_n})]):\n")
print(s_E_n_full[, .(n_cells = .N,
                      sw_dprod = sum(dprod * cell_pre_total_sales, na.rm = TRUE)
                                  / sum(cell_pre_total_sales, na.rm = TRUE),
                      unw_dprod = mean(dprod, na.rm = TRUE)),
                  by = nshare_q][order(nshare_q)])

cat("\n=========================================================\n")
cat("PAPER-READY SUMMARY (corrected CES denominator)\n")
cat("=========================================================\n")
old_denom <- 0.30 * 0.70
new_denom_full_sw <- with(s_E_n_full,
  sum(dprod * cell_pre_total_sales, na.rm = TRUE)
   / sum(cell_pre_total_sales, na.rm = TRUE))
new_denom_full_unw <- mean(s_E_n_full$dprod, na.rm = TRUE)
new_denom_q4_sw <- s_E_n_full[nshare_q == "Q4",
  sum(dprod * cell_pre_total_sales, na.rm = TRUE)
   / sum(cell_pre_total_sales, na.rm = TRUE)]
new_denom_q4_unw <- s_E_n_full[nshare_q == "Q4",
                                 mean(dprod, na.rm = TRUE)]

cat(sprintf("Old denominator s_{j*}*(1-s_{j*}) at s_{j*}=0.30: %.4f\n", old_denom))
cat(sprintf("New denom (unweighted, full):                     %.4f\n", new_denom_full_unw))
cat(sprintf("New denom (sales-weighted, full):                 %.4f\n", new_denom_full_sw))
cat(sprintf("New denom (unweighted, Q4):                       %.4f\n", new_denom_q4_unw))
cat(sprintf("New denom (sales-weighted, Q4):                   %.4f\n", new_denom_q4_sw))
cat(sprintf("\nWidening factor (CI multiplier, sales-weighted full): %.2fx\n",
            old_denom / new_denom_full_sw))
cat(sprintf("Widening factor (CI multiplier, sales-weighted Q4):   %.2fx\n",
            old_denom / new_denom_q4_sw))
