# TODO

Open analyses that are deferred until headline results land. Add dated entries when new follow-ups appear; strike through and date items when they're closed out.

Four active workstreams:

1. **Reallocation mechanism** — H1 (within-sector reallocation) vs H2 (inelastic-demand shield). Plan: [REALLOCATION_MECHANISM_PLAN.md](REALLOCATION_MECHANISM_PLAN.md).
2. **PRODCOM pass-through** — Stata port of firm × PC8 × month pipeline for co-author. Plan: [PRODCOM_PLAN.md](PRODCOM_PLAN.md).
3. **Threat hypothesis** — do firms invest in cleaner tech in response to carbon-price news, not only realized prices? Plan: [TREAT_HYPOTHESIS_PLAN.md](TREAT_HYPOTHESIS_PLAN.md).
4. **Greenflation** — firm-level test of CPShock pass-through into realized prices, extending Hensel et al. / Känzig-Konradt. Lit review: [greenflation.md](greenflation.md).

A fifth section at the bottom holds shock-size / abatement-timing diagnostics from the earlier Phase 3 scope that aren't tied to any single workstream.

---

## 1. Reallocation-mechanism workstream (added 2026-04-22)

Source: [REALLOCATION_MECHANISM_PLAN.md](REALLOCATION_MECHANISM_PLAN.md). Goal: discriminate H1 (reallocation within high-pass-through sectors) from H2 (pass-through reflects inelastic demand, no reallocation anywhere).

### Step 1 — Build firm-level treatment variables and time-series signals
Treatment is cost-based, analog of sector-level `intensity_base_s`. Revenue was the wrong denominator because it's endogenous to the ETS shock itself (updated 2026-04-22).

- [ ] Compute `firm_cost_share_i` = mean_{t∈2013..16} [shortage_{i,t} × EUA_t] / mean_{t∈2013..16} [total_cost_{i,t}] per ETS firm. `total_cost = mat_inputs + wage_bill` already built at [phase3_build_exposure_panel.R:65-66](analysis/phase3_build_exposure_panel.R).
- [ ] Compute `firm_emint_physical_i` = mean shortage / mean total_cost (tCO₂ per €) as a no-EUA-price robustness variant.
- [ ] Compute `firm_dev_{i,s}` = `firm_cost_share_i` minus NACE4d sector mean.
- [ ] **Build three time-series signals** (Angle 1 and Angle 4 both use all three):
  - ID-A: `CPShock^ann_t` = sum of Känzig monthly `Shock` over each calendar year, 2005–2019. *Known weak: annual SD 0.53, S7–S11 failed in [PASSTHROUGH_CPSHOCK.md](PASSTHROUGH_CPSHOCK.md).*
  - ID-B: `EUA_t` = annual mean of daily EUA price (already loaded in [phase3_build_exposure_panel.R](analysis/phase3_build_exposure_panel.R)).
  - ID-C: `Post_t` dummies for MSR (T*=2014, Commission proposal) and Phase IV (T*=2018, Council approval 2018-02), with event-time indexing for h ∈ {−3..+5}.
- [ ] **Verification before regressions:** aggregate `firm_cost_share_i` to NACE4d with firm total-cost weights and confirm it reproduces `intensity_base_s` from [phase3_build_exposure_panel.R](analysis/phase3_build_exposure_panel.R). Mismatch = build bug.

### Step 2 — Angle 1: firm-level output reallocation
New script: `analysis/phase4_firm_output_reallocation.R`. Each spec is estimated under ID-A, ID-B, and ID-C.

- [ ] **Spec 1.A (base H1 test):** `Δlog(real_rev)_{i,s,t,h} = β·(Signal_t × firm_dev_{i,s}) + α_{s,t} + α_i + ε`, horizons h ∈ {0,1,2,3}, two-way cluster firm and sector-year. Run 3× (one per signal).
- [ ] **Spec 1.B (pass-through interaction):** add `β2·(Signal_t × firm_dev_{i,s} × intensity_base_s)`. H1 → β2 < 0; H2 → β1 ≈ β2 ≈ 0. Run 3×.
- [x] **Spec 1.C (sample split on realized pass-through) — first pass done 2026-04-22.** Per-sector γ̂_s via interacted panel LP at h=12; sample-split Spec 1.A across six classification cutoffs. Results in [REALLOCATION_FINDINGS.md](REALLOCATION_FINDINGS.md) Phase 4 (cont.) section. Two open follow-ups below.
- [ ] **Spec 1.C follow-up A — diagnose Shock vs Surprise sign flip.** Firm-level Spec 1.A and per-sector γ̂_s both flip sign between `cpshock_shock` (positive) and `cpshock_surprise` (negative) regressors. Same pathology as S7–S11 in [PASSTHROUGH_CPSHOCK.md](PASSTHROUGH_CPSHOCK.md). Need to understand: is it levels-vs-flows (Shock carrying VAR-level persistence co-moving with EUA price level and therefore with trending PPIs); is it the mean-zero vs non-mean-zero property; or is it a per-sector vs aggregate difference? Until this is understood, sign interpretation of Spec 1.A/1.B/1.C under ID-A is not trustworthy.
- [ ] **Spec 1.C follow-up B — better sector classification (rank-based).** Current `cpshock_shock` classification is nearly non-discriminating (118 of 133 sectors are γ̂_s > 0); `cpshock_surprise` classification is too noisy at NACE4d (no sector reaches t > 1.645). Replace with a rank-based rule that does not depend on statistical significance — e.g., top decile under *both* shock and surprise, or top tercile under the pooled-absolute-rank. Re-run Spec 1.A on the rank-defined high-pass-through sectors.
- [ ] **Spec 1.D (ETS × non-ETS margin + placebo):** run Spec 1.A on the full firm panel (ETS + non-ETS) with ETS dummy × Signal × `intensity_base_s` triple interaction, `firm_cost_share_i = 0` for non-ETS. Under ID-B this doubles as the placebo test — non-ETS coefficient must be null for ID-B to be clean. Closes the loop with [phase0_ets_share_shift.R](analysis/phase0_ets_share_shift.R). Run 3×.
- [ ] **Reporting:** coefficient tables Spec 1.A–1.D × ID-A/B/C × horizons. Binscatter of Δlog(real_rev) on `firm_dev` within sector pass-through terciles. Dose-response plot of β by `intensity_base_s` decile. Event-study plot for ID-C (β_h, h = −3..+5). Robustness column swapping `firm_cost_share_i` → `firm_emint_physical_i`.
- [ ] **Verification:** Spec 1.A without the signal interaction should recover the within-sector output-share sign in [phase1a_output_share_by_exposure.R](analysis/phase1a_output_share_by_exposure.R) (caveat: phase1a uses revenue-normalized treatment, so magnitude differs, sign should match).

### Step 3 — Angle 4: B2B supplier switching
New script: `analysis/phase4_b2b_supplier_switching.R`. B2B cross-section is large enough that ID-A is more likely to work here than in Angle 1.

- [ ] Build (seller_j, buyer_b, year_t) panel from `b2b_selected_sample.RData`, restricting seller side to ETS firms with known `firm_cost_share_j`. Compute `flow_{j,b,t}` and within-buyer within-seller-sector share.
- [ ] **Spec 4.A (flow pair panel):** `Δlog(flow)_{j,b,t,h} = β·(Signal_t × firm_cost_share_j) + α_{b,t} + α_{j,b} + ε`, two-way cluster on seller and buyer. Run 3×.
- [ ] **Spec 4.B (within-sector supplier share):** `Δshare_{j,b,t,h} = β·(Signal_t × firm_dev_{j,s(j)}) + α_{b,s(j),t} + α_{j,b} + ε`. Tightest H1 test. Run 3×.
- [ ] **Spec 4.C (pass-through triple):** add `× intensity_base_{s(j)}` interaction to 4.A and 4.B. Run 3×.
- [ ] **Spec 4.D (non-ETS seller placebo):** enlarge seller side to include non-ETS sellers (`firm_cost_share_j = 0`); add ETS-dummy × Signal interaction. Under ID-B, non-ETS sellers should not systematically gain/lose share conditional on buyer × sector × year FE. Parallel to Spec 1.D.
- [ ] **Extensive margin:** LPM on relationship continuation — do buyers *drop* high-carbon-cost-share suppliers? Run 3×.
- [ ] **Local vs RMD:** develop on local 1 downsampled B2B for code correctness only; pair FE collapses on downsampled. Deploy to RMD for real estimates.
- [ ] **Verification:** pair-level flows summed to totals should reconcile with phase0 B2B aggregates.

### Step 4 — Assemble and cross-reference
- [ ] Produce Angle 1 × Angle 4 × ID-A/B/C results matrix (6 cells) with coefficients on `(Signal × firm_cost_share)`. Publishable result = sign consistency across the matrix, not p-values in any single cell.
- [ ] Ask Känzig (advisor per [memory/project_advisors_and_collaborators.md](memory/project_advisors_and_collaborators.md)) for BKR-extended CPShock. Re-run ID-A only if it increases pre-2019 annual variation; skip if the extension is Phase-IV-only.
- [ ] After Angles 1 and 4 land, move the "Further analysis — PRODCOM" section from [REALLOCATION_MECHANISM_PLAN.md](REALLOCATION_MECHANISM_PLAN.md) into a new "Reallocation extension" section of [PRODCOM_PLAN.md](PRODCOM_PLAN.md).

---

## 2. PRODCOM pass-through workstream (added 2026-04-21)

Context: [analysis/prodcom_passthrough_stata/](analysis/prodcom_passthrough_stata/) is a Stata port of the data-cleaning pipeline so the co-author (Stata-only, on RMD) can reproduce the analysis end-to-end. First pass landed data-build scripts `00_` through `05_` + `verify_against_R.R`. Regression scripts, sample-selection logic, and local testing still open. Full plan: [PRODCOM_PLAN.md](PRODCOM_PLAN.md).

### ~~Step 1 — Port annual-accounts sample selection~~ (done 2026-04-21)
~~Write `02a_build_annual_accounts_selected_sample.do` mirroring `inferring_emissions/preprocess/annual_accounts_sample_selection.R`. Two filters: `wage_bill > 0` (v_0001023) and `turnover_VAT > 0`. Save `annual_accounts_selected_sample.dta` with (vat_ano, year). Then wire into `02_build_firm_year_euets.do` to populate the `in_sample` dummy (currently `.`), and into `05_build_prodcom_panel.do` as an optional filter.~~

**Resolved:** default to `keep if in_sample == 1` in `05_`, switchable via `global APPLY_IN_SAMPLE` (set to `1` by default; flip to `0` to match MMS 2024). In `05_` the dummy is merged directly from `02a_` output, not via `firm_year_belgian_euets.dta`, so non-ETS firms with positive wage bill + turnover are not incorrectly dropped.

### Step 2 — Run the pipeline on RMD against the mock `prod.dta` (updated 2026-04-22)
Local-1 Stata is not available (no install, no license). Local-2 is a bridge-only machine. Testing venue is RMD. On RMD, `cd` into `analysis/prodcom_passthrough_stata/` and run `00_` → `01_` → `02a_` → `02_` → `03_` → `04_` → `05_` in order. Before running, confirm (a) the `jardang` branch of `00_paths.do` points at the right `$DATA_DIR` / `$REPO_DIR`, and (b) the public inputs listed in the README (EUTL CSVs, ICAP CSV, Statbel XLSX, Eurostat CSV) are staged under `$RAW_DATA`. Expected: steps 01–04 match the R reference closely (verify via `verify_against_R.R`, run locally); step 05 produces a structurally-correct panel with zero merge matches on exposure (RMD's `prod.dta` is the same mock as local-1 — numeric IDs don't match real `vat_ano` hashes, since only the co-author has the real PRODCOM).

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
Confirm with co-author that on RMD `prod.dta`'s `ID` column matches `vat_ano` in `Annual_Accounts_MASTER_ANO.dta` (string 64-char hash). If instead it's a separate numeric identifier, add a crosswalk merge in `05_build_prodcom_panel.do`.

### Step 6 — Reallocation extension (linked to workstream 1)
Once the reallocation-mechanism results land (workstream 1), append the "Further analysis — PRODCOM" section from [REALLOCATION_MECHANISM_PLAN.md](REALLOCATION_MECHANISM_PLAN.md) into [PRODCOM_PLAN.md](PRODCOM_PLAN.md). That block specifies a quantity-dose-response regression and a joint price-quantity test as the sharpest PC8 × month discrimination between H1 and H2.

---

## 3. Threat-hypothesis workstream (added 2026-04-22)

Source: [TREAT_HYPOTHESIS_PLAN.md](TREAT_HYPOTHESIS_PLAN.md). Goal: test whether firms invest in cleaner technology in response to *news* about future carbon policy (CPShock), not only realized EUA prices. Deferred — no implementation yet.

### Step 1 — Build the NACE × carbon-leakage-status panel
- [ ] Parse annexes of Commission Decisions 2009/161/EC, 2014/746/EU, 2019/708/EU into a NACE4d × year dataset of free-allocation status. Output: `data/processed/cl_status_by_nace4d.csv`. Estimated ~1 day.

### Step 2 — Add investment / capex measures to the firm panel
- [ ] Pull tangible-asset lines from Annual Accounts; build log(capex / revenue) and energy-cost share. Reuse `intensity_base` from S12. Estimated ~1 day.
- [ ] Diagnose lumpiness: variance decomposition of firm-year capex to decide between flow vs 3-year-window vs stock measure.

### Step 3 — Strategy A: direct S12 analog on investment
- [ ] `Δlog(capex_{i,t+h}) = γ_h · (CPShock_t × intensity_base_i) + α_i + δ_t + ε`. Reuse [phase3_ppi_passthrough_monthly.R](analysis/phase3_ppi_passthrough_monthly.R) as template, swap LHS. Placebo on non-ETS firms matched by size × sector × region.

### Step 4 — Strategy B: horse race threat vs realized price
- [ ] Decompose `EUA_t` into `cum_CPShock`-news component + residual; re-run with both interactions. Hypothesis: γ₁ (news) >> γ₂ (residual price).

### Step 5 — Strategy C: carbon-leakage-list event study (sharpest)
- [ ] Event study around 2014-05 (Decision 2014/746/EU) and 2019-02 (Decision 2019/708/EU). Treatment: sectors removed from the leakage list (lose free-allocation protection going forward). Pre-trends h = −3…−1, post h = 0…+5. Non-ETS placebo required.
- [ ] Use earliest credible announcement date (Commission proposal) rather than final Decision to avoid attenuation from anticipation.

### Step 6 — Pre-trend and robustness
- [ ] Non-ETS matched placebo on size × sector × region. Check pre-event parallel trends for investment.

### Risks / knowns
- Capex is lumpy and noisy at firm-year; Step 2 lumpiness diagnosis gates the LHS choice.
- 2014 CL-list event was largely expected through 2013 — use earliest announcement.
- Pre-2005 counterfactual thin; anticipatory investment in 2003 underpowered.

---

## 4. Greenflation workstream (added 2026-04-22)

Source: [greenflation.md](greenflation.md) (literature review). Goal: deliver a firm- and sector-level test of carbon-price pass-through into realized prices that extends Hensel et al. (2024) and Känzig–Konradt (2023) using Belgian data's unique firm-level ETS identification. No implementation plan yet — this is an open research agenda to be scoped before work starts.

### Step 1 — Scope into a concrete plan
- [ ] Convert `greenflation.md` section "How this project's data can extend this literature" (subsections 1–6) into a sequenced implementation plan (analogue of `REALLOCATION_MECHANISM_PLAN.md` or `TREAT_HYPOTHESIS_PLAN.md`). Output: `GREENFLATION_PLAN.md`.

### Step 2 — Candidate tests (from the lit-review synthesis, to be prioritized)
- [ ] Firm-level Hensel-style pass-through: CPShock × firm ETS exposure → realized unit prices (PRODCOM) and sector PPI. Leverages existing PRODCOM and S12 machinery.
- [ ] Within-Belgium version of the Känzig–Konradt channel decomposition (coverage, leakage) — using B2B-derived direct vs network-propagated exposure.
- [ ] Empirical test of the DDD (2025) two facts for Belgium: energy centrality in the I/O matrix, and emission-intensive sectors' price-change frequency.
- [ ] Free-allocation heterogeneity: within-Belgium replication of Känzig–Konradt's cross-country allocation result, using firm-year `allocated_free` from EUTL.
- [ ] Price leakage in small open economy: does pass-through rise in sectors with low import exposure? Requires customs × PRODCOM × PPI.
- [ ] Phase IV as a natural experiment: first high-EUA-price window for a within-country test.

### Step 3 — Open questions to resolve before designing regressions
- [ ] Why do Bettarelli (2025) and Konradt–WdM (2023) find opposite signs? Does the Bettarelli result survive in an OECD-only subsample? Matters because Belgium is OECD-European and inherits the Konradt–WdM benchmark.
- [ ] Clean side-by-side mapping between pass-through layers (wholesale, futures, HICP, NACE4d PPI, firm unit prices). Missing from the literature; this project is positioned to deliver it.
- [ ] Direct vs network-propagated pass-through decomposition. DDD counterfactuals say IO propagation ≈ 2/3 of core inflation response; our B2B-derived Leontief can test this empirically (caveat: downsampled local version only directional; real decomposition needs RMD).

---

## 5. Legacy — Phase 3 shock-size / abatement diagnostics

Context: originally scoped under the Phase 3 pipeline (`phase3_*`, addressing histograms of carbon cost share, sector-level pass-through, and shock-size diagnostics). Items below were postponed until headline diagnostics landed. They touch multiple workstreams above (reallocation, threat, greenflation) and don't belong exclusively to any one, so they sit here until reshelved.

### Task 3.5 — Benchmark EUA-driven cost variation against other shocks (added 2026-04-21)
Compare within-firm standard deviation of `(shortage × EUA price) / total_cost` against within-firm s.d. of other cost shocks, 2005–2023:

- Natural gas wholesale price (TTF front-month, annual mean)
- Electricity wholesale price (Belgian day-ahead or equivalent)
- Nominal wage growth (annual % change, from `wage_bill` at firm level)

If EUA-driven variation is an order of magnitude smaller than gas or electricity, that is itself a headline. One figure, one table: within-firm s.d. per component by phase.

### Task 3.6 — Abatement speed after the Phase IV price jump (added 2026-04-21)
Direct test of the hypothesis that pollutant firms "protect" customers by abating quickly. For high-shortage firms (top tercile of 2013–2016 shortage intensity, following Phase 1a), plot:

- within-firm emissions growth 2020 → 2021 → 2022 → 2023
- within-firm shortage growth (net of free-allowance reduction)
- within-firm emissions intensity (emissions / real revenue)

Compare to matched low-shortage ETS controls. If abatement is fast (>5% YoY within two years of the price jump), that shortens the reallocation window and supports a "shock was small in effective terms" story.

### Triggers for revisiting
- Task 1 histograms show the shock is genuinely small through Phase III → both 3.5 and 3.6 become essential to quantify "how small".
- Task 2 pass-through not statistically significant → 3.5 becomes the explanation of last resort.
- Task 2 pass-through IS significant → 3.6 becomes a follow-up on timing/lag structure.
