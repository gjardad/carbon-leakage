# phase2_cmdj_figure3.R
#
# Replicates CMdG Figure 3 ("Evolution of firm-level imports from non-ETS
# countries: regulated vs. unregulated inputs"). Year-by-year event-study
# coefficients corresponding to Table 1 col (5) (the preferred specification
# with firm^product^country + country^year + sector^year FE).
#
# Spec:
#   y_{f,p,i,t} = sum_{tau != 2004} b_tau * 1(non_ets x regulated x year=tau)
#                 + alpha_{f,p,i} + delta_{i,t} + delta_{s,t} + e
#
# Two outcomes (two-panel figure):
#   (a) share_{f,p,i,t}
#   (b) prob_active_{f,p,i,t}
#
# Reference year: 2004 (last pre-ETS year).
# Cluster SE: two-way firm + country.
#
# Inputs / outputs analogous to phase2_cmdj_table1.R.

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE)) install.packages("fixest", repos = "https://cloud.r-project.org")
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2", repos = "https://cloud.r-project.org")
if (!requireNamespace("patchwork", quietly = TRUE)) install.packages("patchwork", repos = "https://cloud.r-project.org")

library(data.table)
library(fixest)
library(ggplot2)
library(patchwork)

USE_MOCK <- !file.exists(file.path(PROC_DATA, "customs_import_panel_regulated.dta"))

if (USE_MOCK) {
  cat("USING MOCK CUSTOMS PANEL.\n")
  load(file.path(PROC_DATA, "mock_customs_import_panel_regulated.RData"))
  d <- as.data.table(panel)
} else {
  cat("USING REAL CUSTOMS PANEL.\n")
  if (!requireNamespace("haven", quietly = TRUE)) install.packages("haven", repos = "https://cloud.r-project.org")
  d <- as.data.table(haven::read_dta(file.path(PROC_DATA, "customs_import_panel_regulated.dta")))
}
d <- d[year %between% c(2000L, 2019L)]

# Outcomes.
d[, total_value_ft := sum(value), by = .(vat, year)]
d[, share := ifelse(total_value_ft > 0, value / total_value_ft, 0)]
d[, prob_active := as.integer(value > 0)]

# Treatment indicator.
d[, treat := as.integer(is_regulated_product == 1L & is_non_ets_country == 1L)]

# Year as factor with reference 2004.
d[, year_f := factor(year, levels = sort(unique(year)))]
d[, year_f := relevel(year_f, ref = "2004")]

# FE strings (col 5 spec).
d[, firm_prod_country := paste(vat, cn8, partner_iso2, sep = "_")]
d[, country_year := paste(partner_iso2, year, sep = "_")]
d[, sector_year := paste(buyer_nace2d, year, sep = "_")]

# Run event studies.
run_es <- function(outcome_var, label) {
  fm <- as.formula(sprintf(
    "%s ~ i(year_f, treat, ref = '2004') | firm_prod_country + country_year + sector_year",
    outcome_var))
  m <- feols(fm, data = d, cluster = ~ vat + partner_iso2)
  co <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
  setnames(co, c("term", "estimate", "se", "tval", "pval"))
  co[, year := suppressWarnings(as.integer(gsub(".*::([0-9]+):.*", "\\1", term)))]
  co <- co[!is.na(year)]
  co[, ci_lo := estimate - 1.96 * se]
  co[, ci_hi := estimate + 1.96 * se]
  ref <- data.table(year = 2004L, estimate = 0, se = 0, ci_lo = 0, ci_hi = 0)
  out <- rbind(co[, .(year, estimate, se, ci_lo, ci_hi)], ref, fill = TRUE)
  out[, outcome := label]
  setorder(out, year)
  out
}

es_share <- run_es("share", "Share")
es_prob  <- run_es("prob_active", "Probability of sourcing")

cat("\n--- Share event-study coefficients ---\n")
print(es_share[, .(year, beta = round(estimate, 3),
                   se = round(se, 3),
                   ci_lo = round(ci_lo, 3),
                   ci_hi = round(ci_hi, 3))])
cat("\n--- Prob event-study coefficients ---\n")
print(es_prob[, .(year, beta = round(estimate, 3),
                  se = round(se, 3),
                  ci_lo = round(ci_lo, 3),
                  ci_hi = round(ci_hi, 3))])

# Plotting helper.
make_es_plot <- function(es_dt, ylab, panel_title) {
  ggplot(es_dt, aes(x = year, y = estimate)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_vline(xintercept = 2004.5, linetype = "dotted", color = "grey50") +
    geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi),
                    size = 0.3, color = "navy") +
    labs(title = panel_title, x = NULL, y = ylab) +
    theme_minimal(base_size = 11)
}

p_share <- make_es_plot(es_share, expression(beta[tau]),
                        "(a) Import share, regulated x non-ETS")
p_prob  <- make_es_plot(es_prob, expression(beta[tau]),
                        "(b) Probability of sourcing, regulated x non-ETS")
combined <- (p_share / p_prob) +
  plot_annotation(
    title = "CMdG Figure 3 replication: event-study coefficients",
    subtitle = sprintf("Belgium customs panel%s, 2000-2019; FE: firm^product^country + country^year + sector^year; cluster: firm + country",
                       ifelse(USE_MOCK, " (MOCK DATA)", "")),
    caption = "Vertical bars = 95% CI. Reference year = 2004.")

fig_dir <- file.path(REPO_DIR, "output", "figures")
tab_dir <- file.path(REPO_DIR, "output", "tables")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

out_fig <- file.path(fig_dir,
                     ifelse(USE_MOCK, "phase2_cmdj_figure3_MOCK.png",
                                       "phase2_cmdj_figure3.png"))
ggsave(out_fig, combined, width = 9, height = 8, dpi = 200)
cat("\nFigure saved:", out_fig, "\n")

# Save coefficients.
out_tab <- file.path(tab_dir,
                     ifelse(USE_MOCK, "phase2_cmdj_figure3_MOCK.csv",
                                       "phase2_cmdj_figure3.csv"))
fwrite(rbind(es_share, es_prob), out_tab)
cat("Coefficients saved:", out_tab, "\n")
