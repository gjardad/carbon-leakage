###############################################################################
# phase1_ppi_passthrough_cmdj_monthly.R
#
# PURPOSE:
#   Replicate Coster, Méjean & di Giovanni (2024) Figure 1 ("Evolution of
#   relative prices of regulated versus unregulated products: Evidence from
#   French PPI data") on Belgian monthly NACE 4-digit PPI data.
#
#   This is the canonical CMdG specification at the same frequency CMdG use
#   (monthly), with the same FE structure they use (sector × calendar-month
#   for sector-specific seasonality + year FE), and the same reference period
#   (pre-ETS, 2000-2004). Differs from phase1_ppi_passthrough_cmdj.R in that
#   the latter aggregates the panel to annual frequency (because the previous
#   monthly deflator started 2005-01 and lacked pre-ETS observations).
#
# SPEC (CMdG eq. 1):
#
#   log(PPI_{s,t}) = sum_{τ != 2004} β_τ · 1[s ∈ regulated] · 1[year(t) = τ]
#                   + α_{s, month(t)}       (sector × calendar-month FE)
#                   + δ_{year(t)}           (year FE)
#                   + ε_{s,t}
#
#   Standard errors clustered on NACE 4d.
#
# SAMPLE:
#   2000-01 to 2022-12 monthly. 134 NACE 4-digit sectors.
#
# TREATMENT DEFINITIONS:
#   "CMdG-tight" — 7 NACE 2-digit sectors {17, 19, 20, 23, 24, 25, 35} per
#                  CMdG Table A.5 col (1)/(4). Default headline.
#   "Broad"      — 14 NACE 2-digit sectors per regulated_producing_nace.csv.
#                  Reported as a robustness in the paper appendix.
#
# INPUT:
#   ${PROC_DATA}/deflator_nace4d_2005base_monthly.RData (extended back to 2000-01)
#   data/io/regulated_producing_nace.csv
#
# OUTPUT:
#   ${OUTPUT_FIG}/phase1_figure1_cmdj_style.png   (headline, CMdG-tight)
#   ${OUTPUT_FIG}/phase1_figure1_cmdj_style_broad.png  (broad treatment)
#   ${OUTPUT_TAB}/phase1_eventstudy_be_monthly.csv      (yearly β coefs)
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(ggplot2)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# Phase boundaries (for plot annotation)
ETS_PHASE1   <- 2005L
ETS_PHASE2   <- 2008L
ETS_PHASE3   <- 2013L
ETS_PHASE4   <- 2021L
SAMPLE_START <- 2000L
SAMPLE_END   <- 2022L
REF_YEAR     <- 2004L  # last pre-ETS year (CMdG reference)

# CMdG-tight regulated NACE 2d set (Table A.5 col (1)/(4))
CMDJ_TIGHT_2D <- c("17", "19", "20", "23", "24", "25", "35")

###############################################################################
# 1. Load monthly deflator and treatment definitions
###############################################################################
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))
def <- as.data.table(deflator_monthly)
setnames(def, "nace4d", "nace4d_str")

reg <- fread(file.path(REPO_DIR, "data", "io", "regulated_producing_nace.csv"))
reg[, nace2d := sprintf("%02d", as.integer(nace2d))]
reg_2d <- reg$nace2d

cat(sprintf("Monthly deflator: %d obs, %d NACE 4d, %s to %s\n",
            nrow(def), uniqueN(def$nace4d_str),
            format(min(def$date)), format(max(def$date))))
cat(sprintf("Pre-ETS obs (year < %d): %d (%.1f%%)\n",
            ETS_PHASE1, sum(def$year < ETS_PHASE1),
            100 * mean(def$year < ETS_PHASE1)))
cat(sprintf("Regulated NACE 2d, broad (%d): %s\n",
            length(reg_2d), paste(reg_2d, collapse = ", ")))
cat(sprintf("Regulated NACE 2d, CMdG-tight (%d): %s\n",
            length(CMDJ_TIGHT_2D), paste(CMDJ_TIGHT_2D, collapse = ", ")))

# Filter to goods-producing (B/C/D = NACE 2d 05-39) and sample window
def <- def[as.integer(nace2d) %between% c(5L, 39L) &
           year %between% c(SAMPLE_START, SAMPLE_END)]
def[, treated_broad := nace2d %in% reg_2d]
def[, treated_tight := nace2d %in% CMDJ_TIGHT_2D]
def[, log_ppi := log(ppi)]
def[, year_f  := factor(year, levels = sort(unique(year)))]
def[, year_f  := relevel(year_f, ref = as.character(REF_YEAR))]

cat(sprintf("\nSample after filters: %d obs, %d NACE 4d\n",
            nrow(def), uniqueN(def$nace4d_str)))
cat(sprintf("  Treated NACE 4d (CMdG-tight): %d\n",
            uniqueN(def[treated_tight == TRUE, nace4d_str])))
cat(sprintf("  Treated NACE 4d (broad):       %d\n",
            uniqueN(def[treated_broad == TRUE, nace4d_str])))

###############################################################################
# 2. CMdG event-study at monthly frequency
###############################################################################
# Spec: log(PPI_{s,t}) = sum_τ β_τ · 1[treated] · 1[year(t)=τ]
#                       + sector × month FE (seasonality)
#                       + year FE
#                       + error clustered on NACE 4d.
#
# Implementation: feols formula has FE = nace4d_str^month + year_f, where
# nace4d_str^month creates one fixed effect per (sector, calendar month)
# pair (so 134 × 12 = 1,608 sector-month FE), exactly mirroring CMdG's
# "X'_st includes sector × month and year fixed effects".
###############################################################################

run_cmdj_es <- function(treat_col, label) {
  d <- copy(def)
  setnames(d, treat_col, "treated")
  m <- feols(
    log_ppi ~ i(year_f, treated, ref = as.character(REF_YEAR)) |
      nace4d_str^month + year_f,
    cluster = ~ nace4d_str,
    data = d
  )
  co <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
  setnames(co, c("term", "estimate", "se", "tval", "pval"))
  co[, year := suppressWarnings(as.integer(gsub(".*::([0-9]+).*",
                                                "\\1", term)))]
  co <- co[!is.na(year)]
  co[, ci_lo := estimate - 1.96 * se]
  co[, ci_hi := estimate + 1.96 * se]
  ref_row <- data.table(year = REF_YEAR, estimate = 0,
                        se = 0, ci_lo = 0, ci_hi = 0)
  out <- rbind(co[, .(year, estimate, se, ci_lo, ci_hi)], ref_row, fill = TRUE)
  out[, treat_label := label]
  setorder(out, year)
  out
}

cat("\n=== Event study (CMdG-tight, monthly, sector × month + year FE) ===\n")
es_tight <- run_cmdj_es("treated_tight", "CMdG-tight (7 NACE 2d)")
print(es_tight[, .(year,
                   beta = round(estimate, 3),
                   se = round(se, 3),
                   ci_lo = round(ci_lo, 3),
                   ci_hi = round(ci_hi, 3))])

cat("\n=== Event study (broad, monthly) ===\n")
es_broad <- run_cmdj_es("treated_broad", "Broad (our list, 14 NACE 2d)")
print(es_broad[, .(year,
                   beta = round(estimate, 3),
                   se = round(se, 3),
                   ci_lo = round(ci_lo, 3),
                   ci_hi = round(ci_hi, 3))])

###############################################################################
# 3. Phase-aggregated coefficients (for prose magnitudes)
###############################################################################
def[, phase := fcase(
  year < ETS_PHASE1, "0 (Pre-ETS, 2000-2004)",
  year < ETS_PHASE2, "1 (2005-2007)",
  year < ETS_PHASE3, "2 (2008-2012)",
  year < ETS_PHASE4, "3 (2013-2020)",
  default          = "4 (2021+)"
)]

phase_tight <- feols(
  log_ppi ~ i(phase, treated_tight, ref = "0 (Pre-ETS, 2000-2004)") |
    nace4d_str^month + year_f,
  cluster = ~ nace4d_str, data = def
)
cat("\n=== Phase-aggregated event study, CMdG-tight (ref = Pre-ETS 2000-2004) ===\n")
print(summary(phase_tight))

phase_broad <- feols(
  log_ppi ~ i(phase, treated_broad, ref = "0 (Pre-ETS, 2000-2004)") |
    nace4d_str^month + year_f,
  cluster = ~ nace4d_str, data = def
)
cat("\n=== Phase-aggregated event study, broad (ref = Pre-ETS 2000-2004) ===\n")
print(summary(phase_broad))

###############################################################################
# 4. CMdG Figure 1 style plot
###############################################################################
# CMdG aesthetic: capped point-range error bars in navy, Phase 1 and Phase 3
# shaded light blue, "Pre-ETS / Phase 1 / Phase 2 / Phase 3" labels at top,
# x-axis 2000-2019 to match their sample. Use CMdG-tight as headline.

cmdj_phase_band <- function(xmin, xmax, fill = "lightblue", alpha = 0.25) {
  annotate("rect", xmin = xmin - 0.5, xmax = xmax + 0.5,
           ymin = -Inf, ymax = Inf, fill = fill, alpha = alpha)
}

plot_cmdj_style <- function(es_data, label_str, xmax_year = 2019L) {
  d <- es_data[year <= xmax_year]
  y_top <- max(d$ci_hi, na.rm = TRUE) * 1.05
  y_bot <- min(d$ci_lo, na.rm = TRUE) - 0.02

  ggplot(d, aes(x = year, y = estimate)) +
    cmdj_phase_band(ETS_PHASE1, ETS_PHASE2 - 1) +     # Phase 1 (2005-2007)
    cmdj_phase_band(ETS_PHASE3, xmax_year) +          # Phase 3 (2013-2019)
    geom_hline(yintercept = 0, color = "firebrick", linewidth = 0.5) +
    geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi),
                    size = 0.3, fatten = 1.8, color = "navy") +
    annotate("text", x = (SAMPLE_START + ETS_PHASE1) / 2 - 0.5,
             y = y_top, label = "Pre-ETS", size = 3.2, color = "grey20") +
    annotate("text", x = (ETS_PHASE1 + ETS_PHASE2 - 1) / 2,
             y = y_top, label = "Phase 1", size = 3.2, color = "grey20") +
    annotate("text", x = (ETS_PHASE2 + ETS_PHASE3 - 1) / 2,
             y = y_top, label = "Phase 2", size = 3.2, color = "grey20") +
    annotate("text", x = (ETS_PHASE3 + xmax_year) / 2,
             y = y_top, label = "Phase 3", size = 3.2, color = "grey20") +
    scale_x_continuous(breaks = seq(SAMPLE_START, xmax_year, by = 5)) +
    scale_y_continuous(limits = c(y_bot, y_top * 1.05)) +
    labs(
      title = "Belgian PPI: regulated vs. unregulated NACE 4d sectors (CMdG Fig. 1 style)",
      subtitle = sprintf(
        "Beta_tau on (regulated × year=tau), ref = %d; FE: NACE 4d × month + year; cluster: NACE 4d (%s)",
        REF_YEAR, label_str
      ),
      x = NULL, y = expression(beta[tau]),
      caption = "Vertical bars = 95% CI. Shaded areas = ETS Phases 1 and 3 (per CMdG Fig 1 convention)."
    ) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank())
}

p_tight <- plot_cmdj_style(es_tight, "CMdG-tight, 7 NACE 2d")
p_broad <- plot_cmdj_style(es_broad, "Broad, 14 NACE 2d")

ggsave(file.path(OUTPUT_FIG, "phase1_figure1_cmdj_style.png"),
       p_tight, width = 8, height = 5, dpi = 220)
ggsave(file.path(OUTPUT_FIG, "phase1_figure1_cmdj_style.pdf"),
       p_tight, width = 8, height = 5)
ggsave(file.path(OUTPUT_FIG, "phase1_figure1_cmdj_style_broad.png"),
       p_broad, width = 8, height = 5, dpi = 220)

cat("\nFigure saved:",
    file.path(OUTPUT_FIG, "phase1_figure1_cmdj_style.png"), "\n")
cat("Broad-treatment robustness:",
    file.path(OUTPUT_FIG, "phase1_figure1_cmdj_style_broad.png"), "\n")

###############################################################################
# 5. Save coefficient tables
###############################################################################
fwrite(rbind(es_tight, es_broad),
       file.path(OUTPUT_TAB, "phase1_eventstudy_be_monthly.csv"))
cat("Coefficient table saved:",
    file.path(OUTPUT_TAB, "phase1_eventstudy_be_monthly.csv"), "\n")
