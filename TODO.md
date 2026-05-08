# TODO

Open analyses that are deferred until headline results land. Add dated entries when new follow-ups appear; strike through and date items when they're closed out.

Five active workstreams:

0. **New exposure measure (high priority, added 2026-05-07)** — rebuild the firm-level treatment intensity as `emissions_pre × (1 − expected_allocation_share_post)` with both pieces predetermined / exogenous to MSR. See §0 below.
1. **Reallocation mechanism** — H1 (within-sector reallocation) vs H2 (inelastic-demand shield). Plan: [REALLOCATION_MECHANISM_PLAN.md](REALLOCATION_MECHANISM_PLAN.md).
2. **PRODCOM pass-through** — Stata port of firm × PC8 × month pipeline for co-author. Plan: [PRODCOM_PLAN.md](PRODCOM_PLAN.md).
3. **Threat hypothesis** — do firms invest in cleaner tech in response to carbon-price news, not only realized prices? Plan: [TREAT_HYPOTHESIS_PLAN.md](TREAT_HYPOTHESIS_PLAN.md).
4. **Greenflation** — firm-level test of CPShock pass-through into realized prices, extending Hensel et al. / Känzig-Konradt. Lit review: [greenflation.md](greenflation.md).

A sixth section at the bottom holds shock-size / abatement-timing diagnostics from the earlier Phase 3 scope that aren't tied to any single workstream.

---

## 0. New exposure measure (added 2026-05-07)

### Motivation

Current `firm_cost_share_j` (defined in [phase5_attach_firm_cost_share.R](analysis/phase5_attach_firm_cost_share.R) and [paper/leakage_within_across/sections/data.tex](paper/leakage_within_across/sections/data.tex)):

```
firm_cost_share_j = avg(shortage × EUA, 2013–2016) / avg(total_cost, 2010–2012)
```

has three problems we surfaced in conversation 2026-05-07:

1. **Numerator extends to 2016**, past the MSR decision (Oct 2015), so the regressor is not strictly predetermined.
2. **EUA inside the regressor adds no cross-sectional content** (EUA is firm-invariant in the construction window) and only adds within-window timing noise.
3. **Asymmetric numerator/denominator windows** (2013–16 vs 2010–12) are motivated by anticipation concerns that DiD's parallel-trends assumption is supposed to rule out anyway — internally inconsistent.

The replacement separates **firm-structural exposure** (predetermined, pre-2016) from **institutional shortfall** (sector × year, exogenous to firm response, built from public EU rules):

```
treatment_intensity_j = (avg(emissions, 2013–2015) / avg(total_cost, 2013–2015))
                        × (1 − expected_allocation_share_post_j)
```

where `expected_allocation_share_post_j` is the average post-2015 ratio of expected free allowances to expected emissions, with allowances projected from realized 2013 firm allocation × sector-year institutional ratios (Phase III + Phase IV rules), and emissions held at the 2013–15 average. The criterion is **exogeneity to firm response to MSR**, which permits using post-MSR institutional rules (Phase IV decisions of 2018–19) as long as they are EU-level policy choices not caused by individual firm behaviour.

Detailed conceptual derivation is in the conversation transcript of 2026-05-07.

### Step 1 — Download and digitize EU institutional rule book

Goal: produce four CSV tables under `data/processed/eu_ets_rules/` covering 2013–2030.

#### 1.1 Carbon-leakage list at NACE 4-digit

- [ ] Download Commission Decision 2010/2/EU (Phase III leakage list 2013–14). EUR-Lex CELEX 32010D0002. https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32010D0002
- [ ] Download Commission Decision 2014/746/EU (Phase III leakage list 2015–19). EUR-Lex CELEX 32014D0746. https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32014D0746
- [ ] Download Commission Delegated Decision (EU) 2019/708 (Phase IV leakage list 2021–30). EUR-Lex CELEX 32019D0708. https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32019D0708
- [ ] Digitize each Annex into a tidy CSV with columns `(nace4d, on_list_2013_14, on_list_2015_19, on_list_2021_30)`. Each list is ~150–200 NACE 4-digit codes. Hand-typing or `tabula`/`pdfplumber`. Save as `data/processed/eu_ets_rules/leakage_list_by_nace4d.csv`.
- [ ] **Verification:** spot-check Belgian ETS sectors (NACE 19 petroleum, 20 chemicals, 23 cement/glass, 24 basic metals) against the existing hand-coded `allocation_rule` table at [phase0_sector_phase_dataset.R:63](analysis/phase0_sector_phase_dataset.R) — they should agree on whether each NACE 2-digit's dominant sub-sectors are on each list.

#### 1.2 Cross-sectoral correction factor (CSCF), Phase III only

- [ ] Copy CSCF values 2013–2020 from Annex II of Commission Decision 2013/448/EU. EUR-Lex CELEX 32013D0448. Save as `data/processed/eu_ets_rules/cscf_phase3.csv` with columns `(year, cscf)`. ~8 rows. Reference values (verify against Annex II): 2013 ≈ 0.9427, 2014 ≈ 0.9263, 2015 ≈ 0.9100, 2016 ≈ 0.8936, 2017 ≈ 0.8772, 2018 ≈ 0.8609, 2019 ≈ 0.8445, 2020 ≈ 0.8281.

#### 1.3 Phase-out factor for non-leakage sectors

- [ ] Build `data/processed/eu_ets_rules/phaseout_factor.csv` with columns `(year, phaseout_non_leakage, phaseout_leakage)` from the formula in Article 10a(11) of Directive 2003/87/EC (Phase III) and Article 10b (Phase IV). No download — mechanical:
  - Phase III non-leakage: 0.80 in 2013, declining linearly to 0.30 by 2020.
  - Phase III leakage: 1.00 throughout 2013–2020.
  - Phase IV non-leakage 2021–25: 0.30. 2026–30: declining linearly from 0.30 to 0.00.
  - Phase IV leakage 2021–25: 1.00. 2026–30: 1.00 (subject to revision).

#### 1.4 Phase IV linear reduction factor (LRF) and benchmark updates

- [ ] Encode Phase IV LRF = 2.2%/year from 2021 (Article 9 of Directive (EU) 2018/410). Save as `data/processed/eu_ets_rules/lrf_phase4.csv` with columns `(year, cap_factor_relative_to_2020)`.
- [ ] Optional (skip on first cut): download Phase IV benchmark updates from Commission Implementing Regulation (EU) 2021/447 (CELEX 32021R0447). Provides updated benchmark values for 2021–25; subsequent regulations cover 2026–30. https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32021R0447. Digitize Annex into `data/processed/eu_ets_rules/phase4_benchmarks.csv` with columns `(sector_benchmark_id, value_phase3, value_phase4_2021_25)`. **Skip if first iteration uses realized 2013 allocation as the baseline (recommended) — benchmarks are then implicit.**

### Step 2 — Build the projected sector-year allocation factor table

- [ ] New script `analysis/build_eu_ets_allocation_factor.R`. Inputs: the four CSVs from Step 1. Output: `data/processed/eu_ets_allocation_factor_by_nace4d_year.RData` with one row per `(nace4d, year)` for `year ∈ 2013..2022` and column `allocation_factor`:

```
allocation_factor(nace4d, year) = leakage_factor(nace4d, year) × cscf_or_lrf(year) × phaseout(year)
```

  where `leakage_factor` is 1 if on-list and `phaseout_non_leakage` ratio if not, `cscf_or_lrf(year)` applies CSCF for 2013–2020 and the relative LRF for 2021–22, and `phaseout(year)` applies the Article 10a(11) / 10b schedule. The exact functional form needs care at the 2020/2021 boundary — verify with one Belgian leakage-listed firm (e.g. a NACE 24 basic-metals installation) against realized EUTL allowance trajectory. Sign-off rule: predicted-vs-realized correlation > 0.9 within Phase III for that firm.

### Step 3 — Build the new firm-year exposure regressor

- [ ] New script `analysis/build_firm_exposure_v2.R`. Replaces (does not modify) [phase5_attach_firm_cost_share.R](analysis/phase5_attach_firm_cost_share.R). Inputs:
  - `firm_year_belgian_euets.RData` (RMD): emissions and free allowances per VAT-year.
  - `data/processed/eu_ets_allocation_factor_by_nace4d_year.RData` from Step 2.
  - Annual Accounts firm-year total cost.
  - Per-VAT NACE 4-digit code.
- [ ] Per VAT j, compute:
  - `emission_intensity_j = mean(emissions_{j,t} / total_cost_{j,t}, t ∈ 2013..2015)`. Drop firms with missing emissions or zero total cost in any of 2013–2015.
  - `baseline_allowance_j = mean(free_allowance_{j,t}, t ∈ 2013..2015)` — predetermined firm-level allocation anchor.
  - `expected_allowance_j(t)` for `t ∈ 2016..2022`: scale `baseline_allowance_j` by `allocation_factor(nace4d_j, t) / mean(allocation_factor(nace4d_j, 2013..2015))`.
  - `expected_emissions_j(t) = mean(emissions_{j,t}, t ∈ 2013..2015)` held constant.
  - `expected_allocation_share_j_post = mean(expected_allowance_j(t) / expected_emissions_j, t ∈ 2016..2022)`.
  - `treatment_intensity_v2_j = emission_intensity_j × max(0, 1 − expected_allocation_share_j_post)`.
- [ ] Save `firm_exposure_v2.RData` with `(vat, nace4d, emission_intensity, baseline_allowance, expected_allocation_share_post, treatment_intensity_v2)`.
- [ ] **Diagnostic:** report cross-sectional correlation between `treatment_intensity_v2_j` and the legacy `firm_cost_share_j`. Expect high (> 0.7) but not perfect — if very high (> 0.95) the redesign may not change much; if low (< 0.4) something is off.
- [ ] **Sanity check:** sort firms by `treatment_intensity_v2_j` and inspect the top decile by NACE 4-digit. Should be dominated by basic metals, cement, refining, chemicals, paper.
- [ ] **Phase II analog:** `treatment_intensity_v2_phase2_j = mean(emissions, 2005..2007) / mean(total_cost, 2005..2007) × (1 − expected_allocation_share_phase2_post)` where the post-period is 2008–2012 and the institutional schedule uses Phase II free allocation rules (mostly grandfathered → 100% free, so `expected_allocation_share_phase2_post ≈ 1` for many firms; the regressor then collapses to physical emission intensity). Worth building as a robustness sibling for §5.1.6.

### Step 4 — Re-run the headline DiD specifications with the new regressor

The legacy `firm_cost_share_j` is consumed in 37 R scripts under `analysis/`. Most are diagnostics or robustness siblings; the following is the minimal re-run set for the paper headlines.

#### Headline regressions

- [ ] **§5.1.1 Test H within-NACE-4d** — re-run with `treatment_intensity_v2`. Script: [phase5_test_h_most_exposed_ets_supplier.R](analysis/phase5_test_h_most_exposed_ets_supplier.R) and trend-corrected sibling [phase6_test_h_corrected.R](analysis/phase6_test_h_corrected.R). Compare β headline and σ̂ mapping to the old version. RMD-only.
- [ ] **§5.1.4 Test I across-category** — recompute `nace_exposure_n` from new `treatment_intensity_v2_j` per [phase3_build_exposure_panel.R](analysis/phase3_build_exposure_panel.R). Re-run [phase5_test_i_cross_nace_substitution.R](analysis/phase5_test_i_cross_nace_substitution.R) and [phase6_test_i_corrected.R](analysis/phase6_test_i_corrected.R). RMD-only.
- [ ] **§5.2.2 B1 buyer-supplier** — recompute `pair_exposure_EU_{f,p}` per [phase6_b1_corrected.R](analysis/phase6_b1_corrected.R) using new firm-level exposure. RMD-only.

#### Horizon LPs

- [ ] **§5.1.2** [phase6_a1_test_h_horizon_lp.R](analysis/phase6_a1_test_h_horizon_lp.R) re-run.
- [ ] **§5.1.4 HTE** [phase6_a2_test_i_horizon_hte.R](analysis/phase6_a2_test_i_horizon_hte.R) re-run.
- [ ] **§5.2.3 B2** [phase6_b1_b2_customs_buyer_supplier.R](analysis/phase6_b1_b2_customs_buyer_supplier.R) re-run.

#### Phase II event-study

- [ ] **§5.1.6/7** [phase6_a3_a4_phase2_eventstudy.R](analysis/phase6_a3_a4_phase2_eventstudy.R) re-run with `treatment_intensity_v2_phase2`.

#### Pre-trend / sensitivity follow-ons

- [ ] [phase6_a6_pretrend_power.R](analysis/phase6_a6_pretrend_power.R) — re-run with new regressor; the Roth (2022) power analysis depends on regressor scale.
- [ ] [phase6_a7_honestdid.R](analysis/phase6_a7_honestdid.R) — Rambachan-Roth breakdown values rescale with the regressor.
- [ ] [phase6_a8_dcdh_test_h.R](analysis/phase6_a8_dcdh_test_h.R) and [phase6_a8b_dcdh_test_h_phase2.R](analysis/phase6_a8b_dcdh_test_h_phase2.R) — dCdH static intensity with the v2 regressor.
- [ ] [phase6_a9_drdid_test_i.R](analysis/phase6_a9_drdid_test_i.R) — DRDID with the v2 regressor.

#### Defer for now

- [ ] **Time-varying intensity (R7a/b/c):** [phase6_a10_build_timevarying_intensity.R](analysis/phase6_a10_build_timevarying_intensity.R), [phase6_a10_dcdh_timevarying_test_h.R](analysis/phase6_a10_dcdh_timevarying_test_h.R), [phase6_a10b_dcdh_timevarying_test_i.R](analysis/phase6_a10b_dcdh_timevarying_test_i.R), [phase6_a10c_dcdh_timevarying_phase2.R](analysis/phase6_a10c_dcdh_timevarying_phase2.R). The v2 regressor is already a partial reconciliation with these specs (it captures sector × year institutional variation), so the dCdH-2022 cross-checks become less load-bearing.

### Step 5 — Update paper

- [ ] Rewrite the "Treatment intensity" subsection of [paper/leakage_within_across/sections/data.tex](paper/leakage_within_across/sections/data.tex) (currently §2 Setting and Data, equation 2.1) with:
  - The new exposure formula and its decomposition into firm-structural × institutional components.
  - A short paragraph explaining the predetermination criterion (exogeneity to firm response, not info-set membership).
  - One sentence flagging that the legacy `firm_cost_share` formulation is reported as a robustness sibling.
- [ ] Replace headline coefficients in [leakage_domestic.tex](paper/leakage_within_across/sections/leakage_domestic.tex) §5.1.1, §5.1.2, §5.1.4, §5.1.6/7 with the v2 results.
- [ ] Replace headline coefficients in [leakage_international.tex](paper/leakage_within_across/sections/leakage_international.tex) §5.2.2, §5.2.3 with the v2 results.
- [ ] Re-derive σ̂ mapping in §5.1.1 — the constant `100 ρ E[s_{j*}(1−s_{E_n})]` rescales because the regressor is now in tCO₂/€ instead of €/€. Specifically: if the new regressor is `R_j = (em/cost) × (1 − alloc_share)` and the old regressor was approximately `R_old_j ≈ R_j × EUA_pre`, then β_v2 / β_old ≈ 1 / EUA_pre. The σ̂ formula needs the post-period EUA path explicitly rather than baked into the regressor.
- [ ] Update [PAPER_STATUS.md](PAPER_STATUS.md) to flag every §5 row as RMD-RERUN-PENDING-V2 until the v2 numbers land.

### Step 6 — Robustness reports

- [ ] **Robustness column in main tables:** keep the legacy `firm_cost_share` regressor as a side-by-side robustness column. Two columns per headline: v2 (predetermined emission intensity × institutional shortfall) and v1 (legacy `firm_cost_share`). Pre-register the headline as v2; report v1 alongside.
- [ ] **Sensitivity to the institutional-rule projection:** run v2 under three institutional-rule variants:
  1. *Realized*: use realized post-2015 free allowances directly (not exogenous on the user's criterion — partial endogeneity via Phase IV HAL — but a useful upper bound).
  2. *Phase III + linear extrapolation*: stop institutional rules at 2020 and linearly extrapolate to 2022.
  3. *Full institutional projection (headline)*: Phase III rules through 2020, Phase IV rules from 2021.
  Report the three side-by-side. If v2-headline and v2-realized agree to within sampling noise, the institutional-rule construction is doing what it should.
- [ ] **Truncated post-period:** report v2 with post-period = 2016–2020 only (Phase III window). Cleanest information-set defense; loses the Phase IV price spike but rules out any Phase IV endogeneity concern.

### Estimated effort

| Step | Owner | Venue | Time |
|---|---|---|---|
| 1.1–1.4: download + digitize 4 EU rule files | local-1 (web) | local-1 | 1–2 hours |
| 2: build sector-year allocation factor table | local-1 | local-1 | 0.5 day |
| 3: build firm-year v2 exposure | RMD | RMD | 0.5 day |
| 4: re-run ~10 headline + horizon scripts | RMD | RMD | 1 day total runtime, sequential |
| 5: paper rewrite of §2 + §5 numbers | local-1 | local-1 | 0.5 day |
| 6: robustness siblings | RMD | RMD | 0.5 day |

**Total: ~3–4 days of work, ~80% of which is on RMD.** Step 1's downloads can be done on local-2 (web access) and copied to RMD via the standard cloud bridge.

### Verification gates

- [ ] After Step 2: predicted-vs-realized 2013–2020 free-allowance correlation > 0.9 for at least 3 representative Belgian leakage-listed firms.
- [ ] After Step 3: cross-sectional correlation of `treatment_intensity_v2_j` with legacy `firm_cost_share_j` > 0.7. Top decile dominated by NACE 19/20/23/24.
- [ ] After Step 4: v2 Test H σ̂ within ±50% of legacy σ̂ ≈ 1; if very different, suspect a unit error in the new regressor or the σ̂ mapping.
- [ ] After Step 6: v2-headline and v2-realized institutional projections agree to within sampling noise on the Test H coefficient.

### Open issues to resolve along the way

- [ ] **Phase IV HAL endogeneity.** Phase IV initial allocation uses 2014–2018 activity. Using realized post-2015 allocation in the regressor partially imports firm response to MSR. Headline construction (Step 3) sidesteps this by using *predetermined* 2013–15 allocation as the baseline and projecting forward with sector-year ratios only, not realized allocations. Robustness sibling (Step 6.1) uses the realized variant as a comparator.
- [ ] **NACE 4-digit ↔ leakage-list mapping.** Phase IV leakage list (Decision 2019/708) mixes NACE 4-digit and "subsector" classifications; some sectors are listed at finer-than-4-digit granularity. For our coarser classification we either (a) treat the whole NACE 4-digit as on the list if any subsector is, or (b) drop ambiguous NACE 4-digits. Decide before Step 1.1.
- [ ] **Belgian aluminium / ferro-alloys reclassifications post-2020.** [memory/project_nace24_eutl_break_post2020.md](memory/project_nace24_eutl_break_post2020.md) flags 3 NACE 24 VATs whose post-2020 EUTL coverage breaks. The v2 regressor must continue to exclude these VATs from 2021+ — code in [phase6_a10_build_timevarying_intensity.R](analysis/phase6_a10_build_timevarying_intensity.R) already handles this; copy that filter into `build_firm_exposure_v2.R`.

---

## 0a. Pass-through reconciliation + early EUA price acquisition (added 2026-05-07)

### Reconciliation: PPI panel-LP magnitude discrepancy (FIRST-ORDER)

The new Känzig-style PPI IRF in [analysis/phase3_ppi_lp_kanzig_style.R](analysis/phase3_ppi_lp_kanzig_style.R) gives γ_h values that are **3–4× smaller** than the same spec recorded in [output/tables/phase3_ppi_passthrough_monthly.txt](output/tables/phase3_ppi_passthrough_monthly.txt) (e.g. γ_12 = 1.22 new vs β_12 = 4.08 saved, with proportional SE rescaling). Same N at every horizon, same code path, same RHS variable name, same regression structure. The shape of the IRF is preserved.

Most likely culprit: `exposure_alt_total` in [data/processed/phase3_sector_exposure.RData](data/processed/phase3_sector_exposure.RData) has been re-scaled or re-normalised since the original [output/tables/phase3_ppi_passthrough_monthly.txt](output/tables/phase3_ppi_passthrough_monthly.txt) was written. Both the coefficient and the SE rescale by the same factor, which is exactly what a units change in `intensity_base` would do.

This bears on the §4 paper claim ($\sigma$ mapping from sector pass-through) and must be settled before publication.

- [ ] Compare the current `exposure_alt_total` in `phase3_sector_exposure.RData` with the field as it stood when the saved `phase3_ppi_passthrough_monthly.RData` / `.txt` were last regenerated. Run `git log -- analysis/phase3_build_exposure_panel.R` and `git log -- analysis/phase3_ppi_passthrough_monthly.R` to identify the change.
- [ ] If `exposure_alt_total` was rescaled (e.g. from cost-share fraction to percentage points, or vice versa), pick the correct scale and document it explicitly in [phase3_build_exposure_panel.R](analysis/phase3_build_exposure_panel.R).
- [ ] Re-run [phase3_ppi_passthrough_monthly.R](analysis/phase3_ppi_passthrough_monthly.R) and confirm headline coefficients now match the new Känzig-style IRF at horizons {0, 1, 3, 6, 12, 24}.
- [ ] Update §4 prose in [paper/leakage_within_across/sections/passthrough.tex](paper/leakage_within_across/sections/passthrough.tex) with the verified magnitudes (currently quotes γ_12 = 1.22 from the new run; verify this is the right scale).
- [ ] Re-derive the implied σ at the post-period EUA path under the verified scale; confirm the §5.1 σ ≈ 1 anchor still holds.

### Daily EUA price 2005–2009 acquisition — DONE 2026-05-08

Resolved via Investing.com export of the EUA continuous front-year futures contract (`${RAW_DATA}/European Union Carbon Permits Allowance (EUA) Yearly Futures Historical Data.csv`, daily 2005-04-25 onward, same Refinitiv-`LECEZ` series convention used by Känzig 2023). The figure script ([phase3_eua_price_timeseries_figure.R](analysis/phase3_eua_price_timeseries_figure.R)) was rewritten to read this CSV in place of ICAP+annual-step fallback. Verified historical milestones on the regenerated series: Phase I peak €30.45 (Apr 2006); May 2006 trough €9.30; 2007 mean €1.28 (≈0); Phase II 2008-H1 mean €23.60; 2009-Q1 trough €8.20; 2022 peak €98.01. Caption in [shock_magnitude.tex](paper/leakage_within_across/sections/shock_magnitude.tex) updated.

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
- **Why here (and not in the reallocation descriptive work).** The reallocation note already observes `shortage_{i,t} = max(emissions − free, 0)` directly at firm-year, so ``who pays how much'' is already identified without any allocation-rule crosswalk. The 4d CL list is valuable specifically as a *treatment indicator* for anticipation: a firm in a 4d sector that stays on the CL list after the 2014-05 revision learns it will keep free allocation; one removed from the list learns it will face declining free allocation starting in 2015+. That asymmetric announcement is the identification Strategy C below relies on. The reallocation note's §4 caveat on NACE 2d coarseness points here for that reason. Discussed 2026-04-23.

### Step 1b — Pre-2008 physical-intensity exposure measure (added 2026-04-23)
- [ ] Build `phys_intensity_s` = mean_{2005..07}(sector emissions / sector total cost) at NACE 4d, for sectors with ETS firms in the 2005-07 window. Source: `firm_year_belgian_euets` (emissions) + annual accounts (cost). Gives a **pre-Phase-2** exposure measure constructed from data that predates the main 2008+ EUA variation.
- [ ] Interaction `phys_intensity_s × EUA_t` interpreted as **latent / counterfactual carbon cost** if all emissions were priced. Rerun §5 of the reallocation note (ETS vs non-ETS) and §6 (within-ETS cross-sector) with this alternative exposure on 2008-2022.
- **Why here (and not in the reallocation descriptive work).** Under Phase 1--2 rules firms weren't actually paying carbon cost on the portion of emissions covered by their NAP free allocation, so `phys_intensity × EUA` during 2008-12 attributes a carbon cost they didn't face. Any response β picks up is therefore a response to *latent / anticipated* carbon cost, which is the threat-hypothesis exercise, not the realized-cost reallocation exercise in the paper note. Discussed 2026-04-23.

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
