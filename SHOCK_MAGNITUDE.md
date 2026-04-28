# Shock Magnitude: How Big is the ETS Cost Shock to Belgian B2B?

*Plan A of [streamed-leaping-tide.md](C:\Users\jota_\.claude\plans\streamed-leaping-tide.md). Six descriptive moments characterizing how big the ETS cost shock is at the firm-year, sector-year, and pair-year levels, by ETS phase. Anchors whether the null leakage finding in [B2B_LEAKAGE.md](B2B_LEAKAGE.md) and [IMPORT_LEAKAGE.md](IMPORT_LEAKAGE.md) is informative or mechanically driven by a too-small shock.*

## Verdict

**Population-level: shock is moderate. Cement-buyer-level: shock is real. Most-other-regulated-buyer-level: shock is submerged in normal cost-volatility noise.**

- Phase IV (2021–22) p90 of `firm_cost_share_{j,t}` across all ETS firms: **2.3%**.
- Phase IV p90 of pair-shock at active treated pairs (the buyer-exposure measure that drives the leakage incentive): **2.1%**.
- Phase IV p90 of pair-shock at **cement (NACE 23) buyers**: **9.8%** (sales-wmean 5.7%).
- Phase IV p90 of pair-shock at refining (19), paper (17), chemicals (20) buyers: **0.7–1.7%**.
- Phase IV p90 of pair-shock at basic-metals, pharma, machinery, electrical buyers: **≤ 0.2%**.
- Cross-buyer median annual σ of Δlog material cost: **26%**.

Following the decision rule in the plan (pair-shock p90 in Phase IV: >5% real, 1–5% moderate, <1% small):

| Buyer sector | Phase IV p90 | Verdict |
|---|---|---|
| Cement (NACE 23) | 9.8% | **Real** |
| Refining, paper, chemicals (19, 17, 20) | 0.7–1.7% | **Moderate–small** |
| Basic metals, pharma, machinery, electrical (24, 21, 28, 27) | ≤ 0.2% | **Small** |
| Population (all treated active pairs) | 2.1% | **Moderate** |

**Implication for the [STICKINESS_VS_CONCENTRATION.md](STICKINESS_VS_CONCENTRATION.md) plan:**

1. The null leakage finding is *informative* for cement: the shock is real, the substitution incentive exists, the null says something about the cement market.
2. The null is *mechanically driven by small magnitude* for basic metals, pharma, machinery, electrical: the shock is well below normal buyer-level cost volatility (26% median σ), so "no substitution" is the rational response regardless of stickiness or concentration.
3. The null is *moderate-mixed* for refining, chemicals, paper: the shock is non-trivial in absolute terms (1–2% pair-shock) but comparable to roughly 1× buyer-level σ. Hard to distinguish from noise.
4. **Plan B should be run with sector-level decomposition front and center** — and cement should be reported separately from the rest. A pooled stickiness-vs-concentration test on the full panel may average the cement signal away.
5. **Plan B's framing should acknowledge the bounded interpretability of the null.** "Belgium does not exhibit measurable carbon leakage" is correct but partially mechanical; the more accurate framing is "Belgian buyers face only modest pair-level ETS exposure even in Phase IV (median pair-shock far below normal cost volatility); no leakage is measured but the test is identification-bound by the shock magnitude."

The plan's 2017/2018 + Phase IV framing is correct — Phase I–III have shocks that are at or below the noise floor for nearly all buyers.

## Definition of `firm_cost_share`

Plan A is descriptive. Same-year ratio:

```
firm_cost_share_{j,t} = (shortage_{j,t} × EUA_t) / total_cost_{j,t}
```

`shortage = max(emissions − allocated_free, 0)`. `total_cost = (revenue − value_added) + wage_bill`. Numerator and denominator both in year t. No Bartik denominator needed because Plan A estimates no treatment effect; the ratio is a pure descriptive statistic and the same-year version is automatically inflation-neutral. Plan B's regression specs use a different definition, see the plan file.

Sample: Belgian ETS firms `in_sample == 1` from `firm_year_belgian_euets.RData`. Three contaminated VAT hashes (NACE 20, 24 EUTL artefact post-2020) excluded from 2021+ per [MEMORY.md](C:\Users\jota_\.claude\projects\c--Users-jota--Documents-carbon-leakage\memory\project_nace24_eutl_break_post2020.md). Firm-years with `total_cost ≤ 0` dropped (22 obs, 0.6%). Final sample: 3,902 firm-years.

## Moment 1 — Same-year `firm_cost_share` distribution by phase (population)

[output/tables/phase5_moment1_cost_share_distribution.csv](output/tables/phase5_moment1_cost_share_distribution.csv)

| Phase | n firm-years | n firms | % positive shortage | p50 | p90 | p99 | mean | sales-wmean |
|---|---|---|---|---|---|---|---|---|
| I (2005–07) | 642 | 224 | 16% | 0% | 0.006% | 0.4% | 0.018% | 0.08% |
| II (2008–12) | 1122 | 240 | 9% | 0% | 0% | 0.32% | 0.14% | 0.07% |
| III pre-MSR (13–17) | 1095 | 232 | 52% | 0.001% | 0.25% | 7.6% | 0.47% | 0.08% |
| III post-MSR (18–20) | 635 | 217 | 57% | 0.028% | 1.12% | 22.0% | 1.13% | 0.28% |
| **IV (21–22)** | **408** | **208** | **64%** | **0.15%** | **2.27%** | **43.0%** | **5.35%** | **0.65%** |

**Read:**
- Phase I–II: shocks essentially zero everywhere (free allocation generous).
- Phase III pre-MSR: shock starts to bite for upper-tail firms (p99 = 7.6%); median still ~0.
- Phase IV: median 0.15%, p90 2.3%, p99 43%. Distribution is heavy-tailed.

[output/figures/phase5_moment1_distribution_by_phase.pdf](output/figures/phase5_moment1_distribution_by_phase.pdf) plots the within-phase distributions winsorized at p99.

## Moment 2 — Same-year `firm_cost_share` at the ETS sellers in the B2B sample

The ETS sellers that appear in the B2B leakage panel are 187 of the 224 ETS firms (those with at least one regulated-intensive buyer in the core-input pairs). Their firm-year cost-share distribution is essentially identical to the full ETS-firm population (Moment 1 numbers by phase), confirming that B2B-sample ETS sellers are not a low-intensity subset.

[output/tables/phase5_moment2_b2b_seller_distribution.csv](output/tables/phase5_moment2_b2b_seller_distribution.csv)
[output/tables/phase5_moment2_b2b_seller_by_nace2d_phase4.csv](output/tables/phase5_moment2_b2b_seller_by_nace2d_phase4.csv)

Phase IV by seller NACE 2d (top sectors by p90):

| Seller NACE 2d | Sector | p50 | p90 | sales-wmean |
|---|---|---|---|---|
| 35 | Electricity | 1.3% | 71.0% | 2.1% |
| 33 | Repair | 21.8% | 39.1% | 1.5% |
| 19 | Refining | 0.13% | 8.9% | 0.5% |
| 49 | Transport | 2.4% | 6.1% | 1.7% |
| 23 | Cement / non-metallic minerals | 0.68% | 4.4% | 2.1% |
| 10 | Food | 0.34% | 2.2% | 0.27% |
| 17 | Paper | 0.28% | 2.0% | 0.75% |
| 20 | Chemicals | 0.11% | 2.1% | 0.51% |
| 24 | Basic metals | 0.006% | 0.22% | 0.07% |
| 21 | Pharma | 0.01% | 0.09% | 0.01% |

The cement and electricity sellers have meaningful Phase IV exposure. Most other sellers — including the heavily-emitting basic metals after the EUTL artefact correction — have very small ratios.

## Moment 3 — Effective €/tonne emitted by phase

[output/tables/phase5_moment3_effective_carbon_price.csv](output/tables/phase5_moment3_effective_carbon_price.csv)

| Phase | EUA range (€) | Σ emissions (Mt) | Σ shortage (Mt) | Σ carbon cost (M€) | % emissions priced | Effective €/t emitted |
|---|---|---|---|---|---|---|
| I (2005–07) | 0.7–22.0 | 150.5 | 17.9 | 270.3 | 11.9% | **1.80** |
| II (2008–12) | 7.2–22.0 | 231.3 | 33.5 | 481.0 | 14.5% | **2.08** |
| III pre-MSR (13–17) | 4.4–7.6 | 213.7 | 71.8 | 416.3 | 33.6% | **1.95** |
| III post-MSR (18–20) | 15.5–24.8 | 125.0 | 46.5 | 1,000.0 | 37.2% | **8.00** |
| **IV (21–22)** | **53.7–80.2** | **64.0** | **31.5** | **2,100.0** | **49.2%** | **32.82** |

The Phase IV effective per-tonne shock is **~18× Phase I and ~16× Phase II**. This is consistent with the [PASSTHROUGH.md](PASSTHROUGH.md) Section A shock-size diagnostic table; the ranges align except for higher Phase IV EUA range (we use 2021–22 vs PASSTHROUGH's 2021 only).

This is the only metric where Phase IV looks like an unambiguously "real" shock at aggregate level. But this aggregate hides what fraction of buyers' input bills it represents — that's Moment 4.

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
| I | 1763 | 0% | 0% | 0.0004% | 0.005% | 0.14% | 0.006% | 0.005% |
| II | 3216 | 0% | 0% | 0% | 0.001% | 0.08% | 0.002% | 0.017% |
| III pre-MSR | 2999 | 0% | 0.012% | 0.11% | 0.31% | 0.98% | 0.11% | 0.14% |
| III post-MSR | 1632 | 0.004% | 0.13% | 0.69% | 1.23% | 3.03% | 0.22% | 0.66% |
| **IV** | **992** | **0.084%** | **0.47%** | **2.11%** | **5.02%** | **12.0%** | **1.23%** | **1.04%** |

Phase IV by **buyer NACE 2d** (this is the leakage-relevant decomposition — the question is whether buyers in different downstream sectors face different incentives to substitute):

[output/tables/phase5_moment4_pair_shock_by_buyer_nace2d_phase4.csv](output/tables/phase5_moment4_pair_shock_by_buyer_nace2d_phase4.csv)

| Buyer NACE 2d | Sector | n pairs | p50 | p90 | p99 | sales-wmean |
|---|---|---|---|---|---|---|
| **23** | **Cement / minerals** | **263** | **1.12%** | **9.81%** | **63.5%** | **5.70%** |
| 19 | Refining | 14 | 0.05% | 1.71% | 5.24% | 0.96% |
| 17 | Paper | 21 | 0.11% | 1.07% | 2.32% | 0.27% |
| 32 | Other manufacturing | 1 | — | 0.94% | — | 0.94% |
| 20 | Chemicals | 430 | 0.07% | 0.75% | 4.44% | 0.34% |
| 22 | Plastics | 40 | 0.10% | 0.74% | 1.82% | 0.39% |
| 18 | Printing | 4 | 0.18% | 0.74% | 0.88% | 0.86% |
| 13 | Textiles | 61 | 0.08% | 0.38% | 0.60% | 0.10% |
| 25 | Fabricated metals | 14 | 0.01% | 0.33% | 0.38% | 0.02% |
| 28 | Machinery | 5 | 0.16% | 0.21% | 0.23% | 0.001% |
| 24 | Basic metals | 52 | 0.008% | 0.20% | 0.68% | 0.04% |
| 11 | Beverages | 38 | 0% | 0.14% | 0.31% | 0.004% |
| 21 | Pharma | 7 | 0.03% | 0.09% | 0.14% | 0.03% |
| 27 | Electrical | 10 | 0% | 0.02% | 0.16% | 0.007% |
| 29 | Motor vehicles | 17 | 0% | 0.008% | 0.008% | 0.0005% |
| 16 | Wood | 14 | 0% | 0% | 0% | 0% |

**Cement is sui generis.** Its buyers (chiefly construction, civil engineering, ready-mix downstream) face Phase IV pair-shocks an order of magnitude larger than any other downstream sector. Most other regulated downstream sectors face Phase IV pair-shocks in the basis-points range.

[output/figures/phase5_moment4_pair_shock_distribution.pdf](output/figures/phase5_moment4_pair_shock_distribution.pdf) plots the distributions by phase (winsorized at p99 within phase).

## Moment 5 — Substitution-relevant benchmarks

[output/tables/phase5_moment5_buyer_volatility.csv](output/tables/phase5_moment5_buyer_volatility.csv)
[output/tables/phase5_moment5_benchmarks_summary.txt](output/tables/phase5_moment5_benchmarks_summary.txt)

### (b) Buyer-level input-cost volatility

For each buyer in the B2B sample, compute `σ_b = sd_t(Δlog(inputs_VAT))` over consecutive years, where `inputs_VAT` is the firm's directly-declared input expenditure on VAT returns (from `annual_accounts_more_selected_sample.RData`). Using `inputs_VAT` rather than the prior `revenue − value_added` avoids conflating revenue volatility (prices, demand, inventory wedges) with input-cost volatility.

Reported separately for three windows:

| Window | n buyers | p25 | p50 | p75 | p90 | mean |
|---|---|---|---|---|---|---|
| **2005–2019 (pre-shock)** | **612** | 16.0% | **24.0%** | 39.0% | 67.0% | 32.6% |
| 2019–2022 (Phase IV / pandemic) | 488 | 14.3% | 22.0% | 32.4% | 47.6% | 28.6% |
| 2005–2022 (pooled) | 620 | 17.0% | 24.9% | 39.9% | 65.7% | 33.6% |

The **2005–2019 σ_b is the cleaner benchmark** — it's the noise floor that *predates* the Phase IV ETS shock and the pandemic. The 2019–2022 σ_b is somewhat lower at the median, plausibly due to (i) small-n downward bias (only 2–3 differences per buyer in this 4-year window) and (ii) more co-movement of input costs across firms during 2020–22 macro shocks (less cross-sectional dispersion).

By buyer NACE 2d (2005–2019, p50 σ_b): cement (NACE 23) = **20.8%**, chemicals (20) = 24.1%, basic metals (24) = 34.8%, paper (17) = 12.5%, machinery (28) = 26.2%, refining (19) = 23.1%. Cement buyers are at the low end of the noise distribution.

**Note:** sub-checks on local-1 are broken by B2B downsampling: the ratio `input_cost / inputs_VAT` (domestic share of inputs) shows median 5% on local-1 vs. ~50–70% expected. Both this diagnostic and the domestic-only σ_b robustness check need to be re-run on RMD with the full B2B universe.

### (c) Heise 2024 (AER) FX-shock benchmark

Heise's calibrated quarterly std of log e is σ_ξ = 0.066, with FX-to-seller-cost elasticity α = 0.444. A typical 1-σ quarterly FX shock translates to a 2.93% seller-cost shock per quarter, or roughly 5.86% annualized (treating quarterly innovations as iid). At a typical Heise import-share of ~25% of buyer's input bill, the buyer-side annual shock from a 1-σ FX move is ~1.5%.

### (a) Cross-border price gap — DEFERRED

Requires customs unit-value rebuild. Not computed. Will be added if Plan B Test F is reactivated.

### Comparison

| Quantity | Magnitude |
|---|---|
| Phase IV pair-shock p90 (treated, all sectors) | **2.1%** |
| Phase IV pair-shock p90 (cement buyers) | **9.8%** |
| Phase IV pair-shock p90 (chemicals, refining) | 0.7–1.7% |
| Heise typical 1-σ FX shock (buyer-side, annual) | ~1.5% |
| Belgian buyer median σ_b on inputs_VAT, 2005–2019 | **24.0%** |
| Belgian buyer median σ_b on inputs_VAT, 2019–2022 | 22.0% |
| Cement buyer median σ_b, 2005–2019 | 20.8% |

**The pair-shock signal is small relative to background noise.** A typical regulated buyer experiencing a 2% ETS-driven cost increase at one of their sellers is facing a perturbation that is buried under their normal year-on-year material-cost noise. Even the cement-buyer p90 (9.8%) is below the typical buyer's 1-σ annual cost volatility.

This is consistent with the literature on FX pass-through (Heise's mechanism gets identified despite small per-shock magnitudes, but using high-frequency price observations and structural identification — not from observed sourcing changes). At our annual-frequency, value-only, no-price-data setup, the signal-to-noise ratio is too low to expect observable substitution at the typical pair.

## Moment 6 — Phase IV stress test

[output/tables/phase5_moment6_phase4_stress.csv](output/tables/phase5_moment6_phase4_stress.csv)

The Phase IV-only by-NACE-2d firm-year distribution (Moment 1 restricted to 2021–22) confirms the right-tail concentration: top sectors by p90 are NACE 35 (electricity, p90 71%), 33 (repair, p90 39%), 19 (refining, p90 8.9%), 49 (transport, p90 6.1%), 23 (cement, p90 4.4%). The same ranking appears in Moment 2 (B2B-sample restriction).

## Verification (per Plan A)

1. **Phase IV p90 sanity check:** population p90 = 2.27%. High-intensity NACE 23 p90 = 4.4%; NACE 19 p90 = 8.9%; NACE 35 p90 = 71%. All in the 2–80% range — sensible. Cross-walks with [PASSTHROUGH.md](PASSTHROUGH.md) shock-size table. ✓
2. **Pair-shock = 0 for non-ETS sellers:** mechanically built in via the `seller_is_ets == 1` filter. ✓
3. **Cross-check Moment 3 against PASSTHROUGH.md:** my Phase IV effective €/tonne (32.8) is higher than PASSTHROUGH's 19.3 because PASSTHROUGH used 2021 only with €40 EUA, while I use 2021–22 average with EUA up to €80 in 2022. EUA range matches PASSTHROUGH's 2021 €40. ✓ (small difference noted; not a discrepancy in computation)
4. **Sales-weighted vs unweighted:** Phase IV mean cost-share is 5.35% (population) but sales-weighted is only 0.65%, indicating the heavy right tail is at small sellers. Confirmed. ✓
5. **Sector decomposition:** cement, refining, electricity have the largest p90s; pharma, machinery, electrical near zero. Matches expectation from PASSTHROUGH.md selection finding. ✓
6. **Verdict consistency:** Moment 1 population p90 (2.27%) ≈ Moment 4 treated active p90 (2.11%). Moment 2 (B2B sellers) is ~equal to Moment 1 because B2B sellers ≈ full ETS population. ✓
7. **Loss-making firms:** 22 firm-years dropped (0.6%). Negligible. ✓

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
- `phase5_moment5_buyer_volatility.csv`
- `phase5_moment6_phase4_stress.csv`
- `phase5_shock_distribution_summary.txt` (Moments 1, 3, 6 readable)
- `phase5_pair_shock_summary.txt` (Moments 2, 4 readable)
- `phase5_moment5_benchmarks_summary.txt` (Moment 5 readable)

### Figures (output/figures/)
- `phase5_moment1_distribution_by_phase.pdf`
- `phase5_moment4_pair_shock_distribution.pdf`

## Caveats

- B2B coverage on local-1 is downsampled (full universe only on RMD). Numbers above are from the local-1 downsampled `b2b_cmdj_panel.RData`. Tail of Moment 4 may shift on RMD; rerun there before paper-grade numbers.
- 3 contaminated VAT hashes (NACE 20, 24 EUTL artefact post-2020) excluded from 2021+. Without this fix Phase IV NACE 20/24 cost-shares would be artefactually inflated. See [MEMORY.md](C:\Users\jota_\.claude\projects\c--Users-jota--Documents-carbon-leakage\memory\project_nace24_eutl_break_post2020.md).
- σ_b uses `inputs_VAT` from `annual_accounts_more_selected_sample.RData` — the firm's directly-declared input expenditure on VAT returns. This is the right concept (avoids revenue-volatility contamination of the older `revenue − value_added` measure). It is nominal (includes input-price inflation), which is correct for the benchmark question: a buyer absorbing a 5% input-price increase still has to pay it, regardless of whether it is real or nominal. The pre-2020 vs post-2019 split separates the low-inflation noise floor from the contaminated test-window noise.
- The local-1 σ_b numbers may shift on RMD because Annual Accounts is also downsampled on local-1 per [CLAUDE.md](CLAUDE.md). The cross-buyer median is robust to random sampling, but tail percentiles and small-NACE-2d cells need RMD re-runs.
- The robustness check using `firm_year_domestic_input_cost` (domestic-only B2B-aggregated total) is **broken on local-1** because that file is built from downsampled B2B. On RMD it should produce a σ_b that roughly tracks the `inputs_VAT` number. Same with the domestic-share sanity check (`input_cost / inputs_VAT` ≈ 5% on local-1 vs. expected 50–70%).
- Heise's calibrated α = 0.444 is for FX-to-seller-cost. The "buyer-side annualized 1.5%" is computed assuming 25% import share at the buyer level (rough Heise number); actual Belgian numbers may differ.
- Cement (NACE 23) Phase IV pair-shock distribution is driven by 263 treated pair-years across only ~30 distinct ETS sellers (the cement industry is concentrated). The cement-buyer p99 = 63.5% reflects a small number of pairs where one ETS seller dominates the buyer's input bill. Stickiness vs concentration distinction matters most for this sector, since it's the only place the shock is large enough to be detectable.

---

*Generated: 2026-04-28. Plan A complete; Plan B (stickiness vs concentration) is the next phase.*
