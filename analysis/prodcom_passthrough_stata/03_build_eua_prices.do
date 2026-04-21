*! 03_build_eua_prices.do
*! Annual EUA spot-price series 2005–2023, from ICAP daily data (2010+)
*! and curated Phase I/II values (2005–2009).
*!
*! Port of: carbon-leakage/analysis/phase3_eua_prices.R
*!
*! Input
*!   $RAW_DATA/icap_euets_price_2005_26.csv
*!
*! Output
*!   $OUT_DATA/eua_prices_annual.dta
*!
*! ICAP CSV layout (after the 2-row banner header):
*!   col 1: Date (YYYY-MM-DD)
*!   cols 2–5:  fx EUR/EUR, fx EUR/USD, currency, primary-market price (2005–2018)
*!   col 6:  spacer
*!   cols 7–11: fx EUR/EUR, fx EUR/USD, currency, primary-market price (2019+),
*!             secondary-market price (2019+)
*!   col 12: spacer

do "`c(pwd)'/00_paths.do"

* -----------------------------------------------------------------------------
* STEP 1. Read ICAP CSV (skip 2-row banner, 12 cols, everything as string)
* -----------------------------------------------------------------------------

import delimited using "$RAW_DATA/icap_euets_price_2005_26.csv", ///
    varnames(nonames) stringcols(_all) encoding("utf-8") clear

* Drop the two banner rows.
drop in 1/2

* Rename to R's naming convention.
rename v1  date_str
rename v2  fx1_eur
rename v3  fx1_usd
rename v4  ccy1
rename v5  price_pre2019_str
rename v6  sp1
rename v7  fx2_eur
rename v8  fx2_usd
rename v9  ccy2
rename v10 price_from2019_str
rename v11 price_secondary_str
rename v12 sp2

gen date = date(date_str, "YMD")
format date %td
gen year = year(date)

destring price_pre2019_str   , gen(price_pre2019)   force
destring price_from2019_str  , gen(price_from2019)  force
destring price_secondary_str , gen(price_secondary) force

* coalesce(price_pre2019, price_from2019, price_secondary)
gen double price = price_pre2019
replace    price = price_from2019  if missing(price)
replace    price = price_secondary if missing(price)

drop if missing(price) | missing(year)

display "ICAP daily/weekly obs kept: " _N
summarize year, meanonly
display "Years covered: " r(min) " - " r(max)

* -----------------------------------------------------------------------------
* STEP 2. Annual mean
* -----------------------------------------------------------------------------

preserve
    collapse (mean) eua_price_icap = price (count) n_obs = price, by(year)
    tempfile icap_annual
    save "`icap_annual'"
restore

* -----------------------------------------------------------------------------
* STEP 3. Assemble 2005–2023 panel with curated Phase I/II values
* -----------------------------------------------------------------------------

clear
set obs 19
gen year = 2004 + _n   // 2005..2023

merge 1:1 year using "`icap_annual'", keep(master match) nogen

* Curated Phase I/II prices from Ellerman et al. 2010 / Martin-Muûls-Wagner 2016.
gen double eua_price_curated = .
replace    eua_price_curated = 22    if year == 2005
replace    eua_price_curated = 18    if year == 2006
replace    eua_price_curated = 0.7   if year == 2007
replace    eua_price_curated = 22    if year == 2008
replace    eua_price_curated = 13    if year == 2009

* Unified series: curated for 2005–2009, ICAP mean otherwise (curated also
* used as fallback if ICAP is missing for a given year).
gen double eua_price = eua_price_icap
replace    eua_price = eua_price_curated if year <= 2009 | missing(eua_price_icap)

gen str40 source = ""
replace source = "curated (ECX/Bluenext, Phase I/II)" if year <= 2009
replace source = "ICAP annual mean" if year > 2009 & !missing(eua_price_icap)

* Phase labels.
gen str10 phase = ""
replace phase = "Phase I"   if inrange(year, 2005, 2007)
replace phase = "Phase II"  if inrange(year, 2008, 2012)
replace phase = "Phase III" if inrange(year, 2013, 2020)
replace phase = "Phase IV"  if year >= 2021

order year eua_price source eua_price_icap eua_price_curated n_obs phase
list, noobs sep(0)

compress
save "$OUT_DATA/eua_prices_annual.dta", replace
display as result "Saved: $OUT_DATA/eua_prices_annual.dta  (N = " _N ")"
