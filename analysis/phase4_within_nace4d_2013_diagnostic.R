###############################################################################
# phase4_within_nace4d_2013_diagnostic.R
#
# PURPOSE
#   Diagnose why phase4_within_nace4d_reallocation_did at tau = 2013 finds
#   only 813 treated cells, far fewer than tau = 2008 (4,515) or tau = 2017
#   (8,275). Suspected driver: the 2008-09 crisis left widespread allowance
#   surpluses through Phase II, so very few EUTL firms had positive shortage
#   in the 2011-12 pre-interval -- and the headline DiD requires >=1 such
#   supplier per cell.
#
#   Three diagnostics, one script:
#
#     (A) Firm-level interval-averaged omega1 (shortage/total_cost)
#         distributions for each of the three pre-intervals
#         (2006-07, 2011-12, 2015-16). Histogram + ECDF.
#
#     (B) Counts of EUTL firms passing each filter step at each interval:
#         - in firm_exposure with non-NA shortage in BOTH years
#         - omega1 > 0 on the interval average
#         - omega1 > 0 in either single year
#
#     (C) Relaxed-filter DiD: same identification as the headline, but drop
#         the "top-omega supplier must have omega > 0" requirement. Top-omega
#         is then just the highest-omega supplier in the cell (may be <= 0).
#         If 2013's treated-cell count jumps to a comparable order of
#         magnitude under the relaxed filter, the omega > 0 filter is the
#         binding driver of the small sample.
#
# OUTPUTS
#   - phase4_within_nace4d_2013_diagnostic_firm_omega_hist.{png,pdf}
#   - phase4_within_nace4d_2013_diagnostic_filter_counts.{csv,tex}
#   - phase4_within_nace4d_2013_diagnostic_relaxed_did_coefs.{csv,tex}
#   - phase4_within_nace4d_2013_diagnostic_cell_counts.csv
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

write_tex_table <- function(dt, file, digits = 4, caption = NULL) {
  x <- xtable(as.data.frame(dt), digits = digits, caption = caption)
  print(x, file = file, include.rownames = FALSE, booktabs = TRUE,
        caption.placement = "top",
        sanitize.colnames.function = function(s) gsub("_", "\\\\_", s, fixed = TRUE),
        sanitize.text.function    = function(s) gsub("_", "\\\\_", s, fixed = TRUE))
  invisible(NULL)
}

YEAR_LO <- 2005L
YEAR_HI <- 2022L

INTERVALS <- list(
  "treat_2008" = list(years = c(2006L, 2007L), treat_year = 2008L),
  "treat_2013" = list(years = c(2011L, 2012L), treat_year = 2013L),
  "treat_2017" = list(years = c(2015L, 2016L), treat_year = 2017L)
)

# ---------------------------------------------------------------------------
# 1. Load data (same as the headline DiD)
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

seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d %in% ets_treated_nace4d]

b2b[, total_buyer_nace4d_spend := sum(sales),
    by = .(buyer, seller_nace4d, year)]

# ---------------------------------------------------------------------------
# 2. (A) Firm-omega histograms per interval
#    For each interval, compute firm-level omega1 = sum(shortage) / sum(total_cost)
#    requiring presence in BOTH years (n_yrs == 2). Pool into a long
#    data.table for plotting.
# ---------------------------------------------------------------------------
cat("\nDiagnostic (A): firm-level omega1 distributions per interval...\n")

build_firm_omega <- function(yrs) {
  d <- fe[year %in% yrs & !is.na(shortage) & !is.na(total_cost) & total_cost > 0,
          .(vat, year, shortage, total_cost)]
  o <- d[, .(n_yrs = .N,
             sum_short = sum(shortage),
             sum_cost  = sum(total_cost)),
         by = vat]
  o <- o[n_yrs == 2L & sum_cost > 0]
  o[, omega := sum_short / sum_cost]
  o
}

firm_omega <- lapply(INTERVALS, function(s) build_firm_omega(s$years))
for (label in names(firm_omega)) {
  firm_omega[[label]][, version := label]
}
firm_omega_long <- rbindlist(firm_omega, use.names = TRUE)
firm_omega_long[, label := factor(version,
                                  levels = names(INTERVALS),
                                  labels = c("Phase I (2006-07)",
                                             "Phase II (2011-12)",
                                             "Phase III pre-MSR (2015-16)"))]

cat("\nOmega1 quantiles per interval (sum_shortage / sum_total_cost over both years):\n")
print(firm_omega_long[, as.list(round(quantile(omega,
                                               probs = c(0, .1, .25, .5, .75, .9, 1)),
                                      6)),
                     by = label])

# Histogram + ECDF
base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom")

# Plot 1: density of omega across firms, by interval. Trim x-axis to a
# sensible window around zero so the tail doesn't squash the visible body.
omg_for_plot <- firm_omega_long[omega %between% c(-0.01, 0.01)]
p_hist <- ggplot(omg_for_plot, aes(x = omega, fill = label)) +
  geom_histogram(position = "identity", alpha = 0.55, bins = 60) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "firebrick") +
  facet_wrap(~ label, ncol = 1, scales = "free_y") +
  scale_x_continuous(labels = scales::number_format(accuracy = 0.001)) +
  scale_fill_manual(values = c("Phase I (2006-07)" = "#1f78b4",
                               "Phase II (2011-12)" = "#b30000",
                               "Phase III pre-MSR (2015-16)" = "#33a02c"),
                    guide = "none") +
  labs(title    = "Firm-level interval-averaged omega1 distribution, by pre-interval",
       subtitle = sprintf("Omega1 = sum(shortage) / sum(total_cost) over the 2-year interval. n firms per interval: %s",
                          paste(sprintf("%s = %d",
                                        levels(omg_for_plot$label),
                                        sapply(levels(omg_for_plot$label),
                                               function(l) nrow(firm_omega_long[label == l]))),
                                collapse = "; ")),
       x = "omega1 (truncated to [-0.01, 0.01])",
       y = "Count of EUTL firms") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_2013_diagnostic_firm_omega_hist.png"),
       p_hist, width = 9, height = 7, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_2013_diagnostic_firm_omega_hist.pdf"),
       p_hist, width = 9, height = 7)

# ---------------------------------------------------------------------------
# 3. (B) Filter-pass-rate counts per interval
# ---------------------------------------------------------------------------
cat("\nDiagnostic (B): firm counts at each filter step, per interval...\n")

count_filters <- function(label) {
  yrs <- INTERVALS[[label]]$years
  fe_int <- fe[year %in% yrs]

  n_rows_in_fe        <- nrow(fe_int)
  n_firms_in_fe       <- uniqueN(fe_int$vat)
  n_firms_with_data   <- fe_int[!is.na(shortage) & !is.na(total_cost) & total_cost > 0,
                                uniqueN(vat)]

  d <- fe_int[!is.na(shortage) & !is.na(total_cost) & total_cost > 0]
  o <- d[, .(n_yrs = .N,
             sum_short = sum(shortage),
             sum_cost  = sum(total_cost),
             max_short = max(shortage),
             min_short = min(shortage)),
         by = vat]
  n_firms_with_2yrs   <- nrow(o[n_yrs == 2L & sum_cost > 0])

  o2 <- o[n_yrs == 2L & sum_cost > 0]
  n_firms_omega_pos_avg <- nrow(o2[sum_short > 0])
  n_firms_omega_pos_any <- nrow(o2[max_short > 0])
  n_firms_omega_neg_avg <- nrow(o2[sum_short < 0])
  n_firms_omega_zero    <- nrow(o2[sum_short == 0])

  data.table(
    version            = label,
    interval           = paste(yrs, collapse = "-"),
    n_rows_in_fe       = n_rows_in_fe,
    n_firms_in_fe      = n_firms_in_fe,
    n_firms_with_data  = n_firms_with_data,
    n_firms_2yrs       = n_firms_with_2yrs,
    n_firms_omega_pos_avg = n_firms_omega_pos_avg,
    n_firms_omega_pos_any = n_firms_omega_pos_any,
    n_firms_omega_neg_avg = n_firms_omega_neg_avg,
    n_firms_omega_zero    = n_firms_omega_zero,
    pct_pos_of_2yr     = round(100 * n_firms_omega_pos_avg / n_firms_with_2yrs, 1)
  )
}

filter_counts <- rbindlist(lapply(names(INTERVALS), count_filters))
print(filter_counts)

fwrite(filter_counts,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_2013_diagnostic_filter_counts.csv"))
write_tex_table(filter_counts,
                file.path(OUTPUT_TAB,
                          "phase4_within_nace4d_2013_diagnostic_filter_counts.tex"),
                caption = "Firm-level filter pass counts per pre-interval.")

# ---------------------------------------------------------------------------
# 4. (C) Relaxed-filter DiD: same DiD as headline, but drop the
#    omega > 0 requirement on the top-omega supplier. Just take the
#    cell's highest-omega supplier vs lowest-omega supplier.
# ---------------------------------------------------------------------------
cat("\nDiagnostic (C): relaxed-filter DiD (omega > 0 requirement removed)...\n")

build_relaxed_cells <- function(label) {
  spec <- INTERVALS[[label]]
  yrs  <- spec$years

  pre <- b2b[year %in% yrs,
             .(int_sales = sum(sales)),
             by = .(buyer, seller_nace4d, seller)]
  pre <- pre[int_sales > 0]

  cn <- pre[, .(n_supp = uniqueN(seller)), by = .(buyer, seller_nace4d)]
  multi <- cn[n_supp >= 2L, .(buyer, seller_nace4d)]
  pre <- merge(pre, multi, by = c("buyer", "seller_nace4d"))

  # Same omega merge, but DO NOT require omega > 0
  pre <- merge(pre, firm_omega[[label]][, .(vat, omega)],
               by.x = "seller", by.y = "vat", all.x = TRUE)
  pre[is.na(omega), omega := 0]

  setorder(pre, buyer, seller_nace4d, -omega, -int_sales, seller)
  top <- pre[, .SD[1L], by = .(buyer, seller_nace4d)]
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

cell_long_relaxed <- rbindlist(lapply(names(INTERVALS), build_relaxed_cells),
                               use.names = TRUE)

cell_counts <- cell_long_relaxed[, .(
  n_rows_relaxed   = .N,
  n_cells_relaxed  = uniqueN(paste(buyer, seller_nace4d)),
  n_cells_omega_pos_top = uniqueN(paste(buyer, seller_nace4d)[
                                          supplier_role == "top" & omega > 0])
), by = version]
fwrite(cell_counts,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_2013_diagnostic_cell_counts.csv"))

cat("\nCell counts under relaxed filter (with comparison to headline):\n")
print(cell_counts)

# Long panel for the regression
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])

panel <- cell_long_relaxed[, .(year = YEAR_LO:YEAR_HI),
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

results <- list()
for (label in names(INTERVALS)) {
  cat(sprintf("\n--- relaxed DiD %s ---\n", label))

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

coefs_relaxed <- rbindlist(results, use.names = TRUE, fill = TRUE)
fwrite(coefs_relaxed,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_2013_diagnostic_relaxed_did_coefs.csv"))

setnames(coefs_relaxed,
         c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
         c("estimate", "std_error", "t_stat", "p_value"),
         skip_absent = TRUE)
write_tex_table(coefs_relaxed,
                file.path(OUTPUT_TAB,
                          "phase4_within_nace4d_2013_diagnostic_relaxed_did_coefs.tex"),
                caption = "Relaxed-filter DiD (no omega > 0 requirement) on top-omega vs bottom-omega supplier.")

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
