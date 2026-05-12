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
# Inputs:
#   * RMD: ${PROC_NBB}/customs_import_panel_regulated.dta
#   * local 1: NBB_data/processed/customs_import_panel_regulated.RData
#     (or mock_customs_import_panel_regulated.RData if not present; toggle
#     via USE_MOCK).
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

  cat("Aggregate share by group/year:\n")
  print(dcast(share_dt, year ~ group, value.var = "share"))

  p_a <- ggplot(share_dt, aes(x = year, y = share, color = group)) +
    geom_vline(xintercept = 2004.5, linetype = "dashed", color = "grey40") +
    geom_line(linewidth = 0.9) + geom_point(size = 1.6) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    scale_color_manual(values = GROUP_COLORS, drop = FALSE) +
    annotate("text", x = 2002, y = max(share_dt$share, na.rm = TRUE),
             label = "Pre-ETS", size = 3, color = "grey40") +
    annotate("text", x = 2012, y = max(share_dt$share, na.rm = TRUE),
             label = "Post-2005 (ETS)", size = 3, color = "grey40") +
    labs(title = sprintf("(a) Source split within product type, %s", sample_label),
         subtitle = "Regulated pair (Red+Blue) sums to 1; Unregulated pair (Orange+Grey) sums to 1.",
         x = NULL, y = "Share within product type", color = NULL) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")

  # --- Panel (b): probability of sourcing -----------------------------
  prob_dt <- d_in[!is.na(group), .(active = mean(value > 0)),
                   by = .(year, group)]
  if (length(incomplete_years) > 0) {
    prob_dt <- prob_dt[!year %in% incomplete_years]
  }

  cat("Probability of sourcing by group/year:\n")
  print(dcast(prob_dt, year ~ group, value.var = "active"))

  p_b <- ggplot(prob_dt, aes(x = year, y = active, color = group)) +
    geom_vline(xintercept = 2004.5, linetype = "dashed", color = "grey40") +
    geom_line(linewidth = 0.9) + geom_point(size = 1.6) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
    scale_color_manual(values = GROUP_COLORS, drop = FALSE) +
    labs(title = "(b) Probability of sourcing (extensive margin)",
         x = NULL, y = "P(value > 0 | triplet, year)", color = NULL) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")

  # --- Combine and save -----------------------------------------------
  p_combined <- (p_a / p_b) +
    plot_annotation(
      title = sprintf("CdGM Figure 2 replication: %s", sample_label),
      subtitle = sprintf("Belgium customs panel%s, 2000-2019",
                         ifelse(USE_MOCK, " (MOCK DATA)", "")),
      caption = paste("Four lines:",
                      paste(GROUP_LEVELS, collapse = "; "),
                      ".  Panel (a) denominator: within-regulation-status",
                      "totals (regulated pair sums to 1; unregulated pair sums to 1).",
                      "Panel (b) denominator: per-group triplet pool.",
                      sep = " ")
    ) &
    theme(plot.title = element_text(size = 12),
          legend.position = "bottom")

  fig_dir <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
  tab_dir <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

  mock_tag <- if (USE_MOCK) "_MOCK" else ""
  out_fig <- file.path(fig_dir, sprintf("phase2_cdgm_figure2%s%s.png",
                                         fname_suffix, mock_tag))
  ggsave(out_fig, p_combined, width = 9, height = 8, dpi = 200)
  cat(sprintf("Figure saved: %s\n", out_fig))

  out_tab <- file.path(tab_dir, sprintf("phase2_cdgm_figure2%s%s.csv",
                                         fname_suffix, mock_tag))
  agg <- merge(share_dt[, .(year, group, share)],
               prob_dt[, .(year, group, prob_active = active)],
               by = c("year", "group"))
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
