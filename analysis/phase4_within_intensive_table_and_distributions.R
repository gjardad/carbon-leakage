###############################################################################
# phase4_within_intensive_table_and_distributions.R
#
# PURPOSE
#   Builds the paper artifacts for the within-NACE4d / intensive-margin
#   subsection:
#     (1) The missing DiD for the topQ_buyertotal heterogeneity cut.
#     (2) The combined 4-column DiD table: pooled + 3 heterogeneity cuts
#         (topQ_buyertotal, topQ_nace4dshare, topQ_omegagap),
#         across the three event years (2008, 2013, 2017).
#     (3) Three "fix-ideas-about-magnitudes" distribution figures:
#           (a) omega_top * (cell spend on top-omega supplier / buyer total cost)
#           (b) (cell spend on NACE4d / buyer total cost)
#           (c) omega_top - omega_bot
#     (4) Counterfactual savings figure: the buyer's potential savings as a
#         fraction of total input cost from substituting all of its top-omega
#         spend to the bottom-omega supplier, for rho in {0.25, 0.5, 0.75, 1}.
#
# DEPENDENCIES
#   - b2b_selected_sample.RData
#   - annual_accounts_selected_sample.RData
#   - annual_accounts_selected_sample_key_variables.RData
#   - phase3_firm_exposure.RData
#   - output_<machine>/tables/phase4_within_nace4d_reallocation_did_coefs.csv
#   - output_<machine>/tables/phase4_within_nace4d_reallocation_topQ_heterogeneity_did_coefs.csv
#
# OUTPUTS (output_<machine>/figures/, output_<machine>/tables/)
#   - phase4_within_nace4d_reallocation_topQ_buyertotal_did_coefs.csv
#   - phase4_within_nace4d_reallocation_did_table_combined.csv
#   - phase4_within_nace4d_reallocation_did_table_combined.tex
#   - phase4_within_nace4d_intensive_dist_shock_buyertotal.{png,pdf}
#   - phase4_within_nace4d_intensive_dist_nace4d_share.{png,pdf}
#   - phase4_within_nace4d_intensive_dist_omega_gap.{png,pdf}
#   - phase4_within_nace4d_intensive_savings_by_passthrough.{png,pdf}
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(fixest)
  library(xtable)
})

set.seed(20260513)

YEAR_LO <- 2005L
YEAR_HI <- 2022L

INTERVALS <- list(
  "treat_2008" = list(years = c(2006L, 2007L), treat_year = 2008L),
  "treat_2013" = list(years = c(2011L, 2012L), treat_year = 2013L),
  "treat_2017" = list(years = c(2015L, 2016L), treat_year = 2017L)
)

DIST_VERSION <- "treat_2017"  # for distribution + savings figures
RHO_GRID     <- c(0.25, 0.5, 0.75, 1.0)

# EUA annual mean prices used to convert omega (= shortage/total_cost,
# units tCO2 per euro of total cost) into a euro savings rate at a given
# point in time. Sourced from data/processed/phase3_eua_prices.RData.
EUA_SCENARIOS <- list(
  "2017" = list(eua = 5.76,  label = "EUA = 5.76 EUR/tCO2 (2017 annual mean, pre-MSR price)"),
  "2022" = list(eua = 80.24, label = "EUA = 80.24 EUR/tCO2 (2022 annual mean, post-MSR peak)")
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
  vat   = as.character(vat_ano),
  year  = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))
aa_kv <- as.data.table(df_annual_accounts_selected_sample_key_variables)[, .(
  vat = as.character(vat),
  year = as.integer(year),
  revenue, value_added, wage_bill
)]
rm(df_annual_accounts_selected_sample_key_variables)
aa_kv[, total_cost := (revenue - value_added) + wage_bill]
buyer_tc <- aa_kv[!is.na(total_cost) & total_cost > 0,
                  .(buyer = vat, year, buyer_total_cost = total_cost)]

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(vat = as.character(vat),
                                       year, shortage, total_cost,
                                       allocated_free)]
rm(firm_exposure)

# Compute firm-year omega: shortage / total_cost (carbon-cost share)
fe[, omega := ifelse(!is.na(total_cost) & total_cost > 0,
                     pmax(shortage, 0) / total_cost, NA_real_)]

# Attach seller NACE4d to B2B
b2b <- merge(b2b, aa, by.x = c("seller", "year"), by.y = c("vat", "year"),
             all.x = TRUE)
setnames(b2b, "nace4d", "seller_nace4d")
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d != ""]

cat(sprintf("  B2B rows after seller-NACE4d merge: %s\n",
            format(nrow(b2b), big.mark = ",")))

# Annual buyer-NACE4d spend (denominator for shares)
b2b[, total_buyer_nace4d_spend := sum(sales),
    by = .(buyer, seller_nace4d, year)]

# ---------------------------------------------------------------------------
# 2. Build cells per interval with all three heterogeneity scores
# ---------------------------------------------------------------------------
build_cells_interval <- function(version_label, years, treat_year) {
  yrs <- seq(years[1], years[2])

  # Interval-period seller-level aggregates within (buyer, seller_nace4d)
  seller_int <- b2b[year %in% yrs,
                    .(int_sales = sum(sales)),
                    by = .(buyer, seller_nace4d, seller)]

  # Attach interval-period omega for each seller
  fe_int <- fe[year %in% yrs,
               .(int_omega = mean(omega, na.rm = TRUE)),
               by = .(vat)]
  seller_int <- merge(seller_int, fe_int,
                      by.x = "seller", by.y = "vat", all.x = TRUE)
  seller_int[is.na(int_omega), int_omega := 0]

  # Require >=2 distinct suppliers and >=1 with omega>0 per cell
  setorder(seller_int, buyer, seller_nace4d, -int_omega, -int_sales, seller)
  seller_int[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
  cell_summary <- seller_int[, .(n_suppliers = .N,
                                 max_omega   = max(int_omega, na.rm = TRUE)),
                             by = .(buyer, seller_nace4d)]
  cell_summary <- cell_summary[n_suppliers >= 2L & max_omega > 0]

  cells <- merge(seller_int, cell_summary[, .(buyer, seller_nace4d)],
                 by = c("buyer", "seller_nace4d"))

  # Top-omega vs bottom-omega supplier within cell
  top_sup <- cells[rk == 1, .(buyer, seller_nace4d,
                              top_supplier = seller,
                              omega_top    = int_omega,
                              top_sales    = int_sales)]
  bot_sup <- cells[, .SD[.N], by = .(buyer, seller_nace4d)][,
                  .(buyer, seller_nace4d,
                    bot_supplier = seller,
                    omega_bot    = int_omega,
                    bot_sales    = int_sales)]

  cells_top_bot <- merge(top_sup, bot_sup, by = c("buyer", "seller_nace4d"))
  cells_top_bot[, omega_gap := omega_top - omega_bot]

  # NACE4d input share = sum_t in interval [spend(buyer, NACE4d, t)] /
  #                      sum_t in interval [buyer_total_cost(t)]
  spend_int <- b2b[year %in% yrs,
                   .(int_nace4d_spend = sum(sales)),
                   by = .(buyer, seller_nace4d)]
  bt_int <- buyer_tc[year %in% yrs,
                     .(sum_buyer_tc = sum(buyer_total_cost),
                       n_yr_tc      = .N),
                     by = buyer]
  cells_top_bot <- merge(cells_top_bot, spend_int,
                         by = c("buyer", "seller_nace4d"))
  cells_top_bot <- merge(cells_top_bot, bt_int, by = "buyer", all.x = TRUE)
  cells_top_bot[, nace4d_input_share := ifelse(!is.na(sum_buyer_tc) &
                                                 sum_buyer_tc > 0,
                                               int_nace4d_spend / sum_buyer_tc,
                                               NA_real_)]

  # Dollar shock at buyer's total cost from the top-omega supplier:
  #   shock_buyertotal = omega_top * (top_sales / buyer_total_cost)
  cells_top_bot[, top_supplier_share_of_buyer := ifelse(
    !is.na(sum_buyer_tc) & sum_buyer_tc > 0,
    top_sales / sum_buyer_tc, NA_real_
  )]
  cells_top_bot[, shock_buyertotal := omega_top * top_supplier_share_of_buyer]

  # Top-quartile flags per cut (within version)
  qtl_share <- quantile(cells_top_bot$nace4d_input_share, 0.75, na.rm = TRUE)
  qtl_gap   <- quantile(cells_top_bot$omega_gap,           0.75, na.rm = TRUE)
  qtl_buy   <- quantile(cells_top_bot$shock_buyertotal,    0.75, na.rm = TRUE)
  cells_top_bot[, topQ_nace4dshare := nace4d_input_share >= qtl_share &
                                       !is.na(nace4d_input_share)]
  cells_top_bot[, topQ_omegagap    := omega_gap           >= qtl_gap   &
                                       !is.na(omega_gap)]
  cells_top_bot[, topQ_buyertotal  := shock_buyertotal    >= qtl_buy   &
                                       !is.na(shock_buyertotal)]

  cells_top_bot[, version    := version_label]
  cells_top_bot[, treat_year := treat_year]
  cells_top_bot[]
}

cells_list <- lapply(names(INTERVALS), function(lab) {
  iv <- INTERVALS[[lab]]
  cat(sprintf("Building cells for %s...\n", lab))
  build_cells_interval(lab, iv$years, iv$treat_year)
})
cells_all <- rbindlist(cells_list, use.names = TRUE, fill = TRUE)

cat(sprintf("Cells built: %s total rows across versions.\n",
            format(nrow(cells_all), big.mark = ",")))

# Save cells with all three scores
fwrite(cells_all, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_cells_all_scores.csv"))

# ---------------------------------------------------------------------------
# 3. Build long panel for the topQ_buyertotal subset, then run DiD
# ---------------------------------------------------------------------------
build_long_for_topQ <- function(flag_col, cells_dt) {
  sub <- cells_dt[get(flag_col) == TRUE,
                  .(buyer, seller_nace4d, version, treat_year,
                    top_supplier, bot_supplier)]
  if (nrow(sub) == 0L) return(data.table())

  long_top <- sub[, .(buyer, seller_nace4d, version, treat_year,
                      seller = top_supplier,
                      supplier_role = "top")]
  long_bot <- sub[, .(buyer, seller_nace4d, version, treat_year,
                      seller = bot_supplier,
                      supplier_role = "bot")]
  long <- rbind(long_top, long_bot)

  panel <- long[, .(year = YEAR_LO:YEAR_HI),
                by = .(buyer, seller_nace4d, version, treat_year,
                       seller, supplier_role)]

  yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                             total_buyer_nace4d_spend)])
  yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

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
  panel
}

cat("Building long panel for topQ_buyertotal...\n")
panel_buyer <- build_long_for_topQ("topQ_buyertotal", cells_all)

run_did_per_version <- function(panel_dt, cut_label) {
  out <- list()
  for (label in names(INTERVALS)) {
    d <- panel_dt[version == label & !is.na(share)]
    if (nrow(d) == 0L) next
    d[, top  := as.integer(supplier_role == "top")]
    d[, post := as.integer(year >= treat_year)]
    d[, cell_role_id := paste(buyer, seller_nace4d, supplier_role, sep = "::")]
    d[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]
    fit <- feols(share ~ i(post, top, ref = 0) | cell_role_id + year,
                 data = d, cluster = ~ cell_id)
    ct <- as.data.table(coeftable(fit), keep.rownames = "term")
    setnames(ct, old = c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
                 new = c("estimate", "std_error", "t_stat", "p_value"),
                 skip_absent = TRUE)
    out[[label]] <- cbind(cut = cut_label, version = label,
                          n_obs = nobs(fit),
                          n_treated_cells = uniqueN(d$cell_id), ct)
  }
  rbindlist(out, use.names = TRUE, fill = TRUE)
}

did_buyer <- run_did_per_version(panel_buyer, "Top quartile by buyer-total shock")
fwrite(did_buyer, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_reallocation_topQ_buyertotal_did_coefs.csv"))
cat("topQ_buyertotal DiD done.\n")

# ---------------------------------------------------------------------------
# 4. Combine all four DiD specifications into one table
# ---------------------------------------------------------------------------
pooled <- fread(file.path(OUTPUT_TAB,
                          "phase4_within_nace4d_reallocation_did_coefs.csv"))
pooled[, cut := "Pooled (no heterogeneity)"]

het <- fread(file.path(OUTPUT_TAB,
             "phase4_within_nace4d_reallocation_topQ_heterogeneity_did_coefs.csv"))

did_all <- rbind(
  pooled[, .(cut, version, n_obs, n_treated_cells, term,
             estimate, std_error, t_stat, p_value)],
  did_buyer[, .(cut, version, n_obs, n_treated_cells, term,
                estimate, std_error, t_stat, p_value)],
  het[, .(cut, version, n_obs, n_treated_cells, term,
          estimate, std_error, t_stat, p_value)],
  use.names = TRUE, fill = TRUE
)

cut_order <- c("Pooled (no heterogeneity)",
               "Top quartile by buyer-total shock",
               "Top quartile by NACE4d input share",
               "Top quartile by omega gap")
did_all[, cut := factor(cut, levels = cut_order)]
setorder(did_all, version, cut)
fwrite(did_all, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_reallocation_did_table_combined.csv"))

# Wide pivot for paper LaTeX
wide <- dcast(did_all,
              version ~ cut,
              value.var = c("estimate", "std_error", "p_value",
                            "n_treated_cells"))
wide_rows <- list()
for (lab in c("treat_2008", "treat_2013", "treat_2017")) {
  ev_year <- INTERVALS[[lab]]$treat_year
  for (cut_name in cut_order) {
    r <- did_all[version == lab & cut == cut_name]
    if (nrow(r) == 0L) next
    wide_rows[[length(wide_rows) + 1L]] <- data.table(
      `Event year`   = ev_year,
      `Heterogeneity cut` = cut_name,
      `beta`         = sprintf("%.3f", r$estimate),
      `SE`           = sprintf("(%.3f)", r$std_error),
      `p`            = sprintf("%.3f", r$p_value),
      `N treated cells` = format(r$n_treated_cells, big.mark = ",")
    )
  }
}
combined_long <- rbindlist(wide_rows, use.names = TRUE)

# Build the LaTeX table by hand: rows = event years, columns = 4 cuts.
build_latex_4col <- function(did_all) {
  versions <- c("treat_2008", "treat_2013", "treat_2017")
  event_years <- c("Phase II onset (2008)",
                   "Phase III onset (2013)",
                   "MSR (2017)")
  cuts <- cut_order

  cell_fmt <- function(beta, se, pv, n) {
    if (length(beta) == 0L || is.na(beta)) return("---")
    sig <- ifelse(pv < 0.001, "$^{***}$",
                  ifelse(pv < 0.01, "$^{**}$",
                         ifelse(pv < 0.05, "$^{*}$",
                                ifelse(pv < 0.10, "$^{\\dagger}$", ""))))
    sprintf("\\makecell{%.3f%s \\\\ \\footnotesize{(%.3f)} \\\\ \\footnotesize{N=%s}}",
            beta, sig, se, format(n, big.mark = ","))
  }

  body <- ""
  for (i in seq_along(versions)) {
    v <- versions[i]; ev <- event_years[i]
    body <- paste0(body, "\n", ev)
    for (cut_name in cuts) {
      r <- did_all[version == v & cut == cut_name]
      body <- paste0(body, " & ",
                     cell_fmt(r$estimate, r$std_error, r$p_value,
                              r$n_treated_cells))
    }
    body <- paste0(body, " \\\\\\addlinespace")
  }

  header <- paste0(
    "% Requires \\usepackage{makecell,booktabs} in main.tex\n",
    "\\begin{tabular}{lcccc}\n",
    "\\toprule\n",
    " & & \\multicolumn{3}{c}{Top quartile by} \\\\\n",
    "\\cmidrule(lr){3-5}\n",
    "Treatment period & Pooled & Cost shock & Input share & Exposure gap \\\\\n",
    "\\midrule"
  )
  footer <- paste0(
    "\n\\bottomrule\n",
    "\\end{tabular}\n",
    "% Notes: Cells report $\\hat{\\beta}$ on (post $\\times$ top-omega) in the within-cell DiD, ",
    "two-way clustered SE in parentheses, and the number of treated cells. ",
    "Significance: $^{\\dagger}\\,p<0.10$, $^{*}\\,p<0.05$, $^{**}\\,p<0.01$, $^{***}\\,p<0.001$."
  )

  paste0(header, body, footer)
}

tex_table <- build_latex_4col(did_all)
writeLines(tex_table,
           file.path(OUTPUT_TAB,
                     "phase4_within_nace4d_reallocation_did_table_combined.tex"))
cat("Combined 4-col DiD table written.\n")

# ---------------------------------------------------------------------------
# 5. Three distribution figures (using DIST_VERSION cells)
# ---------------------------------------------------------------------------
cat(sprintf("Building distribution figures using version %s...\n",
            DIST_VERSION))
cells_dist <- cells_all[version == DIST_VERSION &
                          !is.na(shock_buyertotal) &
                          !is.na(nace4d_input_share) &
                          !is.na(omega_gap)]

base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        plot.title    = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(size = 10, color = "grey30"))

plot_dist <- function(x, xlab, title, subtitle, log_x = FALSE) {
  d <- data.table(val = x[is.finite(x) & x > 0])
  if (nrow(d) == 0L) {
    cat(sprintf("No positive values for %s\n", title)); return(NULL)
  }
  qs <- quantile(d$val, c(0.50, 0.75, 0.90, 0.99), na.rm = TRUE)
  subtitle_full <- sprintf(
    "%s\nMedian = %s | p75 = %s | p90 = %s | p99 = %s | N = %s cells",
    subtitle,
    formatC(qs[1], format = "g", digits = 3),
    formatC(qs[2], format = "g", digits = 3),
    formatC(qs[3], format = "g", digits = 3),
    formatC(qs[4], format = "g", digits = 3),
    format(nrow(d), big.mark = ",")
  )
  p <- ggplot(d, aes(x = val)) +
    geom_histogram(bins = 60, fill = "steelblue", color = "white", alpha = 0.85) +
    geom_vline(xintercept = qs[2], linetype = "dashed", color = "firebrick") +
    annotate("text", x = qs[2], y = Inf, label = " p75",
             vjust = 1.5, hjust = 0, color = "firebrick", size = 3) +
    labs(title = title, subtitle = subtitle_full,
         x = xlab, y = "Number of cells") +
    base_theme
  if (log_x) p <- p + scale_x_log10(labels = scales::comma_format())
  p
}

p_shock <- plot_dist(
  cells_dist$shock_buyertotal,
  expression(omega[top] %*% "(top-supplier spend / buyer total cost)"),
  "Distribution of the dollar shock at the buyer's total cost",
  sprintf("Across (buyer, NACE4d) cells with >=2 ETS-relevant suppliers in %s pre-period.",
          DIST_VERSION),
  log_x = TRUE
)
p_nshare <- plot_dist(
  cells_dist$nace4d_input_share,
  "Cell spend on NACE4d / buyer total cost",
  "Distribution of NACE4d inputs as share of buyer's total input cost",
  sprintf("Across (buyer, NACE4d) cells with >=2 ETS-relevant suppliers in %s pre-period.",
          DIST_VERSION),
  log_x = TRUE
)
p_gap <- plot_dist(
  cells_dist$omega_gap,
  expression(omega[top] - omega[bot]),
  expression("Distribution of " * omega[top] - omega[bot]),
  sprintf("Across (buyer, NACE4d) cells with >=2 ETS-relevant suppliers in %s pre-period.",
          DIST_VERSION),
  log_x = TRUE
)

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_shock_buyertotal.png"),
       p_shock, width = 8, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_shock_buyertotal.pdf"),
       p_shock, width = 8, height = 5)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_nace4d_share.png"),
       p_nshare, width = 8, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_nace4d_share.pdf"),
       p_nshare, width = 8, height = 5)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_omega_gap.png"),
       p_gap, width = 8, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_omega_gap.pdf"),
       p_gap, width = 8, height = 5)
cat("Three distribution figures written.\n")

# ---------------------------------------------------------------------------
# 6. Counterfactual savings figures: TWO versions, one per EUA scenario
#    savings(b,n,rho,EUA) = rho * EUA * (omega_top - omega_bot)
#                                * (cell spend / buyer total cost)
#    omega here is shortage/total_cost (tCO2 per euro of total cost), so the
#    EUA multiplier converts the savings into a euro rate.
# ---------------------------------------------------------------------------
cat("Building counterfactual savings figures (two EUA scenarios)...\n")
sv <- cells_dist[, .(buyer, seller_nace4d, omega_gap, nace4d_input_share)]
sv <- sv[!is.na(omega_gap) & !is.na(nace4d_input_share) &
           omega_gap > 0 & nace4d_input_share > 0]

summary_rows <- list()
for (sc_name in names(EUA_SCENARIOS)) {
  sc <- EUA_SCENARIOS[[sc_name]]
  eua_p <- sc$eua

  sv_panels <- rbindlist(lapply(RHO_GRID, function(rho) {
    data.table(rho     = rho,
               savings = rho * eua_p * sv$omega_gap * sv$nace4d_input_share)
  }))

  # Percentile summary
  sv_summary <- sv_panels[, .(
    eua_scenario = sc_name,
    eua_price    = eua_p,
    median = quantile(savings, 0.50, na.rm = TRUE),
    p75    = quantile(savings, 0.75, na.rm = TRUE),
    p90    = quantile(savings, 0.90, na.rm = TRUE),
    p99    = quantile(savings, 0.99, na.rm = TRUE),
    n      = .N
  ), by = rho]
  summary_rows[[sc_name]] <- sv_summary

  p_sv <- ggplot(sv_panels[savings > 0],
                 aes(x = savings, fill = factor(rho), color = factor(rho))) +
    stat_ecdf(geom = "step", linewidth = 0.9, alpha = 0.9) +
    scale_x_log10(labels = scales::percent_format(accuracy = 0.0001),
                  breaks = c(1e-8, 1e-7, 1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1)) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    scale_color_brewer(palette = "Set1", name = expression("Pass-through " * rho)) +
    scale_fill_brewer(palette = "Set1", name = expression("Pass-through " * rho)) +
    labs(
      title = sprintf("Potential euro savings from substituting away from the top-omega supplier (EUA %s)",
                      sc_name),
      subtitle = sprintf(
        "Savings = rho x EUA x (omega_top - omega_bot) x (cell spend / buyer total cost).\n%s. ECDF across (buyer, NACE4d) cells, version = %s.",
        sc$label, DIST_VERSION),
      x = "Savings as % of buyer total input cost (log scale)",
      y = "Cumulative share of cells"
    ) +
    base_theme +
    theme(legend.position = "bottom")

  fig_base <- sprintf("phase4_within_nace4d_intensive_savings_by_passthrough_eua%s",
                      sc_name)
  ggsave(file.path(OUTPUT_FIG, paste0(fig_base, ".png")), p_sv,
         width = 8, height = 5.5, dpi = 200)
  ggsave(file.path(OUTPUT_FIG, paste0(fig_base, ".pdf")), p_sv,
         width = 8, height = 5.5)
}

sv_summary_all <- rbindlist(summary_rows, use.names = TRUE)
fwrite(sv_summary_all, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_intensive_savings_summary.csv"))
cat("Counterfactual savings figures written (2 EUA scenarios).\n")

cat("\nAll outputs:\n")
cat("  Figures:", OUTPUT_FIG, "\n")
cat("  Tables :", OUTPUT_TAB, "\n")
cat("Done.\n")
