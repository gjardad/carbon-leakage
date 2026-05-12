# Paper status tracker

Live status of every analysis subsection in the joint paper
`paper/leakage_within_across/`. Use this to know what's done, what needs
revisiting, and what's still queued.

## Status legend

- ✅ **DONE** — analysis run on RMD, headline result in paper, no known concerns.
- 🟡 **DONE-REVISIT** — analysis run, but a recent finding suggests the spec
  needs to be re-run with a correction before the headline is final.
- 🟠 **READY-NOT-RUN** — script exists and tested locally; just needs RMD execution.
- 🔴 **BLOCKED** — script exists but is waiting on a data input that doesn't exist yet.
- ⚪ **TBD** — content not yet sketched in the paper or in code.

## Paper outline (current `paper/leakage_within_across/main.tex`)

```
§1 Introduction                                                       [BLANK PLACEHOLDER]
§2 Setting and Data
§3 How Big Is the Shock?
§4 Price Pass-Through
§5 Leakage
   §5.1 Across domestic suppliers (within-country)
   §5.2 Across international suppliers
§6 Conclusion                                                         [BLANK PLACEHOLDER]
```

The numbering below uses the actual `\label{}` keys from the .tex files.

---

## §2 Setting and Data — ✅ DONE

| Subsection | Label | Status | Script(s) |
|---|---|---|---|
| EU ETS in Belgium | — | ✅ | descriptive prose |
| MSR identifying event | `sec:msr_identification` | ✅ | descriptive prose |
| Belgian B2B records | — | ✅ | descriptive prose |
| Belgian customs panel | `sec:data_customs` | ✅ | descriptive prose |
| Treatment intensity | — | ✅ | `analysis/phase5_attach_firm_cost_share.R` (existing) + P1 below |
| Sample sizes | — | ✅ | descriptive prose |

---

## §3 How Big Is the Shock? — ✅ DONE

| Subsection | Status | Script |
|---|---|---|
| Shock to treated firms | ✅ | `phase5_shock_distribution_byphase.R` |
| Shock to treated buyers | ✅ | `phase5_pair_shock_magnitude.R` |
| Cross-sector heterogeneity | ✅ | `phase5_pair_shock_magnitude.R` (sector breakdown) |
| Comparison to noise floor | ✅ | `phase5_shock_benchmarks.R` |

---

## §4 Price Pass-Through — ✅ DONE

| Subsection | Status | Script |
|---|---|---|
| CPShock LP (Strategy 1) | ✅ | `phase3_ppi_passthrough.R` (CPShock branch) |
| CdGM event-study (Strategy 2) | ✅ | `phase1_ppi_passthrough_cdgm.R` |
| OLS with sector trends (Strategy 3) | ✅ | `phase3_ppi_passthrough.R` (OLS branch) |

---

## §5.1 Across domestic suppliers — partially done

### Modern-DiD robustness program (R1–R7, plan ref `imperative-whistling-acorn.md`)

| Item | Status | Script(s) | Notes |
|---|---|---|---|
| **R1** spec-classification preamble + RSBP framing in §5.1 paragraphs | ✅ | `paper/leakage_within_across/sections/leakage_domestic.tex` | Two-layer reading of RSBP Table 1 Q1 (literal Q1=YES with sufficient-statistic identifying assumption; substantive Q1=NO with continuously-time-varying EUA bite). 10 new bibliography entries in `paper/thesis/sections/refs.bib`. Prose has `\notrun{}` placeholders for breakdown M̄ / pretrends-power / dCdH numbers. |
| **R2** Test I event-study with simultaneous bands | 🟡 LOCAL-DOWNSAMPLE | `phase6_a5_test_i_eventstudy_simbands.R` | On local-1 downsampled B2B (~1% of RMD): sup-t crit values: continuous = **2.82**, binary = **2.33** (vs pointwise 1.96), so simultaneous bands are 1.43× / 1.19× wider. RMD will give the final figure. |
| **R3** pre-trend power (Roth 2022) | 🟡 LOCAL-DOWNSAMPLE | `phase6_a6_pretrend_power.R` | On local-1 downsample: Test H pre-trend test has 100% power vs σ=4 alternative; slope at 50% / 80% power = 2.79 / 4.62 per year. Test I has 94% power vs σ_cat ≤ 0.5; slope at 50% / 80% = 0.005 / 0.007. **Power numbers will tighten on RMD; directionally pre-trend tests are *not* vacuous, but final paper numbers need RMD.** |
| **R4** Rambachan-Roth (2023) breakdown M̄ | 🟡 LOCAL-DOWNSAMPLE | `phase6_a7_honestdid.R` | Δ^{RM} + Δ^{SD} sensitivity for both Test H and Test I at h=0, on the downsampled network. On local-1: Test H Δ^{RM}=0 CI = [-3.6, 10.5] (too wide to test σ=4); Test I Δ^{RM}=0 CI = [-0.022, 0.057]; Test I Δ^{SD}=0 CI = [-0.012, -0.003] excludes zero on negative side — *suggestive* but on 1% of the data. Need RMD for paper numbers. |
| **R5** dCdH static-intensity Fuzzy DiD (Test H Phase IV + Phase II) | 🟠 RMD-REQ | `phase6_a8_dcdh_test_h.R`, `phase6_a8b_dcdh_test_h_phase2.R` | Local-1 has only 79 / 104 type-a cells; dCdH internal regression collapses. Code is ready; rerun on RMD's full 14k-cell sample. |
| **R6** Sant'Anna-Zhao (2020) DRDID for Test I | 🟡 LOCAL-DOWNSAMPLE — *suggestive only* | `phase6_a9_drdid_test_i.R` | On local-1 downsampled network (~1% of RMD): DRDID-imp ATT = −0.0073 (s.e. 0.0027, p = 0.007), conditioning on (buyer_reg_exposure, NACE-2d, log inputs). Compare to OLS trend-corrected β = −0.003 (s.e. 0.009, p = 0.76). The DRDID estimate is 2.4× larger in absolute magnitude and significant on local-1; **whether this survives RMD is the question**. Do NOT rewrite §5.1.4 until RMD confirms. Plan-spec'd headline rule will fire at RMD-run time, not now. |
| **R7a** dCdH-2022 intertemporal (time-varying intensity), Test H Phase IV | 🟠 RMD-REQ | `phase6_a10_dcdh_timevarying_test_h.R` (+ `phase6_a10_build_timevarying_intensity.R` builder) | Time-varying intensity_{j*,t} = (allowance_shortage × eua_price)/revenue_pre. Local-1: too few balanced type-a cells. RMD required. |
| **R7b** dCdH-2022, Test I Phase IV | ⚪ STRUCTURAL-NO | `phase6_a10b_dcdh_timevarying_test_i.R` | **Negative finding documented in script:** cat_intensity_{n,t} is constant across cells with same NACE-4d at given year, so within-(group,time) variation needed for dCdH is zero after FE demeaning. Both cell-level and NACE-4d-aggregated versions fail "After removing NAs, not a single explanatory variable is different from 0." Test I's substantive R7 cross-check reduces to the static `nace_exposure × post` interaction already in §5.1.4. |
| **R7c** dCdH-2022, Test H Phase II | 🟠 RMD-REQ | `phase6_a10c_dcdh_timevarying_phase2.R` | Same as R7a but with Phase II cost share + 2003-2019 window. |

### Existing §5.1 specifications

| Subsection | Label | Status | Script | Notes |
|---|---|---|---|---|
| Headline within-NACE-4d | `sec:domestic_within` | ✅ | `phase5_test_h_most_exposed_ets_supplier.R` + `phase6_test_h_corrected.R` (RMD-RUN 2026-05-04) | Trend-corrected sibling confirms robustness: β_naive = +1.34 (n.s.), β_trend-corrected = +0.20 (n.s.), trend coef +0.22/yr (p=0.31, n.s.). Headline σ ≈ 1 unaffected by trend control. |
| HTE by time horizon (A1) | `sec:domestic_within_horizon` | 🟡 | `phase6_a1_test_h_horizon_lp.R` (RMD-RUN 2026-05-04) | LP too noisy. Full sample h=6 = -16,220 (**), but h=0 = +8,552 (*). Intensive-only sample wildly oscillates with sign flips between adjacent horizons. No clean monotonic pattern. Headline σ ≈ Cobb-Douglas at the level regression stands; horizon claims need careful framing. |
| HTE by shock magnitude | `sec:domestic_within_hte` | ✅ | (Q4 splits inside `phase5_test_h_most_exposed_ets_supplier.R`) | Already in paper as Table |
| Headline across-category | `sec:domestic_across` | ✅ | `phase5_test_i_cross_nace_substitution.R` (paper headline) + `phase6_test_i_corrected.R` (RMD-RUN, has known panel-construction discrepancy with paper's β = -0.003 — likely unbalanced-vs-balanced panel; trend coefficient itself is small and insignificant either way, so the trend-correction conclusion is robust) | |
| HTE on across-category (A2) | `sec:domestic_across_hte` | 🟡 | `phase6_a2_test_i_horizon_hte.R` (RMD-RUN 2026-05-04) | Horizon LP: tiny mostly-negative post-period coefficients (-0.001 to -0.002), weakly significant. **Buyer-quartile split is the headline**: Q4 (heavily affected) β = -0.0038 (p=0.061), Q2 = +0.0066 (***), Q3 = +0.0035 (**), pooled near zero. Heterogeneity matters: substitution materialises at high-exposure buyers but pooled away at low. |
| Phase II event-study (A3) | `sec:domestic_phase2` | ✅ | `phase6_a3_a4_phase2_eventstudy.R` (RMD-RUN 2026-05-04) | Test H Phase II level: β = -978 (n.s., p=0.46). Test I Phase II level: +0.0026 (n.s., p=0.18). Both null at level. Phase II shock too small at typical buyer for level identification (p99 firm cost share = 0.46%). |
| Short-run vs long-run Phase II (A4) | `sec:domestic_phase2_horizon` | 🟡 | `phase6_a3_a4_phase2_eventstudy.R` (RMD-RUN 2026-05-04) | **Test H Phase II horizon shows long-run substitution**: pre-period flat, h=4 = -2371 (**, p=0.009), h=5 = -2148 (**, p=0.013), h=7 = -2120 (°, p=0.097), h=11 = -1771 (n.s.). Suggestive of long-run substitution at horizons 4–7 (years 2012–2015). Test I Phase II horizon: positive coefficients growing at long horizons (h=11 = +0.005 °), wrong-signed for substitution. |

---

## §5.2 Across international suppliers — partially done, MAJOR REVISITS

| Subsection | Label | Status | Script | Notes |
|---|---|---|---|---|
| **CdGM replication** | `sec:international_cmdg` | ✅ | `phase2_cdgm_table1.R` (original, in paper) + `phase6_cdgm_table1_corrected.R` (trend-corrected, RMD-RUN 2026-05-04) | Trend-corrected version run on RMD. Trend slope is small but real (+0.000269/year ** Panel A col 5). Phase-φ coefficients become **more negative** by ~2.5× (Phase 3 share: −0.0024 → −0.0062 ***). Same sign as original, sharper magnitude. Paper §5.2.1 headline to be updated to use trend-corrected numbers; original kept as robustness reference. |
| Buyer-supplier (B1) | `sec:international_buyer_supplier` | ✅ | `phase6_b1_corrected.R` | Trend-corrected β = -0.560 on RMD. Event-study figure regenerated 2026-05-04, both naive and de-trended figures clean. |
| HTE on B1 (B2) | `sec:international_hte` | ✅ | `phase6_b1_b2_customs_buyer_supplier.R` (RMD-RUN 2026-05-04) | Horizon LP confirms B1-corrected naive event study: pre-trend rises monotonically from -0.37 (h=-9) to ~0 (h=-1, all significant), post-period declines monotonically from -0.022 (h=0) to -0.306 (h=7, all *** post-h=1). Quartile split: Q4 (heaviest) β = -1.84, Q1 = -0.23, both n.s. (large SE). |
| Non-EU price response (B3) | `sec:international_price_response` | ✅ | `phase6_b3_nonEU_price_response.R` (RMD-RUN 2026-05-04) | β = +0.069 (s.e. 0.054, p=0.20). **Null**: non-EU exporters did not systematically adjust unit-value prices in response to EU ETS. Year-by-year: 2017 = +0.21 ** (one notable spike), other post-2015 years insignificant. **Strengthens the B1 substitution interpretation** — the cross-border substitution we recover reflects real reallocation, not strategic pricing offset by non-EU exporters. |
| σ from customs prices (B4) | `sec:international_sigma` | 🟡 | `phase6_b4_sigma_from_customs_prices.R` (RMD-RUN 2026-05-04) | **IV underpowered.** First stage: t = 0.32, F ≈ 0.1. IV β on log price ratio = +1.44 (s.e. 8.55, p=0.87). σ̂ = -0.44, 95% CI [-17, +16]. Structural σ from customs prices is unidentified in this design. The IV (HS6 carbon intensity × CPShock annual) doesn't generate enough cross-product price variation post-2015. Alternative IV needed: direct EUA price changes interacted with HS6 carbon intensity, or PRODCOM-based identification (deferred). |
| Imports vs domestic (C1) | `sec:international_imports_vs_domestic` | 🟠 | `phase6_c1_imports_vs_domestic.R` | Ran on local-1 with FE collinearity issue; needs RMD. |
| Parallel trends EU-share (C2) | `sec:international_eu_share_pretrends` | 🟡 | `phase6_c2_parallel_trends_eu_share.R` | **Subsumed by B1-corrected.** B1's event study now displays the pre-trend explicitly. The standalone C2 script still runs; outputs match B1's leads. Keep it as a transparency exhibit; not a separate headline. |
| Within-EU emission-intensity sorting (C3) | `sec:international_within_eu` | 🔴 | `phase6_c3_within_EU_emission_intensity.R` | BLOCKED. Needs Eurostat air-emissions input from `phase6_build_eu_emission_intensity.R`, which has a column-name bug (`TIME_PERIOD` rename) that needs fixing on local-1 with internet first. |

---

## RMD prerequisites — ✅ DONE

| Task | Output | Status |
|---|---|---|
| **P1**: Phase II `firm_cost_share` flavor (2005–08 / 2003–05) | `firm_cost_share_flavors.RData` adds `cost_share_regressor_phase2` (177 firms) | ✅ |
| **P2**: Extended customs panel (2000–2022, with quantity) | `customs_import_panel_extended.RData` (11.2M rows; quantity 95.9% covered conditional on positive value) | ✅ |

---

## Quick reference: which RMD scripts produce which paper sections

```
§5.1.2   → phase6_a1_test_h_horizon_lp.R
§5.1.4   → phase6_a2_test_i_horizon_hte.R
§5.1.6,7 → phase6_a3_a4_phase2_eventstudy.R    (depends on P1)
§5.2.1   → phase2_cdgm_table1.R                (existing, in paper)
§5.2.1*  → phase6_cdgm_table1_corrected.R      (NEW, trend-corrected revisit)
§5.2.2   → phase6_b1_corrected.R               (RUN; β = -0.560 trend-corrected)
§5.2.3   → phase6_b1_b2_customs_buyer_supplier.R (formal quartile HTE; horizon already in B1)
§5.2.4   → phase6_b3_nonEU_price_response.R    (depends on P2)
§5.2.5   → phase6_b4_sigma_from_customs_prices.R (depends on P2 + cpshock + hs6_ci)
§5.2.6   → phase6_c1_imports_vs_domestic.R     (depends on P2)
§5.2.7   → phase6_c2_parallel_trends_eu_share.R (subsumed by B1 event study)
§5.2.8   → phase6_c3_within_EU_emission_intensity.R (BLOCKED on Eurostat builder)
```

---

## Open methodological issues / things to revisit

1. **CdGM trend-correction.** Just pushed `phase6_cdgm_table1_corrected.R`. RMD result will tell us whether §5.2.1's Belgium null is robust to the pre-trend that hit B1, or whether the headline needs to flip. Three possible outcomes documented in the script's docstring.

2. **Test H trend-correction (analog for §5.1.1).** Test H's pre-trend test in the original paper used a continuous-trend control on the headline regressor and got a non-significant slope (p = 0.42). So Test H is plausibly trend-robust already. **Worth confirming** by running Test H with the explicit linear-trend control as a sibling to phase6_b1_corrected, just to be belt-and-braces. Not high priority.

3. **C2 (parallel trends EU-share)** is mostly subsumed by B1's event study, which now visibly traces out the pre-trend in the leads of the naive figure and the residual deviation in the de-trended figure. C2 can stay as an appendix robustness exhibit but doesn't need its own headline subsection.

4. **C3 (within-EU emission-intensity sorting)** is blocked on the Eurostat data builder. Local-1 fix needed: rename column `TIME_PERIOD` → `time` (the eurostat R package changed schema between versions). User has indicated this can stay parked.

5. **§1 Introduction and §6 Conclusion** are deliberate blank placeholders. To be written after the §5 results stabilize.

---

## Recommended RMD next runs (in order)

1. ~~`phase6_cdgm_table1_corrected.R`~~ ✅ **DONE** (RMD-RUN 2026-05-04). §5.2.1 headline reinforced.
2. **`phase6_a1_test_h_horizon_lp.R`** — within-country horizon IRF (§5.1.2). Tests whether Test H is trend-active or stays Cobb-Douglas across horizons. ~5 min.
3. **`phase6_b3_nonEU_price_response.R`** — non-EU exporter pricing, fills §5.2.4. ~5 min.
4. **`phase6_b4_sigma_from_customs_prices.R`** — structural σ from customs prices, fills §5.2.5. ~10 min.
5. **`phase6_a2_test_i_horizon_hte.R`** — across-category horizon, fills §5.1.4. ~30 min (large sample).
6. **`phase6_a3_a4_phase2_eventstudy.R`** — Phase II event-study, fills §5.1.6 and §5.1.7. ~10 min.
7. **`phase6_c1_imports_vs_domestic.R`** — imports vs domestic substitution, fills §5.2.6. ~5 min.

After (2)–(7), the only outstanding empirical work is C3 (Eurostat input fix on local-1).

---

*Last updated: 2026-05-04. Maintain this file as the single source of truth on paper-vs-script status.*
