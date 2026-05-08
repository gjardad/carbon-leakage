# Phase 1 -- Belgian PPI pass-through, CMDJ Figure 1 analog.
#
# Replicates CMDJ Figure 1 ("Evolution of relative prices of regulated versus
# unregulated products: Evidence from French PPI data") on Belgian data.
#
# Inputs:
#   * NBB_data/processed/deflator_nace4d_2005base.RData -- BE PPI 2005-2024,
#     139 NACE 4d sectors (Statbel + Eurostat chain-linked, 2005=100).
#   * data/io/regulated_producing_nace.csv -- 14 regulated NACE 2d sectors from
#     Step 6 (Phase 0).
#
# Outputs:
#   * output/figures/phase1_ppi_figure1_be.png  -- average log PPI by treatment,
#     plus regulated-minus-unregulated difference.
#   * output/figures/phase1_eventstudy_be.png   -- year-by-year coefficients
#     from event-study spec.
#   * output/tables/phase1_eventstudy_be.csv    -- full coefficient table.
#
# Specs:
#   1. Descriptive (Figure 1 form): average log(PPI/PPI_2005) by year and
#      treatment; plot the difference with 95% CI.
#   2. Event-study (regression form):
#        log(PPI_{s,t}) = Sum_{tau != 2005} beta_tau * 1(s in regulated) *
#                         1(year = tau) + alpha_s + delta_t + e_{s,t}
#      with FE on NACE 4d and year, cluster on NACE 4d.
#
# Sample: NACE 4d in goods-producing sections (B/C/D = NACE 2d 05-39) since
# regulation only applies to goods. Years 2005-2022 (CMDJ uses 2000-2019; we
# match what data we have).

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE)) install.packages("fixest", repos = "https://cloud.r-project.org")
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2", repos = "https://cloud.r-project.org")
library(data.table)
library(fixest)
library(ggplot2)

# Year of ETS Phase boundaries (for plot annotation):
ETS_PHASE1 <- 2005L
ETS_PHASE2 <- 2008L
ETS_PHASE3 <- 2013L
ETS_PHASE4 <- 2021L
SAMPLE_START <- 2001L  # earliest year with full Eurostat 2d coverage
SAMPLE_END   <- 2022L  # last year with full deflator data
REF_YEAR     <- 2004L  # last pre-ETS year (CMdG reference)

# CMdG-tight regulated NACE 2d set (Table A.5 col (1)/(4) ETS sectors collapsed
# to 2-digit). For "exact replication" robustness column.
CMDJ_TIGHT_2D <- c("17", "19", "20", "23", "24", "25", "35")

# -------------------------------------------------------------------------
# 1. Load data
# -------------------------------------------------------------------------
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData"))
def <- as.data.table(deflator)
setnames(def, "nace4d", "nace4d_str")
def[, nace2d := substr(nace4d_str, 1, 2)]

reg <- fread(file.path(REPO_DIR, "data", "io", "regulated_producing_nace.csv"))
reg[, nace2d := sprintf("%02d", as.integer(nace2d))]
reg_2d <- reg$nace2d
cat("Regulated-producing NACE 2d (broad, our list,", length(reg_2d), "): ",
    paste(reg_2d, collapse = ", "), "\n", sep = "")
cat("Regulated-producing NACE 2d (CMdG-tight,", length(CMDJ_TIGHT_2D), "): ",
    paste(CMDJ_TIGHT_2D, collapse = ", "), "\n", sep = "")

# Filter to goods-producing (B/C/D = NACE 2d 05-39), cap years at SAMPLE_END.
def <- def[as.integer(nace2d) %between% c(5L, 39L) &
           year %between% c(SAMPLE_START, SAMPLE_END)]
def[, treated_broad := nace2d %in% reg_2d]
def[, treated_tight := nace2d %in% CMDJ_TIGHT_2D]
def[, log_ppi := log(ppi)]

cat("\nSample sizes:\n")
cat("  total (sector, year)             :", nrow(def), "\n")
cat("  distinct NACE 4d                 :", uniqueN(def$nace4d_str), "\n")
cat("  treated NACE 4d (broad)          :", uniqueN(def[treated_broad == TRUE, nace4d_str]), "\n")
cat("  treated NACE 4d (CMdG-tight)     :", uniqueN(def[treated_tight == TRUE, nace4d_str]), "\n")
cat("  control NACE 4d (broad)          :", uniqueN(def[treated_broad == FALSE, nace4d_str]), "\n")
cat("  control NACE 4d (tight)          :", uniqueN(def[treated_tight == FALSE, nace4d_str]), "\n")
cat("  years                            :", min(def$year), "-", max(def$year), "\n")
cat("  pre-ETS years (",  SAMPLE_START, "-2004): ",
    sum(def$year < 2005), " obs\n", sep = "")

# -------------------------------------------------------------------------
# 2. Descriptive Figure 1 analog -- both treatment definitions
# -------------------------------------------------------------------------
make_diff_dt <- function(treat_col) {
  d <- copy(def)
  setnames(d, treat_col, "treated")
  desc <- d[, .(mean_logppi = mean(log_ppi),
                sd_logppi  = sd(log_ppi),
                n          = .N),
            by = .(year, treated)]
  dd <- dcast(desc, year ~ treated, value.var = c("mean_logppi", "sd_logppi", "n"))
  setnames(dd,
           c("mean_logppi_FALSE", "mean_logppi_TRUE",
             "sd_logppi_FALSE", "sd_logppi_TRUE",
             "n_FALSE", "n_TRUE"),
           c("mean_unreg", "mean_reg",
             "sd_unreg", "sd_reg",
             "n_unreg", "n_reg"))
  dd[, diff := mean_reg - mean_unreg]
  dd[, se_diff := sqrt(sd_reg^2 / n_reg + sd_unreg^2 / n_unreg)]
  dd[, ci_lo := diff - 1.96 * se_diff]
  dd[, ci_hi := diff + 1.96 * se_diff]
  ref_diff <- dd[year == REF_YEAR, diff]
  dd[, diff_rebased := diff - ref_diff]
  dd[, ci_lo_rebased := ci_lo - ref_diff]
  dd[, ci_hi_rebased := ci_hi - ref_diff]
  dd[, treat_def := treat_col]
  dd
}
diff_broad <- make_diff_dt("treated_broad")
diff_tight <- make_diff_dt("treated_tight")
diff_both <- rbind(diff_broad, diff_tight)
diff_both[, treat_label := ifelse(treat_def == "treated_broad",
                                   "Broad (our list, 14 NACE 2d)",
                                   "CMdG-tight (7 NACE 2d)")]

cat("\nDescriptive (regulated - unregulated log PPI, rebased to", REF_YEAR, "= 0):\n")
cat("\n  -- Broad treatment --\n")
print(diff_broad[, .(year, diff_rebased = round(diff_rebased, 3))])
cat("\n  -- CMdG-tight treatment --\n")
print(diff_tight[, .(year, diff_rebased = round(diff_rebased, 3))])

# Plot
fig_dir <- file.path(REPO_DIR, "output", "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
tab_dir <- file.path(REPO_DIR, "output", "tables")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

y_max_pad <- max(diff_both$ci_hi_rebased, na.rm = TRUE) * 0.95
p_fig1 <- ggplot(diff_both, aes(x = year, y = diff_rebased,
                                 color = treat_label, fill = treat_label)) +
  geom_ribbon(aes(ymin = ci_lo_rebased, ymax = ci_hi_rebased),
              alpha = 0.15, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.5) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  geom_vline(xintercept = ETS_PHASE1 - 0.5, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = ETS_PHASE2 - 0.5, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = ETS_PHASE3 - 0.5, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = ETS_PHASE4 - 0.5, linetype = "dotted", color = "grey50") +
  annotate("text", x = SAMPLE_START + 0.5, y = y_max_pad,
           label = "Pre-ETS", hjust = 0, size = 3, color = "grey40") +
  annotate("text", x = ETS_PHASE1 + 1, y = y_max_pad,
           label = "Phase 1", hjust = 0, size = 3, color = "grey40") +
  annotate("text", x = ETS_PHASE2 + 1, y = y_max_pad,
           label = "Phase 2", hjust = 0, size = 3, color = "grey40") +
  annotate("text", x = ETS_PHASE3 + 1, y = y_max_pad,
           label = "Phase 3", hjust = 0, size = 3, color = "grey40") +
  annotate("text", x = ETS_PHASE4 + 0.5, y = y_max_pad,
           label = "Phase 4", hjust = 0, size = 3, color = "grey40") +
  scale_color_manual(values = c("steelblue", "darkorange")) +
  scale_fill_manual(values = c("steelblue", "darkorange")) +
  labs(
    title = "Belgian PPI: regulated vs. unregulated NACE 4d sectors",
    subtitle = sprintf("Average log(PPI) reg - unreg, rebased to %d = 0", REF_YEAR),
    x = NULL, y = "Log PPI difference (reg - unreg)",
    color = "Treatment", fill = "Treatment",
    caption = "Source: Statbel + Eurostat chained PPI. Tight = NACE {17,19,20,23,24,25,35} per CMdG Table A.5 col (1)/(4)."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(fig_dir, "phase1_ppi_figure1_be.png"),
       p_fig1, width = 9, height = 5.5, dpi = 200)
cat("\nFigure 1 saved:", file.path(fig_dir, "phase1_ppi_figure1_be.png"), "\n")

# -------------------------------------------------------------------------
# 3. Event-study regression -- both treatment definitions
# -------------------------------------------------------------------------
def[, year_f := factor(year, levels = sort(unique(year)))]
def[, year_f := relevel(year_f, ref = as.character(REF_YEAR))]

run_es <- function(treat_col, label) {
  d <- copy(def)
  setnames(d, treat_col, "treated")
  es <- feols(log_ppi ~ i(year_f, treated, ref = as.character(REF_YEAR)) |
                nace4d_str + year_f,
              cluster = ~ nace4d_str,
              data = d)
  co <- as.data.table(summary(es)$coeftable, keep.rownames = "term")
  setnames(co, c("term", "estimate", "se", "tval", "pval"))
  co[, year := suppressWarnings(as.integer(gsub(".*::([0-9]+).*", "\\1", term)))]
  co <- co[!is.na(year)]
  co[, ci_lo := estimate - 1.96 * se]
  co[, ci_hi := estimate + 1.96 * se]
  ref_row <- data.table(year = REF_YEAR, estimate = 0, se = 0, ci_lo = 0, ci_hi = 0)
  out <- rbind(co[, .(year, estimate, se, ci_lo, ci_hi)], ref_row, fill = TRUE)
  out[, treat_label := label]
  setorder(out, year)
  out
}
es_broad <- run_es("treated_broad", "Broad (our list, 14 NACE 2d)")
es_tight <- run_es("treated_tight", "CMdG-tight (7 NACE 2d)")
es_both  <- rbind(es_broad, es_tight)

cat("\nEvent-study coefficients, BROAD treatment (ref = 2004):\n")
print(es_broad[, .(year, beta = round(estimate, 3),
                   se = round(se, 3),
                   ci_lo = round(ci_lo, 3),
                   ci_hi = round(ci_hi, 3))])

cat("\nEvent-study coefficients, CMdG-TIGHT treatment (ref = 2004):\n")
print(es_tight[, .(year, beta = round(estimate, 3),
                   se = round(se, 3),
                   ci_lo = round(ci_lo, 3),
                   ci_hi = round(ci_hi, 3))])

p_es <- ggplot(es_both, aes(x = year, y = estimate,
                            color = treat_label, fill = treat_label)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.15, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.5) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  geom_vline(xintercept = ETS_PHASE1 - 0.5, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = ETS_PHASE2 - 0.5, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = ETS_PHASE3 - 0.5, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = ETS_PHASE4 - 0.5, linetype = "dotted", color = "grey50") +
  scale_color_manual(values = c("steelblue", "darkorange")) +
  scale_fill_manual(values = c("steelblue", "darkorange")) +
  labs(
    title = "Belgian PPI event study: regulated NACE 4d sectors",
    subtitle = sprintf("Beta_tau on (regulated x year=tau), ref = %d; FE: NACE 4d, year; cluster: NACE 4d", REF_YEAR),
    x = NULL, y = "Beta_tau",
    color = "Treatment", fill = "Treatment"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(fig_dir, "phase1_eventstudy_be.png"),
       p_es, width = 9, height = 5.5, dpi = 200)
cat("\nEvent-study figure saved:", file.path(fig_dir, "phase1_eventstudy_be.png"), "\n")

fwrite(es_both, file.path(tab_dir, "phase1_eventstudy_be.csv"))
cat("Coefficient table saved:", file.path(tab_dir, "phase1_eventstudy_be.csv"), "\n")

# Phase-aggregated estimates -- both treatments side by side.
def[, phase := fcase(
  year < ETS_PHASE1, "0 (Pre-ETS, 2001-2004)",
  year < ETS_PHASE2, "1 (2005-2007)",
  year < ETS_PHASE3, "2 (2008-2012)",
  year < ETS_PHASE4, "3 (2013-2020)",
  default = "4 (2021+)"
)]
phase_broad <- feols(log_ppi ~ i(phase, treated_broad, ref = "0 (Pre-ETS, 2001-2004)") |
                       nace4d_str + year,
                     cluster = ~ nace4d_str,
                     data = def)
phase_tight <- feols(log_ppi ~ i(phase, treated_tight, ref = "0 (Pre-ETS, 2001-2004)") |
                       nace4d_str + year,
                     cluster = ~ nace4d_str,
                     data = def)
cat("\n=== Phase-aggregated event study, BROAD (ref = Pre-ETS 2001-2004) ===\n")
print(summary(phase_broad))
cat("\n=== Phase-aggregated event study, CMdG-TIGHT (ref = Pre-ETS 2001-2004) ===\n")
print(summary(phase_tight))

# -------------------------------------------------------------------------
# 4. CMdG-style Figure 1 -- exact visual replica
# -------------------------------------------------------------------------
# Headline figure uses the SECTOR-SPECIFIC LINEAR TRENDS spec (es_tight_dt /
# es_broad_dt computed below in section 5), since the no-trend version has
# clear pre-ETS dynamics that contaminate the post-2005 coefficients
# (regulated vs unregulated PPI gap was already trending upward before ETS).
# The trend-controlled version keeps the spec internally consistent with
# the eq. (\eqref{eq:passthrough_strategy2}) prose in the paper, which states
# "with sector-specific linear trends θ_s · t".
#
# The no-trend version is computed earlier (es_tight, es_broad) but is no
# longer the headline figure; it was the previous version of figure
# phase1_figure1_cmdj_style.png and remains as a baseline-without-trends
# comparator inside Diagnostic 1 (phase1_diag1_sector_trends.png).
#
# CMdG aesthetic: capped error bars (point-range), Phase 1 and Phase 3
# shaded in light blue, Phase 2 unshaded, "Pre-ETS / Phase 1 / Phase 2 /
# Phase 3" labels at top, x-axis 2001-2019 to match their sample.

# Need to compute es_tight_dt / es_broad_dt before the headline plot.
def[, year_num := as.integer(year)]
def[, year_f := factor(year, levels = sort(unique(year)))]
def[, year_f := relevel(year_f, ref = as.character(REF_YEAR))]

run_es_with_trends_inline <- function(treat_col, label) {
  d <- copy(def)
  setnames(d, treat_col, "treated")
  es <- feols(log_ppi ~ i(year_f, treated, ref = as.character(REF_YEAR)) |
                nace4d_str + year_f + nace4d_str[year_num],
              cluster = ~ nace4d_str,
              data = d)
  co <- as.data.table(summary(es)$coeftable, keep.rownames = "term")
  setnames(co, c("term", "estimate", "se", "tval", "pval"))
  co[, year := suppressWarnings(as.integer(gsub(".*::([0-9]+).*", "\\1", term)))]
  co <- co[!is.na(year)]
  co[, ci_lo := estimate - 1.96 * se]
  co[, ci_hi := estimate + 1.96 * se]
  ref_row <- data.table(year = REF_YEAR, estimate = 0, se = 0, ci_lo = 0, ci_hi = 0)
  out <- rbind(co[, .(year, estimate, se, ci_lo, ci_hi)], ref_row, fill = TRUE)
  out[, treat_label := label]
  setorder(out, year)
  out
}
es_cmdj       <- run_es_with_trends_inline("treated_tight", "Tight + sector trends")[year <= 2019L]
es_cmdj_broad <- run_es_with_trends_inline("treated_broad", "Broad + sector trends")[year <= 2019L]

cmdj_phase_band <- function(xmin, xmax, fill = "lightblue", alpha = 0.25) {
  annotate("rect", xmin = xmin - 0.5, xmax = xmax + 0.5,
           ymin = -Inf, ymax = Inf, fill = fill, alpha = alpha)
}

y_top <- max(es_cmdj$ci_hi, na.rm = TRUE) * 1.05
y_bot <- min(es_cmdj$ci_lo, na.rm = TRUE) - 0.02

p_cmdj <- ggplot(es_cmdj, aes(x = year, y = estimate)) +
  cmdj_phase_band(ETS_PHASE1, ETS_PHASE2 - 1) +     # Phase 1 (2005-2007)
  cmdj_phase_band(ETS_PHASE3, 2019L) +              # Phase 3 (2013-2019)
  geom_hline(yintercept = 0, color = "firebrick", linewidth = 0.5) +
  geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi),
                  size = 0.3, fatten = 1.8,
                  color = "navy") +
  annotate("text", x = (SAMPLE_START + ETS_PHASE1) / 2 - 0.5,
           y = y_top, label = "Pre-ETS", size = 3.2, color = "grey20") +
  annotate("text", x = (ETS_PHASE1 + ETS_PHASE2 - 1) / 2,
           y = y_top, label = "Phase 1", size = 3.2, color = "grey20") +
  annotate("text", x = (ETS_PHASE2 + ETS_PHASE3 - 1) / 2,
           y = y_top, label = "Phase 2", size = 3.2, color = "grey20") +
  annotate("text", x = (ETS_PHASE3 + 2019) / 2,
           y = y_top, label = "Phase 3", size = 3.2, color = "grey20") +
  scale_x_continuous(breaks = seq(SAMPLE_START, 2019, by = 5)) +
  scale_y_continuous(limits = c(y_bot, y_top * 1.05)) +
  labs(
    title = "Belgian PPI: regulated vs. unregulated NACE 4d sectors (CMdG Fig. 1 style)",
    subtitle = sprintf("Beta_tau on (regulated x year=tau), ref = %d; FE: NACE 4d + year + NACE 4d-specific linear trends; cluster: NACE 4d (CMdG-tight, 7 NACE 2d)", REF_YEAR),
    x = NULL, y = expression(beta[tau]),
    caption = "Vertical bars = 95% CI. Shaded areas = ETS Phases 1 and 3 (per CMdG Fig 1 convention)."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(fig_dir, "phase1_figure1_cmdj_style.png"),
       p_cmdj, width = 8, height = 5, dpi = 220)
cat("\nCMdG-style figure saved:",
    file.path(fig_dir, "phase1_figure1_cmdj_style.png"), "\n")

# Same plot, broad treatment (for completeness).
y_top_b <- max(es_cmdj_broad$ci_hi, na.rm = TRUE) * 1.05
y_bot_b <- min(es_cmdj_broad$ci_lo, na.rm = TRUE) - 0.02
p_cmdj_broad <- ggplot(es_cmdj_broad, aes(x = year, y = estimate)) +
  cmdj_phase_band(ETS_PHASE1, ETS_PHASE2 - 1) +
  cmdj_phase_band(ETS_PHASE3, 2019L) +
  geom_hline(yintercept = 0, color = "firebrick", linewidth = 0.5) +
  geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi),
                  size = 0.3, fatten = 1.8, color = "navy") +
  annotate("text", x = (SAMPLE_START + ETS_PHASE1) / 2 - 0.5,
           y = y_top_b, label = "Pre-ETS", size = 3.2, color = "grey20") +
  annotate("text", x = (ETS_PHASE1 + ETS_PHASE2 - 1) / 2,
           y = y_top_b, label = "Phase 1", size = 3.2, color = "grey20") +
  annotate("text", x = (ETS_PHASE2 + ETS_PHASE3 - 1) / 2,
           y = y_top_b, label = "Phase 2", size = 3.2, color = "grey20") +
  annotate("text", x = (ETS_PHASE3 + 2019) / 2,
           y = y_top_b, label = "Phase 3", size = 3.2, color = "grey20") +
  scale_x_continuous(breaks = seq(SAMPLE_START, 2019, by = 5)) +
  scale_y_continuous(limits = c(y_bot_b, y_top_b * 1.05)) +
  labs(
    title = "Belgian PPI: regulated vs. unregulated NACE 4d sectors (CMdG Fig. 1 style)",
    subtitle = sprintf("Beta_tau, ref = %d; FE: NACE 4d + year + NACE 4d-specific linear trends; cluster: NACE 4d (broad, 14 NACE 2d)", REF_YEAR),
    x = NULL, y = expression(beta[tau]),
    caption = "Vertical bars = 95% CI. Shaded areas = ETS Phases 1 and 3 (per CMdG Fig 1 convention)."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(fig_dir, "phase1_figure1_cmdj_style_broad.png"),
       p_cmdj_broad, width = 8, height = 5, dpi = 220)
cat("CMdG-style figure (broad) saved:",
    file.path(fig_dir, "phase1_figure1_cmdj_style_broad.png"), "\n")

# -------------------------------------------------------------------------
# 5. Diagnostic 1 -- sector-specific linear trends
# -------------------------------------------------------------------------
# Add nace4d_str[year] to the FE structure: each NACE 4d gets its own linear
# trend in year. This absorbs slow-moving differential trends pre-dating ETS.
# If the post-2005 coefficients survive, the kink at 2005 is real (not just
# pre-trend extrapolation). If they collapse to zero, the entire signal was
# the pre-existing trend.
def[, year_num := as.integer(year)]

run_es_with_trends <- function(treat_col, label) {
  d <- copy(def)
  setnames(d, treat_col, "treated")
  es <- feols(log_ppi ~ i(year_f, treated, ref = as.character(REF_YEAR)) |
                nace4d_str + year_f + nace4d_str[year_num],
              cluster = ~ nace4d_str,
              data = d)
  co <- as.data.table(summary(es)$coeftable, keep.rownames = "term")
  setnames(co, c("term", "estimate", "se", "tval", "pval"))
  co[, year := suppressWarnings(as.integer(gsub(".*::([0-9]+).*", "\\1", term)))]
  co <- co[!is.na(year)]
  co[, ci_lo := estimate - 1.96 * se]
  co[, ci_hi := estimate + 1.96 * se]
  ref_row <- data.table(year = REF_YEAR, estimate = 0, se = 0, ci_lo = 0, ci_hi = 0)
  out <- rbind(co[, .(year, estimate, se, ci_lo, ci_hi)], ref_row, fill = TRUE)
  out[, treat_label := label]
  setorder(out, year)
  out
}
es_tight_dt <- run_es_with_trends("treated_tight", "Tight + sector trends")
es_broad_dt <- run_es_with_trends("treated_broad", "Broad + sector trends")

cat("\n=== Diagnostic 1: event study with sector-specific linear trends ===\n")
cat("\n  -- Tight + sector trends --\n")
print(es_tight_dt[, .(year, beta = round(estimate, 3),
                      se = round(se, 3),
                      ci_lo = round(ci_lo, 3),
                      ci_hi = round(ci_hi, 3))])
cat("\n  -- Broad + sector trends --\n")
print(es_broad_dt[, .(year, beta = round(estimate, 3),
                      se = round(se, 3),
                      ci_lo = round(ci_lo, 3),
                      ci_hi = round(ci_hi, 3))])

# Side-by-side plot: with and without sector-specific trends, tight treatment.
es_tight_baseline <- copy(es_tight)
es_tight_baseline[, treat_label := "Tight (baseline, no trends)"]
diag1_compare <- rbind(es_tight_baseline, es_tight_dt)
diag1_compare <- diag1_compare[year <= 2019]

p_diag1 <- ggplot(diag1_compare, aes(x = year, y = estimate,
                                      color = treat_label, fill = treat_label)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.15, color = NA) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.2) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  geom_vline(xintercept = ETS_PHASE1 - 0.5, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = ETS_PHASE2 - 0.5, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = ETS_PHASE3 - 0.5, linetype = "dotted", color = "grey50") +
  scale_color_manual(values = c("steelblue", "darkorange")) +
  scale_fill_manual(values = c("steelblue", "darkorange")) +
  labs(title = "Diagnostic 1: event study with vs. without sector-specific linear trends",
       subtitle = "Tight treatment (CMdG-comparable). Sector trends absorb pre-existing differential trends.",
       x = NULL, y = expression(beta[tau]),
       color = NULL, fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(fig_dir, "phase1_diag1_sector_trends.png"),
       p_diag1, width = 9, height = 5.5, dpi = 220)
cat("\nDiagnostic 1 figure saved:",
    file.path(fig_dir, "phase1_diag1_sector_trends.png"), "\n")

# Phase-aggregated with sector trends
phase_tight_trends <- feols(log_ppi ~ i(phase, treated_tight,
                                         ref = "0 (Pre-ETS, 2001-2004)") |
                              nace4d_str + year + nace4d_str[year_num],
                            cluster = ~ nace4d_str, data = def)
cat("\n=== Phase-aggregated event study, TIGHT + sector trends ===\n")
print(summary(phase_tight_trends))

# -------------------------------------------------------------------------
# 6. Diagnostic 2 -- pre-ETS placebo (2001-2004 only, fake treatment in 2003)
# -------------------------------------------------------------------------
# Restrict sample to the four pre-ETS years 2001-2004. Estimate the same event
# study with reference year 2001. If the parallel-trends assumption holds,
# beta_2002, beta_2003, beta_2004 should all be zero. If they're non-zero,
# the 2001-2004 dynamics are driven by something OTHER than ETS, and the
# post-2005 "treatment effects" we observe in the main spec are at least
# partly continuation of that pre-existing dynamic.

PLACEBO_END <- 2004L
PLACEBO_REF <- 2001L

def_pre <- def[year %between% c(SAMPLE_START, PLACEBO_END)]
def_pre[, year_f_pre := factor(year, levels = sort(unique(year)))]
def_pre[, year_f_pre := relevel(year_f_pre, ref = as.character(PLACEBO_REF))]

run_placebo <- function(treat_col, label) {
  d <- copy(def_pre)
  setnames(d, treat_col, "treated")
  es <- feols(log_ppi ~ i(year_f_pre, treated, ref = as.character(PLACEBO_REF)) |
                nace4d_str + year_f_pre,
              cluster = ~ nace4d_str,
              data = d)
  co <- as.data.table(summary(es)$coeftable, keep.rownames = "term")
  setnames(co, c("term", "estimate", "se", "tval", "pval"))
  co[, year := suppressWarnings(as.integer(gsub(".*::([0-9]+).*", "\\1", term)))]
  co <- co[!is.na(year)]
  co[, ci_lo := estimate - 1.96 * se]
  co[, ci_hi := estimate + 1.96 * se]
  ref_row <- data.table(year = PLACEBO_REF, estimate = 0, se = 0, ci_lo = 0, ci_hi = 0)
  out <- rbind(co[, .(year, estimate, se, ci_lo, ci_hi)], ref_row, fill = TRUE)
  out[, treat_label := label]
  setorder(out, year)
  out
}
plac_tight <- run_placebo("treated_tight", "Placebo (Tight, 2001-2004 only)")
plac_broad <- run_placebo("treated_broad", "Placebo (Broad, 2001-2004 only)")

cat("\n=== Diagnostic 2: pre-ETS placebo (2001-2004 only, ref = 2001) ===\n")
cat("\n  -- Tight placebo --\n")
print(plac_tight[, .(year, beta = round(estimate, 3),
                     se = round(se, 3),
                     ci_lo = round(ci_lo, 3),
                     ci_hi = round(ci_hi, 3))])
cat("\n  -- Broad placebo --\n")
print(plac_broad[, .(year, beta = round(estimate, 3),
                     se = round(se, 3),
                     ci_lo = round(ci_lo, 3),
                     ci_hi = round(ci_hi, 3))])

# Joint significance test on pre-ETS coefficients via Wald.
plac_tight_full <- feols(log_ppi ~ i(year_f_pre, treated_tight,
                                      ref = as.character(PLACEBO_REF)) |
                           nace4d_str + year_f_pre,
                         cluster = ~ nace4d_str, data = def_pre)
cat("\n  Wald joint-zero test on (2002, 2003, 2004) tight placebo:\n")
print(wald(plac_tight_full,
           keep = "year_f_pre::200(2|3|4):treated_tight"))

# Save diagnostic outputs
fwrite(rbind(es_tight_dt[, .(year, estimate, se, ci_lo, ci_hi, spec = "diag1_tight_trends")],
             es_broad_dt[, .(year, estimate, se, ci_lo, ci_hi, spec = "diag1_broad_trends")],
             plac_tight[,   .(year, estimate, se, ci_lo, ci_hi, spec = "diag2_tight_placebo")],
             plac_broad[,   .(year, estimate, se, ci_lo, ci_hi, spec = "diag2_broad_placebo")]),
       file.path(tab_dir, "phase1_diagnostics.csv"))
cat("\nDiagnostics table saved:", file.path(tab_dir, "phase1_diagnostics.csv"), "\n")
