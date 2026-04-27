# phase2_cmdj_figure2.R
#
# Replicates CMdG Figure 2 ("Aggregate import shares and probability of
# sourcing from a new supplier market: control vs. treatment groups").
#
# Two panels:
#   (a) Aggregate import SHARE by year, treatment vs. control.
#   (b) Aggregate PROBABILITY of sourcing by year (extensive margin), treatment
#       vs. control.
#
# Treatment group: regulated_product == 1 AND non_ets_country == 1.
# Control group:   regulated_product == 0 AND non_ets_country == 1
#                  (CMdG's preferred control = unregulated x non-ETS).
#
# Inputs:
#   * RMD: ${PROC_NBB}/customs_import_panel_regulated.dta
#   * local 1: NBB_data/processed/mock_customs_import_panel_regulated.RData
#     (toggle via USE_MOCK).
#
# Outputs:
#   * output/figures/phase2_cmdj_figure2.png  (replication of CMdG Fig 2)
#   * output/tables/phase2_cmdj_figure2.csv   (annual aggregates per group)

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

# Restrict to non-ETS source countries (CMdG's domain for Fig 2).
d_ne <- d[is_non_ets_country == 1L]
cat("Non-ETS country subset rows:", nrow(d_ne), "\n")

# Group definition: treatment = regulated, control = unregulated.
d_ne[, group := factor(ifelse(is_regulated_product == 1L,
                              "Treated (regulated x non-ETS)",
                              "Control (unregulated x non-ETS)"),
                       levels = c("Control (unregulated x non-ETS)",
                                  "Treated (regulated x non-ETS)"))]

# -------------------------------------------------------------------------
# Panel (a): aggregate import share.
# Per CMdG p. 12: "share in overall imports". For each year, the share is
# the fraction of total non-ETS-country imports going to that group.
# (Aggregate value of the group / total non-ETS imports that year.)
# -------------------------------------------------------------------------
share_dt <- d_ne[, .(value = sum(value)), by = .(year, group)]
share_dt[, total := sum(value), by = year]
share_dt[, share := value / total]

cat("\nAggregate share by group/year:\n")
print(dcast(share_dt, year ~ group, value.var = "share"))

p_a <- ggplot(share_dt, aes(x = year, y = share, color = group)) +
  geom_vline(xintercept = 2004.5, linetype = "dashed", color = "grey40") +
  geom_line(linewidth = 0.9) + geom_point(size = 1.6) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = c("grey40", "steelblue")) +
  annotate("text", x = 2002, y = max(share_dt$share, na.rm = TRUE),
           label = "Pre-ETS", size = 3, color = "grey40") +
  annotate("text", x = 2012, y = max(share_dt$share, na.rm = TRUE),
           label = "Post-2005 (ETS)", size = 3, color = "grey40") +
  labs(title = "(a) Aggregate import share, non-ETS source countries",
       x = NULL, y = "Share of non-ETS imports", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

# -------------------------------------------------------------------------
# Panel (b): aggregate probability of sourcing (extensive margin).
# Per CMdG p. 12: "probability of sourcing from a given supplier (i.e., the
# extensive margin)". For each (year, group): fraction of (firm x cn8 x partner)
# triplets in the balanced panel that have value > 0.
# -------------------------------------------------------------------------
prob_dt <- d_ne[, .(active = mean(value > 0)),
                by = .(year, group)]

cat("\nProbability of sourcing by group/year:\n")
print(dcast(prob_dt, year ~ group, value.var = "active"))

p_b <- ggplot(prob_dt, aes(x = year, y = active, color = group)) +
  geom_vline(xintercept = 2004.5, linetype = "dashed", color = "grey40") +
  geom_line(linewidth = 0.9) + geom_point(size = 1.6) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  scale_color_manual(values = c("grey40", "steelblue")) +
  labs(title = "(b) Probability of sourcing (extensive margin)",
       x = NULL, y = "P(value > 0 | triplet, year)", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

# -------------------------------------------------------------------------
# Combine panels and save.
# -------------------------------------------------------------------------
p_combined <- (p_a / p_b) +
  plot_annotation(
    title = "CMdG Figure 2 replication: Aggregate import shares and probability of sourcing",
    subtitle = sprintf("Belgium customs panel%s, non-ETS source countries, 2000-2019",
                       ifelse(USE_MOCK, " (MOCK DATA)", "")),
    caption = "Treatment: regulated product x non-ETS source country. Control: unregulated x non-ETS."
  ) &
  theme(plot.title = element_text(size = 12),
        legend.position = "bottom")

fig_dir <- file.path(REPO_DIR, "output", "figures")
tab_dir <- file.path(REPO_DIR, "output", "tables")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

out_fig <- file.path(fig_dir,
                     ifelse(USE_MOCK, "phase2_cmdj_figure2_MOCK.png",
                                       "phase2_cmdj_figure2.png"))
ggsave(out_fig, p_combined, width = 9, height = 8, dpi = 200)
cat("\nFigure saved:", out_fig, "\n")

# Save raw aggregates
out_tab <- file.path(tab_dir,
                     ifelse(USE_MOCK, "phase2_cmdj_figure2_MOCK.csv",
                                       "phase2_cmdj_figure2.csv"))
agg <- merge(share_dt[, .(year, group, share)],
             prob_dt[, .(year, group, prob_active = active)],
             by = c("year", "group"))
fwrite(agg, out_tab)
cat("Table saved:", out_tab, "\n")
