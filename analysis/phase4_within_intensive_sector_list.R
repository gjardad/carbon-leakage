###############################################################################
# phase4_within_intensive_sector_list.R
#
# PURPOSE
#   Simple two-column table of the seller sectors represented in the
#   within-NACE-4d intensive-margin DiD sample (present-in-2010-14). Each
#   cell is a (buyer, NACE-4d) pair; within a cell, top and bot sellers
#   are by construction in the same NACE-4d, so the "seller sector" is
#   just the cell's NACE-4d.
#
#   Output: sector name (NACE 4-digit, grouped under NACE 2-digit division
#   headers) and number of unique suppliers per sector.
#
# OUTPUTS
#   - phase4_within_intensive_sector_list.tex (longtable)
#   - phase4_within_intensive_sector_list.csv (flat machine copy)
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
})

PRE_WINDOW <- 2010L:2014L
OMEGA_WIN  <- c(2015L, 2016L)

# ---------------------------------------------------------------------------
# NACE Rev 2 labels (covers every code that appears in the sample).
# Add new entries here if the sample expands.
# ---------------------------------------------------------------------------
NACE2D_LABELS <- c(
  "08" = "Other mining and quarrying",
  "10" = "Manufacture of food products",
  "11" = "Manufacture of beverages",
  "13" = "Manufacture of textiles",
  "17" = "Manufacture of paper and paper products",
  "19" = "Manufacture of coke and refined petroleum products",
  "20" = "Manufacture of chemicals and chemical products",
  "22" = "Manufacture of rubber and plastic products",
  "23" = "Manufacture of other non-metallic mineral products",
  "24" = "Manufacture of basic metals",
  "35" = "Electricity, gas, steam and air conditioning supply",
  "42" = "Civil engineering",
  "46" = "Wholesale trade",
  "49" = "Land transport and transport via pipelines",
  "71" = "Architectural and engineering activities; technical testing"
)

NACE4D_LABELS <- c(
  "0811" = "Quarrying of ornamental and building stone, limestone, etc.",
  "0812" = "Operation of gravel and sand pits; mining of clays and kaolin",
  "1031" = "Processing and preserving of potatoes",
  "1039" = "Other processing and preserving of fruit and vegetables",
  "1041" = "Manufacture of oils and fats",
  "1051" = "Operation of dairies and cheese making",
  "1062" = "Manufacture of starches and starch products",
  "1082" = "Manufacture of cocoa, chocolate and sugar confectionery",
  "1089" = "Manufacture of other food products n.e.c.",
  "1105" = "Manufacture of beer",
  "1107" = "Manufacture of soft drinks; bottled waters",
  "1320" = "Weaving of textiles",
  "1393" = "Manufacture of carpets and rugs",
  "1712" = "Manufacture of paper and paperboard",
  "1722" = "Manufacture of household and sanitary paper goods",
  "1920" = "Manufacture of refined petroleum products",
  "2011" = "Manufacture of industrial gases",
  "2012" = "Manufacture of dyes and pigments",
  "2014" = "Manufacture of other organic basic chemicals",
  "2015" = "Manufacture of fertilisers and nitrogen compounds",
  "2016" = "Manufacture of plastics in primary forms",
  "2020" = "Manufacture of pesticides and other agrochemical products",
  "2059" = "Manufacture of other chemical products n.e.c.",
  "2222" = "Manufacture of plastic packing goods",
  "2229" = "Manufacture of other plastic products",
  "2314" = "Manufacture of glass fibres",
  "2332" = "Manufacture of bricks, tiles and construction products in baked clay",
  "2351" = "Manufacture of cement",
  "2352" = "Manufacture of lime and plaster",
  "2365" = "Manufacture of fibre cement",
  "2399" = "Manufacture of other non-metallic mineral products n.e.c.",
  "2443" = "Lead, zinc and tin production",
  "2444" = "Copper production",
  "3511" = "Production of electricity",
  "4211" = "Construction of roads and motorways",
  "4673" = "Wholesale of wood, construction materials and sanitary equipment",
  "4676" = "Wholesale of other intermediate products",
  "4950" = "Transport via pipeline",
  "7112" = "Engineering activities and related technical consultancy"
)

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
cat("Loading data...\n")
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[!is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year),
             sales)]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat    = as.character(vat_ano),
  year   = as.integer(year),
  nace4d = substr(nace5d, 1, 4))]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(vat = as.character(vat),
                                       year, shortage, total_cost)]
rm(firm_exposure)
fe[, omega_sh := ifelse(!is.na(total_cost) & total_cost > 0,
                        pmax(shortage, 0) / total_cost, NA_real_)]

# Attach seller NACE4d (cells are buyer x seller-NACE-4d)
b2b_with_nace <- merge(b2b, aa, by.x = c("seller", "year"), by.y = c("vat", "year"),
                       all.x = TRUE)
setnames(b2b_with_nace, "nace4d", "seller_nace4d")
b2b_with_nace <- b2b_with_nace[!is.na(seller_nace4d) & seller_nace4d != ""]

# ---------------------------------------------------------------------------
# Present-in-2010-14 sample construction (matches phase4_within_intensive_*)
# ---------------------------------------------------------------------------
cat("Building present-in-2010-14 sample...\n")
pre_active <- b2b_with_nace[year %in% PRE_WINDOW,
                            .(pre_sales = sum(sales)),
                            by = .(buyer, seller_nace4d, seller)]
omega_window_active <- b2b_with_nace[year %in% OMEGA_WIN,
                                     .(omega_win_sales = sum(sales)),
                                     by = .(buyer, seller_nace4d, seller)]
pool_pairs <- merge(pre_active, omega_window_active,
                    by = c("buyer", "seller_nace4d", "seller"))

omega_byvat <- fe[year %in% OMEGA_WIN,
                  .(omega_anchor = mean(omega_sh, na.rm = TRUE)),
                  by = vat]
pool_pairs <- merge(pool_pairs, omega_byvat,
                    by.x = "seller", by.y = "vat", all.x = TRUE)
pool_pairs[is.na(omega_anchor), omega_anchor := 0]

cell_summary <- pool_pairs[, .(n = .N,
                               max_omega = max(omega_anchor),
                               min_omega = min(omega_anchor)),
                           by = .(buyer, seller_nace4d)]
cell_ok <- cell_summary[n >= 2L & max_omega > 0 & min_omega < max_omega]
pool <- merge(pool_pairs, cell_ok[, .(buyer, seller_nace4d)],
              by = c("buyer", "seller_nace4d"))
pool[, cell_min_omega := min(omega_anchor), by = .(buyer, seller_nace4d)]

setorder(pool, buyer, seller_nace4d, -omega_anchor, -pre_sales, seller)
pool[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
sample_pairs <- pool[rk == 1L | omega_anchor == cell_min_omega,
                     .(buyer, seller_nace4d, seller)]
cat(sprintf("  Sample: %d unique (buyer, seller) pairs across %d sellers and %d NACE-4d sectors\n",
            nrow(sample_pairs),
            uniqueN(sample_pairs$seller),
            uniqueN(sample_pairs$seller_nace4d)))

# ---------------------------------------------------------------------------
# Aggregate to (NACE 4d) -> unique-seller count, then organise by 2-digit
# ---------------------------------------------------------------------------
by_4d <- sample_pairs[, .(n_suppliers = uniqueN(seller)),
                      by = .(nace4d = seller_nace4d)]
by_4d[, nace2d := substr(nace4d, 1, 2)]
setorder(by_4d, nace2d, -n_suppliers, nace4d)

# A seller can in principle appear in cells with different NACE4d (rare).
# 2-digit "unique suppliers" therefore deduplicates within the division.
by_2d <- sample_pairs[, .(nace2d = substr(seller_nace4d, 1, 2), seller)]
by_2d <- by_2d[, .(n_suppliers_2d = uniqueN(seller)), by = nace2d]
setorder(by_2d, nace2d)

# Total unique sellers (deduplicated across the whole sample)
total_unique <- uniqueN(sample_pairs$seller)

# ---------------------------------------------------------------------------
# Build LaTeX longtable (sector name | unique suppliers)
# ---------------------------------------------------------------------------
cat("Writing LaTeX table...\n")

esc <- function(x) gsub("&", "\\\\&", x, fixed = FALSE)

lines <- c(
  "\\begin{longtable}{lr}",
  paste0("\\caption{Sectoral composition of the suppliers in the within-NACE-4d ",
         "intensive-margin DiD sample. A cell is a (buyer, supplier-NACE-4d) ",
         "pair; within a cell, top and bot sellers share the same NACE-4d, so ",
         "the table covers both sides of the regression simultaneously. ",
         "Counts are unique sellers; 2-digit subtotals deduplicate sellers that ",
         "appear in cells from more than one 4-digit within the same division. ",
         "Sectors sorted by 2-digit division; within each division, 4-digit ",
         "sectors are sorted by supplier count descending.}",
         "\\label{tab:phase4_within_intensive_sector_list} \\\\"),
  "\\toprule",
  "Sector & Unique suppliers \\\\",
  "\\midrule",
  "\\endfirsthead",
  "\\toprule",
  "Sector & Unique suppliers \\\\",
  "\\midrule",
  "\\endhead",
  "\\midrule",
  "\\multicolumn{2}{r}{\\textit{continued on next page}} \\\\",
  "\\endfoot",
  "\\bottomrule",
  "\\endlastfoot"
)

divisions <- unique(by_4d$nace2d)
for (d in divisions) {
  d_label <- NACE2D_LABELS[d]
  if (is.na(d_label)) d_label <- "(label missing)"
  d_subtotal <- by_2d[nace2d == d, n_suppliers_2d]
  lines <- c(lines,
    sprintf("\\addlinespace[2pt]\\textbf{%s --- %s} & \\textbf{%d} \\\\",
            d, esc(d_label), d_subtotal))
  rows4 <- by_4d[nace2d == d]
  for (i in seq_len(nrow(rows4))) {
    code <- rows4$nace4d[i]
    lab  <- NACE4D_LABELS[code]
    if (is.na(lab)) lab <- "(label missing)"
    lines <- c(lines,
      sprintf("\\hspace{1em}%s --- %s & %d \\\\",
              code, esc(lab), rows4$n_suppliers[i]))
  }
}
lines <- c(lines,
  "\\midrule",
  sprintf("\\textbf{Total (unique sellers, sample-wide)} & \\textbf{%d} \\\\",
          total_unique),
  "\\end{longtable}")

writeLines(lines, file.path(OUTPUT_TAB,
                            "phase4_within_intensive_sector_list.tex"))

# Flat CSV copy
out_csv <- merge(by_4d,
                 data.table(nace2d  = names(NACE2D_LABELS),
                            nace2d_label = unname(NACE2D_LABELS)),
                 by = "nace2d", all.x = TRUE)
out_csv[, nace4d_label := NACE4D_LABELS[nace4d]]
setcolorder(out_csv, c("nace2d", "nace2d_label", "nace4d", "nace4d_label",
                       "n_suppliers"))
setorder(out_csv, nace2d, -n_suppliers, nace4d)
fwrite(out_csv, file.path(OUTPUT_TAB,
                          "phase4_within_intensive_sector_list.csv"))

cat("\nDone.\n")
cat("  ", file.path(OUTPUT_TAB, "phase4_within_intensive_sector_list.tex"), "\n")
cat("  ", file.path(OUTPUT_TAB, "phase4_within_intensive_sector_list.csv"), "\n")
