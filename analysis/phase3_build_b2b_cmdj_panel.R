# phase3_build_b2b_cmdj_panel.R
#
# Build the regulated-intensive B2B panel for the Phase 3 CMdG replication
# (the novel Belgian contribution: domestic supplier switching).
#
# Conceptual mapping from Phase 2 customs to Phase 3 B2B:
#   Phase 2: firm × imported CN8 × source country × year.
#   Phase 3: buyer × seller × year. The "country" dimension collapses to
#            seller-firm, and the "regulated product" dimension collapses to
#            "seller produces in a regulated NACE 2d sector."
#
# Treatment maps as:
#   Phase 2: regulated × non-ETS-country (leakage to non-ETS sources).
#   Phase 3: regulated-NACE × ETS-seller (treatment cell -- domestic ETS sellers
#            in regulated sectors are the ones whose costs rose).
#
# Per CMdG_REPLICATION.md p. 197-225:
#   y_{j,b,t} ~ TREAT_j × phase + FE
#   TREAT_j  = 1(seller_is_ets) × 1(seller_is_regulated_nace)
# Sign expectation: NEGATIVE (treated sellers should LOSE buyer share / pair
# activation post-2005, the leakage analog within Belgium).
#
# Build steps:
#   1. Load raw B2B (b2b_selected_sample.RData on local; full on RMD).
#   2. Restrict years to 2005-2022 (CMdG window 2000-2019 + Phase 4 extension).
#   3. Attach seller NACE 2d via annual accounts.
#   4. Attach seller_is_ets (EUTL match).
#   5. Tag seller_is_regulated_nace using regulated_producing_nace from
#      Phase 0 Step 6.
#   6. Attach buyer NACE 2d.
#   7. Filter buyers to regulated_intensive_nace.
#   8. Filter pairs to core inputs: seller's NACE 2d in core_inputs[buyer_nace2d].
#   9. Balance: every (buyer, seller) pair ever observed gets all years 2005-2022.
#  10. Drop the 3 contaminated VATs (only relevant for ETS-status feed; here we
#      keep them in B2B but their is_ets_firm flag remains TRUE since they ARE
#      in EUTL throughout).
#
# Output: ${PROC_DATA}/b2b_cmdj_panel.RData

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)
library(haven)

YEAR_LO <- 2005L
YEAR_HI <- 2022L

# ---------------------------------------------------------------------------
# 1. Load B2B and supporting tables
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "corr_sales"),
         skip_absent = TRUE)
cat("Raw B2B rows:", nrow(b2b), "\n")
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(corr_sales) & corr_sales > 0]
cat("After year + positive-flow filter:", nrow(b2b), "rows\n")

# ---------------------------------------------------------------------------
# 2. Annual accounts -- get NACE 2d for both seller and buyer
# ---------------------------------------------------------------------------
aa_path <- file.path(RAW_DATA, "NBB", "Annual_Accounts_MASTER_ANO.dta")
aa <- as.data.table(read_dta(aa_path,
                             col_select = c("vat_ano", "year", "nace5d")))
setnames(aa, "vat_ano", "vat")
aa[, year := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa[, nace2d := substr(nace4d, 1, 2)]
aa <- unique(aa[, .(vat, year, nace4d, nace2d)])

# Seller NACE
seller_nace <- copy(aa); setnames(seller_nace, c("vat", "year", "nace4d", "nace2d"),
                                  c("seller", "year", "seller_nace4d", "seller_nace2d"))
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)

# Buyer NACE
buyer_nace <- copy(aa); setnames(buyer_nace, c("vat", "year", "nace4d", "nace2d"),
                                 c("buyer", "year", "buyer_nace4d", "buyer_nace2d"))
b2b <- merge(b2b, buyer_nace, by = c("buyer", "year"), all.x = TRUE)
cat("After NACE join: drop NA seller/buyer NACE...\n")
b2b <- b2b[!is.na(seller_nace2d) & !is.na(buyer_nace2d)]
cat("Rows after NACE filter:", nrow(b2b), "\n")

# ---------------------------------------------------------------------------
# 3. ETS seller flag
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

# ---------------------------------------------------------------------------
# 4. Regulated-NACE seller flag
# ---------------------------------------------------------------------------
reg_prod <- fread(file.path(REPO_DIR, "data", "io", "regulated_producing_nace.csv"))
reg_prod[, nace2d := sprintf("%02d", as.integer(nace2d))]
b2b[, seller_is_regulated_nace := as.integer(seller_nace2d %in% reg_prod$nace2d)]

# ---------------------------------------------------------------------------
# 5. Buyer regulated-intensive filter
# ---------------------------------------------------------------------------
ri <- fread(file.path(REPO_DIR, "data", "io", "regulated_intensive_nace.csv"))
ri[, nace2d := sprintf("%02d", as.integer(nace2d))]
b2b <- b2b[buyer_nace2d %in% ri$nace2d]
cat("After regulated-intensive buyer filter:", nrow(b2b), "rows\n")

# ---------------------------------------------------------------------------
# 6. Core-input filter (10% threshold)
# ---------------------------------------------------------------------------
core <- fread(file.path(REPO_DIR, "data", "io", "core_inputs_by_downstream.csv"))
core <- core[threshold == 0.10,
             .(buyer_nace2d = downstream_nace2d,
               seller_nace2d = upstream_cpa_nace2d)]
core[, buyer_nace2d := sprintf("%02d", as.integer(buyer_nace2d))]
core[, seller_nace2d := sprintf("%02d", as.integer(seller_nace2d))]
core[, is_core := TRUE]
core <- unique(core)
b2b <- merge(b2b, core, by = c("buyer_nace2d", "seller_nace2d"), all.x = TRUE)
b2b <- b2b[!is.na(is_core)]
b2b[, is_core := NULL]
cat("After core-input pair filter:", nrow(b2b), "rows\n")

# ---------------------------------------------------------------------------
# 7. Aggregate any duplicate (seller, buyer, year)
# ---------------------------------------------------------------------------
b2b <- b2b[, .(corr_sales = sum(corr_sales, na.rm = TRUE),
               seller_nace4d = first(seller_nace4d),
               seller_nace2d = first(seller_nace2d),
               buyer_nace4d  = first(buyer_nace4d),
               buyer_nace2d  = first(buyer_nace2d),
               seller_is_ets = max(seller_is_ets),
               seller_is_regulated_nace = max(seller_is_regulated_nace)),
           by = .(seller, buyer, year)]
cat("After (seller,buyer,year) aggregation:", nrow(b2b), "rows\n")

# ---------------------------------------------------------------------------
# 8. Balance the panel: every (seller, buyer) pair ever observed -> all years
# ---------------------------------------------------------------------------
pairs <- unique(b2b[, .(seller, buyer)])
years_dt <- data.table(year = YEAR_LO:YEAR_HI)
skel <- pairs[, .(year = years_dt$year), by = .(seller, buyer)]

bal <- merge(skel, b2b, by = c("seller", "buyer", "year"), all.x = TRUE)
bal[is.na(corr_sales), corr_sales := 0]

# Propagate pair-level (time-invariant) attributes.
prop_cols <- c("seller_nace4d", "seller_nace2d", "buyer_nace4d", "buyer_nace2d",
               "seller_is_ets", "seller_is_regulated_nace")
for (cl in prop_cols) {
  bal[, (cl) := {
    v <- get(cl)
    v_obs <- v[!is.na(v)][1]
    v[is.na(v)] <- v_obs
    v
  }, by = .(seller, buyer)]
}

cat("After balance + zero-fill:", nrow(bal), "rows\n")

# ---------------------------------------------------------------------------
# 9. Diagnostic + save
# ---------------------------------------------------------------------------
cat("\n=== B2B CMdG panel ===\n")
cat("Rows                    :", nrow(bal), "\n")
cat("Distinct sellers        :", uniqueN(bal$seller), "\n")
cat("Distinct buyers         :", uniqueN(bal$buyer),  "\n")
cat("Distinct (seller,buyer) :", uniqueN(bal[, .(seller, buyer)]), "\n")
cat("Years                   :", min(bal$year), "-", max(bal$year), "\n")

cat("\nSeller-side cell counts (buyer x seller x year):\n")
print(bal[, .N, by = .(seller_is_ets, seller_is_regulated_nace)][order(-seller_is_ets, -seller_is_regulated_nace)])

cat("\nSeller NACE 2d distribution (top 10):\n")
print(bal[, .N, by = seller_nace2d][order(-N)][1:10])

cat("\nBuyer NACE 2d distribution (top 10):\n")
print(bal[, .N, by = buyer_nace2d][order(-N)][1:10])

panel <- bal
out_path <- file.path(PROC_DATA, "b2b_cmdj_panel.RData")
save(panel, file = out_path)
cat("\nSaved", out_path, "\n")
