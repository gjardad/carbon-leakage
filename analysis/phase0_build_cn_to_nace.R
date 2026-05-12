# Phase 0 Step 2b -- CN8 to NACE 4d bridge.
#
# Inputs:
#   * NBB_data/raw/Correspondences_and_dictionaries/product_id_pc8plus_pc8_cn8_final
#     (ID-PC8-CN8 codes final).csv -- GRANTPA wide-form CN <-> PC family-tree map.
#   * data/concordances/cn_family_long.csv -- BLM C^3 panel (year, cn8, family_id),
#     used to ground the CN8 universe and add the year dimension.
#
# Output:
#   * data/concordances/cn8_to_nace4d.csv -- long-form (year, cn8, family_id, pc8,
#     nace4d, source) where source in {GRANTPA, supplement_HS27, NA}.
#
# What this step does that simply applying GRANTPA does NOT:
#   1. Parses GRANTPA's wide-form CSV to a long-form (product_id, cn8) and
#      (product_id, pc8) panel. GRANTPA only ships the wide form.
#   2. Strips the `(YYYY)` year markers and treats all CN8s in a row as belonging
#      to the same product_id, regardless of their year of validity. This is a
#      deliberate simplification: NACE 4d is a property of the family, not of the
#      year. Time variation in CN8 codes is captured separately by Step 2a's
#      family_id panel.
#   3. Joins the parsed GRANTPA mapping onto BLM C^3's complete (year, cn8) panel.
#      This means the output covers EVERY (year, cn8) tuple in the EU CN
#      nomenclature 1995-2018, not just the GRANTPA universe.
#   4. Adds a small hand-coded HS27 supplement covering CN codes that GRANTPA
#      omits (mineral fuels: coal, lignite, peat, petroleum, gas, electricity).
#      The mapping follows CDGM Table A.5 cols (1)/(4): ETS activities -> NAF
#      sectors, with the NAF expanded to the corresponding NACE Rev.2 4d code.
#   5. Reports diagnostics: how many CN8s have GRANTPA NACE, how many use the
#      supplement, how many are still unmapped, and how many product_ids have
#      heterogeneous NACE 4d (indicating PC8 reclassification across NACE).

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)

grantpa_path <- file.path(RAW_DATA, "Correspondences_and_dictionaries",
                          "product_id_pc8plus_pc8_cn8_final(ID-PC8-CN8 codes final).csv")
families_path <- file.path(REPO_DIR, "data", "concordances", "cn_family_long.csv")
out_path     <- file.path(REPO_DIR, "data", "concordances", "cn8_to_nace4d.csv")

# -------------------------------------------------------------------------
# 1. Parse GRANTPA wide form into long (product_id, cn8) and (product_id, pc8)
# -------------------------------------------------------------------------

gr <- fread(grantpa_path)
stopifnot(all(c("product_id", "prodcom", "CN8") %in% names(gr)))

# Year-aware parser: walk tokens left-to-right, tracking the current "valid from"
# year context (set by `(YYYY)` markers). Returns code, start_year pairs.
# Pre-marker codes default to start_year = 1995 (GRANTPA panel start).
parse_with_years <- function(cell, n_digits = 8L, default_start = 1995L) {
  toks <- unlist(strsplit(cell, "\\s+"))
  toks <- toks[nchar(toks) > 0L]
  cur <- default_start
  codes <- character(0)
  starts <- integer(0)
  for (t in toks) {
    if (grepl("^\\([0-9]{4}\\)$", t)) {
      cur <- as.integer(substr(t, 2L, 5L))
    } else if (grepl(sprintf("^[0-9]{%d}$", n_digits), t)) {
      codes <- c(codes, t)
      starts <- c(starts, cur)
    }
  }
  data.table(code = codes, start_year = starts)
}

# Long (product_id, cn8, start_year). For CN we keep ALL year contexts because
# CN reclassifications can happen anywhere -- BLM C^3 already harmonized them.
gr_cn <- gr[, parse_with_years(CN8, 8L), by = product_id]
setnames(gr_cn, "code", "cn8")

# For PC, we want the codes valid in the LATEST years of the panel, where
# PRODCOM uses NACE Rev.2. Take only the codes appearing after the latest
# `(YYYY)` marker in each cell (the "current" segment). If no year markers
# exist, take all codes (they're stable, so their NACE 4d assignment is the
# Rev.2 assignment for any year >= 2008 they appeared in).
parse_latest_segment <- function(cell, n_digits = 8L) {
  toks <- unlist(strsplit(cell, "\\s+"))
  toks <- toks[nchar(toks) > 0L]
  is_marker <- grepl("^\\([0-9]{4}\\)$", toks)
  last_marker_idx <- if (any(is_marker)) max(which(is_marker)) else 0L
  segment <- toks[(last_marker_idx + 1L):length(toks)]
  segment <- segment[grepl(sprintf("^[0-9]{%d}$", n_digits), segment)]
  unique(segment)
}

gr_pc_latest <- gr[, .(pc8 = unlist(lapply(prodcom, parse_latest_segment, 8L))),
                   by = product_id]
gr_pc_latest <- unique(gr_pc_latest)

cat("PC8 codes (latest segment per product_id):\n")
cat("  total (product_id, pc8) tuples   :", nrow(gr_pc_latest), "\n")
cat("  product_ids with >=1 PC8 mapped  :", uniqueN(gr_pc_latest$product_id), "\n")
cat("  product_ids with NO PC8 mapped   :", uniqueN(gr$product_id) - uniqueN(gr_pc_latest$product_id), "\n")

cat("GRANTPA parsed:\n")
cat("  rows in wide form              :", nrow(gr), "\n")
cat("  long (product_id, cn8) tuples  :", nrow(gr_cn), "\n")
cat("  long (product_id, pc8) tuples  :", nrow(gr_pc_latest), "\n")
cat("  unique CN8 codes               :", uniqueN(gr_cn$cn8), "\n")
cat("  unique PC8 codes               :", uniqueN(gr_pc_latest$pc8), "\n")
cat("  unique product_ids             :", uniqueN(gr$product_id), "\n")

# Derive NACE 4d = first 4 digits of PC8 (NACE Rev.2 by construction).
gr_pc_latest[, nace4d := substr(pc8, 1, 4)]

# Reduce to product_id -> {nace4d}. Most product_ids should now have a single NACE 4d.
pid_nace <- unique(gr_pc_latest[, .(product_id, nace4d)])
n_nace_per_pid <- pid_nace[, .(n_nace = uniqueN(nace4d)), by = product_id]
cat("\nNACE 4d heterogeneity within product_ids:\n")
cat("  product_ids with 1 NACE 4d   :", sum(n_nace_per_pid$n_nace == 1), "\n")
cat("  product_ids with 2 NACE 4d   :", sum(n_nace_per_pid$n_nace == 2), "\n")
cat("  product_ids with 3+ NACE 4d  :", sum(n_nace_per_pid$n_nace >= 3), "\n")
cat("  --> for heterogeneous product_ids we keep the modal nace4d (and flag).\n")

# Modal NACE 4d per product_id (ties broken alphabetically by code).
modal_nace <- gr_pc_latest[, .N, by = .(product_id, nace4d)
                          ][order(product_id, -N, nace4d)
                          ][, .SD[1L], by = product_id
                          ][, .(product_id, nace4d)]
setnames(modal_nace, "nace4d", "nace4d_modal")

# Concatenated list of all NACE 4d codes per product_id (for traceability).
all_nace <- pid_nace[order(product_id, nace4d),
                     .(nace4d_all = paste(unique(nace4d), collapse = ";")),
                     by = product_id]

pid_nace_summary <- merge(modal_nace, all_nace, by = "product_id")

# Per-CN8 NACE: each CN8 inherits its product_id's modal NACE.
# Note gr_cn has multiple rows per (product_id, cn8) due to year contexts;
# collapse to unique (product_id, cn8) pairs first.
gr_cn_unique <- unique(gr_cn[, .(product_id, cn8)])
gr_cn8_nace <- merge(gr_cn_unique, pid_nace_summary, by = "product_id")
cat("\nGRANTPA CN8 -> NACE 4d coverage:\n")
cat("  CN8 codes mapped via GRANTPA :", uniqueN(gr_cn8_nace$cn8), "\n")

# -------------------------------------------------------------------------
# 2. HS27 supplement (and a handful of other gaps CDGM documents).
# -------------------------------------------------------------------------
# Hand-coded mapping for HS chapters that GRANTPA misses because they have no
# PRODCOM counterpart. Source: CDGM Table A.5 cols (1)/(4) ETS-activity ->
# NAF mapping, and structural NACE Rev.2 codes.
#
# Format: hs_prefix (HS chapter or heading), nace4d, description.
hs27_supplement <- data.table(
  hs_prefix = c(
    "2701", "2702", "2703", "2704", "2705", "2706",
    "2707", "2708", "2709", "2710", "2711", "2712",
    "2713", "2714", "2715", "2716"
  ),
  nace4d = c(
    "0510", "0520", "0892", "1910", "3522", "1910",
    "1920", "1910", "0610", "1920", "0620", "1920",
    "1920", "0899", "2399", "3511"
  ),
  description = c(
    "Coal -> Mining of hard coal",
    "Lignite -> Mining of lignite",
    "Peat -> Extraction of peat",
    "Coke and semi-coke -> Manufacture of coke oven products",
    "Coal gas, water gas, etc. -> Distribution of gaseous fuels through mains",
    "Tar from coal/lignite/peat -> Manufacture of coke oven products",
    "Aromatic oils from coal tar -> Refined petroleum products",
    "Pitch and pitch coke -> Manufacture of coke oven products",
    "Crude petroleum -> Extraction of crude petroleum",
    "Refined petroleum -> Manufacture of refined petroleum products",
    "Petroleum gases -> Extraction of natural gas",
    "Petroleum jelly, waxes -> Manufacture of refined petroleum products",
    "Petroleum coke -> Manufacture of refined petroleum products",
    "Bitumen and asphalt -> Other mining/quarrying n.e.c.",
    "Bituminous mixtures -> Manufacture of other non-metallic mineral products n.e.c.",
    "Electrical energy -> Production of electricity"
  )
)
cat("\nHS27 supplement: ", nrow(hs27_supplement), "HS-headings hand-mapped\n")

# -------------------------------------------------------------------------
# 3. Build final long-form table (year, cn8, family_id, pc8, nace4d, source)
# -------------------------------------------------------------------------

fams <- fread(families_path, colClasses = list(character = "cn8"))

# Primary join: BLM panel + GRANTPA NACE.
out <- merge(fams,
             gr_cn8_nace[, .(cn8, nace4d_modal, nace4d_all)],
             by = "cn8", all.x = TRUE)
setnames(out, "nace4d_modal", "nace4d")
out[, source := ifelse(is.na(nace4d), NA_character_, "GRANTPA")]

# Propagate NACE within BLM families: if any CN8 in a family has a GRANTPA NACE,
# every CN8 in the same family inherits that NACE. Take modal NACE per family.
fam_nace <- out[!is.na(nace4d), .N, by = .(family_id, nace4d)
              ][order(family_id, -N, nace4d)
              ][, .SD[1L], by = family_id
              ][, .(family_id, fam_nace4d = nace4d)]
out <- merge(out, fam_nace, by = "family_id", all.x = TRUE)
out[is.na(nace4d) & !is.na(fam_nace4d),
    `:=`(nace4d = fam_nace4d, source = "GRANTPA_via_family")]
out[, fam_nace4d := NULL]

# Secondary fill: HS27 supplement for CN8 codes still unmapped.
out[, hs4 := substr(cn8, 1, 4)]
out_supp <- merge(out[is.na(nace4d), .(year, cn8, family_id, hs4)],
                  hs27_supplement[, .(hs_prefix, nace4d_supp = nace4d)],
                  by.x = "hs4", by.y = "hs_prefix", all.x = TRUE)
out_supp_keep <- out_supp[!is.na(nace4d_supp)]
fill_keys <- out_supp_keep[, .(year, cn8)]
out[fill_keys, on = c("year", "cn8"),
    `:=`(nace4d = out_supp_keep$nace4d_supp[match(paste(year, cn8), paste(out_supp_keep$year, out_supp_keep$cn8))],
         source = "supplement_HS27")]

# Add a sanity column listing ALL NACE 4d codes for the family (when GRANTPA
# heterogeneity exists). For supplement rows this is just the supplement code.
out[is.na(nace4d_all) & !is.na(nace4d), nace4d_all := nace4d]

# Final tidy.
setorder(out, year, cn8)
out <- out[, .(year, cn8, family_id, nace4d, nace4d_all, source)]

# De-duplicate: each (year, cn8) should appear exactly once.
out <- unique(out, by = c("year", "cn8"))

# Force nace4d to 4-character zero-padded string (preserves "0510", "0812").
pad4 <- function(x) {
  out_chr <- ifelse(is.na(x), NA_character_, sprintf("%04d", as.integer(x)))
  out_chr
}
out[, nace4d := pad4(nace4d)]
# nace4d_all is already a string but may have unpadded codes; rebuild from nace4d.
out[!is.na(nace4d_all), nace4d_all := sapply(strsplit(nace4d_all, ";"),
                                              function(v) paste(pad4(v), collapse = ";"))]

cat("\n--- Coverage summary ---\n")
cat("Total (year, cn8) tuples         :", nrow(out), "\n")
cat("  with GRANTPA NACE 4d (direct)  :", sum(out$source == "GRANTPA", na.rm = TRUE), "\n")
cat("  with GRANTPA NACE via family   :", sum(out$source == "GRANTPA_via_family", na.rm = TRUE), "\n")
cat("  with HS27 supplement NACE 4d   :", sum(out$source == "supplement_HS27", na.rm = TRUE), "\n")
cat("  STILL UNMAPPED                 :", sum(is.na(out$nace4d)), "\n")

cat("\nUnmapped (year, cn8) tuples by HS chapter (top 10):\n")
out_um <- out[is.na(nace4d)]
out_um[, hs2 := substr(cn8, 1, 2)]
print(out_um[, .N, by = hs2][order(-N)][1:10])

fwrite(out, out_path)
cat("\nWrote", out_path, "\n")
