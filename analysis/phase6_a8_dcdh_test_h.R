# =============================================================================
# R5 — dCdH (2018) static-intensity heterogeneity-robust counterpart for Test H.
# Plan ref: §R5.
#
# This is the *literal-reading* dCdH: treatment is the time-invariant
# pre-shock pair_exposure, switched on at t = 2015 simultaneously for every
# cell. dCdH (2018) Fuzzy DiD applies. With a single common cutoff, dCdH ≡
# CS ≡ Sun-Abraham — they all reduce to the standard DiD where the
# heterogeneity-robust point estimate equals the OLS β̂ exactly when there
# is no negative weighting (per RSBP §3.5).
#
# In our setting, the static-intensity dCdH should agree with OLS within
# sampling noise — the "useful negative finding" that confirms RSBP §3.5's
# empirical regularity. Significant divergence would indicate negative-
# weighting issues with the OLS spec.
#
# Spec.
#   group     = (buyer, seller_nace4d) cell  [integer-coded]
#   time      = year
#   outcome   = share_top
#   treatment = pair_exposure × Post   (i.e., pair_exposure when t≥2015,
#               else 0; pair_exposure = pre-shock 2010-14 pair-level intensity
#               = firm_cost_share × spend_share_pre)
#   continuous = TRUE
#   cluster   = buyer
#
# Outputs:
#   ${OUT_TAB}/phase6_a8_dcdh_test_h.csv (event-study table)
#   ${OUT_TAB}/phase6_a8_dcdh_test_h_summary.csv (vs OLS)
#   ${OUT_FIG}/phase6_a8_dcdh_test_h.pdf
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2)
  library(polars); library(DIDmultiplegtDYN)
})
source(file.path(REPO_DIR, "analysis/phase6_panel_builders.R"))

YEAR_LO <- 2005L; YEAR_HI <- 2022L
PRE_LO  <- 2010L; PRE_HI  <- 2014L
EFFECTS <- 5
PLACEBO <- 3
N_CELLS_MIN <- 500L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

# Build panel and compute pair_exposure (pre-shock pair-level intensity).
samp_ab <- build_test_h_panel()
# Pre-shock pair exposure: firm_cost_share × pre-shock spending share.
pre <- samp_ab[year %between% c(PRE_LO, PRE_HI),
                .(spend_pre = sum(corr_sales_j_star),
                  total_pre = sum(total_sales_cell)),
                by = .(buyer, seller_nace4d)]
pre[, share_pre := spend_pre / total_pre]
samp_ab <- merge(samp_ab,
                 pre[, .(buyer, seller_nace4d, share_pre)],
                 by = c("buyer", "seller_nace4d"), all.x = TRUE)
samp_ab[is.na(share_pre), share_pre := 0]
samp_ab[, pair_exposure := fcs_j_star * share_pre]
samp_ab[, post := as.integer(year >= 2015L)]
samp_ab[, treat_static := pair_exposure * post]

# Restrict to type-a cells (j* active throughout) for balanced panel.
samp_a <- samp_ab[is_type_a == 1L]
cat(sprintf("R5 Test H balanced sample: %d cell-years across %d cells\n",
            nrow(samp_a), uniqueN(samp_a[, .(buyer, seller_nace4d)])))

samp_a[, cell_id  := .GRP, by = .(buyer, seller_nace4d)]
samp_a[, year_int := as.integer(year)]
samp_a[, buyer_id := .GRP, by = buyer]

df_dcdh <- samp_a[, .(cell_id    = as.integer(cell_id),
                       year_int  = as.integer(year_int),
                       share_top = as.numeric(share_top),
                       treat_static = as.numeric(treat_static),
                       buyer_id  = as.integer(buyer_id))]

# Balance panel.
all_years <- seq(min(df_dcdh$year_int), max(df_dcdh$year_int))
all_cells <- unique(df_dcdh[, .(cell_id, buyer_id)])
balanced  <- CJ(cell_id = all_cells$cell_id, year_int = all_years)
balanced  <- merge(balanced, all_cells, by = "cell_id")
df_dcdh   <- merge(balanced, df_dcdh,
                   by = c("cell_id", "year_int", "buyer_id"), all.x = TRUE)
df_dcdh[is.na(treat_static), treat_static := 0]

n_cells <- uniqueN(df_dcdh$cell_id)
if (n_cells < N_CELLS_MIN) {
  cat(sprintf("\n[WARNING] only %d type-a cells; dCdH needs RMD. OLS only.\n",
              n_cells))
  res <- NULL
} else {
  cat("\nRunning dCdH (static fuzzy)...\n")
  t0 <- Sys.time()
  res <- tryCatch(
    did_multiplegt_dyn(
      df = as.data.frame(df_dcdh),
      outcome = "share_top",
      group = "cell_id",
      time = "year_int",
      treatment = "treat_static",
      effects = EFFECTS,
      placebo = PLACEBO,
      continuous = 1,
      cluster = "buyer_id",
      graph_off = TRUE,
      ci_level = 95,
      bootstrap = 100,
      drop_if_d_miss_before_first_switch = TRUE
    ),
    error = function(e) {cat("dCdH error:", conditionMessage(e), "\n"); NULL})
  cat(sprintf("Elapsed: %s\n", format(Sys.time() - t0)))
}

# OLS comparator (the headline static spec).
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
if (nrow(es_table) > 0L) {
  fwrite(es_table, file.path(OUT_TAB, "phase6_a8_dcdh_test_h.csv"))
  print(es_table)
} else {
  fwrite(data.table(note = "dCdH skipped — RMD required"),
         file.path(OUT_TAB, "phase6_a8_dcdh_test_h.csv"))
}

cum_max <- if (nrow(es_table) > 0L)
  sum(es_table[kind == "effect" & h <= (EFFECTS - 1L)]$Estimate) else NA_real_

summary_tbl <- data.table(
  spec     = c("OLS static (pair_exposure × post)",
               sprintf("dCdH static cumulative h=0..%d", EFFECTS - 1L)),
  estimate = c(ols_b, cum_max),
  se       = c(ols_se, NA_real_),
  units    = c("share / unit pair_exposure", "share")
)
fwrite(summary_tbl, file.path(OUT_TAB, "phase6_a8_dcdh_test_h_summary.csv"))
cat("\nR5 summary:\n"); print(summary_tbl)

if (nrow(es_table) > 0L) {
  es_table[, ci_lo := Estimate - 1.96 * SE]
  es_table[, ci_hi := Estimate + 1.96 * SE]
  g <- ggplot(es_table, aes(x = h, y = Estimate, ymin = ci_lo, ymax = ci_hi,
                            colour = kind)) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_vline(xintercept = -0.5, linetype = "dotted") +
    geom_pointrange() +
    labs(title = "Test H — dCdH (2018) static-intensity Fuzzy DiD",
         subtitle = "Common 2015 cutoff with continuous time-invariant pair_exposure. 95% CIs.",
         x = "Horizon h relative to 2015", y = "Effect on share_top") +
    theme_bw()
  ggsave(file.path(OUT_FIG, "phase6_a8_dcdh_test_h.pdf"),
         g, width = 9, height = 5)
}
