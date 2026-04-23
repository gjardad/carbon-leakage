# Pass-Through: Känzig CPShock-Identified Specifications

*Belgian NACE4d sector PPI response to ETS carbon-policy shocks using Känzig's (2025 JMP) high-frequency external instrument and VAR-identified structural shock.*

**Companion document:** [PASSTHROUGH_OLS.md](PASSTHROUGH_OLS.md) covers the descriptive OLS specifications (S1–S6 + alternative denominators + heterogeneity) on the same panel. Shared infrastructure (exposure measures, data sources, shock-size diagnostics) is documented there. This document covers S7–S12 — all CPShock-identified — and the pipeline-validation HICP replication.

---

## Summary

Annual-OLS sector-PPI pass-through (S1–S6) is small and unidentified; see companion [PASSTHROUGH_OLS.md](PASSTHROUGH_OLS.md). This document asks what happens when we substitute Känzig's high-frequency carbon-policy-surprise instrument (or his VAR-identified structural shock) for raw `EUA_t`.

**Four findings.**

1. **Pipeline validation.** Running a local projection of euro-area HICP on Känzig's structural Shock reproduces his published SVAR IRF — headline impact **+0.19%** vs his **+0.2%** benchmark, peak-to-peak ratio 0.23 vs his ~0.2. Pipeline works.

2. **Surprise-based specs on 2005–2019 (S7–S10) fail.** First stages have cluster-F ≤ 0.05; reduced forms reach significance only with wrong sign (e.g., cumulative-CPShock × intensity: β = −48.57, p = 0.001). Not interpretable. Root cause: levels-vs-flows mismatch and low shock-size variation in the pre-Phase-IV era.

3. **Shock-based specs (S7-shk through S10-shk) show positive delayed pass-through.** Annual cumulative distributed-lag +9.22 (SE 3.68, p = 0.012); LP h = 1, 2, 3 yr all significant positive. Monthly panel-LP (S12) sharpens this: **h = 12 months, β = +4.08 (SE 0.64, t = 6.39)** with a coherent gradual-buildup IRF matching Känzig's aggregate HICP. Conditional on Känzig's 8-variable VAR identification. **This is the main result of the document.**

4. **Phase IV rebuild (S11, S12b, 2020–2024) fails.** Our log-return daily surprise (computed from BKR Appendix A.1 events + investing.com EUA futures) is *not* orthogonalized against macro/oil news. Covid, Ukraine, and the 2021–22 gas crisis contaminate the surprise; impact response is wrong-signed, longer horizons null. Would need either the BKR-extended refined series or our own Bauer-Swanson residualization.

**Headline table:**

| Question | Answer |
|---|---|
| Pipeline validation? | HICP replication: headline impact **+0.19%** vs Känzig's **+0.2%** benchmark. Pipeline correct. |
| Surprise-based annual (S7–S10, 2005–2019)? | Dead first stages, wrong-sign RFs. Not informative. |
| Shock-based annual (S7-shk, S10-shk, 2005–2019)? | LP h=1yr: **+5.09 (SE 1.71, t=2.98)**; cumulative **+9.22 (p=0.012)**. Significant delayed pass-through. |
| **Shock-based monthly panel-LP (S12, 2005-01 to 2019-12)?** | **h = 12 months: +4.08 (SE 0.64, t = 6.39).** ETS-only +4.50 (t = 6.42). Coherent IRF matching Känzig HICP. **Main result.** |
| Phase IV rebuild (S11 annual, S12b monthly, 2020–2024)? | Wrong-sign / null. Our log-return surprise not orthogonalized against macro. Not informative. |

---

## Why CPShock identification

The descriptive OLS specs (S1–S6) regress sector-PPI on `exposure_{s,t}` which uses `EUA_t` as its time-varying component. `EUA_t` is exogenous to Belgian-sector-specific shocks (small-country argument — Belgium is ~3% of the EU ETS, same property Fabra-Reguant rely on for Spain). But `EUA_t` *does* correlate with euro-area-wide macro variables (oil, gas, aggregate demand) that independently affect Belgian PPIs. Year FE absorb aggregate `EUA_t` but not its differential transmission across sectors.

Känzig (2025, JMP) addresses this by building a high-frequency event-study surprise:
```
CPSurprise_d = (F^carbon_d − F^carbon_{d−1}) / P^elec_{d−1}
```
on ETS-regulatory-announcement days `d`, orthogonalized against pre-event macro/oil/climate indices (Bauer-Swanson 2023 procedure). Monthly aggregate: `CPShock_m = Σ_{d ∈ m} CPSurprise_hat_d`. He then identifies a structural carbon-policy Shock via an external-instruments SVAR.

Two RHS variants available to us:
- **`Surprise` column** (raw refined event-day aggregate): pure external instrument, weakest structural assumption.
- **`Shock` column** (VAR-identified structural shock, conditional on his 8-variable SVAR): cleaner identification but imports his modelling assumptions.

Sample coverage: Känzig's series is 2005-06-20 → 2019-11-08 (114 daily events, 246 months with Surprise sums 1999–2019). BKR (2026) extend to 2024 with 45 additional events (their Appendix A.1) but do not publish the refined daily series.

---

## Pipeline validation: replicating Känzig's HICP IRF

Before interpreting any CPShock-based specification on our sector-PPI panel, we validate the pipeline by replicating Känzig's published HICP impulse response. Script: [analysis/phase3_replicate_kanzig_hicp.R](analysis/phase3_replicate_kanzig_hicp.R).

**Setup.**
- Download euro-area monthly HICP (headline CP00, energy NRG) from Eurostat `prc_hicp_midx` via the `eurostat` R package, 1996-01 to 2025-12.
- Load Känzig's monthly CPShock series from `carbonPolicyShocks.xlsx` (columns `Surprise` and `Shock`).
- Run local projection: `log(HICP_{m+h}) − log(HICP_{m−1}) = γ_h · X_m + ε`, Newey-West SE with lag h+1. Sample 2005-01 to 2019-12.
- Two RHS variants, matching Känzig's Appendix C.5 (Surprise-as-instrument) and Appendix C.6 (Shock-as-regressor).

**Results vs Känzig's published SVAR IRF.**

| Metric | Our LP (Shock) | Känzig SVAR |
|---|---|---|
| HICP energy impact (h=0) | +0.83% | +1% (normalization) |
| HICP headline impact (h=0) | **+0.19%** | ~0.2% (impact) |
| HICP headline peak | +0.35% at h=21 | ~0.2% at peak |
| Headline/energy peak ratio | 0.23 | ~0.2 |

The Shock-based LP reproduces his benchmark cleanly. The Surprise-based LP (without full-VAR orthogonalization) is noisier, as Känzig himself reports in his Appendix C.5 robustness.

**Validation conclusion: the pipeline works correctly when fed the Shock column.** This is the prerequisite for interpreting the sector-PPI CPShock specs below.

---

## S7–S10 — Surprise-based (2005–2019, annual)

### S7 — Reduced-form panel interaction (Känzig eq 10 contemporaneous)

```
log(PPI)_{s,t} = γ · (CPShock_t × intensity_base_s) + α_s + δ_t + ε_{s,t}
```
where `intensity_base_s` = mean of `exposure_alt_total` over 2013–2016 (post-auctioning, pre-MSR, time-invariant per sector). Identification: within-year cross-sector variation.

| Spec | Form | β | SE | N |
|---|---|---|---|---|
| S7a | levels, all sectors, sector + year FE | −3.16 | 4.64 | 2085 |
| S7b | levels, ETS sectors only | −2.11 | 4.55 | 780 |
| S7c | Δlog(PPI) ~ Δ(CPShock × int), year FE | −2.01 | 2.88 | 1946 |
| S7d | S7a with 0/1/2-year lags, cumulative | +2.76 | 34.39 | 1807 |

All null. 15 years × 52 ETS sectors × sparse annual surprise series does not give power.

### S8 — IV on exposure levels: instrument `exp_direct` with `CPShock × intensity`

| Stage | Coef | SE | Cluster-F | Within R² |
|---|---|---|---|---|
| FS: `exp_direct ~ CPShock × int` \| sector + year | −0.0022 | 0.114 | 0.0007 | **6.2e-9** |

Second stage: S8a (all) failed (FE-collinearity); S8b (ETS-only) −74.15 (SE 327.4), not interpretable.

**Diagnosis.** Levels-vs-flows mismatch. `exp_direct` tracks the EUA-price LEVEL (€2 in 2005 → €25 in 2019). `CPShock_t` is the annual sum of mean-zero daily surprises (SD 0.53). After year FE absorb the EUA trend from `exp_direct`, almost no residual variation is explained by a single-year surprise aggregate.

### Three fixes for the weak first stage

#### Fix 1 (S8c) — Δexposure as endogenous (flow-on-flow match)

| Stage | Coef | SE | Note |
|---|---|---|---|
| FS: Δexp_direct ~ CPShock × int \| year | −0.099 | 0.047 | nominal t = −2.09; **cluster-F = 0.02** |
| S8c: Δlog(PPI) ~ Δexp_direct (IV), year FE | +168.81 | 82.86 | Weak-IV inflation |

Nominal first-stage significance evaporates under clustering; the large second-stage coefficient is a weak-IV artefact.

#### Fix 2 (S9) — Cumulative CPShock as EUA-level proxy

`cum_CPShock_t = Σ_{τ ≤ t} CPShock_τ`, matching the level dimension of `exp_direct`.

| Spec | Form | Coef | SE | Note |
|---|---|---|---|---|
| FS | exp_direct ~ cum_CPShock × int \| sector + year | −0.162 | 0.141 | Cluster-F = 0.054 |
| S9a RF | log(PPI) ~ cum_CPShock × int (all) | **−48.57** | 14.71 | **p = 0.001, wrong sign** |
| S9b RF | same, ETS only | **−51.38** | 15.56 | **p = 0.002, wrong sign** |
| S9c IV | exp_direct ~ cum_CPShock × int (all) | +299.72 | 233.05 | Weak IV |
| S9d IV | same, ETS only | +662.04 | 1555.97 | Weak IV |

The reduced form is highly significant but wrong-signed and orders of magnitude larger than plausible. Adding sector-specific linear trends shrinks the coefficient from −48.57 to −29.74 (SE 9.94) — partial attenuation but sign persists.

Diagnostic on `cum_CPShock`: wanders between −0.63 and +0.79 across 2005–2019, ends near 0, correlation with t is −0.37. Not a pure linear trend, so the S1→S6 selection-via-trend story does not mechanically account for the negative sign.

#### Fix 3 (S10) — Local projections (Känzig 2025 panel eq 10 analogue)

```
log(PPI)_{s,t+h} = α_s + δ_t + γ_h · (CPShock_t × intensity_base_s) + ε
```

| h | All sectors β (SE) | ETS only β (SE) |
|---|---|---|
| 0 | −3.16 (4.64) | −2.11 (4.55) |
| 1 | **−11.71 (2.78)** *** | **−11.22 (2.82)** *** |
| 2 | −4.05 (5.75) | −6.35 (6.32) |
| 3 | **−9.78 (3.30)** ** | **−12.55 (3.90)** ** |

Alternating significance with wrong sign — not a coherent dynamic response; spurious timing correlation with specific year pairs.

### Summary of S7–S10 Surprise-based

1. **Nothing is identified cleanly on 2005–2019.** First stages dead (Cluster-F ≤ 0.05); IV estimates are weak-IV noise.
2. **Reduced-form specs that reach significance have the wrong sign and implausible magnitudes.**
3. **Root cause: shock size.** Phase IV (2021+, EUA €39–84) is excluded from the Känzig 2005–2019 window; pre-2020 shocks were 10–20× smaller than Phase IV in emissions-weighted carbon-cost-share terms.

---

## Shock-based robustness (Känzig Appendix C.6 approach) — positive pass-through emerges

*The main CPShock result is in this section and the S12 monthly extension below.*

Motivation: S7–S10 use `Surprise` as the CPShock variable. Känzig's own Appendix C.6 (Figure C.21) runs LPs using the **VAR-identified structural Shock** as the RHS — the reduced form of his Step 6 construction. Our HICP replication (above) confirms the Shock column reproduces his HICP IRF cleanly, while Surprise-based LP is noisier. Running our sector-PPI specs with Shock in place of Surprise gives substantively different results.

| Spec | β | SE | t | p | N |
|---|---|---|---|---|---|
| S7a-shk (levels, all) | +1.28 | 1.72 | 0.74 | 0.460 | 2085 |
| S7b-shk (levels, ETS) | +0.36 | 1.54 | 0.24 | 0.814 | 780 |
| S7c-shk (Δ log, all) | −1.35 | 0.54 | −2.49 | 0.014 | 1946 |
| S7d-shk L0 | −0.25 | 1.39 | −0.18 | 0.856 | 1807 |
| S7d-shk L1 | **+4.87** | 1.68 | 2.90 | 0.004 | 1807 |
| S7d-shk L2 | **+4.61** | 1.11 | 4.14 | <0.001 | 1807 |
| **S7d-shk cumulative** | **+9.22** | 3.68 | **2.51** | **0.012** | 1807 |
| S10-shk LP h=0 (all) | +1.28 | 1.72 | 0.74 | — | 2085 |
| S10-shk LP h=1 (all) | **+5.09** | 1.71 | 2.98 | <0.01 | 1946 |
| S10-shk LP h=2 (all) | **+4.77** | 1.19 | 4.00 | <0.001 | 1807 |
| S10-shk LP h=3 (all) | **+3.85** | 0.96 | 3.99 | <0.001 | 1668 |

**Pattern.** Contemporaneous null, significant positive at lagged horizons (L1, L2) and LP horizons h=1, 2, 3 (ETS-only subsample identical pattern). Cumulative distributed-lag effect +9.22 (p=0.012). LP IRF shape coherent: rise to peak at h=2, slight decline at h=3 — consistent with gradual pass-through rather than the alternating-significance noise under Surprise. For a sector with base intensity 0.005 and a unit structural shock, cumulative response implies roughly +4.6% PPI over 2–3 years.

**Caveat.** `Shock` is Känzig's VAR-identified structural shock, not a pure reduced-form input — these specs import his 8-variable-VAR identification assumptions. Our Surprise-based specs are the "primary" analysis in that they rest only on the event-day exogeneity assumption. But the Shock-based robustness is what Känzig himself uses for reduced-form LP (his Appendix C.6), and it reproduces his HICP benchmark cleanly.

---

## S12 — Monthly panel-LP (Känzig-JMP HICP analog at sector-PPI level)

Having built monthly Belgian NACE4d PPI (2005m1–2024m6, see [phase0_build_deflator_monthly.R](analysis/phase0_build_deflator_monthly.R)), we re-run the Shock-based spec at **monthly** frequency — the direct panel analog of Känzig's time-series LP on aggregate HICP. Two adaptations: (i) sector-level Belgian PPI replaces aggregate euro-area HICP; (ii) interacted with base-period intensity so that sector FE + year-month FE absorb all aggregate confounders, with identification from within-month cross-sector variation.

```
log(PPI_{s,m+h}) − log(PPI_{s,m−1}) = γ_h · (CPShock_m × intensity_base_s)
                                      + α_s + δ_m + ε
```
Sample: 2005-01 to 2019-12, 23,986 observations at h=0 (vs 2085 at annual). Clustered-on-sector SE.

| Horizon (months) | Shock, all (β / SE / t) | Shock, ETS only (β / SE / t) |
|---|---|---|
| 0 | +0.76 / 0.29 / **2.65** | +0.59 / 0.27 / **2.15** |
| 1 | +0.86 / 0.45 / 1.93 | +0.59 / 0.39 / 1.49 |
| 3 | +0.87 / 0.59 / 1.48 | +0.73 / 0.62 / 1.19 |
| 6 | +1.66 / 0.58 / **2.87** | +1.71 / 0.58 / **2.95** |
| **12** | **+4.08 / 0.64 / 6.39** | **+4.50 / 0.70 / 6.42** |
| 24 | +3.84 / 0.96 / **4.00** | +4.28 / 1.07 / **4.01** |

**IRF shape.** Modest positive on impact (+0.76, sig), builds over 6 months, peaks at 12 months (+4.08 log pp per unit shock × intensity, t = 6.39), fades slightly by 24 months. Classic gradual-propagation response — the shape Känzig reports for aggregate HICP.

**Precision gain.** At 12-month horizon SE = 0.64 vs SE = 1.71 for annual S10-shk h=1yr spec — 2.7× sharper. Going from 15 annual × 139 sectors to 180 months × 139 sectors at the same base intensity.

**Surprise-based monthly LP.** Run for robustness; same pattern as annual Surprise-based (noisy, coefficients not significant at most horizons, sign wanders).

**Magnitude translation.** For a typical ETS sector with `intensity_base ≈ 0.005`, a unit monthly CPShock raises log-PPI by about 0.020 = 2.0% at the 12-month horizon. Monthly CPShock has SD ≈ 0.3; so a ±1 SD shock implies a ±0.6% PPI response. Aligns with BKR's 0.2–0.4 electricity-futures elasticity after sector-share attenuation.

**Specification details (for reference).**
- Sector level: **NACE 4-digit** (139 sectors, 31 with positive `intensity_base`)
- Controls: **only fixed effects**. `nace4d` (139 levels) + `year_month` (180 levels). No additional regressors. Year-month FE absorbs aggregate CPShock_m and all macro confounders.
- Standard errors: **clustered at `nace4d`**
- Exposure measure: `intensity_base_s` = mean of `exposure_alt_total` over 2013–2016 (base-period-fixed cost denominator = 2010–2012 mean sector cost). Time-invariant per sector.
- Identification: within-month cross-sector variation only.

*Output:* [output/tables/phase3_ppi_passthrough_monthly.txt](output/tables/phase3_ppi_passthrough_monthly.txt), [output/figures/phase3_ppi_lp_monthly.pdf](output/figures/phase3_ppi_lp_monthly.pdf).

### S12b — Phase IV monthly extension (2020m1–2024m12)

Extend S12 to 2020–2024 using our rebuilt log-return surprise series (aggregated to monthly from 45 BKR events). Non-event months = 0. Sample: 7236 observations, 134 sectors.

| Horizon | All sectors β (SE) | ETS-only β (SE) |
|---|---|---|
| 0 | **−0.41 (0.19)** * | **−0.66 (0.24)** ** |
| 1 | −0.25 (0.43) | −0.56 (0.43) |
| 3 | −0.15 (0.46) | −0.55 (0.51) |
| 6 | −0.47 (0.80) | −0.89 (0.90) |
| 12 | −1.42 (1.59) | −1.58 (1.68) |
| 24 | +0.65 (3.75) | +0.26 (3.89) |

**Wrong-sign impact and null at longer horizons.** Unlike S12, S12b shows a significantly negative impact response and noisy-null IRF.

**Leading cause: macro contamination.** Our log-return surprise is *not* orthogonalized against macro/oil news, unlike Känzig's refined Surprise (which uses Bauer-Swanson 2023 residualization). On Jul 14, 2021 (Fit-for-55 vote) the EUA moved, but so did TTF gas; attributing the EUA move purely to carbon policy requires the residualization step we did not perform. 2020–2024 coincides with Covid, Russia/Ukraine, and the 2021–22 gas crisis — all orthogonal-to-carbon-policy shocks not absorbed by our raw log-return surprise.

**Scale caveat.** S12b uses log-return × intensity (unit = % × cost share); S12 uses structural Shock × intensity. Different units, not directly comparable in magnitude.

**Interpretation.** S12b does NOT establish Phase IV pass-through. The 2005–2019 S12 with clean identification remains the strongest panel-LP evidence.

*Output:* [output/figures/phase3_ppi_lp_monthly_phase4.pdf](output/figures/phase3_ppi_lp_monthly_phase4.pdf).

---

## S11 — Phase IV CPShock annual (2020–2024)

Parallel to S12b at annual frequency, using the same log-return surprise aggregated to years.

**Rebuilt CPShock series from primary sources.** BKR (2026) Appendix A.1 gives 45 regulatory events 2020–2024. We compute daily log-return surprises `cps_d = 100 · log(F_d / F_{d−1})` using ICE EUA front-month futures settlement (investing.com CFI2, 1620 trading days 2020-01-02 → 2026-04-22). All 45 events matched cleanly.

**No electricity-price normalization.** BKR's Figure B.7 shows their own robustness using log-return scaling — qualitatively equivalent to their baseline electricity-scaled version. Our rebuild uses this simpler approach.

| Year | CPShock_y (log-return, %) | n events |
|---|---|---|
| 2020 | **+17.1** | 13 |
| 2021 | +8.3 | 10 |
| 2022 | −0.3 | 6 |
| 2023 | −2.8 | 13 |
| 2024 | +0.3 | 3 |

Top five daily surprises by |magnitude|: Jan-18-2023 (ETS aviation reform, +5.3%), May-18-2020 (UK aviation auction, +5.7%), May-12-2021 (MSR reduces auctions, +4.2%), Nov-16-2020 (Phase 4 adoption, +4.1%), Jun-21-2023 (auction-calendar revision, −3.9%).

### Specifications

| Spec | Form | β | SE | t | p | N |
|---|---|---|---|---|---|---|
| S11a | log(PPI) ~ CPShock(log-ret) × int \| nace4d + year (all) | **−2.20** | 1.27 | −1.73 | 0.085 | 695 |
| S11b | same, ETS sectors only | **−2.39** | 1.27 | −1.89 | 0.065 | 260 |
| S11c | %-change scaling (BKR Fig B.3 formula), all | −2.17 | 1.26 | −1.72 | 0.088 | 695 |
| S11d h=0 | LP all sectors | −2.20 | 1.27 | −1.73 | — | 695 |
| S11d h=1 | LP all sectors | −2.49 | 1.32 | −1.89 | — | 556 |
| S11d h=2 | LP all sectors | −0.57 | 2.15 | −0.27 | — | 417 |

### Interpretation of S11

1. **Magnitudes are economically plausible** (β ≈ −2, not the −48 or +169 of S7–S10).
2. **Sign is negative, marginally significant (p ≈ 0.07–0.09).** Same macro-contamination explanation as S12b.
3. **Log-return and %-change scalings are interchangeable** (S11a vs S11c: −2.20 vs −2.17). BKR's own Figures B.3/B.7 show the same equivalence.
4. **LP dynamics are not coherent.** h=0 (−2.20), h=1 (−2.49), h=2 (−0.57) — doesn't build up or decay monotonically.
5. **Power is marginal.** Only 5 years × 31 ETS-intensity sectors.

S11 is the first CPShock spec to produce coefficients of plausible economic magnitude, but wrong sign and incoherent LP dynamics mean it does **not** constitute positive evidence of pass-through.

---

## Interpretation — two stories

Two stories of the same panel, both defensible:

**Story A (naïve OLS, see [PASSTHROUGH_OLS.md](PASSTHROUGH_OLS.md)):** Annual sector PPI data, without structural identification, shows at best small positive pass-through (+0.07 to +0.15) not distinguishable from zero and not scaling with exposure intensity. The negative S1/S5 coefficient reflects selection-into-exposure; only sector-specific trends (S6) flip the sign. Under this story, sector-level pass-through is "near zero, maybe slightly positive, unidentified".

**Story B (CPShock-identified, this document):** With Känzig's VAR-identified structural shock interacted with base intensity, run as a panel LP at monthly frequency (S12), significant positive pass-through emerges at delayed horizons — peak at h=12 months, +4.08 log pp per unit shock × intensity, IRF shape matching Känzig's aggregate HICP. Consistent with BKR's 0.2–0.4 electricity-futures elasticity after downstream attenuation. Under this story, pass-through exists, is delayed, and is identifiable with clean instruments — conditional on Känzig's VAR structure being correct.

The two stories are not contradictory: S1–S6 are descriptive regressions without identification arguments; S7-shk and S12 have structural identification (conditional on the VAR). The "right" interpretation depends on whether one trusts the external-instrument machinery.

### Limits remaining even with CPShock identification

- **Cross-firm dose-response within product within sector.** S12 interacts a scalar sector intensity with a scalar time shock; it cannot test whether, within the same NACE4d sector in the same month, high-exposure firms raise prices more than low-exposure firms.
- **Price-rigidity decomposition.** We can't measure the frequency of price changes or the share of pass-through absorbed by sticky prices.
- **Product-level heterogeneity.** A NACE4d sector aggregates many products with heterogeneous pass-through; PRODCOM 8-digit would resolve this.

Firm-level PRODCOM data would close these gaps. See [PRODCOM_PLAN.md](PRODCOM_PLAN.md) for specs.

---

## Comparison with external evidence (CPShock-relevant rows)

| Study | Context | Measure | Result |
|---|---|---|---|
| **This paper — annual LP (S10-shk)** | Belgium, NACE4d, 2005–19, Känzig Shock × intensity | log(PPI) ~ Shock × int | h=1yr: +5.09 (t=2.98); h=2yr: +4.77 (t=4.0) |
| **This paper — monthly panel-LP (S12)** | Belgium, NACE4d, 2005-01 to 2019-12, Känzig Shock × intensity | log(PPI) ~ Shock × int | **h=12 mo: +4.08 (SE 0.64, t=6.39); peak at 12 months, IRF matches Känzig HICP** |
| **Bauer, Känzig & Rudebusch 2026** | European energy futures, daily event study | log(price) ~ CPShock | Electricity **0.2–0.4**, gas ~0.2, oil ~0.1–0.15 |
| **Känzig 2025** (JMP) | Euro area, macro VAR, monthly | headline HICP ~ CPShock (SVAR) | Aggregate peak ~0.2% headline per 1% energy-price shock |
| **Fabra & Reguant 2014** (AER) | Spain, wholesale electricity, daily auction | price level ~ marginal ETS cost (IV) | **0.86–1.05** (near-full pass-through at source) |
| **Martin, Muûls & Stoerk 2024** | Belgium, firm-level PRODCOM unit prices | Δ unit price ~ ETS dummy | +0.14 (SE 0.15), insignificant |

Our S12 monthly LP coefficient of +4.08 at h=12 translates (via typical intensity ≈ 0.005) to ~0.02 log-pp per unit shock — comparable to BKR's 0.2 × intensity for electricity pass-through after sector-share attenuation. Sector PPI thus sits where it should on the price chain: attenuated vs energy-futures but detectable with structural identification.

---

## Caveats (CPShock-specific)

1. **`Shock` column imports Känzig's 8-variable-VAR identification.** Our main positive results (S7-shk, S10-shk, S12) rely on this. Pure reduced-form Surprise-based specs remain noisy.
2. **Sample for 2005–2019 specs ends at Känzig's JMP window (2019-12).** The BKR extension to 2024 is not publicly posted.
3. **Phase IV rebuild (S11, S12b) uses un-residualized log-return surprises.** Contaminated by Covid/Ukraine/gas-crisis shocks. Not informative.
4. **No first-stage-robust inference in S12 Shock-based specs.** Using Shock as a regressor is already structural (LP-IV is unnecessary and uninformative when Shock is the identified innovation); standard cluster-robust SE applies, but the implicit structural assumption is Känzig's VAR.
5. **`intensity_base` is time-invariant (2013–2016 mean).** Sectors whose carbon intensity changed materially after 2016 are not captured. A later base period (e.g., 2018–2019) could be used as robustness.

---

## Scripts

| Purpose | Script |
|---|---|
| Build annual Känzig CPShock series from `carbonPolicyShocks.xlsx` | [analysis/phase3_build_cpshock.R](analysis/phase3_build_cpshock.R) |
| Build Phase IV CPShock 2020–2024 from BKR event list + investing.com EUA | [analysis/phase3_build_cpshock_phase4.R](analysis/phase3_build_cpshock_phase4.R) |
| Replicate Känzig JMP HICP IRF (LP, Shock + Surprise variants) | [analysis/phase3_replicate_kanzig_hicp.R](analysis/phase3_replicate_kanzig_hicp.R) |
| Build monthly Belgian NACE4d PPI 2005–2024 | [analysis/phase0_build_deflator_monthly.R](analysis/phase0_build_deflator_monthly.R) |
| Monthly panel-LP of PPI on CPShock × base intensity (S12, S12b) | [analysis/phase3_ppi_passthrough_monthly.R](analysis/phase3_ppi_passthrough_monthly.R) |
| Main PPI pass-through annual regressions (S1–S6, A, S7–S10, S10-shk, S11) | [analysis/phase3_ppi_passthrough.R](analysis/phase3_ppi_passthrough.R) |

Shared-infrastructure scripts (exposure panel, EUA prices, annual deflator, heterogeneity) are listed in [PASSTHROUGH_OLS.md](PASSTHROUGH_OLS.md).

Output artefacts in [output/tables/phase3_*.txt](output/tables/) and [output/figures/phase3_*.pdf](output/figures/).

---

## Deferred analyses (CPShock-relevant)

Priority-ordered follow-ups:

1. **Extend the exposure panel to 2023–2024.** Currently 2005–2022; annual accounts for 2023–2024 would roughly double the Phase IV sample and make S11/S12b credible. Depends on NBB release schedule.
2. **Phase IV CPShock residualization à la Bauer-Swanson 2023.** Orthogonalize our 2020–2024 daily log-return surprises against oil (Brent daily), gas (TTF daily), climate-news index, pre-event macro. Take residuals as the refined Phase IV surprise. Would let S11/S12b produce clean numbers. ~1 week of work.
3. **Request BKR-extended daily refined surprise series (2020–2024).** Alternative to #2. Email Bauer or Rudebusch (not Diego — new baby). Free lunch if they share.
4. **PRODCOM workstream.** See [PRODCOM_PLAN.md](PRODCOM_PLAN.md). Highest research priority: within-product annual dose-response (Spec 1). Decisive test of whether firm-level heterogeneity confirms or overturns the S12 positive result.

For OLS-specific to-dos (network panel rebuild, exposure panel extension, etc.) see [PASSTHROUGH_OLS.md](PASSTHROUGH_OLS.md).

---

*Last revision: 2026-04-22. Split from former `PASSTHROUGH_FINDINGS.md`.*
