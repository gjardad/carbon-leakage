*! 05_build_prodcom_panel.do
*! Build the PRODCOM firm × PC8 × year analysis panel for pass-through
*! regressions. Annualises the monthly PRODCOM file, attaches firm-level
*! ETS exposure (shortage × EUA / cost), NACE4d deflator, and base-period
*! exposure (for Bartik-style specifications).
*!
*! No R equivalent — this workstream is PRODCOM-specific.
*!
*! Inputs
*!   $RAW_DATA/NBB/prod.dta
*!   $OUT_DATA/firm_year_belgian_euets.dta   (from 02_)
*!   $OUT_DATA/eua_prices_annual.dta         (from 03_)
*!   $OUT_DATA/deflator_nace4d_2005base.dta  (from 04_)
*!
*! Output
*!   $OUT_DATA/prodcom_analysis_panel.dta
*!
*! ID merging. On RMD the coauthor's prod.dta has an anonymised firm id
*! ("ID") that should correspond to vat_ano in Annual_Accounts and
*! EUTL_Belgium. On the local mock file ID is a small numeric index
*! that will NOT match the real vat_ano hashes — the pipeline still runs
*! and produces a panel, just with 0 merge matches on the ETS side.
*! If on RMD prod.dta's ID uses a different convention, add a crosswalk
*! merge at the "ID -> vat_ano" step below.

do "`c(pwd)'/00_paths.do"

local base_window_start 2013
local base_window_end   2016

* =============================================================================
* STEP 1. Load PRODCOM and annualise to firm × pc8 × year
* =============================================================================

use "$RAW_DATA/NBB/prod.dta", clear

* Rename ID → vat_ano (convention used throughout the rest of the pipeline).
rename ID vat_ano

* Coerce vat_ano to string so it merges with Annual_Accounts / EUTL_Belgium
* (which store vat_ano as 64-char hashes).
capture confirm string variable vat_ano
if _rc {
    tostring vat_ano, replace force
}

* Sanity: drop rows with missing or non-positive v/q (can't form a price).
drop if missing(v) | missing(q) | v <= 0 | q <= 0

* Annualise: sum value and quantity per firm × pc8 × year.
collapse (sum) v q, by(vat_ano pc8 year)

gen double price = v / q
gen double log_price = log(price)

* Panel id for within-firm × pc8 time series.
egen panelid = group(vat_ano pc8)
xtset panelid year

* Δ log(price) within firm × pc8.
gen double d_log_price = log_price - L.log_price

* NACE 4d derived from PC8 (first 4 digits of the 8-digit code).
capture confirm string variable pc8
if _rc {
    gen pc8_str = string(pc8, "%08.0f")
}
else {
    gen pc8_str = pc8
    * Pad to 8 characters if shorter.
    replace pc8_str = "0" + pc8_str if strlen(pc8_str) == 7
    replace pc8_str = "00" + pc8_str if strlen(pc8_str) == 6
}
gen str4 nace4d = substr(pc8_str, 1, 4)
drop pc8_str

tempfile prodcom_annual
save "`prodcom_annual'"

* =============================================================================
* STEP 2. Attach firm-level ETS exposure
* =============================================================================

use "$OUT_DATA/firm_year_belgian_euets.dta", clear
keep vat_ano year emissions allocated_free revenue value_added wage_bill

* Cost denominator = material inputs + wage bill
*                  = (revenue - value_added) + wage_bill.
gen double cost_ivt = (revenue - value_added) + wage_bill

* Shortage (non-negative).
gen double shortage = emissions - allocated_free
replace    shortage = 0 if missing(shortage) | shortage < 0

keep vat_ano year emissions allocated_free shortage cost_ivt
tempfile firm_ets
save "`firm_ets'"

use "`prodcom_annual'", clear
merge m:1 vat_ano year using "`firm_ets'", keep(master match) nogen

* Firms not in the ETS panel are non-ETS → zero exposure.
foreach v in emissions allocated_free shortage cost_ivt {
    replace `v' = 0 if missing(`v')
}

gen byte ets_firm = shortage > 0 | emissions > 0

* =============================================================================
* STEP 3. Attach annual EUA price and build exposure_{i,t}
* =============================================================================

merge m:1 year using "$OUT_DATA/eua_prices_annual.dta", ///
    keepusing(eua_price phase) keep(master match) nogen

gen double exposure = .
replace    exposure = shortage * eua_price / cost_ivt if cost_ivt > 0

* =============================================================================
* STEP 4. Base-period shortage (for Bartik-style specification)
*         = mean shortage in the pre-period window, per firm.
* =============================================================================

preserve
    use "`firm_ets'", clear
    keep if inrange(year, `base_window_start', `base_window_end')
    collapse (mean) base_shortage = shortage, by(vat_ano)
    tempfile base_sh
    save "`base_sh'"
restore

merge m:1 vat_ano using "`base_sh'", keep(master match) nogen
replace base_shortage = 0 if missing(base_shortage)

* Bartik-style shock: base shortage × contemporaneous EUA price.
gen double bartik_exposure = base_shortage * eua_price

* =============================================================================
* STEP 5. Attach NACE4d PPI deflator (optional — used for real-price specs)
* =============================================================================

merge m:1 nace4d year using "$OUT_DATA/deflator_nace4d_2005base.dta", ///
    keepusing(ppi ppi_source) keep(master match) nogen

gen double price_real   = cond(!missing(ppi) & ppi > 0, price / (ppi/100), .)
gen double log_price_real = log(price_real)

sort panelid year
gen double d_log_price_real = log_price_real - log_price_real[_n-1] if panelid == panelid[_n-1]

* =============================================================================
* STEP 6. Save
* =============================================================================

order vat_ano pc8 nace4d year panelid v q price log_price d_log_price ///
      price_real log_price_real d_log_price_real ///
      ets_firm emissions allocated_free shortage cost_ivt eua_price ///
      exposure base_shortage bartik_exposure phase ppi ppi_source

compress
save "$OUT_DATA/prodcom_analysis_panel.dta", replace
display as result "Saved: $OUT_DATA/prodcom_analysis_panel.dta  (N = " _N ")"

* -----------------------------------------------------------------------------
* Diagnostics
* -----------------------------------------------------------------------------

display _n "=== Panel dimensions ==="
display "Observations           : " _N
quietly levelsof vat_ano
display "Distinct firms         : " r(r)
quietly levelsof pc8
display "Distinct PC8 products  : " r(r)
summarize year, meanonly
display "Year range             : " r(min) " - " r(max)

display _n "=== ETS coverage ==="
count if ets_firm == 1
display "ETS firm-year-product rows: " r(N)
count if exposure > 0 & !missing(exposure)
display "Rows with positive exposure: " r(N)

display _n "=== Exposure distribution (non-zero) ==="
summarize exposure if exposure > 0 & !missing(exposure), detail

display _n "=== Δ log(price) distribution ==="
summarize d_log_price, detail
