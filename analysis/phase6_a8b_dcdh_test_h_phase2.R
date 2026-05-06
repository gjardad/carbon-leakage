# =============================================================================
# R5 Phase II — dCdH static-intensity counterpart for Test H Phase II.
# Plan ref: §R5 Phase II.
#
# Same structure as phase6_a8_dcdh_test_h.R but with the 2008 cutoff and the
# Phase II cost share (cost_share_regressor_phase2, 2003-05 baseline).
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2)
  library(polars); library(DIDmultiplegtDYN)
})

YEAR_LO <- 2003L; YEAR_HI <- 2019L
PRE_LO  <- 2003L; PRE_HI  <- 2007L
EFFECTS <- 7
PLACEBO <- 3
N_CELLS_MIN <- 500L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# Inline panel build for Phase II (Phase II uses different cost share + window).
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)[, .(seller = vat_i_ano,
                                                  buyer = vat_j_ano,
                                                  year, corr_sales = corr_sales_ij)]
rm(df_b2b_selected_sample)
b2b[, year := as.integer(year)]
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(corr_sales) & corr_sales > 0]

load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_more_selected_sample)[
  , .(vat = vat_ano, year, nace5d)]
rm(df_annual_accounts_more_selected_sample)
aa[, year := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa <- unique(aa[, .(vat, year, nace4d)])
seller_nace <- copy(aa); setnames(seller_nace, c("vat", "nace4d"), c("seller", "seller_nace4d"))
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]

load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
if (!exists("cost_share_regressor_phase2")) {
  stop("cost_share_regressor_phase2 not found")
}
b2b <- merge(b2b,
             cost_share_regressor_phase2[, .(seller = vat,
                                              fcs_p2 = firm_cost_share_regressor_phase2)],
             by = "seller", all.x = TRUE)
b2b[is.na(fcs_p2), fcs_p2 := 0]

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
  t_first_j_star == YEAR_LO & t_last_j_star  == YEAR_HI &
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

pre <- samp_a[year %between% c(PRE_LO, PRE_HI),
               .(spend_pre = sum(corr_sales_j_star),
                  total_pre = sum(total_sales_cell)),
               by = .(buyer, seller_nace4d)]
pre[, share_pre := spend_pre / total_pre]
samp_a <- merge(samp_a, pre[, .(buyer, seller_nace4d, share_pre)],
                 by = c("buyer", "seller_nace4d"), all.x = TRUE)
samp_a[is.na(share_pre), share_pre := 0]
samp_a[, pair_exposure := fcs_j_star * share_pre]
samp_a[, post := as.integer(year >= 2008L)]
samp_a[, treat_static := pair_exposure * post]
samp_a[, cell_id  := .GRP, by = .(buyer, seller_nace4d)]
samp_a[, year_int := as.integer(year)]
samp_a[, buyer_id := .GRP, by = buyer]

cat(sprintf("R5 Phase II Test H sample: %d cell-years across %d cells\n",
            nrow(samp_a), uniqueN(samp_a$cell_id)))

df_dcdh <- samp_a[, .(cell_id    = as.integer(cell_id),
                       year_int  = as.integer(year_int),
                       share_top = as.numeric(share_top),
                       treat_static = as.numeric(treat_static),
                       buyer_id  = as.integer(buyer_id))]

all_years <- seq(min(df_dcdh$year_int), max(df_dcdh$year_int))
all_cells <- unique(df_dcdh[, .(cell_id, buyer_id)])
balanced  <- CJ(cell_id = all_cells$cell_id, year_int = all_years)
balanced  <- merge(balanced, all_cells, by = "cell_id")
df_dcdh   <- merge(balanced, df_dcdh,
                   by = c("cell_id", "year_int", "buyer_id"), all.x = TRUE)
df_dcdh[is.na(treat_static), treat_static := 0]

n_cells <- uniqueN(df_dcdh$cell_id)
if (n_cells < N_CELLS_MIN) {
  cat(sprintf("\n[WARNING] only %d type-a cells (Phase II); RMD required.\n",
              n_cells))
  res <- NULL
} else {
  cat("\nRunning dCdH (Phase II static)...\n")
  t0 <- Sys.time()
  res <- tryCatch(
    did_multiplegt_dyn(
      df = as.data.frame(df_dcdh),
      outcome = "share_top", group = "cell_id", time = "year_int",
      treatment = "treat_static", effects = EFFECTS, placebo = PLACEBO,
      continuous = 1, cluster = "buyer_id", graph_off = TRUE,
      ci_level = 95, bootstrap = 100,
      drop_if_d_miss_before_first_switch = TRUE),
    error = function(e) {cat("dCdH error:", conditionMessage(e), "\n"); NULL})
  cat(sprintf("Elapsed: %s\n", format(Sys.time() - t0)))
}

samp_a[, cell_str := paste(buyer, seller_nace4d, sep = "_")]
samp_a[, sn4d_year := paste(seller_nace4d, year, sep = "_")]
m_ols <- feols(share_top ~ pair_exposure:post | cell_str + sn4d_year,
               data = samp_a, cluster = ~ buyer, notes = FALSE)
ols_b  <- coef(m_ols)["pair_exposure:post"]
ols_se <- sqrt(diag(vcov(m_ols)))["pair_exposure:post"]

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
fwrite(if (nrow(es_table) > 0L) es_table else
       data.table(note = "Phase II dCdH skipped — RMD required"),
       file.path(OUT_TAB, "phase6_a8b_dcdh_test_h_phase2.csv"))

cum_max <- if (nrow(es_table) > 0L)
  sum(es_table[kind == "effect" & h <= (EFFECTS - 1L)]$Estimate) else NA_real_

summary_tbl <- data.table(
  spec = c("OLS static (pair_exposure × post, Phase II)",
           sprintf("dCdH static cumulative h=0..%d (Phase II)", EFFECTS - 1L)),
  estimate = c(ols_b, cum_max),
  se = c(ols_se, NA_real_)
)
fwrite(summary_tbl,
       file.path(OUT_TAB, "phase6_a8b_dcdh_test_h_phase2_summary.csv"))
cat("\nR5 Phase II summary:\n"); print(summary_tbl)
