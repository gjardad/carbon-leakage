###############################################################################
# phase3_exposure_histograms.R
#
# PURPOSE:
#   Task 1. Four histograms of carbon cost intensity across ETS firm-years,
#   one per ETS phase (I, II, III, IV), on the MAIN denominator (total cost).
#   Appendix histograms with material-inputs-only and revenue denominators.
#
#   Two weight schemes per denominator:
#     - firm-year weight   : each ETS firm-year counts equally
#     - emissions weight   : firm-year weighted by its share of total emissions
#                            (so large emitters dominate, matching the policy
#                             relevance of the shock)
#
# INPUT:
#   data/processed/phase3_firm_exposure.RData
#
# OUTPUT:
#   output/figures/phase3_task1_hist_main_firmweight.pdf
#   output/figures/phase3_task1_hist_main_emweight.pdf
#   output/figures/phase3_task1_hist_matinputs_firmweight.pdf
#   output/figures/phase3_task1_hist_revenue_firmweight.pdf
#   output/tables/phase3_task1_hist_summary.csv
###############################################################################

rm(list = ls())

library(dplyr)
library(ggplot2)
library(tidyr)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load ----
load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))

phase_levels <- c("Phase I", "Phase II", "Phase III", "Phase IV")

# ===========================================================================
# Winsorize each cost-share variable within phase at the 1st and 99th
# percentile. Within-phase trimming keeps Phase I-II (mostly zeros) from
# collapsing Phase IV extremes -- the 99th percentile of Phase II is not
# the 99th percentile of Phase IV.
# ===========================================================================
winsorize_within_phase <- function(df, col) {
  df %>%
    group_by(phase) %>%
    mutate(
      "{col}" := {
        x <- .data[[col]]
        lo <- quantile(x, 0.01, na.rm = TRUE)
        hi <- quantile(x, 0.99, na.rm = TRUE)
        pmin(pmax(x, lo), hi)
      }
    ) %>%
    ungroup()
}

firm_exposure <- firm_exposure %>%
  winsorize_within_phase("cost_share_total") %>%
  winsorize_within_phase("cost_share_mat") %>%
  winsorize_within_phase("cost_share_rev")

cat("Winsorized cost_share_* at 1st/99th pct within phase.\n")

# ===========================================================================
# Helper: build a histogram-ready long data frame for one denominator
# ===========================================================================
prep <- function(df, share_col) {
  df %>%
    filter(!is.na(.data[[share_col]])) %>%
    mutate(share = .data[[share_col]],
           phase = factor(phase, levels = phase_levels)) %>%
    select(vat, year, phase, emissions, share)
}

# ===========================================================================
# Summary table across all denominators and phases
# ===========================================================================
summ <- function(df, share_col, denom_label) {
  df %>%
    filter(!is.na(.data[[share_col]])) %>%
    mutate(share = .data[[share_col]]) %>%
    group_by(phase) %>%
    summarise(
      denominator = denom_label,
      n_firm_years       = n(),
      pct_positive_share = 100 * mean(share > 0, na.rm = TRUE),
      mean_share         = mean(share, na.rm = TRUE),
      median_share       = median(share, na.rm = TRUE),
      p75_share          = quantile(share, 0.75, na.rm = TRUE),
      p90_share          = quantile(share, 0.90, na.rm = TRUE),
      p99_share          = quantile(share, 0.99, na.rm = TRUE),
      max_share          = max(share, na.rm = TRUE),
      # Emissions-weighted mean
      em_weighted_mean   = sum(share * emissions, na.rm = TRUE) /
                           sum(emissions, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    select(denominator, phase, everything())
}

summary_tbl <- bind_rows(
  summ(firm_exposure, "cost_share_total", "total_cost"),
  summ(firm_exposure, "cost_share_mat",   "mat_inputs"),
  summ(firm_exposure, "cost_share_rev",   "revenue")
) %>%
  arrange(denominator, phase)

cat("=== Summary table (all denominators, all phases) ===\n")
print(as.data.frame(summary_tbl))
write.csv(summary_tbl,
          file = file.path(OUTPUT_TAB, "phase3_task1_hist_summary.csv"),
          row.names = FALSE)

# ===========================================================================
# Histogram plotting
# ===========================================================================
#
# Plot strategy:
#   - x axis is share in %, on pseudo-log scale with a separate bar for zeros.
#   - To show zeros clearly, we bin shares into:
#       "0"          share == 0
#       "(0,.01%]"
#       "(.01,.1%]"
#       "(.1,1%]"
#       "(1,5%]"
#       "(5,10%]"
#       "(10,25%]"
#       ">25%"
#   - For each phase we compute the fraction of the weight (firm-years OR
#     emissions) in each bin.
# ===========================================================================

bin_share <- function(x) {
  bins <- cut(
    100 * x,  # convert to percent
    breaks = c(-Inf, 0,
               0.01, 0.1, 1, 5, 10, 25, Inf),
    labels = c("0",
               "(0, 0.01%]", "(0.01, 0.1%]",
               "(0.1, 1%]",  "(1, 5%]",
               "(5, 10%]",   "(10, 25%]", ">25%"),
    right = TRUE,
    include.lowest = TRUE
  )
  # Map numeric zero cleanly to the "0" bin
  bins[x == 0] <- "0"
  bins
}

make_hist <- function(df, share_col, weight_col, title_txt, subtitle_txt, out_file) {

  d <- df %>%
    filter(!is.na(.data[[share_col]])) %>%
    mutate(share = .data[[share_col]],
           bin   = bin_share(share),
           w     = if (weight_col == "firm_year") 1 else .data[[weight_col]],
           phase = factor(phase, levels = phase_levels))

  plotdat <- d %>%
    group_by(phase, bin) %>%
    summarise(w_sum = sum(w, na.rm = TRUE), .groups = "drop_last") %>%
    mutate(frac = w_sum / sum(w_sum)) %>%
    ungroup() %>%
    complete(phase, bin, fill = list(w_sum = 0, frac = 0))

  # Number of firm-years per phase for subtitle
  n_labels <- d %>%
    group_by(phase) %>%
    summarise(n = n(), .groups = "drop") %>%
    mutate(facet_lab = sprintf("%s (n = %d)", phase, n))

  plotdat <- plotdat %>%
    left_join(n_labels %>% select(phase, facet_lab), by = "phase") %>%
    mutate(facet_lab = factor(facet_lab, levels = n_labels$facet_lab))

  p <- ggplot(plotdat, aes(x = bin, y = 100 * frac)) +
    geom_col(fill = "#1f77b4", color = "white") +
    geom_text(aes(label = sprintf("%.0f%%", 100 * frac)),
              vjust = -0.35, size = 2.8) +
    facet_wrap(~ facet_lab, ncol = 2, scales = "free_y") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(
      title    = title_txt,
      subtitle = subtitle_txt,
      x        = "Carbon cost / denominator (log-style bins)",
      y        = "Share of weight in bin (%)"
    ) +
    theme_bw(base_size = 10) +
    theme(
      plot.title    = element_text(face = "bold"),
      axis.text.x   = element_text(angle = 30, hjust = 1),
      strip.text    = element_text(face = "bold")
    )

  ggsave(out_file, p, width = 10, height = 7)
  cat("Saved:", out_file, "\n")
}

# --- Main denominator: total_cost, firm-year weighted ---
make_hist(
  firm_exposure,
  share_col   = "cost_share_total",
  weight_col  = "firm_year",
  title_txt   = "Task 1: Carbon cost as share of total cost (inputs + wages), by ETS phase",
  subtitle_txt = "Each ETS firm-year weighted equally. Total cost = (revenue - value_added) + wage_bill.",
  out_file    = file.path(OUTPUT_FIG, "phase3_task1_hist_main_firmweight.pdf")
)

# --- Main denominator, emissions-weighted ---
make_hist(
  firm_exposure,
  share_col   = "cost_share_total",
  weight_col  = "emissions",
  title_txt   = "Task 1: Carbon cost as share of total cost, emissions-weighted",
  subtitle_txt = "Weight = firm emissions in that year. Big emitters dominate, matching policy relevance.",
  out_file    = file.path(OUTPUT_FIG, "phase3_task1_hist_main_emweight.pdf")
)

# --- Appendix: material inputs only ---
make_hist(
  firm_exposure,
  share_col   = "cost_share_mat",
  weight_col  = "firm_year",
  title_txt   = "Appendix: Carbon cost as share of material inputs, by phase",
  subtitle_txt = "Material inputs = revenue - value_added. Firm-year weights.",
  out_file    = file.path(OUTPUT_FIG, "phase3_task1_hist_matinputs_firmweight.pdf")
)

# --- Appendix: revenue denominator ---
make_hist(
  firm_exposure,
  share_col   = "cost_share_rev",
  weight_col  = "firm_year",
  title_txt   = "Appendix: Carbon cost as share of revenue, by phase",
  subtitle_txt = "Firm-year weights.",
  out_file    = file.path(OUTPUT_FIG, "phase3_task1_hist_revenue_firmweight.pdf")
)

cat("\nSummary table written to:",
    file.path(OUTPUT_TAB, "phase3_task1_hist_summary.csv"), "\n")
cat("Done.\n")
