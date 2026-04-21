# verify_against_R.R
#
# Cross-check the Stata pipeline's .dta outputs against the R pipeline's
# reference .RData files. Run this LOCALLY (on local-1) after executing
# the full .do pipeline from inside this folder.
#
# For each output:
#   - loads both .RData and .dta
#   - compares row counts
#   - compares column-wise sums / means / quantiles for key variables
#   - reports any mismatch above a small tolerance
#
# Mismatches can come from:
#   (a) bugs in the port — investigate
#   (b) legitimate divergence (e.g. Stata / R handle duplicate keys
#       differently when collapsing) — document and move on
#   (c) type differences (string vs numeric keys) — coerce and re-check
#
# The PRODCOM panel (05_) has no R reference; we just sanity-check the .dta.

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

STATA_OUT <- OUT_DATA   # .dta files land in $OUT_DATA = REPO/data/processed
RDATA_DIR <- PROC_DATA  # .RData reference in NBB_data/processed

cat("==============================================================\n")
cat(" Stata ↔ R cross-check\n")
cat("   Stata outputs : ", STATA_OUT, "\n")
cat("   R reference   : ", RDATA_DIR, "\n")
cat("==============================================================\n\n")

# ---- small helpers ----------------------------------------------------------

compare_scalar <- function(label, r_val, s_val, tol = 1e-6) {
  diff <- abs(r_val - s_val)
  rel  <- diff / max(abs(r_val), 1)
  flag <- ifelse(rel < tol, "OK", "DIFF")
  cat(sprintf("    %-28s R = %14.4f   Stata = %14.4f   [%s]\n",
              label, r_val, s_val, flag))
}

summarise_num <- function(x, label) {
  x <- x[!is.na(x)]
  if (length(x) == 0) return(list(n = 0, sum = NA, mean = NA, median = NA))
  list(n = length(x), sum = sum(x), mean = mean(x),
       median = median(x))
}

compare_num_col <- function(r_df, s_df, col, tol = 1e-4) {
  if (!col %in% names(r_df) || !col %in% names(s_df)) {
    cat(sprintf("  [%s] column missing on one side (R: %s, Stata: %s)\n",
                col, col %in% names(r_df), col %in% names(s_df)))
    return(invisible(NULL))
  }
  r_stats <- summarise_num(r_df[[col]])
  s_stats <- summarise_num(s_df[[col]])
  cat(sprintf("  [%s]\n", col))
  compare_scalar("n (non-missing)",  r_stats$n,     s_stats$n, 0.005)
  compare_scalar("sum",               r_stats$sum,   s_stats$sum,   tol)
  compare_scalar("mean",              r_stats$mean,  s_stats$mean,  tol)
  compare_scalar("median",            r_stats$median,s_stats$median,tol)
}

# ---- 01 installation_year_emissions -----------------------------------------

cat("\n--- 01  installation_year_emissions -------------------------\n")
r_iye_file  <- file.path(RDATA_DIR, "installation_year_emissions.RData")
s_iye_file  <- file.path(STATA_OUT, "installation_year_emissions.dta")
if (file.exists(r_iye_file) && file.exists(s_iye_file)) {
  e <- new.env(); load(r_iye_file, envir = e)
  r_iye <- as_tibble(e$installation_year_emissions)
  s_iye <- read_dta(s_iye_file)
  cat(sprintf("  rows: R = %d   Stata = %d\n", nrow(r_iye), nrow(s_iye)))
  for (col in c("verified", "allocated_free", "allocated_total")) {
    r_col <- intersect(c(col, gsub("_", "", col), "allocatedFree",
                         "allocatedTotal")[1], names(r_iye))
    if (length(r_col)) {
      compare_num_col(r_iye %>% rename(!!col := !!r_col), s_iye, col)
    }
  }
} else {
  cat("  skipped — one or both files missing\n")
}

# ---- 02 firm_year_belgian_euets ---------------------------------------------

cat("\n--- 02  firm_year_belgian_euets -----------------------------\n")
r_fye_file <- file.path(RDATA_DIR, "firm_year_belgian_euets.RData")
s_fye_file <- file.path(STATA_OUT, "firm_year_belgian_euets.dta")
if (file.exists(r_fye_file) && file.exists(s_fye_file)) {
  e <- new.env(); load(r_fye_file, envir = e)
  r_fye <- as_tibble(e$firm_year_belgian_euets)
  s_fye <- read_dta(s_fye_file)
  cat(sprintf("  rows: R = %d   Stata = %d\n", nrow(r_fye), nrow(s_fye)))
  cat(sprintf("  distinct firms (vat/vat_ano): R = %d   Stata = %d\n",
              dplyr::n_distinct(r_fye$vat %||% r_fye$vat_ano),
              dplyr::n_distinct(s_fye$vat_ano)))
  for (col in c("emissions", "allocated_free", "allowance_shortage",
                "revenue", "value_added", "wage_bill")) {
    compare_num_col(r_fye, s_fye, col)
  }
} else {
  cat("  skipped — one or both files missing\n")
}

# ---- 03 eua_prices_annual ---------------------------------------------------

cat("\n--- 03  eua_prices_annual -----------------------------------\n")
r_eua_file <- file.path(OUT_DATA, "phase3_eua_prices.RData")  # from R pipeline
s_eua_file <- file.path(STATA_OUT, "eua_prices_annual.dta")
if (file.exists(r_eua_file) && file.exists(s_eua_file)) {
  e <- new.env(); load(r_eua_file, envir = e)
  r_eua <- as_tibble(e$eua_prices_annual)
  s_eua <- read_dta(s_eua_file)
  cat(sprintf("  rows: R = %d   Stata = %d\n", nrow(r_eua), nrow(s_eua)))
  for (col in c("eua_price")) compare_num_col(r_eua, s_eua, col, tol = 1e-2)
} else {
  cat("  skipped — one or both files missing\n")
}

# ---- 04 deflator ------------------------------------------------------------

cat("\n--- 04  deflator_nace4d_2005base ----------------------------\n")
r_def_file <- file.path(RDATA_DIR, "deflator_nace4d_2005base.RData")
s_def_file <- file.path(STATA_OUT, "deflator_nace4d_2005base.dta")
if (file.exists(r_def_file) && file.exists(s_def_file)) {
  e <- new.env(); load(r_def_file, envir = e)
  r_def <- as_tibble(e$deflator)
  s_def <- read_dta(s_def_file)
  cat(sprintf("  rows: R = %d   Stata = %d\n", nrow(r_def), nrow(s_def)))
  compare_num_col(r_def, s_def, "ppi", tol = 1e-2)

  # Spot-check: 2410 (iron & steel), 2351 (cement)
  for (code in c("2410", "2351")) {
    rr <- r_def %>% filter(nace4d == code) %>% arrange(year)
    ss <- s_def %>% filter(nace4d == code) %>% arrange(year)
    cat(sprintf("  NACE %s: R rows = %d  Stata rows = %d\n",
                code, nrow(rr), nrow(ss)))
    if (nrow(rr) > 0 && nrow(ss) > 0) {
      merged <- dplyr::inner_join(rr %>% select(year, ppi_R = ppi),
                                  ss %>% select(year, ppi_S = ppi), by = "year")
      cat(sprintf("    max |ppi_R - ppi_S| on overlap: %.3f\n",
                  max(abs(merged$ppi_R - merged$ppi_S))))
    }
  }
} else {
  cat("  skipped — one or both files missing\n")
}

# ---- 05 prodcom_analysis_panel ----------------------------------------------

cat("\n--- 05  prodcom_analysis_panel (no R reference) -------------\n")
s_pr_file <- file.path(STATA_OUT, "prodcom_analysis_panel.dta")
if (file.exists(s_pr_file)) {
  s_pr <- read_dta(s_pr_file)
  cat(sprintf("  rows: %d   distinct firms: %d   distinct pc8: %d\n",
              nrow(s_pr), dplyr::n_distinct(s_pr$vat_ano),
              dplyr::n_distinct(s_pr$pc8)))
  cat(sprintf("  year range: %d-%d\n", min(s_pr$year), max(s_pr$year)))
  cat(sprintf("  rows with positive exposure: %d\n",
              sum(!is.na(s_pr$exposure) & s_pr$exposure > 0)))
} else {
  cat("  skipped — file missing\n")
}

cat("\n==============================================================\n")
cat("Done. Lines flagged DIFF are divergences to investigate.\n")

# Small helper for null-coalesce (tibble bindings).
`%||%` <- function(a, b) if (!is.null(a)) a else b
