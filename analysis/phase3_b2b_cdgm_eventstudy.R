# phase3_b2b_cdgm_eventstudy.R
#
# Event-study version of the B2B CdGM-style design. Year-by-year coefficients,
# col(5) FE preferred spec, ref = 2004.
#
# Spec:
#   y_{j,b,t} = sum_{tau != 2004} b_tau * TREAT_j * 1(year=tau)
#               + alpha_{j,b} + delta_{sn4d,t} + delta_{bn4d,t} + e
#   TREAT_j = is_ets_seller * is_regulated_nace_seller
#
# Two outcomes (two-panel figure):
#   (a) share_{j,b,t}
#   (b) pair_active_{j,b,t}
#
# Cluster SE: two-way seller + buyer.
#
# Sample: 2005-2019 to match Phase 2 / CdGM window.
# (The B2B panel itself extends to 2022; we keep that data but restrict the
# event study to the CdGM window.)
#
# Outputs:
#   output/figures/phase3_b2b_cdgm_eventstudy.png
#   output/tables/phase3_b2b_cdgm_eventstudy.csv

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

REF_YEAR <- 2004L
SAMPLE_LO <- 2000L
SAMPLE_HI <- 2019L
# (Note: panel only starts at 2005 by construction, so REF_YEAR = 2004 here
# acts as an absorbed baseline; effective leads are 2005, 2006, ... vs 2005.)

panel_path <- file.path(PROC_DATA, "b2b_cdgm_panel.RData")
load(panel_path)
d <- as.data.table(panel)
d <- d[year %between% c(SAMPLE_LO, SAMPLE_HI)]

# Outcomes.
d[, total_buyer_sn4d_t := sum(corr_sales),
  by = .(buyer, seller_nace4d, year)]
d[, share := ifelse(total_buyer_sn4d_t > 0,
                    corr_sales / total_buyer_sn4d_t, 0)]
d[, prob_active := as.integer(corr_sales > 0)]

# Treatment.
d[, treat := seller_is_ets * seller_is_regulated_nace]

# Year factor with ref = 2004 (or earliest available year if 2004 absent).
ref <- if (REF_YEAR %in% d$year) as.character(REF_YEAR) else as.character(min(d$year))
d[, year_f := factor(year)]
d[, year_f := relevel(year_f, ref = ref)]

# FE keys.
d[, seller_buyer := paste(seller, buyer, sep = "_")]
d[, sn4d_year   := paste(seller_nace4d, year, sep = "_")]
d[, bn4d_year   := paste(buyer_nace4d,  year, sep = "_")]

run_es <- function(outcome, label) {
  fm <- as.formula(sprintf(
    "%s ~ i(year_f, treat, ref = '%s') | seller_buyer + sn4d_year + bn4d_year",
    outcome, ref))
  m <- feols(fm, data = d, cluster = ~ seller + buyer)
  co <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
  setnames(co, c("term", "estimate", "se", "tval", "pval"))
  co[, year := suppressWarnings(as.integer(gsub(".*::([0-9]+):.*", "\\1", term)))]
  co <- co[!is.na(year)]
  co[, ci_lo := estimate - 1.96 * se]
  co[, ci_hi := estimate + 1.96 * se]
  ref_row <- data.table(year = as.integer(ref),
                         estimate = 0, se = 0, ci_lo = 0, ci_hi = 0)
  out <- rbind(co[, .(year, estimate, se, ci_lo, ci_hi)], ref_row, fill = TRUE)
  out[, outcome := label]
  setorder(out, year)
  out
}

es_share <- run_es("share",       "Share")
es_prob  <- run_es("prob_active", "Probability")

cat("\n--- Share event-study coefficients ---\n")
print(es_share[, .(year, beta = round(estimate, 4),
                   se = round(se, 4),
                   ci_lo = round(ci_lo, 4),
                   ci_hi = round(ci_hi, 4))])

cat("\n--- Probability event-study coefficients ---\n")
print(es_prob[, .(year, beta = round(estimate, 4),
                  se = round(se, 4),
                  ci_lo = round(ci_lo, 4),
                  ci_hi = round(ci_hi, 4))])

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
                        "(a) Buyer share, ETS x regulated-NACE seller")
p_prob  <- make_es_plot(es_prob,  expression(beta[tau]),
                        "(b) Pair active, ETS x regulated-NACE seller")
combined <- (p_share / p_prob) +
  plot_annotation(
    title = "B2B CdGM event study: Belgian domestic supplier switching",
    subtitle = sprintf("Treatment = ETS x regulated_NACE seller; FE: seller^buyer + seller_nace4d^year + buyer_nace4d^year; cluster: seller + buyer; ref = %s",
                       ref),
    caption = "Sign expectation under leakage hypothesis: NEGATIVE post-2005.")

fig_dir <- file.path(REPO_DIR, "output", "figures")
tab_dir <- file.path(REPO_DIR, "output", "tables")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

ggsave(file.path(fig_dir, "phase3_b2b_cdgm_eventstudy.png"),
       combined, width = 9, height = 8, dpi = 200)
cat("\nFigure saved:", file.path(fig_dir, "phase3_b2b_cdgm_eventstudy.png"), "\n")

fwrite(rbind(es_share, es_prob),
       file.path(tab_dir, "phase3_b2b_cdgm_eventstudy.csv"))
cat("Coefficients saved:", file.path(tab_dir, "phase3_b2b_cdgm_eventstudy.csv"), "\n")
