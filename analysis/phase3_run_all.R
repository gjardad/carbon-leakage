# phase3_run_all.R
#
# One-click runner: builds the B2B CMdG panel, then runs the regression with
# control-group robustness, then the event study. Use on RMD when you want
# to go for a run while it churns.
#
# Each script is sourced in its own local environment so variables don't
# leak between steps. Each step's wall-clock time is reported.
#
# Usage (from any directory inside the repo):
#   Rscript analysis/phase3_run_all.R
#
# Stops on first error.

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)

steps <- c(
  "phase3_build_b2b_cmdj_panel.R",
  "phase3_b2b_cmdj_did.R",
  "phase3_b2b_cmdj_eventstudy.R"
)

t_total <- Sys.time()
for (s in steps) {
  path <- file.path(REPO_DIR, "analysis", s)
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("RUNNING: ", s, "\n", sep = "")
  cat(strrep("=", 70), "\n", sep = "")
  t0 <- Sys.time()
  ok <- tryCatch({
    sys.source(path, envir = new.env())
    TRUE
  }, error = function(e) {
    cat("\n!!! ERROR in ", s, "\n", sep = "")
    cat(conditionMessage(e), "\n")
    FALSE
  })
  dur <- round(as.numeric(Sys.time() - t0, units = "mins"), 2)
  cat("\n--- DONE: ", s, " (", dur, " min) ---\n", sep = "")
  if (!ok) {
    cat("\nStopping: subsequent steps depend on this one.\n")
    quit(save = "no", status = 1)
  }
}

total_dur <- round(as.numeric(Sys.time() - t_total, units = "mins"), 2)
cat("\n", strrep("=", 70), "\n", sep = "")
cat("ALL THREE PHASE 3 SCRIPTS DONE in ", total_dur, " min total.\n", sep = "")
cat(strrep("=", 70), "\n", sep = "")
