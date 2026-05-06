# =============================================================================
# R7 Phase II — Test H heterogeneity-robust intertemporal estimator (dCdH 2022)
# with time-varying intensity. Plan ref: §R7 Phase II.
#
# Same structure as phase6_a10_dcdh_timevarying_test_h.R but:
#   - cutoff at 2008 (Phase II) instead of 2015 (Phase IV)
#   - sample window 2003–2019
#   - intensity built from `intensity_phase2` (cost_share_regressor_phase2
#     denominator, 2003–05 baseline)
#   - cost_share_regressor_phase2 used to define j*'s firm cost share
#
# Outputs:
#   ${OUT_TAB}/phase6_a10c_dcdh_timevarying_phase2_test_h.csv
#   ${OUT_TAB}/phase6_a10c_dcdh_timevarying_phase2_test_h_summary.csv
#   ${OUT_FIG}/phase6_a10c_dcdh_timevarying_phase2_test_h.pdf
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2)
  if (requireNamespace("polars", quietly = TRUE)) suppressWarnings(library(polars))
  library(DIDmultiplegtDYN)
})

YEAR_LO <- 2003L; YEAR_HI <- 2019L
EFFECTS <- 7
PLACEBO <- 3
N_CELLS_MIN <- 500L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Replicate the Phase II Test H panel from phase6_a3_a4_phase2_eventstudy.R
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

load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_more_selected_sample)[
  , .(vat = vat_ano, year, nace5d)]
rm(df_annual_accounts_more_selected_sample)
aa[, year := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa <- unique(aa[, .(vat, year, nace4d)])
seller_nace <- copy(aa); setnames(seller_nace, c("vat", "nace4d"),
                                  c("seller", "seller_nace4d"))
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]

load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
if (!exists("cost_share_regressor_phase2")) {
  stop("cost_share_regressor_phase2 not found. Run phase6_attach_firm_cost_share_phase2.R first.")
}
b2b <- merge(b2b,
             cost_share_regressor_phase2[, .(seller = vat,
                                              fcs_p2 = firm_cost_share_regressor_phase2)],
             by = "seller", all.x = TRUE)
b2b[is.na(fcs_p2), fcs_p2 := 0]

# Cell-year aggregation
cell_yr <- b2b[, .(n_active_sellers = .N,
                   total_sales_cell = sum(corr_sales)),
               by = .(buyer, seller_nace4d, year)]
ets_in_cell <- unique(b2b[seller_is_ets == 1L,
                          .(buyer, seller_nace4d, seller, fcs_p2)])
setorder(ets_in_cell, buyer, seller_nace4d, -fcs_p2, seller)
j_star <- ets_in_cell[, .SD[1L], by = .(buyer, seller_nace4d)]
setnames(j_star, c("seller", "fcs_p2"), c("j_star", "fcs_j_star"))

j_star_b2b <- merge(b2b[, .(buyer, seller_nace4d, year, seller, corr_sales)],
                    j_star, by = c("buyer", "seller_nace4d"))
j_star_b2b <- j_star_b2b[seller == j_star]
j_window <- j_star_b2b[, .(t_first_j_star = min(year),
                            t_last_j_star  = max(year),
                            n_years_j_star_active = uniqueN(year)),
                       by = .(buyer, seller_nace4d, j_star, fcs_j_star)]
j_window[, is_type_a := as.integer(
  t_first_j_star == YEAR_LO &
  t_last_j_star  == YEAR_HI &
  n_years_j_star_active == (YEAR_HI - YEAR_LO + 1L))]

j_star_sales <- j_star_b2b[, .(buyer, seller_nace4d, year,
                                corr_sales_j_star = corr_sales)]
panel <- cell_yr[n_active_sellers >= 2L]
panel <- merge(panel, j_window, by = c("buyer", "seller_nace4d"))
panel <- merge(panel, j_star_sales,
               by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
panel[is.na(corr_sales_j_star), corr_sales_j_star := 0]
panel[, share_top := corr_sales_j_star / total_sales_cell]

samp_a <- panel[is_type_a == 1L]
cat(sprintf("Phase II Test H sample (a, balanced): %d cell-years across %d cells\n",
            nrow(samp_a), uniqueN(samp_a[, .(buyer, seller_nace4d)])))

# ---------------------------------------------------------------------------
# 2. Merge Phase II time-varying intensity for j*
# ---------------------------------------------------------------------------
load(file.path(REPO_DIR, "data/processed/firm_year_timevarying_intensity.RData"))
fyti <- as.data.table(firm_year_timevarying_intensity)[
  , .(j_star = vat, year, pair_intensity = intensity_phase2)]
samp_a <- merge(samp_a, fyti, by = c("j_star", "year"), all.x = TRUE)
samp_a[is.na(pair_intensity), pair_intensity := 0]

# ---------------------------------------------------------------------------
# 3. Encode group/cluster, balance panel
# ---------------------------------------------------------------------------
samp_a[, cell_str := paste(buyer, seller_nace4d, sep = "_")]
samp_a[, cell_id  := .GRP, by = cell_str]
samp_a[, year_int := as.integer(year)]
samp_a[, buyer_id := .GRP, by = buyer]

df_dcdh <- samp_a[, .(cell_id    = as.integer(cell_id),
                       year_int   = as.integer(year_int),
                       share_top  = as.numeric(share_top),
                       pair_intensity = as.numeric(pair_intensity),
                       buyer_id   = as.integer(buyer_id))]

all_years <- seq(min(df_dcdh$year_int), max(df_dcdh$year_int))
all_cells <- unique(df_dcdh[, .(cell_id, buyer_id)])
balanced  <- CJ(cell_id = all_cells$cell_id, year_int = all_years)
balanced  <- merge(balanced, all_cells, by = "cell_id")
df_dcdh   <- merge(balanced, df_dcdh,
                   by = c("cell_id", "year_int", "buyer_id"), all.x = TRUE)
df_dcdh[is.na(pair_intensity), pair_intensity := 0]

cat(sprintf("Balanced dCdH panel (Phase II): %d rows (%d cells × %d years)\n",
            nrow(df_dcdh), uniqueN(df_dcdh$cell_id), length(all_years)))

# ---------------------------------------------------------------------------
# 4. dCdH estimator (graceful fallback on small local-1 sample)
# ---------------------------------------------------------------------------
n_cells <- uniqueN(df_dcdh$cell_id)
if (n_cells < N_CELLS_MIN) {
  cat(sprintf(
    "\n[WARNING] only %d type-a cells available (Phase II); dCdH-2022 needs RMD.\n",
    n_cells))
  res <- NULL
} else {
  cat("\nRunning did_multiplegt_dyn on Phase II panel...\n")
  t0 <- Sys.time()
  res <- tryCatch(
    did_multiplegt_dyn(
      df         = as.data.frame(df_dcdh),
      outcome    = "share_top",
      group      = "cell_id",
      time       = "year_int",
      treatment  = "pair_intensity",
      effects    = EFFECTS,
      placebo    = PLACEBO,
      continuous = 1,
      cluster    = "buyer_id",
      graph_off  = TRUE,
      ci_level   = 95,
      bootstrap  = 100,
      drop_if_d_miss_before_first_switch = TRUE
    ),
    error = function(e) {cat("dCdH error:", conditionMessage(e), "\n"); NULL})
  cat(sprintf("Elapsed: %s\n", format(Sys.time() - t0)))
}

# ---------------------------------------------------------------------------
# 5. OLS comparator (Phase II Test H static)
# ---------------------------------------------------------------------------
samp_a[, post := as.integer(year >= 2008L)]
samp_a[, sn4d_year := paste(seller_nace4d, year, sep = "_")]
m_ols <- feols(share_top ~ fcs_j_star:post | cell_str + sn4d_year,
               data = samp_a, cluster = ~ buyer, notes = FALSE)
ols_b  <- coef(m_ols)["fcs_j_star:post"]
ols_se <- sqrt(diag(vcov(m_ols)))["fcs_j_star:post"]

# ---------------------------------------------------------------------------
# 6. Output
# ---------------------------------------------------------------------------
parse_dcdh <- function(res) {
  out <- list()
  if (!is.null(res$results$Effects)) {
    eff <- as.data.frame(res$results$Effects)
    eff$h <- seq_len(nrow(eff)) - 1L; eff$kind <- "effect"
    out[[length(out) + 1L]] <- eff
  }
  if (!is.null(res$results$Placebos)) {
    pl <- as.data.frame(res$results$Placebos)
    pl$h <- -seq_len(nrow(pl)); pl$kind <- "placebo"
    out[[length(out) + 1L]] <- pl
  }
  if (length(out) == 0L) return(data.table())
  rbindlist(out, use.names = TRUE, fill = TRUE)
}

es_table <- if (!is.null(res)) parse_dcdh(res) else data.table()
if (nrow(es_table) > 0L) {
  fwrite(es_table,
         file.path(OUT_TAB,
                   "phase6_a10c_dcdh_timevarying_phase2_test_h.csv"))
  print(es_table)
} else {
  fwrite(data.table(note = "Phase II dCdH skipped — too few cells / RMD required"),
         file.path(OUT_TAB,
                   "phase6_a10c_dcdh_timevarying_phase2_test_h.csv"))
}

cum_h_max <- if (nrow(es_table) > 0L)
  sum(es_table[kind == "effect" & h <= (EFFECTS - 1L)]$Estimate) else NA_real_

summary_tbl <- data.table(
  spec     = c("OLS static (β·fcs_j_star × post, Phase II)",
               sprintf("dCdH cumulative h=0..%d (Phase II, time-varying)",
                       EFFECTS - 1L)),
  estimate = c(ols_b, cum_h_max),
  se       = c(ols_se, NA_real_),
  units    = c("share-pp / unit fcs_p2", "share-pp")
)
fwrite(summary_tbl,
       file.path(OUT_TAB,
                 "phase6_a10c_dcdh_timevarying_phase2_test_h_summary.csv"))
cat("\nSummary OLS vs dCdH (Phase II):\n"); print(summary_tbl)

if (nrow(es_table) > 0L) {
  es_table[, ci_lo := Estimate - 1.96 * SE]
  es_table[, ci_hi := Estimate + 1.96 * SE]
  g <- ggplot(es_table, aes(x = h, y = Estimate, ymin = ci_lo, ymax = ci_hi,
                            colour = kind)) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_vline(xintercept = -0.5, linetype = "dotted") +
    geom_pointrange() +
    labs(title = "Test H Phase II — dCdH (2022) intertemporal estimator",
         subtitle = "Phase II; time-varying intensity. 95% CIs.",
         x = "Horizon h relative to first treatment change",
         y = "Effect on share_top") +
    theme_bw()
  ggsave(file.path(OUT_FIG, "phase6_a10c_dcdh_timevarying_phase2_test_h.pdf"),
         g, width = 9, height = 5)
}
