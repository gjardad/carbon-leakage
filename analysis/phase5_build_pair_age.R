# phase5_build_pair_age.R
#
# Prep 1 for Plan B (SHOCK_AND_SUBSTITUTION_PLAN.md).
#
# Compute first_year_pair = min(year) per (seller, buyer) from raw B2B,
# so downstream tests can derive:
#   pair_age_{j,b,t}     = year - first_year_pair
#   is_new_pair_{j,b,t}  = 1(year == first_year_pair)
#
# Read the raw B2B file (B2B_ANO.dta) rather than the 2005-restricted
# b2b_selected_sample.RData, so we capture the full 2002+ history -- pairs
# whose true first year is 2002, 2003, or 2004 would otherwise look like
# they "started" in 2005.
#
# Left-censoring caveat: B2B itself starts in 2002, so pairs with
# first_year_pair == 2002 may have started earlier. Flag them with
# is_left_censored so downstream tests can stratify or drop.
#
# Output: ${PROC_DATA}/b2b_pair_age.RData
#   pair_age :: data.table keyed on (seller, buyer)
#     seller, buyer, first_year_pair, is_left_censored

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)
library(haven)

B2B_FIRST_YEAR <- 2002L  # earliest year present in B2B

# ---------------------------------------------------------------------------
# 1. Load raw B2B (full universe on RMD; downsampled on local-1)
# ---------------------------------------------------------------------------
b2b_path <- file.path(RAW_DATA, "NBB", "B2B_ANO.dta")
cat("Reading", b2b_path, "...\n")
b2b <- as.data.table(read_dta(b2b_path,
                              col_select = c("vat_i_ano", "vat_j_ano", "year")))
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano"),
         new = c("seller", "buyer"))
b2b[, year := as.integer(year)]
cat("Raw B2B rows:", nrow(b2b), "\n")
cat("Year range:  ", min(b2b$year, na.rm = TRUE), "-",
                     max(b2b$year, na.rm = TRUE), "\n")

# ---------------------------------------------------------------------------
# 2. First year per (seller, buyer)
# ---------------------------------------------------------------------------
# setkey before by-grouping uses data.table's sorted path -- a large speedup
# at RMD scale (~80M unique pairs).
setkey(b2b, seller, buyer)
pair_age <- b2b[, .(first_year_pair = min(year, na.rm = TRUE)),
                by = .(seller, buyer)]
pair_age[, is_left_censored := as.integer(first_year_pair == B2B_FIRST_YEAR)]
setkey(pair_age, seller, buyer)

cat("\nDistinct (seller, buyer) pairs:", nrow(pair_age), "\n")
cat("Distribution of first_year_pair:\n")
print(pair_age[, .N, by = first_year_pair][order(first_year_pair)])

cat("\nLeft-censored share (first_year_pair == 2002):",
    round(mean(pair_age$is_left_censored), 3), "\n")

# ---------------------------------------------------------------------------
# 3. Sanity checks
# ---------------------------------------------------------------------------
# Spot-check 10 random pairs.
set.seed(42)
sample_pairs <- pair_age[sample(.N, 10)]
cat("\nSpot check (10 random pairs):\n")
for (i in seq_len(nrow(sample_pairs))) {
  sp <- sample_pairs[i]
  yrs <- sort(b2b[seller == sp$seller & buyer == sp$buyer, year])
  cat(sprintf("  pair %d: first_year_pair=%d, years observed=[%s]\n",
              i, sp$first_year_pair, paste(yrs, collapse = ",")))
  stopifnot(sp$first_year_pair == min(yrs))
}

# ---------------------------------------------------------------------------
# 4. Save
# ---------------------------------------------------------------------------
out_path <- file.path(PROC_DATA, "b2b_pair_age.RData")
save(pair_age, file = out_path)
cat("\nSaved", out_path, "\n")
