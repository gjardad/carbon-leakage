###############################################################################
# phase4_across_nace4d_domestic_vs_imported.R
#
# PURPOSE
#   Heterogeneity #4 on across-NACE4d intensive margin: for the same set of
#   ETS-treated NACE4d sectors, split buyer expenditure into domestic (B2B)
#   vs imported (customs) and plot the share evolution. The carbon-leakage-
#   via-imports hypothesis predicts that the imported share of ETS-NACE4d
#   spending rises (and the domestic share falls) as EUA prices rise.
#
#   Sector definition (consistent with phase4_across_nace4d_intensive*.R):
#     ETS-NACE4d = any NACE4d containing >= 1 in-sample EUTL-matched firm
#     (i.e. NACE4d appearing in firm_exposure).
#
#   Customs HS6/CN8 codes are mapped to NACE4d via cn8_to_nace4d.csv (year-
#   specific where available; we fall back to the last year of the
#   concordance for customs years that exceed its coverage).
#
#   Two views are reported:
#     (A) "Within ETS spending": share of (domestic_ets + imported_ets) that
#         is domestic vs imported. Sums to 1 within ETS spending. Direct
#         leakage-via-imports test.
#     (B) "Of total spending": share of (domestic + imported) that is
#         domestic-ets, imported-ets, or non-ETS-mixed. Provides level context.
#
#   Aggregation = sum/sum (CdGM-style), matching phase4_intl_intensive_margin.R.
#
# OUTPUTS
#   - phase4_across_nace4d_domestic_vs_imported.{png,pdf}      (view A)
#   - phase4_across_nace4d_domestic_vs_imported_of_total.{png,pdf} (view B)
#   - phase4_across_nace4d_domestic_vs_imported.csv
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

YEAR_LO <- 2005L
YEAR_HI <- 2022L

# ---------------------------------------------------------------------------
# 1. ETS-treated NACE4d set
# ---------------------------------------------------------------------------
cat("Loading firm_exposure for ETS-treated NACE4d set...\n")
load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
ets_nace4d <- unique(as.data.table(firm_exposure)$nace4d)
ets_nace4d <- ets_nace4d[!is.na(ets_nace4d) & ets_nace4d != ""]
rm(firm_exposure)
cat(sprintf("  ETS-treated NACE4d: %d\n", length(ets_nace4d)))

# ---------------------------------------------------------------------------
# 2. Domestic side (B2B aggregated by buyer-year-ETS-flag)
# ---------------------------------------------------------------------------
cat("\nLoading B2B...\n")
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year),
             sales)]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano),
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b[, is_ets := as.integer(!is.na(seller_nace4d) & seller_nace4d %in% ets_nace4d)]

domestic <- b2b[, .(
  domestic_ets = sum(sales * is_ets),
  domestic_non = sum(sales * (1L - is_ets))
), by = .(buyer = buyer, year)]

cat(sprintf("  domestic buyer-year rows: %d\n", nrow(domestic)))

# ---------------------------------------------------------------------------
# 3. Imported side (customs aggregated by buyer-year-ETS-flag)
# ---------------------------------------------------------------------------
cat("\nLoading customs panel...\n")
load(file.path(PROC_DATA, "customs_import_panel_regulated.RData"))
panel <- as.data.table(panel)[value > 0,
                              .(buyer = as.character(vat),
                                cn8 = as.character(cn8),
                                year = as.integer(year),
                                value)]
cat(sprintf("  customs rows (value>0): %d, year range %d-%d\n",
            nrow(panel), min(panel$year), max(panel$year)))

cat("Loading cn8 -> nace4d concordance...\n")
conc <- fread(file.path(REPO_DIR, "data", "concordances", "cn8_to_nace4d.csv"),
              colClasses = c(cn8 = "character", nace4d = "character"))
conc <- conc[!is.na(nace4d) & nace4d != "", .(year = as.integer(year),
                                              cn8, prod_nace4d = nace4d)]
# Customs panel may go past concordance year range -> fall back to last year.
conc_last_year <- max(conc$year)
cat(sprintf("  concordance year range %d-%d (fallback for >%d uses %d)\n",
            min(conc$year), conc_last_year, conc_last_year, conc_last_year))

# Year-exact merge first, then carry-forward fallback for unmatched rows.
panel <- merge(panel, conc, by = c("cn8", "year"), all.x = TRUE)
miss <- panel[is.na(prod_nace4d)]
if (nrow(miss) > 0) {
  conc_recent <- conc[year <= conc_last_year]
  conc_recent <- conc_recent[, .SD[year == max(year)], by = cn8][,
                              .(cn8, prod_nace4d_fb = prod_nace4d)]
  panel <- merge(panel, conc_recent, by = "cn8", all.x = TRUE)
  panel[is.na(prod_nace4d), prod_nace4d := prod_nace4d_fb]
  panel[, prod_nace4d_fb := NULL]
}
cat(sprintf("  customs rows with NACE4d mapping: %d / %d (%.1f%%)\n",
            sum(!is.na(panel$prod_nace4d)), nrow(panel),
            100 * mean(!is.na(panel$prod_nace4d))))

panel[, is_ets := as.integer(!is.na(prod_nace4d) & prod_nace4d %in% ets_nace4d)]

imported <- panel[, .(
  imported_ets = sum(value * is_ets),
  imported_non = sum(value * (1L - is_ets))
), by = .(buyer, year)]
cat(sprintf("  imported buyer-year rows: %d\n", nrow(imported)))

# ---------------------------------------------------------------------------
# 4. Outer-join: full buyer-year panel (zero-fill missing side)
# ---------------------------------------------------------------------------
panel_all <- merge(domestic, imported, by = c("buyer", "year"), all = TRUE)
for (col in c("domestic_ets", "domestic_non", "imported_ets", "imported_non")) {
  panel_all[is.na(get(col)), (col) := 0]
}

# Restrict to years covered by both data sources for the main plot
yr_lo_main <- max(min(domestic$year), min(imported$year))
yr_hi_main <- min(max(domestic$year), max(imported$year))
cat(sprintf("\nOverlapping year range for the figure: %d-%d\n",
            yr_lo_main, yr_hi_main))

# ---------------------------------------------------------------------------
# 5. Aggregate (sum/sum) by year
# ---------------------------------------------------------------------------
agg <- panel_all[year %between% c(yr_lo_main, yr_hi_main),
                 .(domestic_ets = sum(domestic_ets),
                   domestic_non = sum(domestic_non),
                   imported_ets = sum(imported_ets),
                   imported_non = sum(imported_non)),
                 by = year]
agg[, total           := domestic_ets + domestic_non + imported_ets + imported_non]
agg[, total_ets       := domestic_ets + imported_ets]
agg[, share_dom_of_ets := domestic_ets / total_ets]
agg[, share_imp_of_ets := imported_ets / total_ets]
agg[, share_dom_ets_of_total := domestic_ets / total]
agg[, share_imp_ets_of_total := imported_ets / total]
agg[, share_dom_non_of_total := domestic_non / total]
agg[, share_imp_non_of_total := imported_non / total]
setorder(agg, year)

fwrite(agg,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_domestic_vs_imported.csv"))

cat("\nAggregate shares (within ETS spending):\n")
print(agg[, .(year, share_dom_of_ets = round(share_dom_of_ets, 3),
              share_imp_of_ets = round(share_imp_of_ets, 3))])

# ---------------------------------------------------------------------------
# 6. Plot A: within-ETS-spending domestic vs imported (the leakage test)
# ---------------------------------------------------------------------------
plot_A <- melt(agg, id.vars = "year",
               measure.vars = c("share_dom_of_ets", "share_imp_of_ets"),
               variable.name = "side", value.name = "share")
plot_A[, side := factor(side,
                        levels = c("share_dom_of_ets", "share_imp_of_ets"),
                        labels = c("Domestic (B2B from ETS-NACE4d sellers)",
                                   "Imported (customs imports of ETS-NACE4d products)"))]

cmdg_colors <- c("Domestic (B2B from ETS-NACE4d sellers)"           = "#1f3b5b",
                 "Imported (customs imports of ETS-NACE4d products)" = "#b30000")

base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom")

pA <- ggplot(plot_A, aes(x = year, y = share, color = side, shape = side)) +
  geom_line(linewidth = 0.85) +
  geom_point(size = 1.6) +
  scale_x_continuous(breaks = seq(yr_lo_main, yr_hi_main, by = 2)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = cmdg_colors, name = NULL) +
  scale_shape_manual(values = c(16, 17), name = NULL) +
  labs(title    = "Domestic vs imported share of ETS-NACE4d expenditure",
       subtitle = "Within total spend on ETS-NACE4d (B2B + customs). Same NACE4d set on both sides.",
       x = NULL, y = "Share of ETS-NACE4d expenditure") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_domestic_vs_imported.png"),
       pA, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_domestic_vs_imported.pdf"),
       pA, width = 9, height = 5)

# ---------------------------------------------------------------------------
# 7. Plot B: of-total composition (4 stacked components)
# ---------------------------------------------------------------------------
plot_B <- melt(agg, id.vars = "year",
               measure.vars = c("share_dom_ets_of_total",
                                "share_imp_ets_of_total",
                                "share_dom_non_of_total",
                                "share_imp_non_of_total"),
               variable.name = "cell", value.name = "share")
plot_B[, cell := factor(cell,
                        levels = c("share_dom_ets_of_total",
                                   "share_imp_ets_of_total",
                                   "share_dom_non_of_total",
                                   "share_imp_non_of_total"),
                        labels = c("Domestic ETS-NACE4d",
                                   "Imported ETS-NACE4d",
                                   "Domestic non-ETS",
                                   "Imported non-ETS"))]
cell_colors <- c("Domestic ETS-NACE4d" = "#1f3b5b",
                 "Imported ETS-NACE4d" = "#b30000",
                 "Domestic non-ETS"    = "#7a8da0",
                 "Imported non-ETS"    = "#a9c5d8")

pB <- ggplot(plot_B, aes(x = year, y = share, fill = cell)) +
  geom_area(alpha = 0.85) +
  scale_x_continuous(breaks = seq(yr_lo_main, yr_hi_main, by = 2),
                     expand = expansion(0)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::percent_format(accuracy = 1),
                     expand = expansion(0)) +
  scale_fill_manual(values = cell_colors, name = NULL) +
  labs(title    = "Decomposition of buyer total spend (domestic B2B + customs imports)",
       subtitle = "Aggregate sum/sum across buyer-years. Same NACE4d set on both sides.",
       x = NULL, y = "Share of total expenditure") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_domestic_vs_imported_of_total.png"),
       pB, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_domestic_vs_imported_of_total.pdf"),
       pB, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
