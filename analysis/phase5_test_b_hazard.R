###############################################################################
# phase5_test_b_hazard.R
#
# Test B of Plan B: pair-survival hazard by seller carbon intensity ×
# pair-age bucket × post-shock indicator.
#
# Stickiness predicts that old pairs are LESS responsive to ETS shocks than
# young pairs (Heise's break-up hazard falls with age; relational capital
# binds tightest for low-capital young pairs). Concentration predicts the
# hazard is uncorrelated with seller intensity at any age.
#
# SAMPLE:
#   B2B panel restricted to Phase 3 universe (regulated-intensive buyer +
#   core-input pair). Pair-years with pair_age >= 1, 2012-2022.
#
# OUTCOME:
#   pair_dies_t = 1 if pair was active in t-1 (corr_sales_{t-1} > 0) and
#                 has NO further activity from year t onwards (true death,
#                 not just a temporary lapse). Computed within-pair on the
#                 balanced panel.
#
# SPECIFICATION (linear probability):
#   pair_dies_t = Σ_b γ_b · firm_cost_share_regressor_j × 1(t >= 2015)
#                                                    × 1(pair_age_bucket == b)
#               + α_pair + δ_{seller_NACE4d × year} + ε
#   pair_age_bucket ∈ {1-3, 4-7, 8+}
#   firm_cost_share_regressor_j = time-invariant pre-shock value (Prep 2);
#                                 0 for non-ETS sellers.
#   No pre-2015 / 2005-2014 specification is run (Phase II free allocation
#   makes 2005-binding-shock numerator near-zero -- see plan §Prep 2).
#   Cluster on (seller, buyer) two-way per Phase 3 convention.
#
# Predictions:
#   Stickiness:    γ_{1-3} > 0 strongest. Young pairs at high-intensity
#                  sellers die more after 2015; old pairs persist.
#   Concentration: γ ≈ 0 across all age buckets.
#
# Output:
#   output/tables/phase5_test_b_hazard_main.csv         -- main coefficients by age bucket
#   output/tables/phase5_test_b_hazard_by_buyer_nace2d.csv -- sector decomposition
#   output/figures/phase5_test_b_hazard_coefs.pdf
###############################################################################

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE))
  install.packages("fixest", repos = "https://cloud.r-project.org")
if (!requireNamespace("ggplot2", quietly = TRUE))
  install.packages("ggplot2", repos = "https://cloud.r-project.org")

library(data.table)
library(fixest)
library(ggplot2)

YEAR_LO <- 2012L
YEAR_HI <- 2022L
POST_FROM <- 2015L

# ---------------------------------------------------------------------------
# 1. Load balanced B2B panel (Phase 3 universe; 2005-2022)
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "b2b_cmdj_panel.RData"))   # panel
load(file.path(PROC_DATA, "b2b_pair_age.RData"))     # pair_age
load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))   # cost_share_regressor

panel <- as.data.table(panel)
pair_age <- as.data.table(pair_age)

panel <- merge(panel, pair_age, by = c("seller", "buyer"), all.x = TRUE)
panel[, pair_age_t := year - first_year_pair]
panel <- panel[!is.na(first_year_pair)]

# Drop contaminated VATs from 2021+ (consistent with Plan A scripts).
contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
n_drop <- panel[seller %in% contaminated_vats & year >= 2021L, .N]
panel <- panel[!(seller %in% contaminated_vats & year >= 2021L)]
cat(sprintf("Dropped %d B2B rows for contaminated sellers (year >= 2021).\n",
            n_drop))

# ---------------------------------------------------------------------------
# 2. Build pair_dies_t (true death: no activity from year t onward)
# ---------------------------------------------------------------------------
# Within each (seller, buyer), let last_active_year = max(year | corr_sales > 0).
# If t == last_active_year + 1 AND corr_sales_t == 0, pair_dies_t = 1.
# A right-censored pair (last_active_year == YEAR_HI) never dies in-sample.
panel[, active := as.integer(corr_sales > 0)]
# setkey before by-grouping uses data.table's sorted path -- a large speedup
# on the RMD-scale balanced panel.
setkey(panel, seller, buyer, year)
panel[, last_active_year := suppressWarnings(max(year[active == 1L])),
      by = .(seller, buyer)]
# pairs with no active year in the trimmed sample shouldn't appear; keep guard
panel <- panel[is.finite(last_active_year)]
# (re-key after the row drop)
setkey(panel, seller, buyer, year)

# Active in t-1?
panel[, active_lag1 := shift(active, 1L, type = "lag"), by = .(seller, buyer)]
panel[, year_gap_lag := year - shift(year, 1L, type = "lag"),
      by = .(seller, buyer)]
panel[year_gap_lag != 1L, active_lag1 := NA_integer_]

# Death indicator: was active in t-1, inactive in t, never active again.
panel[, pair_dies_t := as.integer(
  active_lag1 == 1L &
  active == 0L &
  year > last_active_year)]
# (year > last_active_year guarantees no activity from year t on.)

# ---------------------------------------------------------------------------
# 3. Attach firm_cost_share_regressor; 0 for non-ETS
# ---------------------------------------------------------------------------
panel <- merge(panel,
               cost_share_regressor[, .(seller = vat,
                                        fcs_reg = firm_cost_share_regressor)],
               by = "seller", all.x = TRUE)
panel[is.na(fcs_reg), fcs_reg := 0]

# Drop ETS sellers without a regressor value (consistent with Test G).
ets_with_fcs <- cost_share_regressor$vat
panel <- panel[!(seller_is_ets == 1L & !(seller %in% ets_with_fcs))]

# ---------------------------------------------------------------------------
# 4. Restrict to estimation sample: pair_age >= 1, year in [YEAR_LO, YEAR_HI]
# ---------------------------------------------------------------------------
samp <- panel[year %between% c(YEAR_LO, YEAR_HI) &
                pair_age_t >= 1L &
                !is.na(active_lag1)]

cat(sprintf("Estimation sample rows: %d\n", nrow(samp)))
cat(sprintf("  Active-in-prior-year rows: %d\n", sum(samp$active_lag1 == 1L)))
cat(sprintf("  Death events:              %d\n", sum(samp$pair_dies_t == 1L)))
cat(sprintf("  Death rate:                %.3f%%\n",
            100 * mean(samp$pair_dies_t)))

# Pair-age bucket. Note: pair_age_t is computed as year - first_year_pair,
# so pair_age_t == 0 is the FORMATION year (first observed year). The
# specification looks at hazard CONDITIONAL on age >= 1 (already past
# formation), bucket on age in {1-3, 4-7, 8+}.
samp[, age_bucket := fcase(
  pair_age_t %between% c(1L, 3L), "1-3",
  pair_age_t %between% c(4L, 7L), "4-7",
  pair_age_t >= 8L,                "8+",
  default = NA_character_
)]
samp[, post := as.integer(year >= POST_FROM)]

# Interaction terms: fcs_reg × post × age_bucket.
for (b in c("1-3", "4-7", "8+")) {
  col <- paste0("treat_", gsub("\\+", "plus", gsub("-", "_", b)))
  samp[, (col) := fcs_reg * post * (age_bucket == b)]
}
# Also a level interaction term per age bucket (for the post-only interaction
# without intensity, controlling for age × post).
for (b in c("1-3", "4-7", "8+")) {
  col <- paste0("post_age_", gsub("\\+", "plus", gsub("-", "_", b)))
  samp[, (col) := post * (age_bucket == b)]
}

samp[, seller_buyer := paste(seller, buyer, sep = "_")]
samp[, sn4d_year   := paste(seller_nace4d, year, sep = "_")]

# ---------------------------------------------------------------------------
# 5. Main regression
# ---------------------------------------------------------------------------
extract_table <- function(model, label) {
  ct <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(ct, c("term", "estimate", "se", "tval", "pval"))
  ct <- ct[grepl("^treat_|^post_age_", term)]
  ct[, spec := label]
  ct[, n    := nobs(model)]
  ct[, .(spec, term, estimate, se, tval, pval, n)]
}

cat("\n--- Main: pair_dies_t ~ fcs_reg x post x age_bucket | pair + sn4d_year ---\n")
m_main <- feols(
  pair_dies_t ~ treat_1_3 + treat_4_7 + treat_8plus +
                post_age_1_3 + post_age_4_7 + post_age_8plus |
    seller_buyer + sn4d_year,
  data = samp, cluster = ~ seller + buyer)
print(summary(m_main))

# Without level age × post controls (simpler).
cat("\n--- Simpler: only intensity x post x age_bucket interactions ---\n")
m_simple <- feols(
  pair_dies_t ~ treat_1_3 + treat_4_7 + treat_8plus |
    seller_buyer + sn4d_year,
  data = samp, cluster = ~ seller + buyer)
print(summary(m_simple))

main_out <- rbindlist(list(extract_table(m_main, "with_post_age_levels"),
                           extract_table(m_simple, "intensity_only")))
fwrite(main_out, file.path(OUTPUT_TAB, "phase5_test_b_hazard_main.csv"))

# ---------------------------------------------------------------------------
# 6. Sector decomposition (split by buyer NACE 2d)
# ---------------------------------------------------------------------------
sector_results <- samp[, {
  if (.N >= 200L && uniqueN(year) >= 2L &&
      uniqueN(fcs_reg[fcs_reg > 0]) >= 1L) {
    m <- tryCatch(feols(
      pair_dies_t ~ treat_1_3 + treat_4_7 + treat_8plus |
        seller_buyer + sn4d_year,
      data = .SD, cluster = ~ seller + buyer),
      error = function(e) NULL)
    if (!is.null(m)) {
      ct <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
      setnames(ct, c("term", "estimate", "se", "tval", "pval"))
      list(term = ct$term,
           estimate = ct$estimate,
           se = ct$se,
           tval = ct$tval,
           pval = ct$pval,
           n_obs = nobs(m))
    } else {
      list(term = NA_character_, estimate = NA_real_, se = NA_real_,
           tval = NA_real_, pval = NA_real_, n_obs = .N)
    }
  } else {
    list(term = NA_character_, estimate = NA_real_, se = NA_real_,
         tval = NA_real_, pval = NA_real_, n_obs = .N)
  }
}, by = buyer_nace2d]
setorder(sector_results, buyer_nace2d, term)
print(sector_results)
fwrite(sector_results,
       file.path(OUTPUT_TAB, "phase5_test_b_hazard_by_buyer_nace2d.csv"))

# ---------------------------------------------------------------------------
# 7. Coefficient plot
# ---------------------------------------------------------------------------
plot_dt <- as.data.table(summary(m_main)$coeftable, keep.rownames = "term")
setnames(plot_dt, c("term", "estimate", "se", "tval", "pval"))
plot_dt <- plot_dt[grepl("^treat_", term)]
plot_dt[, age_bucket := fcase(
  term == "treat_1_3",    "1-3y",
  term == "treat_4_7",    "4-7y",
  term == "treat_8plus",  "8+y",
  default = NA_character_)]
plot_dt[, ci_lo := estimate - 1.96 * se]
plot_dt[, ci_hi := estimate + 1.96 * se]

p <- ggplot(plot_dt, aes(x = age_bucket, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey40") +
  geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi),
                  size = 0.5, colour = "firebrick") +
  labs(title = "Test B: hazard response to ETS shock by pair-age bucket",
       subtitle = sprintf(
         "Coefficient on firm_cost_share x 1(t >= %d) x age_bucket. Pair FE + seller_NACE4d x year FE.",
         POST_FROM),
       x = "Pair-age bucket at year t",
       y = "Coefficient on intensity x post x age (LPM)") +
  theme_minimal(base_size = 11)

ggsave(file.path(OUTPUT_FIG, "phase5_test_b_hazard_coefs.pdf"),
       p, width = 7, height = 5)
cat(sprintf("\nSaved: %s\n",
            file.path(OUTPUT_FIG, "phase5_test_b_hazard_coefs.pdf")))

cat("\nTest B complete.\n")
