*! 01_build_installation_year_emissions.do
*! Builds installation-year EUTL emissions panel (EU-wide) and a Belgian
*! subset with bvd_id / vat_ano attached.
*!
*! Port of: inferring_emissions/preprocess/build_installation_year.R
*!
*! Inputs
*!   $RAW_DATA/EUTL/Oct_2024_version/installation.csv
*!   $RAW_DATA/EUTL/Oct_2024_version/compliance.csv
*!   $RAW_DATA/EUTL/Oct_2024_version/account.csv
*!   $RAW_DATA/NBB/EUTL_Belgium.dta
*!
*! Outputs
*!   $OUT_DATA/installation_year_emissions.dta   (EU-wide installation × year)
*!   $OUT_DATA/installation_year_in_belgium.dta  (Belgian subset with vat_ano)

do "`c(pwd)'/00_paths.do"

* -----------------------------------------------------------------------------
* STEP 1. Installation registry (activity / NACE / country)
* -----------------------------------------------------------------------------

import delimited using "$RAW_DATA/EUTL/Oct_2024_version/installation.csv", ///
    varnames(1) stringcols(_all) encoding("utf-8") clear

rename id installation_id
keep installation_id country_id activity_id nace_id

* Drop aviation (NACE 51.00). nace_id arrives as string; match on string.
drop if nace_id == "51.00"

tempfile installation
save "`installation'"

* -----------------------------------------------------------------------------
* STEP 2. Compliance table → merge onto installations
* -----------------------------------------------------------------------------

import delimited using "$RAW_DATA/EUTL/Oct_2024_version/compliance.csv", ///
    varnames(1) encoding("utf-8") clear

keep installation_id year allocatedfree allocatedtotal verified

* Make sure the types match for the merge
tostring installation_id, replace force
destring year allocatedfree allocatedtotal verified, replace force

tempfile compliance
save "`compliance'"

* -----------------------------------------------------------------------------
* STEP 3. Join + clean → installation_year_emissions
* -----------------------------------------------------------------------------

use "`installation'", clear
joinby installation_id using "`compliance'", unmatched(master)
* unmatched master = keep installations even if no compliance record (→ NA year)

drop _merge
keep installation_id year country_id activity_id nace_id ///
     allocatedfree allocatedtotal verified

drop if missing(year) | year > 2023

* In R, allocatedFree / allocatedTotal NA → 0.
* `verified` NA is intentionally preserved (distinguishes "not regulated"
* from "regulated with zero emissions").
replace allocatedfree  = 0 if missing(allocatedfree)
replace allocatedtotal = 0 if missing(allocatedtotal)

* Activity id crosswalk: Phase I/II used codes 1-10; from Phase III the
* EUETS info version uses 20-99. See Abrell (EUETS.INFO), Table C1.
*   1-5 -> +19;  6 -> 29;  7 -> 31;  8 -> 32;  9 -> 35
destring activity_id, replace force
replace activity_id = activity_id + 19 if inrange(activity_id, 1, 5)
replace activity_id = 29 if activity_id == 6
replace activity_id = 31 if activity_id == 7
replace activity_id = 32 if activity_id == 8
replace activity_id = 35 if activity_id == 9

* Pad single-digit-prefix NACE with leading zero (e.g. "1.25" -> "01.25").
replace nace_id = "0" + nace_id if regexm(nace_id, "^[0-9]\.")

rename (allocatedfree allocatedtotal) (allocated_free allocated_total)
order installation_id year country_id activity_id nace_id ///
      allocated_free allocated_total verified

compress
save "$OUT_DATA/installation_year_emissions.dta", replace
display as result "Saved: $OUT_DATA/installation_year_emissions.dta  (N = " _N ")"

tempfile iye
save "`iye'"

* -----------------------------------------------------------------------------
* STEP 4. Belgian subset with bvd_id / vat_ano
* -----------------------------------------------------------------------------

* Account registry → {bvd_id, installation_id} for Belgian ETS accounts.
import delimited using "$RAW_DATA/EUTL/Oct_2024_version/account.csv", ///
    varnames(1) stringcols(_all) encoding("utf-8") clear

rename accounttype_id  account_type
rename bvdid           bvd_id
rename id              account_id
rename companyregistrationnumber firm_id

keep account_id account_type bvd_id installation_id firm_id
keep if inlist(account_type, "100-7", "120-0")

* One installation can appear in multiple account rows; collapse to
* {bvd_id, installation_id} distinct.
keep bvd_id installation_id
* Stata's joinby matches "" to "" (unlike R's NA-to-NA non-match); drop
* empty-bvd rows so they don't create spurious matches downstream.
drop if bvd_id == "" | missing(bvd_id)
duplicates drop

tempfile account_bvd
save "`account_bvd'"

* {bvd_id, vat_ano} from NBB EUTL registry.
use "$RAW_DATA/NBB/EUTL_Belgium.dta", clear
rename bvdid bvd_id
keep bvd_id vat_ano
drop if bvd_id == "" | missing(bvd_id) | vat_ano == "" | missing(vat_ano)
duplicates drop

tempfile bvd_vat
save "`bvd_vat'"

* Join: installation-year  ⟶  bvd_id  ⟶  vat_ano, Belgian only.
use "`iye'", clear
joinby installation_id using "`account_bvd'"   // inner join
duplicates drop

* bvd_vat can have multiple vat_ano per bvd_id (historical VAT changes).
* Use joinby so all vat_ano are kept; the gsort-dedup below picks one per
* (installation_id, year).
joinby bvd_id using "`bvd_vat'", unmatched(master)

keep if substr(installation_id, 1, 2) == "BE"

* Normalise and dedup: prefer rows with both bvd_id and vat_ano.
replace bvd_id  = strtrim(bvd_id)
replace vat_ano = strtrim(vat_ano)
replace bvd_id  = "" if inlist(bvd_id,  "NA")
replace vat_ano = "" if inlist(vat_ano, "NA")

gen byte has_bvd = bvd_id  != ""
gen byte has_vat = vat_ano != ""

gsort installation_id year -has_bvd -has_vat
by installation_id year: keep if _n == 1
drop has_bvd has_vat

compress
save "$OUT_DATA/installation_year_in_belgium.dta", replace
display as result "Saved: $OUT_DATA/installation_year_in_belgium.dta  (N = " _N ")"
