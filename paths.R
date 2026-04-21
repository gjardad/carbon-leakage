# paths.R -- central path configuration for carbon-leakage.
#
# Every analysis script should source this at the top via:
#   REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
#                        error = function(e) normalizePath(getwd(), winslash = "/"))
#   while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
#   source(file.path(REPO_DIR, "paths.R"))
#
# That snippet walks up from the script's own directory until it finds
# paths.R -- so it works regardless of where the script is called from.
# paths.R then defines the remaining globals based on the current user.

if (tolower(Sys.info()[["user"]]) == "jardang") {
  # RMD: code on C:, data on X:
  DATA_DIR <- "X:/Documents/JARDANG/data"
  REPO_DIR <- "C:/Users/jardang/Documents/carbon-leakage"
} else if (tolower(Sys.info()[["user"]]) == "jota_") {
  # Local 1
  DATA_DIR <- "C:/Users/jota_/Documents/NBB_data"
  REPO_DIR <- "C:/Users/jota_/Documents/carbon-leakage"
} else {
  stop("paths.R: define directories for this user (",
       Sys.info()[["user"]], ")")
}

PROC_DATA  <- file.path(DATA_DIR, "processed")
RAW_DATA   <- file.path(DATA_DIR, "raw")
OUT_DATA   <- file.path(REPO_DIR, "data", "processed")
OUTPUT_FIG <- file.path(REPO_DIR, "output", "figures")
OUTPUT_TAB <- file.path(REPO_DIR, "output", "tables")

dir.create(OUT_DATA,   recursive = TRUE, showWarnings = FALSE)
dir.create(OUTPUT_FIG, recursive = TRUE, showWarnings = FALSE)
dir.create(OUTPUT_TAB, recursive = TRUE, showWarnings = FALSE)
