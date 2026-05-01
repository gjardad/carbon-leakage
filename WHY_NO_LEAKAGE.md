# Why no leakage in Belgian B2B: shock-too-small

This doc consolidates the Plan B (substitution) test battery. It replaces the earlier [STICKINESS_VS_CONCENTRATION.md](STICKINESS_VS_CONCENTRATION.md) — the original "stickiness vs concentration" framing has been superseded by a cleaner verdict.

For the planning context, see [SHOCK_AND_SUBSTITUTION_PLAN.md](SHOCK_AND_SUBSTITUTION_PLAN.md). For the magnitude evidence that anchors the headline, see [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md).

## Verdict

**The leakage null in Belgian B2B is consistent with the carbon shock being too small to motivate substitution at the buyer-total-cost level.** Concentration (no alternatives) is ruled out cleanly. Stickiness (relational frictions) is consistent with the data but is not the load-bearing channel — it is set aside as a paper claim.

The verdict is **directionally well-supported but not tightly estimated** at the regression level — see "Caveats" below. Two pillars hold up the claim:

1. **Magnitude evidence ([SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md))** — pair-shock at the buyer-total-cost level is well below the σ_share noise floor for all sectors except cement, anchored to a real quantitative threshold. This is the load-bearing pillar.
2. **Direct DiD evidence (Test H)** — among the 9% of buyers facing a real substitution decision, the intensive-margin DiD on the share of the most-exposed ETS supplier returns null (β = +1.34, p = 0.16, n = 110,870) and the version restricted to where the NACE 4d is heaviest in the buyer's input bill returns β = +0.03 (SE = 1.39, p = 0.98). This is corroborative, not load-bearing on its own.

Test H's null is consistent with no substitution but does not tightly bound it — see Caveats. The most defensible paper framing is to lean on the magnitude story as primary and present Test H as confirming evidence with the caveats acknowledged.

## Three facts that pin the verdict

### 1. Substitution is feasible for most buyers (concentration is NOT the bottleneck)

`phase5_test_g_followup_substitution_universe`:

| Count | Value | % of all buyers |
|---|---|---|
| NACE 4d sectors with ≥1 ETS firm | 117 / 540 | (22% of sectors) |
| Buyers with ≥2 suppliers in same NACE 4d (treated set) | 214,675 | **70%** |
| Buyers in [2] AND ≥1 ETS supplier | 27,053 | **9%** |
| Total B2B buyers | 307,536 | — |

Yearly stratification is flat — these counts don't trend with the shock window.

The 70% number kills concentration directly. Most buyers have alternative suppliers within an ETS-relevant NACE 4d. The 9% number says ~27K firms — a substantial slice of the Belgian economy — face the substitution decision at all (have ≥1 ETS supplier among multi-supplier NACE 4d cells).

### 2. The 9% of buyers facing the decision do NOT substitute

`phase5_test_h_most_exposed_ets_supplier`. For each (buyer × seller_NACE4d) cell, identify j*(n) = the ETS seller with the highest `firm_cost_share_regressor` (pre-shock 2012-14, time-invariant). Outcome: share of j* in the cell's annual spending. Spec:

```
share_top_{n,t} = β · firm_cost_share_{j*(n)} × Post_t + α_n + δ_{NACE4d_s, t} + ε
```

Two specs:

| Spec | n_cells | n_obs | β | SE | p |
|---|---|---|---|---|---|
| spec_a (j* always active 2005-2022) | 705 | 8,732 | −293 | 135 | **0.030** |
| spec_a_b (a + b restricted to j*'s tenure) | 32,631 | 110,870 | +1.34 | 0.96 | 0.16 |

Specs disagree dramatically. spec_a's significant negative β is on a tiny selected subsample (cells where j* never exited the relationship in 18 years). spec_a_b on the broader 32K-cell sample shows null.

The event study (`phase5_test_h_event_study.csv`, ref year 2014) reveals **a significant pre-trend**: 2010 β = −5.70 (p<0.05), 2011 β = −5.05 (p<0.05). High-fcs j*s were *already* losing share before the 2015 shock. The post-2015 coefficients (−0.5 to −2.0) are smaller in magnitude than the pre-trend coefficients. Parallel trends fail. Spec_a's significance is contaminated by pre-trend, not driven by the shock.

### 3. The "where it should be biggest" test fails

If substitution depends on whether the cost shock is large enough to matter at the buyer's *total* input bill, the right test is to restrict to cells where the NACE 4d is a heavy part of that bill. `phase5_test_h_by_nace_share_split` splits cells by buyer's pre-shock (2010-2014) average spending share on the NACE 4d:

| Subset | n_cells | β | SE | p |
|---|---|---|---|---|
| Q1_lowest | 5,936 | −16.98 | 13.5 | 0.21 |
| Q2 | 5,935 | +1.55 | 1.66 | 0.35 |
| Q3 | 5,936 | +1.98 | 1.52 | 0.19 |
| **Q4_highest** | **5,936** | **+0.03** | **1.39** | **0.98** |
| above_median | 11,872 | +0.75 | 1.02 | 0.47 |
| below_median | 11,871 | +1.46 | 1.32 | 0.27 |

**Q4 — the cells where buyers have the strongest economic incentive to substitute — shows β = +0.03, point-estimate near zero.** 95% CI is roughly [−2.7, +2.8]. At fcs = p99 ≈ 0.05 of the regressor distribution, the lower bound corresponds to a ~13.5 pp share loss; we rule out very large substitution but not modest substitution at the high-fcs tail. The above-median half (Q3+Q4 combined) is similar: β = +0.75, SE 1.02.

Sector decomposition reinforces: cement buyers (NACE 23, the most-shocked sector per [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md)) show β = +4.42 (p=0.17, wrong sign). Chemicals buyers (NACE 20) show β = +2.74 (p=0.06, wrong sign).

Extensive-margin robustness (R2: outcome = 1(j* active in year t)) gives β = −3.61 (p=0.014) — statistically significant but economically tiny: at p90 of fcs (≈ 0.0014), the predicted drop in j*-activity probability is ~0.5 percentage points.

## Why this is a defensible verdict

Two facts pull in the same direction:

- **Pair-shock magnitudes** (per [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md)): population p90 of pair-shock at total-cost level is ~0.23%; cement is 0.27% (signal-to-noise = 0.68σ); everything else is below 0.1σ of buyer's σ_share input-cost noise floor.
- **Substitution test in the most-favorable subset** (Test H Q4): β = +0.03, n.s.

The magnitude story does not require any behavioral / institutional / relational friction — it is anchored to a quantitative threshold (σ_share ≈ 15% pre-shock, vs maximum pair-shock-total ≈ 0.5%). The Test H direct DiD adds confirming evidence on 32K cells of buyers facing real substitution decisions.

## Caveats — Test H is not airtight

The Test H regression evidence has known weaknesses. The current results support the verdict directionally but should not be load-bearing on their own.

### 1. Pre-trend in the event study (parallel trends fail)
`phase5_test_h_event_study.csv`, ref year 2014:

| Year | β |
|---|---|
| 2010 | **−5.70** (p < 0.05) |
| 2011 | **−5.05** (p < 0.05) |
| 2014 | 0 (ref) |
| 2015 | −0.54 (n.s.) |
| 2017 | −1.92 (n.s.) |

High-fcs j*s were already losing share *before* the 2015 shock — the 2010-11 pre-coefficients are significantly negative. The post-2015 coefficients are estimated against a contaminated baseline. The post-shock movement cannot be cleanly attributed to the shock under standard DiD interpretation.

### 2. Extensive margin contradicts the strict null
Test H's R2 (extensive-margin outcome 1(j* active in year t)): β = −3.61 (SE 1.47, **p = 0.014**). j* exits *do* concentrate in high-fcs cells post-2015 — a statistically significant rejection of the strict no-substitution null at the seller-exit margin.

Economic magnitude is small at typical fcs (0.5 pp drop in active probability at p90 fcs ≈ 0.0014), but the result is a real signal. The headline framing of "no substitution" should be qualified to "no observable intensive-margin reweighting; small but detectable extensive-margin seller exits, economically negligible at typical exposure."

### 3. Q4 SE is wider than the headline suggests
β = +0.03 with SE = 1.39 gives 95% CI ≈ [−2.7, +2.8]. At high-fcs cells (p99 fcs ≈ 0.05), the lower bound corresponds to a 13.5 pp share loss — not a tight bound. We rule out *large* substitution effects but not *modest* ones at the high-fcs tail. "Precise zero" was an overstatement in earlier framings of this result.

### 4. Sector decomposition is uninterpretable without winsorization
`phase5_test_h_by_buyer_nace2d.csv` has extreme outliers: NACE 73 β = +3,600; NACE 26 β = −1,906; NACE 22 β = +6,121. These are LPM coefficients dominated by extreme-fcs cells in small sectors. Cannot read sectoral patterns without bounding fcs first.

The cleaner sectors are also unhelpful for the magnitude story:
- **Cement (NACE 23)**: β = +4.42 (p = 0.17). Wrong sign. Cement is the only sector where pair-shock signal-to-noise > 0.5σ, so we'd expect substitution there if anywhere — and it's the wrong sign.
- **Chemicals (NACE 20)**: β = +2.74 (p = 0.06). Wrong sign, marginal.

### 5. fcs distribution is heavy-skewed
The regressor `firm_cost_share_regressor` has p50 ≈ 3.3×10⁻⁵ and p99 ≈ 0.056. Most cells contribute near-zero to the identification of β. The pooled β can hide offsetting effects across the fcs distribution that would only be visible with a more flexible specification (e.g., fcs quantile dummies × Post).

## Anchoring "shock too small" against the carbon-leakage literature

The "shock too small" verdict needs an anchor — what's a big enough shock? Two reference points from papers that *do* find substitution responses:

- **Peter & Ruane (2024, India tariff cuts).** Indian MFN tariffs on intermediate inputs fell by 15-20 percentage points on individual HS products. For an importer where the input is 5% of the bill, that's a 0.75-1.0 percentage point change in *total* input cost — at least 2-4× larger than the population p90 pair-shock-total in our data (1.16% in Phase IV; cement 8.80%). They identify σ ≈ 4-5 from these cuts.
- **Arkolakis, Huneeus & Miyauchi (2025, Chile-US/China FTAs).** Bilateral tariffs fell from ~6-7% to near-zero on most HS lines — a ~6.5pp tariff cut on individual inputs. They observe firms expanding the number of foreign suppliers (extensive margin) and shifting expenditure toward newly-cheaper foreign sources (intensive margin). A 6.5pp tariff cut on a 5%-of-bill input is again ~0.3pp of total cost — comparable to our Phase IV cement signal but 30-50× larger than our population pair-shock-total.

For a typical Belgian buyer, EU ETS at 2018-2020 prices (€25-30/tCO₂) translates to a 0.06-0.1pp change in total input cost per ETS supplier of typical emissions intensity. **One to two orders of magnitude smaller than the smallest shocks where the literature has identified substitution.** This is the anchor that makes "too small" quantitative rather than asserted.

A back-of-the-envelope extrapolation: at ~€100/tCO₂ (4× the 2005-2020 average), the typical buyer's pair-shock-total would still be ~0.3-0.4pp — comparable to AHM's per-input shock magnitude and approaching P&R's. Whether that's enough for substitution depends on the ratio of pair-shock-total to buyer-side input-cost noise (σ_share). At cement-buyer σ_share ≈ 13% and a hypothetical Phase IV signal scaled 4× to 35%, signal-to-noise rises from 0.68σ to ~2.7σ — clearly above detection threshold. For non-cement sectors with σ_share ≈ 15% and current p90 < 0.5%, even 4× scaling lifts signal-to-noise only to ~0.13σ. **The "$X would be different" claim is plausible for cement and basically nowhere else.**

## Upgrades implemented (April 2026)

[analysis/phase5_test_h_upgrades.R](analysis/phase5_test_h_upgrades.R) implements three tightening upgrades to Test H without retiring the original spec. Outputs go to `output_<machine>/tables/` and `output_<machine>/figures/`.

### Upgrade #1 — Detrending the 2010-11 pre-trend
The event study (ref 2014) shows β_2010 = -5.70 and β_2011 = -5.05 for the seller-side regressor `fcs_{j*}`. We add `fcs_{j*} × year_c` as a continuous control alongside the Post interaction. β is then identified from the *deviation* of post-2015 coefficients from the 2005-2014 linear drift. Output: `phase5_test_h_upgrades_main_up1.csv` (pooled DiD), `phase5_test_h_upgrades_event_study_detrended_fcs.{csv,pdf}` (year-by-year, detrended).

### Upgrade #4 — Pair-exposure-anchored regressor
Replace the seller-side `fcs_{j*}` with a buyer-side magnitude:
```
pair_exposure_pre_{n} = fcs_{j*(n)} × s_{j*(n)}_pre
s_{j*(n)}_pre        = mean_{2010..2014}[ corr_sales_{j*, b, t} / inputs_VAT_{b, t} ]
```
Units: % of buyer b's *total* input cost that would be at risk if j*'s carbon shock pass-through is full and b doesn't substitute. Same units as Moment 4(c) `pair_shock_total` from [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md), but time-invariant per cell.

Quartile split by `pair_exposure_pre` is the economically-meaningful version of the existing `nace_share_pre` split — the latter splits on how much of the buyer's bill is in the seller's NACE 4d, which is a necessary but not sufficient condition for the carbon shock to bite hard. `pair_exposure_pre` directly measures the shock magnitude that would hit the buyer through j*. Output: `phase5_test_h_upgrades_main_up4.csv`, `phase5_test_h_upgrades_pair_exposure_split.csv`, `phase5_test_h_upgrades_event_study_detrended_pe.{csv,pdf}`.

### Upgrade #5 — Cement-specific clean test
Restrict to buyer NACE 2d == "23" (cement / non-metallic minerals — the only sector where pair-shock signal-to-noise exceeds 0.5σ per [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md)) and apply both #1 (detrending) and #4 (pair-exposure regressor), with the regressor winsorized at its cement-subsample p99 to bound LPM coefficients on the heavy-tailed distribution. The current cement coefficient in the original Test H is β = +4.42 (p=0.17, wrong sign); this version asks whether that flips or sharpens once trend and outliers are handled. Output: `phase5_test_h_upgrades_cement.csv`, `phase5_test_h_upgrades_cement_event_study.{csv,pdf}`.

### How to read the output
- **β on pair_exposure × Post (detrended), pooled.** If still ≈ 0 with a tighter SE, the magnitude verdict tightens — the most economically-meaningful regressor finds no substitution where the shock could actually bite.
- **β by quartile of pair_exposure_pre.** If the Q4 coefficient is large and negative while Q1-Q3 are zero, that's a Huneeus-style kink and the "$X would generate substitution" narrative gains support. If the gradient stays flat across quartiles (the result we got with `nace_share_pre`), the kink-based version of the narrative is dead.
- **Cement detrended event study.** If post-2017 coefficients drift down and pre-2014 coefficients are flat, cement substitution is real and we have a sector-anchored result (the headline becomes "cement substitutes; nothing else does"). If both pre and post stay flat, even the most-powered test fails to find substitution and the magnitude story stands alone.

## Other possible upgrades (not implemented)

1. **Triple-difference using a synthetic placebo j*.** Construct `share_top - cell_mean_non_ETS_share` to absorb cell-level common trends. Detrending (#1 above) is the lighter-weight version and was implemented first.
2. **Reconcile R2 and headline.** The extensive-margin R2 (β = -3.61, p = 0.014) is small but significant. Either reframe the headline as "no intensive-margin reweighting; small but detectable extensive-margin exits, economically negligible at typical exposure" or run a follow-up that bounds the exit channel directly.
3. **Quantile-flexible spec.** Replace `pair_exposure_pre × Post` with `(pe_quartile dummies) × Post` to see whether a pooled β ≈ 0 hides offsetting effects across the distribution. Adds one column to the existing `pair_exposure_split.csv`.
4. **Refresh the pair-exposure window.** The current pre-shock window is 2010-2014. If MSR-binding (Phase IV, post-2018) is the relevant treatment date, the cleaner pre-window is 2013-2016. Cheap to swap.

## Parked (not in paper)

The following Plan B results are noted for completeness but not used. The paper does not need a stickiness narrative; the magnitude story is sufficient.

### Test C — Heise life-cycle moments
Belgian B2B exhibits Heise (2024 AER) relational dynamics:
- Pairs older than 5 years are 18% of pairs but **79% of trade** (full RMD universe; non-left-censored).
- Within total-duration cohorts, mean log(corr_sales) rises monotonically with pair age (no terminal-year hump).
- Break-up hazard: 46% at age 0 → 19% at age 5 → 14% at age 18.

Verdict: Heise-style life-cycle is present, but not load-bearing for the leakage null. Not used.

### Test A — new-pair carbon-intensity tilt (n=544,592)
- A2 rank, p_p2 (post-2017): β = −4.7×10⁻⁴, p = 0.065. Right sign, marginally significant, **economically tiny** (~0.05 percentile points).
- A1 R3 (with buyer-NACE2d × year FE): β = −0.39, p = 0.93. Marginal tilt is buyer-side timing, not seller-side selection.
- Stock-vs-flow gap widens post-2017 (flow-mean is ~26-52% of stock-mean during 2017-2022, vs ~57-100% pre-2013). Heise stock-vs-flow signature visible, magnitudes small.

Verdict: marginal at best, not used.

### Test B — survival hazard by intensity × pair-age (winsorized; n=7.42M)
- intensity_only: treat_1_3 = +6.89 (p=0.35), treat_4_7 = −2.52 (p=0.64), treat_8plus = +2.33 (p=0.39).
- Sign pattern (young pair coefficient positive) right for stickiness; pooled magnitudes statistically null.

Verdict: pooled null, not used.

### Test G — feasibility-restricted substitution test
- Filter (n_ets ≥ 2, spread ≥ 0.005, max_pair_shock_total ≥ 0.005): 1 cell at default thresholds, max 29 cells across the (θ_spread, θ_shock_total) grid even on the full 112M-row B2B universe.
- The empty filter is itself a finding — the *intersection* of "feasibility AND material exposure" is structurally rare. But Test H subsumes its substantive question with a much larger sample.

Verdict: superseded by Test H. Not used.

### Phase-3-universe pair persistence (incidental)
Of ~680K distinct pairs in the regulated-intensive buyer + core-input-pair universe, only 5,327 had a formation year observable in 2003-2022 — i.e., **~99% of Phase-3-universe pairs are left-censored at 2002.** Striking persistence fact for the regulated supply network. Not used.

## Files of record

Outputs from the most recent RMD run, under `output_rmd/tables/`:

- `phase5_test_g_followup_substitution_universe.csv` — the 117 / 70% / 9% / 3% counts.
- `phase5_test_h_main.csv` — spec_a and spec_a_b coefficients.
- `phase5_test_h_robustness.csv` — R1 (+buyer-NACE2d × year FE) and R2 (extensive margin).
- `phase5_test_h_event_study.csv` — year-by-year coefficients showing the pre-trend.
- `phase5_test_h_by_nace_share_split.csv` — quartile split with the Q4 = 0.03 result.
- `phase5_test_h_by_buyer_nace2d.csv` — sector decomposition.

Tests A, B, C, G outputs in the same folder are parked.
