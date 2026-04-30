###############################################################################
# phase5_test_a_new_pair_tilt.R
#
# Test A of Plan B: extensive-margin separator. Among newly formed
# (seller, buyer) pairs, does the seller's carbon intensity tilt
# downward post-2017 (after MSR-binding raised the EUA cost shock)?
#
#   Stickiness:    YES, β2 < 0. New buyers, choosing fresh and not locked
#                  into a sticky relationship, prefer lower-intensity sellers.
#   Concentration: NO, β2 ≈ 0. New buyers also have to match with whoever
#                  exists -- no alternative low-intensity sellers available.
#
# SAMPLE:
#   New pairs formed in year t (is_new_pair_t == 1, where pair_age_t == 0).
#   Restricted to regulated-intensive buyer NACE + core-input pairs (the
#   Phase 3 universe).
#
# OUTCOME (two flavors):
#   A1 (continuous): firm_cost_share_outcome_{j,t} (Prep 2). Seller's
#                    carbon intensity at the time of match.
#   A2 (rank):       within-(seller_nace4d × year) rank of A1, normalized
#                    to [0, 1]. Side-steps year-level shocks to the level
#                    of intensity.
#
# SPECIFICATION:
#   y_{j,b,t} = α
#             + β1 · 1(t ∈ 2005-2016)
#             + β2 · 1(t ∈ 2017+)
#             + γ_{seller_nace4d}
#             + ε
#   Cluster on seller_nace4d. Pre-period 2002-2004 = omitted reference.
#   2017 break = post-MSR Phase III + Phase IV (consistent with Plan A's
#                "binding shock" framing).
#
#   Robustness columns:
#     R1: weight by initial pair sales (β reflects new-trade-value composition).
#     R2: drop left-censored pairs (first_year_pair == 2002).
#     R3: add buyer_nace2d × year FE (test from buyer's perspective).
#
# Stock-vs-flow plot:
#   Mean seller intensity over time, in (i) all active pairs and (ii) new
#   pairs only. Heise §4.2 logic: divergence post-shock = stickiness on stock,
#   substitution on flow.
#
# Output:
#   output/tables/phase5_test_a_new_pair_tilt_main.csv     -- A1 + A2 phase coefs
#   output/tables/phase5_test_a_robustness.csv             -- R1, R2, R3
#   output/tables/phase5_test_a_stock_vs_flow.csv          -- mean intensity by year, sample
#   output/figures/phase5_test_a_event_study.pdf           -- year-by-year coefs
#   output/figures/phase5_test_a_stock_vs_flow.pdf
###############################################################################

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE))
  install.packages("fixest", repos = "https://cloud.r-project.org")
if (!requireNamespace("ggplot2", quietly = TRUE))
  install.packages("ggplot2", repos = "https://cloud.r-project.org")
if (!requireNamespace("patchwork", quietly = TRUE))
  install.packages("patchwork", repos = "https://cloud.r-project.org")

library(data.table)
library(fixest)
library(haven)
library(ggplot2)
library(patchwork)

YEAR_LO <- 2003L  # firm_cost_share_outcome needs t-1 = 2002
YEAR_HI <- 2022L
REF_YEAR <- 2004L

# ---------------------------------------------------------------------------
# 1. Load B2B (selected sample) + pair age + firm_cost_share_outcome + NACE
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         c("seller", "buyer", "corr_sales"))
b2b[, year := as.integer(year)]
b2b <- b2b[!is.na(corr_sales) & corr_sales > 0 & year %between% c(YEAR_LO, YEAR_HI)]
cat(sprintf("B2B active rows in [%d, %d]: %d\n", YEAR_LO, YEAR_HI, nrow(b2b)))

load(file.path(PROC_DATA, "b2b_pair_age.RData"))     # pair_age
b2b <- merge(b2b, pair_age, by = c("seller", "buyer"), all.x = TRUE)
b2b[, pair_age_t   := year - first_year_pair]
b2b[, is_new_pair_t := as.integer(year == first_year_pair)]

# Annual accounts (selected sample) -- NACE 2d/4d for buyer and seller.
load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_more_selected_sample)[
  , .(vat = vat_ano, year, nace5d)]
rm(df_annual_accounts_more_selected_sample)
aa[, year   := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa[, nace2d := substr(nace4d, 1, 2)]
aa <- unique(aa[, .(vat, year, nace4d, nace2d)])

seller_nace <- copy(aa); setnames(seller_nace,
  c("vat", "year", "nace4d", "nace2d"),
  c("seller", "year", "seller_nace4d", "seller_nace2d"))
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)

buyer_nace <- copy(aa); setnames(buyer_nace,
  c("vat", "year", "nace4d", "nace2d"),
  c("buyer", "year", "buyer_nace4d", "buyer_nace2d"))
b2b <- merge(b2b, buyer_nace, by = c("buyer", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace2d) & !is.na(buyer_nace2d)]

# Regulated-intensive buyer + core-input pair filter (Phase 3 universe).
ri <- fread(file.path(REPO_DIR, "data", "io", "regulated_intensive_nace.csv"))
ri[, nace2d := sprintf("%02d", as.integer(nace2d))]
b2b <- b2b[buyer_nace2d %in% ri$nace2d]

core <- fread(file.path(REPO_DIR, "data", "io", "core_inputs_by_downstream.csv"))
core <- core[threshold == 0.10,
             .(buyer_nace2d  = sprintf("%02d", as.integer(downstream_nace2d)),
               seller_nace2d = sprintf("%02d", as.integer(upstream_cpa_nace2d)),
               is_core = TRUE)]
core <- unique(core)
b2b <- merge(b2b, core, by = c("buyer_nace2d", "seller_nace2d"), all.x = TRUE)
b2b <- b2b[!is.na(is_core)][, is_core := NULL]
cat(sprintf("After Phase 3 universe filter: %d rows\n", nrow(b2b)))

# Drop contaminated VATs from 2021+ (consistent with Plan A scripts).
contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)
b2b <- b2b[!(seller %in% contaminated_vats & year >= 2021L)]

# Attach firm_cost_share_outcome (per-year, lagged-denominator).
load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
b2b <- merge(b2b,
             cost_share_outcome[, .(seller = vat, year,
                                    fcs_outcome = firm_cost_share_outcome)],
             by = c("seller", "year"), all.x = TRUE)
# Non-ETS sellers have no fcs_outcome -- treat as 0 for the continuous outcome
# (their "intensity at match" is zero).
b2b[is.na(fcs_outcome), fcs_outcome := 0]

# Within-(seller_nace4d, year) rank of fcs_outcome, normalized to [0, 1].
# setkey before by-grouping for the data.table sorted path.
setkey(b2b, seller_nace4d, year)
b2b[, fcs_rank := frank(fcs_outcome, ties.method = "average"),
    by = .(seller_nace4d, year)]
b2b[, n_in_cell := .N, by = .(seller_nace4d, year)]
b2b[, fcs_rank_norm := ifelse(n_in_cell > 1L,
                              (fcs_rank - 1) / (n_in_cell - 1),
                              0.5)]

# ---------------------------------------------------------------------------
# 2. New-pair sample
# ---------------------------------------------------------------------------
new_pairs <- b2b[is_new_pair_t == 1L]
cat(sprintf("New-pair observations in Phase 3 universe (%d-%d): %d\n",
            YEAR_LO, YEAR_HI, nrow(new_pairs)))

# Period dummies. Reference = 2003-2004 (pre-shock).
new_pairs[, period := fcase(
  year %between% c(2003L, 2004L), "pre",
  year %between% c(2005L, 2016L), "p1",
  year %between% c(2017L, 2022L), "p2",
  default = NA_character_
)]
new_pairs[, p_p1 := as.integer(period == "p1")]
new_pairs[, p_p2 := as.integer(period == "p2")]

# ---------------------------------------------------------------------------
# 3. A1 (continuous) and A2 (rank) main regressions
# ---------------------------------------------------------------------------
extract_table <- function(model, label) {
  ct <- as.data.table(summary(model)$coeftable, keep.rownames = "term")
  setnames(ct, c("term", "estimate", "se", "tval", "pval"))
  ct <- ct[term %in% c("p_p1", "p_p2")]
  ct[, spec := label]
  ct[, n    := nobs(model)]
  ct[, .(spec, term, estimate, se, tval, pval, n)]
}

m_a1 <- feols(fcs_outcome ~ p_p1 + p_p2 | seller_nace4d,
              data = new_pairs, cluster = ~ seller_nace4d)
m_a2 <- feols(fcs_rank_norm ~ p_p1 + p_p2 | seller_nace4d,
              data = new_pairs, cluster = ~ seller_nace4d)

cat("\n--- A1 (continuous: fcs_outcome at match) ---\n")
print(summary(m_a1))
cat("\n--- A2 (rank within seller_nace4d x year) ---\n")
print(summary(m_a2))

main_out <- rbindlist(list(extract_table(m_a1, "A1_continuous"),
                           extract_table(m_a2, "A2_rank")))
fwrite(main_out, file.path(OUTPUT_TAB, "phase5_test_a_new_pair_tilt_main.csv"))

# ---------------------------------------------------------------------------
# 4. Robustness: weighted, drop left-censored, buyer NACE 2d x year FE
# ---------------------------------------------------------------------------
# R1: weight by initial pair sales (corr_sales at the year of formation).
m_a1_w <- feols(fcs_outcome ~ p_p1 + p_p2 | seller_nace4d,
                data = new_pairs, cluster = ~ seller_nace4d,
                weights = ~ corr_sales)
# R2: drop left-censored (first_year_pair == 2002).
m_a1_nlc <- feols(fcs_outcome ~ p_p1 + p_p2 | seller_nace4d,
                  data = new_pairs[is_left_censored == 0L],
                  cluster = ~ seller_nace4d)
# R3: add buyer_nace2d x year FE (test from buyer's perspective).
new_pairs[, bn2d_year := paste(buyer_nace2d, year, sep = "_")]
m_a1_bn <- feols(fcs_outcome ~ p_p1 + p_p2 | seller_nace4d + bn2d_year,
                 data = new_pairs, cluster = ~ seller_nace4d)

cat("\n--- A1 R1 weighted by corr_sales ---\n")
print(summary(m_a1_w))
cat("\n--- A1 R2 drop left-censored ---\n")
print(summary(m_a1_nlc))
cat("\n--- A1 R3 + buyer NACE2d x year FE ---\n")
print(summary(m_a1_bn))

robust_out <- rbindlist(list(
  extract_table(m_a1_w,   "A1_R1_weighted"),
  extract_table(m_a1_nlc, "A1_R2_drop_left_censored"),
  extract_table(m_a1_bn,  "A1_R3_bn2d_year_FE")
))
fwrite(robust_out, file.path(OUTPUT_TAB, "phase5_test_a_robustness.csv"))

# ---------------------------------------------------------------------------
# 5. Year-by-year event study
# ---------------------------------------------------------------------------
new_pairs[, year_f := factor(year)]
new_pairs[, year_f := relevel(year_f, ref = as.character(REF_YEAR))]

m_es <- feols(fcs_outcome ~ i(year_f, ref = as.character(REF_YEAR)) | seller_nace4d,
              data = new_pairs, cluster = ~ seller_nace4d)
es_dt <- as.data.table(summary(m_es)$coeftable, keep.rownames = "term")
setnames(es_dt, c("term", "estimate", "se", "tval", "pval"))
es_dt[, year := suppressWarnings(as.integer(gsub(".*::([0-9]+).*", "\\1", term)))]
es_dt <- es_dt[!is.na(year)]
es_dt[, ci_lo := estimate - 1.96 * se]
es_dt[, ci_hi := estimate + 1.96 * se]
es_dt <- rbind(es_dt[, .(year, estimate, se, ci_lo, ci_hi)],
               data.table(year = REF_YEAR, estimate = 0, se = 0,
                          ci_lo = 0, ci_hi = 0),
               fill = TRUE)
setorder(es_dt, year)
fwrite(es_dt, file.path(OUTPUT_TAB, "phase5_test_a_event_study.csv"))

p_es <- ggplot(es_dt, aes(x = year, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey40") +
  geom_vline(xintercept = 2004.5, linetype = "dotted", colour = "grey50") +
  geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi), size = 0.3, colour = "navy") +
  labs(title = "Test A: new-pair seller-intensity event study",
       subtitle = "Mean fcs_outcome at match year, vs 2004 reference. Seller_NACE4d FE; cluster on seller_NACE4d.",
       x = NULL, y = "Coefficient on year (relative to 2004)") +
  theme_minimal(base_size = 11)

ggsave(file.path(OUTPUT_FIG, "phase5_test_a_event_study.pdf"),
       p_es, width = 9, height = 4.5)
cat(sprintf("Saved: %s\n",
            file.path(OUTPUT_FIG, "phase5_test_a_event_study.pdf")))

# ---------------------------------------------------------------------------
# 6. Stock-vs-flow plot
# ---------------------------------------------------------------------------
stock <- b2b[, .(mean_fcs = mean(fcs_outcome, na.rm = TRUE),
                 sw_fcs   = sum(fcs_outcome * corr_sales, na.rm = TRUE) /
                            sum(corr_sales, na.rm = TRUE),
                 n        = .N),
             by = year][, sample := "Stock (all active pairs)"]
flow  <- new_pairs[, .(mean_fcs = mean(fcs_outcome, na.rm = TRUE),
                       sw_fcs   = sum(fcs_outcome * corr_sales, na.rm = TRUE) /
                                  sum(corr_sales, na.rm = TRUE),
                       n        = .N),
                   by = year][, sample := "Flow (newly formed pairs)"]
sf <- rbindlist(list(stock, flow), use.names = TRUE)
fwrite(sf, file.path(OUTPUT_TAB, "phase5_test_a_stock_vs_flow.csv"))

p_sf <- ggplot(sf, aes(x = year, y = mean_fcs, colour = sample)) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 1.2) +
  geom_vline(xintercept = 2004.5, linetype = "dotted", colour = "grey60") +
  geom_vline(xintercept = 2016.5, linetype = "dashed", colour = "grey40") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  labs(title = "Test A: stock-vs-flow seller carbon intensity",
       subtitle = "Mean firm_cost_share_outcome at the match year (flow) vs across all active pairs (stock).",
       x = NULL, y = "Mean firm_cost_share_outcome", colour = NULL) +
  theme_minimal(base_size = 11)

ggsave(file.path(OUTPUT_FIG, "phase5_test_a_stock_vs_flow.pdf"),
       p_sf, width = 9, height = 4.5)
cat(sprintf("Saved: %s\n",
            file.path(OUTPUT_FIG, "phase5_test_a_stock_vs_flow.pdf")))

cat("\nTest A complete.\n")
