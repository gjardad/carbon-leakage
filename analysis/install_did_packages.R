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

install_polars_multi_mirror <- function() {
  if (requireNamespace("polars", quietly = TRUE)) {
    cat(sprintf("[ok] polars already installed (version %s)\n",
                as.character(packageVersion("polars"))))
    return(invisible(TRUE))
  }
  mirrors <- c(
    "https://community.r-multiverse.org",
    "https://rpolars.r-universe.dev",
    "https://cloud.r-project.org"
  )
  old <- options(download.file.method = "wininet")
  on.exit(options(old), add = TRUE)
  for (m in mirrors) {
    cat(sprintf("[..] trying polars from %s ...\n", m))
    ok <- tryCatch({
      install.packages("polars", repos = m)
      requireNamespace("polars", quietly = TRUE)
    }, error = function(e) {cat("    ", conditionMessage(e), "\n"); FALSE},
       warning = function(w) FALSE)
    if (ok) {
      cat(sprintf("[ok] polars installed (version %s) from %s\n",
                  as.character(packageVersion("polars")), m))
      return(invisible(TRUE))
    }
  }
  invisible(FALSE)
}

# Install DIDmultiplegtDYN with a polars-aware fallback:
#   - On R ≥ 4.5: try the latest CRAN version (2.3.x); if polars install fails
#     (RMD firewall, etc.), fall back to 1.0.15 from CRAN archive.
#   - On R < 4.5: skip polars entirely; install 1.0.15 directly.
# Version 1.0.15 is pure R (NeedsCompilation: no), uses data.table + dplyr
# (no polars), and has the same did_multiplegt_dyn() function signature for
# the args used by R5/R7. No Rtools needed.
install_dcdh_dyn <- function() {
  if (requireNamespace("DIDmultiplegtDYN", quietly = TRUE)) {
    cat(sprintf("[ok] DIDmultiplegtDYN already installed (version %s)\n",
                as.character(packageVersion("DIDmultiplegtDYN"))))
    return(invisible(TRUE))
  }
  rver <- paste(R.version$major, R.version$minor, sep = ".")
  rmajmin <- as.numeric(sprintf("%s.%s",
                                R.version$major, sub("\\..*", "", R.version$minor)))
  on_r_ge_45 <- rmajmin >= 4.5
  cat(sprintf("[..] R version detected: %s (≥ 4.5? %s)\n", rver, on_r_ge_45))

  if (on_r_ge_45) {
    cat("[..] R >= 4.5: trying latest CRAN DIDmultiplegtDYN with polars backend\n")
    polars_ok <- install_polars_multi_mirror()
    if (polars_ok) {
      install_with_fallback("DIDmultiplegtDYN")
      return(invisible(TRUE))
    }
    cat("[..] polars unavailable; falling back to DIDmultiplegtDYN 1.0.15\n")
  } else {
    cat("[..] R < 4.5: polars-r has no R 4.4 binary; installing\n")
    cat("    DIDmultiplegtDYN 1.0.15 (last polars-free version) from CRAN archive\n")
  }

  # Install 1.0.15 from CRAN archive source tarball (NeedsCompilation: no).
  old <- options(download.file.method = "wininet", timeout = 300)
  on.exit(options(old), add = TRUE)
  url <- "https://cran.r-project.org/src/contrib/Archive/DIDmultiplegtDYN/DIDmultiplegtDYN_1.0.15.tar.gz"
  tmp <- file.path(tempdir(), "DIDmultiplegtDYN_1.0.15.tar.gz")
  download.file(url, tmp, mode = "wb")
  install.packages(tmp, repos = NULL, type = "source")
  if (!requireNamespace("DIDmultiplegtDYN", quietly = TRUE)) {
    stop("Failed to install DIDmultiplegtDYN 1.0.15 from source.")
  }
  cat(sprintf("[ok] DIDmultiplegtDYN 1.0.15 installed (no polars dependency)\n"))
}

# 1. CRAN packages (excluding DIDmultiplegtDYN — handled separately below).
cran_pkgs <- c("DRDID", "mvtnorm", "remotes")
for (p in cran_pkgs) install_with_fallback(p)

# 2. DIDmultiplegtDYN — polars-aware version selection.
install_dcdh_dyn()

# 3. GitHub-only packages.
install_gh_with_fallback("asheshrambachan/HonestDiD")
install_gh_with_fallback("jonathandroth/pretrends")

# 4. Verify all loaded.
all_pkgs <- c("DIDmultiplegtDYN", "DRDID", "mvtnorm", "HonestDiD",
              "pretrends", "fixest", "data.table")
cat("\n=== Final status ===\n")
for (p in all_pkgs) {
  cat(sprintf("  %-20s %s\n", p,
              if (requireNamespace(p, quietly = TRUE)) "OK" else "MISSING"))
}
# polars is optional — only relevant on R ≥ 4.5 with the latest DIDmultiplegtDYN.
cat(sprintf("  %-20s %s\n", "polars (optional)",
            if (requireNamespace("polars", quietly = TRUE))
              sprintf("OK (v%s)", packageVersion("polars"))
            else
              "MISSING (fine on R < 4.5 with DIDmultiplegtDYN 1.0.15)"))
cat(sprintf("  %-20s %s\n", "DIDmultiplegtDYN ver",
            as.character(packageVersion("DIDmultiplegtDYN"))))
cat("\nDone.\n")
