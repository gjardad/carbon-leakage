###############################################################################
# phase5_test_i_cross_nace_substitution.R
#
# Test I: across-NACE-4d category substitution in the buyer's input mix.
# Companion to Test H (within-NACE-4d, across-supplier substitution).
#
# Question: when carbon pricing raises the *average* price of category n
# (driven by category n's average ETS exposure), do Belgian buyers reweight
# their expenditure away from category n toward other categories?
#
# This is the buyer-side analog of CdGM's regulated-vs-unregulated PPI event
# study. CdGM's published spec is at the SECTOR PPI level (output-side
# pass-through). Test I asks whether buyers' INPUT-MIX shares respond to the
# same category-level treatment.
#
# Difference from Phase 0 GK decomposition (which already shows ~20-23pp
# between-sector emissions decline 2005-2022): Phase 0 is descriptive,
# attributing emissions changes to accounting channels. Test I is causal --
# does treatment-by-exposure correlate with within-buyer share reallocation
# post-2015, conditional on buyer-year scale and buyer-category preference?
#
# CONSTRUCTION
#
#   Treatment: nace_exposure_n at the NACE 4d level
#       nace_exposure_n = Σ_{j ∈ ETS sellers in n} mean_{2010..14}[corr_sales_j] × fcs_j
#                         ÷
#                         Σ_{j ∈ all sellers in n} mean_{2010..14}[corr_sales_j]
#       Time-invariant per category. Represents the average per-€ supplier-
#       side cost shock under full pass-through. Both ETS-share and average
#       fcs of regulated firms enter multiplicatively.
#
#   Outcome: share_{b, n, t}
#       = Σ_{j: seller_nace4d_j = n} corr_sales_{j, b, t}
#         ÷
#         inputs_VAT_total_{b, t}
#
#   Sample: (buyer × NACE 4d) cells where the buyer has positive spending
#       on category n in at least one pre-shock year (2010-14). Restricts
#       attention to the buyer's "active categories" -- the categories they
#       could plausibly substitute among.
#
# REGRESSIONS
#
#   Spec I.1 (pooled DiD):
#       share_{b,n,t} = β · nace_exposure_n × Post_t + α_{b,t} + α_{b,n} + ε
#
#   Spec I.2 (detrended):
#       + γ · nace_exposure_n × year_c control
#
#   Spec I.3 (binary regulated dummy):
#       share_{b,n,t} = β · regulated_n × Post_t + α_{b,t} + α_{b,n} + ε
#       regulated_n = 1{nace_exposure_n > 0} or {2-digit in CdGM-broad list}
#
#   Spec I.4 (event study):
#       share_{b,n,t} = Σ_τ γ_τ · 1{t = τ} × nace_exposure_n + α_{b,t} + α_{b,n} + ε
#       Post-hoc detrending: subtract pre-2014 linear fit (same helper as
#       phase5_test_h_upgrades.R).
#
#   Spec I.5 (quartile split): re-run I.2 separately on the four quartiles
#       of nace_exposure_n. The economically-meaningful test of whether the
#       response scales with treatment intensity.
#
# OUTPUTS to OUTPUT_TAB / OUTPUT_FIG (per-machine via paths.R):
#
#   phase5_test_i_main.csv             (Spec I.1, I.2, I.3 pooled)
#   phase5_test_i_quartile_split.csv   (Spec I.5)
#   phase5_test_i_event_study.csv      (Spec I.4 with detrended col)
#   phase5_test_i_event_study.pdf
#   phase5_test_i_nace_exposure_distribution.csv (treatment distribution)
###############################################################################

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) {
  parent <- dirname(REPO_DIR)
  if (parent == REPO_DIR) stop("paths.R not found walking up from ",
                                normalizePath(getwd(), winslash = "/"),
                                ". cd into the repo root first.")
  REPO_DIR <- parent
}
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE))
  install.packages("fixest", repos = "https://cloud.r-project.org")
if (!requireNamespace("ggplot2", quietly = TRUE))
  install.packages("ggplot2", repos = "https://cloud.r-project.org")

library(data.table)
library(fixest)
library(ggplot2)

YEAR_LO   <- 2005L
YEAR_HI   <- 2022L
POST_FROM <- 2015L
PRE_LO    <- 2010L
PRE_HI    <- 2014L

# ---------------------------------------------------------------------------
# 1. Load B2B, NACE, EUETS, fcs, buyer total inputs
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
cat(sprintf("B2B active rows in [%d, %d]: %d\n", YEAR_LO, YEAR_HI, nrow(b2b)))

load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_more_selected_sample)[
  , .(vat = vat_ano, year, nace5d, inputs_VAT)]
rm(df_annual_accounts_more_selected_sample)
aa[, year   := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa[, nace2d := substr(nace4d, 1, 2)]

seller_nace <- unique(aa[, .(seller = vat, year, seller_nace4d = nace4d,
                              seller_nace2d = nace2d)])
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

# Drop contaminated VATs from 2021+
contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
b2b <- b2b[!(seller %in% contaminated_vats & year >= 2021L)]

# Drop ETS sellers without an fcs_reg value (consistent with Test H)
ets_with_fcs <- cost_share_regressor$vat
b2b <- b2b[!(seller_is_ets == 1L & !(seller %in% ets_with_fcs))]

cat(sprintf("After cleaning: %d rows; %d distinct buyers; %d distinct sellers\n",
            nrow(b2b), uniqueN(b2b$buyer), uniqueN(b2b$seller)))

# ---------------------------------------------------------------------------
# 2. Compute nace_exposure_n at the NACE 4d level
#    Pre-shock (2010-14) sales-weighted average fcs across all sellers.
# ---------------------------------------------------------------------------
b2b_pre <- b2b[year %between% c(PRE_LO, PRE_HI)]
seller_pre <- b2b_pre[, .(sales_pre = sum(corr_sales),
                           fcs_seller = max(fcs_reg)),  # time-invariant per seller
                       by = .(seller, seller_nace4d)]

nace_exposure <- seller_pre[, .(
  total_sales_pre        = sum(sales_pre),
  weighted_fcs_numerator = sum(sales_pre * fcs_seller)
), by = seller_nace4d]
nace_exposure[, nace_exposure := weighted_fcs_numerator / total_sales_pre]
nace_exposure[, nace_regulated_dummy := as.integer(nace_exposure > 0)]
setnames(nace_exposure, "seller_nace4d", "nace4d")

cat(sprintf("\nNACE 4d categories with pre-shock B2B sales: %d\n",
            nrow(nace_exposure)))
cat("nace_exposure distribution (across NACE 4d categories):\n")
print(quantile(nace_exposure$nace_exposure,
               c(0.5, 0.75, 0.9, 0.95, 0.99), na.rm = TRUE))
cat(sprintf("Categories with nace_exposure > 0 (regulated): %d (%.1f%%)\n",
            sum(nace_exposure$nace_regulated_dummy),
            100 * mean(nace_exposure$nace_regulated_dummy)))

# Top 10 categories by nace_exposure
top_n <- copy(nace_exposure)[order(-nace_exposure)][1:10]
cat("\nTop 10 NACE 4d by nace_exposure:\n")
print(top_n[, .(nace4d, nace_exposure, total_sales_pre)])

fwrite(nace_exposure[order(-nace_exposure)],
       file.path(OUTPUT_TAB, "phase5_test_i_nace_exposure_distribution.csv"))

# ---------------------------------------------------------------------------
# 3. Build cell panel: (buyer × NACE 4d × year) spending
# ---------------------------------------------------------------------------
cell_yr <- b2b[, .(spend_bn = sum(corr_sales)),
               by = .(buyer, nace4d = seller_nace4d, year)]
setkey(cell_yr, buyer, nace4d, year)

# Active-category sample: cells with positive spending in at least one
# pre-shock year (2010-14)
active_cells <- unique(cell_yr[year %between% c(PRE_LO, PRE_HI) & spend_bn > 0,
                                .(buyer, nace4d)])
cat(sprintf("\nActive (buyer × NACE 4d) cells with pre-shock positive spending: %d\n",
            nrow(active_cells)))
cat(sprintf("  Distinct buyers in active sample: %d\n",
            uniqueN(active_cells$buyer)))

# Build a balanced panel for active cells: every (buyer, nace4d, year) in
# YEAR_LO..YEAR_HI, with spend = 0 if not observed in cell_yr.
all_years <- data.table(year = YEAR_LO:YEAR_HI)
panel <- active_cells[, .(buyer, nace4d)][, k := 1L][
  all_years[, k := 1L], on = "k", allow.cartesian = TRUE][, k := NULL]
panel <- merge(panel, cell_yr,
               by = c("buyer", "nace4d", "year"), all.x = TRUE)
panel[is.na(spend_bn), spend_bn := 0]

# Bring in buyer's total inputs and treatment
panel <- merge(panel, buyer_inputs, by = c("buyer", "year"), all.x = FALSE)
panel <- merge(panel, nace_exposure[, .(nace4d, nace_exposure,
                                         nace_regulated_dummy)],
               by = "nace4d", all.x = TRUE)
panel <- panel[!is.na(nace_exposure)]

panel[, share := spend_bn / inputs_VAT_total]
panel[, post  := as.integer(year >= POST_FROM)]
panel[, year_c := year - YEAR_LO]
panel[, treat_post     := nace_exposure       * post]
panel[, treat_year     := nace_exposure       * year_c]
panel[, regulated_post := nace_regulated_dummy * post]

# Buyer × year and buyer × nace4d cluster IDs (concat for fixest)
panel[, by_year := paste(buyer, year, sep = "_")]
panel[, b_n     := paste(buyer, nace4d, sep = "_")]

cat(sprintf("\nFinal panel: %d cell-years across %d active cells, %d buyers, %d categories\n",
            nrow(panel), uniqueN(panel$b_n), uniqueN(panel$buyer),
            uniqueN(panel$nace4d)))
cat(sprintf("Share statistics:\n"))
print(summary(panel$share))

# ---------------------------------------------------------------------------
# 4. Helper: extract single coefficient from a feols model
# ---------------------------------------------------------------------------
extract_one <- function(model, term_name, label, n_cells = NA_integer_) {
  if (is.null(model)) return(NULL)
  ct <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(ct, c("term", "estimate", "se", "tval", "pval"))
  row <- ct[term == term_name]
  if (nrow(row) == 0L) return(NULL)
  row[, spec := label]
  row[, n    := nobs(model)]
  row[, n_cells := n_cells]
  row[, .(spec, term, estimate, se, tval, pval, n, n_cells)]
}

# ---------------------------------------------------------------------------
# 5. Spec I.1 (pooled DiD), I.2 (detrended), I.3 (regulated dummy)
# ---------------------------------------------------------------------------
cat("\n\n=== Spec I.1: pooled DiD ===\n")
m_i1 <- feols(share ~ treat_post | by_year + b_n,
              data = panel, cluster = ~ buyer)
print(summary(m_i1))

cat("\n\n=== Spec I.2: detrended (treat_year continuous control) ===\n")
m_i2 <- feols(share ~ treat_post + treat_year | by_year + b_n,
              data = panel, cluster = ~ buyer)
print(summary(m_i2))

cat("\n\n=== Spec I.3: regulated × Post (binary treatment) ===\n")
m_i3 <- feols(share ~ regulated_post | by_year + b_n,
              data = panel, cluster = ~ buyer)
print(summary(m_i3))

n_cells <- uniqueN(panel$b_n)
main_out <- rbindlist(list(
  extract_one(m_i1, "treat_post",     "I1_pooled",          n_cells),
  extract_one(m_i2, "treat_post",     "I2_detrended_POST",  n_cells),
  extract_one(m_i2, "treat_year",     "I2_detrended_TREND", n_cells),
  extract_one(m_i3, "regulated_post", "I3_regulated_post",  n_cells)
), use.names = TRUE)
fwrite(main_out, file.path(OUTPUT_TAB, "phase5_test_i_main.csv"))

# ---------------------------------------------------------------------------
# 6. Spec I.4: event study (raw) + post-hoc detrending
# ---------------------------------------------------------------------------
cat("\n\n=== Spec I.4: event study (raw) ===\n")
panel[, year_f := factor(year)]
ref_year <- 2014L
panel[, year_f := relevel(year_f, ref = as.character(ref_year))]

m_es <- feols(share ~ i(year_f, nace_exposure, ref = as.character(ref_year)) |
                       by_year + b_n,
              data = panel, cluster = ~ buyer)
print(summary(m_es))

detrend_eventstudy <- function(model, ref_yr, pre_lo = YEAR_LO,
                               pre_hi = ref_yr) {
  ct <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(ct, c("term", "estimate", "se", "tval", "pval"))
  ct <- ct[grepl("year_f::", term)]
  ct[, year := suppressWarnings(as.integer(gsub(".*::([0-9]+):.*", "\\1", term)))]
  ct <- ct[!is.na(year)]
  out <- rbind(ct[, .(year, estimate, se)],
               data.table(year = ref_yr, estimate = 0, se = 0), fill = TRUE)
  setorder(out, year)
  pre <- out[year >= pre_lo & year <= pre_hi]
  slope <- if (nrow(pre) >= 2L)
    coef(lm(estimate ~ I(year - ref_yr) + 0, data = pre))[["I(year - ref_yr)"]]
  else 0
  out[, trend_pred := slope * (year - ref_yr)]
  out[, estimate_detrended := estimate - trend_pred]
  out[, ci_lo := estimate - 1.96 * se]
  out[, ci_hi := estimate + 1.96 * se]
  out[, ci_lo_detrended := estimate_detrended - 1.96 * se]
  out[, ci_hi_detrended := estimate_detrended + 1.96 * se]
  attr(out, "slope") <- slope
  out
}

es_dt <- detrend_eventstudy(m_es, ref_year)
cat(sprintf("\nPre-trend slope: %.4f per year\n", attr(es_dt, "slope")))
fwrite(es_dt, file.path(OUTPUT_TAB, "phase5_test_i_event_study.csv"))

p_es <- ggplot(es_dt, aes(x = year, y = estimate_detrended)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey40") +
  geom_vline(xintercept = ref_year + 0.5, linetype = "dotted",
             colour = "grey50") +
  geom_pointrange(aes(ymin = ci_lo_detrended, ymax = ci_hi_detrended),
                  size = 0.3, colour = "navy") +
  labs(title = "Test I: across-NACE-4d input-mix substitution -- event study",
       subtitle = paste0("Coef on nace_exposure_n × year_f, detrended on 2005-",
                          ref_year, " linear fit. Buyer × year + Buyer × NACE 4d FE."),
       x = NULL, y = "Detrended coef on nace_exposure × year") +
  theme_minimal(base_size = 11)
ggsave(file.path(OUTPUT_FIG, "phase5_test_i_event_study.pdf"),
       p_es, width = 9, height = 4.5)

# ---------------------------------------------------------------------------
# 7. Spec I.5: quartile split by nace_exposure
# ---------------------------------------------------------------------------
cat("\n\n=== Spec I.5: quartile split by nace_exposure ===\n")

# Quartiles defined at the NACE-4d level (one obs per category)
qs <- quantile(nace_exposure$nace_exposure, c(0.25, 0.5, 0.75), na.rm = TRUE)
cat(sprintf("nace_exposure quartile thresholds: Q1=%.4e, median=%.4e, Q3=%.4e\n",
            qs[1], qs[2], qs[3]))

panel[, ne_quartile := fcase(
  nace_exposure <  qs[1], "Q1_lowest",
  nace_exposure <  qs[2], "Q2",
  nace_exposure <  qs[3], "Q3",
  nace_exposure >= qs[3], "Q4_highest",
  default = NA_character_
)]

run_subset <- function(d, label, detrend = TRUE) {
  if (nrow(d) < 100L || uniqueN(d$year) < 2L ||
      uniqueN(d$nace_exposure) < 2L) {
    return(data.table(subset = label, detrend = detrend,
                      n_cells = uniqueN(d$b_n),
                      n_obs = nrow(d), estimate = NA_real_, se = NA_real_,
                      tval = NA_real_, pval = NA_real_))
  }
  fml <- if (detrend) share ~ treat_post + treat_year | by_year + b_n
         else        share ~ treat_post              | by_year + b_n
  m <- tryCatch(feols(fml, data = d, cluster = ~ buyer),
                error = function(e) NULL)
  if (is.null(m)) {
    return(data.table(subset = label, detrend = detrend,
                      n_cells = uniqueN(d$b_n),
                      n_obs = nrow(d), estimate = NA_real_, se = NA_real_,
                      tval = NA_real_, pval = NA_real_))
  }
  ct <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
  setnames(ct, c("term", "estimate", "se", "tval", "pval"))
  ct <- ct[term == "treat_post"]
  data.table(subset = label, detrend = detrend,
             n_cells = uniqueN(d$b_n), n_obs = nobs(m),
             estimate = ct$estimate, se = ct$se,
             tval = ct$tval, pval = ct$pval)
}

split_results <- rbindlist(list(
  run_subset(panel,                                     "all",                detrend = TRUE),
  run_subset(panel[ne_quartile == "Q1_lowest"],         "Q1_lowest",          detrend = FALSE),
  run_subset(panel[ne_quartile == "Q2"],                "Q2",                 detrend = TRUE),
  run_subset(panel[ne_quartile == "Q3"],                "Q3",                 detrend = TRUE),
  run_subset(panel[ne_quartile == "Q4_highest"],        "Q4_highest",         detrend = TRUE),
  run_subset(panel[ne_quartile %in% c("Q3", "Q4_highest")], "Q3_Q4_top_half",  detrend = TRUE),
  run_subset(panel[ne_quartile %in% c("Q1_lowest", "Q2")], "Q1_Q2_bottom_half", detrend = TRUE)
), use.names = TRUE, fill = TRUE)

cat("\n=== Quartile split results ===\n")
print(split_results)
fwrite(split_results,
       file.path(OUTPUT_TAB, "phase5_test_i_quartile_split.csv"))

# ---------------------------------------------------------------------------
# 8. Robustness: log-spending instead of share, using only nonzero cells
# ---------------------------------------------------------------------------
cat("\n\n=== Robustness: log(spend) on nonzero cells ===\n")
panel_nz <- panel[spend_bn > 0]
panel_nz[, log_spend := log(spend_bn)]
m_log <- feols(log_spend ~ treat_post + treat_year | by_year + b_n,
               data = panel_nz, cluster = ~ buyer)
print(summary(m_log))

robust_out <- rbindlist(list(
  extract_one(m_log, "treat_post", "log_spend_detrended_POST",
              uniqueN(panel_nz$b_n)),
  extract_one(m_log, "treat_year", "log_spend_detrended_TREND",
              uniqueN(panel_nz$b_n))
), use.names = TRUE)
fwrite(robust_out, file.path(OUTPUT_TAB, "phase5_test_i_robustness_logspend.csv"))

cat("\nTest I complete. Files:\n")
cat(sprintf("  %s\n", file.path(OUTPUT_TAB, "phase5_test_i_main.csv")))
cat(sprintf("  %s\n", file.path(OUTPUT_TAB, "phase5_test_i_quartile_split.csv")))
cat(sprintf("  %s\n", file.path(OUTPUT_TAB, "phase5_test_i_event_study.csv")))
cat(sprintf("  %s\n", file.path(OUTPUT_TAB, "phase5_test_i_nace_exposure_distribution.csv")))
cat(sprintf("  %s\n", file.path(OUTPUT_TAB, "phase5_test_i_robustness_logspend.csv")))
cat(sprintf("  %s\n", file.path(OUTPUT_FIG, "phase5_test_i_event_study.pdf")))
