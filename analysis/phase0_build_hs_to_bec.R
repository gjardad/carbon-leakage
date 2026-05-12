# Phase 0 Step 3 -- HS6 to BEC concordance for capital-goods filter.
#
# CdGM (supplemental appendix p. 44) drop CN8 codes whose underlying HS6 is
# classified as BEC 41 (Capital goods except transport equipment) or BEC 521
# (Industrial transport equipment) using the UN HS2002 -> BEC Rev.4 table.
#
# Input:
#   * NBB_data/raw/Correspondences_and_dictionaries/
#     JobID-40_Concordance_H3_to_BE.CSV
#     -- UN HS 2007 (H3) -> BEC Rev.4 correspondence, 5,051 rows.
#   Note: this is HS 2007, not HS 2002 as in CdGM. The difference between H2
#   and H3 is a few hundred reclassified codes; for BEC capital-goods flagging
#   the loss in coverage is negligible.
#
# Output:
#   * data/concordances/hs_to_bec.csv with columns (hs6, bec4, bec_description,
#     is_capital). is_capital = TRUE iff bec4 in {"41", "521"}.

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)

in_path  <- file.path(RAW_DATA, "Correspondences_and_dictionaries",
                      "JobID-40_Concordance_H3_to_BE.CSV")
out_path <- file.path(REPO_DIR, "data", "concordances", "hs_to_bec.csv")

d <- fread(in_path, colClasses = list(character = c("HS 2007 Product Code",
                                                     "BEC Product Code")))
setnames(d,
         c("HS 2007 Product Code", "HS 2007 Product Description",
           "BEC Product Code",      "BEC Product Description"),
         c("hs6", "hs_description", "bec4", "bec_description"))

# Pad HS to 6 chars (some codes might lose leading zeros).
d[, hs6 := sprintf("%06d", as.integer(hs6))]

# Capital-goods flag: BEC 41 (capital goods except transport equipment)
# OR BEC 521 (industrial transport equipment).
d[, is_capital := bec4 %in% c("41", "521")]

cat("HS6 -> BEC concordance:\n")
cat("  rows                 :", nrow(d), "\n")
cat("  distinct HS6         :", uniqueN(d$hs6), "\n")
cat("  distinct BEC codes   :", uniqueN(d$bec4), "\n")
cat("  capital-goods rows   :", sum(d$is_capital), "\n")
cat("  capital-goods share  :", round(mean(d$is_capital), 3), "\n\n")

cat("BEC code distribution:\n")
print(d[, .(N = .N, share = round(.N / nrow(d), 3)), by = bec4][order(-N)])

cat("\nCapital-goods CN by HS chapter (top 10 chapters by capital count):\n")
d[, hs2 := substr(hs6, 1, 2)]
cap_by_chap <- d[is_capital == TRUE, .N, by = hs2][order(-N)][1:10]
print(cap_by_chap)
cat("\nExpected concentration: HS 84 (machinery), HS 85 (electrical machinery),\n")
cat("HS 86 (railway), HS 87 (vehicles), HS 88 (aircraft), HS 89 (ships).\n")

# Output
fwrite(d[, .(hs6, bec4, bec_description, is_capital)], out_path)
cat("\nWrote", out_path, "\n")
