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
  shortage, total_cost,
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
test1_list <- list()
test2_list <- list()
test3_list <- list()

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

  supplier_long <- rbind(
    suppliers[, .(seller, seller_nace4d, tau, abater,
                  period = "pre",  n_pairs = n_new_pre)],
    suppliers[, .(seller, seller_nace4d, tau, abater,
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
}

# ---------------------------------------------------------------------------
# 3. Combined output
# ---------------------------------------------------------------------------
all_coefs <- rbindlist(c(test3_list, test2_list, test1_list),
                       use.names = TRUE, fill = TRUE)
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
