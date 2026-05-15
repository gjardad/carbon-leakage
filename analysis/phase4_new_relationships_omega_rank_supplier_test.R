###############################################################################
# phase4_new_relationships_omega_rank_supplier_test.R
#
# PURPOSE
#   Supplier-level tests to distinguish two observationally-equivalent stories
#   in the omega-rank event study at tau in {2005, 2017}:
#
#     Story A: buyer behavior unchanged. Same suppliers picked pre and post
#              tau. Those suppliers abated -> mean year-t rank of picks
#              declines.
#     Story B: buyer behavior shifted toward cleaner suppliers post tau.
#              Coincidentally the same suppliers picked because they're now
#              cleaner -> mean year-t rank of picks declines.
#
#   Both stories produce identical observational patterns in the picks
#   (same set of suppliers chosen, year-t rank declines, fixed-at-tau-1
#   rank flat). They differ only in what happens to a non-abater under
#   the buyer's choice rule.
#
#   TEST 1 (Story A vs B): supplier-level DiD on new-buyer count.
#     Unit: supplier x period (period in {pre, post}).
#     LHS:  log(1 + n_pairs)  -- new pairs supplier i forms in the period
#     RHS:  post:abater | seller + period FE
#     abater_i = 1{delta_rank_i < median(delta_rank)} where
#       delta_rank_i = rank_at_(tau+5) - rank_at_(tau-1)
#       (abater = supplier i lost more rank than the median EUTL firm
#        between tau-1 and tau+5 -- they "abated" relative to NACE4d peers)
#     Cluster: seller (supplier-level)
#     Interpretation:
#       post:abater > 0  -> abaters disproportionately gain new buyers
#                            post-event  ->  Story B (behavior change)
#       post:abater ~ 0  -> no differential  ->  Story A (unchanged)
#
#   TEST 2 (Is the user's concern empirically valid?):
#     Are the pre-event most-popular suppliers also the ones who abated
#     most? If yes, Story A is plausible and the year-t-rank trajectory
#     decline is hard to interpret. If no, the year-t-rank trajectory
#     decline cleanly reflects buyer behavior change (Story B).
#     Unit: supplier (cross-section).
#     LHS: delta_rank_i  (post-tau rank minus pre-tau rank; negative = abated)
#     RHS: log(1 + n_new_pre_i) | seller_nace4d FE
#     Cluster: seller_nace4d
#     Interpretation:
#       coefficient < 0  -> popular pre-event suppliers abated more
#                            -> user's concern empirically holds
#       coefficient ~ 0  -> no differential abatement by pre-event popularity
#                            -> year-t-rank spec is more cleanly Story B
#
# CAVEAT
#   delta_rank is measured over [tau-1, tau+5], which overlaps with the
#   post-period in which n_pairs_post is measured. Simultaneity caveat
#   applies (abatement and pickup may be jointly determined). Document
#   in interpretation; could be tightened later by measuring delta_rank
#   over [tau-1, tau+2] and n_pairs_post over [tau+3, tau+5].
#
# OUTPUTS (output_<machine>/tables/ and output_<machine>/figures/)
#   - phase4_new_relationships_omega_rank_supplier_test_coefs.{csv,tex}
#   - phase4_new_relationships_omega_rank_supplier_test_data_{tau}.csv
#   - phase4_new_relationships_omega_rank_supplier_popularity_vs_abatement_{tau}.{png,pdf}
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(ggplot2)
  library(xtable)
})

set.seed(20260516)

TAUS        <- c(2005L, 2017L)
WINDOW      <- 5L
B2B_YEAR_LO <- 2002L
B2B_YEAR_HI <- 2022L

ref_year_for_tau <- function(tau) if (tau == 2005L) 2005L else tau - 1L
end_year_for_tau <- function(tau) tau + WINDOW

write_tex_table <- function(dt, file, digits = 4, caption = NULL) {
  x <- xtable(as.data.frame(dt), digits = digits, caption = caption)
  print(x, file = file, include.rownames = FALSE, booktabs = TRUE,
        caption.placement = "top",
        sanitize.colnames.function = function(s) gsub("_", "\\\\_", s, fixed = TRUE),
        sanitize.text.function    = function(s) gsub("_", "\\\\_", s, fixed = TRUE))
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# 1. Load data (mirror omega_rank_did.R)
# ---------------------------------------------------------------------------
cat("Loading data...\n")

load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(B2B_YEAR_LO, B2B_YEAR_HI) &
           !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year))]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano),
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(
  vat = as.character(vat),
  year = as.integer(year),
  emissions, allocated_free, shortage, total_cost,
  nace4d = as.character(nace4d)
)]
rm(firm_exposure)
fe[, omega1 := ifelse(!is.na(shortage) & !is.na(total_cost) & total_cost > 0,
                      shortage / total_cost, NA_real_)]
ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]

# Attach seller NACE4d to b2b (with modal fallback)
seller_modal_nace <- aa[, .N, by = .(vat, nace4d)][
  order(vat, -N), .SD[1L], by = vat][, .(seller = vat, modal_nace4d = nace4d)]
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- merge(b2b, seller_modal_nace, by = "seller", all.x = TRUE)
b2b[is.na(seller_nace4d), seller_nace4d := modal_nace4d]
b2b[, modal_nace4d := NULL]
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d %in% ets_treated_nace4d]

# Supplier B2B tenure proxy: first year each seller appears anywhere in b2b
supplier_first_b2b <- b2b[, .(supplier_first_b2b_year = min(year)),
                          by = seller]

# First-year-observed and new pairs
first_year <- b2b[, .(year_first = min(year)), by = .(buyer, seller)]
new_rel <- first_year[year_first > B2B_YEAR_LO]
new_rel <- merge(new_rel,
                 b2b[, .(buyer, seller, year, seller_nace4d)],
                 by.x = c("buyer", "seller", "year_first"),
                 by.y = c("buyer", "seller", "year"))
cat(sprintf("  new pairs %d-%d: %d\n",
            B2B_YEAR_LO + 1L, B2B_YEAR_HI, nrow(new_rel)))

# Within-NACE4d-year percentile rank (Def 1)
rank_yearly <- fe[!is.na(omega1), .(seller = vat, year, seller_nace4d = nace4d,
                                    omega = omega1)]
rank_yearly[, rank := frank(omega, ties.method = "average") / .N,
            by = .(seller_nace4d, year)]
rank_yearly <- rank_yearly[, .(seller, year, seller_nace4d, rank)]

# ---------------------------------------------------------------------------
# 2. Per-tau: build supplier-level dataset + run two tests
# ---------------------------------------------------------------------------
test1_list       <- list()
test1_es_list    <- list()
test2_list       <- list()
test3_list       <- list()
test4_list       <- list()
stable_nace_list <- list()
# Per-tau, per-threshold lists of NACE4d names (used in TEST 5 below)
stable_naces_at <- list()

for (tau in TAUS) {
  cat(sprintf("\n========== tau = %d ==========\n", tau))
  ref_year <- ref_year_for_tau(tau)
  end_year <- end_year_for_tau(tau)
  cat(sprintf("  baseline year = %d, endpoint year = %d\n", ref_year, end_year))

  # Suppliers with rank defined in both endpoints
  rank_pre  <- rank_yearly[year == ref_year, .(seller, seller_nace4d, rank_pre = rank)]
  rank_post <- rank_yearly[year == end_year, .(seller, seller_nace4d, rank_post = rank)]
  suppliers <- merge(rank_pre, rank_post, by = c("seller", "seller_nace4d"))
  suppliers[, delta_rank := rank_post - rank_pre]
  cat(sprintf("  EUTL suppliers with rank in both %d and %d: %d\n",
              ref_year, end_year, nrow(suppliers)))

  # New-pair counts in pre and post periods at supplier level
  pre_win  <- c(tau - WINDOW, tau - 1L)
  post_win <- c(tau,           tau + WINDOW)
  n_pre  <- new_rel[year_first %between% pre_win,
                    .(n_new_pre = .N), by = seller]
  n_post <- new_rel[year_first %between% post_win,
                    .(n_new_post = .N), by = seller]
  suppliers <- merge(suppliers, n_pre,  by = "seller", all.x = TRUE)
  suppliers <- merge(suppliers, n_post, by = "seller", all.x = TRUE)
  suppliers <- merge(suppliers, supplier_first_b2b, by = "seller", all.x = TRUE)
  suppliers[is.na(n_new_pre),  n_new_pre  := 0L]
  suppliers[is.na(n_new_post), n_new_post := 0L]
  cat(sprintf("  suppliers with n_new_pre > 0:  %d (mean = %.2f)\n",
              sum(suppliers$n_new_pre > 0),  mean(suppliers$n_new_pre)))
  cat(sprintf("  suppliers with n_new_post > 0: %d (mean = %.2f)\n",
              sum(suppliers$n_new_post > 0), mean(suppliers$n_new_post)))

  # Save raw supplier-level dataset
  suppliers[, tau := tau]
  fwrite(suppliers,
         file.path(OUTPUT_TAB,
                   sprintf("phase4_new_relationships_omega_rank_supplier_test_data_%d.csv", tau)))

  # -------------------------------------------------------------------------
  # TEST 3: does pre-event rank predict subsequent rank change?
  #   (Mean-reversion test. If negative, high-rank suppliers tend to lose
  #   rank over time -- so even unchanged buyer behavior, picking from the
  #   same set of high-rank suppliers, would mechanically yield year-t rank
  #   decline. If null, year-t rank distribution is stable at the supplier
  #   level and the year-t-rank trajectory must reflect behavior.)
  # -------------------------------------------------------------------------
  m_t3 <- feols(delta_rank ~ rank_pre | seller_nace4d,
                cluster = ~ seller_nace4d,
                data = suppliers)
  cat("\n-- TEST 3: delta_rank ~ rank_pre | seller_nace4d FE --\n")
  cat("   negative => high-rank firms drop in rank (mean reversion);\n")
  cat("               Story A could mechanically generate year-t-rank decline\n")
  cat("   ~ zero  => rank distribution is stable; year-t-rank decline must\n")
  cat("              come from buyer behavior change (Story B)\n")
  print(coeftable(m_t3))

  t3 <- as.data.table(coeftable(m_t3), keep.rownames = "term")
  setnames(t3, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("estimate", "se", "t", "p"))
  t3[, n_obs := m_t3$nobs]
  t3[, tau   := tau]
  t3[, test  := "TEST_3_rank_mean_reversion"]
  test3_list[[as.character(tau)]] <- t3

  # -------------------------------------------------------------------------
  # TEST 4: decompose rank change into 4 supplier-side channels.
  #   omega = shortage / total_cost = (emissions - allocated_free) / total_cost.
  #   We regress Delta_log of each primitive on rank_pre:
  #     (a) emissions       -> abatement-related but confounded by output scale
  #     (b) allocated_free  -> policy-driven (free allocations)
  #     (c) total_cost      -> firm size / output proxy
  #     (d) emissions/cost  -> emission intensity (cleanest abatement measure)
  #   Negative coefficient on rank_pre means high-rank firms had a bigger
  #   negative Delta_log in that channel.
  # Caveat: mean reversion is partly mechanical even in log-changes because
  # rank_pre is a function of (emissions_pre, allocated_free_pre, cost_pre).
  # The pattern across channels is more informative than any single coef.
  # -------------------------------------------------------------------------
  fe_pre  <- fe[year == ref_year, .(seller = vat,
                                    emissions_pre      = emissions,
                                    allocated_free_pre = allocated_free,
                                    total_cost_pre     = total_cost)]
  fe_post <- fe[year == end_year, .(seller = vat,
                                    emissions_post      = emissions,
                                    allocated_free_post = allocated_free,
                                    total_cost_post     = total_cost)]
  decomp <- merge(suppliers[, .(seller, seller_nace4d, rank_pre)],
                  fe_pre,  by = "seller", all.x = TRUE)
  decomp <- merge(decomp, fe_post, by = "seller", all.x = TRUE)
  # Compute Delta_log for each primitive (positive values only).
  safe_dlog <- function(post, pre) {
    ifelse(!is.na(post) & !is.na(pre) & post > 0 & pre > 0,
           log(post) - log(pre), NA_real_)
  }
  decomp[, dlog_emissions := safe_dlog(emissions_post,      emissions_pre)]
  decomp[, dlog_allocated := safe_dlog(allocated_free_post, allocated_free_pre)]
  decomp[, dlog_cost      := safe_dlog(total_cost_post,     total_cost_pre)]
  decomp[, dlog_intensity := ifelse(!is.na(dlog_emissions) & !is.na(dlog_cost),
                                    dlog_emissions - dlog_cost, NA_real_)]

  channel_names <- c("dlog_emissions", "dlog_allocated", "dlog_cost", "dlog_intensity")
  for (ch in channel_names) {
    d_ch <- decomp[!is.na(get(ch))]
    if (nrow(d_ch) < 10L) next
    fml <- as.formula(sprintf("%s ~ rank_pre | seller_nace4d", ch))
    m_t4 <- feols(fml, cluster = ~ seller_nace4d, data = d_ch)
    cat(sprintf("\n-- TEST 4 [%s] ~ rank_pre | seller_nace4d FE (n=%d) --\n",
                ch, m_t4$nobs))
    print(coeftable(m_t4))
    t4 <- as.data.table(coeftable(m_t4), keep.rownames = "term")
    setnames(t4, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
             c("estimate", "se", "t", "p"))
    t4[, n_obs := m_t4$nobs]
    t4[, tau   := tau]
    t4[, test  := sprintf("TEST_4_%s", ch)]
    test4_list[[paste0(tau, "_", ch)]] <- t4
  }

  # -------------------------------------------------------------------------
  # Stable-NACE4d count: for each NACE4d with >= 3 EUTL firms tracked at both
  # endpoints, compute Spearman rho between rank_pre and rank_post within the
  # NACE4d. Report counts and sample sizes at thresholds {1.0, 0.9, 0.8}.
  # -------------------------------------------------------------------------
  per_nace <- suppliers[, .(n_firms = .N,
                            rho     = if (.N >= 3L)
                              suppressWarnings(cor(rank_pre, rank_post,
                                                   method = "spearman"))
                            else NA_real_),
                        by = seller_nace4d]
  per_nace_eligible <- per_nace[n_firms >= 3L & !is.na(rho)]
  cat(sprintf("\n  Stable-NACE4d analysis: %d NACE4d have >= 3 EUTL firms at both endpoints (out of %d total).\n",
              nrow(per_nace_eligible), nrow(per_nace)))

  for (thr in c(1.0, 0.9, 0.8)) {
    stable_naces <- per_nace_eligible[rho >= thr, seller_nace4d]
    n_naces  <- length(stable_naces)
    n_firms  <- sum(suppliers$seller_nace4d %in% stable_naces)
    # # new pairs in window with supplier in stable NACE4d
    n_pairs  <- nrow(new_rel[year_first %between% c(tau - WINDOW, tau + WINDOW) &
                             seller_nace4d %in% stable_naces])
    cat(sprintf("    rho >= %.1f: %d NACE4d, %d firms, %d new pairs in window.\n",
                thr, n_naces, n_firms, n_pairs))
    stable_nace_list[[paste0(tau, "_", thr)]] <- data.table(
      tau            = tau,
      threshold_rho  = thr,
      n_nace4d       = n_naces,
      n_firms        = n_firms,
      n_pairs_window = n_pairs
    )
    stable_naces_at[[paste0(tau, "_", thr)]] <- stable_naces
  }
  fwrite(per_nace_eligible,
         file.path(OUTPUT_TAB,
                   sprintf("phase4_new_relationships_omega_rank_supplier_test_stable_nace4d_%d.csv", tau)))

  # -------------------------------------------------------------------------
  # TEST 2: is pre-event popularity correlated with abatement?
  # -------------------------------------------------------------------------
  suppliers[, log_n_pre := log1p(n_new_pre)]
  m_t2 <- feols(delta_rank ~ log_n_pre | seller_nace4d,
                cluster = ~ seller_nace4d,
                data = suppliers)
  cat("\n-- TEST 2: delta_rank ~ log(1 + n_new_pre) | seller_nace4d FE --\n")
  cat("   negative => popular pre-event suppliers abated more (concern holds)\n")
  cat("   ~ zero  => no differential (year-t-rank trajectory cleanly Story B)\n")
  print(coeftable(m_t2))

  t2 <- as.data.table(coeftable(m_t2), keep.rownames = "term")
  setnames(t2, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("estimate", "se", "t", "p"))
  t2[, n_obs := m_t2$nobs]
  t2[, tau   := tau]
  t2[, test  := "TEST_2_popularity_vs_abatement"]
  test2_list[[as.character(tau)]] <- t2

  # Scatter plot for Test 2 (suppliers with n_new_pre > 0 for readability)
  p_t2 <- ggplot(suppliers[n_new_pre > 0],
                 aes(x = log_n_pre, y = delta_rank)) +
    geom_point(alpha = 0.35, color = "steelblue", size = 1.4) +
    geom_smooth(method = "lm", se = TRUE, color = "firebrick") +
    geom_hline(yintercept = 0, linetype = "dotted", color = "grey30") +
    labs(title    = sprintf("Pre-event popularity vs abatement (tau = %d)", tau),
         subtitle = sprintf("Each point = one EUTL supplier. Delta_rank = rank(%d) - rank(%d); negative = abated. Pre window = [%d, %d].",
                            end_year, ref_year, pre_win[1], pre_win[2]),
         x = "log(1 + n_new_pairs_pre)",
         y = sprintf("Delta_rank (rank_%d - rank_%d)", end_year, ref_year)) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank())
  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_new_relationships_omega_rank_supplier_popularity_vs_abatement_%d.png", tau)),
         p_t2, width = 8, height = 5, dpi = 200)
  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_new_relationships_omega_rank_supplier_popularity_vs_abatement_%d.pdf", tau)),
         p_t2, width = 8, height = 5)

  # -------------------------------------------------------------------------
  # TEST 1: Story A vs B (supplier-period DiD)
  # -------------------------------------------------------------------------
  median_dr <- median(suppliers$delta_rank, na.rm = TRUE)
  suppliers[, abater := as.integer(delta_rank < median_dr)]
  cat(sprintf("\n  median delta_rank = %.4f. abater = delta_rank < median (n=%d, %d non-abaters).\n",
              median_dr, sum(suppliers$abater == 1L),
              sum(suppliers$abater == 0L)))

  # -------------------------------------------------------------------------
  # Pre-event size measures per supplier (for the size-confound check below).
  # Activity = number of distinct buyers per year, averaged over [tau-5, tau-1].
  # Total transactions = rows in b2b per year, averaged over the same window.
  # -------------------------------------------------------------------------
  size_pre <- b2b[year %between% c(tau - WINDOW, tau - 1L),
                  .(customers_yr   = uniqueN(buyer),
                    n_trans_yr     = .N),
                  by = .(seller, year)]
  size_pre <- size_pre[, .(mean_customers_pre = mean(customers_yr),
                           mean_trans_pre     = mean(n_trans_yr)),
                       by = seller]
  suppliers <- merge(suppliers, size_pre, by = "seller", all.x = TRUE)
  suppliers[is.na(mean_customers_pre), mean_customers_pre := 0]
  suppliers[is.na(mean_trans_pre),     mean_trans_pre     := 0]
  suppliers[, log_customers_pre := log1p(mean_customers_pre)]
  suppliers[, log_trans_pre     := log1p(mean_trans_pre)]

  # Descriptive: abater vs non-abater means
  size_desc <- suppliers[, .(
    n_suppliers           = .N,
    mean_customers_pre    = mean(mean_customers_pre),
    median_customers_pre  = median(mean_customers_pre),
    mean_trans_pre        = mean(mean_trans_pre),
    median_trans_pre      = median(mean_trans_pre)
  ), by = abater]
  cat("\n  Pre-event size: abater vs non-abater\n")
  print(size_desc)

  supplier_long <- rbind(
    suppliers[, .(seller, seller_nace4d, tau, abater, log_customers_pre, log_trans_pre,
                  period = "pre",  n_pairs = n_new_pre)],
    suppliers[, .(seller, seller_nace4d, tau, abater, log_customers_pre, log_trans_pre,
                  period = "post", n_pairs = n_new_post)]
  )
  supplier_long[, post        := as.integer(period == "post")]
  supplier_long[, log1p_pairs := log1p(n_pairs)]

  # Main DiD: log(1+n_pairs) ~ post:abater | seller + period FE
  # post and abater are absorbed by seller + period FE; coefficient on
  # post:abater is the DiD estimate. SE clustered at supplier (= seller).
  m_t1 <- feols(log1p_pairs ~ post:abater | seller + period,
                cluster = ~ seller,
                data = supplier_long)
  cat("\n-- TEST 1: log(1 + n_pairs) ~ post:abater | seller + period FE --\n")
  cat("   > 0 => abaters gain more new buyers post-event (Story B; behavior change)\n")
  cat("   ~ 0 => no differential (Story A; behavior unchanged)\n")
  print(coeftable(m_t1))

  t1 <- as.data.table(coeftable(m_t1), keep.rownames = "term")
  setnames(t1, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("estimate", "se", "t", "p"))
  t1[, n_obs := m_t1$nobs]
  t1[, tau   := tau]
  t1[, test  := "TEST_1_storyA_vs_B"]
  test1_list[[as.character(tau)]] <- t1

  # -------------------------------------------------------------------------
  # TEST 1 with size control: same pooled DiD but with post:log_customers_pre
  # absorbing differential pre/post drift for larger vs smaller suppliers.
  # If the post:abater coefficient shrinks after adding this control, then
  # the abater indicator was partly picking up size-driven activity growth
  # that supplier FE can't absorb (supplier FE absorbs levels, not trends).
  # -------------------------------------------------------------------------
  m_t1_sizectrl <- feols(log1p_pairs ~ post:abater + post:log_customers_pre |
                                      seller + period,
                         cluster = ~ seller,
                         data = supplier_long)
  cat("\n-- TEST 1 + size control: log(1+n_pairs) ~ post:abater + post:log_customers_pre | seller + period --\n")
  print(coeftable(m_t1_sizectrl))

  t1_sc <- as.data.table(coeftable(m_t1_sizectrl), keep.rownames = "term")
  setnames(t1_sc, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("estimate", "se", "t", "p"))
  t1_sc[, n_obs := m_t1_sizectrl$nobs]
  t1_sc[, tau   := tau]
  t1_sc[, test  := "TEST_1_storyA_vs_B_size_ctrl"]
  test1_list[[paste0(tau, "_sc")]] <- t1_sc

  # -------------------------------------------------------------------------
  # TEST 1 (event-time version): same DiD but with rel-year interactions.
  #
  #   For each (supplier i, calendar year y in [tau-WINDOW, tau+WINDOW]):
  #     n_pairs_iy = count of new buyer pairs with supplier i in year y
  #
  #   log(1 + n_pairs_iy) ~ Sigma_e beta_e * 1{rel_year_y = e} * abater_i
  #                          + alpha_i + delta_y + eps_iy           (ref e=-1)
  #
  #   beta_e captures the differential new-buyer count between abaters and
  #   non-abaters at rel-year e, relative to rel-year = -1. Pre-trends
  #   parallel iff beta_e ~ 0 for e < -1. Story B iff beta_e > 0 for e >= 0.
  # -------------------------------------------------------------------------
  panel_es <- CJ(seller     = suppliers$seller,
                 year_first = (tau - WINDOW):(tau + WINDOW))
  n_pairs_iy <- new_rel[year_first %between% c(tau - WINDOW, tau + WINDOW),
                        .(n_pairs = .N), by = .(seller, year_first)]
  panel_es <- merge(panel_es, n_pairs_iy,
                    by = c("seller", "year_first"), all.x = TRUE)
  panel_es[is.na(n_pairs), n_pairs := 0L]
  panel_es <- merge(panel_es,
                    suppliers[, .(seller, seller_nace4d, abater,
                                  log_customers_pre, log_trans_pre,
                                  supplier_first_b2b_year)],
                    by = "seller")
  panel_es[, rel_year    := year_first - tau]
  panel_es[, log1p_pairs := log1p(n_pairs)]

  # Four event-time specs run on the same panel, all with the same
  # rel_year:abater coefficients of interest. Each spec adds one control
  # to isolate which (if any) flattens the pre-trends.
  #   base       : seller + year FE only
  #   +size      : + i(rel_year, log_customers_pre) -- pre-event size trend
  #   +nace4d    : + seller_nace4d^year_first FE     -- sectoral year trends
  #   +vintage   : + i(rel_year, supplier_first_b2b_year) -- supplier-age trend
  m_t1_es <- feols(log1p_pairs ~ i(rel_year, abater, ref = -1) |
                                seller + year_first,
                   cluster = ~ seller,
                   data    = panel_es)
  cat("\n-- TEST 1 (event-time, base): log(1+n_pairs) ~ i(rel_year, abater, ref=-1) | seller + year FE --\n")
  print(coeftable(m_t1_es))

  m_t1_es_sc <- feols(log1p_pairs ~ i(rel_year, abater, ref = -1) +
                                    i(rel_year, log_customers_pre, ref = -1) |
                                   seller + year_first,
                      cluster = ~ seller,
                      data    = panel_es)
  cat("\n-- TEST 1 event-time + size control (pre-event customers x rel_year) --\n")
  print(coeftable(m_t1_es_sc))

  m_t1_es_nace <- feols(log1p_pairs ~ i(rel_year, abater, ref = -1) |
                                     seller + year_first + seller_nace4d^year_first,
                        cluster = ~ seller,
                        data    = panel_es)
  cat("\n-- TEST 1 event-time + NACE4d x year FE --\n")
  print(coeftable(m_t1_es_nace))

  m_t1_es_vin <- feols(log1p_pairs ~ i(rel_year, abater, ref = -1) +
                                     i(rel_year, supplier_first_b2b_year, ref = -1) |
                                    seller + year_first,
                       cluster = ~ seller,
                       data    = panel_es)
  cat("\n-- TEST 1 event-time + supplier vintage x rel_year --\n")
  print(coeftable(m_t1_es_vin))

  tidy_t1_es <- function(fit, spec_label) {
    d <- as.data.table(coeftable(fit), keep.rownames = "term")
    setnames(d, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
             c("estimate", "se", "t", "p"))
    # Keep only abater interactions, drop the log_customers_pre × rel_year
    # controls (we only want abater coefs in the plot/output).
    d <- d[grepl("^rel_year::.*:abater$", term)]
    d[, rel_year := as.integer(sub("rel_year::(-?\\d+):.*", "\\1", term))]
    d[, tau     := tau]
    d[, spec    := spec_label]
    d[, test    := "TEST_1_storyA_vs_B_eventtime"]
    # Add the omitted reference row
    d <- rbind(d,
               data.table(term = "rel_year::-1:abater",
                          estimate = 0, se = NA_real_,
                          t = NA_real_, p = NA_real_,
                          rel_year = -1L, tau = tau,
                          spec = spec_label,
                          test = "TEST_1_storyA_vs_B_eventtime"),
               fill = TRUE)
    setorder(d, rel_year)
    d[, ci_lo := estimate - 1.96 * se]
    d[, ci_hi := estimate + 1.96 * se]
    d
  }
  t1_es <- rbindlist(list(
    tidy_t1_es(m_t1_es,      "base"),
    tidy_t1_es(m_t1_es_sc,   "size_ctrl"),
    tidy_t1_es(m_t1_es_nace, "nace4d_year_FE"),
    tidy_t1_es(m_t1_es_vin,  "vintage_ctrl")
  ), use.names = TRUE)
  test1_es_list[[as.character(tau)]] <- t1_es
}

# ---------------------------------------------------------------------------
# 2b. TEST 5: year-t-rank event study at tau=2017 restricted to NACE4d where
#     the supplier rank order is stable between 2016 and 2022 (Spearman rho
#     above threshold). In these NACE4d, year-t rank ~ rank-at-tau-1 by
#     construction, so the year-t-rank LHS is no longer confounded by
#     supplier-side rank evolution.
#
#     Specification (new-pair level):
#       rank_year_first_ij = Sigma_e beta_e * 1{year_first - 2017 = e}
#                              + alpha_buyer + gamma_NACE4d + eps_ij
#       ref e = -1 (year_first = 2016). SE two-way clustered: buyer x
#       supplier-NACE4d.
#
#     Three samples: rho == 1.0, rho >= 0.9, rho >= 0.8.
# ---------------------------------------------------------------------------
cat("\n========== TEST 5: year-t-rank ES at tau=2017, restricted to stable NACE4d ==========\n")

tau5 <- 2017L
window5 <- c(tau5 - WINDOW, tau5 + WINDOW)

# Build year-t rank panel under Def 1 (consistent with rank_pre / rank_post)
rank_yearly <- fe[!is.na(omega1), .(seller = vat, year,
                                    seller_nace4d = nace4d,
                                    omega = omega1)]
rank_yearly[, rank_yt := frank(omega, ties.method = "average") / .N,
            by = .(seller_nace4d, year)]
rank_yearly <- rank_yearly[, .(seller, year, seller_nace4d, rank_yt)]

# Attach to new pairs in window
nr_window <- new_rel[year_first %between% window5]
nr_window <- merge(nr_window, rank_yearly,
                   by.x = c("seller", "year_first", "seller_nace4d"),
                   by.y = c("seller", "year",       "seller_nace4d"))
nr_window[, rel_year := year_first - tau5]
cat(sprintf("  new pairs in [%d, %d] with year-t rank: %d\n",
            window5[1], window5[2], nrow(nr_window)))

test5_es_list <- list()
for (thr in c(1.0, 0.9, 0.8)) {
  stable_naces <- stable_naces_at[[paste0(tau5, "_", thr)]]
  d_sub <- nr_window[seller_nace4d %in% stable_naces]
  cat(sprintf("\n-- TEST 5, rho >= %.1f: %d NACE4d, %d new pairs --\n",
              thr, length(stable_naces), nrow(d_sub)))
  if (nrow(d_sub) < 30L) {
    cat("  (sample too small, skipping)\n")
    next
  }
  m_t5 <- feols(rank_yt ~ i(rel_year, ref = -1) | buyer + seller_nace4d,
                cluster = ~ buyer + seller_nace4d,
                data    = d_sub)
  print(coeftable(m_t5))
  t5 <- as.data.table(coeftable(m_t5), keep.rownames = "term")
  setnames(t5, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("estimate", "se", "t", "p"))
  t5[, rel_year := as.integer(sub("rel_year::(-?\\d+).*", "\\1", term))]
  t5[, tau     := tau5]
  t5[, threshold_rho := thr]
  t5[, n_obs   := m_t5$nobs]
  t5[, n_nace4d := length(stable_naces)]
  # Add omitted reference row (rel_year = -1, beta = 0)
  t5 <- rbind(t5,
              data.table(term = "rel_year::-1", estimate = 0, se = NA_real_,
                         t = NA_real_, p = NA_real_,
                         rel_year = -1L, tau = tau5, threshold_rho = thr,
                         n_obs = m_t5$nobs, n_nace4d = length(stable_naces)),
              fill = TRUE)
  setorder(t5, rel_year)
  t5[, ci_lo := estimate - 1.96 * se]
  t5[, ci_hi := estimate + 1.96 * se]
  test5_es_list[[as.character(thr)]] <- t5
}

if (length(test5_es_list) > 0L) {
  es5 <- rbindlist(test5_es_list, use.names = TRUE, fill = TRUE)
  fwrite(es5,
         file.path(OUTPUT_TAB,
                   "phase4_new_relationships_omega_rank_supplier_test_stable_yeartrank_event_study.csv"))

  es5[, spec_lab := factor(threshold_rho,
                           levels = c(1.0, 0.9, 0.8),
                           labels = c("rho == 1.0",
                                      "rho >= 0.9",
                                      "rho >= 0.8"))]
  p5 <- ggplot(es5, aes(x = rel_year, y = estimate,
                        color = spec_lab, group = spec_lab)) +
    geom_hline(yintercept = 0, linetype = "dotted", color = "grey30") +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "firebrick") +
    geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi),
                  width = 0.25,
                  position = position_dodge(width = 0.6)) +
    geom_point(size = 2, position = position_dodge(width = 0.6)) +
    scale_x_continuous(breaks = seq(-WINDOW, WINDOW, 1)) +
    scale_color_manual(values = c("rho == 1.0"  = "steelblue",
                                  "rho >= 0.9"  = "firebrick",
                                  "rho >= 0.8"  = "forestgreen"),
                       name = NULL) +
    labs(title    = "Year-t-rank event study at tau=2017, restricted to stable-NACE4d",
         subtitle = "Stable = within-NACE4d Spearman rho between 2016 and 2022 ranks above threshold. Coefs on rel_year dummies (ref = -1).",
         x = "Year relative to tau = 2017",
         y = "Coefficient on year-t rank") +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(),
          legend.position  = "bottom")
  ggsave(file.path(OUTPUT_FIG,
                   "phase4_new_relationships_omega_rank_supplier_test_stable_yeartrank_event_study.png"),
         p5, width = 10, height = 6, dpi = 200)
  ggsave(file.path(OUTPUT_FIG,
                   "phase4_new_relationships_omega_rank_supplier_test_stable_yeartrank_event_study.pdf"),
         p5, width = 10, height = 6)
}

# ---------------------------------------------------------------------------
# 3. TEST 1 event-time: combined CSV + per-tau plot
# ---------------------------------------------------------------------------
es_all <- rbindlist(test1_es_list, use.names = TRUE, fill = TRUE)
fwrite(es_all,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_supplier_test_event_study.csv"))

spec_levels <- c("base", "size_ctrl", "nace4d_year_FE", "vintage_ctrl")
spec_labels <- c(
  "Base (seller + year FE)",
  "+ size x rel_year",
  "+ NACE4d x year FE",
  "+ supplier vintage x rel_year"
)
spec_colors <- c(
  "Base (seller + year FE)"        = "steelblue",
  "+ size x rel_year"               = "firebrick",
  "+ NACE4d x year FE"              = "forestgreen",
  "+ supplier vintage x rel_year"   = "purple"
)

for (this_tau in TAUS) {
  d <- es_all[tau == this_tau]
  d[, spec_lab := factor(spec, levels = spec_levels, labels = spec_labels)]
  p <- ggplot(d,
              aes(x = rel_year, y = estimate,
                  color = spec_lab, group = spec_lab)) +
    geom_hline(yintercept = 0, linetype = "dotted", color = "grey30") +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "firebrick") +
    geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi),
                  width = 0.25,
                  position = position_dodge(width = 0.6)) +
    geom_point(size = 2, position = position_dodge(width = 0.6)) +
    scale_x_continuous(breaks = seq(-WINDOW, WINDOW, 1)) +
    scale_color_manual(values = spec_colors, name = NULL) +
    labs(title    = sprintf("TEST 1 event-time: abater vs non-abater new-buyer count (tau = %d)",
                            this_tau),
         subtitle = sprintf("Abater = supplier with below-median Delta_rank between %d and %d.",
                            ref_year_for_tau(this_tau), end_year_for_tau(this_tau)),
         x = sprintf("Year relative to tau = %d", this_tau),
         y = "Coefficient on rel_year:abater") +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(),
          legend.position  = "bottom")
  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_new_relationships_omega_rank_supplier_test_event_study_%d.png", this_tau)),
         p, width = 10, height = 6, dpi = 200)
  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_new_relationships_omega_rank_supplier_test_event_study_%d.pdf", this_tau)),
         p, width = 10, height = 6)
}

# ---------------------------------------------------------------------------
# 4. Combined output (pooled tests)
# ---------------------------------------------------------------------------
all_coefs <- rbindlist(c(test3_list, test4_list, test2_list, test1_list),
                       use.names = TRUE, fill = TRUE)

stable_nace_summary <- rbindlist(stable_nace_list, use.names = TRUE, fill = TRUE)
fwrite(stable_nace_summary,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_supplier_test_stable_nace4d_summary.csv"))
cat("\nStable-NACE4d summary (count at thresholds):\n")
print(stable_nace_summary)
fwrite(all_coefs,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_supplier_test_coefs.csv"))

# Pretty print table
print_tbl <- all_coefs[, .(test, tau, term,
                           estimate = round(estimate, 4),
                           se       = round(se,       4),
                           p        = round(p,        4),
                           n_obs)]
write_tex_table(print_tbl,
                file.path(OUTPUT_TAB,
                          "phase4_new_relationships_omega_rank_supplier_test_coefs.tex"),
                caption = "Supplier-level decomposition tests. TEST 2 (cross-section): does pre-event popularity correlate with abatement? Negative coefficient on log(1 + n\\_new\\_pre) means popular suppliers abated more. TEST 1 (supplier-period DiD): do abaters gain more new buyers post-tau? Positive coefficient on post:abater means yes (Story B; behavior change). SEs clustered at the appropriate level.")

cat("\nCombined supplier-test coefficients:\n")
print(print_tbl)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
