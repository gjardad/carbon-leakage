*! 00_paths.do
*! Central path configuration for the PRODCOM pass-through Stata workstream.
*! Every other .do file in this folder starts by running `do 00_paths.do`,
*! so setting paths correctly here is the only per-environment step.
*!
*! To adapt for a new environment, add a branch below that matches
*! `c(username)` and defines $DATA_DIR and $REPO_DIR. The remaining
*! globals ($RAW_DATA, $PROC_DATA, $OUT_DATA, ...) are derived.

version 15
clear all
set more off

local user = c(username)
display "00_paths.do: running as user `user'"

if "`user'" == "jota_" {
    * Local 1 (Gabriel). Used for local testing with the mock prod.dta.
    global DATA_DIR  "C:/Users/jota_/Documents/NBB_data"
    global REPO_DIR  "C:/Users/jota_/Documents/carbon-leakage"
}
else if "`user'" == "jardang" {
    * RMD (coauthor). EDIT THESE TWO PATHS if your layout differs.
    global DATA_DIR  "X:/Documents/JARDANG/data"
    global REPO_DIR  "C:/Users/jardang/Documents/carbon-leakage"
}
else {
    display as error "00_paths.do: no path branch defined for user `user'."
    display as error "Add a new `else if' block above matching c(username)."
    exit 198
}

global RAW_DATA   "$DATA_DIR/raw"
global PROC_DATA  "$DATA_DIR/processed"
global OUT_DATA   "$REPO_DIR/data/processed"
global OUT_FIG    "$REPO_DIR/output/figures"
global OUT_TAB    "$REPO_DIR/output/tables"

capture mkdir "$OUT_DATA"
capture mkdir "$OUT_FIG"
capture mkdir "$OUT_TAB"

display "  DATA_DIR  = $DATA_DIR"
display "  REPO_DIR  = $REPO_DIR"
display "  OUT_DATA  = $OUT_DATA"
