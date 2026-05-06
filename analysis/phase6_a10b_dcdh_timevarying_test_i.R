# =============================================================================
# R7 Phase IV — Test I heterogeneity-robust intertemporal estimator (dCdH 2022)
# with time-varying continuous treatment intensity. Plan ref: §R7 Test I.
#
# Subtlety / negative finding. cat_intensity_{n,t} is the same across all
# buyer × NACE-4d cells that share NACE-4d n at year t. Running dCdH at the
# (buyer, NACE-4d) level therefore leaves zero within-group variation in
# treatment after fixed-effect demeaning. We tested aggregating to the
# (NACE-4d, year) level — but at that level the time-series of intensity
# across all ETS-regulated NACE-4ds is dominated by the common EUA-price
# trend, which is absorbed by year fixed effects. After demeaning, the
# residual variation in cat_intensity is too small to identify dCdH effects:
# both the cell-level and the NACE-4d-level versions return
# "After removing NAs, not a single explanatory variable is different from 0."
#
# **Conclusion.** Test I, by design, is identified from cross-NACE-4d variation
# in *exposure* to the EUA price interacted with a single common cutoff
# (2015), not from time-varying intensity within a panel of treated NACEs.
# The substantive R7 cross-check therefore reduces to the static
# `nace_exposure × post` interaction already reported in §5.1.4. We document
# this here for transparency and recommend the dCdH-2022 estimator only at
# the cell level for Test H (where j*'s firm-specific time path of intensity
# does generate within-cell, within-year variation).
#
# This script is kept and run for completeness; it always reports OLS only.
#
# Spec.
#   group     = NACE-4d  [integer-coded]
#   time      = year
#   outcome   = total_share_{n,t} = sum_b spend_{b,n,t} / sum_b inputs_{b,t}
#               (= aggregate buyer share of inputs spent on category n in year t,
#                  weighted by buyer size via the inputs denominator)
#   treatment = cat_intensity_{n,t}
#               = sales-weighted average over ETS sellers j ∈ NACE-4d n
#                 of intensity_{j,t}
#   effects   = 5  (post-first-switch dynamic effects, h = 0..4)
#   placebo   = 3
#   continuous= 1
#   cluster   = nace2d  (cluster on NACE-2d to allow sectoral correlations)
#
# Outputs:
#   ${OUT_TAB}/phase6_a10b_dcdh_timevarying_test_i.csv
#   ${OUT_TAB}/phase6_a10b_dcdh_timevarying_test_i_summary.csv
#   ${OUT_FIG}/phase6_a10b_dcdh_timevarying_test_i.pdf
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

YEAR_LO   <- 2005L
YEAR_HI   <- 2022L
PRE_LO    <- 2010L
PRE_HI    <- 2014L
EFFECTS   <- 5
PLACEBO   <- 3
N_GROUPS_MIN <- 100L  # at NACE-4d level, ~250-300 NACE-4d on full panel

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Replicate Test I panel from phase5_test_i_cross_nace_substitution.R
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
  , .(vat = vat_ano, year, nace5d, inputs_VAT)]
rm(df_annual_accounts_more_selected_sample)
aa[, year := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
seller_nace <- unique(aa[, .(seller = vat, year, seller_nace4d = nace4d)])
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]

buyer_inputs <- unique(aa[!is.na(inputs_VAT) & inputs_VAT > 0,
                           .(buyer = vat, year, inputs_VAT_total = inputs_VAT)])

load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
b2b <- merge(b2b,
             cost_share_regressor[, .(seller = vat,
                                       fcs_reg = firm_cost_share_regressor)],
             by = "seller", all.x = TRUE)
b2b[is.na(fcs_reg), fcs_reg := 0]

contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
b2b <- b2b[!(seller %in% contaminated_vats & year >= 2021L)]

ets_with_fcs <- cost_share_regressor$vat
b2b <- b2b[!(seller_is_ets == 1L & !(seller %in% ets_with_fcs))]

# ---------------------------------------------------------------------------
# 2. Build cat_intensity_{n,t} (NACE-4d × year time-varying treatment)
# ---------------------------------------------------------------------------
load(file.path(REPO_DIR, "data/processed/firm_year_timevarying_intensity.RData"))
fyti <- as.data.table(firm_year_timevarying_intensity)[
  , .(seller = vat, year, intensity_phase4)]

# Sales-weighted average of seller intensity within each (NACE-4d, year),
# weighted by current-year corr_sales of ETS sellers in that NACE-4d.
b2b_ets <- merge(b2b[seller_is_ets == 1L,
                      .(seller, seller_nace4d, year, corr_sales)],
                 fyti, by = c("seller", "year"), all.x = TRUE)
b2b_ets[is.na(intensity_phase4), intensity_phase4 := 0]
cat_int <- b2b_ets[, .(
  cat_intensity = sum(corr_sales * intensity_phase4) / pmax(sum(corr_sales), 1e-12)
), by = .(nace4d = seller_nace4d, year)]

# ---------------------------------------------------------------------------
# 3. Cell panel and pre-shock regulated_dummy
# ---------------------------------------------------------------------------
b2b_pre <- b2b[year %between% c(PRE_LO, PRE_HI)]
seller_pre <- b2b_pre[, .(sales_pre = sum(corr_sales),
                           fcs_seller = max(fcs_reg)),
                       by = .(seller, seller_nace4d)]
nace_exp <- seller_pre[, .(
  total_sales_pre        = sum(sales_pre),
  weighted_fcs_numerator = sum(sales_pre * fcs_seller)
), by = seller_nace4d]
nace_exp[, nace_exposure := weighted_fcs_numerator / total_sales_pre]
nace_exp[, nace_regulated_dummy := as.integer(nace_exposure > 0)]
setnames(nace_exp, "seller_nace4d", "nace4d")

buyer_year_nace <- b2b[, .(spend_bn = sum(corr_sales)),
                       by = .(buyer, nace4d = seller_nace4d, year)]
panel <- merge(buyer_year_nace, buyer_inputs,
               by = c("buyer", "year"), all.x = FALSE)
panel <- merge(panel, nace_exp[, .(nace4d, nace_exposure,
                                     nace_regulated_dummy)],
               by = "nace4d", all.x = TRUE)
panel <- panel[!is.na(nace_exposure)]
panel[, share := spend_bn / inputs_VAT_total]

# Merge in cat_intensity (n × t)
panel <- merge(panel, cat_int, by = c("nace4d", "year"), all.x = TRUE)
panel[is.na(cat_intensity), cat_intensity := 0]

# Drop 2023 if present (some sources extend a year past YEAR_HI)
panel <- panel[year %between% c(YEAR_LO, YEAR_HI)]

cat(sprintf("Test I cell-years: %d, cells: %d, NACE-4d: %d, years: %d-%d\n",
            nrow(panel), uniqueN(paste(panel$buyer, panel$nace4d)),
            uniqueN(panel$nace4d), min(panel$year), max(panel$year)))

# ---------------------------------------------------------------------------
# 4. Aggregate to (NACE-4d, year) level — the level at which treatment varies.
# ---------------------------------------------------------------------------
agg <- panel[, .(total_spend  = sum(spend_bn),
                  total_inputs = sum(inputs_VAT_total),
                  cat_intensity = first(cat_intensity)),
              by = .(nace4d, year)]
agg[, total_share := total_spend / total_inputs]
agg[, year_int := as.integer(year)]
agg[, nace2d   := substr(nace4d, 1, 2)]
agg[, group_id := .GRP, by = nace4d]
agg[, nace2d_id := .GRP, by = nace2d]

# Balance: every NACE-4d observed every year (already approximately so).
all_years <- seq(min(agg$year_int), max(agg$year_int))
all_groups <- unique(agg[, .(group_id, nace4d, nace2d_id)])
balanced  <- CJ(group_id = all_groups$group_id, year_int = all_years)
balanced  <- merge(balanced, all_groups, by = "group_id")
panel_b   <- merge(balanced,
                   agg[, .(group_id, year_int, total_share, cat_intensity)],
                   by = c("group_id", "year_int"), all.x = TRUE)
panel_b[is.na(total_share), total_share := 0]
panel_b[is.na(cat_intensity), cat_intensity := 0]

cat(sprintf("R7 Test I aggregated panel: %d rows (%d NACE-4d × %d years)\n",
            nrow(panel_b), uniqueN(panel_b$group_id), length(all_years)))

# ---------------------------------------------------------------------------
# 5. dCdH estimator
# ---------------------------------------------------------------------------
df_dcdh <- panel_b[, .(group_id     = as.integer(group_id),
                        year_int    = as.integer(year_int),
                        total_share = as.numeric(total_share),
                        cat_intensity = as.numeric(cat_intensity),
                        nace2d_id   = as.integer(nace2d_id))]

n_groups <- uniqueN(df_dcdh$group_id)
if (n_groups < N_GROUPS_MIN) {
  cat(sprintf(
    "\n[WARNING] only %d NACE-4d groups available; need %d+ for dCdH.\n",
    n_groups, N_GROUPS_MIN))
  res <- NULL
} else {
  cat("\nRunning did_multiplegt_dyn at NACE-4d × year level...\n")
  t0 <- Sys.time()
  res <- tryCatch(
    did_multiplegt_dyn(
      df         = as.data.frame(df_dcdh),
      outcome    = "total_share",
      group      = "group_id",
      time       = "year_int",
      treatment  = "cat_intensity",
      effects    = EFFECTS,
      placebo    = PLACEBO,
      continuous = 1,
      cluster    = "nace2d_id",
      graph_off  = TRUE,
      ci_level   = 95,
      bootstrap  = 100,
      drop_if_d_miss_before_first_switch = TRUE
    ),
    error = function(e) {cat("dCdH error:", conditionMessage(e), "\n"); NULL})
  cat(sprintf("Elapsed: %s\n", format(Sys.time() - t0)))
}

# ---------------------------------------------------------------------------
# 6. OLS comparator (the headline trend-corrected binary spec)
# ---------------------------------------------------------------------------
panel[, post := as.integer(year >= 2015L)]
panel[, regulated_post := nace_regulated_dummy * post]
panel[, by_year := paste(buyer, year, sep = "_")]
panel[, b_n     := paste(buyer, nace4d, sep = "_")]
m_ols <- feols(share ~ regulated_post | by_year + b_n,
               data = panel, cluster = ~ buyer, notes = FALSE)
ols_b  <- coef(m_ols)["regulated_post"]
ols_se <- sqrt(diag(vcov(m_ols)))["regulated_post"]

# ---------------------------------------------------------------------------
# 7. Output
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
  fwrite(es_table, file.path(OUT_TAB, "phase6_a10b_dcdh_timevarying_test_i.csv"))
  print(es_table)
} else {
  fwrite(data.table(note = "dCdH skipped — too few cells / RMD required"),
         file.path(OUT_TAB, "phase6_a10b_dcdh_timevarying_test_i.csv"))
}

if (nrow(es_table) > 0L) {
  cum_h_max <- sum(es_table[kind == "effect" & h <= (EFFECTS - 1L)]$Estimate)
} else {
  cum_h_max <- NA_real_
}
summary_tbl <- data.table(
  spec = c("OLS static binary (regulated × post)",
           sprintf("dCdH cumulative h=0..%d (time-varying cat_intensity)",
                   EFFECTS - 1L)),
  estimate = c(ols_b, cum_h_max),
  se       = c(ols_se, NA_real_),
  units    = c("share / unit", "share")
)
fwrite(summary_tbl,
       file.path(OUT_TAB, "phase6_a10b_dcdh_timevarying_test_i_summary.csv"))
cat("\nSummary OLS vs dCdH:\n"); print(summary_tbl)

if (nrow(es_table) > 0L) {
  es_table[, ci_lo := Estimate - 1.96 * SE]
  es_table[, ci_hi := Estimate + 1.96 * SE]
  g <- ggplot(es_table, aes(x = h, y = Estimate, ymin = ci_lo, ymax = ci_hi,
                            colour = kind)) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_vline(xintercept = -0.5, linetype = "dotted") +
    geom_pointrange() +
    labs(title = "Test I — dCdH (2022) intertemporal estimator, time-varying cat_intensity",
         subtitle = "Phase IV; cumulative effect on share per unit cat_intensity. 95% CIs.",
         x = "Horizon h relative to first treatment change",
         y = "Effect on share") +
    theme_bw()
  ggsave(file.path(OUT_FIG, "phase6_a10b_dcdh_timevarying_test_i.pdf"),
         g, width = 9, height = 5)
}
