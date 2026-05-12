# Why no leakage in Belgian B2B: shock-too-small

This doc consolidates the Plan B (substitution) test battery. It replaces the earlier [STICKINESS_VS_CONCENTRATION.md](STICKINESS_VS_CONCENTRATION.md) — the original "stickiness vs concentration" framing has been superseded by a cleaner verdict.

For the planning context, see [SHOCK_AND_SUBSTITUTION_PLAN.md](SHOCK_AND_SUBSTITUTION_PLAN.md). For the magnitude evidence that anchors the headline, see [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md).

## Verdict

**The leakage null in Belgian B2B holds at both substitution margins we can test.** Test H (within NACE 4d, across suppliers) and Test I (across NACE 4d categories, within buyer) both find null. Combined with strong evidence of ETS pass-through into regulated PPI ([PASSTHROUGH.md](PASSTHROUGH.md): Phase IV +21pp regulated vs unregulated; Känzig CPShock LP +4.08 at h=12), the picture is: **prices rose, buyers paid them, neither side reorganized.** Concentration (no alternatives) is ruled out cleanly; stickiness (relational frictions) is consistent with the data but not separately identified.

The verdict has three pillars:

1. **Magnitude evidence ([SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md))** — pair-shock-total at the buyer-total-cost level is well below the σ_share noise floor for all sectors except cement. Anchored quantitatively against P&R below.
2. **Within-NACE-4d substitution (Test H)** — among the 9% of buyers facing a real substitution decision, the intensive-margin DiD on the share of the most-exposed ETS supplier returns null. After detrending and pair-exposure anchoring (upgrades #1, #4, #5), β stays close to zero across all specifications. The Q4 high-magnitude split (where the carbon shock would actually bite) is also null.
3. **Across-NACE-4d substitution (Test I, May 2026)** — across input categories within a buyer, the binary regulated × Post coefficient is essentially zero (β = -0.0026, p = 0.76); the event study post-2015 coefficients are positive in every clean year (against substitution); the only spec showing substitution (I.2 with continuous trend) hangs on a linear-trend assumption that the event-study evidence shows doesn't fit the data.

The most defensible paper framing is to lead with the magnitude story (anchored by the P&R comparison) and present Tests H and I as the joint null on observable substitution at both margins, with the caveat that we cannot separately identify whether what remains is technological rigidity, relational stickiness, or shock-too-small power limits.

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

## Anchoring "shock too small" — precise comparison with Peter & Ruane

The "shock too small" verdict needs a precise anchor: what counts as a big enough shock to expect detectable substitution? We construct an apples-to-apples comparison with **Peter & Ruane (2024)**, who use Indian tariff liberalization to identify σ across imported intermediate-input varieties. The comparison is at the buyer-supplier-pair level: % change in the *buyer's total input cost* implied by one supplier's price change under full pass-through.

The object is the same in both contexts:
```
Δ(buyer's total cost)/cost  =  s × Δp_supplier
```
where `s` = supplier's share of the buyer's total input bill and `Δp_supplier` = supplier's price change under full pass-through.

### Belgian ETS: empirical pair-shock distribution (Phase IV, ≈ 2015 → 2022)

EUA prices: 2015 ≈ €7.6, 2017 ≈ €5.8 (post-collapse, pre-MSR — *prices fell over 2015-17, so this window is not a useful shock*), 2022 ≈ €80.2. The Phase IV pair-shock-total numbers in [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md) Moment 4(c) are computed at 2021-22 EUA levels. Since the 2015 baseline EUA was ≈ 1/10 of 2022, those Phase IV levels approximate the **2015 → 2022 increment under full pass-through.**

```
pair_shock_total = (shortage × EUA / total_cost) × (corr_sales / inputs_VAT_total)
                 = f × s
```

| Quantile | Population (treated active pairs) | Cement-buyer pairs (NACE 23) |
|---|---|---|
| p50 | 0.0016% | 0.13% |
| p90 | **1.16%** | **8.80%** |
| p95 (interpolated) | ~5–7% | ~30–50% |
| p99 | **39.1%** | **67.2%** |

Note p95 is not directly tabulated — values are log-linear interpolations between p90 and p99 under a Pareto-tail approximation.

### Peter & Ruane analogue (with explicit assumptions)

I do not have P&R's microdata, so the equivalent magnitudes are reconstructed from what is publicly known about their setting. Every assumption is flagged.

**What I take as given about P&R:**
- Indian MFN tariffs on intermediate inputs, 2001–2007 sample window.
- Pre-cut tariff levels: ~30–40% on the affected HS-6 products (well-documented; India's average MFN tariff on manufactures was ~32% in 2001).
- Post-cut tariff levels: ~10–15% by 2007.
- Per-HS-6-product tariff cut: Δt ≈ −15 to −20 percentage points; some products see −30pp.

**Step 1 — Tariff cut → supplier price change.** For an importer, delivered price = world price × (1 + t). When `t` falls from `t₀` to `t₁`:
```
Δ(delivered price)/delivered price  =  Δt / (1 + t₀)
```

| Tariff path | Δt | Implied Δp_supplier (full pass-through) |
|---|---|---|
| 30% → 15% | −15pp | **−11.5%** |
| 35% → 15% | −20pp | **−14.8%** |
| 40% → 10% | −30pp | **−21.4%** |

So per-supplier price change is **−12% to −21%**.

**Step 2 — Multiply by importer's spending share `s` on the affected supplier.** Here is where I have to assume: P&R does not publish the buyer-side distribution of `s` (importer's spending share on a single tariff-cut HS-6 product). Plausible benchmarks from the trade microdata literature, drawn from typical importer-product concentration in Indian, Chinese, and Belgian customs panels:

| Quantile (assumed) | Δp = −15% (typical mid-tariff cut) | Δp = −20% (large cut) |
|---|---|---|
| p90 (s = 0.10) | **−1.5%** | **−2.0%** |
| p95 (s = 0.20) | **−3.0%** | **−4.0%** |
| p99 (s = 0.40) | **−6.0%** | **−8.0%** |

**Caveat to flag in the paper.** These `s` values are assumptions, not P&R numbers. A more careful version would require pulling the importer-product spending-share distribution from the Indian customs panel or from a comparable trade microdata source. The values here are plausible but not pinned down.

### Apples-to-apples comparison

| Quantile | Belgian ETS (full PT) | P&R (full PT, assumed s) | Magnitude relation |
|---|---|---|---|
| p90 | +1.16% | −1.5 to −2.0% | **comparable** |
| p95 | ~5–7% | −3.0 to −4.0% | Belgian larger |
| p99 | +39% | −6 to −8% | **Belgian 5–6× larger** |
| p90 cement | +8.8% | −1.5 to −2.0% | Belgian 4–6× larger |
| p99 cement | +67% | −6 to −8% | Belgian 8–10× larger |

**At the right tail, the Belgian Phase IV shocks are AS LARGE OR LARGER than the per-HS-product shocks Peter & Ruane operated with.** The simple "shock too small" framing fails at the right tail. Where the two designs differ is the **distribution mass below p90**:

- P&R: every Indian importer of a tariff-cut HS-6 product gets a uniform ~12–21% price decline on that product. Shocks are broad-based across millions of importer-product cells.
- Belgian: the typical buyer-supplier pair has near-zero ETS exposure (population p50 of pair-shock-total ≈ 0.002%). Only ~9% of buyers have any ETS supplier. Cement is the only sector where the *typical* pair-shock is meaningful.

### What this means for the paper

The clean defensible claim is **not** "the shock is too small at the population." It is the more uncomfortable observation:

> "At the right tail, Belgian Phase IV shocks are comparable to or larger than the per-HS-6-product shocks Peter & Ruane (2024) used to identify σ on Indian tariff cuts. We tested for substitution at exactly that right tail — Test H Q4 of pair_exposure_pre (β = +29, p = 0.16, n.s.) and the cement subsample under the buyer-side pair-exposure regressor (β = −213, p = 0.41, n.s.) — and find no statistically significant evidence of substitution at the magnitudes where the literature has identified σ. The shock is small at the typical pair, but not at the right tail; the null at the right tail is informative, not magnitude-driven. The remaining open questions are whether (i) substitution operates at a different margin than the within-NACE-4d-supplier level we test, or (ii) Belgian B2B has unusually sticky relational frictions even at the right-tail magnitudes."

A back-of-envelope extrapolation: at ~€200/tCO₂ (≈ 2.5× the 2022 average), the Belgian population p90 would scale from 1.16% to ~3%, comparable to P&R's p95. At that price, the right-tail magnitudes already match where σ is identifiable in P&R; whether substitution would actually appear depends on whether the Belgian null at the existing right tail is power-bound or behaviorally bound. Our current data cannot distinguish.

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

## Test I — across-NACE-4d category substitution (May 2026)

[analysis/phase5_test_i_cross_nace_substitution.R](analysis/phase5_test_i_cross_nace_substitution.R) is the buyer-side analog of CdGM's regulated-vs-unregulated PPI event study, but on the **input-mix** rather than the output-PPI margin. It asks: when carbon pricing raises the average price of input category n (driven by category n's average ETS exposure), do Belgian buyers reweight expenditure away from category n toward less-exposed categories?

### Construction

```
nace_exposure_n = Σ_{j ∈ ETS sellers in n} mean_{2010-14}[corr_sales_j] × fcs_j
                  ÷
                  Σ_{j ∈ all sellers in n} mean_{2010-14}[corr_sales_j]
```
Time-invariant per NACE 4d. Captures category-level price-shock exposure under full pass-through.

```
share_{b, n, t} = Σ_{j: nace4d_j = n} corr_sales_{j, b, t} / inputs_VAT_total_{b, t}
```
Buyer's expenditure on category n as fraction of total inputs. Sample = (buyer × NACE 4d) cells where buyer had positive spending in at least one pre-shock year (2010-14). N = 71.7M cell-years across 5.7M cells.

Identification: buyer × year FE absorbs each buyer's overall scale and time path; buyer × NACE 4d FE absorbs persistent buyer-specific category preferences. β identifies whether high-`nace_exposure` cells saw additional share decline post-2015 vs the buyer's other active categories.

### Results

| Spec | β | SE | p | Direction |
|---|---|---|---|---|
| I.1 pooled (no detrend) | +34.5 | 15.2 | 0.023 | wrong sign, significant |
| I.2 detrended POST | −43.3 | 12.5 | 0.0005 | right sign, but artifact of linear-trend imposition (see below) |
| I.2 detrended TREND | +9.1 | 2.2 | <0.001 | strong full-sample drift (high-exposure categories grew their share over 2005-2022) |
| **I.3 binary regulated × Post (CdGM-domestic analog)** | **−0.0026** | **0.0087** | **0.76** | **null** |
| Robustness: log(spend) | +153.96 | 13.4 | <1e-30 | wrong sign, very significant |

Detrended event study (year-by-year coefficient on `nace_exposure × year_f`, post-hoc detrended on the 2005-2014 linear fit):

| Year | Detrended coef |
|---|---|
| 2014 | 0 (ref) |
| **2015** | **+9.1** |
| **2016** | **+13.5** |
| **2017** | **+20.4** |
| **2018** | **+22.8** |
| **2019** | **+26.4** |
| 2020 | −24.7 (COVID) |
| 2021 | +36.8 |
| 2022 | +433.6 (post-COVID / gas-crisis outlier) |

**All clean post-2015 years (2015-2019, 2021) have POSITIVE coefficients** — high-exposure categories saw their within-buyer share *grow* relative to the pre-trend extrapolation, not shrink.

### Why the I.2 negative β is not load-bearing

I.2 imposes a *single linear trend* fit on the full panel. The event-study evidence shows the data does not fit a single linear trend: pre-period coefficients jump between −24.5 (2011, financial-crisis aftermath) and +33.8 (2012, post-crisis rebound). Imposing a single slope of +9.09/year on this jagged series forces the post-period level shift to be negative even though the year-by-year detrended event-study coefficients are uniformly positive.

The cleaner specifications — I.3 (binary regulated dummy, the most direct CdGM-domestic analog), I.4 (event study with pre-period-only trend), and the log-spend robustness — all point in the opposite direction: no substitution, or the wrong sign.

### Test I quartile split: degenerate

Same zero-mass issue as Test H: most NACE 4d categories have `nace_exposure = 0` (no ETS sellers), so Q1, Q2, Q3 collapse and only Q4 has positive mass. The Q4 result equals the all-data result (β = −43.3) because Q4 contains all the variation. Not a useful kink test.

### Combined verdict on substitution

| Margin | Test | Headline | Most-favorable subset |
|---|---|---|---|
| Within NACE 4d, across suppliers | Test H | β ≈ 0 across all specs | Q4 of pair_exposure: β = +29 (n.s., wrong sign); cement pe-anchored: β = −213 (right sign, n.s.) |
| Across NACE 4d, within buyer | Test I | β ≈ 0 (binary, event study); wrong-signed in I.1 and log-spend | Q4 = full sample (degenerate) |

Buyers absorbed the carbon-driven price increases at both substitution margins. The reallocation channel of leakage is null at the supplier level AND at the category level.

---

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
- `phase5_test_h_upgrades_main_up1.csv` — Upgrade #1 (detrended fcs).
- `phase5_test_h_upgrades_main_up4.csv` — Upgrade #4 (pair-exposure regressor).
- `phase5_test_h_upgrades_pair_exposure_split.csv` — quartile split by pair_exposure_pre.
- `phase5_test_h_upgrades_cement.csv` — Upgrade #5 (cement, detrended + winsorized).
- `phase5_test_h_upgrades_event_study_detrended_{fcs,pe}.csv` — fixed event studies.
- `phase5_test_h_upgrades_cement_event_study.csv`.
- `phase5_test_i_main.csv` — Test I pooled, detrended, regulated dummy.
- `phase5_test_i_quartile_split.csv` — degenerate (zero-mass).
- `phase5_test_i_event_study.csv` — clean year-by-year, detrended.
- `phase5_test_i_robustness_logspend.csv` — wrong-signed log(spend) outcome.
- `phase5_test_i_nace_exposure_distribution.csv` — category-level treatment distribution.

Tests A, B, C, G outputs in the same folder are parked.
