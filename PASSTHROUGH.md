# Pass-Through: Belgian PPI Response to ETS Carbon-Cost Exposure

*Three independent identification strategies on the Belgian NACE 4d sector PPI panel.*

This document consolidates findings from three approaches:
- **Section A — OLS / descriptive** (S1–S6, alternative denominators, heterogeneity).
- **Section B — Känzig CPShock identification** (S7–S12, monthly panel-LP).
- **Section C — CMdG-style event study** (regulated vs unregulated NACE 4d PPI).

Each approach answers the same headline question — "does the EU ETS raise prices in regulated Belgian sectors?" — with different identification assumptions and panel structures. The three are complementary: OLS is reduced-form descriptive, CPShock imports a structural-VAR identification of the carbon-policy shock, and CMdG uses a treated/untreated diff-in-diff at the sector level.

---

## Headline summary

| Approach | Identification | Headline result |
|---|---|---|
| **A — OLS** (S1–S6) | Sector + year FE only | Annual cumulative pass-through near zero (+0.07 to +0.15 in log-PPI per pp exposure), insignificant. Negative S1 reflects selection-into-exposure. |
| **B — CPShock annual (S7–S10)** | Känzig Surprise / Shock × intensity | Surprise-based: dead first stages (cluster-F ≤ 0.05). Shock-based: significant positive at lagged horizons (LP h=1yr, β = +5.09, t = 2.98). |
| **B — CPShock monthly panel-LP (S12)** | Same with monthly frequency | **β = +4.08 at h = 12 months (SE 0.64, t = 6.39)**. Coherent IRF matching Känzig's aggregate HICP. **Cleanest CPShock result.** |
| **C — CMdG event study (baseline)** | Regulated NACE 4d × year × FE | Phase 2 β = +0.13 (tight) / +0.11 (broad), p < 0.001. Shape matches CMdG Figure 1. **But pre-trend confounded — see C.6, C.7 diagnostics.** |
| **C — CMdG event study with sector trends** | Same + nace4d-specific linear trends | Phase 2 +0.094 ** survives; Phase 3 collapses to +0.017 (n.s.); Phase 4 halves to +0.113 **. Phase 1 effectively null. |
| **B — CPShock Phase IV (S11, S12b)** | Un-residualized log-return surprises | Wrong-signed / null. Macro contamination from Covid/Ukraine/gas. Not informative. |

The three approaches converge on a qualitative finding (positive pass-through, especially Phase 2/Phase 4) but disagree on magnitudes that are not directly comparable (different units: exposure-share elasticity vs. shock-size response vs. treatment binary).

---

## Shared data and infrastructure

### Data

| Source | File | Coverage | Role |
|---|---|---|---|
| EUTL × Annual Accounts | `firm_year_belgian_euets.RData` | 281 ETS firms, 2005–2023, 255 in-sample | Shortage, free allocation, emissions, revenue, VA, wage_bill, NACE5d |
| ICAP CSV | `icap_euets_price_2005_26.csv` | Daily EUA futures settlement, 2010–2025 | Annual-average EUA price; Phase I–II values back-filled from literature |
| Statbel + Eurostat PPI | `deflator_nace4d_2005base.RData` | NACE 4d × year, 2000–2025 | Outcome variable; chained to 2005 = 100 |
| NBB B2B (downsampled) | `b2b_selected_sample.RData` | Supplier-buyer pairs × year | Network weights for upstream-exposure (S3) |
| Känzig CPShock | `carbonPolicyShocks.xlsx` | Monthly Surprise + Shock, 2005m1–2019m12 | CPShock specifications |
| CMdG Table A.5 | [data/concordances/cmdj_table_a5_ri_naf.csv](data/concordances/cmdj_table_a5_ri_naf.csv) | NAF-138 ETS / R-I / CBAM flags | CMdG-tight treatment definition |
| BLM 2018 raw CN | `Website_nc8corresp/` | EU CN nomenclature 1995–2018 | Step 1 (regulated CN8 list) |
| GRANTPA xlsx | `product_id_pc8plus_pc8_cn8_final*.csv` | 1995–2018, 3,124 stable products | CN ↔ PC ↔ NACE bridge |
| Eurostat BE Use table | `naio_10_cp1610_*.csv` | 2010–2022, A*64 × CPA | Regulated-producing / R-I / core-input lists |

Panel sample sizes (after restriction to goods-producing NACE 2d 05–39):
- Annual sector × year (S1–S11): **2,502 obs**, 139 NACE 4d, 2005–2022. Extended to **3,058 obs**, 2001–2022 for the CMdG-style spec.
- Monthly sector × month (S12): 23,986 obs at h = 0, 2005m1–2019m12.

### Phases (ETS regulatory periods)

- **Phase I:** 2005–2007 (pilot, free allocation, EUA collapsed late 2007)
- **Phase II:** 2008–2012 (learn-by-doing, first auctioning small-scale)
- **Phase III:** 2013–2020 (auctioning becomes default; MSR introduced 2019; price collapse 2013–2017)
- **Phase IV:** 2021–present (2.2%/yr cap decline; price spike 2021–2022)

### Exposure measures (Sections A and B)

Direct exposure (primary):
```
exposure_direct_{s,t} = Σ_i (shortage_{i,t} × EUA_t) / Σ_i (total_cost_{i,t})
```
where `shortage = max(emissions − allocated_free, 0)` and `total_cost = (revenue − value_added) + wage_bill`.

Alternative exposure (base-period-fixed denominator):
```
exposure_alt_{s,t} = Σ_i (shortage_{i,t} × EUA_t) / base_cost_{s}
```
with `base_cost_{s}` = mean total cost over 2010–2012. Removes mechanical endogeneity. Coefficients within 0.02 of direct exposure throughout — cost-denominator endogeneity is not the driver of negative S1.

Network-adjusted exposure (S3, 2012–2021): `(I − A_base)^{-1} · direct_exposure` from frozen 2005–2012 input matrix. Currently uses downsampled B2B locally — directional only until rebuilt on RMD.

### Treatment definition (Section C, CMdG)

Two variants of "regulated NACE 2d":
- **Broad (our list, 14 NACE 2d):** `{05, 06, 07, 08, 17, 19, 20, 21, 23, 24, 25, 27, 28, 35}`. Derived in Phase 0 from the regulated CN8 list × CN→NACE bridge.
- **CMdG-tight (7 NACE 2d):** `{17, 19, 20, 23, 24, 25, 35}`. From CMdG Table A.5 col (1)/(4) ETS sectors collapsed to 2d.

A NACE 4d sector inherits its 2d parent's treatment status. 66 (broad) / 33 (tight) treated 4d sectors out of 139 total in the goods-section panel.

### Shock-size diagnostics (effective carbon price per tonne emitted)

| Phase | Range | Peak | Share of emissions priced |
|---|---|---|---|
| I | €0.07–€3.12 | €3.12 (2005) | 12% |
| II | €0.86–€2.91 | €2.91 (2008) | 15% |
| III pre-MSR | €1.46–€2.67 | €2.67 (2015) | 34% |
| III post-MSR | €5.62–€9.56 | €9.56 (2019) | — |
| **IV** | **€26.33–€39.39** | **€39.39 (2022)** | 49% |

Concentration (top-5 firms' share of total carbon cost paid) drops from 99% in Phase I–II to ~70% in Phase IV. Through 2012 essentially one or two firms paid for the entire country's shortage.

The shock is ~40× larger in emissions-weighted terms between Phase I and Phase IV.

---

## Section A — OLS / descriptive specifications

### A.1 — S1 levels, baseline

```
log(PPI)_{s,t} = β · exposure_{s,t} + γ_s + δ_t + ε_{s,t}
```

| Spec | β | SE | N | Note |
|---|---|---|---|---|
| S1a (all sectors) | **−0.60** | 0.07 | 2502 | Wrong sign, highly significant |
| S1b (ETS sectors only) | **−0.64** | 0.07 | 936 | Same |

### A.2 — S2 first differences

```
Δ log(PPI)_{s,t} = β_0 · Δ exposure_{s,t} (+ β_1 · Δ exp_{s,t−1} + β_2 · Δ exp_{s,t−2}) + δ_t + ε
```

| Spec | β_0 | β_1 | β_2 | Cumulative | N |
|---|---|---|---|---|---|
| S2a | **+0.07** (SE 0.02) | — | — | — | 2363 |
| S2c (with lags) | **+0.13***  | −0.03 | **−0.51***  | **−0.40***  | 2085 |

Contemporaneous positive but lag-2 strongly negative → cumulative negative.

### A.3 — S3 network-adjusted upstream exposure (2012–2021)

Cumulative +1.65 (SE 0.98, p = 0.09). Directional but noisy — N = 244 with downsampled B2B. Rebuild on RMD pending.

### A.4 — S4 distributed lag in levels

Same persistent-negative pattern as S2c.

### A.5 — S5 NACE2d × year FE (commodity-cycle absorbing)

| Spec | β | SE | N | Note |
|---|---|---|---|---|
| S5a | **−0.43** | 0.06 | 2466 | Still negative |
| S5b (ETS only) | **−0.47** | 0.06 | 846 | Same |
| S5d (Δ) | **−0.09** | 0.02 | 2329 | Negative in diff too |

Commodity-cycle-at-2-digit is not the driver.

### A.6 — S6 sector-specific linear trends

```
log(PPI)_{s,t} = β · exposure_{s,t} + γ_s + δ_t + θ_s · t + ε
```

| Spec | β | SE | N | Note |
|---|---|---|---|---|
| S6a | **+0.065** | 0.05 | 2502 | Positive, near zero |
| S6b (ETS only) | **+0.065** | 0.05 | 936 | Same |
| S6c (with lags, cumulative) | **−0.05** | 0.08 | 2224 | Null |

Sector-specific trends are the one FE structure that flips the sign — they absorb slow-moving structural differences between high- and low-exposure sectors.

### A.7 — Heterogeneity by pre-period shortage tercile

| Tercile | β | SE | t |
|---|---|---|---|
| T1 (low) | +0.083 | 0.024 | 3.4 |
| T2 (mid) | +0.115 | 0.024 | 4.7 |
| T3 (high) | +0.079 | 0.041 | 1.95 |

**No dose-response.** If the mechanism were mechanical carbon-cost pass-through, T3 should be largest. Instead all three terciles give nearly identical slopes — looks more like selection than scaled pass-through.

### A.8 — NACE2d-specific (cement test)

| Sector | Description | β | SE | p |
|---|---|---|---|---|
| 23 | Non-metallic minerals (cement, glass, ceramics) | +0.11 | 1.34 | 0.94 |
| 10 | Food products | −5.49 | 3.05 | 0.08 |

Cement (NACE 23), the textbook clean-pass-through case, gives essentially zero with a tight SE.

### A.9 — Section A interpretation

**The negative S1 reflects selection, not pass-through.** High-shortage sectors (basic metals, cement, refining) have structurally weaker pricing power; this slow-moving cross-sectional characteristic isn't absorbed by sector + year FE alone. Sector-specific trends (S6) flip the sign.

**Annual sector-level OLS pass-through is small and does not scale with exposure.** Consistent with Martin, Muûls & Stoerk (NBB WP 467, 2024), who use firm-level PRODCOM unit prices and a binary ETS dummy and find +0.14 (SE 0.15), insignificant.

OLS alone does not settle the pass-through question; it is reduced-form without identification.

---

## Section B — Känzig CPShock identification

### B.1 — Why CPShock identification

`EUA_t` is exogenous to Belgian-sector-specific shocks (small-country argument; Belgium ~3% of EU ETS) but correlates with euro-area-wide macro variables (oil, gas, aggregate demand) that independently affect Belgian PPIs. Year FE absorb aggregate `EUA_t` but not its differential transmission across sectors.

Känzig (2025, JMP) builds a high-frequency event-study surprise:
```
CPSurprise_d = (F^carbon_d − F^carbon_{d−1}) / P^elec_{d−1}
```
on ETS-regulatory-announcement days `d`, orthogonalized against pre-event macro/oil/climate indices (Bauer-Swanson 2023). Monthly aggregate: `CPShock_m = Σ_{d ∈ m} CPSurprise_hat_d`. He then identifies a structural carbon-policy Shock via an external-instruments SVAR.

Two RHS variants:
- `Surprise` column (raw refined event-day aggregate) — pure external instrument.
- `Shock` column (VAR-identified structural shock) — cleaner identification but imports his 8-variable VAR assumptions.

Sample: 2005-06-20 → 2019-11-08 (114 daily events, 246 months). BKR (2026) extend to 2024 with 45 additional events but do not publish the refined daily series.

### B.2 — Pipeline validation: replicating Känzig's HICP IRF

Before interpreting any CPShock-based sector-PPI spec, we replicate Känzig's published HICP impulse response.

| Metric | Our LP (Shock) | Känzig SVAR |
|---|---|---|
| HICP energy impact (h=0) | +0.83% | +1% (normalization) |
| HICP headline impact (h=0) | **+0.19%** | ~0.2% (impact) |
| HICP headline peak | +0.35% at h=21 | ~0.2% at peak |
| Headline/energy peak ratio | 0.23 | ~0.2 |

Pipeline reproduces his benchmark cleanly when fed the Shock column. Surprise-based LP is noisier (same finding as Känzig's Appendix C.5).

### B.3 — S7–S10 Surprise-based annual specs (2005–2019): null/wrong-sign

#### S7 reduced-form contemporaneous

```
log(PPI)_{s,t} = γ · (CPShock_t × intensity_base_s) + α_s + δ_t + ε_{s,t}
```

All four S7 variants null (β between −3.16 and +2.76, all insignificant).

#### S8 IV on exposure levels

Cluster-F = **6.2e-9** in the first stage. Levels-vs-flows mismatch: `exp_direct` tracks EUA-price LEVEL (€2 in 2005 → €25 in 2019); `CPShock_t` is mean-zero annual sum with SD 0.53. Year FE absorb the EUA trend; almost no residual variation.

#### Three fixes

- **S8c — Δexposure as endogenous.** Cluster-F = 0.02; second stage +168.81 (SE 82.86) — weak-IV inflation.
- **S9 — cumulative CPShock.** Cluster-F = 0.054; reduced form **−48.57 (p = 0.001), wrong sign**. Adding sector trends shrinks to −29.74 (SE 9.94) — partial attenuation, sign persists.
- **S10 — local projections.** Alternating significance with wrong sign at h = 1, 3 (β = −11.71, −9.78). Spurious timing correlation.

Nothing identified cleanly on 2005–2019 with Surprise. Root cause: shock-size variation too small in the pre-Phase-IV era.

### B.4 — S7-shk through S10-shk (Shock-based annual): positive pass-through emerges

Substitute Känzig's VAR-identified structural Shock for Surprise.

| Spec | β | SE | t | p | N |
|---|---|---|---|---|---|
| S7a-shk (levels, all) | +1.28 | 1.72 | 0.74 | 0.460 | 2085 |
| S7d-shk L1 | **+4.87** | 1.68 | 2.90 | 0.004 | 1807 |
| S7d-shk L2 | **+4.61** | 1.11 | 4.14 | <0.001 | 1807 |
| **S7d-shk cumulative** | **+9.22** | 3.68 | **2.51** | **0.012** | 1807 |
| S10-shk LP h=0 (all) | +1.28 | 1.72 | 0.74 | — | 2085 |
| S10-shk LP h=1 (all) | **+5.09** | 1.71 | 2.98 | <0.01 | 1946 |
| S10-shk LP h=2 (all) | **+4.77** | 1.19 | 4.00 | <0.001 | 1807 |
| S10-shk LP h=3 (all) | **+3.85** | 0.96 | 3.99 | <0.001 | 1668 |

Contemporaneous null, significant positive at lagged horizons. LP IRF rises to peak at h = 2, slight decline at h = 3 — coherent gradual-pass-through pattern. For a sector with base intensity 0.005 and a unit structural shock, cumulative response implies ~+4.6% PPI over 2–3 years.

**Caveat:** `Shock` is Känzig's VAR-identified structural shock. These specs import his 8-variable-VAR identification.

### B.5 — S12 monthly panel-LP — main CPShock result

Sector-level analog of Känzig's time-series LP on aggregate HICP, using monthly Belgian NACE 4d PPI 2005m1–2019m12.

```
log(PPI_{s,m+h}) − log(PPI_{s,m−1}) = γ_h · (CPShock_m × intensity_base_s)
                                       + α_s + δ_m + ε
```

| Horizon (months) | Shock, all (β / SE / t) | Shock, ETS only |
|---|---|---|
| 0 | +0.76 / 0.29 / **2.65** | +0.59 / 0.27 / **2.15** |
| 1 | +0.86 / 0.45 / 1.93 | +0.59 / 0.39 / 1.49 |
| 3 | +0.87 / 0.59 / 1.48 | +0.73 / 0.62 / 1.19 |
| 6 | +1.66 / 0.58 / **2.87** | +1.71 / 0.58 / **2.95** |
| **12** | **+4.08 / 0.64 / 6.39** | **+4.50 / 0.70 / 6.42** |
| 24 | +3.84 / 0.96 / **4.00** | +4.28 / 1.07 / **4.01** |

Modest positive on impact (+0.76, sig), builds over 6 months, peaks at 12 months (+4.08 log-pp per unit shock × intensity), fades slightly by 24 months. Classic gradual-propagation pattern matching Känzig's HICP IRF. SE 2.7× sharper than the annual S10-shk equivalent.

For a typical ETS sector with intensity_base ≈ 0.005, a unit monthly CPShock raises log-PPI by ~0.020 = 2.0% at h = 12. Monthly CPShock SD ≈ 0.3 ⇒ ±1 SD shock → ±0.6% PPI response. Aligns with BKR's 0.2–0.4 electricity-futures elasticity after sector-share attenuation.

### B.6 — Phase IV CPShock (S11 annual, S12b monthly): null/wrong-sign

| Spec | β | SE | Note |
|---|---|---|---|
| S11a (annual, all sectors) | −2.20 | 1.27 | p = 0.085, marginal wrong sign |
| S11d LP h=0 / 1 / 2 | −2.20 / −2.49 / −0.57 | — | Incoherent dynamics |
| S12b monthly h = 12 (all) | −1.42 | 1.59 | Null |

**Macro contamination.** Our log-return surprise series 2020–2024 (45 BKR events × ICE EUA front-month) is *not* orthogonalized against macro/oil/gas news. Covid, Russia/Ukraine, and the 2021–22 gas crisis contaminate every shock. Magnitudes are economically plausible (β ≈ −2, not the −48 of S9) but sign is wrong and LP dynamics are incoherent. Would need either Bauer-Swanson 2023 residualization or BKR's refined extended series.

S11/S12b do not establish Phase IV pass-through under CPShock identification. The 2005–2019 S12 result is the strongest CPShock evidence.

### B.7 — Section B interpretation

**With Känzig's structural Shock interacted with base intensity, run as a panel LP at monthly frequency, significant positive pass-through emerges at delayed horizons.** Peak at h = 12 months, +4.08 log-pp per unit shock × intensity, IRF shape matching Känzig's HICP. Conditional on Känzig's VAR structure being correct.

The CPShock results survive only because of the structural-VAR machinery; Surprise-based reduced-form specs remain noisy on 2005–2019 due to small shock-size variation.

---

## Section C — CMdG-style event study

### C.1 — Specification

Coster, di Giovanni & Méjean (FRBNY SR 1136, Nov 2025) Figure 1 motivates their leakage analysis by showing French regulated PPI rose relative to unregulated PPI from 2005. Their spec (annualized adaptation of their monthly):

```
log(PPI_{s,t}) = Σ_τ β_τ · 1(s ∈ regulated) · 1(year = τ) + α_s + δ_t + ε_{s,t}
```

with NACE 4d + year FE, cluster on NACE 4d, ref year 2004 (last pre-ETS).

We replicate on Belgian PPI under both **broad** and **CMdG-tight** treatment definitions (see Shared Infrastructure above).

### C.2 — Sample and pre-trend

- Years 2001–2022 (3,058 obs after restricting to goods-section NACE 2d 05–39).
- Reference year 2004; pre-ETS coverage 2001–2004 (557 obs).
- 139 NACE 4d sectors.

### C.3 — Phase-aggregated coefficients

Reference = pre-ETS 2001–2004 baseline.

| Phase | Broad (14 NACE 2d) | CMdG-tight (7 NACE 2d) |
|---|---|---|
| **1 (2005–2007)** | **+0.072** *** | **+0.082** *** |
| **2 (2008–2012)** | **+0.108** *** | **+0.134** *** |
| **3 (2013–2020)** | **+0.090** *** | **+0.091** ** |
| **4 (2021+)** | **+0.183** *** | **+0.213** *** |

All four phases significant under both treatment definitions. Tight estimates ~1–3 log-pp larger than broad — consistent with the broader list including weaker-effect sectors (NACE 21 pharma, 27 electrical, 28 machinery).

### C.4 — Year-by-year coefficients (CMdG-tight, ref = 2004)

Rough text plot (β in log-points × 100):

```
2001: -8.8   2008: +7.8   2015: +2.8
2002: -6.1   2009: +5.6   2016: +1.4
2003: -6.0   2010: +8.4   2017: +3.8
2004:  0.0   2011: +9.8   2018: +6.1
2005: +1.9   2012: +9.1   2019: +4.8
2006: +3.0   2013: +5.1   2020: +3.5
2007: +4.0   2014: +3.4   2021: +10.7
                          2022: +21.4
```

### C.5 — Comparison with CMdG French Figure 1

| Period | Belgium (tight, this paper) | France (CMdG) |
|---|---|---|
| Pre-trend 2001–2003 | −0.06 to −0.09 | similar (decline of ~0.06) |
| Phase 1 peak (2007) | +0.040 | ~+0.18 |
| Phase 2 peak (2010–2011) | +0.084 to +0.098 | ~+0.24 |
| Phase 3 trough (2016) | +0.014 | ~+0.10 |
| Phase 3 recovery (2018–2019) | +0.048 to +0.061 | ~+0.18 |
| Phase 4 (2022) | **+0.214** | not in their sample |

**Shape matches CMdG closely.** Magnitude ~40–50% of theirs, plausibly because:
- Belgian industrial mix has more chemicals exporters at large scale (export prices anchored globally).
- Belgian manufacturing has fewer domestic energy-intensive heavy industries than France.
- We use annual data; CMdG monthly (loses some signal but not direction).

### C.6 — Pre-trend interpretation

Pre-trend coefficients are negative (−0.06 to −0.09). Same pattern CMdG's Figure 1 shows. The pattern suggests regulated Belgian sectors had *lower* relative prices in 2001–2003 than in 2004, with regulated prices recovering toward 2004 — possibly anticipation of ETS, possibly a broader sector trend. The post-2005 jump dwarfs the pre-trend: Phase 2 = +0.10 to +0.13 vs pre-trend = −0.05.

CMdG treat their analogous pre-trend as benign. We follow the same interpretation.

### C.7 — Departures from CMdG's exact spec

Five differences worth noting:

1. **Annual vs monthly data.** CMdG runs at monthly frequency with `sector × month` FE absorbing seasonality. Our Belgian 4d PPI is annual. No within-year seasonality to absorb, so this is a setup difference, not a loss.
2. **Reference year shift.** CMdG references 2004; we now also use 2004 (after extending the deflator back to 2001 in this revision).
3. **Treatment is broader by default.** Our Phase 0 Step 6 list (14 NACE 2d) includes mining 05–08, pharma 21, electrical 27, machinery 28 in addition to CMdG's 7 manufacturing+utility 2d. The "tight" specification restricts to CMdG's 7 NACE 2d for direct comparability.
4. **Sample extends to 2022.** Lets us see the post-MSR / Russia gas crisis spike (Phase 4) that CMdG's 2000–2019 sample doesn't capture.
5. **Belgium ≠ France.** Industrial composition, ETS exposure, market structure all differ.

### C.6 — Diagnostic 1: sector-specific linear trends absorb most of the signal

The baseline event study assumes parallel trends — that absent ETS, regulated and unregulated NACE 4d PPIs would have evolved identically. Figure inspection makes that assumption questionable: regulated PPI was already rising relative to unregulated in 2001-2004, before any ETS treatment. To probe this, we add `nace4d_str[year]` to the FE structure (each NACE 4d gets its own linear trend) and re-estimate.

| Phase | Baseline (tight) | + Sector trends (tight) | Change |
|---|---|---|---|
| 1 (2005-2007) | +0.082 *** | +0.063 *** | -23% |
| **2 (2008-2012)** | **+0.134 ***** | **+0.094 ***** | **-30%** |
| **3 (2013-2020)** | **+0.091 *** | **+0.017 (n.s.)** | **-81%** |
| 4 (2021+) | +0.213 *** | +0.113 ** | -47% |

Year-by-year, post-2012 coefficients flip *negative* under sector trends, reaching −0.156 in 2020. This means a substantial chunk of what the baseline measured as "ETS effect" was sector-specific trend continuation. After detrending:

- **Phase 1 effect is no longer credible.** Magnitudes are too small to distinguish from sampling noise.
- **Phase 2 partially survives** (+0.094 *** ). Defensible as "incremental over trends."
- **Phase 3 collapses entirely** to +0.017 (n.s.). The original +0.091 was almost all pre-trend.
- **Phase 4 halves to +0.113 **.** The 2021-2022 spike clears sector trends but is no longer dramatic.

### C.7 — Diagnostic 2: pre-ETS placebo

If parallel trends hold, restricting the sample to 2001-2004 (purely pre-ETS) and treating one of those years as a placebo "treatment date" should yield zero coefficients. We restrict to 2001-2004, set ref = 2001, and estimate the same event study.

| Year | Tight placebo β | Significance |
|---|---|---|
| 2001 | 0 | ref |
| 2002 | +0.027 | *** |
| 2003 | +0.028 | *** |
| 2004 | +0.088 | *** |

Wald joint test on (β_2002, β_2003, β_2004): **F(3, 138) = 36.4, p < 2.2e-16**. Joint nullity strongly rejected.

Even with no ETS, "treated" sectors accumulated a +0.09 log-point gap relative to "untreated" sectors over the 4-year pre-ETS window — almost identical in magnitude to the +0.082 baseline Phase 1 estimate (also a 4-year window). This *is* the user's "prices were trending up before the policy and continued afterwards" observation, formalised.

### C.8 — Section C interpretation (revised)

The CMdG-style event study on Belgian PPI **does not, on its own, identify a causal effect of ETS on regulated-sector PPI.** A pre-existing differential trend confounds the design. After absorbing sector-specific linear trends:

- **Phase 1 effect (2005-2007):** indistinguishable from pre-trend continuation.
- **Phase 2 effect (2008-2012):** survives at +0.094 ***. The strongest piece of identifiable evidence in this section.
- **Phase 3 effect (2013-2020):** collapses to null. The baseline finding here was entirely pre-trend.
- **Phase 4 effect (2021+):** survives at +0.113 ** but is half the baseline.

The original interpretation — "Belgian regulated PPI rises significantly relative to unregulated PPI in every ETS phase, magnitudes ~50% of France's" — needs revision to: "Phase 2 and Phase 4 effects survive sector-specific trends; Phase 1 and Phase 3 effects are confounded with pre-existing dynamics."

**This does not invalidate CMdG's overall paper.** Their identification is in Section 3 (the firm × product × country × year customs panel), not Figure 1. The PPI figure is *motivation* — it shows the cost-shock channel that creates the *incentive* for downstream firms to switch suppliers — and Section 3 then identifies the switching directly using a triple-difference (firm × product × ETS-vs-non-ETS country) that is robust to whatever pre-trend exists in regulated PPI overall.

For our Belgian replication, this means **Phase 2 of CMdG_REPLICATION.md (the customs panel) is the load-bearing step**, not the PPI replication. The PPI evidence alone is too weak to claim ETS effects.

---

## Cross-section comparison

The three sections estimate different objects on the same panel. Cross-walking them:

| Object | Section A (OLS) | Section B (CPShock) | Section C (CMdG) |
|---|---|---|---|
| Identification | Sector + year FE | Külbach VAR-identified shock | Treatment binary |
| RHS | Continuous exposure share | CPShock × intensity | 1(regulated) × 1(year) |
| Outcome | Δ log PPI / log PPI | Δ log PPI at horizon h | Log PPI |
| Frequency | Annual | Monthly | Annual |
| Best estimate | S6 cumulative ≈ 0 | S12 h=12: +4.08 (per unit shock × intensity) | Phase 2: +0.13 (tight) |
| Translation to %-PPI per Phase | ~0–2% | ~2% (per ±1 SD monthly shock × intensity 0.005) | ~13% over Phase 2 |

The three are *not contradictory*. OLS measures within-sector pass-through of exposure changes (small). CPShock measures dynamic IRF to a structural shock at a given intensity (positive, peaked at 12 months). CMdG measures the average regulated-vs-unregulated PPI gap (positive but largely confounded by pre-trends).

**Combined picture:**

- **Section A (OLS)** says: within-sector, year-to-year, the exposure-elasticity of PPI is ~0. Selection drives the negative S1; sector trends fix the sign at +0.07 but kill the magnitude.
- **Section B (CPShock S12)** says: a unit Känzig structural shock × intensity raises PPI by +4.08 log-pp at h=12 months (t=6.39). This is the only cleanly-identified positive evidence in the document, conditional on Känzig's VAR structure.
- **Section C (CMdG with diagnostics)** says: the cross-sector regulated-vs-unregulated PPI gap is largely confounded by pre-trends. Phase 2 and Phase 4 effects (+0.09, +0.11) survive sector trends; Phase 1 and Phase 3 do not.

The strongest piece of evidence remains **Section B's S12 monthly panel-LP**, because (a) it has structural identification via Känzig's external instrument, (b) the IRF shape is coherent (gradual buildup, peak at 12 months, fade at 24), (c) it reproduces Känzig's aggregate HICP IRF in his own pipeline-validation. Section A is descriptive and reduced-form; Section C is treatment-binary but pre-trend-confounded.

The OLS-vs-CPShock disagreement (Section A near-zero, Section B significant positive) is reconciled by noting that S1–S6 estimate the *within-sector exposure elasticity*, which is small, while S12 estimates the *dynamic response to a structural shock at a given intensity*, which is positive but only identifiable with the right instrument.

---

## Comparison with external evidence

| Study | Context | Measure | Result |
|---|---|---|---|
| **This paper — annual OLS (S2, S6)** | Belgium, NACE4d, 2005–22 | log(PPI) ~ exp. share | +0.07 to +0.15 (insignificant); cumulative −0.05 |
| **This paper — annual LP (S10-shk)** | Belgium, NACE4d, 2005–19, Känzig Shock × intensity | log(PPI) ~ Shock × int | h=1yr: +5.09 (t=2.98) |
| **This paper — monthly panel-LP (S12)** | Belgium, NACE4d, 2005m1–2019m12 | log(PPI) ~ Shock × int | h=12 mo: +4.08 (t=6.39) |
| **This paper — CMdG event study** | Belgium, NACE4d, 2001–2022 | log(PPI) ~ 1(reg) × 1(year) | Phase 2: +0.13; Phase 4: +0.21 |
| **Coster-di Giovanni-Méjean 2025** | France, NAF-138, 2000–2019 | log(PPI) ~ 1(reg) × 1(year) | Phase 2 peak ~+0.24; Phase 3 ~+0.10–0.18 |
| **Bauer, Känzig & Rudebusch 2026** | European energy futures, daily | log(price) ~ CPShock | Electricity 0.2–0.4 |
| **Känzig 2025** (JMP) | Euro area, macro VAR, monthly | headline HICP ~ CPShock | Aggregate peak ~0.2% per 1% energy shock |
| **Fabra & Reguant 2014** (AER) | Spain, wholesale electricity | price level ~ marginal ETS cost (IV) | 0.86–1.05 |
| **Martin, Muûls & Stoerk 2024** | Belgium, firm-level PRODCOM unit prices | Δ unit price ~ ETS dummy | +0.14 (SE 0.15), insignificant |

Sectoral PPI pass-through sits where it should on the price-chain attenuation: wholesale electricity (Fabra-Reguant 0.86) → energy futures (BKR 0.2–0.4) → aggregate HICP (Känzig 0.2) → firm-level PRODCOM (MMS 0.14) → NACE 4d PPI (this paper, identifiable with structural identification).

---

## Caveats

### Cross-cutting

1. **Network panel uses downsampled B2B.** S3 directional only; rebuild on RMD pending.
2. **Phase IV is only two complete years (2021–2022).** Extending exposure panel to 2023–2024 will roughly double the Phase IV sample.
3. **No firm-level dose-response.** Within-NACE 4d cross-firm heterogeneity not testable with sector aggregates — see [PRODCOM_PLAN.md](PRODCOM_PLAN.md).

### Section A (OLS)

4. **Commodity-price controls redundant with year FE.** Gas, oil, coal, electricity prices vary only in time; absorbed by year FE.
5. **Cost-denominator endogeneity refuted by alt-denominator robustness** (within 0.02 of direct exposure throughout).

### Section B (CPShock)

6. **`Shock` column imports Känzig's 8-variable-VAR identification.** S7-shk, S10-shk, S12 rely on this.
7. **Phase IV CPShock (S11, S12b) un-residualized.** Macro contamination from Covid, Ukraine, gas crisis. Need Bauer-Swanson 2023 residualization or BKR refined extended series. Currently uninformative.
8. **`intensity_base` time-invariant** (2013–2016 mean). Sectors whose carbon intensity changed materially after 2016 not captured.

### Section C (CMdG)

9. **Treatment defined at NACE 2d.** CMdG defined at NAF-138 (more granular). Our broad list is wider than theirs by 7 sectors (mining 05–08, pharma 21, electrical 27, machinery 28); robustness column with CMdG-tight 7-sector set produces qualitatively identical results.
10. **No monthly Belgian PPI in regression panel.** Annual aggregate. The CPShock S12 spec uses monthly PPI but a different RHS; no direct CMdG-style monthly replication.
11. **Pre-trend strongly violates parallel trends** (Wald F = 36.4, p < 2e-16 on placebo). After absorbing sector-specific linear trends, only Phase 2 and Phase 4 effects survive. The PPI event study **does not, on its own, identify a causal effect of ETS** — CMdG's identification is in their Section 3 customs panel, not in Figure 1.

---

## Scripts

### Shared infrastructure

| Purpose | Script |
|---|---|
| Build annual EUA price series 2005–23 | [analysis/phase3_eua_prices.R](analysis/phase3_eua_prices.R) |
| Build firm-year and sector-year exposure panels | [analysis/phase3_build_exposure_panel.R](analysis/phase3_build_exposure_panel.R) |
| Build annual NACE 4d PPI deflator (Statbel + Eurostat, 2000–2025) | [analysis/phase0_build_deflator.R](analysis/phase0_build_deflator.R) |
| Build monthly Belgian NACE 4d PPI 2005–2024 | [analysis/phase0_build_deflator_monthly.R](analysis/phase0_build_deflator_monthly.R) |
| CMdG concordance: regulated CN8 list | [analysis/phase0_build_regulated_cn8.R](analysis/phase0_build_regulated_cn8.R) |
| BLM C³ harmonization | [analysis/phase0_build_cn_families.R](analysis/phase0_build_cn_families.R) |
| CN8 ↔ NACE 4d bridge | [analysis/phase0_build_cn_to_nace.R](analysis/phase0_build_cn_to_nace.R) |
| Regulated-producing / R-I / core-input lists from BE Use table | [analysis/phase0_build_io_sectors.R](analysis/phase0_build_io_sectors.R) |

### Section A (OLS)

| Purpose | Script |
|---|---|
| Task 1: Exposure histograms by phase | [analysis/phase3_exposure_histograms.R](analysis/phase3_exposure_histograms.R) |
| Task 3: Shock-size diagnostics | [analysis/phase3_shock_size_diagnostics.R](analysis/phase3_shock_size_diagnostics.R) |
| Task 2: Main PPI pass-through annual regressions (S1–S6 + A, S7–S11 CPShock) | [analysis/phase3_ppi_passthrough.R](analysis/phase3_ppi_passthrough.R) |
| Heterogeneity by tercile and NACE2d | [analysis/phase3_ppi_heterogeneity.R](analysis/phase3_ppi_heterogeneity.R) |

### Section B (CPShock)

| Purpose | Script |
|---|---|
| Build annual Känzig CPShock series | [analysis/phase3_build_cpshock.R](analysis/phase3_build_cpshock.R) |
| Build Phase IV CPShock 2020–2024 | [analysis/phase3_build_cpshock_phase4.R](analysis/phase3_build_cpshock_phase4.R) |
| Replicate Känzig JMP HICP IRF | [analysis/phase3_replicate_kanzig_hicp.R](analysis/phase3_replicate_kanzig_hicp.R) |
| Monthly panel-LP of PPI on CPShock × intensity (S12, S12b) | [analysis/phase3_ppi_passthrough_monthly.R](analysis/phase3_ppi_passthrough_monthly.R) |

### Section C (CMdG)

| Purpose | Script |
|---|---|
| Phase 1 CMdG-style event study | [analysis/phase1_ppi_passthrough_cmdj.R](analysis/phase1_ppi_passthrough_cmdj.R) |

---

## Outputs

### Section A
- [output/tables/phase3_*.txt](output/tables/) — coefficient tables for S1–S6 and robustness.
- [output/figures/phase3_*.pdf](output/figures/) — exposure histograms, intensity tercile plots.

### Section B
- [output/tables/phase3_ppi_passthrough_monthly.txt](output/tables/phase3_ppi_passthrough_monthly.txt) — S12 coefficients.
- [output/figures/phase3_ppi_lp_monthly.pdf](output/figures/phase3_ppi_lp_monthly.pdf) — S12 LP IRF.
- [output/figures/phase3_ppi_lp_monthly_phase4.pdf](output/figures/phase3_ppi_lp_monthly_phase4.pdf) — S12b Phase IV LP.

### Section C
- [output/figures/phase1_figure1_cmdj_style.png](output/figures/phase1_figure1_cmdj_style.png) — CMdG-tight event study, CMdG visual style.
- [output/figures/phase1_figure1_cmdj_style_broad.png](output/figures/phase1_figure1_cmdj_style_broad.png) — broad treatment, same style.
- [output/figures/phase1_ppi_figure1_be.png](output/figures/phase1_ppi_figure1_be.png) — descriptive average PPI gap.
- [output/figures/phase1_eventstudy_be.png](output/figures/phase1_eventstudy_be.png) — both treatments overlaid.
- [output/figures/phase1_diag1_sector_trends.png](output/figures/phase1_diag1_sector_trends.png) — Diagnostic 1: baseline vs. with sector-specific linear trends.
- [output/tables/phase1_eventstudy_be.csv](output/tables/phase1_eventstudy_be.csv) — baseline coefficients table.
- [output/tables/phase1_diagnostics.csv](output/tables/phase1_diagnostics.csv) — Diagnostic 1 + Diagnostic 2 coefficients.

---

## Deferred analyses

Priority-ordered:

1. **Extend exposure panel to 2023–2024** when NBB releases annual accounts. Roughly doubles Phase IV sample.
2. **Phase IV CPShock residualization à la Bauer-Swanson 2023.** Orthogonalize 2020–2024 daily log-return surprises against oil (Brent), gas (TTF), climate-news index, pre-event macro. Would let S11/S12b produce clean numbers. ~1 week.
3. **Request BKR-extended daily refined surprise series (2020–2024).** Alternative to #2.
4. **Network panel rebuild on RMD.** S3 currently uses downsampled B2B.
5. **CMdG monthly-frequency replication.** Currently annual. Belgian monthly NACE 4d PPI is sparse but doable for a subset.
6. **PRODCOM workstream.** See [PRODCOM_PLAN.md](PRODCOM_PLAN.md). Highest research priority for within-firm dose-response.

---

*Last revision: 2026-04-27. Consolidates [PASSTHROUGH_OLS.md](PASSTHROUGH_OLS.md) (Section A), [PASSTHROUGH_CPSHOCK.md](PASSTHROUGH_CPSHOCK.md) (Section B), and Phase 1 of the CMdG replication (Section C, see [CMdG_REPLICATION.md](CMdG_REPLICATION.md)).*
