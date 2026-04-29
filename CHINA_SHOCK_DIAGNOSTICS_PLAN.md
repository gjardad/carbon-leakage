# China Shock Diagnostics — Plan

## Context

[SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md) established that the carbon-pricing shock is small at the typical Belgian ETS pair-year (pair-shock-total p90 = 1.16% in Phase IV; only cement-buyer cells reach signal-to-noise > 0.5σ). Peter & Ruane (2025) argues that **long-run** elasticities are an order of magnitude larger than short-run ones (θ_LR ≈ 2.47 vs θ_SR ≈ 0.5) and that estimating the LR requires a **permanent** shock with a **7+ year horizon**. Their identification: India's 1991 trade liberalization, with shift-share IV using 1989 input shares × 5-digit ASICC tariff cuts.

The closest Belgian analog within our 2002–2022 data window is **China's WTO accession (Dec 2001) and subsequent export-supply expansion** — permanent, large, asymmetric across input categories, full post-period coverage.

Before specifying a P&R-style θ regression, we need two diagnostics that the original P&R paper does not run (or runs only partially) but that are necessary for our setting:

1. **Within-sector variability in Belgian firm exposure to Chinese imports** — required for any specification with output-industry × year FE.
2. **Magnitude of the input-cost change attributable to the China shock** — required to avoid replicating the SHOCK_MAGNITUDE.md problem (well-identified shock that is too small to act on).

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

### Decision rule for D2

| `heavy_china_share_i` p90 (or implied shock p90 at 7-yr) | Verdict |
|---|---|
| > 30% (heavy) or > 10% (implied) | Shock is large at the upper tail — clearly bigger than carbon. Proceed. |
| 10–30% (heavy) or 3–10% (implied) | Moderate. Bigger than carbon but not dramatically. Proceed, flag. |
| < 10% (heavy) or < 3% (implied) | Even the China shock fails the magnitude test for Belgian B2B. Same problem as carbon — abandon, look elsewhere. |

## Joint decision: D1 × D2 × framing

|  | D1 pass | D1 borderline | D1 fail |
|---|---|---|---|
| **D2 pass** | F1, F2, F3 all viable. Choose framing on substantive grounds. | F1, F2 noisy; F3 clean. Lean F3 unless the leakage-paper tie-in (F1) is critical. | F1, F2 dead; F3 still viable — pivot to between-category θ. |
| **D2 borderline** | All three viable but underpowered. Spec event-study to extract maximum signal. | One or both halves weak; expect SE to swallow point estimate. | F3 only, expect noisy estimate. |
| **D2 fail** | Abandon: shock too small at firm level for any framing. | Abandon. | Abandon. |

A D2 fail kills the China shock entirely — same problem as carbon, just with a different shock. A D1 fail narrows the framing to F3 (the actual P&R parameter) but doesn't kill the project.

## Does P&R run these diagnostics?

**D2 (magnitude): partially.** They report the first-stage as their headline magnitude check ("10pp tariff cut → 1.6% domestic price fall") and trim the 5% left tail of tariff changes acknowledging skew. They do not translate this to "% of plant input cost changed" the way SHOCK_MAGNITUDE.md does for the carbon shock.

**D1 (within-sector variability): no.** Their identification is plant-level shift-share with plant FE, identifying off **within-plant input-mix variation × cross-input tariff variation**. Their substitution question (between κ=8 broad input categories — analog of our F3) doesn't require within-output-industry variation. P&R can skip D1 because they're estimating F3-style. We need it because two of our three candidate framings (F1, F2) require within-NACE-4d identification.

## Files to create

**Eyeball stage (run first, gates everything below):**
- `analysis/phase6_eyeball_e1_shifter_dispersion.R` — E1 distribution plot. Two versions: Belgian-Customs-only preview, BACI-based proper.
- `analysis/phase6_eyeball_e2_first_stage.R` — E2 BACI shifter vs Belgian HS6 unit-value scatter (P&R Figure 2 analog).
- `analysis/phase6_eyeball_e3_reduced_form.R` — E3 BACI shifter vs Belgian-supplier-share change.
- `analysis/phase6_eyeball_e4_heterogeneity.R` — E4 buyer-decile plot of import-share change.

**D1/D2 stage (run only after eyeballs pass):**
- `analysis/phase6_build_china_exposure.R` — Concordance work + firm-level `china_exposure_i` and `heavy_china_share_i` construction. The bulk of the work is the NACE-4d ↔ HS6 mapping (B2B is at NACE; Customs is at HS6/CN8); document the assumptions explicitly.
- `analysis/phase6_d1_within_sector_variability.R` — M1.1–M1.4
- `analysis/phase6_d2_magnitude.R` — M2.1–M2.4
- `CHINA_SHOCK_DIAGNOSTICS.md` — consolidated doc with verdict at the head, mirroring SHOCK_MAGNITUDE.md format. Eyeball figures appear at the top of the doc as the visual punchline before the regression-style moments.

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
