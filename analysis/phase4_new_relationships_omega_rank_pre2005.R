###############################################################################
# phase4_new_relationships_omega_rank_pre2005.R
#
# PURPOSE
#   Extend the new-supplier omega-rank trajectory back to pre-2005 years.
#   Motivation: the headline plot starts in 2006 (because 2005 is left-
#   censored), so we have no genuinely "pre-Phase-II" baseline. If we can
#   show that the pre-2005 mean rank is similarly HIGH as the early 2005-07
#   values, the post-2013 drop looks like a real break rather than a
#   continuing trend.
#
#   We have B2B in 2002-2022 (see local-1 sample) but no firm_exposure
#   (emissions) data pre-2005. Strategy:
#
#     - "Stale-rank" approach: for new pairs in 2003 and 2004, score the
#       supplier using the supplier's 2005 within-NACE4d rank (Def 2,
#       emissions/cost). This treats the within-NACE4d ranking as
#       time-invariant for firms that survive into 2005.
#     - "First-available-rank" fallback: if a supplier is not in fe in
#       2005, walk forward to the first year they appear with non-NA
#       omega2, and use that rank. This is a less strict imputation.
#     - For new pairs in 2005+, use the year-t rank as in the headline
#       script (no change).
#
#   Censoring: with 2002 as the earliest B2B year, pairs first observed
#   in 2002 are left-censored. So the extended plot runs 2003-2022.
#
#   Two figures:
#     (A) Hybrid: 2005-baseline rank for 2003-2004; year-t rank for 2005+.
#         This is the natural extension.
#     (B) Fixed-2005: 2005-baseline rank for ALL years 2003-2022. Robustness
#         check — strips out within-firm omega evolution. If the post-2013
#         drop persists under fixed-rank, it is driven by buyers switching
#         to different suppliers (not by suppliers changing their own
#         emission intensity).
#
# OUTPUTS
#   - phase4_new_relationships_omega_rank_pre2005_hybrid.{png,pdf}
#   - phase4_new_relationships_omega_rank_pre2005_fixed.{png,pdf}
#   - phase4_new_relationships_omega_rank_pre2005.csv
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

set.seed(20260511)

# Extended window: B2B goes back to 2002 in the panel; 2002 is the
# censoring year, so the plot starts at 2003.
YEAR_LO_EXT <- 2002L
YEAR_LO     <- 2003L         # first year of "new pair" observations
YEAR_HI     <- 2022L
N_BOOT      <- 1000L
EVENT_YEARS <- c(2005L, 2017L)
BASELINE_YEAR <- 2005L

# ---------------------------------------------------------------------------
# 1. Load data (B2B extended to 2002)
# ---------------------------------------------------------------------------
cat("Loading data...\n")

load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(YEAR_LO_EXT, YEAR_HI) &
           !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year))]
cat(sprintf("  B2B rows: %d, year range %d-%d\n",
            nrow(b2b), min(b2b$year), max(b2b$year)))

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano),
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(
  vat = as.character(vat),
  year = as.integer(year),
  emissions, total_cost,
  nace4d = as.character(nace4d)
)]
rm(firm_exposure)
fe[, omega2 := ifelse(!is.na(emissions) & !is.na(total_cost) & total_cost > 0,
                      emissions / total_cost, NA_real_)]

ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]

# Attach supplier NACE4d to B2B
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
# For seller-years missing AA, try to back/forward-fill from neighbouring
# years (NACE4d is sticky for most firms). Keep most-frequent NACE4d per
# seller as a fallback.
seller_modal_nace <- aa[, .N, by = .(vat, nace4d)][
  order(vat, -N), .SD[1L], by = vat][, .(seller = vat, modal_nace4d = nace4d)]
b2b <- merge(b2b, seller_modal_nace, by = "seller", all.x = TRUE)
b2b[is.na(seller_nace4d), seller_nace4d := modal_nace4d]
b2b[, modal_nace4d := NULL]

# Keep only B2B rows where the seller's NACE4d is ETS-treated. This is the
# universe for new-relationship extraction.
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d %in% ets_treated_nace4d]

# ---------------------------------------------------------------------------
# 2. Identify new relationships (first observed in 2003 or later)
# ---------------------------------------------------------------------------
cat("\nIdentifying new relationships (B2B starts in", YEAR_LO_EXT, ")...\n")

first_year <- b2b[, .(year_first = min(year)), by = .(buyer, seller)]
new_rel <- first_year[year_first > YEAR_LO_EXT]    # drop 2002-censored
new_rel <- merge(new_rel,
                 b2b[, .(buyer, seller, year, seller_nace4d)],
                 by.x = c("buyer", "seller", "year_first"),
                 by.y = c("buyer", "seller", "year"))

cat(sprintf("  new relationships %d-%d: %d\n",
            YEAR_LO, YEAR_HI, nrow(new_rel)))
cat("  new relationships by year_first:\n")
print(new_rel[, .N, by = year_first][order(year_first)])

# ---------------------------------------------------------------------------
# 3. Build two rank panels
#    rank_yeart  : year-t within-NACE4d rank from year-t fe (2005-2022 only)
#    rank_2005   : 2005-baseline within-NACE4d rank for each supplier
#                  (with first-available-rank fallback for suppliers that
#                  don't appear in 2005 but appear later)
# ---------------------------------------------------------------------------
cat("\nBuilding rank panels...\n")

compute_rank_yearly <- function(dt, omega_col) {
  d <- dt[!is.na(get(omega_col)), .(vat, year, nace4d, omega = get(omega_col))]
  d[, rank := frank(omega, ties.method = "average") / .N,
    by = .(nace4d, year)]
  d[, .(seller = vat, year, seller_nace4d = nace4d, rank)]
}
rank_yeart <- compute_rank_yearly(fe, "omega2")
cat(sprintf("  year-t rank panel: %d rows (years %d-%d)\n",
            nrow(rank_yeart), min(rank_yeart$year), max(rank_yeart$year)))

# Per-supplier 2005-baseline rank, with first-available-rank fallback for
# suppliers missing in 2005.
rank_first_avail <- rank_yeart[, .SD[year == min(year)], by = seller][
  , .(seller, seller_nace4d, rank_first = rank, year_first_avail = year)]

rank_2005_only <- rank_yeart[year == BASELINE_YEAR,
                             .(seller, seller_nace4d, rank_2005 = rank)]
rank_baseline <- merge(rank_first_avail, rank_2005_only,
                       by = c("seller", "seller_nace4d"), all = TRUE)
# Prefer the 2005 rank where it exists; otherwise the first-available rank.
rank_baseline[, rank_baseline := fifelse(!is.na(rank_2005),
                                         rank_2005, rank_first)]
cat(sprintf("  baseline-rank panel: %d suppliers (of which %d have 2005 rank, %d use first-available fallback)\n",
            nrow(rank_baseline),
            sum(!is.na(rank_baseline$rank_2005)),
            sum(is.na(rank_baseline$rank_2005))))

# ---------------------------------------------------------------------------
# 4. Build the four observation tables
#    obs_hybrid : 2005 baseline for year_first in 2003-2004; year-t for 2005+
#    obs_fixed  : 2005 baseline for all year_first
# ---------------------------------------------------------------------------
attach_yeart <- function(d) {
  merge(d, rank_yeart,
        by.x = c("seller", "year_first", "seller_nace4d"),
        by.y = c("seller", "year",       "seller_nace4d"))[
        , .(buyer, seller, year_first, seller_nace4d, rank)]
}
attach_baseline <- function(d) {
  merge(d, rank_baseline[, .(seller, seller_nace4d, rank = rank_baseline)],
        by = c("seller", "seller_nace4d"))[
        , .(buyer, seller, year_first, seller_nace4d, rank)]
}

new_rel_pre  <- new_rel[year_first %between% c(YEAR_LO, BASELINE_YEAR - 1L)]
new_rel_post <- new_rel[year_first >= BASELINE_YEAR]

obs_hybrid <- rbind(
  attach_baseline(new_rel_pre),
  attach_yeart(new_rel_post)
)
obs_fixed <- attach_baseline(new_rel)

cat(sprintf("\n  hybrid obs: %d (pre %d, post %d)\n",
            nrow(obs_hybrid),
            sum(obs_hybrid$year_first <  BASELINE_YEAR),
            sum(obs_hybrid$year_first >= BASELINE_YEAR)))
cat(sprintf("  fixed  obs: %d\n", nrow(obs_fixed)))

# ---------------------------------------------------------------------------
# 5. Yearly mean rank + 95% bootstrap CI for each
# ---------------------------------------------------------------------------
boot_ci <- function(x, n_boot = N_BOOT, alpha = 0.05) {
  x <- x[!is.na(x)]
  if (length(x) < 5L) return(list(lo = NA_real_, hi = NA_real_))
  m <- length(x)
  draws <- replicate(n_boot, mean(x[sample.int(m, m, replace = TRUE)]))
  q <- quantile(draws, c(alpha / 2, 1 - alpha / 2), names = FALSE)
  list(lo = q[1], hi = q[2])
}

summarize_yearly <- function(d, label) {
  d[, {
    ci <- boot_ci(rank)
    .(mean_rank = mean(rank, na.rm = TRUE),
      n_obs    = .N,
      ci_lo    = ci$lo,
      ci_hi    = ci$hi)
  }, by = year_first][, version := label][]
}

yearly_hybrid <- summarize_yearly(obs_hybrid, "hybrid (2005-baseline for 2003-04, year-t after)")
yearly_fixed  <- summarize_yearly(obs_fixed,  "fixed (2005-baseline all years)")

yearly_combined <- rbindlist(list(yearly_hybrid, yearly_fixed))
setorder(yearly_combined, version, year_first)

fwrite(yearly_combined,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_pre2005.csv"))

cat("\nYearly summary (hybrid version):\n")
print(yearly_hybrid[, .(year_first, n_obs,
                        mean = round(mean_rank, 3),
                        ci_lo = round(ci_lo, 3),
                        ci_hi = round(ci_hi, 3))])
cat("\nYearly summary (fixed version):\n")
print(yearly_fixed[, .(year_first, n_obs,
                       mean = round(mean_rank, 3),
                       ci_lo = round(ci_lo, 3),
                       ci_hi = round(ci_hi, 3))])

# ---------------------------------------------------------------------------
# 6. Plots
# ---------------------------------------------------------------------------
base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

make_plot <- function(d, title, subtitle) {
  ggplot(d, aes(x = year_first, y = mean_rank)) +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi),
                alpha = 0.18, fill = "steelblue", color = NA) +
    geom_line(color = "steelblue", linewidth = 0.9) +
    geom_point(color = "steelblue", size = 1.4) +
    geom_hline(yintercept = 0.5, linetype = "dotted", color = "grey30") +
    geom_vline(xintercept = EVENT_YEARS - 0.5,
               linetype = "dashed", color = "firebrick") +
    geom_vline(xintercept = BASELINE_YEAR - 0.5,
               linetype = "dotted", color = "darkorange", linewidth = 0.7) +
    scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
    scale_y_continuous(limits = c(0, 1),
                       labels = scales::number_format(accuracy = 0.01)) +
    labs(title = title, subtitle = subtitle,
         x = NULL,
         y = "Mean omega percentile rank within NACE4d (ETS firms)") +
    base_theme
}

p_hybrid <- make_plot(
  yearly_hybrid,
  "New-supplier omega rank (Def 2: emissions/cost) -- pre-2005 extended (hybrid)",
  sprintf("Years 2003-04 use the supplier's %d within-NACE4d rank; 2005+ use year-t rank. Orange dotted = 2005 boundary; red dashed = event years; black dotted = 0.5 reference.", BASELINE_YEAR)
)
p_fixed <- make_plot(
  yearly_fixed,
  "New-supplier omega rank (Def 2: emissions/cost) -- fixed-2005-baseline (robustness)",
  sprintf("All years use the supplier's %d within-NACE4d rank (with first-available-rank fallback). Strips out within-firm omega evolution. Red dashed = event years; black dotted = 0.5 reference.", BASELINE_YEAR)
)

ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_pre2005_hybrid.png"),
       p_hybrid, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_pre2005_hybrid.pdf"),
       p_hybrid, width = 9, height = 5)

ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_pre2005_fixed.png"),
       p_fixed, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_pre2005_fixed.pdf"),
       p_fixed, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
