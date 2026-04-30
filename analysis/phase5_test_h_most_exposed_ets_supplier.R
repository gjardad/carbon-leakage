###############################################################################
# phase5_test_h_most_exposed_ets_supplier.R
#
# Test H of Plan B (added post-stocktake; see STICKINESS_VS_CONCENTRATION.md
# "Next test"). Direct intensive-margin DiD on the 9% of B2B buyers who face
# a real substitution decision: do they reweight away from the most-heavily-
# carbon-exposed ETS supplier in their NACE-4d basket?
#
# Project conventions:
#   - Drops core-input pair filter (per user request).
#   - Drops regulated-intensive buyer NACE filter (per user request).
#   - Sample = "all B2B buyers with at least one ETS supplier within a
#     multi-supplier NACE 4d cell." Matches the 27,053-buyer / 9% framing
#     from G followup count [3].
#
# CONSTRUCTION:
#
#   Cell n = (buyer b, seller_NACE4d s_n4d).
#
#   For each cell n, identify j*(n) = the seller with the highest
#   firm_cost_share_regressor (Prep 2, mean 2012-14) among ETS sellers EVER
#   active in cell n. j* is fixed within a cell, time-invariant.
#
#   Cells without any ETS seller don't have a j* and are dropped.
#
#   Outcome at (n, t):
#     share_top_{n,t} = corr_sales_{j*(n), b, t}
#                       / Σ_{j' active in n at t} corr_sales_{j', b, t}
#     = 0 if j*(n) is inactive in year t.
#     Defined only when n has >= 2 active sellers in year t (substitution
#     feasibility).
#
# TWO SPECIFICATIONS (per user request):
#
#   Spec (a): cells where j*(n) is active in every year of the sample window
#             2005-2022 (no exit). The cleanest, most transparent case.
#
#   Spec (a)+(b): all cells with j*. For type-(b) cells (j* exits at some
#                 point), restrict observations to the window
#                 [t_first_j*(n), t_last_j*(n)] (j*'s tenure as a supplier
#                 to b in NACE 4d). Within this window, share_top = 0 in
#                 years j* is temporarily inactive. Type-(a) cells contribute
#                 their full sample window.
#
# REGRESSION:
#
#   share_top_{n,t} = β · firm_cost_share_{j*(n)} × Post_t
#                    + α_n + δ_{s_n4d, t} + ε
#   Post_t          = 1(t >= 2015)
#   α_n             = (buyer × seller_NACE4d) cell FE
#   δ_{s_n4d, t}    = seller_NACE4d × year FE
#   Cluster on buyer.
#
#   firm_cost_share_{j*(n)} is time-invariant per cell, so absorbed by α_n;
#   only β on the interaction is identified.
#
# PREDICTIONS:
#
#   β < 0  :  cells whose j* has higher cost-share lose more share post-2015
#             -- direct substitution evidence.
#   β ≈ 0  :  no differential reweighting by j*'s intensity -- shock-too-
#             small verdict.
#
# ROBUSTNESS:
#
#   R1: + buyer_NACE2d x year FE (absorb buyer-side timing shocks).
#   R2: extensive-margin outcome -- 1(j* active in year t) instead of share.
#
# OUTPUT (to OUTPUT_TAB / OUTPUT_FIG; per-machine subfolder via paths.R):
#
#   phase5_test_h_main.csv             : β under specs (a) and (a+b)
#   phase5_test_h_robustness.csv       : R1, R2
#   phase5_test_h_event_study.csv      : year-by-year coefficients (spec a+b)
#   phase5_test_h_event_study.pdf
#   phase5_test_h_by_buyer_nace2d.csv  : sector decomposition (spec a+b)
###############################################################################

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) {
  parent <- dirname(REPO_DIR)
  if (parent == REPO_DIR) stop("paths.R not found walking up from ",
                                normalizePath(getwd(), winslash = "/"),
                                ". cd into the repo root first.")
  REPO_DIR <- parent
}
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE))
  install.packages("fixest", repos = "https://cloud.r-project.org")
if (!requireNamespace("ggplot2", quietly = TRUE))
  install.packages("ggplot2", repos = "https://cloud.r-project.org")

library(data.table)
library(fixest)
library(ggplot2)

YEAR_LO   <- 2005L
YEAR_HI   <- 2022L
POST_FROM <- 2015L

# ---------------------------------------------------------------------------
# 1. Load B2B (selected sample), annual accounts (NACE), EUETS, fcs flavors
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
cat(sprintf("B2B active rows in [%d, %d]: %d\n", YEAR_LO, YEAR_HI, nrow(b2b)))

# Seller NACE 4d.
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_more_selected_sample)[
  , .(vat = vat_ano, year, nace5d)]
rm(df_annual_accounts_more_selected_sample)
aa[, year   := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa[, nace2d := substr(nace4d, 1, 2)]
aa <- unique(aa[, .(vat, year, nace4d, nace2d)])

seller_nace <- copy(aa); setnames(seller_nace,
  c("vat", "year", "nace4d", "nace2d"),
  c("seller", "year", "seller_nace4d", "seller_nace2d"))
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]

# Buyer NACE 2d (for R1 robustness).
buyer_nace <- copy(aa)[, .(buyer = vat, year, buyer_nace2d = nace2d)]
b2b <- merge(b2b, buyer_nace, by = c("buyer", "year"), all.x = TRUE)
# It's OK if buyer_nace2d is NA -- those rows just can't take R1.

# ETS flag.
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

# Time-invariant firm_cost_share_regressor; 0 for non-ETS or missing.
load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
b2b <- merge(b2b,
             cost_share_regressor[, .(seller = vat,
                                      fcs_reg = firm_cost_share_regressor)],
             by = "seller", all.x = TRUE)
b2b[is.na(fcs_reg), fcs_reg := 0]

# Drop contaminated VATs from 2021+.
contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
b2b <- b2b[!(seller %in% contaminated_vats & year >= 2021L)]

# Drop ETS sellers that have ETS status but no fcs_reg value (consistent with
# Test G/B). They're a tiny set; their fcs_reg = 0 would mis-rank them.
ets_with_fcs <- cost_share_regressor$vat
b2b <- b2b[!(seller_is_ets == 1L & !(seller %in% ets_with_fcs))]

cat(sprintf("After cleaning: %d rows; %d distinct buyers; %d distinct ETS sellers\n",
            nrow(b2b), uniqueN(b2b$buyer),
            uniqueN(b2b[seller_is_ets == 1L]$seller)))

# ---------------------------------------------------------------------------
# 2. Cell-year statistics: n_active_sellers, n_ets_sellers
# ---------------------------------------------------------------------------
setkey(b2b, buyer, seller_nace4d, year)
cell_yr <- b2b[, .(n_active_sellers = .N,
                   n_ets_sellers    = sum(seller_is_ets == 1L),
                   total_sales_cell = sum(corr_sales)),
               by = .(buyer, seller_nace4d, year)]

# ---------------------------------------------------------------------------
# 3. Identify j*(n) = max-fcs ETS seller ever active in cell n
# ---------------------------------------------------------------------------
ets_in_cell <- unique(b2b[seller_is_ets == 1L,
                          .(buyer, seller_nace4d, seller, fcs_reg)])
setorder(ets_in_cell, buyer, seller_nace4d, -fcs_reg, seller)
j_star <- ets_in_cell[, .SD[1L], by = .(buyer, seller_nace4d)]
setnames(j_star, c("seller", "fcs_reg"), c("j_star", "fcs_j_star"))

cat(sprintf("Cells with at least one ETS seller (= cells with j*): %d\n",
            nrow(j_star)))

# j*'s active span in cell n (within sample window).
j_star_b2b <- merge(b2b[, .(buyer, seller_nace4d, year, seller, corr_sales)],
                    j_star, by = c("buyer", "seller_nace4d"))
j_star_b2b <- j_star_b2b[seller == j_star]
j_window <- j_star_b2b[, .(t_first_j_star = min(year),
                            t_last_j_star  = max(year),
                            n_years_j_star_active = uniqueN(year)),
                       by = .(buyer, seller_nace4d, j_star, fcs_j_star)]
# Type (a): j* active in every year of the sample window.
# i.e., t_first_j_star == YEAR_LO AND t_last_j_star == YEAR_HI AND
# n_years_j_star_active == YEAR_HI - YEAR_LO + 1.
j_window[, is_type_a := as.integer(
  t_first_j_star == YEAR_LO &
  t_last_j_star  == YEAR_HI &
  n_years_j_star_active == (YEAR_HI - YEAR_LO + 1L))]

cat(sprintf("Type (a) cells (j* active every year %d-%d): %d (%.1f%%)\n",
            YEAR_LO, YEAR_HI,
            sum(j_window$is_type_a),
            100 * mean(j_window$is_type_a)))

# ---------------------------------------------------------------------------
# 4. j*'s sales per cell-year (NA if j* inactive that year)
# ---------------------------------------------------------------------------
j_star_sales <- j_star_b2b[, .(buyer, seller_nace4d, year,
                                corr_sales_j_star = corr_sales)]
setkey(j_star_sales, buyer, seller_nace4d, year)

# ---------------------------------------------------------------------------
# 5. Build the cell-year regression panel
# ---------------------------------------------------------------------------
# Start from cell-years with n_active_sellers >= 2 (substitution feasible).
panel <- cell_yr[n_active_sellers >= 2L]
# Restrict to cells with j*.
panel <- merge(panel, j_window, by = c("buyer", "seller_nace4d"))

# Bring in j*'s sales (NA -> j* inactive that year).
panel <- merge(panel, j_star_sales,
               by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
panel[, j_star_active := as.integer(!is.na(corr_sales_j_star))]
panel[is.na(corr_sales_j_star), corr_sales_j_star := 0]
panel[, share_top := corr_sales_j_star / total_sales_cell]

# Bring in buyer NACE 2d (use the most recent year's classification).
buyer_nace2d <- unique(buyer_nace[, .(buyer, buyer_nace2d)])
buyer_nace2d <- buyer_nace2d[!is.na(buyer_nace2d),
                              .SD[1L], by = buyer]   # one classification per buyer
panel <- merge(panel, buyer_nace2d, by = "buyer", all.x = TRUE)

panel[, post := as.integer(year >= POST_FROM)]
panel[, treat_post := fcs_j_star * post]
panel[, cell      := paste(buyer, seller_nace4d, sep = "_")]
panel[, sn4d_year := paste(seller_nace4d, year, sep = "_")]
panel[, bn2d_year := paste(buyer_nace2d,   year, sep = "_")]

cat(sprintf("\nFull regression panel (cell-years, n_active>=2 + j* exists): %d\n",
            nrow(panel)))
cat(sprintf("  Distinct cells (buyer x NACE 4d):                          %d\n",
            uniqueN(panel[, .(buyer, seller_nace4d)])))
cat(sprintf("  Distinct buyers:                                           %d\n",
            uniqueN(panel$buyer)))

# ---------------------------------------------------------------------------
# 6. Spec (a) and Spec (a)+(b) samples
# ---------------------------------------------------------------------------
samp_a   <- panel[is_type_a == 1L]
samp_ab  <- panel[is_type_a == 1L |
                    (year >= t_first_j_star & year <= t_last_j_star)]

cat(sprintf("\nSpec (a)   sample (j* always active 2005-2022): %d cell-years across %d cells\n",
            nrow(samp_a),  uniqueN(samp_a[, .(buyer, seller_nace4d)])))
cat(sprintf("Spec (a+b) sample (a + b restricted to tenure):  %d cell-years across %d cells\n",
            nrow(samp_ab), uniqueN(samp_ab[, .(buyer, seller_nace4d)])))

# ---------------------------------------------------------------------------
# 7. Main regressions
# ---------------------------------------------------------------------------
extract <- function(model, label, n_label) {
  if (is.null(model)) return(NULL)
  ct <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(ct, c("term", "estimate", "se", "tval", "pval"))
  ct <- ct[term == "treat_post"]
  ct[, spec := label]
  ct[, n    := nobs(model)]
  ct[, n_cells := n_label]
  ct[, .(spec, term, estimate, se, tval, pval, n, n_cells)]
}

m_a <- feols(share_top ~ treat_post | cell + sn4d_year,
             data = samp_a, cluster = ~ buyer)
m_ab <- feols(share_top ~ treat_post | cell + sn4d_year,
              data = samp_ab, cluster = ~ buyer)

cat("\n--- Spec (a) -- j* always active 2005-2022 ---\n")
print(summary(m_a))
cat("\n--- Spec (a+b) -- a + b restricted to j*'s tenure ---\n")
print(summary(m_ab))

main_out <- rbindlist(list(
  extract(m_a,  "spec_a",   uniqueN(samp_a[,  .(buyer, seller_nace4d)])),
  extract(m_ab, "spec_a_b", uniqueN(samp_ab[, .(buyer, seller_nace4d)]))
), use.names = TRUE)
fwrite(main_out, file.path(OUTPUT_TAB, "phase5_test_h_main.csv"))

# ---------------------------------------------------------------------------
# 8. Robustness: R1 (+ buyer_NACE2d x year FE), R2 (extensive margin)
# ---------------------------------------------------------------------------
samp_ab_with_bn2d <- samp_ab[!is.na(buyer_nace2d)]
m_r1 <- feols(share_top ~ treat_post | cell + sn4d_year + bn2d_year,
              data = samp_ab_with_bn2d, cluster = ~ buyer)
m_r2 <- feols(j_star_active ~ treat_post | cell + sn4d_year,
              data = samp_ab, cluster = ~ buyer)

cat("\n--- R1: spec (a+b) + buyer_NACE2d x year FE ---\n")
print(summary(m_r1))
cat("\n--- R2: extensive margin -- 1(j* active in year t) ---\n")
print(summary(m_r2))

robust_out <- rbindlist(list(
  extract(m_r1, "R1_spec_ab_plus_bn2d_year_FE",
          uniqueN(samp_ab_with_bn2d[, .(buyer, seller_nace4d)])),
  extract(m_r2, "R2_extensive_margin",
          uniqueN(samp_ab[, .(buyer, seller_nace4d)]))
), use.names = TRUE)
fwrite(robust_out, file.path(OUTPUT_TAB, "phase5_test_h_robustness.csv"))

# ---------------------------------------------------------------------------
# 9. Event study (year-by-year coefficients on fcs_j_star x year, spec a+b)
# ---------------------------------------------------------------------------
samp_ab[, year_f := factor(year)]
ref_year <- 2014L  # last pre-shock year
samp_ab[, year_f := relevel(year_f, ref = as.character(ref_year))]

m_es <- feols(
  share_top ~ i(year_f, fcs_j_star, ref = as.character(ref_year)) |
    cell + sn4d_year,
  data = samp_ab, cluster = ~ buyer)

es_dt <- as.data.table(summary(m_es)$coeftable, keep.rownames = "term")
setnames(es_dt, c("term", "estimate", "se", "tval", "pval"))
es_dt[, year := suppressWarnings(as.integer(gsub(".*::([0-9]+):.*", "\\1", term)))]
es_dt <- es_dt[!is.na(year)]
es_dt[, ci_lo := estimate - 1.96 * se]
es_dt[, ci_hi := estimate + 1.96 * se]
es_dt <- rbind(es_dt[, .(year, estimate, se, ci_lo, ci_hi)],
               data.table(year = ref_year, estimate = 0, se = 0,
                          ci_lo = 0, ci_hi = 0),
               fill = TRUE)
setorder(es_dt, year)
fwrite(es_dt, file.path(OUTPUT_TAB, "phase5_test_h_event_study.csv"))

p_es <- ggplot(es_dt, aes(x = year, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey40") +
  geom_vline(xintercept = ref_year + 0.5, linetype = "dotted",
             colour = "grey50") +
  geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi),
                  size = 0.3, colour = "navy") +
  labs(title = "Test H: share of most-exposed ETS supplier -- event study",
       subtitle = sprintf(
         "Coefficient on fcs_{j*(n)} x year_f (vs %d). Cell + seller_NACE4d x year FE; cluster on buyer.",
         ref_year),
       x = NULL, y = "Coefficient on fcs_{j*} x year") +
  theme_minimal(base_size = 11)

ggsave(file.path(OUTPUT_FIG, "phase5_test_h_event_study.pdf"),
       p_es, width = 9, height = 4.5)
cat(sprintf("Saved: %s\n",
            file.path(OUTPUT_FIG, "phase5_test_h_event_study.pdf")))

# ---------------------------------------------------------------------------
# 10. Sector decomposition by buyer NACE 2d (spec a+b)
# ---------------------------------------------------------------------------
sector_results <- samp_ab[!is.na(buyer_nace2d), {
  if (.N >= 200L && uniqueN(year) >= 2L &&
      uniqueN(fcs_j_star[fcs_j_star > 0]) >= 1L) {
    m <- tryCatch(feols(share_top ~ treat_post | cell + sn4d_year,
                        data = .SD, cluster = ~ buyer),
                  error = function(e) NULL)
    if (!is.null(m)) {
      ct <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
      setnames(ct, c("term", "estimate", "se", "tval", "pval"))
      ct <- ct[term == "treat_post"]
      list(estimate = ct$estimate, se = ct$se, tval = ct$tval, pval = ct$pval,
           n_obs = nobs(m))
    } else {
      list(estimate = NA_real_, se = NA_real_, tval = NA_real_, pval = NA_real_,
           n_obs = .N)
    }
  } else {
    list(estimate = NA_real_, se = NA_real_, tval = NA_real_, pval = NA_real_,
         n_obs = .N)
  }
}, by = buyer_nace2d]
setorder(sector_results, -n_obs)
print(sector_results)
fwrite(sector_results,
       file.path(OUTPUT_TAB, "phase5_test_h_by_buyer_nace2d.csv"))

# ---------------------------------------------------------------------------
# 11. Sample split by buyer's NACE 4d share of total input cost
# ---------------------------------------------------------------------------
# Substitution should be more visible in cells where the NACE 4d is a heavy
# part of the buyer's input bill. Define
#   nace_share_pre_{b,n} = mean over 2010-2014 of
#                          (Σ_j corr_sales_{j,b in n,t} / inputs_VAT_{b,t})
# i.e., the buyer's pre-shock average expenditure share on NACE 4d n out of
# total declared inputs. Time-invariant per cell, anchored pre-MSR-binding.
#
# Splits: above/below median; top quartile (Q4) vs bottom three (Q1-Q3).
# Run spec (a+b) regression on each subset separately.
# ---------------------------------------------------------------------------
NSHARE_LO <- 2010L
NSHARE_HI <- 2014L

# Buyer's total declared inputs (from VAT returns) per buyer-year.
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
buyer_inputs <- as.data.table(df_annual_accounts_more_selected_sample)[
  !is.na(inputs_VAT) & inputs_VAT > 0,
  .(buyer = vat_ano, year, inputs_VAT_total = inputs_VAT)]
rm(df_annual_accounts_more_selected_sample)

# Cell's pre-shock annual sales total, joined with buyer's pre-shock total
# inputs. Compute a per-(b,n,t) ratio then average across t in [2010, 2014].
cell_sales_pre <- cell_yr[year %between% c(NSHARE_LO, NSHARE_HI),
                           .(buyer, seller_nace4d, year,
                             sales_cell = total_sales_cell)]
cell_sales_pre <- merge(cell_sales_pre, buyer_inputs,
                         by = c("buyer", "year"), all.x = FALSE)
cell_sales_pre[, nace_share_yr := sales_cell / inputs_VAT_total]
nace_share_pre <- cell_sales_pre[, .(nace_share_pre = mean(nace_share_yr)),
                                  by = .(buyer, seller_nace4d)]

cat(sprintf("\nCells with nace_share_pre defined (pre-shock %d-%d): %d\n",
            NSHARE_LO, NSHARE_HI, nrow(nace_share_pre)))
cat("Distribution of nace_share_pre:\n")
print(quantile(nace_share_pre$nace_share_pre,
               c(0.1, 0.25, 0.5, 0.75, 0.9), na.rm = TRUE))

# Bring nace_share_pre into the regression panel.
samp_ab_split <- merge(samp_ab, nace_share_pre,
                        by = c("buyer", "seller_nace4d"), all.x = FALSE)
cat(sprintf("Spec (a+b) sample with nace_share_pre defined: %d cell-years across %d cells\n",
            nrow(samp_ab_split),
            uniqueN(samp_ab_split[, .(buyer, seller_nace4d)])))

# Compute quartile thresholds OVER CELLS (not over cell-years), so each cell
# is in exactly one bucket regardless of how many years it contributes.
cell_share <- unique(samp_ab_split[, .(buyer, seller_nace4d, nace_share_pre)])
qs <- quantile(cell_share$nace_share_pre, c(0.25, 0.5, 0.75), na.rm = TRUE)
cat(sprintf("Quartile thresholds: Q1=%.4f, median=%.4f, Q3=%.4f\n",
            qs[1], qs[2], qs[3]))

samp_ab_split[, nshare_above_median := as.integer(nace_share_pre >= qs[2])]
samp_ab_split[, nshare_quartile := fcase(
  nace_share_pre <  qs[1], "Q1",
  nace_share_pre <  qs[2], "Q2",
  nace_share_pre <  qs[3], "Q3",
  nace_share_pre >= qs[3], "Q4",
  default = NA_character_
)]
samp_ab_split[, nshare_top_q4 := as.integer(nshare_quartile == "Q4")]

run_subset <- function(d, label) {
  if (nrow(d) < 50L || uniqueN(d$year) < 2L ||
      uniqueN(d[fcs_j_star > 0]$fcs_j_star) < 2L) {
    return(data.table(subset = label, n_cells = uniqueN(d[, .(buyer, seller_nace4d)]),
                      n_obs = nrow(d), estimate = NA_real_, se = NA_real_,
                      tval = NA_real_, pval = NA_real_))
  }
  m <- tryCatch(feols(share_top ~ treat_post | cell + sn4d_year,
                      data = d, cluster = ~ buyer),
                error = function(e) NULL)
  if (is.null(m)) {
    return(data.table(subset = label, n_cells = uniqueN(d[, .(buyer, seller_nace4d)]),
                      n_obs = nrow(d), estimate = NA_real_, se = NA_real_,
                      tval = NA_real_, pval = NA_real_))
  }
  ct <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
  setnames(ct, c("term", "estimate", "se", "tval", "pval"))
  ct <- ct[term == "treat_post"]
  data.table(subset = label,
             n_cells = uniqueN(d[, .(buyer, seller_nace4d)]),
             n_obs = nobs(m),
             estimate = ct$estimate, se = ct$se,
             tval = ct$tval, pval = ct$pval)
}

split_results <- rbindlist(list(
  run_subset(samp_ab_split,                                     "all_with_share"),
  run_subset(samp_ab_split[nshare_above_median == 1L],          "above_median"),
  run_subset(samp_ab_split[nshare_above_median == 0L],          "below_median"),
  run_subset(samp_ab_split[nshare_quartile == "Q1"],            "Q1_lowest"),
  run_subset(samp_ab_split[nshare_quartile == "Q2"],            "Q2"),
  run_subset(samp_ab_split[nshare_quartile == "Q3"],            "Q3"),
  run_subset(samp_ab_split[nshare_quartile == "Q4"],            "Q4_highest"),
  run_subset(samp_ab_split[nshare_top_q4 == 1L],                "top_quartile_Q4"),
  run_subset(samp_ab_split[nshare_top_q4 == 0L],                "bottom_three_quartiles_Q1Q3")
), use.names = TRUE, fill = TRUE)

cat("\n=== Test H spec (a+b) split by buyer's NACE 4d input-cost share ===\n")
print(split_results)
fwrite(split_results,
       file.path(OUTPUT_TAB, "phase5_test_h_by_nace_share_split.csv"))

cat("\nTest H complete.\n")
