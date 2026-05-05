# =============================================================================
# Diagnostic check for "Plan to address [Not yet run] sections":
#   (1) Does Phase II firm_cost_share exist on local-1, or does it need building?
#   (2) Does the importer x HS6 cell-level pair_exposure exist on customs panel?
#   (3) What is customs unit-value coverage (fraction of cells with both
#       value and quantity)?
#
# Run on local-1 (downsampled / mock data is fine for this diagnostic).
# =============================================================================

REPO_DIR <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
  error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
})

cat("\n###############################################################\n")
cat("# (1) Phase II firm_cost_share check\n")
cat("###############################################################\n\n")

# Inspect what's in firm_cost_share_flavors.RData -- the file that holds
# the constructed exposure measures.
fcs_path <- file.path(PROC_DATA, "firm_cost_share_flavors.RData")
if (file.exists(fcs_path)) {
  e <- new.env()
  load(fcs_path, envir = e)
  cat("Objects in firm_cost_share_flavors.RData:\n")
  for (nm in ls(envir = e)) {
    obj <- get(nm, envir = e)
    cat(sprintf("  %s: ", nm))
    if (is.data.frame(obj)) {
      cat(sprintf("data.frame with %d rows, columns: %s\n",
                  nrow(obj), paste(colnames(obj), collapse = ", ")))
    } else {
      cat(sprintf("class %s\n", paste(class(obj), collapse = ",")))
    }
  }

  # Look for a phase II-flavored variable.
  for (nm in ls(envir = e)) {
    obj <- get(nm, envir = e)
    if (is.data.frame(obj)) {
      cat(sprintf("\nColumns in %s:\n", nm))
      print(colnames(obj))
    }
  }
} else {
  cat(sprintf("NOT FOUND: %s\n", fcs_path))
}

# Also check whether any script in analysis/ builds a phase-II-window cost share.
cat("\nSearching analysis/ for any existing 2005-2008 / Phase II cost-share build:\n")
analysis_dir <- file.path(REPO_DIR, "analysis")
if (dir.exists(analysis_dir)) {
  cands <- list.files(analysis_dir, pattern = "\\.R$", full.names = TRUE)
  matches <- character(0)
  for (f in cands) {
    txt <- tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))
    if (any(grepl("2005.*2008|2005:2008|c\\(2005, 2008\\)|phase.?2|phase.?II|phase2|Phase 2|Phase II",
                  txt, ignore.case = TRUE))) {
      matches <- c(matches, basename(f))
    }
  }
  if (length(matches) > 0L) {
    cat("Candidate scripts referencing Phase II / 2005-2008:\n")
    for (m in matches) cat(sprintf("  %s\n", m))
  } else {
    cat("No analysis script appears to build a 2005-2008 / Phase II firm_cost_share.\n")
    cat("  Conclusion: Phase II exposure construction is NEW work (~0.5 day).\n")
  }
}

cat("\n###############################################################\n")
cat("# (2) Customs panel: does importer x HS6 pair_exposure exist?\n")
cat("###############################################################\n\n")

# Look for the customs panel file. Prefer the EXTENDED panel (built by P2 =
# phase2_build_customs_panel.R after the 2026-05 edits: 2000-2022 window
# with quantity preserved) over the older CMdG-replication panel (2000-2019,
# no quantity).
customs_paths <- c(
  file.path(PROC_DATA, "customs_import_panel_extended.RData"),       # P2 output
  file.path(PROC_DATA, "customs_import_panel_regulated.RData"),      # CMdG panel (no quantity)
  file.path(PROC_DATA, "mock_customs_import_panel_regulated.RData")  # local-1 mock
)
customs_path <- customs_paths[file.exists(customs_paths)][1]
cat(sprintf("Available customs panels in PROC_DATA:\n"))
for (p in customs_paths) {
  cat(sprintf("  %s%s\n", basename(p),
              if (file.exists(p)) "  [FOUND]" else "  [absent]"))
}
cat(sprintf("Using: %s\n\n", customs_path))

if (is.na(customs_path) || length(customs_path) == 0L) {
  cat("NOT FOUND: no customs panel locally. Check RMD.\n")
} else {
  cat(sprintf("Loading: %s\n", customs_path))
  e <- new.env()
  load(customs_path, envir = e)
  cat("Objects loaded:\n")
  for (nm in ls(envir = e)) {
    obj <- get(nm, envir = e)
    cat(sprintf("  %s: ", nm))
    if (is.data.frame(obj)) {
      cat(sprintf("data.frame with %d rows, columns:\n    %s\n",
                  nrow(obj),
                  paste(colnames(obj), collapse = "\n    ")))
    } else {
      cat(sprintf("class %s\n", paste(class(obj), collapse = ",")))
    }
  }

  # Check if any pair_exposure / EU-share variable exists.
  for (nm in ls(envir = e)) {
    obj <- get(nm, envir = e)
    if (is.data.frame(obj)) {
      pair_cols <- grep("pair.*expos|eu.*share|eu_share|source_eu",
                        colnames(obj), value = TRUE, ignore.case = TRUE)
      if (length(pair_cols) > 0L) {
        cat(sprintf("\nFound potential pair_exposure / EU-share columns in %s:\n  %s\n",
                    nm, paste(pair_cols, collapse = ", ")))
      }
    }
  }
}

cat("\n###############################################################\n")
cat("# (3) Customs unit-value coverage\n")
cat("###############################################################\n\n")

if (is.na(customs_path) || length(customs_path) == 0L) {
  cat("Skipping: customs panel not loaded.\n")
} else {
  e <- new.env()
  load(customs_path, envir = e)
  obj_name <- ls(envir = e)[1]
  customs <- as.data.table(get(obj_name, envir = e))

  # Identify value and quantity columns.
  val_col <- intersect(c("value", "value_eur", "import_value"), colnames(customs))[1]
  qty_col <- intersect(c("quantity", "quantity_kg", "import_kg",
                         "weight", "weight_kg"), colnames(customs))[1]
  cat(sprintf("Detected value column: %s\n", val_col))
  cat(sprintf("Detected quantity column: %s\n", qty_col))

  if (!is.na(val_col) && !is.na(qty_col)) {
    has_val <- !is.na(customs[[val_col]]) & customs[[val_col]] > 0
    has_qty <- !is.na(customs[[qty_col]]) & customs[[qty_col]] > 0
    n_total <- nrow(customs)
    n_val <- sum(has_val)
    n_qty <- sum(has_qty)
    n_both <- sum(has_val & has_qty)

    cat(sprintf("\nCustoms records: %d total\n", n_total))
    cat(sprintf("  with positive value:    %d (%.1f%%)\n",
                n_val, 100 * n_val / n_total))
    cat(sprintf("  with positive quantity: %d (%.1f%%)\n",
                n_qty, 100 * n_qty / n_total))
    cat(sprintf("  with BOTH (unit-value computable): %d (%.1f%%)\n",
                n_both, 100 * n_both / n_total))

    # By regulated vs not, if available.
    if ("is_regulated" %in% colnames(customs) ||
        "regulated_product" %in% colnames(customs)) {
      reg_col <- intersect(c("is_regulated", "regulated_product"),
                            colnames(customs))[1]
      reg_mask <- as.logical(customs[[reg_col]])
      cat(sprintf("\nCoverage by regulated status (%s):\n", reg_col))
      for (lbl in c(FALSE, TRUE)) {
        m <- (reg_mask == lbl) & !is.na(reg_mask)
        if (sum(m) > 0L) {
          cat(sprintf("  regulated = %s: %d rows; both = %.1f%%\n",
                      lbl, sum(m),
                      100 * sum(has_val[m] & has_qty[m]) / sum(m)))
        }
      }
    }

    # Headline: % of cells in 2010-2014 (pre-shock) with positive both.
    if ("year" %in% colnames(customs)) {
      pre <- customs[year %between% c(2010, 2014)]
      n_pre <- nrow(pre)
      hv_pre <- !is.na(pre[[val_col]]) & pre[[val_col]] > 0
      hq_pre <- !is.na(pre[[qty_col]]) & pre[[qty_col]] > 0
      cat(sprintf("\nPre-shock (2010-2014) coverage: %d rows, both = %.1f%%\n",
                  n_pre, 100 * sum(hv_pre & hq_pre) / n_pre))
    }
  } else {
    cat("ERROR: could not detect value/quantity columns. Check schema.\n")
  }
}

cat("\n###############################################################\n")
cat("# Summary\n")
cat("###############################################################\n")
cat("All three checks above. Use these to decide RMD scheduling.\n")
