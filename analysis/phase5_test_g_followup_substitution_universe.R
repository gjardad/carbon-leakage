###############################################################################
# phase5_test_g_followup_substitution_universe.R
#
# Follow-up to Test G's near-empty filter result (29 cells max even on full RMD
# B2B). Question: where does the universe shrink to nothing? Is it because
# (a) the set of NACE 4d sectors with any ETS-treated firm is narrow,
# (b) buyers don't typically buy from multiple firms within the same NACE 4d, or
# (c) buyers DO buy from multiple firms in the same NACE 4d, but rarely with
#     an ETS-treated firm among them?
#
# THREE COUNTS:
#
#   (1) "Treated NACE 4d set" -- distinct seller_NACE4d sectors that have at
#       least one ETS-treated firm anywhere in the panel (regardless of
#       whether that firm has ever supplied any specific buyer).
#
#   (2) Buyers with >= 2 suppliers in the same NACE 4d, restricted to the
#       treated NACE 4d set. The buyer counts even if 0 of its suppliers in
#       that NACE 4d are ETS-treated.
#       (= buyers for whom feasibility-of-substitution is structurally
#        possible in some sector that contains an ETS firm.)
#
#   (3) Buyers with >= 2 suppliers in the same NACE 4d, restricted to the
#       treated NACE 4d set, AND >= 1 of those suppliers is ETS-treated.
#       (= buyers in the n_ets_sellers >= 2 filter cells of Test G if we
#        relaxed n_ets_sellers >= 1 -- this is what Test G's
#        n_ets_sellers >= 2 demands all-ETS, but here we ask about the
#        "at least one ETS supplier alongside other suppliers" universe.)
#
# Counts at the (buyer, year) level and at the unique-buyer level.
#
# Project convention: use selected_sample versions, not raw .dta files.
#
# Output:
#   output/tables/phase5_test_g_followup_substitution_universe.csv
###############################################################################

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)

# ---------------------------------------------------------------------------
# 1. Load B2B (selected sample), Annual Accounts (selected sample), and EUTL
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)[, .(seller = vat_i_ano,
                                                  buyer  = vat_j_ano,
                                                  year,
                                                  corr_sales = corr_sales_ij)]
rm(df_b2b_selected_sample)
b2b[, year := as.integer(year)]
b2b <- b2b[!is.na(corr_sales) & corr_sales > 0]
cat(sprintf("B2B active rows: %d\n", nrow(b2b)))

load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_more_selected_sample)[
  , .(vat = vat_ano, year, nace5d)]
rm(df_annual_accounts_more_selected_sample)
aa[, year   := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa <- unique(aa[, .(vat, year, nace4d)])

# Seller NACE 4d.
seller_nace <- copy(aa); setnames(seller_nace,
  c("vat", "year", "nace4d"),
  c("seller", "year", "seller_nace4d"))
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]

# ETS firm flag.
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

cat(sprintf("Distinct sellers in B2B: %d\n", uniqueN(b2b$seller)))
cat(sprintf("Distinct buyers in B2B:  %d\n", uniqueN(b2b$buyer)))
cat(sprintf("Distinct ETS sellers in B2B: %d\n",
            uniqueN(b2b[seller_is_ets == 1L]$seller)))

# ---------------------------------------------------------------------------
# COUNT 1 -- "Treated NACE 4d set": NACE 4d sectors with >= 1 ETS firm
# ---------------------------------------------------------------------------
treated_nace4d <- unique(b2b[seller_is_ets == 1L]$seller_nace4d)
cat(sprintf("\n[1] Treated NACE 4d sectors (>=1 ETS firm anywhere): %d\n",
            length(treated_nace4d)))

# All NACE 4d in B2B for context.
all_nace4d <- unique(b2b$seller_nace4d)
cat(sprintf("    Total seller NACE 4d sectors in B2B: %d\n", length(all_nace4d)))
cat(sprintf("    Share of NACE 4d sectors that are 'treated': %.1f%%\n",
            100 * length(treated_nace4d) / length(all_nace4d)))

# ---------------------------------------------------------------------------
# Restrict B2B to suppliers in treated NACE 4d sectors
# ---------------------------------------------------------------------------
b2b_t <- b2b[seller_nace4d %in% treated_nace4d]
cat(sprintf("    B2B rows with seller in treated NACE 4d: %d\n", nrow(b2b_t)))

# ---------------------------------------------------------------------------
# COUNT 2 -- buyers with >= 2 suppliers in same NACE 4d (in treated set)
# ---------------------------------------------------------------------------
# (buyer, NACE 4d, year) cell: distinct sellers active.
cell_2 <- b2b_t[, .(n_sellers      = uniqueN(seller),
                    n_ets_sellers  = uniqueN(seller[seller_is_ets == 1L])),
                by = .(buyer, seller_nace4d, year)]

# A buyer-year passes if it has at least one (NACE 4d) cell with >= 2 sellers.
buyer_year_pass2 <- unique(cell_2[n_sellers >= 2L, .(buyer, year)])
unique_buyer_pass2 <- unique(buyer_year_pass2$buyer)

cat(sprintf("\n[2] Buyers with >=2 suppliers in same NACE 4d (treated NACE 4d set):\n"))
cat(sprintf("    (buyer, year) cells passing: %d\n", nrow(buyer_year_pass2)))
cat(sprintf("    Distinct buyers across all years: %d\n", length(unique_buyer_pass2)))
cat(sprintf("    Share of all B2B buyers: %.1f%%\n",
            100 * length(unique_buyer_pass2) / uniqueN(b2b$buyer)))

# ---------------------------------------------------------------------------
# COUNT 3 -- buyers with >= 2 suppliers AND >= 1 of them ETS-treated
# ---------------------------------------------------------------------------
buyer_year_pass3 <- unique(cell_2[n_sellers >= 2L & n_ets_sellers >= 1L,
                                   .(buyer, year)])
unique_buyer_pass3 <- unique(buyer_year_pass3$buyer)

cat(sprintf("\n[3] Buyers with >=2 suppliers in same NACE 4d AND >=1 ETS-treated:\n"))
cat(sprintf("    (buyer, year) cells passing: %d\n", nrow(buyer_year_pass3)))
cat(sprintf("    Distinct buyers across all years: %d\n", length(unique_buyer_pass3)))
cat(sprintf("    Share of pass-(2) buyers: %.1f%%\n",
            100 * length(unique_buyer_pass3) / max(length(unique_buyer_pass2), 1L)))
cat(sprintf("    Share of all B2B buyers:   %.1f%%\n",
            100 * length(unique_buyer_pass3) / uniqueN(b2b$buyer)))

# ---------------------------------------------------------------------------
# Stratify counts (2) and (3) by year, to see post-shock evolution
# ---------------------------------------------------------------------------
yearly <- merge(
  buyer_year_pass2[, .(n_buyers_pass2 = uniqueN(buyer)), by = year],
  buyer_year_pass3[, .(n_buyers_pass3 = uniqueN(buyer)), by = year],
  by = "year", all = TRUE)
setorder(yearly, year)
cat("\nYearly counts (treated NACE 4d set):\n")
print(yearly)

# ---------------------------------------------------------------------------
# Stratify count (3) -- where we restrict to >=2 ETS sellers (Test G's filter)
# ---------------------------------------------------------------------------
buyer_year_pass3_two_ets <- unique(cell_2[n_sellers >= 2L & n_ets_sellers >= 2L,
                                           .(buyer, year)])
unique_buyer_pass3_two_ets <- unique(buyer_year_pass3_two_ets$buyer)

cat(sprintf("\n[3'] (Test G's exact filter) Buyers with >=2 ETS-treated suppliers in same NACE 4d:\n"))
cat(sprintf("     (buyer, year) cells passing: %d\n",
            nrow(buyer_year_pass3_two_ets)))
cat(sprintf("     Distinct buyers across all years: %d\n",
            length(unique_buyer_pass3_two_ets)))

# ---------------------------------------------------------------------------
# Summary table
# ---------------------------------------------------------------------------
summary_dt <- data.table(
  count = c("[1] # NACE 4d sectors w/ >=1 ETS firm",
            "[1b] Total NACE 4d sectors in B2B",
            "[2] (buyer-year) cells: >=2 suppliers in same NACE 4d (treated set)",
            "[2b] Distinct buyers in [2]",
            "[3] (buyer-year) cells: [2] AND >=1 ETS supplier",
            "[3b] Distinct buyers in [3]",
            "[3'] (buyer-year) cells: [2] AND >=2 ETS suppliers (Test G's filter)",
            "[3'b] Distinct buyers in [3']",
            "Total B2B buyers (universe)"),
  n     = c(length(treated_nace4d),
            length(all_nace4d),
            nrow(buyer_year_pass2),
            length(unique_buyer_pass2),
            nrow(buyer_year_pass3),
            length(unique_buyer_pass3),
            nrow(buyer_year_pass3_two_ets),
            length(unique_buyer_pass3_two_ets),
            uniqueN(b2b$buyer))
)

cat("\n=== SUMMARY ===\n")
print(summary_dt)
fwrite(summary_dt,
       file.path(OUTPUT_TAB, "phase5_test_g_followup_substitution_universe.csv"))
fwrite(yearly,
       file.path(OUTPUT_TAB, "phase5_test_g_followup_substitution_universe_yearly.csv"))

cat("\nSaved tables.\n")
cat("Done.\n")
