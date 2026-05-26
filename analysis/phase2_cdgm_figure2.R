# phase2_cdgm_figure2.R
#
# Replicates CdGM Figure 2 ("Aggregate import shares and probability of
# sourcing from a new supplier market: control vs. treatment groups"),
# extended with the full 2x2 product-x-country classification (four lines
# per panel) and a robustness version with China removed from the non-ETS
# pool to check whether China dominates the non-ETS lines.
#
# Two panels per figure:
#   (a) Aggregate import SHARE by year, four groups.
#   (b) Aggregate PROBABILITY of sourcing by year (extensive margin), four
#       groups.
#
# Four groups, classified by the time-invariant `is_ets_country_ever` flag
# from country_ets_status.csv (joined on partner_iso2 × year). This avoids
# the artificial 2005 jump that arose when EU-15 imports flipped from
# is_non_ets_country = 1 (pre-2005, ETS didn't yet exist) to 0 (post-2005,
# ETS member). With the new flag, EU-15 and EU-10 countries are classified
# as "ETS country" for all years 2000-2022, even pre-policy; late joiners
# (EU-2 from 2007, EU-1 from 2013, EEA-EFTA from 2008) remain time-varying
# at their accession year. The Table 1 regression in phase2_cdgm_table1.R
# still uses the time-varying is_non_ets_country and is unaffected.
#
#   Unregulated x non-ETS:  is_regulated_product == 0 AND is_ets_country_ever == FALSE
#   Regulated x non-ETS:    is_regulated_product == 1 AND is_ets_country_ever == FALSE
#   Regulated x ETS:        is_regulated_product == 1 AND is_ets_country_ever == TRUE
#   Unregulated x ETS:      is_regulated_product == 0 AND is_ets_country_ever == TRUE
#
# Denominator for panel (a): within-regulation-status total. The two
# "Regulated" lines (Red + Blue) sum to 1; the two "Unregulated" lines
# (Orange + Grey) sum to 1. This matches CdGM's interpretation of Figure 2
# ("share of regulated products from non-ETS rose 4.3 pp") and gives the
# cleanest visual reading of the leakage hypothesis:
#   - if leakage: Blue (reg × non-ETS share within regulated) rises and
#     Red (reg × ETS share within regulated) falls — they're mirror images.
#   - if globalization rather than ETS-specific leakage: the Unregulated
#     pair (Orange/Grey) diverges the same way as the Regulated pair, so
#     the difference between the pairs (the DID signal) is null.
#
# Two output figures per run:
#   * phase2_cdgm_figure2.png            — full sample.
#   * phase2_cdgm_figure2_excl_china.png — China (CN, HK) excluded from the
#                                          non-ETS pool. Tests whether China
#                                          drives the non-ETS lines.
#
# Inputs (in preference order):
#   * customs_import_panel_extended.RData  (2000-2022, preferred on RMD)
#   * customs_import_panel_regulated.dta   (2000-2019, CdGM-window, RMD/local)
#   * customs_import_panel_regulated.RData (2000-2019, local-1)
#   * mock_customs_import_panel_regulated.RData (development fallback)
#
# The extended panel adds the 2020-2022 Phase IV / EUA-spike window, which
# is critical for any leakage signal that's price-driven. The regulated panel
# stops at 2019 (CdGM-window) and is kept as a fallback.
#
# Outputs (per paths.R: output_local/ on local-1, output_rmd/ on RMD):
#   * figures/phase2_cdgm_figure2.png
#   * figures/phase2_cdgm_figure2_excl_china.png
#   * tables/phase2_cdgm_figure2.csv
#   * tables/phase2_cdgm_figure2_excl_china.csv

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("ggplot2",   quietly = TRUE)) install.packages("ggplot2",   repos = "https://cloud.r-project.org")
if (!requireNamespace("patchwork", quietly = TRUE)) install.packages("patchwork", repos = "https://cloud.r-project.org")

library(data.table)
library(ggplot2)
library(patchwork)

# Load panel: prefer the 2000-2022 extended panel; fall back to the
# 2000-2019 regulated panel; fall back to mock. USE_MOCK is set TRUE only
# when no real panel is found.
ext_rdata <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
reg_dta   <- file.path(PROC_DATA, "customs_import_panel_regulated.dta")
reg_rdata <- file.path(PROC_DATA, "customs_import_panel_regulated.RData")
mock_path <- file.path(PROC_DATA, "mock_customs_import_panel_regulated.RData")

USE_MOCK <- FALSE
if (file.exists(ext_rdata)) {
  cat("USING EXTENDED CUSTOMS PANEL (2000-2022).\n")
  load(ext_rdata)
  d <- as.data.table(panel)
} else if (file.exists(reg_dta)) {
  cat("WARNING: extended panel not found; using CdGM-window panel (2000-2019).\n")
  if (!requireNamespace("haven", quietly = TRUE)) install.packages("haven", repos = "https://cloud.r-project.org")
  d <- as.data.table(haven::read_dta(reg_dta))
} else if (file.exists(reg_rdata)) {
  cat("WARNING: extended panel not found; using CdGM-window panel (2000-2019, RData).\n")
  load(reg_rdata)
  d <- as.data.table(panel)
} else {
  cat("USING MOCK CUSTOMS PANEL (local 1, no real panel found).\n")
  USE_MOCK <- TRUE
  load(mock_path)
  d <- as.data.table(panel)
}

cat("Panel rows:", nrow(d),
    "  (firm x cn8 x partner x year cells, including zeros)\n")

# Drop Switzerland everywhere. Swiss-recorded import value is a commodity-
# trading-hub invoicing artifact (value ~25x over 2015-2022 with flat tonnage;
# unit value EUR 21 -> 1331/kg), i.e. country of consignment, not origin. It
# mechanically inflates the extra-EU import share. See
# phase6_cdgm_intrastat_break_diagnostic.R and the paper footnote.
d <- d[partner_iso2 != "CH"]
cat("Dropped Switzerland (CH). Rows now:", nrow(d), "\n")

# Join the time-invariant ETS-country flag on (partner_iso2, year). Once
# phase2_build_customs_panel.R is re-run on RMD with the updated builder,
# the flag will be in the panel directly and this join becomes redundant —
# but harmless.
ets_status_path <- file.path(REPO_DIR, "data", "concordances",
                             "country_ets_status.csv")
ets_status <- data.table::fread(ets_status_path,
                                select = c("iso2", "year", "is_ets_country_ever"))
setnames(ets_status, "iso2", "partner_iso2")
d <- merge(d, ets_status, by = c("partner_iso2", "year"), all.x = TRUE)
d[is.na(is_ets_country_ever), is_ets_country_ever := FALSE]

# Four-group classification (full 2x2 of product regulation × country ETS).
GROUP_LEVELS <- c("Unregulated x non-ETS",
                  "Regulated x non-ETS",
                  "Regulated x ETS",
                  "Unregulated x ETS")
GROUP_COLORS <- c("grey50", "steelblue", "firebrick", "darkorange")
names(GROUP_COLORS) <- GROUP_LEVELS

d[, group := fcase(
  is_regulated_product == 0L & is_ets_country_ever == FALSE, "Unregulated x non-ETS",
  is_regulated_product == 1L & is_ets_country_ever == FALSE, "Regulated x non-ETS",
  is_regulated_product == 1L & is_ets_country_ever == TRUE,  "Regulated x ETS",
  is_regulated_product == 0L & is_ets_country_ever == TRUE,  "Unregulated x ETS"
)]
d[, group := factor(group, levels = GROUP_LEVELS)]

cat("\nRows per group (full sample):\n"); print(d[, .N, by = group])

# China ISO2 codes to exclude in the robustness version. CN is mainland
# China; HK is Hong Kong (often included with China origin in customs
# trade-flow work, cf. the phase6 China-origin-sigma revisit).
CHINA_ISO2 <- c("CN", "HK")

# -------------------------------------------------------------------------
# Figure-construction function. Takes a panel subset, a label suffix for
# titles/captions, and a filename suffix; produces (figure, table) writes.
# -------------------------------------------------------------------------
make_figure <- function(d_in, sample_label, fname_suffix) {

  # --- Time-frame coverage diagnostic ----------------------------------
  year_cov <- d_in[!is.na(group) & value > 0,
                    .(year_min = min(year), year_max = max(year),
                      n_years = uniqueN(year), n_cells = .N),
                    by = group]
  cat(sprintf("\n=== Figure: %s ===\n", sample_label))
  cat("Time-frame coverage by group (cells with value > 0):\n")
  print(year_cov)
  expected_min <- min(d_in$year, na.rm = TRUE)
  expected_max <- max(d_in$year, na.rm = TRUE)
  cat(sprintf("Panel year span overall: %d - %d\n",
              expected_min, expected_max))
  truncated <- year_cov[year_min > expected_min | year_max < expected_max]
  if (nrow(truncated) > 0) {
    cat("WARNING: some groups do NOT span the full panel window:\n")
    print(truncated)
  } else {
    cat("All four groups span the full panel window.\n")
  }

  # --- Panel (a): share within regulation-status total ----------------
  # Denominator = within-regulation-status total per year. So the
  # regulated pair (Red + Blue) sums to 1; the unregulated pair
  # (Orange + Grey) sums to 1.
  regstatus_totals <- d_in[!is.na(group),
                            .(regstatus_total = sum(value)),
                            by = .(year, is_regulated_product)]
  share_dt <- d_in[!is.na(group),
                    .(value = sum(value)),
                    by = .(year, group, is_regulated_product)]
  share_dt <- merge(share_dt, regstatus_totals,
                    by = c("year", "is_regulated_product"))
  share_dt[, share := value / regstatus_total]

  # --- Panel-completeness guard ---------------------------------------
  annual_total <- d_in[!is.na(group), .(annual_value = sum(value)),
                        by = year]
  setorder(annual_total, year)
  median_total <- median(annual_total$annual_value)
  incomplete_years <- annual_total[annual_value < 0.5 * median_total, year]
  if (length(incomplete_years) > 0) {
    cat(sprintf("WARNING: dropping %d year(s) with incomplete aggregates",
                length(incomplete_years)),
        "(< 50% of the median annual import value):\n")
    print(annual_total[year %in% incomplete_years])
    share_dt <- share_dt[!year %in% incomplete_years]
  }

  # Keep only the two non-ETS lines (the CdGM regression sample) and relabel
  # them treatment / control. Their ETS complements are 1 - these and carry no
  # information the non-ETS lines don't, so we drop them for readability.
  TC_LEVELS <- c("Regulated (treatment)", "Unregulated (control)")
  TC_COLORS <- c("Regulated (treatment)" = "firebrick",
                 "Unregulated (control)" = "grey45")
  to_tc <- function(dt) {
    dt <- dt[group %in% c("Regulated x non-ETS", "Unregulated x non-ETS")]
    dt[, tc := factor(fifelse(group == "Regulated x non-ETS",
                              "Regulated (treatment)", "Unregulated (control)"),
                      levels = TC_LEVELS)]
    dt[]
  }

  # Event markers: ETS start (2005) and MSR (2017). No background shading.
  markers <- list(
    geom_vline(xintercept = 2005, linetype = "dashed",
               color = "grey50", linewidth = 0.4),
    geom_vline(xintercept = 2017, linetype = "dashed",
               color = "grey50", linewidth = 0.4)
  )
  marker_labels <- list(
    annotate("text", x = 2005, y = Inf, label = "ETS", hjust = -0.15,
             vjust = 1.6, size = 4.2, color = "grey45"),
    annotate("text", x = 2017, y = Inf, label = "MSR", hjust = -0.15,
             vjust = 1.6, size = 4.2, color = "grey45")
  )

  # Shared clean theme: no gridlines, anchored axis lines, large axis title /
  # tick fonts, and extra space between the y-axis title and its tick labels.
  clean_theme <- theme_minimal(base_size = 14) +
    theme(
      panel.grid      = element_blank(),
      axis.line       = element_line(color = "grey20", linewidth = 0.4),
      axis.ticks      = element_line(color = "grey20", linewidth = 0.4),
      axis.title.x    = element_text(size = 17, margin = margin(t = 10)),
      axis.title.y    = element_text(size = 17, margin = margin(r = 14)),
      axis.text       = element_text(size = 14, color = "grey20"),
      legend.position = "none",
      plot.margin     = margin(6, 80, 6, 6),
      plot.title      = element_blank(),
      plot.subtitle   = element_blank(),
      plot.caption    = element_blank()
    )

  share_tc <- to_tc(share_dt)
  cat("Non-ETS source share by product type / year:\n")
  print(dcast(share_tc, year ~ tc, value.var = "share"))
  lab_a <- share_tc[, .SD[which.max(year)], by = tc]
  lab_a[, lab_short := fifelse(tc == "Regulated (treatment)",
                               "Regulated", "Unregulated")]

  p_a <- ggplot(share_tc, aes(x = year, y = share, color = tc)) +
    markers + marker_labels +
    geom_line(linewidth = 1.1) + geom_point(size = 1.8) +
    geom_text(data = lab_a, aes(label = lab_short, color = tc),
              hjust = 0, nudge_x = 0.20, size = 3.8, fontface = "bold",
              show.legend = FALSE) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    scale_color_manual(values = TC_COLORS, drop = FALSE) +
    scale_x_continuous(expand = expansion(mult = c(0.02, 0.04))) +
    coord_cartesian(clip = "off") +
    labs(x = NULL, y = "Non-ETS import share", color = NULL) +
    clean_theme

  # --- Panel (b): probability of sourcing from non-ETS ----------------
  prob_dt <- d_in[!is.na(group), .(active = mean(value > 0)),
                   by = .(year, group)]
  if (length(incomplete_years) > 0) {
    prob_dt <- prob_dt[!year %in% incomplete_years]
  }
  prob_tc <- to_tc(prob_dt)
  cat("Probability of sourcing from non-ETS by product type / year:\n")
  print(dcast(prob_tc, year ~ tc, value.var = "active"))
  lab_b <- prob_tc[, .SD[which.max(year)], by = tc]
  lab_b[, lab_short := fifelse(tc == "Regulated (treatment)",
                               "Regulated", "Unregulated")]

  p_b <- ggplot(prob_tc, aes(x = year, y = active, color = tc)) +
    markers + marker_labels +
    geom_line(linewidth = 1.1) + geom_point(size = 1.8) +
    geom_text(data = lab_b, aes(label = lab_short, color = tc),
              hjust = 0, nudge_x = 0.20, size = 3.8, fontface = "bold",
              show.legend = FALSE) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
    scale_color_manual(values = TC_COLORS, drop = FALSE) +
    scale_x_continuous(expand = expansion(mult = c(0.02, 0.04))) +
    coord_cartesian(clip = "off") +
    labs(x = NULL, y = "Sourcing probability", color = NULL) +
    clean_theme

  # --- Save each panel as a SEPARATE figure ---------------------------
  fig_dir <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
  tab_dir <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

  mock_tag <- if (USE_MOCK) "_MOCK" else ""
  out_a <- file.path(fig_dir, sprintf("phase2_cdgm_figure2_share%s%s.png",
                                      fname_suffix, mock_tag))
  out_b <- file.path(fig_dir, sprintf("phase2_cdgm_figure2_prob%s%s.png",
                                      fname_suffix, mock_tag))
  ggsave(out_a, p_a, width = 8, height = 5, dpi = 200)
  ggsave(out_b, p_b, width = 8, height = 5, dpi = 200)
  cat(sprintf("Figures saved:\n  %s\n  %s\n", out_a, out_b))

  out_tab <- file.path(tab_dir, sprintf("phase2_cdgm_figure2%s%s.csv",
                                         fname_suffix, mock_tag))
  agg <- merge(share_tc[, .(year, tc, share)],
               prob_tc[, .(year, tc, prob_active = active)],
               by = c("year", "tc"))
  fwrite(agg, out_tab)
  cat(sprintf("Table saved:  %s\n", out_tab))
}

# -------------------------------------------------------------------------
# Run twice: full sample, and with China (CN, HK) removed.
# -------------------------------------------------------------------------
make_figure(d, "all source countries", "")

d_no_china <- d[!partner_iso2 %in% CHINA_ISO2]
cat(sprintf("\nExcluding China (CN, HK): %d rows -> %d rows (%.1f%% kept)\n",
            nrow(d), nrow(d_no_china),
            100 * nrow(d_no_china) / nrow(d)))
make_figure(d_no_china, "excluding China (CN, HK)", "_excl_china")

cat("\n=== Done ===\n")
