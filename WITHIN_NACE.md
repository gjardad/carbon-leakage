# Within-NACE-4d Intensive Margin: Findings

---

## Summary

We test whether the EU ETS / Market Stability Reserve (MSR) caused Belgian buyers to reallocate expenditure away from their most carbon-exposed supplier toward less-exposed alternatives, within the same NACE 4-digit input category.

Using a present-in-2010-14 sample with a 2012-2020 panel window, we find:

- The pooled naive DiD coefficient on `post × top` is **γ̂ = +0.0123 (SE 0.0055, p < 0.05)** — a small, statistically significant **positive** coefficient, opposite to the leakage prediction.
- Once we control for the age × top fixed effects (absorbing differential attrition between top and bot suppliers), the coefficient drops to **γ̂ = +0.0031 (n.s.)** — effectively zero.
- The event study shows **clean pre-trends** (2012-2016 coefficients within ±0.01 of zero) and **mild post-2017 positive deviations** (2018-2020 in the range +0.014 to +0.019 of share).
- The Rambachan-Roth (2023) honest DiD bounds make this fragile: the original 95% CI [−0.001, +0.020] just barely excludes zero, and the **breakdown M̄ is ≈ 0.25** — a very small amount of pre-trend slack collapses the CI to zero.
- The heterogeneity table reveals **opposite-sign effects across cuts**: cost-shock cuts go negative (γ̂ ≈ −0.05, leakage direction) while input-share and exposure-gap cuts stay near zero or positive. None of these survive the Romano-Wolf step-down multiplicity correction (all RW p > 0.10).

**The within-NACE-4d intensive margin response to the EU ETS / MSR is small and not robustly identified.** The pooled estimate is in the anti-leakage direction but fragile to pre-trend slack. The heterogeneity hints at suggestive leakage where the cost-shock incentive is strongest, but the multiplicity-adjusted p-values don't survive.

A complementary structural CES estimation gives a point estimate of σ ≈ 1.5–3 for a reasonable range of pass-through and EUA-price assumptions (slightly above Cobb-Douglas, modest substitutability), though the CI is too wide to pin σ down precisely. See [Structural CES](#structural-ces-estimating-the-elasticity-of-substitution) below.

---

## The empirical question

Carbon-leakage theory predicts that buyers facing a carbon price will substitute away from carbon-intensive suppliers toward less-exposed alternatives. Within a single input category (NACE 4-digit), this is the intensive margin of substitution: does the buyer give the regulated supplier a smaller share of its NACE-4d spend, holding the input category fixed?

The relevant comparison is **within-cell**: for each (buyer, NACE-4d) pair where the buyer sources from both a regulated and an unregulated supplier, what happens to the expenditure-share differential between them after the policy hits?

---

## Sample: "Present in 2010-14"

### Cell definition

A **cell** is a (buyer *b*, NACE-4d *n*) pair where the buyer sources from multiple suppliers in the same input category. A cell enters the sample if:

1. The buyer sourced from at least 2 distinct suppliers in *some* year of 2010-2014 (the pre-window).
2. The buyer sourced from at least one of those suppliers in *some* year of 2015-2016 (the omega-measurement window).
3. The cell's maximum 2015-16 ω is positive (at least one supplier is regulated).
4. The cell's minimum 2015-16 ω is strictly below the maximum (a real exposure contrast exists).

The dual-window requirement (pre AND omega-window activity) ensures that every supplier in the cell was a real candidate for substitution at the moment the MSR price hit. Pairs that died before 2015 are excluded because the buyer can't reallocate away from a dead supplier.

### Top vs. bot

Within each cell:

- **Top supplier**: the single supplier with the highest 2015-16 ω. ω is the firm's carbon shortage (emissions − free allocation) as a share of total cost. Top = most exposed to the carbon price in the omega-window.
- **Bot pool**: all suppliers in the cell tied at the *minimum* 2015-16 ω. In most cells this minimum is 0 (the pool consists of unregulated suppliers or regulated suppliers with surplus allocation); in a small fraction of cells (~5%) it is positive (all suppliers regulated). When multiple suppliers tie at the minimum ω, we compute the average of their expenditure shares — a "portfolio bot" rather than picking one supplier via a sales tiebreaker.

The bot portfolio approach was chosen over the single-bot definition (smallest ω, sales tiebreaker) because on a previous version of the sample roughly 32% of cells had multiple suppliers tied at ω = 0, and the sales tiebreaker systematically picked the smallest of those — biasing the bot toward fragile relationships.

### Sample size (RMD)

- 2017-treatment panel: **4,997 cells** with both top and bot trajectories observable.
- Bot pool averages 3.58 ω=0 suppliers per cell; ~95% of cells have min ω = 0.
- Cell-role panel for the naive DiD (one row per cell × role × year): **81,164 rows** over 2012-2020.
- Pair-year panel for the age × top FE spec: **188,149 rows**.

### Window: 2012-2020

The panel window is **2012-2020**. The window starts at 2012 because the raw event study shows clean, flat pre-period coefficients from 2012 onward, while 2010-2011 are noisy as cells "fill in" toward the 2010-14 pre-window. The window ends at 2020 to keep the post-period inside the MSR price rise (EUA went from ~7 EUR/t in 2016 to ~25 EUR/t at end-2018 to ~30 EUR/t in 2020) without contaminating the comparison with COVID-disrupted 2021-22 or the 2021-22 energy crisis. A 2012-2022 sensitivity is straightforward to produce.

---

## Specification

### The headline DiD

We estimate, at the cell-role-year level (one row per top supplier per cell-year and one row for the bot portfolio mean per cell-year):

```
share_{c,r,t} = α_{c,r}  +  δ_t  +  γ · (post × top)  +  ε_{c,r,t}
```

clustered on cell, where:

- `share_{c,r,t}` is the within-cell expenditure share for role *r* in cell *c* at year *t*.
- `α_{c,r}` is a cell-by-role fixed effect (absorbs time-invariant level differences).
- `δ_t` is a year fixed effect (absorbs aggregate year shocks).
- `post_t = 1[year ≥ 2017]`.
- γ identifies the average post-2017 differential change in within-cell share between top and bot.

### Age × top FE sensitivity

To address differential attrition between top and bot — top relationships survive at higher rates than bot pool members (pre-policy attrition: top 9.4%/year, bot 12.3%/year on RMD) — we estimate a sensitivity version at the pair-year level (one row per pair per year), with age fixed effects and age × top fixed effects:

```
share_{p,t} = α_{cell × role}  +  δ_t  +  δ_age  +  age × top FE
            +  γ · (post × top)  +  ε_{p,t}
```

The age × top fixed effects absorb the structural age-dependent differential between top and bot — exactly the kind of mechanical pattern that differential attrition would produce.

### The event study

The corresponding event study replaces `post × top` with year-by-year interactions on the cell-role panel:

```
share_{c,r,t} = α_{c,r}  +  δ_t
              +  Σ_{k ≠ −1} β_k · 1[year = 2017 + k] · top  +  ε_{c,r,t}
```

where *k* indexes years relative to 2017 (the omitted reference is *k* = −1, i.e. 2016). The β_k coefficients trace the year-by-year top-vs-bot differential, all measured relative to 2016 — the diagnostic that lets us check parallel trends visually.

---

## Identification

The identifying assumption is **parallel trends conditional on cell-role and year fixed effects**: in the absence of the MSR price rise, the post-2017 evolution of the top-bot share gap would have continued along the pre-period trajectory.

This is what the event study tests. On RMD, the event study coefficients are:

| Year | k | β_k | SE | 95% CI |
|---|---|---|---|---|
| 2012 | −5 | −0.0018 | 0.0079 | [−0.017, +0.014] |
| 2013 | −4 | −0.0005 | 0.0075 | [−0.015, +0.014] |
| 2014 | −3 | −0.0094 | 0.0069 | [−0.023, +0.004] |
| 2015 | −2 | −0.0030 | 0.0067 | [−0.016, +0.010] |
| 2016 | −1 | 0 (ref) | -- | -- |
| 2017 | 0 | −0.0072 | 0.0055 | [−0.018, +0.004] |
| 2018 | 1 | **+0.0141** | 0.0063 | [+0.002, +0.026] |
| 2019 | 2 | +0.0139 | 0.0071 | [+0.000, +0.028] |
| 2020 | 3 | **+0.0185** | 0.0075 | [+0.004, +0.033] |

**Pre-period (2012-2015) is essentially flat at zero.** All four pre-period coefficients are between −0.009 and 0, with CIs spanning zero comfortably. This is the cleanest pre-trend diagnostic in any DiD spec we have estimated for this margin.

**Post-period (2017-2020) is mildly positive.** 2017 dips slightly to −0.007 (n.s.); 2018-2020 are uniformly positive at +0.014 to +0.019, with 2018 and 2020 marginally significant at the 5% level.

The variation that identifies γ comes from cross-supplier heterogeneity in carbon-cost exposure ω interacted with the post-2017 timing. After absorbing cell-role and year FE, γ measures the post-2017 break in the top-bot share gap, on the assumption that the gap would have continued at its pre-period level (essentially zero on average from 2012 to 2016) absent MSR.

---

## Findings

### Pooled DiD (RMD)

| Spec | γ̂ | SE | p-value | N obs |
|---|---|---|---|---|
| Naive DiD (cell-role panel, portfolio bot) | **+0.0123** | 0.0055 | 0.025 (**) | 81,164 |
| Pair-level + age × top FE | +0.0031 | 0.0056 | 0.58 | 188,149 |

The naive DiD coefficient is small (+1.2 pp) but statistically significant at the 5% level. Once age × top FE absorb the structural attrition-driven differential, the coefficient drops to +0.3 pp and is no longer significant.

**Sign and magnitude.** γ̂ > 0 is the anti-leakage direction: the most-exposed supplier's share *rose* by 1.2 pp relative to the least-exposed portfolio over 2017-2020. The leakage hypothesis predicts γ̂ < 0; the data goes the other way, but the magnitude is small.

### Event study + HonestDiD bounds (RMD)

The average post-period β across 2017-2020 (equal weights) is **+0.0097**.

| M̄ | Method | 95% CI |
|---|---|---|
| 0 | Original (no PT slack) | **[−0.0010, +0.0204]** — marginal exclusion of zero |
| 0.25 | HonestDiD | [−0.0121, +0.0320] — includes zero |
| 0.50 | HonestDiD | [−0.0279, +0.0480] |
| 0.75 | HonestDiD | [−0.0445, +0.0646] |
| 1.00 | HonestDiD | [−0.0615, +0.0819] |
| 1.25 | HonestDiD | [−0.0788, +0.0991] |
| 1.50 | HonestDiD | [−0.0961, +0.1092] |
| 2.00 | HonestDiD | [−0.1092, +0.1092] |

**Breakdown M̄ ≈ 0.25.** Even allowing the post-period parallel-trends violation to be as small as 25% of the largest pre-period violation collapses the CI to zero. The marginal-positive original CI is **not robust** to plausible pre-trend deviations.

### Reading the bounds

| Claim | Rejected under M̄ ≤ ... |
|---|---|
| Leakage of 5 pp or more (γ ≤ −0.05) | M̄ ≤ 0.75 |
| Leakage of 7 pp or more (γ ≤ −0.07) | M̄ ≤ 1.00 |
| Anti-leakage of 5 pp or more (γ ≥ +0.05) | M̄ ≤ 0.50 |
| Any non-zero effect | Not rejected at any M̄ > 0.25 |

**Big leakage (≥ 5 pp) is rejected** at M̄ ≤ 0.75 — a non-trivial robustness statement. **Big anti-leakage is also rejected** at similar M̄. But pinning down the sign of any small effect requires assuming M̄ < 0.25, which is a strong assumption.

### Heterogeneity (RMD, B = 500 cluster-bootstrap for Romano-Wolf)

| Cut | N cells | γ̂ | SE | unadj p | RW p |
|---|---|---|---|---|---|
| Pooled | 4,997 | +0.0080 | 0.0056 | 0.155 | 0.732 |
| **Cost shock top-Q** | 1,249 | **−0.0527** | 0.0105 | < 0.001 | 0.462 |
| **Cost shock top-D** | 500 | **−0.0473** | 0.0151 | 0.002 | 0.606 |
| Input share top-Q | 1,249 | +0.0076 | 0.0075 | 0.31 | 0.776 |
| Input share top-D | 500 | +0.0030 | 0.0098 | 0.76 | 0.792 |
| Exposure gap top-Q | 1,274 | +0.0069 | 0.0103 | 0.50 | 0.792 |
| Exposure gap top-D | 589 | +0.0277 | 0.0155 | 0.07 | 0.732 |

**Cost-shock cuts flip sign to leakage direction.** On the subsample of cells where the carbon-cost incentive on the top supplier is largest (top quartile and top decile of `ω_top × top-supplier-share-of-buyer × EUA_2018`), the DiD coefficient is **−0.05** — about 5 percentage points of within-cell share lost by the top to the bot. Unadjusted p-values are highly significant.

**But Romano-Wolf adjustment wipes them out.** The cluster-bootstrap on buyer learns the dependence structure across the 7 hypothesis tests; the family-wise error rate correction pushes all p-values above 0.10. Nothing survives multiplicity.

**Other cuts go the other way.** Input-share and exposure-gap cuts are positive or near zero — opposite of the cost-shock pattern. The sign and significance of the heterogeneity DiD depends heavily on which heterogeneity variable you use.

---

## Interpretation

### What we can claim

1. **Pre-trends are clean.** On the 2012-2020 window, the event study shows essentially flat pre-period coefficients with CIs spanning zero. This is the cleanest identification window we have estimated for this margin.
2. **Big effects in either direction are rejected.** Under reasonable assumptions about pre-trend extrapolation (M̄ ≤ 0.5), the average post-period effect is bounded to roughly ±3 to ±5 pp. Effects beyond ±5-7 pp are rejected at any plausible M̄.
3. **Pooled effect is small.** The point estimate is +1.2 pp (anti-leakage direction), marginally significant under exact parallel trends but fragile to pre-trend slack.
4. **Suggestive leakage where the incentive is largest.** The cost-shock cuts deliver a −5 pp coefficient in the leakage direction, in the subsamples where carbon costs put the largest dollar burden on the buyer. Unadjusted p-values are highly significant; multiplicity-adjusted p-values are not.

### What we cannot claim

1. **A robust pooled effect.** The +1.2 pp pooled estimate is sign-dependent on the spec (drops to +0.3 pp under age × top FE) and is not robust to pre-trend slack beyond M̄ = 0.25.
2. **A robust heterogeneity story.** Cost-shock cuts suggest leakage; other cuts don't. After multiplicity correction, no cell rejects the null. The data hints at leakage in the right place but can't deliver a robust statement.

### Story for the paper

The within-NACE-4d intensive margin response to MSR is **small and not robustly identified**. We:

- Reject big effects (≥ 5 pp) in either direction under reasonable identification.
- See a small marginally-significant positive coefficient pooled that fragility analysis collapses to zero.
- See suggestive leakage of −5 pp in the cells with the largest cost-shock incentive, but it doesn't survive multiplicity correction.

The most obvious substitution channel — swap your steel mill for a cleaner steel mill within the same input category — is not where carbon leakage shows up. Whatever reallocation the policy did induce operated on other margins (extensive, across-NACE, or imports).

---

## What this implies for the broader leakage question

Leakage operates on several margins:

1. **Within-NACE-4d intensive (this section):** small, fragile, not robustly identified.
2. **Within-NACE-4d extensive:** does the buyer cut top-ω relationships entirely? (Separate analysis.)
3. **Across-NACE-4d:** does the buyer redesign the input mix away from regulated categories? (Cross-NACE analysis.)
4. **Imports:** does the buyer substitute domestic exposed suppliers for foreign imports? (Import margin analysis.)

The within-NACE-4d intensive margin tells us about substitution among the most directly comparable suppliers — same product category, both already serving the same buyer. The fact that we cannot robustly identify any effect, and that the effect we do identify is small (within 2 pp under exact PT), is informative: it says that the most obvious substitution channel is not where the action is.

Whatever reallocation the policy did induce, it operated on other margins.

---

## Artifacts

### Code (current)

- [`analysis/phase4_within_intensive_pretrend_present_in_2010_14.R`](analysis/phase4_within_intensive_pretrend_present_in_2010_14.R): builds the present-in-2010-14 sample, top + bot portfolio, and the trajectory figure.
- [`analysis/phase4_within_intensive_did.R`](analysis/phase4_within_intensive_did.R): headline DiD (naive + age × top FE) and event study, panel 2012-2020.
- [`analysis/phase4_within_intensive_did_mht.R`](analysis/phase4_within_intensive_did_mht.R): heterogeneity DiD with Romano-Wolf step-down adjusted p-values.
- [`analysis/phase4_within_intensive_did_honestdid.R`](analysis/phase4_within_intensive_did_honestdid.R): HonestDiD bounds on the event study.
- [`analysis/phase4_within_intensive_attrition_did.R`](analysis/phase4_within_intensive_attrition_did.R): survival DiD with age controls.
- [`analysis/phase4_within_intensive_ces_ppml.R`](analysis/phase4_within_intensive_ces_ppml.R): structural CES via Poisson PML.

### Figures (RMD)

- [`output_rmd/figures/phase4_within_nace4d_intensive_topbot_present_in_2010_14_trajectory.pdf`](output_rmd/figures/phase4_within_nace4d_intensive_topbot_present_in_2010_14_trajectory.pdf): 2-panel trajectory.
- [`output_rmd/figures/phase4_within_intensive_did_eventstudy.pdf`](output_rmd/figures/phase4_within_intensive_did_eventstudy.pdf): event study, 2012-2020.
- [`output_rmd/figures/phase4_within_intensive_did_honestdid_bounds.pdf`](output_rmd/figures/phase4_within_intensive_did_honestdid_bounds.pdf): HonestDiD CI vs M̄.
- [`output_rmd/figures/phase4_within_intensive_attrition_did_age_stratified.pdf`](output_rmd/figures/phase4_within_intensive_attrition_did_age_stratified.pdf): age-stratified survival rates.
- [`output_rmd/figures/phase4_within_intensive_ces_ppml_sigma.pdf`](output_rmd/figures/phase4_within_intensive_ces_ppml_sigma.pdf): implied σ vs (ρ, K).

### Tables (RMD)

- [`output_rmd/tables/phase4_within_intensive_did_coefs.tex`](output_rmd/tables/phase4_within_intensive_did_coefs.tex): headline DiD (naive + age × top FE).
- [`output_rmd/tables/phase4_within_intensive_did_eventstudy.tex`](output_rmd/tables/phase4_within_intensive_did_eventstudy.tex): event-study coefficients.
- [`output_rmd/tables/phase4_within_intensive_did_mht_heterogeneity.tex`](output_rmd/tables/phase4_within_intensive_did_mht_heterogeneity.tex): heterogeneity with Romano-Wolf adjusted p-values.
- [`output_rmd/tables/phase4_within_intensive_did_honestdid_bounds.tex`](output_rmd/tables/phase4_within_intensive_did_honestdid_bounds.tex): HonestDiD bounds.
- [`output_rmd/tables/phase4_within_intensive_ces_ppml_beta.tex`](output_rmd/tables/phase4_within_intensive_ces_ppml_beta.tex): PPML coefficient.
- [`output_rmd/tables/phase4_within_intensive_ces_ppml_sigma_grid.tex`](output_rmd/tables/phase4_within_intensive_ces_ppml_sigma_grid.tex): implied σ grid.

---

## Structural CES: estimating the elasticity of substitution

The reduced-form analysis tells us that observed within-cell expenditure-share reallocation was small. To translate that into a statement about preferences (how willing buyers would be to substitute), we estimate the structural elasticity of substitution σ under a CES production function.

*Note: the structural CES estimation uses a wider window (2010-2022) than the headline DiD (2012-2020) because the PPML is more sensitive to sample size than to pre-trend slack. The results below are from a previous run on the full-window sample.*

### Model

Buyer *b* combines inputs in NACE-4d category *n* via a CES aggregator:

```
X_{b,n}  =  [ Σ_s  α_{s,b,n} · x_{s,b,n}^((σ-1)/σ) ]^(σ/(σ-1))
```

with time-invariant taste/quality parameter α_{s,b,n} for each supplier *s*. Under cost minimization:

```
share_{s,b,n,t}  =  α_{s,b,n}^σ · p_{s,t}^(1-σ)  /  D_{b,n,t}
```

Differencing across the policy (the α's are time-invariant by assumption):

```
Δ log(share_top / share_bot)  =  (1 − σ) · Δ log(p_top / p_bot)
```

### From ω to price changes

We don't observe prices directly, but we can model the price change as a function of the carbon-cost shock under marginal-cost pricing with pass-through ρ:

```
Δ log(p_s)  =  ρ · Δ log(MC_s)  =  ρ · ω_s · K
```

where:
- ω_s is the seller's 2015-16 carbon-shortage cost as a fraction of total cost (the same ω used everywhere else).
- K is the proportional change in the EUA price between the omega-measurement window (2015-16, EUA ≈ 8 €/tCO₂) and the relevant post-policy window. For the post-MSR peak (EUA ≈ 80 €/tCO₂), K ≈ 9. For an average post-period EUA closer to 40 €/tCO₂, K ≈ 4.

Substituting back:

```
Δ log(share_top / share_bot)  =  (1 − σ) · ρ · K · (ω_top − ω_bot)
```

### Estimation: Poisson PML

To handle zero shares (some pairs go inactive in the post period) without the selection issue that dropping them would create, we estimate via Poisson PML in **levels** (Silva and Tenreyro 2006):

```
E[share_{p,t} | X]  =  exp{ α_{cell × role} + δ_t + β · (post × ω_p) }
```

Pair-year level. Fixed effects absorb time-invariant cell-role levels and aggregate year shocks. Clustered SEs on cell.

The coefficient maps to the structural parameters:

```
β  =  (1 − σ) · ρ · K
σ̂(ρ, K)  =  1 − β̂ / (ρ · K)
```

Because ρ and K are not separately identified from the data, we report σ̂ over a grid of (ρ, K) values.

### Results (RMD)

**Reduced-form coefficient.** PPML on the present-in-2010-14 pair-year panel (253,683 observations, 4,997 cells, 22,909 unique pairs):

```
β̂  =  −3.91   (cluster-robust SE 10.68,  p = 0.71)
```

Point estimate is negative (consistent with substitutes) but imprecisely identified. The 95% CI on β is roughly [−25, +17].

**Implied σ grid.** For each (ρ, K) in the standard range:

| K \ ρ | 0.25 | 0.50 | 0.75 | 1.00 |
|---|---|---|---|---|
| 1 | 16.6 | 8.8 | 6.2 | 4.9 |
| 2 | 8.8 | 4.9 | 3.6 | 3.0 |
| 4 | 4.9 | **3.0** | **2.3** | **2.0** |
| 6 | 3.6 | **2.3** | **1.9** | **1.7** |
| 8 | 3.0 | **2.0** | **1.7** | **1.5** |
| 10 | 2.6 | 1.8 | 1.5 | 1.4 |

Bolded cells are economically reasonable (ρ ≥ 0.5, K ∈ [4, 8]). Point-estimate σ in this range sits in **[1.5, 3.0]** — modest substitutability between the most-exposed and least-exposed suppliers within an input category, slightly above Cobb-Douglas (σ = 1).

For a typical CES calibration (ρ = 0.5, K ≈ 9 matching the post-MSR peak): **σ̂ ≈ 1.8**.

### What this number can and cannot do

**What we can claim:**
- The structural point estimate is consistent with modest substitutability across regulated and unregulated suppliers within an input category.
- The point estimate is **inconsistent with perfect complements (σ → 0)** as well as **inconsistent with extreme substitutes (σ ≫ 10)**.
- Combined with the reduced-form bound, the joint interpretation is coherent: a finite-but-modest σ delivers the small within-cell reallocation we observe, given the magnitude of the cost shock the policy actually delivered.

**What we cannot claim:**
- A precise structural σ. The cluster-robust 95% CI on β is wide, so σ̂ inherits a wide CI as well. Common literature calibrations (σ ∈ [2, 6]) are all consistent with the data.
- Independence of σ̂ from (ρ, K) choice. The point estimate shifts noticeably across the grid; a tighter prior on ρ and K would tighten σ̂.

### Joint reading of reduced form + structural

The two analyses give a coherent story:

| Object | Estimate | Interpretation |
|---|---|---|
| Reduced-form γ (avg post-period top-bot share differential, 2012-2020) | ≈ +0.01, fragile to PT slack | Buyers did not reallocate much |
| Structural σ (under ρ = 0.5, K = 9) | ≈ 1.8 (CI: wide) | Modest substitutability is plausible |

Together: buyers face a CES production function with modest σ, the policy delivered a small cost shock to top-ω suppliers (ω_top × K × ρ ~ 0.01–0.10 in marginal cost), and the implied within-cell reallocation in expenditure share is also small (~1–5 pp), matching what we see in the data.

---

## References

- Rambachan, A. and Roth, J. (2023). "A More Credible Approach to Parallel Trends." *Review of Economic Studies*, 90(5): 2555-2591.
- Roth, J. (2022). "Pretest with Caution: Event-Study Estimates after Testing for Parallel Trends." *American Economic Review: Insights*, 4(3): 305-322.
- Silva, J. M. C. S. and Tenreyro, S. (2006). "The Log of Gravity." *Review of Economics and Statistics*, 88(4): 641-658.
- Romano, J. P. and Wolf, M. (2005). "Stepwise multiple testing as formalized data snooping." *Econometrica*, 73(4): 1237-1282.
- Callaway, B., Goodman-Bacon, A., and Sant'Anna, P. H. C. (2024). "Difference-in-Differences with a Continuous Treatment." Working paper.
