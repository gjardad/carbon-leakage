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

YEAR_LO <- 2002L  # B2B panel starts in 2002; AA in 2000. Extended below 2005 to provide a real pre-period for the EU ETS launch (2005).
YEAR_HI <- 2022L

# Two treatment periods we report on:
#   "treat_2005" = EU ETS launch. omega computed from 2005 (the year
#     the policy starts and the first year of EUTL records); post = 1
#     from 2005 onwards. Pre-period uses B2B data from 2002-2004
#     (which extends back to 2002, before the EU ETS existed).
#   "treat_2017" = MSR reform. omega computed from 2015-16. Post = 1
#     from 2017 onwards; pre-period is 2005-2016.
INTERVALS <- list(
  "treat_2005" = list(years = c(2005L),         treat_year = 2005L),
  "treat_2017" = list(years = c(2015L, 2016L),  treat_year = 2017L)
)

DIST_VERSION <- "treat_2017"  # for distribution + savings figures
RHO_GRID     <- c(0.25, 0.5, 0.75, 1.0)

# Eurostat HICP (prc_hicp_aind), EA changing composition, all items
# (CP00), base 2015 = 100. Used to deflate end-of-year EUA prices into
# 2016 base euros so the cost-shock distribution and savings figures
# are on a real-euro scale that matches the buyer-total-cost
# denominator (built from 2015-16 accounts).
HICP_BASE <- list("2016" = 100.23,
                  "2017" = 101.78,
                  "2022" = 117.04)
HICP_BASE_YEAR <- 2016L

# End-of-year EUA prices come from the daily settlement CSV; they are
# deflated to 2016 euros using HICP and used to scale the cost shock
# and savings distributions.
EUA_EOY_YEARS <- c(2017L, 2022L)

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
  # `years` is the vector of pre-event years used to compute omega.
  yrs <- years

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

  # Top-quartile flags (>= 75th percentile) per cut (within version)
  qtl_share <- quantile(cells_top_bot$nace4d_input_share, 0.75, na.rm = TRUE)
  qtl_gap   <- quantile(cells_top_bot$omega_gap,           0.75, na.rm = TRUE)
  qtl_buy   <- quantile(cells_top_bot$shock_buyertotal,    0.75, na.rm = TRUE)
  cells_top_bot[, topQ_nace4dshare := nace4d_input_share >= qtl_share &
                                       !is.na(nace4d_input_share)]
  cells_top_bot[, topQ_omegagap    := omega_gap           >= qtl_gap   &
                                       !is.na(omega_gap)]
  cells_top_bot[, topQ_buyertotal  := shock_buyertotal    >= qtl_buy   &
                                       !is.na(shock_buyertotal)]
  # Top-decile flags (>= 90th percentile) per cut (within version)
  dec_share <- quantile(cells_top_bot$nace4d_input_share, 0.90, na.rm = TRUE)
  dec_gap   <- quantile(cells_top_bot$omega_gap,           0.90, na.rm = TRUE)
  dec_buy   <- quantile(cells_top_bot$shock_buyertotal,    0.90, na.rm = TRUE)
  cells_top_bot[, topD_nace4dshare := nace4d_input_share >= dec_share &
                                       !is.na(nace4d_input_share)]
  cells_top_bot[, topD_omegagap    := omega_gap           >= dec_gap   &
                                       !is.na(omega_gap)]
  cells_top_bot[, topD_buyertotal  := shock_buyertotal    >= dec_buy   &
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
# 3. Build long panels (one per cut) and run DiDs internally.
#    Self-contained: does not read from any other script's CSVs.
# ---------------------------------------------------------------------------
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

build_long_for_cut <- function(cut_label) {
  base_cols <- c("buyer", "seller_nace4d", "version", "treat_year",
                 "top_supplier", "bot_supplier", "top_sales", "bot_sales")
  if (cut_label == "pooled") {
    sub <- cells_all[, ..base_cols]
  } else {
    flag_col <- switch(cut_label,
                       "cost_shock_q"   = "topQ_buyertotal",
                       "cost_shock_d"   = "topD_buyertotal",
                       "input_share_q"  = "topQ_nace4dshare",
                       "input_share_d"  = "topD_nace4dshare",
                       "exposure_gap_q" = "topQ_omegagap",
                       "exposure_gap_d" = "topD_omegagap")
    sub <- cells_all[get(flag_col) == TRUE, ..base_cols]
  }
  if (nrow(sub) == 0L) return(data.table())
  long <- rbind(
    sub[, .(buyer, seller_nace4d, version, treat_year,
            seller = top_supplier, supplier_role = "top",
            pre_sales_role = top_sales)],
    sub[, .(buyer, seller_nace4d, version, treat_year,
            seller = bot_supplier, supplier_role = "bot",
            pre_sales_role = bot_sales)]
  )
  panel <- long[, .(year = YEAR_LO:YEAR_HI),
                by = .(buyer, seller_nace4d, version, treat_year,
                       seller, supplier_role, pre_sales_role)]
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
  # Pre-period within-cell role size (log). Used as a control for the
  # size-confound robustness: top-omega and bottom-omega may differ
  # systematically in baseline size, and large vs small suppliers may
  # have different secular trends in within-cell share for reasons
  # unrelated to carbon exposure.
  panel[, log_pre_sales := log1p(pmax(pre_sales_role, 0))]
  panel[]
}

CUT_LABELS <- c("pooled",
                "cost_shock_q",   "cost_shock_d",
                "input_share_q",  "input_share_d",
                "exposure_gap_q", "exposure_gap_d")
CUT_DISPLAY <- c(
  "pooled"         = "Pooled (no heterogeneity)",
  "cost_shock_q"   = "Top quartile by buyer-total shock",
  "cost_shock_d"   = "Top decile by buyer-total shock",
  "input_share_q"  = "Top quartile by NACE4d input share",
  "input_share_d"  = "Top decile by NACE4d input share",
  "exposure_gap_q" = "Top quartile by omega gap",
  "exposure_gap_d" = "Top decile by omega gap"
)

cat("Building long panels for the 4 cuts...\n")
panels <- list()
for (cut_lab in CUT_LABELS) {
  panels[[cut_lab]] <- build_long_for_cut(cut_lab)
  cat(sprintf("  %-13s %s rows\n", cut_lab,
              format(nrow(panels[[cut_lab]]), big.mark = ",")))
}

run_did_one <- function(panel_dt, size_control = FALSE) {
  d <- panel_dt[!is.na(share)]
  if (nrow(d) == 0L || uniqueN(d$post) < 2L || uniqueN(d$top) < 2L) {
    return(list(beta = NA_real_, se = NA_real_, t = NA_real_,
                p = NA_real_, n_obs = 0L, n_cells = 0L))
  }
  d[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]
  d[, cell_role_id := paste(cell_id, supplier_role, sep = "::")]
  if (size_control && "log_pre_sales" %in% names(d) &&
      uniqueN(d$log_pre_sales) > 1L) {
    # Year x log(pre-period sales) interaction lets large vs small
    # suppliers follow different secular trends.
    fml <- share ~ i(post, top, ref = 0) + i(year, log_pre_sales) |
                  cell_role_id + year
  } else {
    fml <- share ~ i(post, top, ref = 0) | cell_role_id + year
  }
  fit <- tryCatch(
    feols(fml, data = d, cluster = ~ cell_id, notes = FALSE),
    error = function(e) NULL
  )
  if (is.null(fit)) return(list(beta = NA_real_, se = NA_real_, t = NA_real_,
                                 p = NA_real_, n_obs = 0L, n_cells = 0L))
  ct <- coeftable(fit)
  list(beta    = as.numeric(ct[1, "Estimate"]),
       se      = as.numeric(ct[1, "Std. Error"]),
       t       = as.numeric(ct[1, "t value"]),
       p       = as.numeric(ct[1, "Pr(>|t|)"]),
       n_obs   = as.integer(nobs(fit)),
       n_cells = uniqueN(d$cell_id))
}

cat("Running baseline DiDs (4 cuts x 2 treatment periods) -- unconditional + size-controlled...\n")
did_rows <- list()
for (spec_name in c("unconditional", "size_controlled")) {
  for (cut_lab in CUT_LABELS) {
    for (ver in names(INTERVALS)) {
      d <- panels[[cut_lab]][version == ver]
      est <- run_did_one(d, size_control = (spec_name == "size_controlled"))
      did_rows[[length(did_rows) + 1L]] <- data.table(
        spec            = spec_name,
        cut             = CUT_DISPLAY[[cut_lab]],
        version         = ver,
        n_obs           = est$n_obs,
        n_treated_cells = est$n_cells,
        term            = "post::1:top",
        estimate        = est$beta,
        std_error       = est$se,
        t_stat          = est$t,
        p_value         = est$p
      )
    }
  }
}
did_all <- rbindlist(did_rows, use.names = TRUE)
fwrite(did_all, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_reallocation_did_specs_comparison.csv"))

# Print a compact summary to console for quick comparison
cat("\n--- DiD comparison (unconditional vs size-controlled) ---\n")
cmp <- dcast(did_all,
             cut + version ~ spec,
             value.var = c("estimate", "std_error", "p_value"))
print(cmp)

# The headline table uses the unconditional spec (matches prior outputs).
did_all <- did_rows[sapply(did_rows, function(r) r$spec == "unconditional")] |>
  rbindlist(use.names = TRUE)

cut_order <- c("Pooled (no heterogeneity)",
               "Top quartile by buyer-total shock",
               "Top decile by buyer-total shock",
               "Top quartile by NACE4d input share",
               "Top decile by NACE4d input share",
               "Top quartile by omega gap",
               "Top decile by omega gap")
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
  versions <- c("treat_2005", "treat_2017")
  event_years <- c("EU ETS start (2005)",
                   "MSR (2017)")
  cuts <- cut_order  # 7 cuts: pooled + 3 metrics x {Q, D}

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
    "\\begin{tabular}{lccccccc}\n",
    "\\toprule\n",
    " & & \\multicolumn{2}{c}{Cost shock} & \\multicolumn{2}{c}{Input share} & \\multicolumn{2}{c}{Exposure gap} \\\\\n",
    "\\cmidrule(lr){3-4}\\cmidrule(lr){5-6}\\cmidrule(lr){7-8}\n",
    "Treatment period & Pooled & Top 25\\% & Top 10\\% & Top 25\\% & Top 10\\% & Top 25\\% & Top 10\\% \\\\\n",
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
# 5. Distribution figures (using DIST_VERSION cells)
# ---------------------------------------------------------------------------
cat(sprintf("Building distribution figures using version %s...\n",
            DIST_VERSION))
cells_dist <- cells_all[version == DIST_VERSION &
                          !is.na(shock_buyertotal) &
                          !is.na(nace4d_input_share) &
                          !is.na(omega_gap)]

# Read daily EUA settlement prices to extract end-of-year values.
cat("Reading daily EUA settlement prices for end-of-year EUA...\n")
eua_daily <- fread(file.path(RAW_DATA,
                "European Union Carbon Permits Allowance (EUA) Yearly Futures Historical Data.csv"))
eua_daily[, date := as.Date(Date, format = "%m/%d/%Y")]
eua_daily <- eua_daily[!is.na(date)]
eua_daily[, yr := as.integer(format(date, "%Y"))]
setorder(eua_daily, date)
eua_eoy <- eua_daily[, .(eua_nominal = last(Price)), by = yr]

deflate_to_base <- function(yr) {
  HICP_BASE[[as.character(yr)]] / HICP_BASE[[as.character(HICP_BASE_YEAR)]]
}

eua_real <- list()
for (yr_target in EUA_EOY_YEARS) {
  nom <- eua_eoy[yr == yr_target, eua_nominal]
  defl <- deflate_to_base(yr_target)
  eua_real[[as.character(yr_target)]] <- nom / defl
  cat(sprintf("  EUA end of %d: nominal = %.2f EUR/tCO2; real (2016 base) = %.2f\n",
              yr_target, nom, eua_real[[as.character(yr_target)]]))
}

# Shared theme for the clean histograms (cost shock, NACE4d input share).
clean_hist_theme <- theme_classic(base_size = 13) +
  theme(panel.grid       = element_blank(),
        axis.title.x     = element_text(margin = margin(t = 14), size = 15),
        axis.title.y     = element_text(margin = margin(r = 14), size = 15),
        axis.text        = element_text(size = 13),
        plot.title       = element_blank(),
        plot.subtitle    = element_blank())

# Generic clean histogram on a log-scale x-axis displayed in %, with a
# dashed line at p75. `vals` is a vector of positive fractions (e.g.
# 0.001 displays as 0.1%).
plot_dist_pct_log <- function(vals, xlab) {
  d <- data.table(val = vals)
  d <- d[is.finite(val) & val > 0]
  if (nrow(d) == 0L) return(NULL)
  qs <- quantile(d$val, c(0.50, 0.75, 0.90, 0.99), na.rm = TRUE)

  pct_breaks <- c(1e-7, 1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1)
  pct_labels <- c("0.00001%", "0.0001%", "0.001%", "0.01%",
                  "0.1%", "1%", "10%", "100%")

  ggplot(d, aes(x = val)) +
    geom_histogram(bins = 60, fill = "steelblue",
                   color = "white", alpha = 0.9) +
    geom_vline(xintercept = qs[2], linetype = "dashed", color = "firebrick") +
    annotate("text", x = qs[2], y = Inf, label = " p75",
             vjust = 1.5, hjust = 0, color = "firebrick", size = 4.5) +
    scale_x_log10(breaks = pct_breaks, labels = pct_labels) +
    labs(x = xlab, y = "Number of cells") +
    clean_hist_theme
}

# Cost shock distribution: shock_buyertotal * deflated EUA, per EUA year.
for (yr_target in EUA_EOY_YEARS) {
  p_cs <- plot_dist_pct_log(
    cells_dist$shock_buyertotal * eua_real[[as.character(yr_target)]],
    "Cost shock"
  )
  fig_base <- sprintf("phase4_within_nace4d_intensive_dist_shock_buyertotal_eua%d",
                      yr_target)
  ggsave(file.path(OUTPUT_FIG, paste0(fig_base, ".png")), p_cs,
         width = 8, height = 5, dpi = 200)
  ggsave(file.path(OUTPUT_FIG, paste0(fig_base, ".pdf")), p_cs,
         width = 8, height = 5)
  cat(sprintf("  Cost-shock distribution (EUA %d) written.\n", yr_target))
}

# NACE4d input share: same clean styling, displayed as a percent on a
# log-scale x-axis.
p_nshare <- plot_dist_pct_log(
  cells_dist$nace4d_input_share,
  "Cost share of expenditure on supplier's sector"
)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_nace4d_share.png"),
       p_nshare, width = 8, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_nace4d_share.pdf"),
       p_nshare, width = 8, height = 5)
cat("  NACE4d input share distribution written.\n")

# Omega gap distribution keeps the older title/subtitle styling for now.
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

p_gap <- plot_dist(
  cells_dist$omega_gap,
  expression(omega[top] - omega[bot]),
  expression("Distribution of " * omega[top] - omega[bot]),
  sprintf("Across (buyer, NACE4d) cells with >=2 ETS-relevant suppliers in %s pre-period.",
          DIST_VERSION),
  log_x = TRUE
)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_omega_gap.png"),
       p_gap, width = 8, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_intensive_dist_omega_gap.pdf"),
       p_gap, width = 8, height = 5)
cat("All distribution figures written.\n")

# ---------------------------------------------------------------------------
# 6. Counterfactual savings figures: TWO versions, one per EUA scenario
#    savings(b,n,rho,EUA) = rho * EUA_real * (omega_top - omega_bot)
#                                * (cell spend / buyer total cost)
#    EUA_real is the deflated end-of-year EUA price (2016 base), so the
#    numerator and denominator are in consistent units.
# ---------------------------------------------------------------------------
cat("Building counterfactual savings figures (two EUA scenarios)...\n")
sv <- cells_dist[, .(buyer, seller_nace4d, omega_gap, nace4d_input_share)]
sv <- sv[!is.na(omega_gap) & !is.na(nace4d_input_share) &
           omega_gap > 0 & nace4d_input_share > 0]

savings_x_breaks <- c(0, 0.005, 0.01, 0.05, 0.10)
savings_x_labels <- c("0%", "0.5%", "1%", "5%", "10%")
savings_x_limits <- c(0, 0.10)

summary_rows <- list()
for (yr_target in EUA_EOY_YEARS) {
  eua_p_real <- eua_real[[as.character(yr_target)]]

  sv_panels <- rbindlist(lapply(RHO_GRID, function(rho) {
    data.table(rho     = rho,
               savings = rho * eua_p_real * sv$omega_gap * sv$nace4d_input_share)
  }))

  sv_summary <- sv_panels[, .(
    eua_year   = yr_target,
    eua_price_real = eua_p_real,
    median = quantile(savings, 0.50, na.rm = TRUE),
    p75    = quantile(savings, 0.75, na.rm = TRUE),
    p90    = quantile(savings, 0.90, na.rm = TRUE),
    p99    = quantile(savings, 0.99, na.rm = TRUE),
    n      = .N
  ), by = rho]
  summary_rows[[as.character(yr_target)]] <- sv_summary

  p_sv <- ggplot(sv_panels[savings >= 0],
                 aes(x = savings, fill = factor(rho), color = factor(rho))) +
    stat_ecdf(geom = "step", linewidth = 0.9, alpha = 0.9) +
    scale_x_continuous(limits = savings_x_limits,
                       breaks = savings_x_breaks,
                       labels = savings_x_labels,
                       oob    = scales::squish) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    scale_color_brewer(palette = "Set1",
                       name = expression("Pass-through " * rho)) +
    scale_fill_brewer(palette = "Set1",
                      name = expression("Pass-through " * rho)) +
    labs(x = "Savings as % of buyer total input cost",
         y = "Cumulative share of cells") +
    theme_classic(base_size = 13) +
    theme(panel.grid       = element_blank(),
          axis.title.x     = element_text(margin = margin(t = 14), size = 15),
          axis.title.y     = element_text(margin = margin(r = 14), size = 15),
          axis.text        = element_text(size = 13),
          plot.title       = element_blank(),
          plot.subtitle    = element_blank(),
          legend.position  = "bottom",
          legend.title     = element_text(size = 13),
          legend.text      = element_text(size = 12))

  fig_base <- sprintf("phase4_within_nace4d_intensive_savings_by_passthrough_eua%d",
                      yr_target)
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
