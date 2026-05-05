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
| CMdG event-study (Strategy 2) | ✅ | `phase1_ppi_passthrough_cmdj.R` |
| OLS with sector trends (Strategy 3) | ✅ | `phase3_ppi_passthrough.R` (OLS branch) |

---

## §5.1 Across domestic suppliers — partially done

| Subsection | Label | Status | Script | Notes |
|---|---|---|---|---|
| Headline within-NACE-4d | `sec:domestic_within` | 🟡 | `phase5_test_h_most_exposed_ets_supplier.R` + upgrades | Done but should re-run with linear-trend control (analog of B1 fix). Test H's pre-trend was previously tested and was insignificant — but worth rechecking after the B1 finding. |
| HTE by time horizon (A1) | `sec:domestic_within_horizon` | 🟠 | `phase6_a1_test_h_horizon_lp.R` | Ready, not run on RMD |
| HTE by shock magnitude | `sec:domestic_within_hte` | ✅ | (Q4 splits inside `phase5_test_h_most_exposed_ets_supplier.R`) | Already in paper as Table |
| Headline across-category | `sec:domestic_across` | ✅ | `phase5_test_i_cross_nace_substitution.R` | |
| HTE on across-category (A2) | `sec:domestic_across_hte` | 🟠 | `phase6_a2_test_i_horizon_hte.R` | Ready, not run on RMD |
| Phase II event-study (A3) | `sec:domestic_phase2` | 🟠 | `phase6_a3_a4_phase2_eventstudy.R` | Ready; P1 dependency done. |
| Short-run vs long-run Phase II (A4) | `sec:domestic_phase2_horizon` | 🟠 | `phase6_a3_a4_phase2_eventstudy.R` | Same script as A3 |

---

## §5.2 Across international suppliers — partially done, MAJOR REVISITS

| Subsection | Label | Status | Script | Notes |
|---|---|---|---|---|
| **CMdG replication** | `sec:international_cmdg` | ✅ | `phase2_cmdj_table1.R` (original, in paper) + `phase6_cmdj_table1_corrected.R` (trend-corrected, RMD-RUN 2026-05-04) | Trend-corrected version run on RMD. Trend slope is small but real (+0.000269/year ** Panel A col 5). Phase-φ coefficients become **more negative** by ~2.5× (Phase 3 share: −0.0024 → −0.0062 ***). Same sign as original, sharper magnitude. Paper §5.2.1 headline to be updated to use trend-corrected numbers; original kept as robustness reference. |
| Buyer-supplier (B1) | `sec:international_buyer_supplier` | ✅ | `phase6_b1_corrected.R` | Trend-corrected β = -0.560 on RMD. Event-study figure regenerated 2026-05-04, both naive and de-trended figures clean. |
| HTE on B1 (B2) | `sec:international_hte` | 🟡 PARTIALLY | `phase6_b1_b2_customs_buyer_supplier.R` | Horizon evidence already produced via the B1 event study (long-run β = -0.89 at h=7). The **separate quartile-split HTE** still needs RMD execution. |
| Non-EU price response (B3) | `sec:international_price_response` | 🟠 | `phase6_b3_nonEU_price_response.R` | UNBLOCKED now that P2 is done (extended panel preserves quantity). |
| σ from customs prices (B4) | `sec:international_sigma` | 🟠 | `phase6_b4_sigma_from_customs_prices.R` | UNBLOCKED. Inputs: P2 + `cpshock_annual.RData` (in repo) + `hs6_carbon_intensity.csv` (in repo). |
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
§5.2.1   → phase2_cmdj_table1.R                (existing, in paper)
§5.2.1*  → phase6_cmdj_table1_corrected.R      (NEW, trend-corrected revisit)
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

1. **CMdG trend-correction.** Just pushed `phase6_cmdj_table1_corrected.R`. RMD result will tell us whether §5.2.1's Belgium null is robust to the pre-trend that hit B1, or whether the headline needs to flip. Three possible outcomes documented in the script's docstring.

2. **Test H trend-correction (analog for §5.1.1).** Test H's pre-trend test in the original paper used a continuous-trend control on the headline regressor and got a non-significant slope (p = 0.42). So Test H is plausibly trend-robust already. **Worth confirming** by running Test H with the explicit linear-trend control as a sibling to phase6_b1_corrected, just to be belt-and-braces. Not high priority.

3. **C2 (parallel trends EU-share)** is mostly subsumed by B1's event study, which now visibly traces out the pre-trend in the leads of the naive figure and the residual deviation in the de-trended figure. C2 can stay as an appendix robustness exhibit but doesn't need its own headline subsection.

4. **C3 (within-EU emission-intensity sorting)** is blocked on the Eurostat data builder. Local-1 fix needed: rename column `TIME_PERIOD` → `time` (the eurostat R package changed schema between versions). User has indicated this can stay parked.

5. **§1 Introduction and §6 Conclusion** are deliberate blank placeholders. To be written after the §5 results stabilize.

---

## Recommended RMD next runs (in order)

1. ~~`phase6_cmdj_table1_corrected.R`~~ ✅ **DONE** (RMD-RUN 2026-05-04). §5.2.1 headline reinforced.
2. **`phase6_a1_test_h_horizon_lp.R`** — within-country horizon IRF (§5.1.2). Tests whether Test H is trend-active or stays Cobb-Douglas across horizons. ~5 min.
3. **`phase6_b3_nonEU_price_response.R`** — non-EU exporter pricing, fills §5.2.4. ~5 min.
4. **`phase6_b4_sigma_from_customs_prices.R`** — structural σ from customs prices, fills §5.2.5. ~10 min.
5. **`phase6_a2_test_i_horizon_hte.R`** — across-category horizon, fills §5.1.4. ~30 min (large sample).
6. **`phase6_a3_a4_phase2_eventstudy.R`** — Phase II event-study, fills §5.1.6 and §5.1.7. ~10 min.
7. **`phase6_c1_imports_vs_domestic.R`** — imports vs domestic substitution, fills §5.2.6. ~5 min.

After (2)–(7), the only outstanding empirical work is C3 (Eurostat input fix on local-1).

---

*Last updated: 2026-05-04. Maintain this file as the single source of truth on paper-vs-script status.*
