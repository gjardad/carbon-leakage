## PRODCOM pass-through — Stata workstream

This folder contains a self-contained Stata pipeline that builds the firm-year ETS exposure panel, EUA price series, NACE4d PPI deflator, and firm × PC8 × year PRODCOM panel, then runs the pass-through regressions.

The pipeline is a line-by-line port of the R scripts in the main `carbon-leakage` repo — it exists so the coauthor (who has Stata but not R on the NBB remote desktop) can reproduce the analysis from the raw `.dta` and `.csv` inputs.

### Inputs (on the NBB RMD)

| File | Source | Role |
|---|---|---|
| `raw/NBB/EUTL_Belgium.dta` | NBB | Account registry (bvd_id ↔ vat_ano mapping) |
| `raw/NBB/Annual_Accounts_MASTER_ANO.dta` | NBB | Revenue, VA, wage bill, NACE5d |
| `raw/NBB/prod.dta` | NBB | PRODCOM firm × PC8 × year × month value/quantity |
| `raw/EUTL/Oct_2024_version/*.csv` | Public (EU Transaction Log) | Installation-level verified emissions + free allocation |
| `raw/icap_euets_price_2005_26.csv` | Public (ICAP) | Daily EUA settlement prices |
| `raw/Statbel/TABEL_WEBSITE_AANGEVERS_EN.xlsx` | Public (Statbel) | NACE4d domestic PPI 2010+ |
| `raw/Eurostat/sts_inppd_a__custom_21089145_linear.csv` | Public (Eurostat) | NACE2d PPI (for 2005–2009 backfill) |

The four "public" inputs are small enough to ship with the repo if they aren't already on the RMD.

### Running the pipeline

**Step 1 — set paths.** Open `00_paths.do` and edit the RMD branch (`jardang`) so `$DATA_DIR` points to your data root and `$REPO_DIR` points to your clone of `carbon-leakage`. The existing `jota_` branch is for Gabriel's local machine (used for testing with the mock `prod.dta`); do not edit it.

**Step 2 — run in order.** From Stata:

```stata
do 00_paths.do        // sets globals; no output file
do 01_build_installation_year_emissions.do
do 02a_build_annual_accounts_selected_sample.do
do 02_build_firm_year_euets.do
do 03_build_eua_prices.do
do 04_build_deflator.do
do 05_build_prodcom_panel.do
```

Each script `do 00_paths.do`s at the top, so they can be run individually once the paths are set.

Outputs land in `$OUT_DATA` (= `$REPO_DIR/data/processed/`):

- `installation_year_emissions.dta`
- `annual_accounts_selected_sample.dta`
- `firm_year_belgian_euets.dta`
- `eua_prices_annual.dta`
- `deflator_nace4d_2005base.dta`
- `prodcom_analysis_panel.dta`

### Verification against the R pipeline

The Gabriel-local `jota_` branch of `00_paths.do` points at a directory tree where the same inputs are already processed in R. The helper `../prodcom_passthrough_stata_check.R` (run locally) loads both the `.RData` and the `.dta` for each step and compares row counts, column sums, and key quantiles. Any mismatch is a signal that the port has diverged from the R reference.

### Mapping to R source files

| Stata | R source |
|---|---|
| `01_build_installation_year_emissions.do` | `inferring_emissions/preprocess/build_firm_year_emissions.R` (the part that builds `installation_year_emissions.RData`) |
| `02a_build_annual_accounts_selected_sample.do` | `inferring_emissions/preprocess/annual_accounts_sample_selection.R` (basic `selected_sample` only) |
| `02_build_firm_year_euets.do` | `inferring_emissions/preprocess/build_firm_year_euets.R` |
| `03_build_eua_prices.do` | `carbon-leakage/analysis/phase3_eua_prices.R` |
| `04_build_deflator.do` | `carbon-leakage/analysis/phase0_build_deflator.R` |
| `05_build_prodcom_panel.do` | new (PRODCOM is specific to this workstream) |

### Deferred (not in this first pass)

- Regression scripts (06–09) for the four pass-through specs.
- Network-adjusted (Leontief) upstream exposure — requires the full B2B network and is a separate porting job.
- The Melitz-Polanec / decomposition branch — not used for pass-through.
