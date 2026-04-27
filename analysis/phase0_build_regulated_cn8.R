# Phase 0 Step 1 — build the regulated CN8 list.
#
# Inputs:
#   * data/concordances/regulated_hs_rules.csv — encoded rules from CMDJ Tables A.2 + A.3.
#   * NBB_data/raw/Correspondences_and_dictionaries/Website_nc8corresp/nom_nc8/CN_unpacked/
#     CN_yyyy.csv (1995-2018) — Bergounhon-Lenoir-Mejean (2018) companion CN nomenclatures.
#     Complete EU CN universe 1995-2018 with no PRODCOM restriction. PRIMARY universe source.
#
# Output:
#   * data/concordances/regulated_products_cn8.csv — CN8-level regulated flag.
#
# Logic:
#   1. Read each CN_yyyy.csv; the third column ("Code") contains the human-readable CN code
#      with spaces (e.g. "0102 21 30"). Strip spaces; keep rows where the result is exactly
#      8 numeric digits — those are CN8 codes.
#   2. Union across years 1995-2018 → complete CN universe.
#   3. For each CN8, derive HS2 = first 2 digits, HS4 = first 4, HS6 = first 6.
#   4. Apply ETS rules (group_id = ets_activity): include if any include rule at any
#      level matches; exclude if any exclude rule within the SAME group matches a parent.
#   5. Apply CBAM rules analogously, with group_id = cbam_category.
#   6. is_regulated = is_ets | is_cbam.
#   7. Single-year sanity check: restrict to codes existing in 2014 and compare per-chapter
#      counts to CMDJ Table A.4.

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)

rules_path <- file.path(REPO_DIR, "data", "concordances", "regulated_hs_rules.csv")
blm_dir <- file.path(RAW_DATA, "Correspondences_and_dictionaries",
                     "Website_nc8corresp", "nom_nc8", "CN_unpacked")
out_path <- file.path(REPO_DIR, "data", "concordances", "regulated_products_cn8.csv")

# 1. Build CN8 universe per year from BLM 2018 CN_yyyy.csv files.
#    Three column layouts across 1995-2018:
#      1995-2006: "Level";"Code";"Code"[;"Description"][;"Self-explanatory texts"]   (4-5 cols)
#      2007-2013: filler;cnkey;v3;level;dashes;en;cs;de;da;es;fr;su;upd               (13 cols)
#      2014-2018: Order;Code;Code;Parent;Description;...;Self-expl texts in DE        (10 cols)
#    In all three, the human-readable CN code (e.g. "0101 11 00") is in column 3.
#    Duplicate "Code" headers force position-based indexing via .SD/[[]] won't work --
#    use the [[i]] form that pulls by integer position only when names are unique.
#    Easiest: read with header = FALSE, skip first line, index column 3.
read_cn8_year <- function(yr) {
  f <- file.path(blm_dir, sprintf("CN_%d.csv", yr))
  d <- fread(f, sep = ";", header = FALSE, skip = 1, encoding = "UTF-8")
  raw <- gsub(" ", "", as.character(d[[3]]), fixed = TRUE)
  is_cn8 <- grepl("^[0-9]{8}$", raw)
  unique(raw[is_cn8])
}

years <- 1995:2018
cn8_by_year <- lapply(years, read_cn8_year)
names(cn8_by_year) <- as.character(years)
for (yr in years) cat("CN_", yr, ".csv: ", length(cn8_by_year[[as.character(yr)]]), " CN8 codes\n", sep = "")
cn8_universe <- sort(unique(unlist(cn8_by_year)))
cat("\nCN8 universe (1995-2018 union):", length(cn8_universe), "\n")

cn <- data.table(cn8 = cn8_universe)
cn[, exists_2014 := cn8 %in% cn8_by_year[["2014"]]]
cn[, hs2 := substr(cn8, 1, 2)]
cn[, hs4 := substr(cn8, 1, 4)]
cn[, hs6 := substr(cn8, 1, 6)]

# 2. Read rules.
rules <- fread(rules_path)
rules[, hs_code := as.character(hs_code)]
rules[, hs_level := as.integer(hs_level)]

apply_rules <- function(cn_dt, rules_dt) {
  # For each group, mark CN8s that match an include rule (any level), then unmark
  # those that match an exclude rule within the same group at any deeper level.
  cn_dt <- copy(cn_dt)
  cn_dt[, flag := FALSE]

  groups <- unique(rules_dt$group_id)
  for (g in groups) {
    grp <- rules_dt[group_id == g]
    inc <- grp[action == "include"]
    exc <- grp[action == "exclude"]

    matched <- rep(FALSE, nrow(cn_dt))
    for (k in seq_len(nrow(inc))) {
      lev <- inc$hs_level[k]
      code <- inc$hs_code[k]
      key_col <- switch(as.character(lev), "2" = "hs2", "4" = "hs4",
                        "6" = "hs6", "8" = "cn8")
      matched <- matched | (cn_dt[[key_col]] == code)
    }
    for (k in seq_len(nrow(exc))) {
      lev <- exc$hs_level[k]
      code <- exc$hs_code[k]
      key_col <- switch(as.character(lev), "2" = "hs2", "4" = "hs4",
                        "6" = "hs6", "8" = "cn8")
      matched <- matched & !(cn_dt[[key_col]] == code)
    }
    cn_dt[, flag := flag | matched]
  }
  cn_dt$flag
}

cn[, is_ets := apply_rules(cn, rules[source == "ETS"])]
cn[, is_cbam := apply_rules(cn, rules[source == "CBAM"])]
cn[, is_regulated := is_ets | is_cbam]

cat("\n--- Full universe (BLM 1995-2018) ---\n")
cat("  ETS-regulated CN8s :", sum(cn$is_ets), "\n")
cat("  CBAM-regulated CN8s:", sum(cn$is_cbam), "\n")
cat("  Union              :", sum(cn$is_regulated), "\n")

cat("\n--- 2014 single-year snapshot (CMDJ-comparable universe) ---\n")
cn_2014 <- cn[exists_2014 == TRUE]
cat("  Universe size      :", nrow(cn_2014),
    " (CMDJ raw universe: 10,174 across all years)\n")
cat("  ETS-regulated CN8s :", sum(cn_2014$is_ets),
    " (CMDJ Table A.4 ETS  1,444 -- caveat: harmonized-product count)\n")
cat("  CBAM-regulated CN8s:", sum(cn_2014$is_cbam),
    " (CMDJ Table A.4 CBAM   421)\n")
cat("  Union              :", sum(cn_2014$is_regulated),
    " (CMDJ Table A.4 Union 1,464)\n")

cat("\nETS counts by HS chapter, 2014 snapshot (compare with CMDJ Table A.4 col (1)):\n")
cmdj_ets <- c("25"=20, "26"=26, "27"=109, "28"=219, "29"=435, "31"=0, "38"=1,
              "47"=17, "48"=61, "68"=7, "69"=49, "70"=131, "72"=321, "73"=249,
              "74"=65, "75"=17, "76"=56, "78"=11, "79"=11, "80"=8, "81"=69)
ours_ets_2014 <- cn_2014[is_ets == TRUE, .N, by = hs2][order(hs2)]
ours_ets_2014[, cmdj := cmdj_ets[hs2]]
ours_ets_2014[, ratio := round(N / cmdj, 2)]
print(ours_ets_2014)

cat("\nCBAM counts by HS chapter, 2014 snapshot (compare with CMDJ Table A.4 col (3)):\n")
cmdj_cbam <- c("25"=7, "26"=1, "27"=1, "28"=5, "31"=24, "72"=308, "73"=157, "76"=49)
ours_cbam_2014 <- cn_2014[is_cbam == TRUE, .N, by = hs2][order(hs2)]
ours_cbam_2014[, cmdj := cmdj_cbam[hs2]]
ours_cbam_2014[, ratio := round(N / cmdj, 2)]
print(ours_cbam_2014)

cat("\nUnion counts by HS chapter, 2014 snapshot (compare with CMDJ Table A.4 col (5)):\n")
cmdj_union <- c("25"=21, "26"=26, "27"=109, "28"=219, "29"=435, "31"=24, "38"=1,
                "47"=17, "48"=61, "68"=7, "69"=49, "70"=131, "72"=321, "73"=249,
                "74"=65, "75"=17, "76"=56, "78"=11, "79"=11, "80"=8, "81"=69)
ours_un_2014 <- cn_2014[is_regulated == TRUE, .N, by = hs2][order(hs2)]
ours_un_2014[, cmdj := cmdj_union[hs2]]
ours_un_2014[, ratio := round(N / cmdj, 2)]
print(ours_un_2014)

# 3. Write the output.
fwrite(cn[, .(cn8, hs2, hs4, hs6, is_ets, is_cbam, is_regulated, exists_2014)], out_path)
cat("\nWrote", out_path, "\n")
