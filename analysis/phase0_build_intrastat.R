# Phase 0 Step 5 -- Belgian Intrastat threshold history.
#
# Output: data/concordances/intrastat_threshold_be.csv
#         (year, arrivals_eur, dispatches_eur, extended_eur, source, break_flag)
#
# Used by Phase 2.4 (Figure 4 alternative-control spec). When the bottom
# threshold rises, small importers stop reporting and apparent intra-EU import
# volume drops -- creating a structural break that must be absorbed with a
# dummy variable. CdGM identified one such break in France in 2011 (EUR 150k
# -> EUR 460k). For Belgium, we examine the NBB Intrastat newsletter archive.
#
# Sources confirmed (verified 2026-04-27 from NBB newsletters):
#   * 2016-2026: arrivals EUR 1,500,000 / dispatches EUR 1,000,000 /
#     extended EUR 25,000,000. Every annual newsletter (Nos. 26-36) explicitly
#     confirms "no changes". URL pattern:
#     https://www.nbb.be/doc/dd/onegate/data/newsletters/newsletter_intrastat_YYYY_en.pdf
#
# UNKNOWN (pre-2016, NBB newsletters not in public archive):
#   * 2000-2015 history -- not on the NBB Foreign Trade page. The newsletters
#     numbered 1-25 (covering 1991-2015) exist but are not posted publicly.
#     To complete the file, either email dst.statistiek@nbb.be or chase NBB
#     working papers / Statbel methodology notes for the threshold series.
#
# IMPLICATION FOR PHASE 2.4:
#   Within our analytical period (2005-2022), no Intrastat threshold change is
#   confirmed. CdGM's France-2011 break has no documented Belgian counterpart
#   in 2016-2022. Pre-2016 may contain breaks; flagged as a known gap.

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)

out_path <- file.path(REPO_DIR, "data", "concordances", "intrastat_threshold_be.csv")

# Year range = our customs-panel analytical horizon.
years <- 2000:2026

# Confirmed values 2016-2026 (NBB newsletters Nos. 26-36).
confirmed <- data.table(
  year          = 2016:2026,
  arrivals_eur  = 1500000,
  dispatches_eur = 1000000,
  extended_eur  = 25000000,
  source        = "NBB newsletter (verified)",
  break_flag    = FALSE
)

# Unknown 2000-2015. Marking NA explicitly to distinguish "no break" from "no data".
unknown <- data.table(
  year          = 2000:2015,
  arrivals_eur  = NA_real_,
  dispatches_eur = NA_real_,
  extended_eur  = NA_real_,
  source        = "UNKNOWN -- pre-2016 NBB newsletters not on public archive",
  break_flag    = NA
)

dt <- rbind(unknown, confirmed)
setorder(dt, year)

cat("Belgian Intrastat threshold history:\n")
print(dt)
cat("\n", nrow(dt), "rows.\n", sep = "")
cat("Confirmed (2016-2026):", nrow(dt[!is.na(arrivals_eur)]), "years\n")
cat("UNKNOWN (2000-2015)  :", nrow(dt[is.na(arrivals_eur)]), "years\n")

fwrite(dt, out_path)
cat("\nWrote", out_path, "\n")
