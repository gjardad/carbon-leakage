*! 02_build_firm_year_euets.do
*! Build firm-year ETS panel for Belgian firms: emissions, free allocation,
*! shortage, revenue, value added, wage bill, NACE5d, and productivity
*! measures.
*!
*! Port of:
*!   - inferring_emissions/preprocess/build_firm_year_emissions.R
*!       (installation_year_emissions → firm_year_emissions via account.csv)
*!   - inferring_emissions/preprocess/build_firm_year_euets.R
*!       (firm_year_emissions + EUTL_Belgium + Annual_Accounts
*!        → firm_year_belgian_euets)
*!
*! Inputs
*!   $OUT_DATA/installation_year_emissions.dta    (from 01_)
*!   $OUT_DATA/installation_year_in_belgium.dta   (from 01_)
*!   $RAW_DATA/EUTL/Oct_2024_version/account.csv
*!   $RAW_DATA/NBB/EUTL_Belgium.dta
*!   $RAW_DATA/NBB/Annual_Accounts_MASTER_ANO.dta
*!
*! Output
*!   $OUT_DATA/firm_year_belgian_euets.dta
*!
*! NOTE: The R builder also attaches an `in_sample` dummy from
*! `annual_accounts_selected_sample.RData`. That sample-selection step is
*! not yet ported; this script sets `in_sample = .` as a placeholder.
*! The PRODCOM pass-through regressions don't rely on `in_sample`, but
*! the sector-level analysis does — if you need it, port
*! `annual_accounts_sample_selection.R` separately.

do "`c(pwd)'/00_paths.do"

* -----------------------------------------------------------------------------
* STEP 1. account.csv → {bvd_id, installation_id} for EUTL operator accounts
* -----------------------------------------------------------------------------

import delimited using "$RAW_DATA/EUTL/Oct_2024_version/account.csv", ///
    varnames(1) stringcols(_all) encoding("utf-8") clear

rename accounttype_id account_type
rename bvdid          bvd_id
rename id             account_id
rename companyregistrationnumber firm_id

keep account_id account_type bvd_id installation_id firm_id
keep if inlist(account_type, "100-7", "120-0")

* A firm (bvd) may hold multiple accounts for the same installation; keep
* distinct {bvd_id, installation_id} pairs.
keep bvd_id installation_id
* Stata's joinby matches "" to "" (unlike R's NA-to-NA non-match); drop
* empty-bvd rows so they don't create spurious matches downstream.
drop if bvd_id == "" | missing(bvd_id)
duplicates drop

tempfile account_bvd
save "`account_bvd'"

* -----------------------------------------------------------------------------
* STEP 2. installation_year_emissions ⟕ {bvd_id, installation_id}
*         → firm-year aggregates
* -----------------------------------------------------------------------------

use "$OUT_DATA/installation_year_emissions.dta", clear

* Ensure installation_id is string for the string-key merge.
capture confirm string variable installation_id
if _rc {
    tostring installation_id, replace force
}

* A single installation_id can legitimately appear under several bvd_id
* (e.g. change of operator). R's left_join produces all pairwise matches;
* the Stata equivalent is `joinby` with `unmatched(master)` to keep
* installation-years with no account match.
joinby installation_id using "`account_bvd'", unmatched(master)
duplicates drop

* Rows without a matched bvd_id (installation not in the account registry)
* cannot be assigned to a firm. R keeps them with empty bvd_id then drops
* at the bottom of the firm-year collapse; same here.
replace bvd_id = "" if missing(bvd_id)
capture drop _merge

* --- Firm-year aggregation.
* Sums: allocated_free, allocated_total.
* Emissions: sum(verified, na.rm=TRUE) if any verified is non-missing in the
*            group, else missing. This distinguishes "regulated with 0" from
*            "not regulated that year".
* activity_id / nace_id: from the installation with the largest verified
*            emissions (fallback to first when all verified are missing).

gen byte _has_verified = !missing(verified)

* Sort so that within (bvd_id, year), non-missing verified come first,
* then descending by verified. [1] is then "top verified", or first row
* when all are missing.
gsort bvd_id year -_has_verified -verified

by bvd_id year: gen activity_id_top = activity_id[1]
by bvd_id year: gen nace_id_top     = nace_id[1]

* Emissions: sum of verified when at least one is non-missing, else missing.
by bvd_id year: egen any_verified  = max(_has_verified)
by bvd_id year: egen sum_verified  = total(verified)
gen emissions = sum_verified
replace emissions = . if any_verified == 0

* Free / total allowances: simple sums (NAs were already zeroed in 01_).
by bvd_id year: egen allocated_free  = total(allocated_free)
by bvd_id year: egen allocated_total = total(allocated_total)

* country_id: first in group (R uses `first(country_id)`).
by bvd_id year: gen country_id_top = country_id[1]

* Collapse to one row per (bvd_id, year).
by bvd_id year: keep if _n == 1

keep bvd_id year emissions allocated_free allocated_total ///
     country_id_top activity_id_top nace_id_top
rename country_id_top  country_id
rename activity_id_top activity_id
rename nace_id_top     nace_id_from_eutl

drop if bvd_id == ""

tempfile firm_year_emissions
save "`firm_year_emissions'"

* -----------------------------------------------------------------------------
* STEP 3. Attach vat_ano via EUTL_Belgium.dta → Belgian subset
* -----------------------------------------------------------------------------

use "$RAW_DATA/NBB/EUTL_Belgium.dta", clear
rename bvdid bvd_id
keep bvd_id vat_ano
drop if bvd_id == "" | missing(bvd_id) | vat_ano == "" | missing(vat_ano)
duplicates drop

tempfile bvd_vat
save "`bvd_vat'"

use "`firm_year_emissions'", clear
* bvd_vat can have multiple vat_ano per bvd_id (historical VAT changes).
* Use joinby so all vat_ano are kept; dedup on (vat_ano, year, bvd_id)
* happens at the bottom of this script.
joinby bvd_id using "`bvd_vat'", unmatched(master)
duplicates drop

* Drop non-Belgian firms (no vat_ano).
drop if missing(vat_ano)

tempfile belgian_ets
save "`belgian_ets'"

* -----------------------------------------------------------------------------
* STEP 4. Merge Annual_Accounts variables onto firm-year
* -----------------------------------------------------------------------------

use "$RAW_DATA/NBB/Annual_Accounts_MASTER_ANO.dta", clear
keep vat_ano year v_0022_27 turnover_VAT v_0001023 v_0001003 v_0009800 nace5d

rename v_0022_27    capital
rename turnover_VAT revenue
rename v_0001023    wage_bill
rename v_0001003    fte
rename v_0009800    value_added

tostring nace5d, replace force

* Annual_Accounts is keyed on (vat_ano, year) — but there can be duplicate
* entries per firm-year (e.g. from amendments). Keep one record per key
* before merging. If multiple exist, Stata's `duplicates drop ... force`
* keeps the first; this matches R's default join behaviour after distinct().
duplicates drop vat_ano year, force

tempfile ann_acc
save "`ann_acc'"

use "`belgian_ets'", clear
merge m:1 vat_ano year using "`ann_acc'", keep(master match) nogen

* -----------------------------------------------------------------------------
* STEP 5. Derived variables: productivity + shortage
* -----------------------------------------------------------------------------

* Productivity measures: log(revenue / X), with 0 returned when either
* numerator or denominator is 0 (and missing propagated otherwise).
foreach pair in "emissions emissions_prod" "fte fte_prod" ///
                "wage_bill labor_prod" "capital capital_prod" {
    local denom : word 1 of `pair'
    local out   : word 2 of `pair'
    gen double `out' = log(revenue / `denom')
    replace    `out' = 0 if revenue == 0 | `denom' == 0
}

gen double allowance_shortage = emissions - allocated_free
gen double shortage_prod = log(revenue / allowance_shortage)
replace    shortage_prod = 0 if revenue == 0 | allowance_shortage == 0

* -----------------------------------------------------------------------------
* STEP 6. Dedup (different firm_id but same (vat, year, bvd_id))
* -----------------------------------------------------------------------------

duplicates drop vat_ano year bvd_id, force

* -----------------------------------------------------------------------------
* STEP 7. Belgian vs foreign emissions split via installation_year_in_belgium
* -----------------------------------------------------------------------------

preserve
    use "$OUT_DATA/installation_year_in_belgium.dta", clear
    drop if missing(vat_ano) | missing(verified)
    collapse (sum) verified, by(vat_ano year)
    rename verified emissions_belgian
    tempfile belg_em
    save "`belg_em'"
restore

merge m:1 vat_ano year using "`belg_em'", keep(master match) nogen
replace emissions_belgian = 0 if missing(emissions_belgian)

gen double emissions_foreign = emissions - emissions_belgian
replace    emissions_foreign = 0 if !missing(emissions_foreign) & emissions_foreign < 0
* (If emissions itself is missing, emissions_foreign is missing — matches
*  R's `pmax(NA - 0, 0) = NA`.)

* -----------------------------------------------------------------------------
* STEP 8. Placeholder for in_sample dummy (annual-accounts sample selection)
* -----------------------------------------------------------------------------

gen byte in_sample = .
label variable in_sample ///
    "Placeholder; port annual_accounts_sample_selection.R to populate."

* -----------------------------------------------------------------------------
* Save
* -----------------------------------------------------------------------------

order vat_ano year bvd_id emissions allocated_free allocated_total ///
      allowance_shortage revenue value_added wage_bill capital fte ///
      nace5d nace_id_from_eutl activity_id country_id ///
      emissions_belgian emissions_foreign ///
      emissions_prod fte_prod labor_prod capital_prod shortage_prod ///
      in_sample

compress
save "$OUT_DATA/firm_year_belgian_euets.dta", replace
display as result "Saved: $OUT_DATA/firm_year_belgian_euets.dta  (N = " _N ")"

* Quick sanity print
summarize year emissions allocated_free allowance_shortage revenue ///
          value_added wage_bill, separator(0)

count if !missing(emissions) & emissions > 0
display as text "  firm-years with positive emissions: " r(N)

count if !missing(allowance_shortage) & allowance_shortage > 0
display as text "  firm-years with positive shortage:  " r(N)
