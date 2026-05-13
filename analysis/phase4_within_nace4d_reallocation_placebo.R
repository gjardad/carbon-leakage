###############################################################################
# phase4_within_nace4d_reallocation_placebo.R
#
# PURPOSE
#   Placebo test: do treated cells (>=1 supplier with omega > 0 during the
#   interval) reallocate within-NACE4d expenditure differently from cells
#   with no ETS exposure of any kind (no supplier in EUTL during the interval)?
#
#   For each multi-supplier (buyer, NACE4d) cell and each year t, define a
#   reallocation magnitude relative to the LAST year of the interval:
#
#     R_jt = 1 - sum_i min(s_ij,t, s_ij,base_year)
#
#   where s_ij,t is supplier i's share of buyer j's NACE4d spend in year t,
#   and base_year is the last year of the interval (2007 / 2012 / 2016).
#   This is the total-variation distance (= L1/2) between the year-t share
#   vector and the base-year share vector. R is bounded in [0, 1]:
#     0 = identical to base; 1 = no overlap with base.
#
#   By construction R_{j, base_year} = 0 (cell-level), so the cross-cell
#   mean is anchored at 0 in the norm year.
#
# CELL UNIVERSE
#   Two variants are produced:
#     anyNACE4d  -- all (buyer, supplier-NACE4d) multi-supplier cells.
#     etsNACE4d  -- only cells where supplier-NACE4d contains >=1 ETS firm.
#
# GROUPS (per cell, per interval)
#   treated -- >=1 supplier in the interval has omega > 0.
#   placebo -- 0 suppliers in the interval are in the EUTL panel (no ETS
#              exposure of any kind).
#   (Cells with EUTL suppliers but no positive omega are saved in the
#    underlying CSV but excluded from the placebo plot.)
#
# OUTPUTS (output_local/figures/, output_local/tables/)
#   - phase4_within_nace4d_reallocation_placebo_anyNACE4d.{png,pdf}
#   - phase4_within_nace4d_reallocation_placebo_etsNACE4d.{png,pdf}
#   - phase4_within_nace4d_reallocation_placebo_cells.csv
#         cell-interval-level: group, supplier counts, NACE4d-treated flag.
#   - phase4_within_nace4d_reallocation_placebo_yearly.csv
#         cell-interval-year-level: R_jt + group + flags.
#   - phase4_within_nace4d_reallocation_placebo_pooled.csv
#         year-version-group-universe means with bootstrap CIs.
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

set.seed(20260508)

YEAR_LO <- 2005L
YEAR_HI <- 2022L
N_BOOT  <- 1000L

INTERVALS <- list(
  "treat_2005" = list(years = c(2005L),         base_year = 2005L, treat_year = 2006L),
  "treat_2017" = list(years = c(2015L, 2016L),  base_year = 2016L, treat_year = 2017L)
)

# ---------------------------------------------------------------------------
# 1. Load data
# ---------------------------------------------------------------------------
cat("Loading b2b, AA, EUTL, firm_exposure...\n")

load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year),
             sales)]

# AA -> seller NACE4d
load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano),
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

# Firm exposure (for omega per firm-year and the ETS-treated NACE4d set)
load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(vat, year, shortage, total_cost, nace4d)]
rm(firm_exposure)

ets_vats_all       <- unique(fe$vat)
ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]
cat(sprintf("  EUTL/in_sample firms: %d, ETS-treated NACE4d: %d\n",
            length(ets_vats_all), length(ets_treated_nace4d)))

# Attach seller NACE4d to b2b
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]

# ---------------------------------------------------------------------------
# 2. Per (buyer, seller_nace4d, seller, year) supplier share within NACE4d
# ---------------------------------------------------------------------------
b2b[, total_buyer_nace4d_spend := sum(sales),
    by = .(buyer, seller_nace4d, year)]
b2b[, share := sales / total_buyer_nace4d_spend]

# A compact share-only view (one row per supplier-cell-year)
shares <- b2b[, .(buyer, seller_nace4d, seller, year, share)]

# ---------------------------------------------------------------------------
# 3. Per-interval firm-omega panel
# ---------------------------------------------------------------------------
build_firm_omega <- function(yrs) {
  d <- fe[year %in% yrs & !is.na(shortage) & !is.na(total_cost) & total_cost > 0,
          .(vat, year, shortage, total_cost)]
  o <- d[, .(n_yrs = .N,
             sum_short = sum(shortage),
             sum_cost  = sum(total_cost)),
         by = vat]
  o <- o[n_yrs == 2L & sum_cost > 0]
  o[, omega := sum_short / sum_cost]
  o[, .(vat, omega)]
}

firm_omega <- lapply(INTERVALS, function(s) build_firm_omega(s$years))

# ---------------------------------------------------------------------------
# 4. Cell-interval table: tag each cell with treatment status
# ---------------------------------------------------------------------------
cat("\nBuilding cell-interval treatment status...\n")

cell_status_list <- list()
for (label in names(INTERVALS)) {
  yrs <- INTERVALS[[label]]$years

  pre <- b2b[year %in% yrs,
             .(int_sales = sum(sales)),
             by = .(buyer, seller_nace4d, seller)]
  pre <- pre[int_sales > 0]

  # Multi-supplier filter
  cn <- pre[, .(n_supp = uniqueN(seller)), by = .(buyer, seller_nace4d)]
  multi <- cn[n_supp >= 2L]

  pre <- merge(pre, multi[, .(buyer, seller_nace4d)],
               by = c("buyer", "seller_nace4d"))

  pre[, is_eutl := as.integer(seller %in% ets_vats_all)]
  pre <- merge(pre, firm_omega[[label]],
               by.x = "seller", by.y = "vat", all.x = TRUE)
  pre[is.na(omega), omega := 0]

  cs <- pre[, .(
    n_supp           = uniqueN(seller),
    n_eutl_supp      = sum(is_eutl),
    n_omega_pos_supp = sum(omega > 0)
  ), by = .(buyer, seller_nace4d)]

  cs[, group := fcase(
    n_omega_pos_supp >= 1L, "Treated (>=1 omega>0 supplier)",
    n_eutl_supp     == 0L,  "Placebo (no EUTL supplier)",
    default                 = "Middle (EUTL but omega=0)"
  )]

  cs[, version          := label]
  cs[, base_year        := INTERVALS[[label]]$base_year]
  cs[, treat_year       := INTERVALS[[label]]$treat_year]
  cs[, nace4d_ets_treated := as.integer(seller_nace4d %in% ets_treated_nace4d)]

  cell_status_list[[label]] <- cs
}
cell_status <- rbindlist(cell_status_list, use.names = TRUE)

cat("\nCell counts by version, NACE4d-ETS-status, and group:\n")
print(cell_status[, .N, by = .(version, nace4d_ets_treated, group)][order(version, nace4d_ets_treated, group)])

fwrite(cell_status,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_reallocation_placebo_cells.csv"))

# ---------------------------------------------------------------------------
# 5. R_jt computation per (cell, version, year)
# ---------------------------------------------------------------------------
cat("\nComputing R_jt for each (cell, version, year)...\n")

compute_R_for_version <- function(label) {
  spec <- INTERVALS[[label]]
  base_yr <- spec$base_year

  cells_v <- cell_status[version == label,
                         .(buyer, seller_nace4d, group, nace4d_ets_treated)]

  # Base share vector at base_year (raw shares, no group columns yet).
  base <- shares[year == base_yr,
                 .(buyer, seller_nace4d, seller, base_share = share)]

  # Cells lacking activity at base_year (rare; report only).
  cells_with_base <- unique(base[, .(buyer, seller_nace4d)])
  cells_no_base   <- cells_v[!cells_with_base, on = c("buyer", "seller_nace4d")]
  if (nrow(cells_no_base) > 0L) {
    cat(sprintf("  %s: %d / %d cells have no base-year activity (drop from R).\n",
                label, nrow(cells_no_base), nrow(cells_v)))
  }

  # For each year t, build the joined supplier-share table and compute R
  out <- vector("list", length(YEAR_LO:YEAR_HI))
  i <- 1L
  for (t in YEAR_LO:YEAR_HI) {
    yt <- shares[year == t,
                 .(buyer, seller_nace4d, seller, share_t = share)]
    j <- merge(yt, base,
               by = c("buyer", "seller_nace4d", "seller"),
               all = TRUE)
    # Restrict to cells in cells_v (drops irrelevant joins)
    j <- merge(j, cells_v, by = c("buyer", "seller_nace4d"))
    j[is.na(share_t),    share_t    := 0]
    j[is.na(base_share), base_share := 0]

    R_t <- j[, .(
      R = 1 - sum(pmin(share_t, base_share)),
      sum_t    = sum(share_t),
      sum_base = sum(base_share)
    ), by = .(buyer, seller_nace4d, group, nace4d_ets_treated)]

    # If buyer had no NACE4d spend in year t (sum_t == 0) AND no base
    # activity (sum_base == 0), drop the cell-year (NA). We could also keep
    # those rows if base existed but t didn't (treats a buyer leaving the
    # NACE4d as full reallocation = R = 1); for now we drop them.
    R_t <- R_t[sum_t > 0]

    R_t[, year    := t]
    R_t[, version := label]
    R_t[, base_year   := base_yr]
    R_t[, treat_year  := spec$treat_year]
    out[[i]] <- R_t
    i <- i + 1L
  }
  rbindlist(out, use.names = TRUE)
}

R_long <- rbindlist(lapply(names(INTERVALS), compute_R_for_version),
                    use.names = TRUE)
cat(sprintf("  R_long rows: %d\n", nrow(R_long)))

fwrite(R_long,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_reallocation_placebo_yearly.csv"))

# ---------------------------------------------------------------------------
# 6. Pooled means with bootstrap CIs, two universes
# ---------------------------------------------------------------------------
boot_ci <- function(x, stat = mean, n_boot = N_BOOT, alpha = 0.05) {
  x <- x[!is.na(x)]
  if (length(x) < 5L) return(list(lo = NA_real_, hi = NA_real_))
  m <- length(x)
  draws <- replicate(n_boot, stat(x[sample.int(m, m, replace = TRUE)]))
  q <- quantile(draws, c(alpha / 2, 1 - alpha / 2), names = FALSE)
  list(lo = q[1], hi = q[2])
}

aggregate_universe <- function(R_dt, universe_label) {
  if (universe_label == "anyNACE4d") {
    d <- R_dt
  } else if (universe_label == "etsNACE4d") {
    d <- R_dt[nace4d_ets_treated == 1L]
  } else stop("unknown universe")

  d <- d[group %in% c("Treated (>=1 omega>0 supplier)",
                      "Placebo (no EUTL supplier)")]

  d[, {
    ci <- boot_ci(R, stat = mean)
    .(mean_R   = mean(R),
      n_cells = .N,
      ci_lo   = ci$lo,
      ci_hi   = ci$hi)
  },
  by = .(version, treat_year, base_year, year, group)][, universe := universe_label][]
}

pooled_any <- aggregate_universe(R_long, "anyNACE4d")
pooled_ets <- aggregate_universe(R_long, "etsNACE4d")
pooled_all <- rbind(pooled_any, pooled_ets)
setorder(pooled_all, universe, version, group, year)

fwrite(pooled_all,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_reallocation_placebo_pooled.csv"))

cat("\nPooled cell counts (year = base_year, where R should be ~0):\n")
print(pooled_all[year == base_year,
                 .(universe, version, group, n_cells, mean_R = round(mean_R, 4))])

# ---------------------------------------------------------------------------
# 7. Plots
# ---------------------------------------------------------------------------
version_labels <- c(
  "treat_2008" = "Treatment 2008 (base = 2007)",
  "treat_2013" = "Treatment 2013 (base = 2012)",
  "treat_2017" = "Treatment 2017 (base = 2016)"
)

base_theme <- theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"),
        panel.grid.minor = element_blank(),
        legend.position = "bottom")

treat_lines <- data.table(
  version_lab = factor(version_labels, levels = version_labels),
  treat_year  = sapply(INTERVALS, `[[`, "treat_year"),
  base_year   = sapply(INTERVALS, `[[`, "base_year")
)

make_plot <- function(d, title_suffix) {
  d2 <- copy(d)
  d2[, version_lab := factor(version,
                             levels = names(version_labels),
                             labels = version_labels)]
  d2[, group := factor(group,
                       levels = c("Treated (>=1 omega>0 supplier)",
                                  "Placebo (no EUTL supplier)"))]

  ggplot(d2, aes(x = year, y = mean_R, color = group, fill = group)) +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.18, color = NA) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 1.1) +
    geom_hline(yintercept = 0, linetype = "dotted", color = "grey30") +
    geom_vline(data = treat_lines,
               aes(xintercept = base_year + 0.5),
               linetype = "dashed", color = "grey30",
               inherit.aes = FALSE) +
    geom_vline(data = treat_lines,
               aes(xintercept = treat_year - 0.5),
               linetype = "dashed", color = "firebrick",
               inherit.aes = FALSE) +
    facet_wrap(~ version_lab, ncol = 1, scales = "free_y") +
    scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
    scale_y_continuous(limits = c(0, NA)) +
    scale_color_manual(values = c("Treated (>=1 omega>0 supplier)" = "firebrick",
                                  "Placebo (no EUTL supplier)"    = "navy"),
                       name = NULL) +
    scale_fill_manual(values = c("Treated (>=1 omega>0 supplier)" = "firebrick",
                                 "Placebo (no EUTL supplier)"    = "navy"),
                      name = NULL) +
    labs(title = sprintf("Within-NACE4d reallocation magnitude (R_jt) -- %s",
                         title_suffix),
         subtitle = "R_jt = total variation distance between year-t supplier shares and base-year (last interval year) shares.\nMean across cells; 95% bootstrap CI; red dashed = treatment year. R = 0 at base year by construction.",
         x = NULL,
         y = "Total variation distance from base-year share vector") +
    base_theme
}

p_any <- make_plot(pooled_any, "any NACE4d")
p_ets <- make_plot(pooled_ets, "ETS-treated NACE4d only")

ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_placebo_anyNACE4d.png"),
       p_any, width = 9, height = 10, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_placebo_anyNACE4d.pdf"),
       p_any, width = 9, height = 10)

ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_placebo_etsNACE4d.png"),
       p_ets, width = 9, height = 10, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_reallocation_placebo_etsNACE4d.pdf"),
       p_ets, width = 9, height = 10)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
