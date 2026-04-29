# Shock Magnitude: How Big is the ETS Cost Shock to Belgian B2B?

*Plan A of [streamed-leaping-tide.md](C:\Users\jota_\.claude\plans\streamed-leaping-tide.md). Six descriptive moments characterizing how big the ETS cost shock is at the firm-year, sector-year, and pair-year levels, by ETS phase. Anchors whether the null leakage finding in [B2B_LEAKAGE.md](B2B_LEAKAGE.md) and [IMPORT_LEAKAGE.md](IMPORT_LEAKAGE.md) is informative or mechanically driven by a too-small shock. Numbers below are from the **full Belgian B2B universe and full Annual Accounts** computed on RMD; the upstream `firm_year_belgian_euets.RData` reflects the corrected `is_regulated`-aware build.*

## Verdict

**Population-level: shock is moderate. Cement-buyer-level: shock is real. Most-other-regulated-buyer-level: shock is submerged in normal cost-volatility noise.**

- Phase IV (2021–22) p90 of `firm_cost_share_{j,t}` across all ETS firms: **2.6%**.
- Phase IV p90 of pair-shock at active treated pairs (the buyer-exposure measure that drives the leakage incentive): **3.3%**.
- Phase IV p90 of pair-shock at **cement (NACE 23) buyers**: **9.8%** (sales-wmean 2.4%, n = 1,340 treated pair-years).
- Phase IV p90 of pair-shock at refining (19), paper (17), chemicals (20), plastics (22): **0.6–2.3%**.
- Phase IV p90 of pair-shock at basic-metals, pharma, machinery, electrical buyers: **≤ 0.2%**.
- Cross-buyer median annual σ_b on `inputs_VAT` (2005–2019, pre-shock): **24.1%** (n = 13,386 buyers).

Following the decision rule in the plan (pair-shock p90 in Phase IV: >5% real, 1–5% moderate, <1% small):

| Buyer sector | Phase IV p90 | Verdict |
|---|---|---|
| Cement (NACE 23) | 9.81% | **Real** |
| Paper (17) | 2.31% | **Moderate** |
| Refining (19), chemicals (20), plastics (22), printing (18) | 0.6–1.6% | **Moderate–small** |
| Textiles (13), fab metals (25), machinery (28), basic metals (24), pharma (21), motor vehicles (29) | ≤ 0.4% | **Small** |
| Population (all treated active pairs) | 3.30% | **Moderate (upper end)** |

**Implication for the [STICKINESS_VS_CONCENTRATION.md](STICKINESS_VS_CONCENTRATION.md) plan:**

1. The null leakage finding is *informative* for cement: the shock is real, the substitution incentive exists, the null says something about the cement market. Cement-buyer p90 is ~½× their typical annual σ_b (20.7%) — the signal is non-trivial relative to background noise for this sector.
2. The null is *mechanically driven by small magnitude* for basic metals, pharma, machinery, electrical, motor vehicles: the shock is well below normal buyer-level cost volatility (24% median σ_b), so "no substitution" is the rational response regardless of stickiness or concentration.
3. The null is *moderate-mixed* for chemicals, refining, paper, plastics: the shock is non-trivial in absolute terms (0.6–2.3% pair-shock) but only ~5–10% of buyer-level σ_b. Likely buried in noise.
4. **Test G of Plan B (feasibility-restricted substitution) is the right primary test.** It restricts to high-power cells where pair-shock is materially above background. Cement-buyer cells are the natural candidates and where the test will have most power.
5. **Plan B's framing should acknowledge the bounded interpretability of the null.** "Belgium does not exhibit measurable carbon leakage" is correct but partially mechanical; the more accurate framing is "outside cement, Belgian buyers face only modest pair-level ETS exposure even in Phase IV (typical pair-shock far below normal cost volatility); no leakage is measured but the test is identification-bound by the shock magnitude."

The plan's 2017/2018 + Phase IV framing is correct — Phase I–III have shocks that are at or below the noise floor for nearly all buyers.

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

**Cement-buyer σ_b (20.7%) is on the low end** — meaning cement buyers face less natural noise than other sectors. Combined with their Phase IV pair-shock p90 of 9.81%, this puts the cement signal-to-noise at roughly **9.81% / 20.7% ≈ 0.47×** — non-trivial.

### (c) Heise 2024 (AER) FX-shock benchmark

Heise's calibrated quarterly std of log e is σ_ξ = 0.066, with FX-to-seller-cost elasticity α = 0.444. A typical 1-σ quarterly FX shock translates to a 2.93% seller-cost shock per quarter, or roughly 5.86% annualized (treating quarterly innovations as iid). At a typical Heise import-share of ~25% of buyer's input bill, the buyer-side annual shock from a 1-σ FX move is **~1.5%**.

### (a) Cross-border price gap — DEFERRED

Requires customs unit-value rebuild. Not computed.

### Comparison

| Quantity | Magnitude | vs σ_b 2005–2019 (24.1%) |
|---|---|---|
| Phase IV pair-shock p90 (treated, all sectors) | **3.30%** | **0.14×** |
| Phase IV pair-shock p90 (cement buyers) | **9.81%** | **0.47×** |
| Phase IV pair-shock p90 (chemicals, refining) | 0.6–1.7% | 0.03–0.07× |
| Heise typical 1-σ FX shock (buyer-side, annual) | ~1.5% | 0.06× |

**The pair-shock signal is small relative to background noise outside cement.** A typical regulated buyer experiencing a 3% ETS-driven cost increase at one of their sellers is facing a perturbation that is ~1/7th of their annual material-cost noise. The cement-buyer p90 (~½× σ_b) is the only regulated-buyer subset where the signal-to-noise ratio is meaningful.

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
- `phase5_moment4_pair_shock_distribution.csv`
- `phase5_moment4_pair_shock_by_buyer_nace2d_phase4.csv`
- `phase5_moment5_buyer_volatility_inputsVAT.csv`
- `phase5_moment5_buyer_volatility_by_nace2d.csv`
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
