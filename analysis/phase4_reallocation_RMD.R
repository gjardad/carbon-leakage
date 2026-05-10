###############################################################################
# phase4_reallocation_RMD.R
#
# PURPOSE
#   One-shot orchestrator: source every script needed to produce the ten
#   selected within- and across-NACE4d reallocation plots on RMD against
#   the full (non-downsampled) NBB data.
#
# SELECTED OUTPUT PLOTS (in OUTPUT_FIG)
#   Within-NACE4d reallocation
#     1. phase4_within_nace4d_reallocation_topQ_buyertotal.pdf
#           Top-quartile cells (top-omega + bottom-omega supplier).
#     2. phase4_within_nace4d_reallocation_allcells_buyertotal.pdf
#           All multi-supplier cells (top-omega + bottom-omega supplier).
#     3. phase4_within_nace4d_reallocation_placebo_anyNACE4d.pdf
#           R_jt placebo: treated vs no-EUTL placebo, all NACE4d.
#     4. phase4_within_nace4d_reallocation_placebo_etsNACE4d.pdf
#           R_jt placebo: treated vs no-EUTL placebo, ETS-treated NACE4d only.
#     5. phase4_within_nace4d_reallocation_pooled_combined_raw.pdf
#           Headline raw within-NACE4d expenditure share on top-omega supplier.
#     6. phase4_supplier_count_share_multi_by_year.pdf
#           Share of buyer-NACE4d cells with >=2 suppliers, by year.
#     7. phase4_supplier_count_hist_by_interval.pdf
#           Distribution of #suppliers per buyer x ETS-NACE4d cell, by interval.
#   Across-NACE4d margin
#     8. phase4_across_nace4d_intensive_margin.pdf
#           Buyer-level expenditure share on ETS-treated NACE4d, by year.
#     9. phase4_across_nace4d_extensive_margin.pdf
#           Share of B2B-active buyers buying from any ETS-treated NACE4d.
#    10. phase4_within_nace4d_extensive_margin.pdf
#           Among buyers in ETS-treated NACE4d, share buying from an ETS firm.
#
# DEPENDENCY GRAPH
#   raw EUTL panel + ICAP price files
#       -> phase3_eua_prices.R         -> phase3_eua_prices.RData
#                                       -> phase3_build_exposure_panel.R
#                                       -> phase3_firm_exposure.RData
#   phase3_firm_exposure + b2b + AA
#       -> phase4_within_nace4d_reallocation_plots.R     [plot 5; produces panel CSV]
#       -> phase4_within_nace4d_reallocation_topQ.R      [plots 1, 2; reads panel CSV]
#       -> phase4_within_nace4d_reallocation_placebo.R   [plots 3, 4]
#       -> phase4_supplier_count_distribution.R          [plots 6, 7]
#       -> phase4_across_nace4d_intensive_margin.R       [plot 8]
#       -> phase4_across_nace4d_extensive_margin.R       [plot 9]
#       -> phase4_within_nace4d_extensive_margin.R       [plot 10]
#
# USAGE
#   On RMD (or any machine where paths.R resolves correctly), from the repo
#   root:
#     Rscript analysis/phase4_reallocation_RMD.R
#   The script will:
#     - build phase3_eua_prices.RData and phase3_firm_exposure.RData if absent;
#     - run the seven phase4 scripts in dependency order;
#     - print a summary with the resolved paths of the ten selected plots.
#
# NOTES
#   - Each child script is sourced into an isolated environment so its
#     `rm(list = ls())` cannot interfere with the orchestrator's state.
#   - Existing intermediate data files (phase3_*.RData) are reused if present;
#     delete them first if you want a full rebuild.
###############################################################################

# Capture the orchestrator's repo location BEFORE sourcing anything.
ORCH_REPO_DIR <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
  error = function(e) normalizePath(getwd(), winslash = "/")
)
while (!file.exists(file.path(ORCH_REPO_DIR, "paths.R"))) {
  ORCH_REPO_DIR <- dirname(ORCH_REPO_DIR)
}
source(file.path(ORCH_REPO_DIR, "paths.R"))

# Set wd to REPO_DIR so any inner script that falls back to getwd() finds
# paths.R via the parent-walk.
setwd(REPO_DIR)

# Helper -- run a script in an isolated environment.
# `rm(list = ls())` inside the child clears the local env, not globalenv().
run_script <- function(rel_path) {
  full_path <- file.path(REPO_DIR, rel_path)
  if (!file.exists(full_path))
    stop("Script not found: ", full_path)
  cat("\n", strrep("=", 72), "\n",
      ">>> Running: ", rel_path, "\n",
      strrep("=", 72), "\n", sep = "")
  e <- new.env(parent = globalenv())
  source(full_path, local = e, chdir = FALSE)
  cat(strrep("-", 72), "\n",
      "<<< Done   : ", rel_path, "\n",
      strrep("-", 72), "\n", sep = "")
  invisible(NULL)
}

# ----------------------------------------------------------------------------
# Step 1: Upstream prerequisites (build only if their outputs are missing)
# ----------------------------------------------------------------------------
eua_path <- file.path(OUT_DATA, "phase3_eua_prices.RData")
fe_path  <- file.path(OUT_DATA, "phase3_firm_exposure.RData")

if (!file.exists(eua_path)) {
  cat(sprintf("\n[prereq] phase3_eua_prices.RData missing -- building.\n"))
  run_script("analysis/phase3_eua_prices.R")
} else {
  cat(sprintf("\n[prereq] phase3_eua_prices.RData OK -- skipping build.\n"))
}

if (!file.exists(fe_path)) {
  cat(sprintf("\n[prereq] phase3_firm_exposure.RData missing -- building.\n"))
  run_script("analysis/phase3_build_exposure_panel.R")
} else {
  cat(sprintf("\n[prereq] phase3_firm_exposure.RData OK -- skipping build.\n"))
}

# ----------------------------------------------------------------------------
# Step 2: Within-NACE4d analysis scripts (in dependency order)
# ----------------------------------------------------------------------------
# Plot 5 + the panel CSV used downstream by topQ
run_script("analysis/phase4_within_nace4d_reallocation_plots.R")

# Plots 1 & 2 (depends on panel CSV from the previous step)
run_script("analysis/phase4_within_nace4d_reallocation_topQ.R")

# Plots 3 & 4 (independent of topQ; uses firm_exposure + b2b + AA)
run_script("analysis/phase4_within_nace4d_reallocation_placebo.R")

# Plots 6 & 7 (independent)
run_script("analysis/phase4_supplier_count_distribution.R")

# ----------------------------------------------------------------------------
# Step 3: Across-NACE4d margin scripts (independent, can run in any order)
# ----------------------------------------------------------------------------
# Plot 8
run_script("analysis/phase4_across_nace4d_intensive_margin.R")

# Plot 9
run_script("analysis/phase4_across_nace4d_extensive_margin.R")

# Plot 10
run_script("analysis/phase4_within_nace4d_extensive_margin.R")

# Regular within-treated DiD on top-omega vs bottom-omega (no plot; coefs CSV)
run_script("analysis/phase4_within_nace4d_reallocation_did.R")

# Heterogeneity cuts: top-Q by NACE4d input share + top-Q by omega gap.
# Two PDFs and a DiD coefs CSV.
run_script("analysis/phase4_within_nace4d_reallocation_topQ_heterogeneity.R")

# ----------------------------------------------------------------------------
# Step 4: Summary
# ----------------------------------------------------------------------------
selected_plots <- c(
  # Within-NACE4d reallocation
  "phase4_within_nace4d_reallocation_topQ_buyertotal.pdf",
  "phase4_within_nace4d_reallocation_allcells_buyertotal.pdf",
  "phase4_within_nace4d_reallocation_placebo_anyNACE4d.pdf",
  "phase4_within_nace4d_reallocation_placebo_etsNACE4d.pdf",
  "phase4_within_nace4d_reallocation_pooled_combined_raw.pdf",
  "phase4_supplier_count_share_multi_by_year.pdf",
  "phase4_supplier_count_hist_by_interval.pdf",
  # Across-NACE4d margins
  "phase4_across_nace4d_intensive_margin.pdf",
  "phase4_across_nace4d_extensive_margin.pdf",
  "phase4_within_nace4d_extensive_margin.pdf"
)

cat("\n", strrep("=", 72), "\n",
    "Orchestrator finished. Selected plots in:\n",
    "  ", OUTPUT_FIG, "\n",
    strrep("=", 72), "\n", sep = "")

for (f in selected_plots) {
  p <- file.path(OUTPUT_FIG, f)
  status <- if (file.exists(p)) "OK  " else "MISS"
  cat(sprintf("  [%s] %s\n", status, f))
}

cat("\nMachine tag: ", MACHINE_TAG, "\n", sep = "")
cat("Done.\n")
