# China Shock Diagnostics — Findings

## Verdict at the head

We instrumented Belgian input prices with a Bartik-style shift-share built from China's expansion of exports into the rest of the EU (2002–2012). The instrument is strong: the shifter has substantial cross-product variation and transmits to Belgian unit values with an F-statistic of 195. Belgian buyers do tilt their direct imports toward China where the shock hits hardest. But on full RMD B2B, the load-bearing test of domestic substitution — Belgian buyers reducing the share of input expenditure they direct to Belgian sellers in China-shocked categories — returns a small negative point estimate (β = −0.103) that is not statistically distinguishable from zero (p = 0.27, 95% CI [−0.29, +0.08]). The China shock turns out to be **broader but not uniformly larger** than the carbon shock at the buyer level; at the high-exposure tail (p99) the carbon shock dominates, while at p50–p95 the China shock dominates. The original ambition — use a much-bigger shock to identify the substitution elasticity that the carbon shock was too small to see — does not survive contact with the data. What survives is a clean first stage and an ambiguous reduced form, both consistent with the Belgian-B2B-stickiness reading of the leakage paper.

---

## 1. Motivation

[B2B_LEAKAGE.md](B2B_LEAKAGE.md) documents a robust null leakage finding for the EU ETS at the **seller** level: high-ETS-intensity Belgian sellers do not lose output share to low-ETS-intensity sellers within the same NACE 4d. [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md) showed that the carbon-pricing cost shock at the typical Belgian ETS pair-year is small (pair-shock-total p90 = 1.16% in Phase IV, signal-to-noise ≈ 0.08σ at population p90). The buyer-side counterpart — do *buyers* substitute away from high-ETS-intensity sellers? — remains an open question that Plan B Test G is designed to address.

Two interpretive risks for the seller-side null:

1. **Shock too small.** If most ETS sellers face a shock that is small relative to ordinary input-cost noise, buyers have no reason to act. A null in that case is uninterpretable.
2. **Substitution requires a long horizon.** Peter & Ruane (2025) shows long-run elasticities of substitution between intermediate inputs are roughly 5× short-run estimates (θ_LR ≈ 2.47 vs. θ_SR ≈ 0.5), and that recovering the long-run requires a permanent shock with a 7+ year horizon.

The China shock — the rest of the world's adjustment to China's WTO accession (Dec 2001) and subsequent export-supply expansion — is a permanent shock with a full 7+ year post-period inside our 2002–2022 data window. The motivating question:

> **Does a clean, well-identified, long-run shock to relative input prices induce Belgian buyers to substitute their input mix?**

If yes, the substitution channel is alive in Belgian B2B and the carbon-leakage null is most plausibly a "shock too small" finding for the carbon shock specifically. If no, Belgian B2B is sticky enough to suppress substitution even under a clean and large shock — a stronger finding about Belgian B2B as an institution.

---

## 2. Data

### 2.1. Sources

| Data | Source | Granularity | Coverage | Where |
|---|---|---|---|---|
| Bilateral trade flows | BACI HS02 V202601 (CEPII) | exporter × importer × HS6 × year | 2002–2024 | RMD + local-1 |
| Belgian B2B transactions | NBB | seller-VAT × buyer-VAT × year | 2002–2022 (full universe on RMD; downsample on local-1) | RMD = full, local-1 = downsample |
| Belgian Annual Accounts | NBB | firm × year | 2000–2022 | RMD = full, local-1 = downsample |
| HS / CN8 → NACE 4d concordance | repo `data/concordances/cn8_to_nace4d.csv` | CN8 × year | 1995–2018 | repo |

BACI gives bilateral trade values and quantities at HS6 product level. Belgian B2B gives intra-Belgium firm-pair flows. Annual Accounts gives firm characteristics, including total declared input bill (`inputs_VAT`) used as the denominator for buyer-level shock magnitudes. CN8 → NACE 4d is the concordance that lets us aggregate HS6-level shifters to the NACE 4d level B2B records.

### 2.2. Constructed objects

```
ChinaShare_{k,t}    = v_China,EU26-excl-BE,k,t / v_total,EU26-excl-BE,k,t
ΔChinaShare_k       = ChinaShare_{k,2012} − ChinaShare_{k,2002}

UV_Belgium,k,t,src  = v_src->BE,k,t / q_src->BE,k,t
                       (src ∈ {China, non-China})

Δlog UV_BE,k,src    = log(UV_Belgium,k,2012,src) − log(UV_Belgium,k,2002,src)

importance_weight_k = v_total,EU26-excl-BE,k,2002 / Σ_k v_total,EU26-excl-BE,k,2002
```

The "EU-26" importer set is the EU-27 as of 2007 minus Belgium, fixed across years (Croatia, which joined in 2013, is excluded so the importer set is stable across the 2002–2012 window). Importance weights are the standard P&R/Borusyak convention: each HS6 contributes to estimates in proportion to its 2002 share of EU-26 trade value.

---

## 3. Specifications

We ran four specifications, each addressing a distinct question.

### 3.1. E1 — Shifter dispersion

Descriptive: distribution of `ΔChinaShare_k` across HS6 products, with importance weights. The diagnostic question is whether the shifter has enough cross-product variation to support an instrumental-variables design downstream. P&R (2025) Appendix Figure B.3 is the direct analog.

### 3.2. E2 — Belgian first stage (price transmission)

```
Δlog UV_Belgium,k,src = α + ψ_src · ΔChinaShare_k + ε_k
```

For each HS6 product k (one observation per product), regress the change in Belgian unit value on the EU-26 ChinaShare gain. WLS with 2002 importance weights. Two outcomes:

- **`src = China`**: Belgian unit value of imports from China only — the *direct* price channel.
- **`src = non-China`**: Belgian unit value of imports from all non-Chinese sources — the *pro-competitive* channel, where third-country suppliers cut prices to retain Belgian customers under Chinese competition.

The non-China slope is the load-bearing parameter. It tells us how much the China shock shifted the price of the alternative-source basket — which is the relative-price signal Belgian buyers see on inputs they source from non-Chinese (including domestic Belgian) suppliers.

We ran the regression at four horizons against the 2002 baseline: 5-yr (→2007), 10-yr (→2012), 15-yr (→2017), 20-yr (→2022).

### 3.3. E3 — Reduced-form substitution

After aggregating the HS6 shifter to NACE 4d via the repo concordance (with HS6 trade-value weighting), three regressions, all WLS with NACE-4d 2002 EU-26 trade value as the importance weight:

**Version A (level outcome):**
```
Δlog (B2B sales by Belgian sellers in NACE 4d n) = α + β_A · ΔChinaShare_n + ε
```
For each input-NACE-4d, did Belgian sellers' total sales grow more or less? Caveat: this absorbs aggregate GDP growth in α; only the cross-NACE-4d slope identifies a differential.

**Version A2 (share outcome — load-bearing):**
```
Δ (Belgian-seller share of expenditure on NACE 4d n) = α + β_A2 · ΔChinaShare_n + ε
```
where Belgian-seller share = `b2b_sales / (b2b_sales + total_imports)` for that NACE 4d. Did the Belgian-source share of buyer expenditure on inputs from category n fall more for China-shocked categories? This is the substantive substitution outcome.

Currency: B2B is in EUR, BACI imports are in thousand USD. We convert BACI to EUR using ECB annual-mean rates (2002: 0.9456 USD per EUR; 2012: 1.2848 USD per EUR) before computing shares.

**Version B (sanity check):**
```
Δ (China share of Belgian imports of NACE 4d n) = α + β_B · ΔChinaShare_n + ε
```
Did Belgium's import sourcing tilt toward China where the rest of the EU did?

### 3.4. D2 — Buyer-level magnitude

For each Belgian buyer b in 2002, the % of total input cost that the China shock implies through the B2B side, mirroring SHOCK_MAGNITUDE.md's `buyer_total_shock`:

```
china_buyer_shock_b2b_b = Σ_n (b2b_spend_{b,n,2002} / inputs_VAT_{b,2002})
                              × ψ × ΔChinaShare_n
```

Components:
- `b2b_spend_{b,n,2002}` = sum of corr_sales from Belgian sellers in NACE 4d n to buyer b in 2002.
- `inputs_VAT_{b,2002}` = buyer b's total declared input bill in 2002 — same denominator as `pair_shock_total` for the carbon shock.
- `ψ = −1.34` from E2's non-China 10-yr first-stage slope.
- `ΔChinaShare_n` = NACE-4d-aggregated shifter from E3.

The Customs-side of the buyer's exposure (direct imports from China) is omitted in this version: it requires firm-level Customs at HS6/CN8 not yet on local-1, and adds a separate channel that operates through a different ψ.

---

## 4. Identification

### 4.1. The Bartik / shift-share argument

The instrument is `ΔChinaShare_k` for HS6 product k, where the share is computed over EU-26 importers (excluding Belgium). The identifying assumption is that China's expansion of exports to the rest of the EU is driven by **Chinese supply-side factors** (productivity, wage growth, exchange rate, policy) rather than by **Belgian demand**. Under that assumption the shifter is exogenous to Belgian-specific outcomes.

This is the standard ADH (Autor–Dorn–Hanson 2013) move adapted to the input-product level. ADH instrumented US commuting-zone Chinese-import exposure with imports into 8 other high-income countries; we instrument Belgian Chinese-import exposure with imports into the 25 other EU countries excluding Belgium. The intuition is the same: Belgium is small enough (~3% of EU GDP) that Belgian-specific demand shocks for HS6 product k cannot meaningfully drive Chinese export expansion across all 25 other EU countries.

The identification rests on **exogeneity of the shifts** in the sense of Borusyak–Hull–Jaravel (2022): we don't require shares to be exogenous; we require the cross-HS6 variation in ChinaShare gains to be uncorrelated with whatever is in the error term of our outcome equation. Diagnostic: BHJ require the shifter to be dispersed, the effective number of independent shifts to be large, and no single shift to dominate. E1 confirms all three (effective number of shifts = 191, max single weight = 4.1%, weighted SD = 8.85pp — comparable in identifying power to P&R's tariff shifter despite a smaller per-shift dispersion).

### 4.2. Threats to identification

The shift-share design handles **simultaneity** (Belgium not driving the shifter) but not all **common shocks** that affect China and Belgium in parallel. Three threats worth flagging:

- **Common productivity shock**: a global shift in the productivity of producing HS6 k could cause both Chinese expansion (because China captures the new productivity) and Belgian seller decline (because Belgian sellers are stuck in the now-low-productivity industry). If this is what drives our results, the slope is not "Belgian buyer substitution induced by Chinese price competition" — it is "common cause moving both LHS and RHS." The standard literature defense is that prices fall as well as quantities (E2 directly addresses this — China gaining share lowers Belgian *prices*, which is harder to explain via a common productivity story).
- **Spillover through Belgian export markets**: Belgian sellers export to other EU countries, where they now compete with China. China's gain in those markets compresses Belgian sellers' overall sales, including their B2B sales to Belgian buyers, even if Belgian buyers themselves don't substitute. This contaminates Version A but not Version A2 (which uses the share, normalizing out aggregate Belgian-seller-revenue effects).
- **Direct Belgian contamination of the shifter**: Belgium is in the EU customs union; if Belgian buyers were a meaningful share of EU-wide imports, ChinaShare_EU would partly *be* driven by Belgian demand, contaminating the shifter. Belgium is ~3% of EU GDP, so this is small, but not zero.

The fix for these is the standard robustness toolkit: pre-trend tests, sub-period heterogeneity, alternative shifters that more clearly isolate Chinese supply (e.g., real exchange rate × China's pre-period export specialization). We have not run these; they would be checklist items in an eventual paper write-up.

---

## 5. What is tautological and what is not

This is worth being explicit about because the three E3 regressions have very different identification credibility.

### 5.1. Version B is partly mechanical

Version B regresses ΔChinaShare in *Belgian* imports on ΔChinaShare in *EU-26* imports. Belgium is one of 26 EU countries operating inside a customs union, importing from the same Chinese exporters under the same trade rules. The two share variables track each other almost by construction. A positive slope on this regression doesn't require any Belgian-buyer substitution decision — it requires only that Belgian import flows track EU import flows, which they trivially do.

Reading B as evidence of substitution is wrong. The correct reading is: B is a **coherence check** that the data is internally consistent. A null on B would mean Belgium is somehow decoupled from EU import patterns, which would be a red flag for the data or measurement. A positive slope close to 1 on B is reassuring but uninformative; a positive slope of 0.15 (what we got) is consistent with Belgium tracking the EU imperfectly, possibly because some EU countries (Eastern Europe, southern Mediterranean) tilted toward China more aggressively than Belgium did.

### 5.2. Versions A and A2 are not tautological

Versions A and A2 regress **Belgian-domestic B2B** outcomes on the EU-26 shifter. These transactions occur between two Belgian VAT numbers and have no mechanical relationship to Chinese trade flows in the rest of the EU. The link between the LHS (Belgian B2B sales / share) and the RHS (EU ChinaShare gain) is **only through firm-level decisions**: Belgian buyer chose to keep or replace their Belgian supplier, plausibly in response to changes in the cost of alternatives that the China shock affected.

A flat slope on A2 is consistent with the data and informative — it would say Belgian buyers don't reweight their Belgian-seller mix even when the cost of alternatives moves. A negative slope means buyers do reweight. There is no mechanical reason A2 must take any particular value.

### 5.3. D2 is purely descriptive

D2 multiplies the buyer's 2002 input-mix shares by ψ × ΔChinaShare to compute an "implied input-cost shock." This is descriptive — it tells us the magnitude of the cost shock the buyer would face if E2's first-stage relationship held perfectly at the buyer level, without testing whether buyers responded. D2 has no identification content of its own; it inherits whatever identification E2 provides for ψ.

---

## 6. Results

All regressions reported below use the **full RMD B2B universe** (78,167 buyers, all sectors).

### 6.1. E1 — Shifter dispersion

| Statistic | Value | P&R benchmark |
|---|---|---|
| HS6 codes in headline (after 1% lower-trade trim) | 4,982 | 297 ASICC 5-digit |
| Trade-weighted SD of ΔChinaShare | **8.85 pp** | 36 pp (tariff change) |
| Effective number of shifts (1/Herfindahl on importance weights) | **191** | 33 |
| Largest single-HS6 importance weight | 0.041 | 0.101 |
| Weighted mean of ΔChinaShare | +5.0 pp | — |
| Weighted p90 | +18.6 pp | — |
| Weighted p99 | +37.6 pp | — |

The shifter is more diffuse than P&R's: lower per-shift dispersion (4× smaller SD), but 6× more effective shifts. First-stage information content (variance × N_eff) is in the same ballpark as P&R, achieved through a different combination of dispersion and sample size.

Source: [output/figures/phase6_eyeball_e1_shifter_dispersion.pdf](output/figures/phase6_eyeball_e1_shifter_dispersion.pdf), [output/tables/phase6_eyeball_e1_summary.txt](output/tables/phase6_eyeball_e1_summary.txt).

### 6.2. E2 — Belgian first stage

Headline (Non-China, 10-yr horizon, 2002→2012):

| Quantity | Value | P&R benchmark |
|---|---|---|
| ψ (slope, fractional units) | **−1.338** (SE 0.096) | — |
| Slope per pp ΔChinaShare | **−1.34%** | −1.59% (per pp tariff cut) |
| F-statistic | **195.4** | 18.0 |
| N (HS6 products) | 4,779 | 297 plant × input |
| R² | 3.9% | — |
| 95% CI on ψ | [−1.53, −1.15] | — |

Plain-language reading: a 10-pp gain in China's share of EU-26 imports of HS6 product k predicts a **13.4%** decline in the Belgian unit value of imports of that HS6 from non-Chinese sources, over the 10-year horizon. The first stage is overwhelmingly strong by Stock-Yogo conventions.

Horizon dependence:

| Horizon | Non-China ψ | F |
|---|---|---|
| 5-yr (→2007) | −1.149 | 149 |
| **10-yr (→2012)** | **−1.338** | **195** |
| 15-yr (→2017) | −0.427 | 22 |
| 20-yr (→2022) | **−1.895** | **353** |

The 20-yr slope is steepest, consistent with P&R's prediction that long-run responses are larger. The 15-yr horizon is anomalously weak (2017 is mid-cycle globally; unit values reflect commodity-price cycles).

Source: [output/figures/phase6_eyeball_e2_first_stage.pdf](output/figures/phase6_eyeball_e2_first_stage.pdf), [output/figures/phase6_eyeball_e2_horizons.pdf](output/figures/phase6_eyeball_e2_horizons.pdf), [output/tables/phase6_eyeball_e2_summary.txt](output/tables/phase6_eyeball_e2_summary.txt).

### 6.3. E3 — Reduced-form substitution (full RMD B2B)

| Spec | β | SE | F | p | N | 95% CI |
|---|---|---|---|---|---|---|
| Version A (Δlog level) | −1.194 | 1.240 | 0.93 | 0.34 | 184 | [−3.64, +1.25] |
| **Version A2 (share)** | **−0.103** | **0.093** | **1.21** | **0.27** | **183** | **[−0.29, +0.08]** |
| Version B (import share) | +0.146 | 0.038 | 14.7 | 0.00017 | 209 | [+0.07, +0.22] |

**A2 is the load-bearing test.** The point estimate is in the expected direction (negative — Belgian-seller share of expenditure falls in China-shocked NACE 4ds) but is not statistically distinguishable from zero. The 95% CI [−0.29, +0.08] is wide enough to include both moderate negative slopes and zero.

The A2 point estimate of −0.103 has an interpretable magnitude: a 10-pp gain in EU-26 ChinaShare predicts a 1-pp fall in the Belgian-seller share of Belgian-buyer expenditure on that NACE 4d. For the typical NACE 4d (median ΔChinaShare ≈ 5pp), this would imply a 0.5-pp fall in Belgian-source share over a decade — economically modest if real, statistically indistinguishable from zero given the data.

Version B confirms that Belgian imports tilt toward China where the rest of the EU did, with a slope of 0.15 (Belgium tracks the EU shift but at ~15% of the EU magnitude — possibly because some EU countries rerouted toward China more aggressively than Belgium).

Source: [output/figures/phase6_eyeball_e3_reduced_form.pdf](output/figures/phase6_eyeball_e3_reduced_form.pdf), [output/tables/phase6_eyeball_e3_summary.txt](output/tables/phase6_eyeball_e3_summary.txt).

### 6.4. D2 — Buyer-level magnitude (full RMD B2B)

|  | Carbon shock (Phase IV, annual) | China shock (10-yr LR cumulative) | China annualized | Apples-to-apples (annualized) |
|---|---|---|---|---|
| N buyers | 15,442 | 78,167 | — | — |
| p50 (abs) | 0.000% | 0.088% | 0.0088%/yr | China dominates (carbon = 0) |
| p90 (abs) | 0.000% | 1.42% | 0.142%/yr | China dominates |
| p95 (abs) | 0.031% | 2.43% | 0.243%/yr | China is **~8× carbon** |
| p99 (abs) | **6.90%** | 6.40% | 0.640%/yr | **carbon is ~10× China** |
| mean (abs) | 0.358% | 0.588% | 0.0588%/yr | carbon is ~6× China |

Manufacturing-buyer subset (N = 12,689):
- p90 = 2.66% cumulative ≈ 0.27%/yr
- p99 = 8.84% cumulative ≈ 0.88%/yr

Top buyer-NACE 2d cells by p90 of |China shock|:

| NACE 2d | What it is | p90 | p99 |
|---|---|---|---|
| 23 | Other non-metallic minerals (cement, glass, ceramics) | 5.77% | 12.5% |
| 14 | Wearing apparel | 5.33% | 16.7% |
| 31 | Furniture | 5.33% | 12.2% |
| 13 | Textiles | 4.77% | 11.8% |
| 16 | Wood products | 3.48% | 7.74% |
| 22 | Rubber and plastic | 2.70% | 5.80% |

Source: [output/figures/phase6_d2_china_vs_carbon_shock.pdf](output/figures/phase6_d2_china_vs_carbon_shock.pdf), [output/tables/phase6_d2_china_shock_magnitude.txt](output/tables/phase6_d2_china_shock_magnitude.txt), [output/tables/phase6_d2_china_vs_carbon_comparison.csv](output/tables/phase6_d2_china_vs_carbon_comparison.csv).

---

## 7. Interpretation

### 7.1. The first stage works cleanly

E2 is a strong, well-identified first stage by any standard in the literature. F = 195 is roughly 10× P&R's F = 18, achieved through 16× more observations at a comparable per-observation slope magnitude (−1.34% vs −1.59% per pp). The pro-competitive channel is alive in Belgium: when Chinese export supply expanded, Belgian buyers saw their non-Chinese supplier basket get cheaper at a rate comparable to what India's tariff liberalization induced for domestic Indian suppliers.

This is independently a methodological contribution. To our knowledge no published paper has run this first stage for Belgium; the result is comparable to the cross-country literature and validates the China shock as a credible identifying instrument for Belgian-input-cost variation.

### 7.2. The reduced form is ambiguous

A2's point estimate (−0.103, p = 0.27, 95% CI [−0.29, +0.08]) is consistent with three readings:

1. **Substitution exists but is small.** Belgian buyers do reduce the Belgian-source share of expenditure on China-shocked NACE 4ds, but at an economically modest rate (~1pp decline per 10pp ChinaShare gain) that is hard to detect at N=183 cells. Under this reading, the point estimate is genuine and the noise is just sampling variability around it.
2. **No substitution.** The point estimate is statistical noise around a true zero. Belgian buyers don't reweight their Belgian-seller mix even under a clean and large LR shock.
3. **Heterogeneous substitution.** β = −0.103 is a population average that masks meaningful negative slopes in some sectors and zero/positive slopes in others. NACE-4d aggregation washes out the heterogeneity.

The data does not distinguish among these. The CI is wide, and the cross-sector heterogeneity has not been examined.

### 7.3. The magnitude comparison is more nuanced than expected

The original framing of the project assumed the China shock would be much larger than the carbon shock. D2 disconfirms that uniformly: at the high-exposure tail (p99) the carbon shock dominates by ~10× annualized, because the carbon shock concentrates on a small set of cement/steel/refining buyers. At p50–p95, the China shock dominates because the carbon shock is essentially zero for non-regulated buyers.

The two shocks tag **different** Belgian buyers:
- Carbon shock: cement (NACE 23), basic metals (24), refining (19), chemicals (20).
- China shock: textiles (13), apparel (14), wood (16), furniture (31), and — interestingly — also cement (23), via cement firms' machinery and material imports.

For the leakage paper, the most useful framing is no longer "China is a bigger shock" but "China is a different shock." The two shocks are complementary in their coverage of Belgian B2B, and a finding that holds across both is a stronger statement than either alone.

### 7.4. Implication for the leakage paper

The seller-side null in [B2B_LEAKAGE.md](B2B_LEAKAGE.md) is now joined by a buyer-side null on a complementary shock that doesn't share the carbon shock's "shock too small" interpretive risk:

- The China shock is a clean, well-identified, long-run permanent shock with a strong first stage on Belgian prices (F = 195).
- It moves the Belgian-source share of expenditure for the typical NACE 4d in the predicted direction, but by an economically modest amount that is statistically indistinguishable from zero on full RMD B2B.

Two readings of the joint pattern are consistent with the data:

- **Stickiness**: Belgian B2B is sticky enough that even a clean LR shock with comparable price magnitude does not induce meaningful substitution. The carbon-leakage null is then part of a broader pattern of Belgian-B2B-substitution-resistance, not specific to the carbon shock. This is the Heise-style relational-capital reading.
- **Concentration / no alternatives**: Belgian sellers within an input-NACE-4d are sufficiently differentiated that buyers can't substitute even when the relative cost of alternatives moves. The China-shock null then says the same thing as the carbon-shock null.

The data we have so far does not distinguish between these. Plan B's full battery (Tests A–C) is designed to do that distinguishing for the carbon shock; the analog for the China shock would require firm-level work (D1 + a θ regression). Whether that effort is worth investing depends on whether the substantive paper-level claim ("Belgian B2B doesn't substitute under either shock") is more valuable than a clean θ estimate from one shock alone.

---

## 8. What's settled, what isn't, and next steps

### Settled

- The China shock has substantial cross-product variation in the EU-26 (E1).
- That variation transmits to Belgian unit values via both the direct and pro-competitive channels (E2). The first stage is strong and comparable in magnitude to P&R's tariff-instrument first stage.
- Belgian imports tilt toward China where the EU does, at attenuated magnitude (E3 Version B).
- The buyer-level B2B-side China shock distribution is broader but not uniformly larger than the carbon shock (D2). The two shocks tag different Belgian buyers.

### Not settled

- Whether Belgian buyers substitute *Belgian* sellers under the China shock at the buyer level (E3 Version A2). The point estimate is in the right direction but the CI includes zero with wide tails.
- Whether the same null holds for the carbon shock at the buyer level. Not yet tested (Test H from [SHOCK_AND_SUBSTITUTION_PLAN.md](SHOCK_AND_SUBSTITUTION_PLAN.md)).
- Whether sector-level heterogeneity is hiding meaningful substitution in some NACE 2d cells.
- Whether finer aggregation (NACE 3d, firm-level) or alternative outcome specifications would tighten the A2 estimate enough to distinguish among the three readings.

### Next steps, in order of cost-effectiveness

1. **Build the carbon-shock buyer-side analog (Test H).** Parallel structure to E3 Version A2 but using `firm_cost_share` × Post interacted with NACE-4d aggregation as the shifter. About 2 days of work using existing infrastructure. This is the cheapest piece of new evidence and is symmetric to the China-shock A2 result, so the joint pattern is interpretable as a Belgian-B2B claim rather than a single-shock claim.

2. **Run sector-level heterogeneity on E3 Version A2.** Decompose β = −0.103 into NACE-2d-specific slopes; identify whether any sector tail shows clear substitution that the population average is masking. About 1 day of work.

3. **Decide whether to invest in D1 / firm-level θ estimation.** Only if Test H also returns a null (joint LR-null is the headline) or only if the heterogeneity decomposition reveals a clear sectoral pattern worth identifying θ off. Otherwise the eyeball-level findings already tell the substantive story.
