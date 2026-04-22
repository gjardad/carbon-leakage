*! 02a_build_annual_accounts_selected_sample.do
*! Build the annual-accounts "selected sample" of domestic Belgian firms:
*! firm-years with positive labor costs AND positive turnover (VAT-declared).
*! Output is a (vat_ano, year) key used downstream to flag `in_sample` in
*! 02_build_firm_year_euets.do and (optionally) to restrict the PRODCOM
*! analysis panel in 05_build_prodcom_panel.do.
*!
*! Port of:
*!   inferring_emissions/preprocess/annual_accounts_sample_selection.R
*!   (only the basic `selected_sample`; `more_selected_sample` is not used
*!    by the PRODCOM pipeline and is not ported here).
*!
*! Filters (match the R source line-for-line):
*!   v_0001023    (wage_bill)  non-missing AND > 0
*!   turnover_VAT (revenue)    non-missing AND > 0
*!
*! Input
*!   $RAW_DATA/NBB/Annual_Accounts_MASTER_ANO.dta
*!
*! Output
*!   $OUT_DATA/annual_accounts_selected_sample.dta   (keys: vat_ano, year)

do "`c(pwd)'/00_paths.do"

use "$RAW_DATA/NBB/Annual_Accounts_MASTER_ANO.dta", clear
keep vat_ano year v_0001023 turnover_VAT

* Positive labor costs.
keep if !missing(v_0001023) & v_0001023 > 0

* Positive output (VAT turnover).
keep if !missing(turnover_VAT) & turnover_VAT > 0

keep vat_ano year
duplicates drop

compress
save "$OUT_DATA/annual_accounts_selected_sample.dta", replace
display as result "Saved: $OUT_DATA/annual_accounts_selected_sample.dta  (N = " _N ")"

* -----------------------------------------------------------------------------
* Diagnostics
* -----------------------------------------------------------------------------

quietly levelsof vat_ano
display as text "  distinct firms : " r(r)
summarize year, meanonly
display as text "  year range     : " r(min) " - " r(max)
