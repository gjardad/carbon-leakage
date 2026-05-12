# phase3_b2b_cdgm_did_continuous.R
#
# Three changes vs phase3_b2b_cdgm_did.R:
#
#   (1) Continuous-intensity treatment: firm_cost_share_j (per Angle 4 /
#       phase4_b2b_supplier_switching.R) replaces the binary
#       is_ets x is_regulated_NACE indicator. Defined for ETS sellers as
#         firm_cost_share = mean_{2013-15}(shortage * EUA) /
#                           mean_{2010-12}(total_cost)
#       and 0 for non-ETS sellers. Coefficient interpretation: response of
#       outcome per unit cost-share intensity.
#
#   (2) Active-pairs-only sample: drop the balance/zero-fill rows. The
#       regression now estimates pure intensive-margin response within active
#       pair-years, removing extensive-margin / market-structure variation
#       that may have inflated the binary-treatment magnitudes.
#
#   (3) Pre-trend test: load B2B from RAW (2002-2022) instead of the
#       2005-restricted selected_sample. Phase indicators add a pre-period
#       (2002-2004) and a placebo "fake-treatment" coefficient on
#       firm_cost_share x pre_period -- if non-zero, parallel trends fail.
#       Reference year for the event study is 2004 (last pre-ETS year).
#
# Spec (phase-aggregated):
#   y_{j,b,t} = b_pre * firm_cost_share_j * 1(t in 2002-04)
#             + b_1   * firm_cost_share_j * 1(t in 2005-08)
#             + b_2   * firm_cost_share_j * 1(t in 2009-12)
#             + b_3   * firm_cost_share_j * 1(t in 2013-19)
#             + alpha_{j,b} + delta_{sn4d,t} + delta_{bn4d,t} + e
#
# Reference: cells with firm_cost_share = 0 (non-ETS sellers) and pre-2002 (none).
# Interpretation: per unit firm_cost_share, the change in y in the given phase
# relative to the implicit baseline. b_pre tests parallel pre-trends.
#
# Outcomes:
#   share        = corr_sales / sum(corr_sales | buyer, seller_nace4d, year)
#   prob_active  = 1(corr_sales > 0)  -- but the active-only filter drops zeros,
#                  so this becomes effectively 1 for all rows. Skip Panel B for
#                  the active-only sample. Run Panel B on the BALANCED panel
#                  separately.
#
# Outputs:
#   output/tables/phase3_b2b_cdgm_continuous_phase.csv  (phase-aggregated, 6 cols + 1 robustness)
#   output/tables/phase3_b2b_cdgm_continuous_eventstudy.csv  (year-by-year)
#   output/figures/phase3_b2b_cdgm_continuous_eventstudy.png

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE)) install.packages("fixest", repos = "https://cloud.r-project.org")
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2", repos = "https://cloud.r-project.org")
if (!requireNamespace("patchwork", quietly = TRUE)) install.packages("patchwork", repos = "https://cloud.r-project.org")

library(data.table)
library(fixest)
library(haven)
library(ggplot2)
library(patchwork)

YEAR_LO <- 2002L
YEAR_HI <- 2019L
REF_YEAR <- 2004L

# Pre-period 2013-15 / 2010-12 windows (Angle 4 convention).
pre_num_lo   <- 2013L
pre_num_hi   <- 2015L
pre_denom_lo <- 2010L
pre_denom_hi <- 2012L

# EUA price series (Angle 4 convention; phase4_b2b_supplier_switching.R:97-99).
eua_prices <- data.table(
  year = 2005:2022,
  eua_price = c(22, 18, 0.7, 22, 13, 14, 13, 7.5,
                4.5, 6, 7.5, 5, 5.8, 16, 25, 25, 53, 80))

# ---------------------------------------------------------------------------
# 1. Load raw B2B (2002-2022) and clean
# ---------------------------------------------------------------------------
b2b_path <- file.path(RAW_DATA, "NBB", "B2B_ANO.dta")
cat("Loading raw B2B from:", b2b_path, "\n")
b2b <- as.data.table(read_dta(b2b_path))
setnames(b2b,
         c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         c("seller", "buyer", "corr_sales"))
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(corr_sales) & corr_sales > 0]
cat("Raw B2B rows after year+positive filter:", nrow(b2b), "\n")

# ---------------------------------------------------------------------------
# 2. Annual accounts -- NACE 2d/4d for seller and buyer
# ---------------------------------------------------------------------------
aa_path <- file.path(RAW_DATA, "NBB", "Annual_Accounts_MASTER_ANO.dta")
aa <- as.data.table(read_dta(aa_path,
                             col_select = c("vat_ano", "year", "nace5d")))
setnames(aa, "vat_ano", "vat")
aa[, year := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa[, nace2d := substr(nace4d, 1, 2)]
aa <- unique(aa[, .(vat, year, nace4d, nace2d)])

seller_nace <- copy(aa)
setnames(seller_nace, c("vat", "year", "nace4d", "nace2d"),
         c("seller", "year", "seller_nace4d", "seller_nace2d"))
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
buyer_nace <- copy(aa)
setnames(buyer_nace, c("vat", "year", "nace4d", "nace2d"),
         c("buyer", "year", "buyer_nace4d", "buyer_nace2d"))
b2b <- merge(b2b, buyer_nace, by = c("buyer", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace2d) & !is.na(buyer_nace2d)]
cat("Rows after NACE join + drop NA:", nrow(b2b), "\n")

# ---------------------------------------------------------------------------
# 3. ETS flag and regulated-NACE flag
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_long <- as.data.table(firm_year_belgian_euets)
ets_vats <- unique(ets_long$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

reg_prod <- fread(file.path(REPO_DIR, "data", "io", "regulated_producing_nace.csv"))
reg_prod[, nace2d := sprintf("%02d", as.integer(nace2d))]
b2b[, seller_is_regulated_nace := as.integer(seller_nace2d %in% reg_prod$nace2d)]

# ---------------------------------------------------------------------------
# 4. Filter: regulated-intensive buyer + core-input pair
# ---------------------------------------------------------------------------
ri <- fread(file.path(REPO_DIR, "data", "io", "regulated_intensive_nace.csv"))
ri[, nace2d := sprintf("%02d", as.integer(nace2d))]
b2b <- b2b[buyer_nace2d %in% ri$nace2d]

core <- fread(file.path(REPO_DIR, "data", "io", "core_inputs_by_downstream.csv"))
core <- core[threshold == 0.10,
             .(buyer_nace2d = sprintf("%02d", as.integer(downstream_nace2d)),
               seller_nace2d = sprintf("%02d", as.integer(upstream_cpa_nace2d)),
               is_core = TRUE)]
core <- unique(core)
b2b <- merge(b2b, core, by = c("buyer_nace2d", "seller_nace2d"), all.x = TRUE)
b2b <- b2b[!is.na(is_core)]
b2b[, is_core := NULL]
cat("Rows after RI buyer + core-input filter:", nrow(b2b), "\n")

# ---------------------------------------------------------------------------
# 5. Build firm_cost_share for each ETS seller (Angle 4 convention)
# ---------------------------------------------------------------------------
firm_exposure <- as.data.table(firm_year_belgian_euets)[in_sample == 1]
firm_exposure <- merge(firm_exposure, eua_prices, by = "year", all.x = TRUE)
firm_exposure[, shortage    := pmax(emissions - allocated_free, 0)]
firm_exposure[, carbon_cost := shortage * eua_price]
firm_exposure[, mat_inputs  := revenue - value_added]
firm_exposure[, total_cost  := mat_inputs + wage_bill]

num_firm <- firm_exposure[year %between% c(pre_num_lo, pre_num_hi),
                          .(mean_carbon_cost = mean(carbon_cost, na.rm = TRUE)),
                          by = vat]
denom_firm <- firm_exposure[year %between% c(pre_denom_lo, pre_denom_hi) &
                              !is.na(total_cost) & total_cost > 0,
                            .(mean_total_cost = mean(total_cost, na.rm = TRUE)),
                            by = vat]
ets_treatment <- merge(num_firm, denom_firm, by = "vat", all = FALSE)
ets_treatment[, firm_cost_share := mean_carbon_cost / mean_total_cost]
ets_treatment <- ets_treatment[!is.na(firm_cost_share),
                                .(seller = vat, firm_cost_share)]

cat("ETS firms with firm_cost_share:", nrow(ets_treatment), "\n")
cat("firm_cost_share quantiles:\n")
print(quantile(ets_treatment$firm_cost_share, c(0.1, 0.5, 0.9, 0.99), na.rm = TRUE))

# Attach to B2B; non-ETS sellers get firm_cost_share = 0.
b2b <- merge(b2b, ets_treatment, by = "seller", all.x = TRUE)
b2b[is.na(firm_cost_share), firm_cost_share := 0]

# Drop ETS sellers without a computable firm_cost_share (small group; same as
# Angle 4 convention -- they have ETS status but no clean exposure measure).
b2b <- b2b[!(seller_is_ets == 1L & !(seller %in% ets_treatment$seller))]
cat("Rows after firm_cost_share join:", nrow(b2b), "\n")

# ---------------------------------------------------------------------------
# 6. Compute outcome (share within buyer x seller-NACE x year)
# ---------------------------------------------------------------------------
b2b[, total_buyer_sn4d_t := sum(corr_sales),
    by = .(buyer, seller_nace4d, year)]
b2b[, share := ifelse(total_buyer_sn4d_t > 0,
                      corr_sales / total_buyer_sn4d_t, 0)]

# ---------------------------------------------------------------------------
# 7. Phase indicators (with pre-period)
# ---------------------------------------------------------------------------
b2b[, phase_pre := as.integer(year %between% c(2002L, 2004L))]
b2b[, phase_p1  := as.integer(year %between% c(2005L, 2008L))]
b2b[, phase_p2  := as.integer(year %between% c(2009L, 2012L))]
b2b[, phase_p3  := as.integer(year %between% c(2013L, 2019L))]

b2b[, treat_pre := firm_cost_share * phase_pre]
b2b[, treat_p1  := firm_cost_share * phase_p1]
b2b[, treat_p2  := firm_cost_share * phase_p2]
b2b[, treat_p3  := firm_cost_share * phase_p3]

# FE keys.
b2b[, seller_buyer := paste(seller, buyer, sep = "_")]
b2b[, sn4d_year   := paste(seller_nace4d, year, sep = "_")]
b2b[, bn4d_year   := paste(buyer_nace4d,  year, sep = "_")]

# ---------------------------------------------------------------------------
# 8. Phase-aggregated regression -- Recommendation 1 + 2 + pre-trend
# ---------------------------------------------------------------------------
# Active-pairs-only sample is automatic: we never zero-filled, so corr_sales > 0
# for every row in b2b.
cat("\n=== Phase-aggregated regression, continuous intensity, active pairs only ===\n")

extract_continuous <- function(model, label) {
  tab <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(tab, c("term", "estimate", "se", "tval", "pval"))
  tab <- tab[grepl("^treat_", term)]
  tab[, spec := label]
  tab[, .(spec, term, estimate, se, tval, pval)]
}

m_share <- feols(
  share ~ treat_pre + treat_p1 + treat_p2 + treat_p3 |
    seller_buyer + sn4d_year + bn4d_year,
  cluster = ~ seller + buyer, data = b2b)
out_share <- extract_continuous(m_share, "share, col5 FE")
cat("\n--- Share (intensive margin) ---\n")
print(out_share)

# Two FE robustness columns for the share regression (col 1, col 4 analogs).
m_share_c1 <- feols(
  share ~ treat_pre + treat_p1 + treat_p2 + treat_p3 |
    sn4d_year,
  cluster = ~ seller + buyer, data = b2b)
m_share_c4 <- feols(
  share ~ treat_pre + treat_p1 + treat_p2 + treat_p3 |
    seller_buyer + bn4d_year,
  cluster = ~ seller + buyer, data = b2b)
out_share_c1 <- extract_continuous(m_share_c1, "share, col1 FE (sn4d_year)")
out_share_c4 <- extract_continuous(m_share_c4, "share, col4 FE (seller_buyer + bn4d_year)")

# NOTE on probability outcome (extensive margin):
# The probability regression requires a balanced (zero-fill) panel. The
# existing b2b_cdgm_panel.RData only covers 2005+ (it was built from
# b2b_selected_sample which restricted to 2005+). Running probability on
# that panel would mean no pre-trend test for the extensive margin.
# Rebuilding a 2002+ balanced panel is non-trivial because of the cross-join
# size and is left for a future iteration. This script focuses on the
# intensive-margin share with full pre-period coverage 2002-2019.

# Save phase-aggregated table.
phase_out <- rbindlist(list(out_share, out_share_c1, out_share_c4))
phase_out[, ci_lo := estimate - 1.96 * se]
phase_out[, ci_hi := estimate + 1.96 * se]

tab_dir <- file.path(REPO_DIR, "output", "tables")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
fwrite(phase_out, file.path(tab_dir, "phase3_b2b_cdgm_continuous_phase.csv"))
cat("\nPhase table saved:",
    file.path(tab_dir, "phase3_b2b_cdgm_continuous_phase.csv"), "\n")

# ---------------------------------------------------------------------------
# 10. Event study: year-by-year coefficients on (firm_cost_share x year_f)
# ---------------------------------------------------------------------------
cat("\n=== Event study, continuous intensity, active pairs only ===\n")
b2b[, year_f := factor(year)]
b2b[, year_f := relevel(year_f, ref = as.character(REF_YEAR))]

run_es <- function(d, outcome, label) {
  fm <- as.formula(sprintf(
    "%s ~ i(year_f, firm_cost_share, ref = '%d') | seller_buyer + sn4d_year + bn4d_year",
    outcome, REF_YEAR))
  m <- feols(fm, data = d, cluster = ~ seller + buyer)
  co <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
  setnames(co, c("term", "estimate", "se", "tval", "pval"))
  co[, year := suppressWarnings(as.integer(gsub(".*::([0-9]+):.*", "\\1", term)))]
  co <- co[!is.na(year)]
  co[, ci_lo := estimate - 1.96 * se]
  co[, ci_hi := estimate + 1.96 * se]
  ref_row <- data.table(year = REF_YEAR, estimate = 0, se = 0, ci_lo = 0, ci_hi = 0)
  out <- rbind(co[, .(year, estimate, se, ci_lo, ci_hi)], ref_row, fill = TRUE)
  out[, outcome := label]
  setorder(out, year)
  out
}

es_share <- run_es(b2b, "share", "Share (active pairs)")
cat("\n--- Share event-study coefficients (continuous intensity) ---\n")
print(es_share[, .(year, beta = round(estimate, 4),
                   se = round(se, 4),
                   ci_lo = round(ci_lo, 4),
                   ci_hi = round(ci_hi, 4))])

fwrite(es_share, file.path(tab_dir, "phase3_b2b_cdgm_continuous_eventstudy.csv"))

# Plot.
make_es_plot <- function(es_dt, ylab, panel_title) {
  ggplot(es_dt, aes(x = year, y = estimate)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_vline(xintercept = 2004.5, linetype = "dotted", color = "grey50") +
    geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi),
                    size = 0.3, color = "navy") +
    labs(title = panel_title, x = NULL, y = ylab) +
    theme_minimal(base_size = 11)
}
p_share <- make_es_plot(es_share, expression(beta[tau]),
                        "Share, active pairs only -- continuous intensity (firm_cost_share)")
combined <- p_share +
  plot_annotation(
    title = "B2B CdGM continuous-intensity event study",
    subtitle = sprintf("Treatment = firm_cost_share x year (vs %d). FE: seller^buyer + sn4d^year + bn4d^year. Cluster: seller + buyer.",
                       REF_YEAR),
    caption = "Active-pairs-only sample. Pre-period 2002-2004 included to test parallel trends.")

fig_dir <- file.path(REPO_DIR, "output", "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
ggsave(file.path(fig_dir, "phase3_b2b_cdgm_continuous_eventstudy.png"),
       combined, width = 9, height = 5, dpi = 200)
cat("\nFigure saved:",
    file.path(fig_dir, "phase3_b2b_cdgm_continuous_eventstudy.png"), "\n")
