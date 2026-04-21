# TODO

Open analyses that are deferred until headline results land. Add dated entries when new follow-ups appear; strike through and date items when they're closed out.

---

## Phase 3 (shock size and pass-through) — deferred sub-tasks

Context: the main Phase 3 pipeline (`phase3_*`) addresses

1. Histograms of carbon cost share by ETS phase (Task 1)
2. Sector-level PPI pass-through using direct and network-adjusted exposure (Task 2)
3. Diagnostics of shock size and timing (Task 3)

Items 5 and 6 below were originally scoped into Task 3 but postponed until the main diagnostics and pass-through regressions have been inspected. They should be revisited once we know whether the basic answer ("the ETS shock was small relative to other cost shocks") already falls out of the first-pass plots.

### Task 3.5 — Benchmark EUA-driven cost variation against other shocks (added 2026-04-21)

Compare the within-firm standard deviation of (shortage × EUA price) / total_cost against the within-firm standard deviation of input cost driven by other shocks over 2005-2023. The natural benchmarks are:

- Natural gas wholesale price (TTF front-month, annual mean)
- Electricity wholesale price (Belgian day-ahead or equivalent)
- Nominal wage growth (annual % change, from `wage_bill` at the firm level)

If EUA-driven variation is an order of magnitude smaller than gas or electricity variation, that is itself the headline answer to "was the shock big?". One figure, one table: within-firm s.d. of each shock component, by phase.

### Task 3.6 — Abatement speed after the Phase IV price jump (added 2026-04-21)

Direct test of the hypothesis that pollutant firms "protect" customers by abating quickly. For high-shortage firms (top tercile of 2013-2016 shortage intensity, following Phase 1a), plot

- within-firm emissions growth 2020 → 2021 → 2022 → 2023
- within-firm shortage growth (net of the free-allowance reduction)
- within-firm emissions intensity (emissions / real revenue)

Compare to a matched control group of low-shortage ETS firms. If abatement is fast (say, >5% YoY within two years of the price jump), that shortens the window in which reallocation could have operated and supports the "shock was small in effective terms" story.

---

## Triggers for revisiting

- When the Task 1 histograms show the shock is genuinely small through Phase III → both 3.5 and 3.6 become essential to quantify "how small".
- When Task 2 pass-through is not statistically significant → 3.5 becomes the explanation of last resort.
- When Task 2 pass-through IS significant → 3.6 becomes a follow-up on timing/lag structure.

---

## PRODCOM pass-through Stata workstream — next steps (added 2026-04-21)

Context: `analysis/prodcom_passthrough_stata/` is a Stata port of the data-cleaning pipeline so the coauthor (Stata-only, on RMD) can reproduce the analysis end-to-end. First pass landed the data-build scripts `00_` through `05_` + `verify_against_R.R`. Regression scripts, sample-selection logic, and local testing are still open.

### Step 1 — Port annual-accounts sample selection
Write `02a_build_annual_accounts_selected_sample.do` mirroring `inferring_emissions/preprocess/annual_accounts_sample_selection.R`. Two filters: `wage_bill > 0` (v_0001023) and `turnover_VAT > 0`. Save `annual_accounts_selected_sample.dta` with (vat_ano, year). Then wire into `02_build_firm_year_euets.do` to populate the `in_sample` dummy (currently `.`), and into `05_build_prodcom_panel.do` as an optional filter.

**Decision still open:** apply `keep if in_sample == 1` in `05_` by default (matches the "255 in-sample" convention from the sector-level Phase 3 work) vs. keep all rows (matches MMS 2024). Default proposal: in-sample, switchable via a global flag at the top of `05_`.

### Step 2 — Find Stata locally and run the pipeline on the mock `prod.dta`
Stata is not on `C:/`. Either install it on local-1, borrow local-2, or wait for coauthor. Once available: `cd` into `analysis/prodcom_passthrough_stata/` and run `00_` → `05_` in order. Expected: steps 01–04 match the R reference closely (verify via `verify_against_R.R`); step 05 produces a structurally-correct panel with zero merge matches on exposure (mock `prod.dta` uses numeric IDs that don't match real `vat_ano` hashes).

### Step 3 — Port the four regression specs (06–09)
Once the data pipeline is validated, port:

- `06_passthrough_continuous.do` — Δ log(price)_{i,p,t} ~ exposure_{i,t} + firm FE + pc8×year FE (requires `reghdfe`)
- `07_passthrough_bartik.do` — base_shortage_i × EUA_t (same FE structure)
- `08_passthrough_event_study.do` — monthly panel, event-time dummies around ETS regulatory news
- `09_passthrough_heterogeneity.do` — split by homogeneous vs differentiated PC8 codes

For step 08 we need a separate monthly-panel build (the current `05_` annualises); either add a flag to `05_` or write `05_monthly.do`.

### Step 4 — Port B2B selected-sample construction (deferred until network exposure needed)
Write `build_b2b_selected_sample.do` mirroring `build_b2b_selected_sample.R`: load `B2B_ANO.dta`, restrict both endpoints to firms in `annual_accounts_selected_sample.dta` per year, save. Needed only when we extend the PRODCOM analysis with Leontief-upstream exposure (the S3 spec from the sector-level work).

### Step 5 — ID convention on real PRODCOM
Confirm with coauthor that on RMD `prod.dta`'s `ID` column matches `vat_ano` in `Annual_Accounts_MASTER_ANO.dta` (string 64-char hash). If instead it's a separate numeric identifier, add a crosswalk merge in `05_build_prodcom_panel.do`.
