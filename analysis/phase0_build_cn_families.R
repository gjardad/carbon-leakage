# Phase 0 Step 2a -- BLM C^3 CN-only family-tree harmonization, ported to R.
#
# Source: Bergounhon-Lenoir-Mejean (2018) `corres_nc8.do` + Matlab `corresp_1.m`,
# itself based on Behrens & Martin (2015) "connected components concordance".
#
# Inputs (BLM 2018 companion package, already unpacked):
#   * NBB_data/raw/Correspondences_and_dictionaries/Website_nc8corresp/nom_nc8/
#     CN_unpacked/CN_yyyy.csv  (1995-2018, one CSV per year)
#   * NBB_data/raw/Correspondences_and_dictionaries/Website_nc8corresp/tablescorresp/
#     corres_unpacked/corresYYYY.txt  (1996-2018, one TXT per transition year)
#
# Output:
#   * data/concordances/cn_family_long.csv -- long-form (year, cn8, family_id) with
#     family_id stable across the 1995-2018 panel.
#
# Algorithm:
#   1. Build the universe of (year, cn8) tuples 1995-2018 from CN_yyyy.csv files.
#   2. Read year-on-year correspondences corresYYYY.txt (v1 = new code in YYYY,
#      v2 = old code in YYYY-1). Build explicit transition edges
#      (year-1, v2) -- (year, v1).
#   3. For (year, cn8) tuples that DO NOT appear as (year-1) endpoint of any
#      transition, add a default "code unchanged" edge to (year+1, same cn8).
#   4. Treat the resulting graph as undirected. Connected components = family trees.
#   5. Assign family_id = component number. Output long table.

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("igraph", quietly = TRUE)) {
  install.packages("igraph", repos = "https://cloud.r-project.org")
}
library(data.table)
library(igraph)

blm_root <- file.path(RAW_DATA, "Correspondences_and_dictionaries", "Website_nc8corresp")
cn_dir   <- file.path(blm_root, "nom_nc8", "CN_unpacked")
cor_dir  <- file.path(blm_root, "tablescorresp", "corres_unpacked")
out_path <- file.path(REPO_DIR, "data", "concordances", "cn_family_long.csv")

firstyr <- 1995L
lastyr  <- 2018L

# ---- 1. Nomenclature panel: (year, cn8) for every year ----
read_cn8_year <- function(yr) {
  f <- file.path(cn_dir, sprintf("CN_%d.csv", yr))
  d <- fread(f, sep = ";", header = FALSE, skip = 1L, encoding = "UTF-8")
  raw <- gsub(" ", "", as.character(d[[3]]), fixed = TRUE)
  unique(raw[grepl("^[0-9]{8}$", raw)])
}

nom <- rbindlist(lapply(firstyr:lastyr, function(yr) {
  codes <- read_cn8_year(yr)
  data.table(year = yr, cn8 = codes)
}))
cat("Nomenclature panel:\n")
cat("  total (year, cn8) tuples :", nrow(nom), "\n")
cat("  distinct cn8 codes       :", uniqueN(nom$cn8), "\n")

# ---- 2. Year-on-year transitions ----
# corres`y'.txt: tab-separated, columns v1 (new code in y) and v2 (old code in y-1).
read_corres_year <- function(yr) {
  f <- file.path(cor_dir, sprintf("corres%d.txt", yr))
  if (!file.exists(f)) return(NULL)
  d <- fread(f, header = TRUE,
             colClasses = list(character = c("v1", "v2")))
  pad8 <- function(x) sprintf("%08d", as.integer(x))
  data.table(year_old = yr - 1L, cn8_old = pad8(d$v2),
             year_new = yr,      cn8_new = pad8(d$v1))
}
trans <- rbindlist(lapply((firstyr + 1L):lastyr, read_corres_year))
trans <- unique(trans[!is.na(cn8_old) & !is.na(cn8_new)])
cat("\nExplicit transitions:\n")
cat("  total transition edges   :", nrow(trans), "\n")
cat("  distinct transition years:", uniqueN(trans$year_new), "\n")

# ---- 3. Default "unchanged" edges for codes with no explicit transition ----
# For each (year, cn8) in years [firstyr, lastyr-1], if (year, cn8) is NOT the
# (year_old, cn8_old) endpoint of any explicit transition, add an edge to
# (year+1, cn8). This propagates the code forward as "unchanged".
trans_keys <- unique(trans[, .(year_old, cn8_old)])
trans_keys[, has_explicit := TRUE]
nom_pre_last <- nom[year < lastyr]
nom_pre_last <- merge(nom_pre_last, trans_keys,
                     by.x = c("year", "cn8"), by.y = c("year_old", "cn8_old"),
                     all.x = TRUE)
unchanged <- nom_pre_last[is.na(has_explicit)]
unchanged_edges <- unchanged[, .(year_old = year, cn8_old = cn8,
                                  year_new = year + 1L, cn8_new = cn8)]
cat("\nDefault 'unchanged' edges:\n")
cat("  total unchanged edges    :", nrow(unchanged_edges), "\n")

# ---- 4. Combine all edges, build graph, find connected components ----
edges_all <- rbindlist(list(trans, unchanged_edges))
edges_all[, node_old := paste(year_old, cn8_old, sep = "_")]
edges_all[, node_new := paste(year_new, cn8_new, sep = "_")]

# All nodes = all (year, cn8) tuples appearing in nomenclature OR as endpoint of
# any transition (covers cases where a transition references a code not in
# nomenclature -- shouldn't happen but defensive).
all_nodes <- unique(c(
  paste(nom$year, nom$cn8, sep = "_"),
  edges_all$node_old, edges_all$node_new
))
cat("\nGraph:\n")
cat("  total nodes              :", length(all_nodes), "\n")
cat("  total edges              :", nrow(edges_all), "\n")

g <- graph_from_data_frame(edges_all[, .(node_old, node_new)],
                           directed = FALSE,
                           vertices = data.frame(name = all_nodes))
comp <- components(g)
cat("  connected components     :", comp$no, "\n")
cat("  largest component size   :", max(comp$csize), "\n")
cat("  median component size    :", median(comp$csize), "\n")
cat("  singleton components (size = 1):", sum(comp$csize == 1), "\n")

# ---- 5. Output long table (year, cn8, family_id) ----
out <- data.table(node = names(comp$membership),
                  family_id = as.integer(comp$membership))
out[, c("year", "cn8") := tstrsplit(node, "_", fixed = TRUE)]
out[, year := as.integer(year)]
out[, cn8 := as.character(cn8)]
# Restrict to (year, cn8) tuples actually in the nomenclature
setkey(nom, year, cn8)
out <- out[nom, on = c("year", "cn8"), nomatch = NULL]
setorder(out, year, cn8)
out <- out[, .(year, cn8, family_id)]

cat("\nOutput long table:\n")
cat("  rows                     :", nrow(out), "\n")
cat("  distinct family_ids      :", uniqueN(out$family_id), "\n")
cat("  CMDJ benchmark           : 7,051 harmonized products (1995-2020)\n")

fwrite(out, out_path)
cat("\nWrote", out_path, "\n")
