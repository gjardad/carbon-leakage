###############################################################################
# phase4_within_nace4d_reallocation_topQ_heterogeneity.R
#
# PURPOSE
#   Two additional heterogeneity cuts on the within-NACE4d top-omega vs
#   bottom-omega comparison. For each ETS event year (2008, 2013, 2017),
#   restrict the sample of treated cells to the top quartile under one of:
#
#   Cut A: NACE4d input share within the buyer's total cost
#       nace4d_input_share_j,N = sum_t in interval [spend(j, N, t)]
#                              / sum_t in interval [buyer_total_cost(j, t)]
#       Asks: do buyers who spend a LOT in this NACE4d switch away from the
#       most carbon-cost-exposed supplier more aggressively?
#
#   Cut B: gap in omega between the two within-cell suppliers
#       omega_gap_j,N = omega_{top, interval} - omega_{bot, interval}
#       Asks: do buyers respond more when their two within-cell suppliers
#       are very differently exposed (and thus presumably face very
#       different cost shocks)?
#
#   For each cut: produce a 3-facet PDF with mean top-omega and bottom-omega
#   share trajectories (95% bootstrap CIs), and run the within-cell DiD
#         share_ijt = alpha_ij + delta_t + beta * top_i * post_t + eps
#   on the top-quartile subsample (per version).
#
# DEPENDENCIES
#   - b2b_selected_sample.RData
#   - annual_accounts_selected_sample.RData                  (seller NACE4d)
#   - annual_accounts_selected_sample_key_variables.RData    (buyer total_cost)
#   - phase3_firm_exposure.RData                             (firm-year omega)
#
# OUTPUTS (output_<machine>/figures/, output_<machine>/tables/)
#   - phase4_within_nace4d_reallocation_topQ_nace4dshare.{png,pdf}
#   - phase4_within_nace4d_reallocation_topQ_omegagap.{png,pdf}
#   - phase4_within_nace4d_reallocation_topQ_heterogeneity_pooled.csv
#   - phase4_within_nace4d_reallocation_topQ_heterogeneity_cells.csv
#   - phase4_within_nace4d_reallocation_topQ_heterogeneity_did_coefs.csv
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
})

set.seed(20260508)

YEAR_LO <- 2005L
YEAR_HI <- 2022L
N_BOOT  <- 1000L

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
# 2. Per-interval firm-omega
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
# 3. Treated cells: pick top-omega and bottom-omega per cell + heterogeneity
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
  top <- top[omega > 0]
  keys <- top[, .(buyer, seller_nace4d)]

  setorder(pre, buyer, seller_nace4d, omega, -int_sales, seller)
  bot <- pre[, .SD[1L], by = .(buyer, seller_nace4d)]
  bot <- bot[keys, on = c("buyer", "seller_nace4d"), nomatch = 0L]

  # Cell-level: omega gap and NACE4d input share
  cells <- merge(
    top[, .(buyer, seller_nace4d, top_supplier = seller, omega_top = omega)],
    bot[, .(buyer, seller_nace4d, bot_supplier = seller, omega_bot = omega)],
    by = c("buyer", "seller_nace4d")
  )
  cells[, omega_gap := omega_top - omega_bot]

  # NACE4d input share: sum_t in interval [spend(j, N, t)] / sum_t [total_cost(j, t)]
  nace_spend <- b2b[year %in% yrs,
                    .(int_nace4d_spend = sum(sales)),
                    by = .(buyer, seller_nace4d)]
  buyer_tc_int <- buyer_tc[year %in% yrs,
                           .(sum_buyer_tc = sum(buyer_total_cost),
                             n_yr = .N),
                           by = buyer]
  cells <- merge(cells, nace_spend, by = c("buyer", "seller_nace4d"),
                 all.x = TRUE)
  cells <- merge(cells, buyer_tc_int, by = "buyer", all.x = TRUE)
  cells[, nace4d_input_share := ifelse(
    !is.na(sum_buyer_tc) & sum_buyer_tc > 0,
    int_nace4d_spend / sum_buyer_tc, NA_real_
  )]

  cells[, version    := label]
  cells[, treat_year := spec$treat_year]
  cells
}

cells <- rbindlist(lapply(names(INTERVALS), build_cells_for_interval),
                   use.names = TRUE)

# Top-quartile flags per version per cut
flag_topQ <- function(dt, score_col, flag_col) {
  dt[, (flag_col) := NA]
  for (v in unique(dt$version)) {
    idx <- which(dt$version == v & !is.na(dt[[score_col]]))
    if (length(idx) == 0L) next
    cutoff <- quantile(dt[[score_col]][idx], 0.75, names = FALSE)
    dt[idx, (flag_col) := dt[[score_col]][idx] >= cutoff]
  }
  invisible(dt)
}
flag_topQ(cells, "nace4d_input_share", "topQ_nace4dshare")
flag_topQ(cells, "omega_gap",          "topQ_omegagap")

cat("\nCells per version with valid scores and top-Q counts:\n")
print(cells[, .(
  n_total           = .N,
  n_with_nace_share = sum(!is.na(nace4d_input_share)),
  n_topQ_nace_share = sum(topQ_nace4dshare,  na.rm = TRUE),
  n_with_omega_gap  = sum(!is.na(omega_gap)),
  n_topQ_omega_gap  = sum(topQ_omegagap,     na.rm = TRUE)
), by = version])

cat("\nCutoffs (75th percentile) per version:\n")
print(cells[, .(
  cutoff_nace_share = round(quantile(nace4d_input_share, 0.75, na.rm = TRUE), 4),
  cutoff_omega_gap  = round(quantile(omega_gap,          0.75, na.rm = TRUE), 6)
), by = version])

fwrite(cells,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_reallocation_topQ_heterogeneity_cells.csv"))

# ---------------------------------------------------------------------------
# 4. Long panel: per (cell, role, year) share for top-Q cells under each cut
# ---------------------------------------------------------------------------
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])

build_long_for_topQ <- function(topQ_flag_col, cut_label) {
  cells_sub <- cells[version != "" & get(topQ_flag_col) == TRUE,
                     .(buyer, seller_nace4d, version, treat_year,
                       top_supplier, bot_supplier)]
  if (nrow(cells_sub) == 0L) return(data.table())

  long_top <- cells_sub[, .(buyer, seller_nace4d, version, treat_year,
                            seller = top_supplier,
                            supplier_role = "top")]
  long_bot <- cells_sub[, .(buyer, seller_nace4d, version, treat_year,
                            seller = bot_supplier,
                            supplier_role = "bot")]
  long <- rbind(long_top, long_bot)

  panel <- long[, .(year = YEAR_LO:YEAR_HI),
                by = .(buyer, seller_nace4d, version, treat_year,
                       seller, supplier_role)]
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
  panel[, cut := cut_label]
  panel
}

panel_a <- build_long_for_topQ("topQ_nace4dshare", "Top quartile by NACE4d input share")
panel_b <- build_long_for_topQ("topQ_omegagap",    "Top quartile by omega gap")

# ---------------------------------------------------------------------------
# 5. Aggregate (mean across cells with bootstrap CI), per cut
# ---------------------------------------------------------------------------
boot_ci <- function(x, stat = mean, n_boot = N_BOOT, alpha = 0.05) {
  x <- x[!is.na(x)]
  if (length(x) < 5L) return(list(lo = NA_real_, hi = NA_real_))
  m <- length(x)
  draws <- replicate(n_boot, stat(x[sample.int(m, m, replace = TRUE)]))
  q <- quantile(draws, c(alpha / 2, 1 - alpha / 2), names = FALSE)
  list(lo = q[1], hi = q[2])
}

agg_one <- function(p) {
  p[!is.na(share),
    {
      ci <- boot_ci(share, stat = mean)
      .(mean_share = mean(share),
        n_cells   = .N,
        ci_lo     = ci$lo,
        ci_hi     = ci$hi)
    },
    by = .(cut, version, treat_year, year, supplier_role)]
}

pooled <- rbind(agg_one(panel_a), agg_one(panel_b))
setorder(pooled, cut, version, supplier_role, year)
fwrite(pooled,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_reallocation_topQ_heterogeneity_pooled.csv"))

# ---------------------------------------------------------------------------
# 6. Plots
# ---------------------------------------------------------------------------
version_labels <- c(
  "treat_2008" = "Treatment 2008 (omega from 2006-07)",
  "treat_2013" = "Treatment 2013 (omega from 2011-12)",
  "treat_2017" = "Treatment 2017 (omega from 2015-16)"
)

base_theme <- theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"),
        panel.grid.minor = element_blank(),
        legend.position = "bottom")

treat_lines <- data.table(
  version_lab = factor(version_labels, levels = version_labels),
  treat_year  = sapply(INTERVALS, `[[`, "treat_year")
)

make_plot <- function(d, title, subtitle) {
  d2 <- copy(d)
  d2[, version_lab := factor(version, levels = names(version_labels),
                             labels = version_labels)]
  d2[, supplier_role := factor(supplier_role,
                               levels = c("top", "bot"),
                               labels = c("Top-omega supplier",
                                          "Bottom-omega supplier"))]
  ggplot(d2, aes(x = year, y = mean_share,
                 color = supplier_role, fill = supplier_role)) +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.18, color = NA) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 1.1) +
    geom_vline(data = treat_lines,
               aes(xintercept = treat_year - 0.5),
               linetype = "dashed", color = "firebrick",
               inherit.aes = FALSE) +
    facet_wrap(~ version_lab, ncol = 1, scales = "free_y") +
    scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
    scale_y_continuous(limits = c(0, 1),
                       labels = scales::percent_format(accuracy = 1)) +
    scale_color_manual(values = c("Top-omega supplier"    = "firebrick",
                                  "Bottom-omega supplier" = "navy"),
                       name = NULL) +
    scale_fill_manual(values = c("Top-omega supplier"    = "firebrick",
                                 "Bottom-omega supplier" = "navy"),
                      name = NULL) +
    labs(title = title, subtitle = subtitle,
         x = NULL,
         y = "Share of buyer's NACE4d spend") +
    base_theme
}

p_a <- make_plot(
  pooled[cut == "Top quartile by NACE4d input share"],
  "Top-quartile cells by NACE4d input share (NACE4d spend / buyer total cost over interval)",
  "Asks: do buyers with high stakes in this NACE4d switch away from the top-omega supplier more?"
)
p_b <- make_plot(
  pooled[cut == "Top quartile by omega gap"],
  "Top-quartile cells by omega gap (omega_top - omega_bot in interval)",
  "Asks: do buyers respond more when their two within-cell suppliers face very different cost shocks?"
)

ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_topQ_nace4dshare.png"),
       p_a, width = 9, height = 10, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_topQ_nace4dshare.pdf"),
       p_a, width = 9, height = 10)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_topQ_omegagap.png"),
       p_b, width = 9, height = 10, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_topQ_omegagap.pdf"),
       p_b, width = 9, height = 10)

# ---------------------------------------------------------------------------
# 7. DiD on each top-Q subsample
# ---------------------------------------------------------------------------
run_did <- function(panel_dt, cut_label) {
  out <- list()
  for (label in names(INTERVALS)) {
    d <- panel_dt[version == label & !is.na(share)]
    if (nrow(d) == 0L) next
    d[, top  := as.integer(supplier_role == "top")]
    d[, post := as.integer(year >= treat_year)]
    d[, cell_role_id := paste(buyer, seller_nace4d, supplier_role,
                              sep = "::")]
    d[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]
    fit <- feols(
      share ~ i(post, top, ref = 0) | cell_role_id + year,
      data    = d,
      cluster = ~ cell_id
    )
    cat(sprintf("\n[%s | %s]\n", cut_label, label))
    print(summary(fit))
    ct <- as.data.table(coeftable(fit), keep.rownames = "term")
    out[[label]] <- cbind(
      cut             = cut_label,
      version         = label,
      n_obs           = nobs(fit),
      n_treated_cells = uniqueN(d$cell_id),
      ct
    )
  }
  rbindlist(out, use.names = TRUE, fill = TRUE)
}

did_a <- run_did(panel_a, "Top quartile by NACE4d input share")
did_b <- run_did(panel_b, "Top quartile by omega gap")
did_all <- rbind(did_a, did_b)
setnames(did_all,
         old = c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
         new = c("estimate", "std_error", "t_stat", "p_value"),
         skip_absent = TRUE)
fwrite(did_all,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_reallocation_topQ_heterogeneity_did_coefs.csv"))

cat("\n\nAll DiD coefficients (top-quartile heterogeneity):\n")
print(did_all[, .(cut, version, term,
                  est = round(estimate, 4),
                  se  = round(std_error, 4),
                  p   = round(p_value, 4),
                  n_obs, n_treated_cells)])

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
