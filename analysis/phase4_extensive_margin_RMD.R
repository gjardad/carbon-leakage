###############################################################################
# phase4_extensive_margin_RMD.R
#
# PURPOSE
#   Batch-specific orchestrator: source only the two new extensive-margin
#   analyses on RMD against the full (non-downsampled) NBB data.
#
#   Use this when you've already run the main orchestrator
#   (phase4_reallocation_RMD.R) and only want to refresh the new outputs
#   without re-rendering the within-NACE4d intensive-margin and across-
#   NACE4d plots.
#
# OUTPUTS (in OUTPUT_FIG / OUTPUT_TAB)
#   Plots
#     1. phase4_within_nace4d_extensive_DiD.{png,pdf}
#          Top-omega vs bottom-omega supplier survival lines, 3 facets,
#          95% bootstrap CIs.
#     2. phase4_new_relationships_omega_rank_def1.{png,pdf}
#          Mean year-t omega percentile rank of new-supplier relationships,
#          omega = shortage / total_cost.
#     3. phase4_new_relationships_omega_rank_def2.{png,pdf}
#          Same, omega = emissions / total_cost.
#   Tables
#     - phase4_within_nace4d_extensive_DiD_pooled.csv
#     - phase4_within_nace4d_extensive_DiD_coefs.csv
#     - phase4_new_relationships_omega_rank_yearly.csv
#     - phase4_new_relationships_omega_rank_pre_post.csv
#     - phase4_new_relationships_omega_rank_obs.csv
#
# DEPENDENCIES
#   - phase3_firm_exposure.RData  (built by phase3_build_exposure_panel.R;
#     skipped here unless missing).
#   - b2b_selected_sample.RData, annual_accounts_selected_sample.RData
#     (raw NBB-side data already on RMD).
#
# USAGE
#   Rscript analysis/phase4_extensive_margin_RMD.R
###############################################################################

ORCH_REPO_DIR <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
  error = function(e) normalizePath(getwd(), winslash = "/")
)
while (!file.exists(file.path(ORCH_REPO_DIR, "paths.R"))) {
  ORCH_REPO_DIR <- dirname(ORCH_REPO_DIR)
}
source(file.path(ORCH_REPO_DIR, "paths.R"))

setwd(REPO_DIR)

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

# Build prereq if missing
fe_path <- file.path(OUT_DATA, "phase3_firm_exposure.RData")
eua_path <- file.path(OUT_DATA, "phase3_eua_prices.RData")
if (!file.exists(eua_path)) run_script("analysis/phase3_eua_prices.R")
if (!file.exists(fe_path))  run_script("analysis/phase3_build_exposure_panel.R")

run_script("analysis/phase4_within_nace4d_extensive_DiD.R")
run_script("analysis/phase4_new_relationships_omega_rank.R")

selected_plots <- c(
  "phase4_within_nace4d_extensive_DiD.pdf",
  "phase4_new_relationships_omega_rank_def1.pdf",
  "phase4_new_relationships_omega_rank_def2.pdf"
)
cat("\n", strrep("=", 72), "\n",
    "Orchestrator finished. Plots in:\n",
    "  ", OUTPUT_FIG, "\n",
    strrep("=", 72), "\n", sep = "")
for (f in selected_plots) {
  p <- file.path(OUTPUT_FIG, f)
  status <- if (file.exists(p)) "OK  " else "MISS"
  cat(sprintf("  [%s] %s\n", status, f))
}
cat("\nMachine tag: ", MACHINE_TAG, "\n", sep = "")
cat("Done.\n")
