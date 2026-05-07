# =============================================================================
# Sequential runner for §5.1 robustness items R5, R6, R7. Plan ref:
# imperative-whistling-acorn.md.
#
# Usage from PowerShell, cmd, RGui, or RStudio:
#
#   Rscript analysis/run_r5_r6_r7_batch.R          # from a shell
#   source("analysis/run_r5_r6_r7_batch.R")        # from R
#
# Each subscript runs in a fresh R process via system2(), so a crash in one
# does not affect the others. Per-script stdout/stderr lands in
# output_${MACHINE_TAG}/logs/<script>.log. Final summary printed at end.
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

LOG_DIR <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "logs")
dir.create(LOG_DIR, recursive = TRUE, showWarnings = FALSE)

# Where Rscript lives (the same R interpreter we're running under).
RSCRIPT <- file.path(R.home("bin"), "Rscript")

cat("Repo dir:    ", REPO_DIR, "\n")
cat("Machine tag: ", MACHINE_TAG, "\n")
cat("Rscript:     ", RSCRIPT, "\n")
cat("Log dir:     ", LOG_DIR, "\n\n")

# Pipeline order (R7 builder must run before any R7 estimator).
scripts <- c(
  "analysis/phase6_a9_drdid_test_i.R",                  # R6 — DRDID Test I
  "analysis/phase6_a8_dcdh_test_h.R",                   # R5 — static dCdH Test H Phase IV
  "analysis/phase6_a8b_dcdh_test_h_phase2.R",           # R5 — static dCdH Test H Phase II
  "analysis/phase6_a10_build_timevarying_intensity.R",  # R7 builder
  "analysis/phase6_a10_dcdh_timevarying_test_h.R",      # R7 — Test H Phase IV
  "analysis/phase6_a10b_dcdh_timevarying_test_i.R",     # R7 — Test I (negative finding)
  "analysis/phase6_a10c_dcdh_timevarying_phase2.R"      # R7 — Phase II Test H
)

status_all <- integer(length(scripts))
elapsed    <- numeric(length(scripts))
start_all  <- Sys.time()

for (i in seq_along(scripts)) {
  scr <- scripts[i]
  base <- sub("\\.R$", "", basename(scr))
  log  <- file.path(LOG_DIR, paste0(base, ".log"))
  scr_path <- file.path(REPO_DIR, scr)

  cat("==================================================================\n")
  cat(sprintf("[%d/%d] %s\n", i, length(scripts), scr))
  cat(sprintf("    log -> %s\n", log))
  cat("==================================================================\n")
  flush.console()

  t0 <- Sys.time()
  # system2 runs the subscript in a fresh R process; stdout = stderr = log.
  rc <- tryCatch(
    system2(RSCRIPT, args = shQuote(scr_path),
            stdout = log, stderr = log, wait = TRUE),
    error = function(e) {
      cat("    system2 error:", conditionMessage(e), "\n")
      999L
    })
  t1 <- Sys.time()
  dur <- as.numeric(difftime(t1, t0, units = "secs"))
  status_all[i] <- rc
  elapsed[i]    <- dur

  if (isTRUE(rc == 0)) {
    cat(sprintf("  -> OK (%dm%02ds)\n\n",
                as.integer(dur) %/% 60L, as.integer(dur) %% 60L))
  } else {
    cat(sprintf("  -> FAILED (exit %s, %dm%02ds)\n",
                as.character(rc), as.integer(dur) %/% 60L,
                as.integer(dur) %% 60L))
    cat("  -> tail of log:\n")
    if (file.exists(log)) {
      tail_lines <- tryCatch(tail(readLines(log, warn = FALSE), 20),
                             error = function(e) character(0))
      for (ln in tail_lines) cat("     ", ln, "\n")
    }
    cat("\n")
  }
  flush.console()
}

end_all <- Sys.time()
total <- as.numeric(difftime(end_all, start_all, units = "secs"))

cat("==================================================================\n")
cat("Summary\n")
cat("==================================================================\n")
cat(sprintf("%-58s %-10s %s\n", "Script", "Status", "Duration"))
for (i in seq_along(scripts)) {
  rc <- status_all[i]; dur <- elapsed[i]
  s <- if (isTRUE(rc == 0)) "OK" else sprintf("FAIL(%s)", rc)
  cat(sprintf("%-58s %-10s %dm%02ds\n",
              basename(scripts[i]), s,
              as.integer(dur) %/% 60L, as.integer(dur) %% 60L))
}
cat(sprintf("\nTotal wall time: %dm%02ds\n",
            as.integer(total) %/% 60L, as.integer(total) %% 60L))
cat(sprintf("Output tables in: output_%s/tables/\n", MACHINE_TAG))
cat(sprintf("Output figures in: output_%s/figures/\n", MACHINE_TAG))
cat(sprintf("Per-script logs in: %s/\n", LOG_DIR))
