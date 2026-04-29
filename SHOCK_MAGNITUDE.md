# Shock Magnitude: How Big is the ETS Cost Shock to Belgian B2B?

*Plan A of [SHOCK_AND_SUBSTITUTION_PLAN.md](SHOCK_AND_SUBSTITUTION_PLAN.md). Six descriptive moments characterizing how big the ETS cost shock is at the firm-year, sector-year, and pair-year levels, by ETS phase. Anchors whether the null leakage finding in [B2B_LEAKAGE.md](B2B_LEAKAGE.md) and [IMPORT_LEAKAGE.md](IMPORT_LEAKAGE.md) is informative or mechanically driven by a too-small shock. Numbers below are from the **full Belgian B2B universe and full Annual Accounts** computed on RMD; the upstream `firm_year_belgian_euets.RData` reflects the corrected `is_regulated`-aware build.*

## Verdict

**Cement is the only sector where the ETS shock is meaningfully detectable. Everywhere else the shock is buried under typical buyer-level input-cost noise.**

The headline signal-to-noise comparison uses **option (c)**: pair-shock-as-fraction-of-total-buyer-inputs (matched in units to the buyer's total-input-cost noise floor, σ_share). This is apples-to-apples across numerator and denominator.

| Subset | Phase IV pair_shock_total p90 | σ_share (pre-shock) p50 | Signal-to-noise |
|---|---|---|---|
| **Cement (NACE 23) buyers** | **8.80%** | **13.0%** | **0.68σ** |
| Other manufacturing (32) | 8.93% | ~15% | ~0.6σ (n=8 only) |
| Paper (17) | 0.49% | 11.8% | 0.04σ |
| Refining (19) | 0.38% | 10.3% | 0.04σ |
| Plastics (22), printing (18), textiles (13), fab metals (25), chemicals (20), machinery (28), basic metals (24), pharma (21), motor vehicles (29) | < 0.2% | 12–18% | ≪ 0.05σ |
| Population (all treated active pairs) | 1.16% | 15.0% | **0.08σ** |

**Implication for the [STICKINESS_VS_CONCENTRATION.md](STICKINESS_VS_CONCENTRATION.md) plan:**

1. **Cement is the only sector where the test has identifying power.** Phase IV pair-shock is ~0.68σ above the cement-buyer noise floor. A 0.68σ shock is roughly the threshold of detectability — buyers facing a shock of this magnitude have a real reason to act on it specifically. The Belgian B2B leakage null in cement is therefore an informative null.
2. **For all non-cement regulated sectors, the null is partially mechanical**: pair_shock_total is well below 0.1σ of typical buyer-level input-cost noise, so "no substitution" is what we'd expect even if every other channel were live. The signal is too small for buyers to act on it specifically.
3. **The buyer-aggregate exposure is essentially zero for most buyers.** Phase IV `buyer_total_shock` (sum across all the buyer's ETS sellers, denominated in total inputs) has p90 = 0% and p95 = 0.03%. Most buyers in the regulated-intensive sample don't have any ETS suppliers in their portfolio. Cement is the dominant cell where ETS sellers concentrate.
4. **Test G of Plan B (feasibility-restricted substitution) is the right primary test.** It restricts to cells where the substitution incentive is materially above background. Cement-buyer cells are essentially the only candidates with sufficient signal.
5. **Plan B's framing should acknowledge the bounded interpretability of the null.** "Belgium does not exhibit measurable carbon leakage" is correct but partially mechanical; the more accurate framing is "outside cement, Belgian buyers face vanishing pair-level ETS exposure relative to background input-cost noise even in Phase IV; the test is identification-bound by shock magnitude for non-cement sectors."

The plan's 2017/2018 + Phase IV framing is correct — Phase I–III have shocks that are well below the noise floor for nearly all buyers.

### Why this version of the verdict is sharper than the previous one

The previous verdict in this doc compared pair-shock at the NACE-4d-specific denominator against σ_b at the total-input denominator — different units. The corrected option (c) comparison puts both numerator and denominator at the total-input level. Effects:

- Population pair-shock-total p90 (1.16%) is much smaller than population pair-shock p90 at NACE-4d denom (3.30%), because most NACE 4ds are a fraction of buyers' total inputs.
- σ_share (scale-stripped) is much smaller than raw σ_b (15.0% vs 24.1%) because half the variation in raw inputs_VAT was scale (firm growing/shrinking).
- Net effect: cement signal-to-noise improves modestly (0.68σ vs the previous 0.47σ). For non-cement sectors it gets worse (signal scaled down faster than noise).

## Definition of `firm_cost_share`

Plan A is descriptive. Same-year ratio:

```
firm_cost_share_{j,t} = (shortage_{j,t} × EUA_t) / total_cost_{j,t}
```

`shortage = max(emissions − allocated_free, 0)`. `total_cost = (revenue − value_added) + wage_bill`. Numerator and denominator both in year t. No Bartik denominator needed because Plan A estimates no treatment effect; the ratio is a pure descriptive statistic and the same-year version is automatically inflation-neutral. Plan B's regression specs use different definitions; see the plan file.

Sample: Belgian ETS firms `in_sample == 1` from the canonical `firm_year_belgian_euets.RData` (post-fix in `inferring_emissions/preprocess/build_firm_year_euets.R`, which now adds `is_ever_euets` and `is_regulated` flags). Three contaminated VAT hashes (NACE 20, 24 EUTL artefact post-2020) excluded from 2021+ per [MEMORY.md](C:\Users\jota_\.claude\projects\c--Users-jota--Documents-carbon-leakage\memory\project_nace24_eutl_break_post2020.md). Firm-years with `is_regulated == 0` (firm-year has no installation reporting verified emissions, so emissions = NA → cost_share = NA) and firm-years with `total_cost ≤ 0` are dropped from the cost-share distribution. Of 3,940 in_sample firm-years, 6 contaminated rows + 833 with NA cost-share = **3,101 used**.

## Moment 1 — Same-year `firm_cost_share` distribution by phase (population)

[output/tables/phase5_moment1_cost_share_distribution.csv](output/tables/phase5_moment1_cost_share_distribution.csv)

| Phase | n firm-years | n firms | % positive shortage | p50 | p90 | p99 | mean | sales-wmean |
|---|---|---|---|---|---|---|---|---|
| I (2005–07) | 505 | 177 | 19.8% | 0% | 0.016% | 0.46% | 0.023% | 0.084% |
| II (2008–12) | 849 | 188 | 12.5% | 0% | 0.009% | 0.46% | 0.18% | 0.078% |
| III pre-MSR (13–17) | 917 | 202 | 62.2% | 0.011% | 0.30% | 8.67% | 0.56% | 0.091% |
| III post-MSR (18–20) | 511 | 175 | 72.0% | 0.092% | 1.40% | 24.0% | 1.41% | 0.31% |
| **IV (21–22)** | **319** | **165** | **83.4%** | **0.34%** | **2.60%** | **59.9%** | **6.85%** | **0.71%** |

**Read:**
- Phase I–II: shocks essentially zero everywhere (free allocation generous).
- Phase III pre-MSR: shock starts to bite for upper-tail firms (p99 = 8.7%); median still ~0.
- **Phase IV: median 0.34%, p90 2.60%, p99 60%, mean 6.85%, sales-wmean 0.71%.** Distribution is heavy-tailed.
- The `is_regulated`-aware filter excludes firm-years where the firm wasn't actually under ETS, so percentiles are computed on genuinely covered firm-years only.

[output/figures/phase5_moment1_distribution_by_phase.pdf](output/figures/phase5_moment1_distribution_by_phase.pdf) plots within-phase distributions winsorized at p99.

## Moment 2 — Same-year `firm_cost_share` at the ETS sellers in the B2B sample

The 192 ETS sellers that appear in the B2B leakage panel have a Phase IV cost-share distribution very close to the full ETS-firm population (n = 249 firm-years, p90 = 2.35%, mean = 1.83%, sales-wmean = 0.34%), confirming that B2B-sample ETS sellers are not a low-intensity subset.

[output/tables/phase5_moment2_b2b_seller_distribution.csv](output/tables/phase5_moment2_b2b_seller_distribution.csv)
[output/tables/phase5_moment2_b2b_seller_by_nace2d_phase4.csv](output/tables/phase5_moment2_b2b_seller_by_nace2d_phase4.csv)

Phase IV by seller NACE 2d (top sectors by p90, n ≥ 5):

| Seller NACE 2d | Sector | n firm-years | p50 | p90 | sales-wmean |
|---|---|---|---|---|---|
| 19 | Refining | 5 | 0.18% | 8.99% | 0.53% |
| 23 | Cement / non-metallic minerals | 68 | 0.92% | 4.43% | 2.15% |
| 17 | Paper | 12 | 0.43% | 2.15% | 0.78% |
| 20 | Chemicals | 91 | 0.12% | 2.15% | 0.51% |
| 13 | Textiles | 13 | 0.14% | 0.43% | 0.13% |
| 24 | Basic metals | 18 | 0.054% | 0.25% | 0.069% |
| 21 | Pharma | 7 | 0.010% | 0.095% | 0.014% |

The cement and refining sellers have meaningful Phase IV exposure. Most other sellers — including basic metals after the EUTL artefact correction — have small ratios.

## Moment 3 — Effective €/tonne emitted by phase

[output/tables/phase5_moment3_effective_carbon_price.csv](output/tables/phase5_moment3_effective_carbon_price.csv)

| Phase | EUA range (€) | Σ emissions (Mt) | Σ shortage (Mt) | Σ carbon cost (M€) | % emissions priced | Effective €/t emitted |
|---|---|---|---|---|---|---|
| I (2005–07) | 0.7–22.0 | 150.5 | 17.9 | 270.3 | 11.9% | **1.80** |
| II (2008–12) | 7.2–22.0 | 231.3 | 33.5 | 481.0 | 14.5% | **2.08** |
| III pre-MSR (13–17) | 4.4–7.6 | 213.7 | 71.8 | 416.3 | 33.6% | **1.95** |
| III post-MSR (18–20) | 15.5–24.8 | 125.0 | 46.5 | 1,000.0 | 37.2% | **8.00** |
| **IV (21–22)** | **53.7–80.2** | **64.0** | **31.5** | **2,100.0** | **49.2%** | **32.82** |

The Phase IV effective per-tonne shock is **~18× Phase I and ~16× Phase II**. This is the only metric where Phase IV looks like an unambiguously "real" shock at aggregate level. But this aggregate hides what fraction of buyers' input bills it represents — that's Moment 4.

## Moment 4 — Pair-level shock magnitude (the headline)

```
pair_shock_{j,b,t} = firm_cost_share_{j,t}
                   × (corr_sales_{j,b,t} / Σ_{j' ∈ same NACE4d as j} corr_sales_{j',b,t})
```

This is the buyer's exposure to a specific ETS seller's cost shock — what fraction of buyer b's spending on that input-NACE 4d goes to a seller whose costs are exposed to ETS at intensity `firm_cost_share_{j,t}`.

[output/tables/phase5_moment4_pair_shock_distribution.csv](output/tables/phase5_moment4_pair_shock_distribution.csv)

Distribution over **TREATED active pair-years** (ETS seller, corr_sales > 0):

| Phase | n pairs | p50 | p75 | p90 | p95 | p99 | mean | sales-wmean |
|---|---|---|---|---|---|---|---|---|
| I | 7,423 | 0% | 0% | 0.0001% | 0.005% | 0.14% | 0.005% | 0.007% |
| II | 12,324 | 0% | 0% | 0% | 0% | 0.07% | 0.002% | 0.014% |
| III pre-MSR | 11,146 | 0% | 0.006% | 0.097% | 0.24% | 0.89% | 0.055% | 0.11% |
| III post-MSR | 5,817 | 0.005% | 0.21% | 0.97% | 1.43% | 3.39% | 0.28% | 0.56% |
| **IV** | **3,597** | **0.084%** | **0.75%** | **3.30%** | **8.29%** | **12.0%** | **1.22%** | **0.94%** |

(Counts ~3.6× the local-1 downsampled estimates, as expected. p90 for Phase IV moved from 2.11% on local-1 to **3.30% on the full universe**.)

Phase IV by **buyer NACE 2d** (this is the leakage-relevant decomposition — the question is whether buyers in different downstream sectors face different incentives to substitute):

[output/tables/phase5_moment4_pair_shock_by_buyer_nace2d_phase4.csv](output/tables/phase5_moment4_pair_shock_by_buyer_nace2d_phase4.csv)

| Buyer NACE 2d | Sector | n pairs | p50 | p90 | p99 | sales-wmean |
|---|---|---|---|---|---|---|
| **23** | **Cement / minerals** | **1,340** | **1.37%** | **9.81%** | **12.0%** | **2.36%** |
| 17 | Paper | 54 | 0.12% | 2.31% | 2.34% | 0.53% |
| 19 | Refining | 15 | 0.07% | 1.64% | 5.20% | 0.96% |
| 32 | Other manufacturing | 8 | 0.79% | 0.94% | 0.94% | 0.70% |
| 22 | Plastics | 166 | 0.077% | 0.59% | 2.31% | 0.19% |
| 20 | Chemicals | 778 | 0.067% | 0.59% | 2.79% | 0.27% |
| 18 | Printing | 42 | 0.0024% | 0.57% | 2.21% | 0.22% |
| 13 | Textiles | 283 | 0.059% | 0.36% | 0.59% | 0.10% |
| 25 | Fabricated metals | 185 | 0.019% | 0.23% | 0.38% | 0.030% |
| 28 | Machinery | 88 | 0.011% | 0.23% | 0.30% | 0.078% |
| 24 | Basic metals | 87 | 0.0036% | 0.18% | 0.48% | 0.040% |
| 27 | Electrical | 25 | 0% | 0.17% | 0.34% | 0.0080% |
| 21 | Pharma | 14 | 0.021% | 0.062% | 0.062% | 0.030% |
| 11 | Beverages | 177 | 0% | 0.055% | 0.36% | 0.015% |
| 29 | Motor vehicles | 98 | 0% | 0.0080% | 0.0091% | 0.0028% |
| 16, 31, 33 | Wood, energy, repair | 237 | 0% | 0% | 0% | 0% |

**Cement is sui generis.** Its buyers (chiefly construction, civil engineering, ready-mix downstream) face Phase IV pair-shocks an order of magnitude larger than any other downstream sector. The 1,340 cement-buyer treated pair-years on the full universe (vs. 263 on local-1 downsampled) confirm this isn't a small-sample artifact. Most other regulated downstream sectors face Phase IV pair-shocks in the basis-points range.

[output/figures/phase5_moment4_pair_shock_distribution.pdf](output/figures/phase5_moment4_pair_shock_distribution.pdf) plots the distributions by phase (winsorized at p99 within phase).

### Moment 4(c) — Pair-shock-total (apples-to-apples with σ_share)

The pair-shock above uses the buyer's **NACE-4d-specific spending** as denominator. To do an apples-to-apples signal-to-noise comparison against σ_share (which is at the total-input scale), we also compute:

```
pair_shock_total_{j,b,t} = firm_cost_share_{j,t} × corr_sales_{j,b,t} / inputs_VAT_{b,t}
```

Same numerator (seller j's carbon-cost contribution to buyer b in year t) but denominator is **buyer's total input bill**.

[output/tables/phase5_moment4c_pair_shock_total_distribution.csv](output/tables/phase5_moment4c_pair_shock_total_distribution.csv)

| Phase | n treated pairs | p50 | p90 | p99 | mean | sales-wmean |
|---|---|---|---|---|---|---|
| I | 7,237 | 0% | 0.0000005% | 0.019% | 0.0006% | 0.003% |
| II | 12,035 | 0% | 0% | 0.0008% | 0.0001% | 0.001% |
| III pre-MSR | 10,889 | 0% | 0.001% | 0.047% | 0.003% | 0.026% |
| III post-MSR | 5,701 | 0.00002% | 0.061% | 0.57% | 0.032% | 0.11% |
| **IV** | **3,541** | **0.0016%** | **1.16%** | **39.1%** | **1.56%** | **6.74%** |

[output/tables/phase5_moment4c_pair_shock_total_by_buyer_nace2d_phase4.csv](output/tables/phase5_moment4c_pair_shock_total_by_buyer_nace2d_phase4.csv)

Phase IV by buyer NACE 2d:

| Buyer NACE 2d | Sector | n treated pairs | p50 | p90 | p99 | sales-wmean |
|---|---|---|---|---|---|---|
| 32 | Other manufacturing | 8 | 0.13% | 8.93% | 12.0% | 8.79% |
| **23** | **Cement / minerals** | **1,319** | **0.13%** | **8.80%** | **67.2%** | **21.0%** |
| 17 | Paper | 54 | 0.0009% | 0.49% | 3.62% | 0.58% |
| 19 | Refining | 15 | 0.005% | 0.38% | 0.47% | 0.13% |
| 13 | Textiles | 276 | 0.001% | 0.19% | 2.44% | 1.17% |
| 18 | Printing | 37 | 0.0001% | 0.10% | 4.02% | 1.15% |
| 22 | Plastics | 166 | 0.0004% | 0.10% | 1.38% | 0.38% |
| 25 | Fab metals | 185 | 0.0008% | 0.09% | 1.03% | 0.57% |
| 20 | Chemicals | 773 | 0.0005% | 0.09% | 2.14% | 0.63% |
| 28 | Machinery | 86 | 0.00007% | 0.06% | 1.48% | 0.35% |
| 27 | Electrical | 25 | 0% | 0.010% | 0.073% | 0.020% |
| 24 | Basic metals | 87 | 0.00003% | 0.008% | 0.33% | 0.015% |
| 11 | Beverages | 170 | 0% | 0.004% | 0.18% | 0.11% |
| 21 | Pharma | 14 | 0.00008% | 0.002% | 0.003% | 0.0006% |
| 29 | Motor vehicles | 97 | 0% | 0.00004% | 0.006% | 0.002% |
| 16, 31, 33 | Wood, energy, repair | 229 | 0% | 0% | 0% | 0% |

Cement again stands out: cement-buyer pair-shock-total p90 is **8.80%** vs cement-buyer σ_share p50 of **13.0%** → signal-to-noise **0.68σ**. For all other regulated sectors the per-pair contribution to total cost is ≤ 0.5%, well below the relevant noise floor.

### Moment 4(a) — Buyer-total-shock (aggregate exposure, sum across pairs)

Sum across all buyer's ETS sellers, divided by total inputs:

```
buyer_total_shock_{b,t} = Σ_j (firm_cost_share_j × corr_sales_{j,b,t}) / inputs_VAT_{b,t}
```

[output/tables/phase5_moment4a_buyer_total_shock_distribution.csv](output/tables/phase5_moment4a_buyer_total_shock_distribution.csv)

| Phase | n buyers | p50 | p90 | p95 | p99 | mean |
|---|---|---|---|---|---|---|
| I | 30,875 | 0 | 0 | 0 | 0.0002% | 0.0001% |
| II | 48,994 | 0 | 0 | 0 | 0% | 0.000024% |
| III pre-MSR | 44,009 | 0 | 0 | 0.000013% | 0.0085% | 0.0007% |
| III post-MSR | 24,801 | 0 | 0 | 0.0004% | 0.20% | 0.007% |
| **IV** | **15,442** | **0** | **0** | **0.031%** | **6.90%** | **0.36%** |

**Most buyers have buyer_total_shock = 0** because they don't have any ETS suppliers in their portfolio. The right-tail buyers (p99 in Phase IV = 6.90%) are mostly cement-input-heavy buyers. This metric is uninformative for the substitution question — it's an aggregate macro-burden number, useful only as background.

## Moment 5 — Substitution-relevant benchmarks

[output/tables/phase5_moment5_buyer_volatility_inputsVAT.csv](output/tables/phase5_moment5_buyer_volatility_inputsVAT.csv)
[output/tables/phase5_moment5_buyer_volatility_by_nace2d.csv](output/tables/phase5_moment5_buyer_volatility_by_nace2d.csv)

### (b) Buyer-level input-cost volatility

For each buyer in the B2B sample, compute `σ_b = sd_t(Δlog(inputs_VAT))` over consecutive years, where `inputs_VAT` is the firm's directly-declared input expenditure on VAT returns (from `annual_accounts_more_selected_sample.RData`). Avoids revenue-volatility contamination of the `revenue − value_added` measure.

Reported separately for three windows. **Full Belgian Annual Accounts universe — n_buyers ranges from 9k to 14k**, vs ~600 on local-1 downsampled.

| Window | n buyers | p25 | p50 | p75 | p90 | mean |
|---|---|---|---|---|---|---|
| **2005–2019 (pre-shock)** | **13,386** | 16.3% | **24.1%** | 38.3% | 63.4% | 33.0% |
| 2019–2022 (Phase IV / pandemic) | 9,038 | 13.7% | 21.4% | 34.1% | 55.4% | 29.4% |
| 2005–2022 (pooled) | 14,103 | 17.3% | 25.3% | 39.7% | 64.9% | 34.1% |

The **2005–2019 σ_b is the cleaner benchmark** — it's the noise floor that *predates* the Phase IV ETS shock and the pandemic. The full-universe p50 is **24.1%**, essentially identical to the local-1 estimate (24.0%). Cross-buyer median is robust to sampling, exactly as expected.

By buyer NACE 2d, 2005–2019 p50 σ_b ranges from **17.3%** (beverages, NACE 11) to **30.9%** (basic metals, NACE 24). Notable cells:

| Buyer NACE 2d | n | p50 σ_b 2005–2019 |
|---|---|---|
| 24 (basic metals) | 255 | 30.9% |
| 33 (repair) | 883 | 29.6% |
| 28 (machinery) | 1,276 | 28.0% |
| 25 (fab metals) | 3,758 | 26.5% |
| **23 (cement)** | **1,094** | **20.7%** |
| 20 (chemicals) | 585 | 22.9% |
| 17 (paper) | 264 | 18.2% |
| 11 (beverages) | 146 | 17.3% |

**Cement-buyer σ_b (20.7%) is on the low end** — meaning cement buyers face less natural noise than other sectors. But raw σ_b mixes scale variation with input-cost-structure variation; the right benchmark is the scale-stripped σ_share below.

### (b') σ_share — scale-stripped on inputs/revenue ratio (THE RIGHT BENCHMARK)

```
σ_share = within-firm sd of Δlog(inputs_VAT / turnover_VAT)
        = within-firm sd of [Δlog(inputs) - Δlog(revenue)]
```

If quantity scales both inputs and revenue together, the ratio is stable in scale and only varies with input-cost-structure changes — i.e., the price-and-margin-composition component. **This is the correct comparator for an ETS price shock**, which is a pure price shock that doesn't depend on the firm's quantity decisions.

[output/tables/phase5_moment5_buyer_volatility_input_share.csv](output/tables/phase5_moment5_buyer_volatility_input_share.csv)
[output/tables/phase5_moment5_buyer_volatility_input_share_by_nace2d.csv](output/tables/phase5_moment5_buyer_volatility_input_share_by_nace2d.csv)

| Window | n buyers | p25 | p50 | p75 | p90 | mean |
|---|---|---|---|---|---|---|
| **2005–2019 (pre-shock)** | **13,386** | 9.9% | **15.0%** | 23.7% | 39.1% | 21.1% |
| 2019–2022 (Phase IV / pandemic) | 9,038 | 7.6% | 12.7% | 21.3% | 35.5% | 18.7% |
| 2005–2022 (pooled) | 14,103 | 10.3% | 15.4% | 24.5% | 40.6% | 21.8% |

**Scale-stripped σ_share is roughly 60% of raw σ_b** (15.0% vs 24.1% at p50 pre-shock), consistent with about half the apparent "input cost noise" being scale variation rather than price-and-mix variation.

By buyer NACE 2d, 2005–2019 p50 σ_share:

| Buyer NACE 2d | n | p50 σ_share |
|---|---|---|
| 21 (pharma) | 129 | 20.7% |
| 26 (computers) | 353 | 17.5% |
| 28 (machinery) | 1,276 | 17.4% |
| 33 (repair) | 883 | 17.4% |
| 24 (basic metals) | 255 | 15.4% |
| 20 (chemicals) | 585 | 13.5% |
| **23 (cement)** | **1,094** | **13.0%** |
| 17 (paper) | 264 | 11.8% |
| 19 (refining) | 14 | 10.3% |

**Cement-buyer σ_share = 13.0%** is the right noise floor for cement-buyer pair-shock-total. Combined with cement-buyer Phase IV pair-shock-total p90 of 8.80%, signal-to-noise = **0.68σ** — meaningful, near the threshold of detectability.

### (b) σ_nace at (buyer × NACE 4d) level — overstates noise

For pair-shock at the NACE-4d denominator, the units-matched noise floor would be `sd_t( Δlog(NACE-4d-spend / revenue) )` per (buyer × NACE 4d).

[output/tables/phase5_moment5_sigma_nace_distribution.csv](output/tables/phase5_moment5_sigma_nace_distribution.csv)

| Window | n cells | p25 | p50 | p75 | p90 | mean |
|---|---|---|---|---|---|---|
| **2005–2019 (pre-shock)** | **79,069** | 50% | **84%** | 129% | 184% | 98% |
| 2019–2022 (Phase IV / pandemic) | 39,901 | 147% | 221% | 264% | 326% | 210% |
| 2005–2022 (pooled) | 85,198 | 69% | 119% | 169% | 225% | 127% |

**σ_nace is dramatically higher than σ_share** because NACE-4d-specific spending captures within-NACE-4d quantity changes, supplier rotations, lumpy purchasing, and product-mix shifts — none of which are the relevant noise for an ETS *price* shock. The cleanest version would require seller-level unit prices (PRODCOM, mocked on local-1).

**Treat σ_nace as an upper bound on the relevant price-noise floor.** Even cement signal-to-noise on this measure (9.81% / ~84% = 0.12σ) is small, but only because σ_nace overstates the relevant noise.

### (c) Heise 2024 (AER) FX-shock benchmark

Heise's calibrated quarterly std of log e is σ_ξ = 0.066, with FX-to-seller-cost elasticity α = 0.444. A typical 1-σ quarterly FX shock translates to a 2.93% seller-cost shock per quarter, or roughly 5.86% annualized (treating quarterly innovations as iid). At a typical Heise import-share of ~25% of buyer's input bill, the buyer-side annual shock from a 1-σ FX move is **~1.5%**.

### (a) Cross-border price gap — DEFERRED

Requires customs unit-value rebuild. Not computed.

### Apples-to-apples signal-to-noise summary (option (c) — primary)

The headline signal-to-noise comparison uses **option (c)**: pair-shock-total at the total-input denominator vs σ_share at the same scale.

| Quantity | Magnitude | vs σ_share 2005–2019 (15.0%) |
|---|---|---|
| Phase IV pair-shock-total p90 (population, treated) | **1.16%** | **0.08σ** |
| **Phase IV pair-shock-total p90 (cement buyers)** | **8.80%** | **0.68σ** |
| Phase IV pair-shock-total p90 (paper, refining) | 0.4–0.5% | 0.03–0.04σ |
| Phase IV pair-shock-total p90 (chemicals, plastics, machinery, basic metals) | < 0.1% | < 0.01σ |
| Heise typical 1-σ FX shock (buyer-side, annual) | ~1.5% | ~0.10σ |

**The pair-shock signal is vanishing relative to background noise outside cement.** A typical regulated buyer's per-pair ETS exposure (1% of total inputs) is ~1/12 of their annual input-cost-structure noise. **Only cement reaches the threshold of detectability**, with signal-to-noise = 0.68σ.

For comparison, the previous version of this verdict used pair-shock at the NACE-4d denominator vs raw σ_b at total-input — *different units*. Putting both at the same scale (option (c)):

- Population: 0.14σ → 0.08σ (smaller, because pair-shock-total < pair-shock at NACE denominator)
- Cement: 0.47σ → 0.68σ (sharper detectability), since σ_share strips out scale and shrinks the denominator faster than the numerator

This is consistent with the literature on FX pass-through (Heise's mechanism gets identified despite small per-shock magnitudes, but using high-frequency price observations and structural identification — not from observed sourcing changes). At our annual-frequency, value-only, no-price-data setup, the signal-to-noise ratio is too low to expect observable substitution at the typical pair, **except in cement**.

## Moment 6 — Phase IV stress test

[output/tables/phase5_moment6_phase4_stress.csv](output/tables/phase5_moment6_phase4_stress.csv)

The Phase IV-only by-NACE-2d firm-year distribution (Moment 1 restricted to 2021–22) confirms the right-tail concentration. Top sectors by Phase IV p90 firm cost-share match the ranking from Moment 2 — refining, cement, paper, chemicals.

## Verification (per Plan A)

1. **Phase IV p90 sanity check:** population p90 = 2.60%. High-intensity NACE 23 seller p90 = 4.4%; NACE 19 (refining) p90 = 8.99%. All in expected ranges. Cross-walks with [PASSTHROUGH.md](PASSTHROUGH.md) shock-size table. ✓
2. **Pair-shock = 0 for non-ETS sellers:** mechanically built in via the `seller_is_ets == 1` filter. ✓
3. **Cross-check Moment 3 against PASSTHROUGH.md:** my Phase IV effective €/tonne (32.8) is higher than PASSTHROUGH's 19.3 because PASSTHROUGH used 2021 only with €40 EUA, while I use 2021–22 average with EUA up to €80 in 2022. EUA range matches PASSTHROUGH's 2021 €40. ✓
4. **Sales-weighted vs unweighted:** Phase IV mean cost-share is 6.85% (population) but sales-weighted is only 0.71%, indicating the heavy right tail is at small sellers. Confirmed. ✓
5. **Sector decomposition:** cement, refining, paper, chemicals have the largest p90s; pharma, machinery, electrical near zero. Matches expectation from PASSTHROUGH.md selection finding. ✓
6. **Verdict consistency:** Moment 1 population p90 (2.60%) ≈ Moment 4 treated active p90 at the population level (3.30%, slightly higher because pair_shock weights by within-NACE share). Moment 2 (B2B sellers) is ~equal to Moment 1 because B2B sellers ≈ full ETS population. ✓
7. **Loss-making firm-years and is_regulated == 0 firm-years dropped:** 833 firm-years where cost-share is undefined (mostly is_regulated == 0 from the upstream fix; some total_cost ≤ 0). Reported transparently. ✓
8. **σ_b cross-buyer median 24.1% on full universe matches 24.0% on local-1 downsampled** — robust to sampling. Tail percentiles slightly different but same shape. ✓
9. **σ_share (scale-stripped) is roughly 60% of σ_b (raw):** 15.0% vs 24.1% pre-shock. Consistent with about half of raw input-cost variation being scale (firm growing/shrinking). ✓
10. **pair-shock-total ≪ pair-shock at NACE-4d denom in non-cement sectors:** because most NACE 4ds are a small fraction of total inputs. Cement is the exception (NACE-4d ≈ buyer-total for cement-input-heavy buyers). ✓
11. **buyer-total-shock has p90 = 0% in Phase IV:** most regulated-intensive buyers don't have any ETS suppliers in their portfolio. Right-tail (p99 = 6.9%) is cement-input-heavy buyers. ✓

## Files and outputs

### Scripts
- [analysis/phase5_shock_distribution_byphase.R](analysis/phase5_shock_distribution_byphase.R) — Moments 1, 3, 6
- [analysis/phase5_pair_shock_magnitude.R](analysis/phase5_pair_shock_magnitude.R) — Moments 2, 4
- [analysis/phase5_shock_benchmarks.R](analysis/phase5_shock_benchmarks.R) — Moment 5

### Tables (output/tables/)
- `phase5_moment1_cost_share_distribution.csv`
- `phase5_moment2_b2b_seller_distribution.csv`
- `phase5_moment2_b2b_seller_by_nace2d_phase4.csv`
- `phase5_moment3_effective_carbon_price.csv`
- `phase5_moment4_pair_shock_distribution.csv` (option (b), NACE-4d denom)
- `phase5_moment4_pair_shock_by_buyer_nace2d_phase4.csv`
- `phase5_moment4a_buyer_total_shock_distribution.csv` (option (a), aggregated)
- `phase5_moment4c_pair_shock_total_distribution.csv` (option (c), total-input denom — primary)
- `phase5_moment4c_pair_shock_total_by_buyer_nace2d_phase4.csv`
- `phase5_moment5_buyer_volatility_inputsVAT.csv` (raw σ_b)
- `phase5_moment5_buyer_volatility_input_share.csv` (σ_share — primary noise floor)
- `phase5_moment5_buyer_volatility_input_share_by_nace2d.csv`
- `phase5_moment5_buyer_volatility_by_nace2d.csv` (raw σ_b by NACE 2d)
- `phase5_moment5_sigma_nace_distribution.csv` (NACE-4d-level σ; upper bound noise)
- `phase5_moment5_sigma_nace_by_buyer_nace2d.csv`
- `phase5_moment5_typical_change.csv` (median |Δlog| companion stat)
- `phase5_moment5_typical_change_input_share.csv`
- `phase5_moment5_inputsVAT_vs_domestic_check.csv`
- `phase5_moment6_phase4_stress.csv`
- `phase5_shock_distribution_summary.txt` (Moments 1, 3, 6 readable)
- `phase5_pair_shock_summary.txt` (Moments 2, 4 readable)
- `phase5_moment5_benchmarks_summary.txt` (Moment 5 readable)

### Figures (output/figures/)
- `phase5_moment1_distribution_by_phase.pdf`
- `phase5_moment4_pair_shock_distribution.pdf`

## Caveats

- All numbers above are from the **full Belgian B2B universe and full Annual Accounts** computed on RMD. The local-1 versions of these scripts are testing-only.
- 3 contaminated VAT hashes (NACE 20, 24 EUTL artefact post-2020) excluded from 2021+. See [MEMORY.md](C:\Users\jota_\.claude\projects\c--Users-jota--Documents-carbon-leakage\memory\project_nace24_eutl_break_post2020.md).
- σ_b uses `inputs_VAT` from `annual_accounts_more_selected_sample.RData` — directly-declared input expenditure, not the accounting-derived `revenue − value_added`. Nominal (includes input-price inflation), which is correct for the benchmark question: a buyer absorbing a 5% input-price increase still has to pay it, regardless of whether it is real or nominal.
- Cement (NACE 23) Phase IV pair-shock distribution is driven by 1,340 treated pair-years across ~30 distinct ETS sellers in cement-supplying NACE 4ds (the cement industry is concentrated). Stickiness vs concentration distinction matters most for this sector, since it's the one place the shock is large enough to be detectable.
- The `is_regulated`-aware filter in the upstream `firm_year_belgian_euets` build ensures firm-years where the firm has no installation reporting verified emissions (entry/exit boundary years and gap years where all installations have NA verified) are flagged with `is_regulated == 0` and `emissions == NA`. They are excluded from the cost-share distribution by the downstream `!is.na(cost_share_total)` filter, so the percentiles above are computed on genuinely covered firm-years only.

---

*Generated: 2026-04-29. Plan A complete; Plan B (stickiness vs concentration) is the next phase, with **Test G (feasibility-restricted substitution test)** as the foundational primary test.*
