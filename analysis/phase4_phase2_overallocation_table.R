###############################################################################
# phase4_phase2_overallocation_table.R
#
# PURPOSE
#   Produce a paper-ready table documenting the Phase II EU-ETS
#   overallocation anomaly that drives the small treat_2013 sample in
#   phase4_within_nace4d_reallocation_did.R.
#
#   For each pre-policy 2-year interval (Phase I 2006-07, Phase II 2011-12,
#   Phase III 2015-16), report:
#     - EUTL firms in the in-sample panel with shortage data in BOTH years.
#     - Firms with positive interval-averaged omega (= sum(shortage) /
#       sum(total_cost) > 0). This is exactly the firm-level filter that
#       the headline DiD requires for >=1 cell-supplier to identify "top-
#       omega".
#     - Share of firms with positive omega -- the bottleneck statistic.
#     - Median ratio of allocated_free / emissions across the interval
#       (>1 means typical firm received more allowances than it emitted,
#       i.e. surplus, so shortage = 0).
#     - Mean EUA spot price during the interval (context).
#
# OUTPUT (output_<machine>/tables/)
#   - phase4_phase2_overallocation_table.{csv,tex}
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(xtable)
})

INTERVALS <- list(
  list(label = "Phase I (2006-07)",       years = c(2006L, 2007L), event = 2008L),
  list(label = "Phase II (2011-12)",      years = c(2011L, 2012L), event = 2013L),
  list(label = "Phase III pre-MSR (2015-16)", years = c(2015L, 2016L), event = 2017L)
)

# ---------------------------------------------------------------------------
# 1. Load firm_exposure (already restricted to in_sample == 1 ETS firms)
# ---------------------------------------------------------------------------
load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)
rm(firm_exposure)

# ---------------------------------------------------------------------------
# 2. Per-interval firm-level summary
# ---------------------------------------------------------------------------
summarise_interval <- function(spec) {
  yrs <- spec$years

  d <- fe[year %in% yrs,
          .(vat, year, shortage, allocated_free, emissions,
            total_cost, eua_price)]

  # Firms with non-NA shortage AND non-NA total_cost > 0 in BOTH years
  d_clean <- d[!is.na(shortage) & !is.na(total_cost) & total_cost > 0]
  firms_both <- d_clean[, .N, by = vat][N == 2L, vat]
  d_clean <- d_clean[vat %in% firms_both]

  # Interval-averaged omega1 per firm
  o <- d_clean[, .(sum_short = sum(shortage),
                   sum_cost  = sum(total_cost),
                   sum_emis  = sum(emissions,       na.rm = TRUE),
                   sum_alloc = sum(allocated_free,  na.rm = TRUE)),
               by = vat]
  o[, omega := sum_short / sum_cost]
  o[, alloc_over_emis := ifelse(sum_emis > 0, sum_alloc / sum_emis, NA_real_)]

  data.table(
    interval                = spec$label,
    event_year              = spec$event,
    n_firms_both_years      = length(firms_both),
    n_firms_omega_pos       = sum(o$omega > 0),
    pct_omega_pos           = round(100 * mean(o$omega > 0), 1),
    median_alloc_over_emis  = round(median(o$alloc_over_emis, na.rm = TRUE), 2),
    pct_alloc_geq_emis      = round(100 * mean(o$alloc_over_emis >= 1,
                                               na.rm = TRUE), 1),
    mean_eua_price          = round(mean(d$eua_price, na.rm = TRUE), 1)
  )
}

tab <- rbindlist(lapply(INTERVALS, summarise_interval))
print(tab)

fwrite(tab,
       file.path(OUTPUT_TAB,
                 "phase4_phase2_overallocation_table.csv"))

# Paper-ready LaTeX
write_tex <- function(dt, file, caption) {
  x <- xtable(as.data.frame(dt), digits = c(0, 0, 0, 0, 0, 1, 2, 1, 1),
              caption = caption,
              label   = "tab:phase2-overallocation")
  print(x, file = file, include.rownames = FALSE, booktabs = TRUE,
        caption.placement = "top",
        sanitize.colnames.function = function(s) gsub("_", "\\\\_", s, fixed = TRUE),
        sanitize.text.function     = function(s) gsub("_", "\\\\_", s, fixed = TRUE))
}

write_tex(
  tab,
  file.path(OUTPUT_TAB, "phase4_phase2_overallocation_table.tex"),
  caption = paste0(
    "Phase II overallocation anomaly. ",
    "Among EUTL Belgian firms with full data in both pre-policy years, ",
    "Phase II (2011-12) is the only interval where the median firm received ",
    "more free allowances than it emitted, leaving only 14\\% of firms with ",
    "positive interval-averaged omega and binding the headline-DiD ",
    "sample at the treat\\_2013 event."
  )
)

cat("\nDone.\n")
cat("  Table : ", OUTPUT_TAB, "\n", sep = "")
