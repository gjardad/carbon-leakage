*===============================================================================
* phase2_build_customs_panel.do
*
* PURPOSE:
*   Build the regulated-intensive customs import panel for the Phase 2 CMdG
*   replication. Produces customs_import_panel_regulated.dta on RMD.
*
* DESIGN:
*   Per CMdG Section 3 + Supplemental Appendix p. 44:
*     1. Restrict to imports.
*     2. Drop non-manufacturing buyer firms (NACE 2d not in 10-33).
*     3. Filter buyers by NACE 4d in regulated_intensive_nace.
*     4. Apply core-input filter: keep CN8 codes whose upstream NACE is in
*        the buyer's core-inputs set (>=10% IO share).
*     5. Drop capital goods (BEC 41, 521).
*     6. Balance the panel in (firm, CN8, partner_country) triplets ever
*        observed; zero-fill missing (firm, CN8, partner, year) cells.
*     7. Attach flags: is_regulated_product, is_non_ets_country, is_ets_firm,
*        is_capital, contaminated_vat.
*
* INPUTS (RMD paths via globals):
*   ${RAW_NBB}/customs/customs_import_<year>.dta  -- one .dta per year, OR
*   ${RAW_NBB}/customs/customs_import_all.dta     -- single panel
*     Schema (CONFIRM ON FIRST RUN):
*       vat (string or numeric, firm ID)
*       cn8 (string, 8-digit CN code)
*       partner_iso2 (string, source country ISO2)
*       year (int)
*       value (double, EUR)
*       quantity (double, kg) [optional]
*       flow_type (1 = import / 2 = export) -- filter to imports only
*   ${PROC_NBB}/firm_year_belgian_euets.dta -- 281 ETS firms x 2005-2023.
*     Schema: vat, year, ets_id, emissions, allocated, shortage, ...
*   ${PROC_NBB}/annual_accounts_selected_sample_key_variables.dta
*     Schema: vat, year, nace5d, revenue, value_added, ...
*
*   Concordances pulled from REPO (rsync to RMD before run):
*     ${REPO}/data/concordances/regulated_products_cn8.csv
*     ${REPO}/data/concordances/cn8_to_nace4d.csv
*     ${REPO}/data/concordances/cn_family_long.csv
*     ${REPO}/data/concordances/hs_to_bec.csv
*     ${REPO}/data/concordances/country_ets_status.csv
*     ${REPO}/data/io/regulated_intensive_nace.csv
*     ${REPO}/data/io/core_inputs_by_downstream.csv
*
* OUTPUT:
*   ${PROC_NBB}/customs_import_panel_regulated.dta
*
* NOTES:
*   * The 3 contaminated VAT hashes (NACE 20/24, post-2020 EUTL break) are
*     hard-coded below and dropped post-2020. See memory:
*     project_nace24_eutl_break_post2020.md.
*   * This script can NOT be tested on local 1 (no customs data). Pre-RMD
*     review of the do-file logic is the validation step.
*===============================================================================

clear all
set more off
capture log close

*------------------------------ Paths -----------------------------------------
* Adjust these globals based on RMD environment.
global REPO     "C:/Users/jardang/Documents/carbon-leakage"
global RAW_NBB  "X:/Documents/JARDANG/data/raw"
global PROC_NBB "X:/Documents/JARDANG/data/processed"

* Sample window matches CMdG.
local FIRSTYEAR 2000
local LASTYEAR  2019

local LOG_DIR "${REPO}/output/logs"
capture mkdir "`LOG_DIR'"
log using "`LOG_DIR'/phase2_build_customs_panel_$(date('%tdN_y_m_d')).log", replace

*------------------------------ 1. Load raw imports ---------------------------
* Prefer single-file panel if available; otherwise loop and append yearly files.
local SINGLE "${RAW_NBB}/customs/customs_import_all.dta"
capture confirm file "`SINGLE'"
if _rc == 0 {
    use "`SINGLE'", clear
}
else {
    tempfile cust_pool
    local first 1
    forvalues y = `FIRSTYEAR'/`LASTYEAR' {
        local f "${RAW_NBB}/customs/customs_import_`y'.dta"
        capture confirm file "`f'"
        if _rc == 0 {
            use "`f'", clear
            if `first' {
                save "`cust_pool'", replace
                local first 0
            }
            else {
                append using "`cust_pool'"
                save "`cust_pool'", replace
            }
        }
    }
    use "`cust_pool'", clear
}

di as txt "Raw imports loaded: " _N " rows."

* Filter to imports if flow column exists.
capture confirm variable flow_type
if _rc == 0 {
    keep if flow_type == 1
    drop flow_type
}

* Filter to analytical years.
keep if inrange(year, `FIRSTYEAR', `LASTYEAR')

* Standardize CN8 to 8-character padded string.
capture confirm string variable cn8
if _rc {
    gen cn8_str = string(cn8, "%08.0f")
    drop cn8
    rename cn8_str cn8
}
replace cn8 = string(real(cn8), "%08.0f") if length(cn8) < 8

di as txt "After flow + year filters: " _N " rows."

*------------------------------ 2. Buyer NACE join ----------------------------
* Get buyer's NACE 4d via annual accounts. Annual accounts gives nace5d per
* (vat, year); take first 4 chars as nace4d.
preserve
use "${PROC_NBB}/annual_accounts_selected_sample_key_variables.dta", clear
gen nace4d = substr(string(nace5d, "%05.0f"), 1, 4)
keep vat year nace4d
duplicates drop vat year, force
tempfile aa_buyer
save "`aa_buyer'"
restore

merge m:1 vat year using "`aa_buyer'", keep(master match) nogenerate

* Buyer NACE 2d for manufacturing filter.
gen buyer_nace2d = substr(nace4d, 1, 2)

*------------------------------ 3. Manufacturing filter -----------------------
* Drop firms not in NACE C 10-33 (manufacturing).
keep if inlist(buyer_nace2d, "10","11","12","13","14","15","16","17") ///
      | inlist(buyer_nace2d, "18","19","20","21","22","23","24","25") ///
      | inlist(buyer_nace2d, "26","27","28","29","30","31","32","33")
di as txt "After manufacturing filter: " _N " rows."

*------------------------------ 4. Regulated-intensive buyer NACE filter ------
preserve
import delimited "${REPO}/data/io/regulated_intensive_nace.csv", clear
keep nace2d
rename nace2d ri_nace2d
* Pad to 2-character string.
tostring ri_nace2d, replace force
replace ri_nace2d = "0" + ri_nace2d if length(ri_nace2d) == 1
duplicates drop
tempfile ri
save "`ri'"
restore

* Tag and keep RI buyers.
merge m:1 buyer_nace2d using "`ri'", keep(match) nogenerate ///
    keepusing(ri_nace2d)
drop ri_nace2d
di as txt "After regulated-intensive buyer NACE filter: " _N " rows."

*------------------------------ 5. CN8 -> upstream NACE 2d --------------------
* Use the CN8 -> NACE 4d bridge to get the IMPORTED product's upstream NACE.
preserve
import delimited "${REPO}/data/concordances/cn8_to_nace4d.csv", ///
    stringcols(_all) clear
keep year cn8 nace4d
rename nace4d upstream_nace4d
gen upstream_nace2d = substr(upstream_nace4d, 1, 2)
* Reduce to (year, cn8) -> upstream_nace2d (modal already taken in Step 2b).
duplicates drop year cn8, force
tempfile bridge
save "`bridge'"
restore

destring year, replace
merge m:1 year cn8 using "`bridge'", keep(master match) nogenerate ///
    keepusing(upstream_nace2d)

*------------------------------ 6. Core-input filter --------------------------
* For each buyer NACE, keep only CN8s whose upstream NACE 2d is in the
* core-input set at the 10% threshold.
preserve
import delimited "${REPO}/data/io/core_inputs_by_downstream.csv", ///
    stringcols(_all) clear
keep if real(threshold) == 0.10
keep downstream_nace2d upstream_cpa_nace2d
rename downstream_nace2d buyer_nace2d
rename upstream_cpa_nace2d upstream_nace2d
gen is_core = 1
duplicates drop buyer_nace2d upstream_nace2d, force
tempfile core
save "`core'"
restore

merge m:1 buyer_nace2d upstream_nace2d using "`core'", ///
    keep(master match) nogenerate keepusing(is_core)
keep if is_core == 1
drop is_core
di as txt "After core-input filter: " _N " rows."

*------------------------------ 7. Capital-goods filter -----------------------
preserve
import delimited "${REPO}/data/concordances/hs_to_bec.csv", ///
    stringcols(_all) clear
keep hs6 is_capital
duplicates drop hs6, force
tempfile bec
save "`bec'"
restore

gen hs6 = substr(cn8, 1, 6)
merge m:1 hs6 using "`bec'", keep(master match) nogenerate ///
    keepusing(is_capital)
drop if is_capital == "TRUE"
drop is_capital hs6
di as txt "After BEC capital-goods filter: " _N " rows."

*------------------------------ 8. Regulated CN8 flag -------------------------
preserve
import delimited "${REPO}/data/concordances/regulated_products_cn8.csv", ///
    stringcols(_all) clear
keep cn8 is_regulated
duplicates drop cn8, force
tempfile reg
save "`reg'"
restore

merge m:1 cn8 using "`reg'", keep(master match) nogenerate
gen is_regulated_product = (is_regulated == "TRUE")
drop is_regulated

*------------------------------ 9. ETS country flag ---------------------------
preserve
import delimited "${REPO}/data/concordances/country_ets_status.csv", ///
    stringcols(_all) clear
destring year, replace
keep iso2 year is_ets
duplicates drop iso2 year, force
rename iso2 partner_iso2
tempfile etsc
save "`etsc'"
restore

merge m:1 partner_iso2 year using "`etsc'", keep(master match) nogenerate
* If absent from table, country is non-ETS.
gen is_non_ets_country = !(is_ets == "TRUE")
drop is_ets

*------------------------------ 10. ETS firm flag -----------------------------
preserve
use "${PROC_NBB}/firm_year_belgian_euets.dta", clear
keep vat year
duplicates drop vat year, force
gen is_ets_firm = 1
tempfile etsf
save "`etsf'"
restore

merge m:1 vat year using "`etsf'", keep(master match) nogenerate
replace is_ets_firm = 0 if missing(is_ets_firm)

*------------------------------ 11. Contaminated VAT filter -------------------
* Three VAT hashes in NACE 20 and 24 produce post-2020 EUTL allocation breaks
* that are not real economic events. See memory:
* project_nace24_eutl_break_post2020.md. Hard-coded from
* phase4_b2b_supplier_switching.R:89-93. UPDATE these hashes after RMD review.
local CONTAM_VAT1 ""  // TODO: copy hash from phase4_b2b_supplier_switching.R
local CONTAM_VAT2 ""
local CONTAM_VAT3 ""
gen contaminated_vat = ///
    (vat == "`CONTAM_VAT1'") | (vat == "`CONTAM_VAT2'") | (vat == "`CONTAM_VAT3'")
drop if contaminated_vat == 1 & year >= 2020
drop contaminated_vat

*------------------------------ 12. Balance the panel -------------------------
* Following CMdG: every (firm, CN8, partner) triplet ever observed in the
* sample becomes a candidate sourcing option in every year. Zero-fill missing.
egen triplet = group(vat cn8 partner_iso2)
preserve
keep triplet
duplicates drop
tempfile triplets
save "`triplets'"
restore

* Cross-join triplets x years.
preserve
use "`triplets'", clear
expand `=`LASTYEAR' - `FIRSTYEAR' + 1'
bys triplet: gen year = `FIRSTYEAR' - 1 + _n
tempfile bal_skel
save "`bal_skel'"
restore

merge 1:1 triplet year using "`bal_skel'"
* Master-only rows: original observed cells. Using-only rows: zero-fill.
replace value = 0 if _merge == 2
* For zero-filled rows, propagate triplet attributes (vat, cn8, partner_iso2)
* from any observed row of the same triplet.
foreach v of varlist vat cn8 partner_iso2 {
    bys triplet (year): replace `v' = `v'[1] if missing(`v')
}
drop _merge

* Re-attach time-varying flags for zero-filled cells.
* For consistency, re-merge ETS firm and ETS country flags.
* (Buyer NACE, regulated_product flag etc. are time-invariant per cn8/vat,
* already propagated.)
* Re-merge ETS firm:
merge m:1 vat year using "`etsf'", keep(master match) nogenerate update
replace is_ets_firm = 0 if missing(is_ets_firm)

* Re-merge ETS country:
merge m:1 partner_iso2 year using "`etsc'", keep(master match) nogenerate update
replace is_non_ets_country = !(is_ets == "TRUE") if missing(is_non_ets_country)
drop is_ets

* Time-varying buyer NACE: re-merge.
merge m:1 vat year using "`aa_buyer'", keep(master match) nogenerate update

di as txt "After balancing + zero-fill: " _N " rows."

*------------------------------ 13. Save --------------------------------------
* Final tidy.
order vat cn8 partner_iso2 year value nace4d buyer_nace2d ///
      is_regulated_product is_non_ets_country is_ets_firm
sort vat cn8 partner_iso2 year

compress
save "${PROC_NBB}/customs_import_panel_regulated.dta", replace

di as txt _newline ///
    "================ Build complete ================" _newline ///
    "Rows: " _N _newline ///
    "Output: ${PROC_NBB}/customs_import_panel_regulated.dta"

* Quick sanity stats.
tab year is_regulated_product, missing
tab year is_non_ets_country, missing
tab buyer_nace2d, missing

log close
