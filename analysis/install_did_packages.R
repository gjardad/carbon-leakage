# =============================================================================
# install_did_packages.R — one-time installer for the modern-DiD packages used
# by the §5.1 robustness program (R2-R7).
#
# Usage (RMD or local-1):
#   Rscript analysis/install_did_packages.R
#
# Handles the SSL-connect-error fallback we hit on local-1 (some packages
# fail with "SSL connect error" on the default libcurl method; wininet works).
# =============================================================================

# Try standard libcurl first, fall back to wininet on failure.
install_with_fallback <- function(pkg, repos = "https://cloud.r-project.org") {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("[ok] %s already installed (version %s)\n",
                pkg, as.character(packageVersion(pkg))))
    return(invisible(TRUE))
  }
  cat(sprintf("[..] installing %s ...\n", pkg))
  ok <- tryCatch({
    install.packages(pkg, repos = repos)
    requireNamespace(pkg, quietly = TRUE)
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (!ok) {
    cat(sprintf("[..] retrying %s with wininet method ...\n", pkg))
    old <- options(download.file.method = "wininet")
    on.exit(options(old), add = TRUE)
    install.packages(pkg, repos = repos)
    ok <- requireNamespace(pkg, quietly = TRUE)
  }
  if (!ok) {
    stop(sprintf("Failed to install %s", pkg))
  }
  cat(sprintf("[ok] %s installed (version %s)\n",
              pkg, as.character(packageVersion(pkg))))
}

install_gh_with_fallback <- function(repo, pkg = sub("^.*/", "", repo)) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("[ok] %s already installed (version %s)\n",
                pkg, as.character(packageVersion(pkg))))
    return(invisible(TRUE))
  }
  cat(sprintf("[..] installing %s from GitHub ...\n", repo))
  old <- options(download.file.method = "wininet")
  on.exit(options(old), add = TRUE)
  remotes::install_github(repo, upgrade = "never")
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("Failed to install %s from GitHub", pkg))
  }
  cat(sprintf("[ok] %s installed (version %s)\n",
              pkg, as.character(packageVersion(pkg))))
}

# 1. CRAN packages.
cran_pkgs <- c("DIDmultiplegtDYN", "DRDID", "mvtnorm", "remotes")
for (p in cran_pkgs) install_with_fallback(p)

# 2. polars (r-universe).
install_with_fallback("polars", repos = "https://rpolars.r-universe.dev")

# 3. GitHub-only packages.
install_gh_with_fallback("asheshrambachan/HonestDiD")
install_gh_with_fallback("jonathandroth/pretrends")

# 4. Verify all loaded.
all_pkgs <- c(cran_pkgs, "polars", "HonestDiD", "pretrends",
              "fixest", "data.table")
cat("\n=== Final status ===\n")
for (p in all_pkgs) {
  cat(sprintf("  %-20s %s\n", p,
              if (requireNamespace(p, quietly = TRUE)) "OK" else "MISSING"))
}
cat("\nDone.\n")
