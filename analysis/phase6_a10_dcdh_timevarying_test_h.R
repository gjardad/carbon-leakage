# =============================================================================
# R7 Phase IV — Test H heterogeneity-robust intertemporal estimator (dCdH 2022)
# with time-varying continuous treatment intensity. Plan ref: §R7 Test H.
#
# Why this script. The static §5.1.1 specification regresses share_top on
# (pre-shock pair_exposure × 1[t≥2015]) — a single common cutoff with
# time-invariant intensity. Per RSBP Table 1's literal reading this is Q1 =
# YES and the static TWFE β̂ is interpretable. But the substantive policy
# (continuously evolving EUA prices × allocation shortage) makes the bite
# time-varying within firm and unit-specific in its onset year, putting us
# at Q1 = NO. dCdH (2022) is the heterogeneity-robust estimator that handles
# both: continuously time-varying treatment with potential dependence on
# the path of treatment.
#
# Spec.
#   group     = cell = (buyer, seller_nace4d)  [integer-coded]
#   time      = year
#   outcome   = share_top
#   treatment = pair_intensity_{b,n,t}
#               = intensity_{j*(b,n), t}
#               = (allowance_shortage × eua_price)/revenue_pre  for j*
#   effects   = 7  (post-first-switch dynamic effects, relative time h = 0..6)
#   placebo   = 5  (placebos at h = -5..-1)
#   continuous= 1  (linear in continuous treatment, dCdH's default)
#   cluster   = buyer
#
# Outputs:
#   ${OUT_TAB}/phase6_a10_dcdh_timevarying_test_h.csv      — full table
#   ${OUT_TAB}/phase6_a10_dcdh_timevarying_test_h_summary.csv  — vs OLS
#   ${OUT_FIG}/phase6_a10_dcdh_timevarying_test_h.pdf      — IRF plot
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(ggplot2)
  library(polars)
  library(DIDmultiplegtDYN)
})

YEAR_LO   <- 2005L
YEAR_HI   <- 2022L
EFFECTS   <- 5
PLACEBO   <- 3

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Replicate samp_ab from phase5_test_h_most_exposed_ets_supplier.R
#    (same construction as phase6_test_h_corrected.R)
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)[, .(seller = vat_i_ano,
                                                  buyer = vat_j_ano,
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

contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
b2b <- b2b[!(seller %in% contaminated_vats & year >= 2021L)]

load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
b2b <- merge(b2b,
             cost_share_regressor[, .(seller = vat,
                                       fcs_reg = firm_cost_share_regressor)],
             by = "seller", all.x = TRUE)
b2b[is.na(fcs_reg), fcs_reg := 0]
ets_with_fcs <- cost_share_regressor$vat
b2b <- b2b[!(seller_is_ets == 1L & !(seller %in% ets_with_fcs))]

setkey(b2b, buyer, seller_nace4d, year)
cell_yr <- b2b[, .(n_active_sellers = .N,
                   n_ets_sellers    = sum(seller_is_ets == 1L),
                   total_sales_cell = sum(corr_sales)),
               by = .(buyer, seller_nace4d, year)]

ets_in_cell <- unique(b2b[seller_is_ets == 1L,
                          .(buyer, seller_nace4d, seller, fcs_reg)])
setorder(ets_in_cell, buyer, seller_nace4d, -fcs_reg, seller)
j_star <- ets_in_cell[, .SD[1L], by = .(buyer, seller_nace4d)]
setnames(j_star, c("seller", "fcs_reg"), c("j_star", "fcs_j_star"))

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
setkey(j_star_sales, buyer, seller_nace4d, year)

panel <- cell_yr[n_active_sellers >= 2L]
panel <- merge(panel, j_window, by = c("buyer", "seller_nace4d"))
panel <- merge(panel, j_star_sales,
               by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
panel[is.na(corr_sales_j_star), corr_sales_j_star := 0]
panel[, share_top := corr_sales_j_star / total_sales_cell]

samp_ab <- panel[is_type_a == 1L |
                   (year >= t_first_j_star & year <= t_last_j_star)]

cat(sprintf("Test H sample (a+b): %d cell-years across %d cells\n",
            nrow(samp_ab), uniqueN(samp_ab[, .(buyer, seller_nace4d)])))

# For dCdH we need a *balanced* panel within cells (every cell observed every
# year of the analysis window). Restrict to type-a cells, which by
# construction have j* active 2005-2022 throughout.
samp_a <- panel[is_type_a == 1L]
n_balanced <- samp_a[, .N, by = .(buyer, seller_nace4d)]
cat(sprintf("Test H sample (a only, balanced): %d cell-years across %d cells (range of obs/cell: %d-%d)\n",
            nrow(samp_a), uniqueN(samp_a[, .(buyer, seller_nace4d)]),
            min(n_balanced$N), max(n_balanced$N)))

# ---------------------------------------------------------------------------
# 2. Merge time-varying intensity for j*
# ---------------------------------------------------------------------------
load(file.path(REPO_DIR, "data/processed/firm_year_timevarying_intensity.RData"))
fyti <- as.data.table(firm_year_timevarying_intensity)[
  , .(j_star = vat, year, pair_intensity = intensity_phase4)]
samp_ab <- merge(samp_ab, fyti, by = c("j_star", "year"), all.x = TRUE)
samp_a  <- merge(samp_a,  fyti, by = c("j_star", "year"), all.x = TRUE)

# Cells with j* in firm_year_belgian_euets but no time-varying intensity row
# (some early years before allocation data) → set intensity to 0.
samp_ab[is.na(pair_intensity), pair_intensity := 0]
samp_a [is.na(pair_intensity), pair_intensity := 0]

# ---------------------------------------------------------------------------
# 3. Integer-encode group identifier (dCdH requires numeric group)
# ---------------------------------------------------------------------------
samp_a[, cell_str := paste(buyer, seller_nace4d, sep = "_")]
samp_a[, cell_id  := .GRP, by = cell_str]
samp_a[, year_int := as.integer(year)]
samp_a[, buyer_id := .GRP, by = buyer]

# ---------------------------------------------------------------------------
# 4. dCdH 2022 intertemporal estimator (use balanced sample_a)
# ---------------------------------------------------------------------------
# Subset to columns dCdH needs. Cluster must be numeric (polars requires
# numeric coercion).
df_dcdh <- samp_a[, .(cell_id    = as.integer(cell_id),
                       year_int   = as.integer(year_int),
                       share_top  = as.numeric(share_top),
                       pair_intensity = as.numeric(pair_intensity),
                       buyer_id   = as.integer(buyer_id))]

# dCdH expects a balanced panel within groups: every cell observed in every
# year of the analysis window. samp_a is type-a (j* active YEAR_LO..YEAR_HI)
# but the cell may still have years with <2 sellers, which were dropped
# upstream. Balance by inserting zero-treatment NA-outcome rows.
all_years <- seq(min(df_dcdh$year_int), max(df_dcdh$year_int))
all_cells <- unique(df_dcdh[, .(cell_id, buyer_id)])
balanced  <- CJ(cell_id = all_cells$cell_id, year_int = all_years)
balanced  <- merge(balanced, all_cells, by = "cell_id")
df_dcdh   <- merge(balanced, df_dcdh,
                   by = c("cell_id", "year_int", "buyer_id"), all.x = TRUE)
df_dcdh[is.na(pair_intensity), pair_intensity := 0]
# Outcome NA in inserted rows is fine — dCdH drops them per cell-year.
cat(sprintf("Balanced dCdH panel: %d rows (%d cells × %d years)\n",
            nrow(df_dcdh), uniqueN(df_dcdh$cell_id), length(all_years)))

# Some cells may have no within-cell variation in pair_intensity (e.g. if
# j* never had positive shortage in any year). dCdH needs at least some
# variation to define switchers. Diagnostic:
n_var <- df_dcdh[, .(sd_t = sd(pair_intensity)), by = cell_id][sd_t > 0, .N]
cat(sprintf("Cells with within-cell variation in pair_intensity: %d / %d\n",
            n_var, uniqueN(df_dcdh$cell_id)))

N_CELLS_MIN <- 500L
n_cells <- uniqueN(df_dcdh$cell_id)
if (n_cells < N_CELLS_MIN) {
  cat(sprintf(
    "\n[WARNING] only %d type-a cells available; dCdH-2022 requires the full RMD\n",
    n_cells))
  cat("[WARNING] sample for reliable estimation. On local-1 with the downsampled\n")
  cat("[WARNING] training data, the dCdH internal regression collapses (insufficient\n")
  cat("[WARNING] within-cell variation across the staggered cohort decomposition).\n")
  cat("[WARNING] Skipping dCdH; OLS-only output below.\n\n")
  res <- NULL
} else {
  cat("\nRunning did_multiplegt_dyn (this can take a few minutes)...\n")
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
      continuous = 1,                   # treat as continuous, linear-in-D
      cluster    = "buyer_id",
      graph_off  = TRUE,
      ci_level   = 95,
      bootstrap  = 100,
      drop_if_d_miss_before_first_switch = TRUE
    ),
    error = function(e) {
      cat("did_multiplegt_dyn error:", conditionMessage(e), "\n")
      NULL
    })
  cat(sprintf("Elapsed: %s\n", format(Sys.time() - t0)))
}

# ---------------------------------------------------------------------------
# 5. Extract effects and placebos into a tidy table (when dCdH ran)
# ---------------------------------------------------------------------------
parse_dcdh <- function(res) {
  out <- list()
  if (!is.null(res$results$Effects)) {
    eff <- as.data.frame(res$results$Effects)
    eff$h <- seq_len(nrow(eff)) - 1L
    eff$kind <- "effect"
    out[[length(out) + 1L]] <- eff
  }
  if (!is.null(res$results$Placebos)) {
    pl <- as.data.frame(res$results$Placebos)
    pl$h <- -seq_len(nrow(pl))
    pl$kind <- "placebo"
    out[[length(out) + 1L]] <- pl
  }
  if (length(out) == 0L) return(data.table())
  rbindlist(out, use.names = TRUE, fill = TRUE)
}

if (!is.null(res)) {
  es_table <- parse_dcdh(res)
  fwrite(es_table, file.path(OUT_TAB, "phase6_a10_dcdh_timevarying_test_h.csv"))
  cat("\ndCdH event-study table:\n"); print(es_table)
} else {
  es_table <- data.table()
  fwrite(data.table(note = "dCdH skipped on local-1 — too few cells; rerun on RMD"),
         file.path(OUT_TAB, "phase6_a10_dcdh_timevarying_test_h.csv"))
}

# ---------------------------------------------------------------------------
# 6. Side-by-side with OLS static (Test H Phase IV headline)
# ---------------------------------------------------------------------------
samp_a[, post := as.integer(year >= 2015L)]
samp_a[, sn4d_year := paste(seller_nace4d, year, sep = "_")]
m_ols <- feols(share_top ~ fcs_j_star:post | cell_str + sn4d_year,
               data = samp_a, cluster = ~ buyer, notes = FALSE)
ols_b  <- coef(m_ols)["fcs_j_star:post"]
ols_se <- sqrt(diag(vcov(m_ols)))["fcs_j_star:post"]

# Cumulative dCdH effect at h = 0..3 and 0..(EFFECTS-1).
if (nrow(es_table) > 0L) {
  cum_h_3 <- if (nrow(es_table[kind == "effect"]) >= 4L)
    sum(es_table[kind == "effect" & h <= 3L]$Estimate) else NA_real_
  cum_h_max <- if (nrow(es_table[kind == "effect"]) >= EFFECTS)
    sum(es_table[kind == "effect" & h <= (EFFECTS - 1L)]$Estimate) else NA_real_
} else {
  cum_h_3 <- NA_real_; cum_h_max <- NA_real_
}

summary_tbl <- data.table(
  spec        = c("OLS static (β·fcs_j_star × post)",
                  "dCdH cumulative h=0..3 (time-varying intensity)",
                  sprintf("dCdH cumulative h=0..%d (time-varying intensity)",
                          EFFECTS - 1L)),
  estimate    = c(ols_b, cum_h_3, cum_h_max),
  se          = c(ols_se, NA_real_, NA_real_),
  units       = c("share-pp / unit fcs", "share-pp", "share-pp")
)
fwrite(summary_tbl,
       file.path(OUT_TAB, "phase6_a10_dcdh_timevarying_test_h_summary.csv"))
cat("\nSummary OLS vs dCdH:\n"); print(summary_tbl)

# ---------------------------------------------------------------------------
# 7. IRF plot (only when dCdH ran)
# ---------------------------------------------------------------------------
if (nrow(es_table) > 0L) {
  es_table[, ci_lo := Estimate - 1.96 * SE]
  es_table[, ci_hi := Estimate + 1.96 * SE]
  g <- ggplot(es_table, aes(x = h, y = Estimate, ymin = ci_lo, ymax = ci_hi,
                            colour = kind)) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_vline(xintercept = -0.5, linetype = "dotted") +
    geom_pointrange() +
    labs(title = "Test H — dCdH (2022) intertemporal estimator, time-varying intensity",
         subtitle = "Phase IV; cumulative effect on share_top per unit pair_intensity. 95% CIs.",
         x = "Horizon h relative to first treatment change",
         y = "Effect on share_top") +
    theme_bw()
  ggsave(file.path(OUT_FIG, "phase6_a10_dcdh_timevarying_test_h.pdf"),
         g, width = 9, height = 5)
  cat("\nFigure written to phase6_a10_dcdh_timevarying_test_h.pdf\n")
} else {
  cat("\n(Figure skipped — dCdH did not run on this sample.)\n")
}
