*! 04_build_deflator.do
*! Unified NACE 4-digit producer-price index, chained to 2005 = 100.
*!
*! Strategy:
*!   - 2005–2009: Eurostat NACE 2-digit PPI, chain-linked across base years
*!                (2010, 2015, 2021), re-indexed to 2005=100.
*!   - 2010–2024: Statbel NACE 4-digit domestic PPI (base 2010=100),
*!                chain-linked to Eurostat 2-digit at 2010.
*!   - Fallback: NACE 4-digit codes absent from Statbel use the Eurostat
*!               2-digit series (incl. aggregates C16-C18 for NACE 18,
*!               C29_C30 for NACE 30).
*!
*! Port of: carbon-leakage/analysis/phase0_build_deflator.R
*!
*! Inputs
*!   $RAW_DATA/Statbel/TABEL_WEBSITE_AANGEVERS_EN.xlsx
*!   $RAW_DATA/Eurostat/sts_inppd_a__custom_21089145_linear.csv
*!
*! Outputs
*!   $OUT_DATA/deflator_nace4d_2005base.dta       (main: nace4d × year)
*!   $OUT_DATA/deflator_nace2d_2005base.dta       (fallback: nace2d × year)

do "`c(pwd)'/00_paths.do"

local base_year 2005
local link_year 2010

* =============================================================================
* STEP 1. Statbel xlsx → {nace4d, year, ppi_statbel}  (base 2010 = 100)
* =============================================================================

import excel using "$RAW_DATA/Statbel/TABEL_WEBSITE_AANGEVERS_EN.xlsx", ///
    sheet("Domestic market") cellrange(A1) clear

rename (A B C D E F G H I J K L M N O) ///
       (nace4d_raw label_or_year jan feb mar apr may jun jul aug sep oct nov dec annual)

* nace4d_raw arrives as numeric (pure NACE codes); convert to string so we
* can fill-down into year rows. `tostring, force` turns missing → "".
tostring nace4d_raw, replace force
replace nace4d_raw = "" if nace4d_raw == "."

* Fill-down: each NACE label row is followed by year rows with blank col A.
replace nace4d_raw = nace4d_raw[_n-1] if nace4d_raw == "" & _n > 1

* label_or_year is a year on data rows (numeric) and a sector label on
* label rows (text). Arrives as string; attempt numeric conversion.
capture confirm numeric variable label_or_year
if _rc {
    destring label_or_year, generate(year) force
}
else {
    gen year = label_or_year
}
drop if missing(year)

* Coerce month + annual columns to numeric.
foreach v in jan feb mar apr may jun jul aug sep oct nov dec annual {
    capture confirm numeric variable `v'
    if _rc destring `v', replace force
}

egen double ppi_month_avg = rowmean(jan feb mar apr may jun jul aug sep oct nov dec)
gen  double ppi_statbel    = annual
replace     ppi_statbel    = ppi_month_avg if missing(ppi_statbel)

keep nace4d_raw year ppi_statbel
rename nace4d_raw nace4d
drop if missing(ppi_statbel)

* Pad nace4d to width 4 with leading zeros.
gen len = strlen(nace4d)
replace nace4d = "0" + nace4d   if len == 3
replace nace4d = "00" + nace4d  if len == 2
replace nace4d = "000" + nace4d if len == 1
drop len

gen nace2d = substr(nace4d, 1, 2)

display "Statbel PPI: " _N " obs"
summarize year, meanonly
display "  year range: " r(min) " - " r(max)
quietly levelsof nace4d
display "  NACE 4d sectors: " r(r)

tempfile ppi_statbel
save "`ppi_statbel'"

* =============================================================================
* STEP 2. Eurostat CSV → NACE 2-digit chained to 2005 = 100
* =============================================================================

import delimited using ///
    "$RAW_DATA/Eurostat/sts_inppd_a__custom_21089145_linear.csv", ///
    varnames(1) stringcols(_all) encoding("utf-8") clear

* Keep pure 2-digit rows (e.g. "C10:...") and specific aggregates
* (C16-C18 → used as NACE 18 series; C29_C30 → used as NACE 30 series).
gen byte is_pure2d  = regexm(nace_r2, "^[A-Z][0-9]{2}:")
gen byte is_agg_18  = regexm(nace_r2, "C16-C18")
gen byte is_agg_30  = regexm(nace_r2, "C29_C30")
keep if is_pure2d | is_agg_18 | is_agg_30

gen nace2d = ""
replace nace2d = substr(nace_r2, 2, 2) if is_pure2d
replace nace2d = "18" if is_agg_18
replace nace2d = "30" if is_agg_30

* R replaces the (incomplete) pure-2d series for NACE 18 and 30 with the
* aggregates — equivalent here: drop pure-2d rows for those two.
drop if inlist(nace2d, "18", "30") & is_pure2d

gen year     = real(time_period)
gen double p = real(obs_value)

gen base = ""
replace base = "b2010" if strpos(unit, "2010")
replace base = "b2015" if strpos(unit, "2015")
replace base = "b2021" if strpos(unit, "2021")

drop if missing(p) | missing(base) | missing(year)
keep nace2d year p base

* Pivot wide: one row per (nace2d, year), one column per base.
reshape wide p, i(nace2d year) j(base) string
* → creates variables pb2010, pb2015, pb2021

* ---- Chain-link across base years (per sector) ----
* Anchor on pb2010. Chain pb2015 at the latest (year, sector) with both
* pb2010 and pb2015 non-missing. Then chain pb2021 against the result.

gen double ppi_chain = pb2010

quietly levelsof nace2d, local(sectors)
foreach s of local sectors {

    * Chain b2015
    capture confirm variable pb2015
    if !_rc {
        summarize year if nace2d == "`s'" & !missing(ppi_chain) & !missing(pb2015), meanonly
        if r(N) > 0 {
            local ly = r(max)
            summarize ppi_chain if nace2d == "`s'" & year == `ly', meanonly
            local cv = r(mean)
            summarize pb2015    if nace2d == "`s'" & year == `ly', meanonly
            local bv = r(mean)
            if `bv' != 0 {
                local ratio = `cv' / `bv'
                quietly replace ppi_chain = pb2015 * `ratio' ///
                    if nace2d == "`s'" & missing(ppi_chain) & !missing(pb2015)
            }
        }
    }

    * Chain b2021
    capture confirm variable pb2021
    if !_rc {
        summarize year if nace2d == "`s'" & !missing(ppi_chain) & !missing(pb2021), meanonly
        if r(N) > 0 {
            local ly = r(max)
            summarize ppi_chain if nace2d == "`s'" & year == `ly', meanonly
            local cv = r(mean)
            summarize pb2021    if nace2d == "`s'" & year == `ly', meanonly
            local bv = r(mean)
            if `bv' != 0 {
                local ratio = `cv' / `bv'
                quietly replace ppi_chain = pb2021 * `ratio' ///
                    if nace2d == "`s'" & missing(ppi_chain) & !missing(pb2021)
            }
        }
    }
}

drop if missing(ppi_chain)

* ---- Re-index to 2005 = 100 ----
preserve
    keep if year == `base_year'
    keep nace2d ppi_chain
    rename ppi_chain base_val
    tempfile base_vals
    save "`base_vals'"
restore

merge m:1 nace2d using "`base_vals'", keep(master match) nogen
gen double ppi_2005 = ppi_chain / base_val * 100
keep if !missing(ppi_2005) & year >= `base_year'
keep nace2d year ppi_2005

* ---- Fill gaps by linear interpolation (NACE 18 and 30 have gaps at
*      2018-2020 because the aggregate series drops out).
*      See DATA_CLEANING.md Assumption 4 in the R repo.
summarize year, meanonly
local max_yr = r(max)

* Rectangularise to (nace2d × [2005..max_yr]).
preserve
    contract nace2d
    drop _freq
    tempfile sectors
    save "`sectors'"
restore

preserve
    clear
    set obs `=`max_yr' - `base_year' + 1'
    gen year = `base_year' - 1 + _n
    tempfile years
    save "`years'"
restore

preserve
    use "`sectors'", clear
    cross using "`years'"
    tempfile grid
    save "`grid'"
restore

merge 1:1 nace2d year using "`grid'", keep(master using match) nogen

sort nace2d year
by nace2d: ipolate ppi_2005 year, generate(ppi_2005_ip)
replace ppi_2005 = ppi_2005_ip if missing(ppi_2005)
drop if missing(ppi_2005)
drop ppi_2005_ip

display "Eurostat chained + interpolated: " _N " obs"
quietly levelsof nace2d
display "  NACE 2d sectors: " r(r)

tempfile ppi_eurostat
save "`ppi_eurostat'"

* =============================================================================
* STEP 3. Chain-link Statbel 4-digit to Eurostat 2-digit at 2010
* =============================================================================

* Eurostat value at link year, per 2d.
preserve
    use "`ppi_eurostat'", clear
    keep if year == `link_year'
    keep nace2d ppi_2005
    rename ppi_2005 eurostat_link_val
    tempfile eu_link
    save "`eu_link'"
restore

* Statbel value at link year, per 4d.
preserve
    use "`ppi_statbel'", clear
    keep if year == `link_year'
    keep nace4d statbel_link_val
    rename statbel_link_val statbel_link_val_
    * (rename avoids clash; we'll rename back on merge)
    rename statbel_link_val_ statbel_link_val
    tempfile sb_link
    save "`sb_link'"
restore

use "`ppi_statbel'", clear
keep if year >= `link_year'
merge m:1 nace4d using "`sb_link'", keep(master match) nogen
merge m:1 nace2d using "`eu_link'", keep(master match) nogen

gen double ppi = (ppi_statbel / statbel_link_val) * eurostat_link_val
keep if !missing(ppi)
keep nace4d nace2d year ppi
gen str30 ppi_source = "statbel_4d_chained"

tempfile deflator_post2010
save "`deflator_post2010'"

* =============================================================================
* STEP 4. Unified deflator: pre-2010 uses Eurostat 2d, post-2010 uses
*         Statbel chained (via NACE 4d → 2d crosswalk from Statbel).
* =============================================================================

* NACE 4d ↔ 2d crosswalk from Statbel.
preserve
    use "`ppi_statbel'", clear
    keep nace4d nace2d
    duplicates drop
    tempfile crosswalk
    save "`crosswalk'"
restore

* Pre-link-year deflator: cross (nace4d × [2005..2009]) with Eurostat 2d.
preserve
    clear
    set obs `=`link_year' - `base_year''
    gen year = `base_year' - 1 + _n
    tempfile pre_years
    save "`pre_years'"
restore

use "`crosswalk'", clear
cross using "`pre_years'"

preserve
    use "`ppi_eurostat'", clear
    keep nace2d year ppi_2005
    rename ppi_2005 ppi
    tempfile eu2d
    save "`eu2d'"
restore

merge m:1 nace2d year using "`eu2d'", keep(master match) nogen
drop if missing(ppi)
gen str30 ppi_source = "eurostat_2d"

* Combine pre + post.
append using "`deflator_post2010'"
sort nace4d year

order nace4d nace2d year ppi ppi_source
compress

* Spot checks (match R's prints).
display _n "=== Deflator summary ==="
quietly levelsof nace4d
display "NACE 4-digit sectors: " r(r)
summarize year, meanonly
display "Year range: " r(min) " - " r(max)
display "Total obs: " _N
tabulate ppi_source, missing

display _n "=== Spot check: NACE 2410 (basic iron & steel) ==="
list nace4d year ppi ppi_source if nace4d == "2410", noobs sep(0)

display _n "=== Spot check: NACE 2351 (cement) ==="
list nace4d year ppi ppi_source if nace4d == "2351", noobs sep(0)

save "$OUT_DATA/deflator_nace4d_2005base.dta", replace
display as result "Saved: $OUT_DATA/deflator_nace4d_2005base.dta  (N = " _N ")"

* =============================================================================
* STEP 5. 2-digit fallback deflator (for nace4d not in Statbel)
* =============================================================================

use "`ppi_eurostat'", clear
keep if year >= `base_year'
rename ppi_2005 ppi
gen str30 ppi_source = "eurostat_2d"
order nace2d year ppi ppi_source
compress

display _n "=== 2-digit fallback summary ==="
quietly levelsof nace2d
display "NACE 2-digit sectors: " r(r)

display _n "=== Spot check fallback: NACE 18 ==="
list nace2d year ppi if nace2d == "18", noobs sep(0)

display _n "=== Spot check fallback: NACE 30 ==="
list nace2d year ppi if nace2d == "30", noobs sep(0)

save "$OUT_DATA/deflator_nace2d_2005base.dta", replace
display as result "Saved: $OUT_DATA/deflator_nace2d_2005base.dta  (N = " _N ")"
