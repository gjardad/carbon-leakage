#!/usr/bin/env bash
# =============================================================================
# Sequential runner for §5.1 robustness items R5, R6, R7. Plan ref:
# imperative-whistling-acorn.md.
#
# Run from the repo root:
#   bash analysis/run_r5_r6_r7_batch.sh
#
# Continues past failures (logs each step's exit code) so one failing
# spec doesn't kill the whole batch. Final summary printed at end.
# All R-script stdout/stderr is also captured in
# output_${MACHINE_TAG}/logs/<script>.log for later inspection.
# =============================================================================

set -u
START_ALL=$(date +%s)

# Resolve repo root (this script lives in analysis/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

# Pick MACHINE_TAG from the same logic paths.R uses.
USER_LC=$(echo "$USER" | tr '[:upper:]' '[:lower:]')
case "$USER_LC" in
  jardang) MACHINE_TAG="rmd" ;;
  jota_)   MACHINE_TAG="local" ;;
  *)       MACHINE_TAG="local" ;;
esac
LOG_DIR="output_${MACHINE_TAG}/logs"
mkdir -p "$LOG_DIR"

# Locate Rscript. RMD-jardang and local-1-jota_ both run R for Windows.
RSCRIPT="${RSCRIPT:-Rscript}"
if ! command -v "$RSCRIPT" >/dev/null 2>&1; then
  # Common Windows install path.
  for cand in "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" \
              "/c/Program Files/R/R-4.4.1/bin/Rscript.exe" \
              "/c/Program Files/R/R-4.4.0/bin/Rscript.exe"; do
    if [ -x "$cand" ]; then RSCRIPT="$cand"; break; fi
  done
fi
echo "Using Rscript: $RSCRIPT"
echo "Machine tag:  $MACHINE_TAG"
echo "Log dir:      $LOG_DIR"
echo

# Pipeline (order matters: R7 builder must run before any R7 estimator).
SCRIPTS=(
  "analysis/phase6_a9_drdid_test_i.R"                  # R6 — DRDID Test I
  "analysis/phase6_a8_dcdh_test_h.R"                   # R5 — static dCdH Test H Phase IV
  "analysis/phase6_a8b_dcdh_test_h_phase2.R"           # R5 — static dCdH Test H Phase II
  "analysis/phase6_a10_build_timevarying_intensity.R"  # R7 builder
  "analysis/phase6_a10_dcdh_timevarying_test_h.R"      # R7 — intertemporal Test H Phase IV
  "analysis/phase6_a10b_dcdh_timevarying_test_i.R"     # R7 — Test I (negative finding)
  "analysis/phase6_a10c_dcdh_timevarying_phase2.R"     # R7 — Phase II Test H
)

declare -a STATUS
declare -a ELAPSED

for i in "${!SCRIPTS[@]}"; do
  script="${SCRIPTS[$i]}"
  base=$(basename "$script" .R)
  log="$LOG_DIR/${base}.log"
  echo "=================================================================="
  echo "[$((i+1))/${#SCRIPTS[@]}] $script"
  echo "    log -> $log"
  echo "=================================================================="
  start=$(date +%s)
  "$RSCRIPT" "$script" >"$log" 2>&1
  rc=$?
  end=$(date +%s)
  dur=$((end - start))
  STATUS[$i]=$rc
  ELAPSED[$i]=$dur
  if [ "$rc" -eq 0 ]; then
    echo "  -> OK ($(printf '%dm%ds' $((dur/60)) $((dur%60))))"
  else
    echo "  -> FAILED (exit $rc, $(printf '%dm%ds' $((dur/60)) $((dur%60))))"
    echo "  -> tail of $log:"
    tail -n 20 "$log" | sed 's/^/     /'
  fi
  echo
done

END_ALL=$(date +%s)
TOTAL=$((END_ALL - START_ALL))

echo "=================================================================="
echo "Summary"
echo "=================================================================="
printf "%-58s %-8s %-10s\n" "Script" "Status" "Duration"
for i in "${!SCRIPTS[@]}"; do
  rc="${STATUS[$i]}"
  dur="${ELAPSED[$i]}"
  if [ "$rc" -eq 0 ]; then s="OK"; else s="FAIL($rc)"; fi
  printf "%-58s %-8s %dm%02ds\n" "$(basename "${SCRIPTS[$i]}")" "$s" $((dur/60)) $((dur%60))
done
echo
echo "Total wall time: $((TOTAL/60))m$((TOTAL%60))s"
echo "Output tables in: output_${MACHINE_TAG}/tables/"
echo "Output figures in: output_${MACHINE_TAG}/figures/"
echo "Per-script logs in: $LOG_DIR/"
