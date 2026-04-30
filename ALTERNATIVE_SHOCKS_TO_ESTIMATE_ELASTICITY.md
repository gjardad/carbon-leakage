# Alternative Shocks to Estimate Elasticity of Substitution — Plan

## Scope

This plan documents the search for shocks that generate sufficient *price dispersion across suppliers* to identify a meaningful elasticity of substitution among Belgian firms. The carbon-pricing and China shocks are the two designs we have invested in to date; both have produced well-estimated nulls or imprecise small elasticities. The plan now also covers candidate alternative shocks (anti-dumping duties, others to be added) so we can document findings across multiple identifying designs in one place rather than maintaining a per-shock plan file.

The bulk of the document remains the China-shock diagnostics, since that work is furthest along. New sections at the bottom cover (i) anti-dumping duties as a future identifying design and (ii) a revisited China design that pivots from substitution-among-Belgian-suppliers to elasticity-of-substitution-toward-Chinese-imports among Belgian importers, with explicit short-run vs long-run and importance-weighted heterogeneity tests.

## Context (China shock — original motivation, retained)

[SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md) established that the carbon-pricing shock is small at the typical Belgian ETS pair-year (pair-shock-total p90 = 1.16% in Phase IV; only cement-buyer cells reach signal-to-noise > 0.5σ). Peter & Ruane (2025) argues that **long-run** elasticities are an order of magnitude larger than short-run ones (θ_LR ≈ 2.47 vs θ_SR ≈ 0.5) and that estimating the LR requires a **permanent** shock with a **7+ year horizon**. Their identification: India's 1991 trade liberalization, with shift-share IV using 1989 input shares × 5-digit ASICC tariff cuts.

The closest Belgian analog within our 2002–2022 data window is **China's WTO accession (Dec 2001) and subsequent export-supply expansion** — permanent, large, asymmetric across input categories, full post-period coverage.

Before specifying a P&R-style θ regression, we need two diagnostics that the original P&R paper does not run (or runs only partially) but that are necessary for our setting:

1. **Within-sector variability in Belgian firm exposure to Chinese imports** — required for any specification with output-industry × year FE.
2. **Magnitude of the input-cost change attributable to the China shock** — required to avoid replicating the SHOCK_MAGNITUDE.md problem (well-identified shock that is too small to act on).

## Findings as of 2026-04-29 — what's been run, what survives

The eyeball stage and a first pass of D2 have been run. Three results that revise the framing of the project below:

**E1, E2 PASS (load-bearing for project viability).** The shifter has variation across HS6 products (trade-weighted SD = 8.85pp, effective shifts = 191) and transmits to Belgian unit values via the pro-competitive channel (non-China 10-yr ψ = -1.34 per fractional unit ≈ -1.34% per pp ChinaShare, F = 195, comparable to P&R's per-pp price elasticity). The China shock is a credible identifying shock for Belgian B2B prices.

**E3 (downsampled local-1) returns a partial:** Version A (Δlog domestic B2B sales) and Version A2 (Δ Belgian-seller share of expenditure) are both null but underpowered (N = 113, wide CIs); Version B (Δ China share of Belgian imports) is cleanly positive (F = 14.7). Belgian buyers tilt their direct imports toward China where the shock hits hardest, but the domestic-substitution channel may or may not be alive — RMD full-B2B re-run pending.

**D2 (B2B-side, local-1) revises the original motivation.** The China shock is **not uniformly larger than the carbon shock at the buyer level**. The two shocks have different distributional shapes:

- *Carbon shock* (Phase IV, annual): narrow but deep. p50 = p75 = p90 = 0% (most buyers have zero ETS exposure); concentrated at the top tail (p99 = 6.9%/yr). Tags cement / steel / refining / chemicals.
- *China shock* (10-yr LR, B2B-side cumulative): broad but shallow. Almost every buyer feels something via their NACE-4d input mix (p99 = 1.13% cumulative ≈ 0.11%/yr). Tags manufacturers with import-substitutable inputs.

At p95 (where both shocks have non-zero values) and on annualized basis, the two shocks are within 1.5× of each other. At the high-exposure tail, the carbon shock dominates by ~6× annualized. The two shocks tag *different* Belgian buyers.

**Implication for the project:**

1. The original "China is a much bigger shock, so a null on China cleanly identifies stickiness" framing is no longer supported. A null on E3 with the China shock is still subject to "shock too small" critiques in the same way the carbon-leakage null was, just for a different population of buyers.

2. What does survive: the China shock and the carbon shock tag *different* firms. If Belgian B2B substitution is observable anywhere in the data, the China shock at least gives a different test population to look at. A **joint** null across both shocks would be a stronger statement about Belgian B2B as an institution than either shock alone supports.

3. E2's clean first stage (F = 195) is a methodological contribution in its own right — the first published China-shock first stage on Belgian B2B-relevant data — independent of any second-stage substitution result.

4. The buyer-side analog of the existing seller-side leakage null is the open question — **noted as Test H in [SHOCK_AND_SUBSTITUTION_PLAN.md](SHOCK_AND_SUBSTITUTION_PLAN.md)**. Both shocks should now be run through Test H's framework once the data side is set.

**Decision: keep going with the China shock (run RMD E3, then re-evaluate).** Do not invest in D1 / full θ-estimation infrastructure until RMD E3 returns. If E3 confirms a domestic-side null on full B2B, the most defensible paper write-up is a *joint* LR-null across the two shocks rather than a clean elasticity estimate. If E3 turns negative-and-significant on full B2B, D1 / θ-estimation becomes worth building.

## Substitution framings the China shock can support

The leakage paper's existing question (within input-NACE-4d substitution between Belgian sellers in response to carbon costs) is **one** framing the China shock could speak to, but not the only one — and not necessarily the natural one for a trade shock. Three viable framings, ordered from closest-to-existing-paper to most P&R-faithful:

- **F1 — Within input-NACE-4d, between Belgian sellers** (Plan B Test G logic): China shock differentially squeezes Belgian sellers within the same input-NACE-4d. Buyers reweight toward less-China-exposed Belgian sellers. Substitution is within-Belgian-network, within-input-category. Identifies the same θ that the carbon-leakage null is informative about.
- **F2 — Between Belgian suppliers and direct Chinese imports** (ADH-on-inputs): the shock makes Chinese imports relatively cheaper. Buyer either keeps Belgian supplier or switches to direct import from China. Substitution is across the domestic/import margin, within-input-category. Closer to the trade-elasticity literature.
- **F3 — Between input categories** (P&R-faithful): firms reweight their input mix at the κ-broad-category level (materials, energy, services, capital, labor) in response to differential price changes across categories driven by the China shock. Identifies the **CES θ between broad input categories** — the actual P&R parameter.

The diagnostics below are agnostic to which framing is run downstream. Both diagnostics measure firm-level China exposure; the within-sector variance ratio (D1) tells us which fixed-effects structures are feasible, which in turn restricts the framings:

- F1 needs within (output-NACE-4d × year) variation in firm exposure → D1 must pass.
- F2 needs within (output-NACE-4d × year) variation but cross-supplier variation in import-vs-domestic substitutability — D1 still required, plus a B2B-vs-Customs decomposition not in this plan.
- F3 needs only cross-firm exposure variation (plant FE soaks up firm-level levels); doesn't require within-output-industry variation. Most permissive on D1 — F3 can survive a D1 fail.

The plan below establishes the diagnostics; the framing choice is downstream. Frame the diagnostics' decision rule jointly with this menu rather than assuming F1.

## Eye-balling pre-diagnostics (run before D1/D2)

### Why these come first

Cheap signal-per-unit-work, decisive go/no-go before committing to the concordance build. P&R themselves use an eyeball protocol: Figure 2 (non-parametric first-stage scatter), Appendix Figure B.3 (shock distribution), Appendix Figure B.4 (importance-weighted shock distribution). Their Figure 2 is the load-bearing visual — a single scatter that shows the shock actually moves prices and that the relationship is approximately linear. A flat or noisy version of the same scatter for Belgium would kill the China-shock approach before any expensive infrastructure is built.

The four eyeballs are ordered from cheapest-to-build to most-substantively-decisive.

### E1 — China shifter dispersion (BACI alone)

Distribution of `ΔChinaShare_k,EU-excl-Belgium,2002→2012` across HS6 products.

**Useful looks like:** SD comparable to or larger than 20pp (P&R's tariff SD was 41pp); heavy right tail of products with dramatic share gains.

**Killer:** SD < 5pp, or only a handful of products show big shifts. Then the cross-input variation is missing at the source — even before any Belgian-side measurement issue.

**Data needed:** BACI only. No concordance, no Belgian data. ~1 day after BACI download.

**Belgian-Customs-only preview:** can run today on RMD by computing the same distribution using *Belgian* imports rather than EU-excl-Belgium imports. This is endogenous to Belgian demand — exactly the contamination BACI's non-Belgian shifter fixes — but for a magnitude-and-shape preview it's directionally informative. If even the endogenous Belgian version shows tight clustering, BACI won't save it.

### E2 — Belgian first stage (BACI shifter → Belgian HS6 unit value)

**Direct analog of P&R Figure 2.** Each point = one HS6 product. X-axis = `ΔChinaShare_k` from BACI. Y-axis = `Δlog(P_Belgium,k)`, the change in Belgian-import unit value (or alternatively the unit value of Belgian imports from non-Chinese sources, capturing China's competitive squeeze on third-country prices). Weight by trade value (P&R-style importance weights). Trim 1% tails per P&R's measurement convention.

**Useful looks like:** linear-ish negative cloud; slope economically meaningful (e.g., `Δlog(P) ≈ -0.005 × ΔChinaShare_pp`, comparable in magnitude to P&R's `-0.16 × Δtariff_pp`); F-stat > 10 in the corresponding regression.

**Killer:** flat or noisy cloud. China import surge didn't move Belgian unit values → no first stage → no IV → entire approach dead.

**Data needed:** BACI + Belgian Customs (HS6 unit values). ~1 week.

**This is the decisive go/no-go.** If E2 fails, neither D1 nor D2 nor any framing rescues the project.

### E3 — Reduced-form: shock vs Belgian-supplier-share change

The eyeball P&R doesn't draw a figure for, but exactly what we want: do Belgian buyers actually reweight when the shifter hits?

**Definition:** for each HS6 product k (or NACE 4d aggregation), compute average `Δlog(B2B_sales_from_Belgian_sellers_in_k_to_domestic_buyers)` 2002→2012. Plot against `ΔChinaShare_k`. Each point = one product category, weighted by 2002 Belgian B2B sales in that category.

**Useful looks like:** clear negative slope, R² > 0.05 across HS6 (or > 0.15 across NACE 4d). Slope steeper for industrial-input categories than consumer goods. Slope magnitude ≈ `(1 - θ_LR) × ψ` where ψ is the first-stage from E2 — so for θ_LR ≈ 2.5 and ψ ≈ -0.005, slope should be roughly `-0.0075 per pp`.

**Killer:** flat cloud. Shock is real, prices move (E2 passed), but Belgian buyers don't reweight away from Belgian suppliers. **This is itself a useful finding** — the LR analog of the carbon-leakage null — but it means there is no usable θ to estimate, and the project pivots from "estimate the elasticity" to "document the LR null." Not a wasted effort, just a different paper.

**Data needed:** BACI + B2B + NACE↔HS6 concordance (rough version OK for eyeball). ~2 weeks.

### E4 — Heterogeneity preview: high-China-exposed buyers vs low

For each Belgian buyer, compute a simple `china_exposure_i` from 2002 NACE-4d input shares × NACE-4d-aggregated `ΔChinaShare`. Bin buyers into deciles of exposure. For each decile, plot the within-firm change in import share (direct Customs imports / total inputs) over 2002–2012.

**Useful looks like:** monotone increasing — high-exposure deciles substitute toward direct imports more than low-exposure deciles. The "domestic→imported" margin (F2 framing).

**Killer:** flat across deciles. Buyers don't reweight even on the import margin — combined with a flat E3, this is a strong null at the LR.

**Data needed:** BACI + Belgian Customs + Annual Accounts + rough NACE↔HS concordance. ~2 weeks.

### Decision rule for the eyeball stage

| E1 | E2 | E3 | Verdict |
|---|---|---|---|
| pass | pass | pass | Green light: proceed to D1, D2, then framing-conditional θ regression. |
| pass | pass | flat | Pivot: write the LR null paper. The shock is real and transmits to prices, but Belgian buyers don't substitute even at LR. Strong contribution. |
| pass | fail | — | Abandon the China shock. Belgian prices don't transmit the EU-wide signal. |
| fail | — | — | Abandon the China shock. The shifter isn't dispersed enough at source. |

E4 is a tiebreaker / channel-decomposition aid; not load-bearing for the go/no-go.

### Recommended sequence and timing

1. **Day 1–3: E1 preview** using Belgian Customs only (no BACI dependency). Cheap sanity check on shock magnitude.
2. **Week 1: BACI download and clean.** Filter to China-as-exporter, EU-excl-Belgium importers. Produces the proper shifter.
3. **Week 1–2: E1 proper + E2.** Decisive go/no-go on prices.
4. **Week 2–4: E3 + E4** (rough NACE↔HS concordance acceptable; refined version for D1/D2).
5. **If all four pass:** proceed to D1 and D2 with full concordance build.

## Diagnostic 1 — Within-sector variability in Belgian firm China exposure

### Definition of firm exposure

ADH-on-inputs, applied to Belgian Customs + B2B:
```
china_exposure_i = Σ_k (input_share_{i,k,2002} × ΔChinaShare_k,2002→2012)

input_share_{i,k,2002} = firm i's 2002 expenditure on HS6 product k / firm i's 2002 total inputs
ΔChinaShare_k         = Chinese share of EU-excl-Belgium imports of HS6 k, 2012 - 2002
```

The non-Belgian-EU shifter is the standard ADH exogeneity move — uses Chinese export-supply expansion as observed in other EU markets, decoupling from Belgian-specific demand.

**Input shares**: built from B2B (domestic supplier purchases by seller NACE 4d) + Customs (direct imports by CN8/HS6). The HS6 dimension comes from Customs (CN8 first-6-digits = HS6 by construction); the BACI shifter is at HS6 and joins via the same truncation. For mapping HS6/CN8 to NACE 4d we use the existing `data/concordances/cn8_to_nace4d.csv` already in the repo. **No new external concordance download is required** — the chain `BACI HS6 → truncate → CN8 → cn8_to_nace4d.csv → NACE 4d` resolves the mapping in a single composition.

### Moments

**M1.1 — Distribution of `china_exposure_i` overall.** p10, p25, p50, p75, p90, p99, mean. Establishes whether *any* firm has meaningful exposure.

**M1.2 — Variance decomposition.**
```
var(china_exposure_i) = var(E[china_exposure | output_NACE_4d]) + E[var(china_exposure | output_NACE_4d)]
                     =  between-NACE                          +  within-NACE
```
Report `within / total`. Specifications with NACE_4d × year FE (which F1 and F2 require) need this fraction to be substantial; F3 is robust to a low ratio.

**M1.3 — Within-NACE-4d SD of firm exposure.** For each output-NACE-4d, compute SD of `china_exposure_i` across firms. Report distribution across NACE 4ds (median NACE-4d-internal SD, IQR). Identify which NACE 4ds have most within-variation — those are where F1/F2 tests have power.

**M1.4 — Cell counts.** For each (output-NACE-4d × year) cell that would enter an F1/F2 regression, report number of firms and number with non-trivial exposure (`china_exposure_i > 0.05`, say). Cells with <5 exposed firms have no within-sector identifying variation.

### Decision rule for D1

| `within / total` variance ratio | F1, F2 verdict | F3 verdict |
|---|---|---|
| > 0.6 | Most variation is within-sector. Identification has plenty of power — proceed. | Proceed. |
| 0.3 – 0.6 | Mixed. Within-sector variation exists but tests will be noisy. Proceed but flag. | Proceed. |
| < 0.3 | China exposure is essentially a sectoral attribute. Output-NACE×year FE absorbs almost everything. Abandon F1/F2. | F3 still viable — only firm-level cross-sectional variation is needed. |

Cross-check: a `within / total` ≈ 0 result means firms in the same NACE 4d all source identically → either the data is too coarse to see input-mix differences (concordance failure) or Belgian production is very industry-stereotyped (substantive). Disambiguate by computing M1.2 with finer industry partition (NACE 4d × size bin, NACE 4d × region).

## Diagnostic 2 — Magnitude of input-cost change attributable to the China shock

### Two complementary versions

**M2.A — Direct exposure (ADH-style, no price needed).** For each firm, the share of its 2002 input bill in HS6 categories where China's share of EU-excl-Belgium imports rose by ≥ 20pp by 2012 ("heavily China-impacted categories"):
```
heavy_china_share_i = Σ_{k : ΔChinaShare_k ≥ 0.20} input_share_{i,k,2002}
```
Report distribution. Headline: **what fraction of firms have heavy_china_share > 30%?** That's the analog of "how much of your input bill was actually shocked."

**M2.B — Implied price change (P&R-analog, requires a price elasticity).** Translate the shift into a price change using either (i) within-Belgium HS6 unit-value changes, decomposed via an ADH first-stage `Δlog(P_k) = ψ × ΔChinaShare_k + ξ` with ψ estimated on EU-wide data, or (ii) a literature elasticity (Amiti–Itskhoki–Konings or similar):
```
implied_input_cost_shock_i = Σ_k (input_share_{i,k,2002} × Δlog(P_k))
```
Report distribution.

### Comparison to SHOCK_MAGNITUDE.md benchmarks

The whole point of this diagnostic is to compare to the carbon shock. Reuse the same benchmarks:

| Benchmark (from SHOCK_MAGNITUDE.md) | Carbon shock p90 (Phase IV) | China shock target |
|---|---|---|
| Pair-shock-total p90 | 1.16% | want > 5% |
| Cement-buyer p90 | 8.80% (signal-to-noise 0.68σ) | want comparable across many sectors, not just 1 |
| Buyer's σ of Δlog material costs | ~15% | implied shock should clear this for a meaningful subset |

### Moments

**M2.1** — Distribution of `heavy_china_share_i` (M2.A). p25, p50, p75, p90, p99, weighted mean.

**M2.2** — Distribution of `implied_input_cost_shock_i` (M2.B). Same percentiles. Report the first-stage ψ used and its source.

**M2.3** — Cumulated 7-year vs 1-year shock. P&R's whole point is that LR shocks dwarf SR shocks. Report the same diagnostic at 1-yr (2010→2011), 3-yr (2008→2011), 7-yr (2005→2012), and 10-yr (2002→2012) horizons. The 10-yr should be much larger.

**M2.4** — Sector breakdown. Report M2.1 and M2.2 by output-NACE 2d. Expected high-exposure sectors (per literature): textiles (NACE 13), apparel (14), leather (15), wood (16), basic metals (24), fabricated metal (25), electronics (26), machinery (28), furniture (31). Expected low-exposure: food (10), beverages (11), pharma (21), services. If the high-exposure sectors don't actually show high `heavy_china_share`, concordance is broken.

### Decision rule for D2 (revised after the 2026-04-29 run)

The original decision rule (top of this section, kept above for reference) assumed the China shock would be "much bigger than carbon" and used absolute-magnitude thresholds. The actual D2 result on local-1 (B2B-side, 10-yr LR; see [output/tables/phase6_d2_china_shock_magnitude.txt](output/tables/phase6_d2_china_shock_magnitude.txt)) does not support that framing: at the buyer level, the China shock is **broader** (almost every buyer feels something) but **shallower** (1.13% cumulative at p99 ≈ 0.11%/yr) than the carbon shock (Phase IV p99 = 6.9%/yr concentrated in cement/steel/refining buyers).

The revised reading:

| Outcome | What it implies | Action |
|---|---|---|
| China shock comparable to carbon at p95 (annualized), broader distribution | China shock isn't decisively larger; "use a bigger shock to settle magnitude" framing is dead. **But** China and carbon tag different firms, so the shocks are still complementary. | Proceed to E3 / RMD. Reframe project as joint-LR-null vs single-shock LR-null, depending on E3 result. |
| China shock dramatically larger than carbon at high tail (≥3× at p95+ on annualized basis) — **not what we found** | "China is the cleaner shock" framing is supported. | Would have justified investing heavily in the China-only paper. |
| China shock dramatically smaller than carbon everywhere (≤0.5× at all percentiles) — **not what we found** | China shock too small to identify substitution; abandon. | Would have ended the project here. |

**The first row is what D2 returned.** Project survives but with reduced ambition: a clean θ estimate from China alone is not the headline — the headline is whether Belgian B2B substitutes under either shock at the buyer level.

## Joint decision: D1 × D2 × framing (revised)

D2's actual reading isn't "pass / fail" — it's a third middle outcome ("China and carbon are comparable in magnitude, complementary in coverage"). The D1 × D2 grid below is updated to reflect this:

|  | D1 pass | D1 borderline | D1 fail |
|---|---|---|---|
| **D2 = "comparable to carbon"** (current state) | F1, F2, F3 all viable in principle, but expect underpowered θ given moderate shock. Framing emphasis shifts to *joint* China + carbon analysis (Test H + buyer-side carbon test) rather than China-alone θ. | F1, F2 weak; F3 cleaner. Same emphasis on joint analysis. | F1, F2 dead; F3 still viable but small per-shift dispersion of the China shock will give noisy θ. Joint analysis with carbon still informative. |
| **D2 = "China dominates carbon"** (hypothetical, not what happened) | F1, F2, F3 all viable. China-alone θ is the headline. | F3 clean; F1/F2 noisy. | F3 only. |
| **D2 = "even China is too small"** (hypothetical, not what happened) | Abandon project. | Abandon. | Abandon. |

A D1 fail under D2 = "comparable" still leaves F3 + joint-shock analysis viable. The most likely-to-survive path through this plan is now: **E3 RMD result → if domestic-side null, write joint LR-null paper using both shocks; if substitution exists, build D1 to support a within-NACE-4d θ estimate.**

## Does P&R run these diagnostics?

**D2 (magnitude): partially.** They report the first-stage as their headline magnitude check ("10pp tariff cut → 1.6% domestic price fall") and trim the 5% left tail of tariff changes acknowledging skew. They do not translate this to "% of plant input cost changed" the way SHOCK_MAGNITUDE.md does for the carbon shock.

**D1 (within-sector variability): no.** Their identification is plant-level shift-share with plant FE, identifying off **within-plant input-mix variation × cross-input tariff variation**. Their substitution question (between κ=8 broad input categories — analog of our F3) doesn't require within-output-industry variation. P&R can skip D1 because they're estimating F3-style. We need it because two of our three candidate framings (F1, F2) require within-NACE-4d identification.

## Files — built vs to-build

**Built and run (local-1 + RMD pending):**
- [analysis/phase6_eyeball_e1_shifter_dispersion.R](analysis/phase6_eyeball_e1_shifter_dispersion.R) — E1, PASS.
- [analysis/phase6_eyeball_e2_first_stage.R](analysis/phase6_eyeball_e2_first_stage.R) — E2, PASS (F = 195).
- [analysis/phase6_eyeball_e3_reduced_form.R](analysis/phase6_eyeball_e3_reduced_form.R) — E3, partial on local-1 (B alive, A/A2 underpowered). Re-run on RMD with full B2B pending.
- [analysis/phase6_d2_china_shock_magnitude.R](analysis/phase6_d2_china_shock_magnitude.R) — D2 buyer-level magnitude vs SHOCK_MAGNITUDE.md, B2B-side only. Result: "China shock comparable to carbon, different distributional shape" (see Findings section above).

**To build only if RMD E3 returns substitution (negative-and-significant Version A2):**
- `analysis/phase6_build_china_exposure.R` — Concordance work + firm-level `china_exposure_i` and `heavy_china_share_i` construction.
- `analysis/phase6_d1_within_sector_variability.R` — M1.1–M1.4 (per the plan above).
- `analysis/phase6_d2_china_shock_magnitude_full.R` — Customs-side addition to D2 (firm-level Customs exposure to ChinaShare-shocked HS6).
- `analysis/phase6_eyeball_e4_heterogeneity.R` — E4 buyer-decile plot, deferred.
- `CHINA_SHOCK_DIAGNOSTICS.md` — consolidated doc with verdict at the head, mirroring SHOCK_MAGNITUDE.md format.

**To build regardless (joint-shock framing for the LR-null paper):**
- `analysis/phase6_test_h_carbon_buyer_substitution.R` — buyer-side analog of E3 for the carbon shock (Test H from [SHOCK_AND_SUBSTITUTION_PLAN.md](SHOCK_AND_SUBSTITUTION_PLAN.md)). Symmetric to China-shock E3 Version A2 but using carbon `firm_cost_share` × `Post` interacted with NACE-4d aggregation. Required for the joint-LR-null write-up.

## Data caveats

- **Customs is on RMD only.** Local-1 prototyping needs a downsample.
- **B2B is downsampled on local-1, full on RMD.** Within-sector SD requires the full universe — final M1.2/M1.3 numbers must be RMD.
- **2002 is the first B2B year.** Pre-shock baseline shares for ADH are exactly at the panel boundary. Robustness: also compute baseline shares as 2002–2004 average.
- **PRODCOM-mocked status irrelevant** for these two diagnostics; they use B2B + Customs.
- **3 contaminated NACE 20/24 VAT hashes** (per MEMORY.md): drop from input-share denominators and from any output-NACE-4d cell aggregation post-2020.

## BACI download spec

- **Vintage**: HS02 release (covers 2002–2024 within one HS revision; avoids cross-vintage harmonization).
- **Years**: 2002–2012 minimum for the LR shock window; recommend 2002–2022 for horizon robustness (M2.3) at marginal extra cost.
- **Files**: annual `BACI_HS02_Y<year>_V<release>.csv` files + `country_codes_V<release>.csv` + `product_codes_V<release>.csv`.
- **Filter**: exporter China (ISO numeric 156) for the numerator; all exporters for the denominator (to compute China's share). Importers = fixed EU-26-minus-Belgium = 25 countries (EU-27 as of 2007 minus Belgium and Croatia).
- **Disk**: ~1–2 GB for 2002–2012, ~3–5 GB for 2002–2022.
- **License**: Etalab 2.0, free for academic use; registration on CEPII required.

## Concordances — what we have, what we need

**Already in repo / NBB raw:**
- `data/concordances/cn8_to_nace4d.csv` — CN8 → NACE 4d (the load-bearing buyer-side mapping).
- `NBB_data/raw/Correspondences_and_dictionaries/cn8_concord.tsv` — CN8 over-time concordance for tracking Belgian code stability.
- HS-to-BEC and HS code descriptions (sanity checks, figure labels).

**Derived in one line of code (no external download):**
- HS6 ↔ CN8: trivial first-6-digit truncation (CN8 is HS6 + 2 EU-specific digits by construction).
- HS6 → NACE 4d: compose `HS6 → CN8 children → cn8_to_nace4d.csv → NACE 4d`. Aggregation over CN8 children weighted by Belgian Customs trade value.

**Not needed for this plan:**
- Cross-HS-vintage concordances (HS02↔HS07↔HS12 etc.). Avoided by staying in HS02 throughout. Would only be needed if we extended past 2024 or merged with non-BACI trade data on a different vintage.

The "scarce concordance" risk earlier flagged in the plan does not bite — `cn8_to_nace4d.csv` already encapsulates the work P&R did manually.

## Verification checklist

1. **Concordance sanity:** total Belgian imports reconstructed from HS6 × firm-level allocation should match aggregate Customs totals within rounding. If material divergence, concordance has gaps.
2. **Sector signature for M2.4:** textiles/apparel/electronics should show top decile `heavy_china_share`. If they don't, abort and rebuild concordance.
3. **2002→2012 vs 2002→2007:** the 5-year slice should show a smaller but directionally consistent shock. Sanity check on horizon dependence.
4. **Cross-check with literature:** Belgian-aggregate Chinese-import-penetration time series should match published ADH-Europe or Bloom–Draca–Van Reenen-style series for Belgium where available.
5. **D1 robustness:** report variance ratio with NACE 4d, NACE 3d, and NACE 2d as the partition. The within ratio should fall as the partition coarsens; if it doesn't, something is wrong.

## Next-step options (post-RMD-E3 stocktake, 2026-04-29)

After running E1, E2, E3 (full RMD), and D2 (full RMD), the picture is documented in [CHINA_SHOCK_FINDINGS.md](CHINA_SHOCK_FINDINGS.md):

- **E1, E2 PASS**: clean first stage, ψ = −1.34 (per fractional unit), F = 195. Comparable in identifying power to P&R.
- **E3 ambiguous**: A2 (the load-bearing buyer-side substitution test) returns β = −0.103 with 95% CI [−0.29, +0.08] on full RMD B2B (N = 183 NACE 4d cells). Point estimate is in the predicted direction; CI includes zero with wide tails.
- **D2 nuanced**: China shock is broader but not uniformly larger than carbon. Carbon dominates at p99 (cement/steel tail); China dominates at p50–p95.
- **Original ambition narrowed**: "use a much-bigger shock to identify substitution under conditions where the carbon shock was too small" is no longer supported as the framing. Surviving narrower contributions: a clean first stage on Belgian data, and an ambiguous reduced form whose interpretation depends on what we do next.

Three candidate paths forward, in increasing order of cost. They are not mutually exclusive; sequencing matters.

### Path 1 — Test H: carbon-shock buyer-side analog (~2 days)

**Goal:** estimate the same regression as E3 Version A2, but using `firm_cost_share` × Post as the shifter instead of ΔChinaShare. Buyer-side analog of [B2B_LEAKAGE.md](B2B_LEAKAGE.md)'s seller-side null. The detailed spec lives in [SHOCK_AND_SUBSTITUTION_PLAN.md](SHOCK_AND_SUBSTITUTION_PLAN.md) Plan B's "Add-on test (open) — Across-NACE-category substitution under ETS exposure" section.

**Why it's the cheapest first move:** uses existing infrastructure (no new data, no new concordance work). Gives a parallel result on a complementary shock. The joint reading of A2-China + Test H-carbon is more informative than either alone:

- Both null with overlapping CIs → joint LR-null on Belgian B2B at the buyer level. **Strong paper claim** that doesn't depend on either single-shock identification holding up to all critiques.
- One null, one significant → contrast: substitution exists for one shock but not the other. The contrast is the finding; pinpoints which shock features matter for substitution (magnitude vs persistence vs price-channel-cleanness).
- Both significant → buyer-side substitution exists; reframes the leakage paper around "substitution exists at the buyer level but not at the seller level," which sharpens the relational-stickiness vs concentration question.

**File to build:** `analysis/phase6_test_h_carbon_buyer_substitution.R`. Should mirror the structure of `phase6_eyeball_e3_reduced_form.R`. Outcome: Δ(Belgian-seller share of expenditure on NACE 4d n) 2010→2022 (or whichever pre/post window matches the Plan B Test G window). Shifter: NACE-4d-aggregated `firm_cost_share` (using Plan B Prep 2's `firm_cost_share_regressor_j`, weighted by ETS sellers' B2B sales 2010 base).

### Path 2 — Sector-level heterogeneity decomposition of E3 A2 (~1 day)

**Goal:** decompose A2's β = −0.103 into NACE-2d-specific slopes. Identify whether some sectors show a clear negative slope that the population average is masking, or whether the population average is genuinely the right summary.

**Why it's worth running:** A2's NACE 4d N=183 is small enough that a single-coefficient population estimate may average over real heterogeneity. P&R's own results vary by industry; some industries have θ ≈ 4 while others have θ ≈ 1. The same heterogeneity is plausible for our Belgian-buyer reduced form.

**Specifically:**
- Run A2 separately for the top-China-exposure NACE 2d cells (textiles 13, apparel 14, wood 16, furniture 31 — see D2 sector breakdown).
- Run A2 separately for low-exposure cells (food 10, pharma 21, services).
- Report sector-by-sector slopes and CIs. Look for: (a) clean negative in the high-exposure tail = within-sector substitution exists, but is sector-specific; (b) flat across all sectors = the null is a robust feature of Belgian B2B.

**File to build:** extend `phase6_eyeball_e3_reduced_form.R` with a sector-decomposition branch. ~50 lines.

### Path 3 — D1 + firm-level θ regression (~1–2 weeks)

**Goal:** the original P&R-style θ estimation. Build firm-level `china_exposure_i` from B2B + Customs + concordances, run the variance-decomposition diagnostic (D1), then estimate θ via 2SLS.

**Why this is now harder to justify:** the magnitude comparison (D2) shows the China shock is not the dramatic improvement over carbon we hoped for. A D1 + θ regression that returns a noisy null estimate is a substantial investment with low payoff; if D1 reveals the within-NACE variance ratio is low (forcing F3 framing) or if E3's hint of substitution doesn't survive sector decomposition, we'd be building an estimator without a target.

**When to run it:** only if Path 1 or Path 2 produces a clear positive-substitution signal. In particular:
- If Path 1's Test H also returns null with tight CI: Path 3 is unlikely to recover a θ estimate worth publishing, because the across-shock null says Belgian buyers don't substitute much under any shock at this aggregation level.
- If Path 2 reveals a clean negative slope concentrated in a few sectors: Path 3 makes sense restricted to those sectors.
- If Path 1 returns substitution on the carbon shock that A2 missed: that contrast is itself the contribution; Path 3 may not add much.

### Recommended sequence

1. **Run Path 1 (Test H) first.** Cheapest, most informative for the paper-level claim, leverages all existing infrastructure.
2. **Run Path 2 (sector decomposition) in parallel or immediately after.** Cheap, helps interpret both A2 and Test H by exposing heterogeneity.
3. **Decide on Path 3 only after Paths 1 and 2 are in.** The decision criterion: is there a credible single-shock or joint-shock signal that a θ estimate would refine into a publishable number? If yes, build D1. If no, the eyeball-level findings + Path 1 + Path 2 already constitute the paper.

### What stops the project

The remaining China-shock work stops if **all three** of the following hold simultaneously after Paths 1 and 2:

- A2 sector decomposition (Path 2) reveals no sector with a clean substitution signal.
- Test H (Path 1) returns null with tight CI.
- D2's distributional pattern doesn't change qualitatively under any reasonable robustness re-spec.

In that case the substantive claim stabilizes around: "Belgian B2B does not show buyer-side substitution under either the carbon shock or a clean LR China shock at the NACE 4d level. This is consistent with relational stickiness (Heise 2024) or with concentration (no within-NACE alternatives), but our identification cannot distinguish between them at this aggregation." The eyeball-level results + Path 1 + Path 2 are then the paper.

---

## Anti-dumping duties — note on a candidate alternative shock

**Status: candidate, not yet scoped.** Anti-dumping (AD) duties imposed by the EU on specific (CN8/HS6 product × origin country) cells are a promising alternative source of identifying variation, with several features that compare favorably to both the carbon and China shocks for our purposes:

- **Persistent.** A typical EU AD duty is set for 5 years and is frequently renewed for another 5 (10+ years is common). Same horizon as our other "permanent" shocks.
- **Large.** EU AD duties on Chinese products are typically 20–80%, sometimes >100% — well above the typical China-shock implied price wedge (D2 found p99 cumulative China shock ≈ 1.13%) and above the carbon shock at all but the cement tail.
- **Persistent, predictable, rule-based.** Investigations follow a published WTO-compatible procedure with provisional and definitive duty stages; firms know they're coming. Same "anticipatable regime change" character as carbon pricing in Phase IV.
- **Origin- and product-specific.** Generates *within-product across-origin* price dispersion — exactly the variation that the China shock and carbon shock lack at the cross-section. A Belgian importer sourcing the same HS6 product from China + Korea + Turkey suddenly faces a wedge on the China leg only.
- **Numerous.** EU runs ~100 AD measures at any given time. Bown's *Global Antidumping Database* + EU TARIC give a panel of staggered (product × origin × year) treatments.

Closest design templates in the literature: Flaaen, Hortaçsu & Tintelnot (2020 AER) on washing machines; Erbahar & Zi (2017 JIE) and Konings & Vandenbussche (2008 JIE) on EU AD measures with Belgian/EU-firm focus; Boehm, Levchenko & Pandalai-Nayar (2022) for the local-projection short-run vs long-run framework.

**Not building this out yet** — kept here so we don't forget the option. If the China-shock revisit (next section) and Test H both stall, the AD-duty design is the next thing to scope.

---

## Revisiting the China shock — importer-side elasticity of substitution toward Chinese goods

### Why pivot

The leakage paper's natural elasticity is between *Belgian suppliers within an input category*. E3's downsampled run on local-1 and the RMD A2 result are at-best a marginally significant point estimate with wide CI for that elasticity. The substitution channel that the data may actually support more cleanly is the one *one notch up the supply chain*: Belgian importers reweighting between **Chinese imports and other origins** as Chinese prices fall.

Two caveats need to be visible up front:

1. **Selection.** Belgian importers are not representative of Belgian firms — they are larger, better-managed, and disproportionately multi-national-affiliated (the same selection problem ADH-on-firms has). A Chinese-elasticity finding among importers does not automatically transfer to the broader Belgian firm population. The paper's claim cannot be "Belgian firms substitute toward China" without qualification — it has to be "Belgian *importers* substitute toward China, on the *origin-of-imports* margin," and we should be explicit about how unrepresentative this population is (size distribution, NACE composition, multi-national share, vs Belgian firm universe in B2B + Annual Accounts).
2. **Margin.** This is the import-origin margin (China vs. non-China origins of HS6 product k), not the domestic-vs-imported margin and not the within-Belgian-supplier margin. It is closer to the standard Armington / trade-elasticity literature than to P&R's input-category θ.

With those caveats, the design has three components, ordered from most-standard to most-novel:

### Component 1 — Estimate the elasticity of substitution toward China

For each Belgian importer i, HS6 product k, year t, define:

```
ChinaShare_{i,k,t} = (imports from China of k by i in year t) / (total imports of k by i in year t)
```

Estimate, across (i, k) pairs over a long-difference horizon (2002 → 2012, with robustness 2002 → 2007 and 2002 → 2022):

```
Δlog ChinaShare_{i,k} = α + θ × Δlog P^China_{k} + γ × Δlog P^non-China_{k} + FEs + ε_{i,k}
```

or in CES form on log-relative-shares:

```
Δlog (ChinaShare_{i,k} / NonChinaShare_{i,k}) = α + (1 − θ) × Δlog (P^China_k / P^non-China_k) + FEs + ε_{i,k}
```

**Identification — IV.** Use the ADH non-Belgian-EU shifter `ΔChinaShare_k,EU-excl-Belgium,2002→2012` as the instrument for the fall in Chinese unit values delivered to Belgium. Decomposes into:

- First stage (already estimated, F = 195 in E2, ψ = −1.34): `Δlog P^China_k = ψ × ΔChinaShare_k + ξ`.
- Reduced form: `Δlog ChinaShare_{i,k} = ρ × ΔChinaShare_k + ν`.
- IV estimate: `θ̂ = 1 + ρ̂ / ψ̂` (sign convention depends on whether the LHS is China share or its complement; pin down once).

**Fixed effects.** HS6 FE is automatic via the long-difference. Importer FE in long differences is a constant per importer; soaks up importer-level mean substitution propensity. Add NACE-2d × HS-section interactions if heterogeneity by sector pollutes the average.

**Sample frame.** Belgian importers with positive imports of HS6 product k in both endpoint years (intensive margin), with a separate analysis on the importer × HS6 cells with extensive-margin transitions (zero in 2002, positive in 2012, or vice versa) to avoid losing the firms that newly tilt toward China. Boehm-Levchenko-Pandalai-Nayar's IHS treatment of zeros is the right template.

**Output.** A point estimate of θ on the import-origin margin with a CI, a first-stage F, and an explicit comparison to: (a) BLP's long-run trade elasticity (−1.75 to −2.25); (b) Amiti-Itskhoki-Konings-style elasticities; (c) any θ from Components 2 and 3.

### Component 2 — Short-run vs long-run

Run Component 1 at horizons h = 1, 2, 3, 5, 7, 10 (and 12, 15, 20 if the panel extends to 2022). Use **local projections à la Jordà / BLP**: a separate long-difference regression at each horizon h, with the IV constructed from the BACI shifter cumulated over the same window:

```
Δ_h log ChinaShare_{i,k,t} = α_h + θ^h × Δ_h log P^China_{k,t} + FEs + ε
```

instrumented by `Δ_h ChinaShare_k,EU-excl-Belgium`. The full impulse response of θ^h vs h is the headline figure (analog of BLP Figure 2; Peter-Ruane Figure 4).

**Useful looks like:** θ^1 small (0.5–1.5), θ^7 large (2–4), monotone or convex transition; CIs at h ≥ 7 narrower than at h ≤ 3 (because LR variation is bigger).

**Killer:** flat across horizons, or LR < SR. Either kills the "elasticity bites in LR" claim or signals identification problems (e.g., the IV is stronger at SR than LR, opposite to what we want).

**This is the central narrative claim** — even more than the level of θ, the *shape* of θ^h vs h is what matches Peter-Ruane and BLP. A clean LR-rises-above-SR pattern is the publishable result, regardless of the level.

### Component 3 — Heterogeneity in importance: high-cost-share vs low-cost-share importers

For each (importer i, HS6 k, base year 2002), compute the cost-share weight of HS6 k in importer i's total input bill:

```
input_share_{i,k,2002} = (importer i's 2002 expenditure on HS6 k, all origins) / (importer i's 2002 total input bill)
```

The expectation under standard CES with adjustment costs / search costs is:

- **High input_share_{i,k}** (HS6 k is a major cost line for importer i): the gain from reallocating origin is large enough to clear the fixed cost of finding and qualifying a new Chinese supplier. Substitution θ_{i,k} should be measurable and positive.
- **Low input_share_{i,k}** (HS6 k is a marginal cost line): the gain from reallocating origin is small relative to the fixed cost of switching. Substitution θ_{i,k} should be near zero.

Test by interacting Component 1's regression with importance bins:

```
Δlog ChinaShare_{i,k} = α + θ_high × Δlog P^China_k × 1{input_share_{i,k,2002} > median}
                              + θ_low × Δlog P^China_k × 1{input_share_{i,k,2002} ≤ median} + FEs
```

with separate first stages for the two interactions (the IV is interacted with the same indicator).

**Useful looks like:** θ_high significantly above θ_low; the contrast itself is the headline. This is a *cleaner* heterogeneity finding than a single-coefficient estimate because it predicts cross-sectional variation in substitution that is ex-ante observable from the cost-share data alone.

**Why this is novel.** Most trade-elasticity papers (BLP, ADH) estimate a population-average θ. Peter-Ruane's heterogeneity is across input *categories* κ, not across firm × product cells. The cross-cell heterogeneity along the importance margin is closest in spirit to the Boehm-Pandalai-Nayar input-linkage literature and to Carvalho et al.'s shock-propagation work — but on the substitution rather than the propagation side. A clean cost-share-weighted heterogeneity result would be a distinctive finding even if the population-average θ is modest.

**Operational note.** `input_share_{i,k,2002}` is the same object D1 needs for the original framing. Building it once supports both Component 3 here and the original P&R-style θ regression. The concordance work (`HS6 → CN8 → cn8_to_nace4d.csv`) already exists in repo.

### How Components 1, 2, 3 sit together for the paper

The narrative the three components jointly support is:

> Among Belgian importers, the elasticity of substitution toward Chinese imports is [θ̂] in the long run, [substantially / modestly] higher than in the short run, and concentrated in (importer, product) pairs where the imported product is a meaningful cost line. We can identify this elasticity in the trade margin even though the same firms' B2B substitution toward Belgian suppliers is [null / weak] under both the carbon shock (Test H) and the China shock at the within-Belgian-supplier margin (E3 A2).

The contribution rests on:

1. A clean import-origin θ estimate where the literature's elasticities mostly concern other margins (BLP: aggregate trade elasticity; P&R: input-category θ; ADH: labor-market exposure).
2. An LR-vs-SR shape that matches the recent literature (BLP, P&R) and disciplines the elasticity for use in calibrated GE models on Belgian data.
3. An importance-weighted heterogeneity result that gives a structural interpretation to why Belgian B2B substitution is weak: at the typical (firm × supplier) pair, the input is too small a cost line to clear the fixed cost of switching.

The selection caveat (importers ≠ Belgian-firm population) bounds the external validity claim but does not undermine the structural interpretation.

### Files to build

- `analysis/phase6_revisit_c1_china_origin_theta.R` — Component 1, long-difference 2SLS at h = 10. Reuses E2's first stage.
- `analysis/phase6_revisit_c2_local_projections.R` — Component 2, the θ^h panel at h = 1..10. BLP-style 2SLS at each h.
- `analysis/phase6_revisit_c3_importance_heterogeneity.R` — Component 3, interacted regression with `input_share_{i,k,2002}` bins. Depends on building the importer × HS6 cost-share matrix.

### Sequencing

1. Component 1 first (cheapest, depends only on existing E2 first stage + Customs).
2. Component 3 next (requires building the importer × HS6 cost-share matrix from B2B + Customs, but no new external data).
3. Component 2 last (most regressions, needs the panel of horizons; useful for the headline figure but doesn't change the existence claim).

This sequencing front-loads the existence test (Component 1) before the panel work (Component 2).

### Decision rule

| Component 1 | Component 2 | Component 3 | Verdict |
|---|---|---|---|
| significant θ, F > 10 | LR > SR with clear transition | high-importance bin θ > low-importance bin θ | **Headline result.** Three-component import-origin-substitution paper. |
| significant θ | LR > SR | flat across importance | Two-component paper, with note that importance margin doesn't bite. |
| significant θ | flat across h | — | Component 1 alone is the result; LR-vs-SR claim is dropped. Paper is shorter but still publishable. |
| null θ in Component 1 | — | — | Even the import-origin margin is null among importers. Combined with E3 A2 + Test H nulls, this is a strong joint-null claim about Belgian substitution at every margin we can measure. Different paper, same project. |

