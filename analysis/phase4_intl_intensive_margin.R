###############################################################################
# phase4_intl_intensive_margin.R
#
# PURPOSE
#   International reallocation margin -- intensive side. CMdG (2024) Figure 2
#   panel (a) for Belgium: aggregate import share by (product-regulation x
#   source-country-ETS-status) cell, by year.
#
#   For each (firm f, product p, source country i, year t) row in the customs
#   import panel, the row is classified into one of four cells:
#       cell 1  ETS-Regulated      = is_regulated_product==1 & is_non_ets_country==0
#       cell 2  Non-ETS-Regulated  = is_regulated_product==1 & is_non_ets_country==1   (treated -- the leakage cell)
#       cell 3  ETS-Unregulated    = is_regulated_product==0 & is_non_ets_country==0   (implicit; not plotted)
#       cell 4  Non-ETS-Unregulated= is_regulated_product==0 & is_non_ets_country==1   (control)
#
#   Per-year aggregate share:
#       share_{c,t} = sum_{f,p,i in cell c} value_{f,p,i,t}
#                   / sum_{f,p,i}          value_{f,p,i,t}
#
#   Replicates CMdG Figure 2 panel (a). Plot shows 3 lines (ETS-Regulated,
#   Non-ETS-Regulated, Non-ETS-Unregulated) per CMdG. The ETS-Unregulated cell
#   is computed and saved in the CSV but not drawn (it is the implicit fourth
#   that closes the four shares to 1).
#
# INPUTS
#   ${PROC_DATA}/customs_import_panel_extended.RData (preferred, 2000-2022)
#   ${PROC_DATA}/customs_import_panel_regulated.RData (fallback, 2000-2019)
#
# OUTPUTS
#   ${OUTPUT_FIG}/phase4_intl_intensive_margin.{png,pdf}
#   ${OUTPUT_TAB}/phase4_intl_intensive_margin.csv
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
# 2. Cell classification (4 cells; 3 plotted)
# ---------------------------------------------------------------------------
# CMdG Figure 2 uses time-invariant country classification: a partner is
# "ETS" if it is *ever* in the EU ETS (i.e., has is_non_ets_country == 0 in
# any sample year). The panel as built carries year-specific is_non_ets_country
# which is 1 for ALL countries pre-2005 (because country_ets_status.csv only
# starts in 2005), so direct use of the year-specific flag would mechanically
# put every pre-2005 row into the Non-ETS cells. We override with the
# partner-level ever-ETS flag.
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
# 3. Aggregate share per (year, cell): sum_value_in_cell / sum_value_in_year
# ---------------------------------------------------------------------------
agg <- panel[, .(value = sum(value, na.rm = TRUE)), by = .(year, cell)]
agg[, total := sum(value), by = year]
agg[, share := value / total]
setorder(agg, year, cell)

# Ensure all 4 cells present every year (zero-fill if a cell is empty)
year_grid <- CJ(year = sort(unique(panel$year)),
                cell = factor(cell_levels, levels = cell_levels))
agg <- merge(year_grid, agg, by = c("year", "cell"), all.x = TRUE)
agg[is.na(value), value := 0]
agg[is.na(share), share := 0]

cat("\nAggregate share by year x cell:\n")
print(dcast(agg, year ~ cell, value.var = "share"))

# ---------------------------------------------------------------------------
# 4. Save CSV (all 4 cells)
# ---------------------------------------------------------------------------
out_tab <- file.path(OUTPUT_TAB, "phase4_intl_intensive_margin.csv")
fwrite(agg[, .(year, cell, value, total_year = total, share)], out_tab)
cat("\nTable saved:", out_tab, "\n")

# ---------------------------------------------------------------------------
# 5. Plot (3 lines, CMdG-style)
# ---------------------------------------------------------------------------
plot_dt <- agg[cell %in% c("Non-ETS-Regulated", "ETS-Regulated", "Non-ETS-Unregulated")]
plot_dt[, cell := droplevels(cell)]

# CMdG palette: dark navy (treated), steel-grey (ETS-Reg control), pale blue (Non-ETS-Unreg control).
cmdg_colors  <- c("Non-ETS-Regulated"   = "#1f3b5b",
                  "ETS-Regulated"       = "#7a8da0",
                  "Non-ETS-Unregulated" = "#a9c5d8")
cmdg_shapes  <- c("Non-ETS-Regulated"   = 16,   # filled circle
                  "ETS-Regulated"       = 17,   # filled triangle
                  "Non-ETS-Unregulated" = 18)   # filled diamond

p <- ggplot(plot_dt, aes(x = year, y = share, color = cell, shape = cell)) +
  geom_line(linewidth = 0.6, alpha = 0.7) +
  geom_point(size = 2.4) +
  scale_x_continuous(breaks = seq(2000, 2022, by = 5)) +
  scale_y_continuous(labels = scales::number_format(accuracy = 0.1)) +
  scale_color_manual(values = cmdg_colors, name = NULL) +
  scale_shape_manual(values = cmdg_shapes, name = NULL) +
  labs(title    = "International reallocation -- intensive margin (CMdG Fig. 2a)",
       subtitle = "Aggregate import share by (product, source-country) cell. Belgium customs panel.",
       x = NULL, y = "Import share") +
  theme_minimal(base_size = 11) +
  theme(legend.position  = "bottom",
        panel.grid.minor = element_blank())

out_png <- file.path(OUTPUT_FIG, "phase4_intl_intensive_margin.png")
out_pdf <- file.path(OUTPUT_FIG, "phase4_intl_intensive_margin.pdf")
ggsave(out_png, p, width = 8, height = 5, dpi = 200)
ggsave(out_pdf, p, width = 8, height = 5)
cat("Figure saved:", out_png, "\n")
cat("Figure saved:", out_pdf, "\n")

cat("\nDone.\n")
