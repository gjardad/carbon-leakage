###############################################################################
# phase4_intl_extensive_margin.R
#
# PURPOSE
#   International reallocation margin -- extensive side. CMdG (2024) Figure 2
#   panel (b) for Belgium: probability of sourcing (extensive margin) by
#   (product-regulation x source-country-ETS-status) cell, by year.
#
#   The customs panel is balanced over (firm x CN8 x partner) triplets ever
#   observed in the sample window, with zero-fill for non-active years (see
#   phase2_build_customs_panel.R). For each (year, cell), the extensive-margin
#   probability is:
#
#       prob_{c,t} = mean( 1[value_{f,p,i,t} > 0]  |  (f,p,i) classified to cell c )
#
#   Cells (defined at firm x CN8 x partner x year):
#       cell 1  ETS-Regulated      = is_regulated_product==1 & is_non_ets_country==0
#       cell 2  Non-ETS-Regulated  = is_regulated_product==1 & is_non_ets_country==1   (treated -- the leakage cell)
#       cell 3  ETS-Unregulated    = is_regulated_product==0 & is_non_ets_country==0   (computed; not plotted)
#       cell 4  Non-ETS-Unregulated= is_regulated_product==0 & is_non_ets_country==1   (control)
#
#   Replicates CMdG Figure 2 panel (b). Plot shows 3 lines per CMdG.
#
# INPUTS
#   ${PROC_DATA}/customs_import_panel_extended.RData (preferred, 2000-2022)
#   ${PROC_DATA}/customs_import_panel_regulated.RData (fallback, 2000-2019)
#
# OUTPUTS
#   ${OUTPUT_FIG}/phase4_intl_extensive_margin.{png,pdf}
#   ${OUTPUT_TAB}/phase4_intl_extensive_margin.csv
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

# ---------------------------------------------------------------------------
# 1. Load customs panel (prefer extended)
# ---------------------------------------------------------------------------
ext_path <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
reg_path <- file.path(PROC_DATA, "customs_import_panel_regulated.RData")

if (file.exists(ext_path)) {
  load(ext_path); cat("Loaded extended customs panel (", ext_path, ").\n", sep = "")
} else if (file.exists(reg_path)) {
  load(reg_path); cat("Extended panel not found; fell back to regulated panel (",
                      reg_path, ").\n", sep = "")
} else {
  stop("Neither extended nor regulated customs panel found in PROC_DATA.")
}
panel <- as.data.table(panel)
cat(sprintf("Panel rows: %d, year range %d-%d\n",
            nrow(panel), min(panel$year), max(panel$year)))

# Drop years that have no positive-value flows. The country_ets_status
# concordance starts in 2005, but more importantly the local-1 downsampled
# panel can have entirely-zero years (e.g. 2019) due to sampling. On RMD
# with the full extended panel this filter is a no-op for the years 2000-2022.
years_with_data <- panel[value > 0, sort(unique(year))]
panel <- panel[year %in% years_with_data]
cat(sprintf("After dropping zero-activity years: %d rows, years %d-%d\n",
            nrow(panel), min(panel$year), max(panel$year)))

# ---------------------------------------------------------------------------
# 2. Cell classification (time-invariant partner ETS flag)
# ---------------------------------------------------------------------------
# CMdG Figure 2 uses time-invariant country classification: a partner is
# "ETS" if it is *ever* in the EU ETS (i.e., has is_non_ets_country == 0 in
# any sample year). The panel's year-specific flag is 1 for all countries
# pre-2005 (because country_ets_status.csv starts in 2005), so we override
# with the partner-level ever-ETS flag.
partner_ets <- panel[, .(partner_ever_non_ets = as.integer(min(is_non_ets_country) == 1L)),
                     by = partner_iso2]
panel <- merge(panel, partner_ets, by = "partner_iso2", all.x = TRUE)

panel[, cell := fifelse(is_regulated_product == 1L & partner_ever_non_ets == 0L, "ETS-Regulated",
                fifelse(is_regulated_product == 1L & partner_ever_non_ets == 1L, "Non-ETS-Regulated",
                fifelse(is_regulated_product == 0L & partner_ever_non_ets == 0L, "ETS-Unregulated",
                                                                                 "Non-ETS-Unregulated")))]

cell_levels <- c("Non-ETS-Regulated", "ETS-Regulated",
                 "Non-ETS-Unregulated", "ETS-Unregulated")
panel[, cell := factor(cell, levels = cell_levels)]

# ---------------------------------------------------------------------------
# 3. Per-(year, cell) extensive-margin probability
# ---------------------------------------------------------------------------
ext <- panel[, .(n_cells   = .N,
                 n_active  = sum(value > 0),
                 prob      = mean(value > 0)),
             by = .(year, cell)]
setorder(ext, year, cell)

# Ensure full year x cell grid
year_grid <- CJ(year = sort(unique(panel$year)),
                cell = factor(cell_levels, levels = cell_levels))
ext <- merge(year_grid, ext, by = c("year", "cell"), all.x = TRUE)
ext[is.na(prob), prob := 0]
ext[is.na(n_cells), n_cells := 0L]
ext[is.na(n_active), n_active := 0L]

cat("\nExtensive-margin probability by year x cell:\n")
print(dcast(ext, year ~ cell, value.var = "prob"))

# ---------------------------------------------------------------------------
# 4. Save CSV (all 4 cells)
# ---------------------------------------------------------------------------
out_tab <- file.path(OUTPUT_TAB, "phase4_intl_extensive_margin.csv")
fwrite(ext, out_tab)
cat("\nTable saved:", out_tab, "\n")

# ---------------------------------------------------------------------------
# 5. Plot (3 lines, CMdG-style)
# ---------------------------------------------------------------------------
plot_dt <- ext[cell %in% c("Non-ETS-Regulated", "ETS-Regulated", "Non-ETS-Unregulated")]
plot_dt[, cell := droplevels(cell)]

cmdg_colors  <- c("Non-ETS-Regulated"   = "#1f3b5b",
                  "ETS-Regulated"       = "#7a8da0",
                  "Non-ETS-Unregulated" = "#a9c5d8")
cmdg_shapes  <- c("Non-ETS-Regulated"   = 16,
                  "ETS-Regulated"       = 17,
                  "Non-ETS-Unregulated" = 18)

p <- ggplot(plot_dt, aes(x = year, y = prob, color = cell, shape = cell)) +
  geom_line(linewidth = 0.6, alpha = 0.7) +
  geom_point(size = 2.4) +
  scale_x_continuous(breaks = seq(2000, 2022, by = 5)) +
  scale_y_continuous(labels = scales::number_format(accuracy = 0.01)) +
  scale_color_manual(values = cmdg_colors, name = NULL) +
  scale_shape_manual(values = cmdg_shapes, name = NULL) +
  labs(title    = "International reallocation -- extensive margin (CMdG Fig. 2b)",
       subtitle = "Probability of sourcing (mean of 1[value > 0]) by (product, source-country) cell. Belgium customs panel.",
       x = NULL, y = "Import probability") +
  theme_minimal(base_size = 11) +
  theme(legend.position  = "bottom",
        panel.grid.minor = element_blank())

out_png <- file.path(OUTPUT_FIG, "phase4_intl_extensive_margin.png")
out_pdf <- file.path(OUTPUT_FIG, "phase4_intl_extensive_margin.pdf")
ggsave(out_png, p, width = 8, height = 5, dpi = 200)
ggsave(out_pdf, p, width = 8, height = 5)
cat("Figure saved:", out_png, "\n")
cat("Figure saved:", out_pdf, "\n")

cat("\nDone.\n")
