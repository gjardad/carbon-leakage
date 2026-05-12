# phase2_cdgm_figure2.R
#
# Replicates CdGM Figure 2 ("Aggregate import shares and probability of
# sourcing from a new supplier market: control vs. treatment groups"),
# extended with a third line for regulated products from ETS countries.
#
# Two panels:
#   (a) Aggregate import SHARE by year, three groups.
#   (b) Aggregate PROBABILITY of sourcing by year (extensive margin), three
#       groups.
#
# Three groups:
#   Control (unregulated x non-ETS):  regulated_product == 0 AND non_ets_country == 1
#   Treated (regulated x non-ETS):    regulated_product == 1 AND non_ets_country == 1
#   Regulated x ETS country (added):  regulated_product == 1 AND non_ets_country == 0
#
# Denominator for panel (a): total Belgian imports across ALL cells per year
# (i.e. across both ETS and non-ETS source countries, both regulated and
# unregulated products). This is the only choice that makes the three lines
# directly comparable on the same axis. The two non-ETS lines no longer sum
# to 1 (they sum to the share of non-ETS imports in total), but their TRENDS
# are unchanged versus the original CdGM specification.
#
# Inputs:
#   * RMD: ${PROC_NBB}/customs_import_panel_regulated.dta
#   * local 1: NBB_data/processed/mock_customs_import_panel_regulated.RData
#     (toggle via USE_MOCK).
#
# Outputs:
#   * output_${MACHINE_TAG}/figures/phase2_cdgm_figure2.png  (replication of CdGM Fig 2 + ETS line)
#   * output_${MACHINE_TAG}/tables/phase2_cdgm_figure2.csv   (annual aggregates per group)
#
# Note on output directory: per paths.R guideline, local-1 runs write to
# output_local/, RMD runs write to output_rmd/. The legacy output/ folder
# is preserved for historical phase 0-4 artifacts and is NOT touched.

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2", repos = "https://cloud.r-project.org")
if (!requireNamespace("patchwork", quietly = TRUE)) install.packages("patchwork", repos = "https://cloud.r-project.org")

library(data.table)
library(ggplot2)
library(patchwork)

# Toggle: TRUE on local 1 to test against the mock panel; FALSE on RMD.
USE_MOCK <- !file.exists(file.path(PROC_DATA, "customs_import_panel_regulated.dta"))

if (USE_MOCK) {
  cat("USING MOCK CUSTOMS PANEL (local 1).\n")
  load(file.path(PROC_DATA, "mock_customs_import_panel_regulated.RData"))
  d <- as.data.table(panel)
} else {
  cat("USING REAL CUSTOMS PANEL (RMD).\n")
  if (!requireNamespace("haven", quietly = TRUE)) install.packages("haven", repos = "https://cloud.r-project.org")
  d <- as.data.table(haven::read_dta(file.path(PROC_DATA, "customs_import_panel_regulated.dta")))
}

cat("Panel rows:", nrow(d),
    "  (firm x cn8 x partner x year cells, including zeros)\n")

# Three-group classification on the FULL panel (no upfront non-ETS restriction).
# Cells with unregulated x ETS-country are dropped (not in any of the three
# groups), but they still contribute to the total-imports denominator for
# panel (a).
d[, group := fcase(
  is_regulated_product == 0L & is_non_ets_country == 1L,
    "Control (unregulated x non-ETS)",
  is_regulated_product == 1L & is_non_ets_country == 1L,
    "Treated (regulated x non-ETS)",
  is_regulated_product == 1L & is_non_ets_country == 0L,
    "Regulated x ETS country",
  default = NA_character_
)]
d[, group := factor(group,
                    levels = c("Control (unregulated x non-ETS)",
                               "Treated (regulated x non-ETS)",
                               "Regulated x ETS country"))]

cat("\nRows per group:\n"); print(d[, .N, by = group])

# -------------------------------------------------------------------------
# Diagnostic: time-frame coverage by group.
# We expect all three groups to span 2000-2019 (the panel build window).
# A group that only starts at 2005 on RMD would indicate a data-build bug;
# on local-1 the downsampled panel is known to have no regulated x ETS
# rows before 2005, which is a downsample artifact.
# -------------------------------------------------------------------------
year_cov <- d[!is.na(group) & value > 0,
              .(year_min  = min(year),
                year_max  = max(year),
                n_years   = uniqueN(year),
                n_cells   = .N),
              by = group]
cat("\nTime-frame coverage by group (cells with value > 0):\n")
print(year_cov)
expected_min <- min(d$year, na.rm = TRUE)
expected_max <- max(d$year, na.rm = TRUE)
cat(sprintf("\nPanel year span overall: %d - %d\n",
            expected_min, expected_max))
truncated <- year_cov[year_min > expected_min | year_max < expected_max]
if (nrow(truncated) > 0) {
  cat("WARNING: the following groups do NOT span the full panel window:\n")
  print(truncated)
  cat("On RMD with the full customs panel, all three groups should span",
      sprintf("%d-%d.", expected_min, expected_max),
      "If this warning fires on RMD, check the customs panel build for a",
      "filter that drops early-year ETS-source rows.\n")
} else {
  cat("All three groups span the full panel window.\n")
}

# -------------------------------------------------------------------------
# Panel (a): aggregate import share.
# Denominator = total Belgian imports across ALL cells per year (regulated
# and unregulated, ETS and non-ETS source). This is the only choice that
# puts the three lines on the same axis. With the old non-ETS-only
# denominator, the two non-ETS lines summed to 1; here they sum to the
# share of non-ETS in total imports (typically much less than 1, since
# ~98% of Belgian trade is intra-EU).
# -------------------------------------------------------------------------
total_imports <- d[, .(total = sum(value)), by = year]
share_dt <- d[!is.na(group), .(value = sum(value)), by = .(year, group)]
share_dt <- merge(share_dt, total_imports, by = "year")
share_dt[, share := value / total]

# -------------------------------------------------------------------------
# Panel-completeness guard.
# Partial-year data at the start or end of the panel produces dramatic
# downward spikes in the share series. Detect any year whose aggregate
# import value is below 50% of the median annual aggregate, warn, and drop
# from both panels. On RMD with the full 2000-2019 panel the final year
# can come in incomplete (NBB administrative cutoff); on local-1 it shows
# up as a zero in 2019.
# -------------------------------------------------------------------------
annual_total <- d[!is.na(group), .(annual_value = sum(value)), by = year]
setorder(annual_total, year)
median_total <- median(annual_total$annual_value)
incomplete_years <- annual_total[annual_value < 0.5 * median_total, year]
if (length(incomplete_years) > 0) {
  cat(sprintf("\nWARNING: dropping %d year(s) with incomplete aggregates",
              length(incomplete_years)),
      "(< 50% of the median annual import value across groups):\n")
  print(annual_total[year %in% incomplete_years])
  cat("If this warning fires on RMD, verify the customs-panel build window",
      "matches the NBB administrative cutoff.\n\n")
  share_dt <- share_dt[!year %in% incomplete_years]
  prob_dt_filter_years <- incomplete_years   # used below for panel (b) too
} else {
  prob_dt_filter_years <- integer(0)
}

cat("\nAggregate share by group/year (denominator = total Belgian imports):\n")
print(dcast(share_dt, year ~ group, value.var = "share"))

p_a <- ggplot(share_dt, aes(x = year, y = share, color = group)) +
  geom_vline(xintercept = 2004.5, linetype = "dashed", color = "grey40") +
  geom_line(linewidth = 0.9) + geom_point(size = 1.6) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = c("grey40", "steelblue", "firebrick")) +
  annotate("text", x = 2002, y = max(share_dt$share, na.rm = TRUE),
           label = "Pre-ETS", size = 3, color = "grey40") +
  annotate("text", x = 2012, y = max(share_dt$share, na.rm = TRUE),
           label = "Post-2005 (ETS)", size = 3, color = "grey40") +
  labs(title = "(a) Aggregate import share, all source countries",
       x = NULL, y = "Share of total Belgian imports", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

# -------------------------------------------------------------------------
# Panel (b): aggregate probability of sourcing (extensive margin).
# Per CdGM p. 12: "probability of sourcing from a given supplier (i.e., the
# extensive margin)". For each (year, group): fraction of (firm x cn8 x partner)
# triplets IN THAT GROUP'S balanced panel that have value > 0. Each group has
# its own denominator (count of triplets in that group), so no rescaling
# issue arises when adding the third line.
# -------------------------------------------------------------------------
prob_dt <- d[!is.na(group), .(active = mean(value > 0)),
             by = .(year, group)]
if (length(prob_dt_filter_years) > 0) {
  prob_dt <- prob_dt[!year %in% prob_dt_filter_years]
}

cat("\nProbability of sourcing by group/year:\n")
print(dcast(prob_dt, year ~ group, value.var = "active"))

p_b <- ggplot(prob_dt, aes(x = year, y = active, color = group)) +
  geom_vline(xintercept = 2004.5, linetype = "dashed", color = "grey40") +
  geom_line(linewidth = 0.9) + geom_point(size = 1.6) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  scale_color_manual(values = c("grey40", "steelblue", "firebrick")) +
  labs(title = "(b) Probability of sourcing (extensive margin)",
       x = NULL, y = "P(value > 0 | triplet, year)", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

# -------------------------------------------------------------------------
# Combine panels and save.
# -------------------------------------------------------------------------
p_combined <- (p_a / p_b) +
  plot_annotation(
    title = "CdGM Figure 2 replication: Aggregate import shares and probability of sourcing",
    subtitle = sprintf("Belgium customs panel%s, 2000-2019",
                       ifelse(USE_MOCK, " (MOCK DATA)", "")),
    caption = paste("Control: unregulated x non-ETS source country.",
                    "Treated: regulated x non-ETS.",
                    "Added line: regulated x ETS source country.",
                    "Panel (a) denominator: total Belgian imports.",
                    sep = " ")
  ) &
  theme(plot.title = element_text(size = 12),
        legend.position = "bottom")

fig_dir <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
tab_dir <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

out_fig <- file.path(fig_dir,
                     ifelse(USE_MOCK, "phase2_cdgm_figure2_MOCK.png",
                                       "phase2_cdgm_figure2.png"))
ggsave(out_fig, p_combined, width = 9, height = 8, dpi = 200)
cat("\nFigure saved:", out_fig, "\n")

# Save raw aggregates
out_tab <- file.path(tab_dir,
                     ifelse(USE_MOCK, "phase2_cdgm_figure2_MOCK.csv",
                                       "phase2_cdgm_figure2.csv"))
agg <- merge(share_dt[, .(year, group, share)],
             prob_dt[, .(year, group, prob_active = active)],
             by = c("year", "group"))
fwrite(agg, out_tab)
cat("Table saved:", out_tab, "\n")
