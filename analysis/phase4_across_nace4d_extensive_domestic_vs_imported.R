###############################################################################
# phase4_across_nace4d_extensive_domestic_vs_imported.R
#
# PURPOSE
#   Extensive-margin twin of phase4_across_nace4d_domestic_vs_imported.R.
#   For each year, two outcomes (both over the high-shortage ETS-NACE4d set):
#
#     A) Share of buyers sourcing domestically (B2B) from at least one
#        high-shortage ETS-NACE4d seller; share importing (customs) at
#        least one high-shortage-ETS-NACE4d product. The two are NOT
#        mutually exclusive -- a buyer can be in both.
#
#     B) Mean count of distinct high-shortage ETS-NACE4d sectors per
#        buyer, separately for domestic and imported sources.
#
#   Same ETS-NACE4d definition on both sides, with customs cn8 mapped to
#   NACE4d via cn8_to_nace4d.csv (year-exact + carry-forward fallback).
#
#   Carbon-leakage hypothesis: domestic share/count should fall while
#   imported share/count rises if buyers substitute foreign suppliers
#   for domestic ETS-regulated ones.
#
# OUTPUTS
#   - phase4_across_nace4d_extensive_domestic_vs_imported_share.{png,pdf}
#   - phase4_across_nace4d_extensive_domestic_vs_imported_count.{png,pdf}
#   - phase4_across_nace4d_extensive_domestic_vs_imported.csv
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

YEAR_LO          <- 2005L
YEAR_HI          <- 2022L
PRE_YEARS        <- 2008L:2012L
MIN_FIRM_YRS_PRE <- 2L

# ---------------------------------------------------------------------------
# 1. Define high-shortage ETS-NACE4d set
# ---------------------------------------------------------------------------
cat("Loading firm_exposure for ETS-treated NACE4d set...\n")
load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(vat = as.character(vat),
                                       year = as.integer(year),
                                       nace4d, shortage, total_cost)]
rm(firm_exposure)

fe_pre <- fe[year %in% PRE_YEARS &
             !is.na(shortage) & !is.na(total_cost) & total_cost > 0]
nace4d_shortage <- fe_pre[, .(n_obs_pre     = .N,
                              sum_shortage  = sum(shortage),
                              sum_totalcost = sum(total_cost)), by = nace4d]
nace4d_shortage[, omega_nace4d := sum_shortage / sum_totalcost]
high_set <- nace4d_shortage[n_obs_pre >= MIN_FIRM_YRS_PRE & omega_nace4d > 0,
                            unique(nace4d)]
cat(sprintf("  high-shortage ETS-NACE4d: %d\n", length(high_set)))

# ---------------------------------------------------------------------------
# 2. Domestic side
# ---------------------------------------------------------------------------
cat("\nLoading B2B and annual_accounts...\n")
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
b2b[, is_high := as.integer(!is.na(seller_nace4d) & seller_nace4d %in% high_set)]

# Per (buyer, year): does buyer source domestically from a high-shortage seller?
# How many distinct high-shortage NACE4d sectors do they source from domestically?
dom_by <- b2b[, .(
  dom_any  = max(is_high),
  dom_n    = uniqueN(seller_nace4d[is_high == 1L])
), by = .(buyer, year)]

yr_active_dom <- b2b[, .(n_active_dom = uniqueN(buyer)), by = year]

# ---------------------------------------------------------------------------
# 3. Imported side
# ---------------------------------------------------------------------------
cat("\nLoading customs panel...\n")
ext_path <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
reg_path <- file.path(PROC_DATA, "customs_import_panel_regulated.RData")
if (file.exists(ext_path)) {
  load(ext_path); cat("  extended panel loaded\n")
} else if (file.exists(reg_path)) {
  load(reg_path); cat("  regulated panel (fallback) loaded\n")
} else {
  stop("No customs panel found in PROC_DATA.")
}
panel <- as.data.table(panel)[value > 0,
                              .(buyer = as.character(vat),
                                cn8 = as.character(cn8),
                                year = as.integer(year),
                                value)]

conc <- fread(file.path(REPO_DIR, "data", "concordances", "cn8_to_nace4d.csv"),
              colClasses = c(cn8 = "character", nace4d = "character"))
conc <- conc[!is.na(nace4d) & nace4d != "", .(year = as.integer(year),
                                              cn8, prod_nace4d = nace4d)]
conc_last_year <- max(conc$year)

panel <- merge(panel, conc, by = c("cn8", "year"), all.x = TRUE)
if (any(is.na(panel$prod_nace4d))) {
  conc_recent <- conc[year <= conc_last_year][, .SD[year == max(year)], by = cn8][,
                       .(cn8, prod_nace4d_fb = prod_nace4d)]
  panel <- merge(panel, conc_recent, by = "cn8", all.x = TRUE)
  panel[is.na(prod_nace4d), prod_nace4d := prod_nace4d_fb]
  panel[, prod_nace4d_fb := NULL]
}
panel[, is_high := as.integer(!is.na(prod_nace4d) & prod_nace4d %in% high_set)]

# Per (buyer, year): does buyer import any high-shortage-NACE4d product?
imp_by <- panel[, .(
  imp_any = max(is_high),
  imp_n   = uniqueN(prod_nace4d[is_high == 1L])
), by = .(buyer, year)]

yr_active_imp <- panel[, .(n_active_imp = uniqueN(buyer)), by = year]

# ---------------------------------------------------------------------------
# 4. Combine: union buyer set per year (buyer must be active in EITHER source)
# ---------------------------------------------------------------------------
panel_all <- merge(dom_by, imp_by, by = c("buyer", "year"), all = TRUE)
for (col in c("dom_any", "dom_n", "imp_any", "imp_n")) {
  panel_all[is.na(get(col)), (col) := 0L]
}

yr <- panel_all[, .(
  n_buyers          = uniqueN(buyer),
  share_dom_any     = mean(dom_any),
  share_imp_any     = mean(imp_any),
  mean_dom_n        = mean(dom_n),
  mean_imp_n        = mean(imp_n)
), by = year]
setorder(yr, year)

# Restrict to years covered by both data sources
yr_lo_main <- max(min(dom_by$year), min(imp_by$year))
yr_hi_main <- min(max(dom_by$year), max(imp_by$year))
cat(sprintf("\nOverlapping year range for the figure: %d-%d\n",
            yr_lo_main, yr_hi_main))
yr <- yr[year %between% c(yr_lo_main, yr_hi_main)]

fwrite(yr,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_extensive_domestic_vs_imported.csv"))

cat("\nYear-level summary:\n")
print(yr)

# ---------------------------------------------------------------------------
# 5. Plot A: share-of-buyers (domestic any high vs imported any high)
# ---------------------------------------------------------------------------
plot_A <- melt(yr, id.vars = "year",
               measure.vars = c("share_dom_any", "share_imp_any"),
               variable.name = "side", value.name = "share")
plot_A[, side := factor(side,
                        levels = c("share_dom_any", "share_imp_any"),
                        labels = c("Any domestic high-shortage seller",
                                   "Any imported high-shortage product"))]

cmdg_colors <- c("Any domestic high-shortage seller"   = "#1f3b5b",
                 "Any imported high-shortage product"  = "#b30000")

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
  labs(title    = "Across-NACE4d extensive margin: share of buyers with any high-shortage source",
       subtitle = "Domestic = B2B from a high-shortage ETS-NACE4d seller. Imported = customs import of a high-shortage ETS-NACE4d product. Not mutually exclusive.",
       x = NULL, y = "Share of buyers (active in either source)") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_domestic_vs_imported_share.png"),
       pA, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_domestic_vs_imported_share.pdf"),
       pA, width = 9, height = 5)

# ---------------------------------------------------------------------------
# 6. Plot B: mean count of distinct high-shortage NACE4d per buyer
# ---------------------------------------------------------------------------
plot_B <- melt(yr, id.vars = "year",
               measure.vars = c("mean_dom_n", "mean_imp_n"),
               variable.name = "side", value.name = "count")
plot_B[, side := factor(side,
                        levels = c("mean_dom_n", "mean_imp_n"),
                        labels = c("Domestic distinct high-shortage NACE4d",
                                   "Imported distinct high-shortage NACE4d"))]
side_colors <- c("Domestic distinct high-shortage NACE4d" = "#1f3b5b",
                 "Imported distinct high-shortage NACE4d" = "#b30000")

pB <- ggplot(plot_B, aes(x = year, y = count, color = side, shape = side)) +
  geom_line(linewidth = 0.85) +
  geom_point(size = 1.6) +
  scale_x_continuous(breaks = seq(yr_lo_main, yr_hi_main, by = 2)) +
  scale_y_continuous(limits = c(0, NA)) +
  scale_color_manual(values = side_colors, name = NULL) +
  scale_shape_manual(values = c(16, 17), name = NULL) +
  labs(title    = "Across-NACE4d extensive margin: distinct high-shortage NACE4d per buyer",
       subtitle = "Mean across buyers in the union of domestic+customs activity. Zero-filled for the side with no high-shortage activity.",
       x = NULL, y = "Mean count of distinct high-shortage NACE4d per buyer") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_domestic_vs_imported_count.png"),
       pB, width = 9, height = 5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_extensive_domestic_vs_imported_count.pdf"),
       pB, width = 9, height = 5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
