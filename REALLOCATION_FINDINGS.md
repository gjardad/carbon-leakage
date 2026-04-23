# Reallocation Findings: Does Carbon Pricing Shift Market Shares in Belgium?

---

## Summary

Belgian ETS emissions fell approximately **46% between 2005 and 2021**. This decline decomposes into:

| Channel | Magnitude (pp) | Share of total |
|---------|---------------|---------------|
| Between-sector reallocation | 20-23 | ~45-50% |
| Within-firm abatement | 23-26 | ~50-55% |
| Within-sector reallocation | ~0 | ~0% |

The dominant forces are (i) a shift in Belgium's manufacturing mix toward less emission-intensive sectors and (ii) individual firms reducing their emission intensity. There is essentially no evidence that market shares shifted from dirty to clean firms within the same sector.

---

## What we are computing

### The decomposition formula

Total emissions in year t can be written as:

```
E_t = Y_t × Σ_i (θ_it × z_it)
```

where `Y_t` is total real output, `θ_it` is firm i's share of total output, and `z_it` is firm i's emission intensity (emissions per unit of real output). Revenue is deflated by a NACE 4-digit domestic PPI (Statbel for 2010+, Eurostat for 2005-2009, chain-linked at 2010; see DATA_CLEANING.md).

Relative to a base period, we construct three counterfactual emission paths:

1. **Scale only:** Hold every firm's output share and emission intensity at base-period levels. Only total output Y_t changes. This tells us what emissions would have been if the economy simply grew or shrank without any change in who produces what or how cleanly they produce.

2. **Scale + Reallocation:** Let output shares change as in the data, but hold each firm's emission intensity at the base level. This adds the effect of market share shifts across firms — if dirtier firms lost share, this line falls below the scale-only line.

3. **Actual:** Both output shares and emission intensities change as in the data.

The gaps between these lines give us:
- **(1) to (2):** reallocation across firms (composition effect)
- **(2) to (3):** within-firm abatement (technique effect)

We further decompose the reallocation into between-sector (NACE 2-digit output shares changing) and within-sector (firm shares shifting within the same sector).

---

## Two approaches and why we need both

### Approach 1: Fixed base year (2005)

**What it does:** For each year t, take all firms that are present in both 2005 and year t. Compare their current output shares and emission intensities to what they were in 2005.

**Simple example:** Suppose sector X has two firms in 2005: Firm A (dirty, 60% market share) and Firm B (clean, 40% share). By 2015, Firm A has 50% share and Firm B has 50% — that's within-sector reallocation. Meanwhile, Firm A also reduced its emission intensity — that's within-firm abatement.

**Advantage:** Cleanly separates within-firm abatement from within-sector reallocation, because we can compare each firm's current intensity to its own 2005 intensity.

**Problem:** The sample shrinks over time. In 2005, 162 firms have non-zero emissions, non-missing revenue, and a NACE code. By 2022, only 100 of these 162 still have clean data. This is not because firms exit the ETS (all 281 Belgian ETS firms are in the EUTL every year) but because their Annual Accounts data becomes unavailable in some years. This attrition could bias the results if the firms that drop out are systematically different.

**Results (key years):**

| Year | Firms | Total change | Scale | Between-sector | Within-sector reallocation | Within-firm abatement |
|------|-------|-------------|-------|----------------|---------------------------|----------------------|
| 2005 | 162 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| 2008 | 141 | -1.2 | 12.1 | 16.3 | 1.9 | -31.5 |
| 2012 | 127 | -27.2 | 3.3 | 17.1 | 2.0 | -49.6 |
| 2016 | 114 | -26.1 | -3.7 | 1.7 | 7.2 | -31.3 |
| 2019 | 104 | -25.9 | -7.4 | -7.4 | 3.2 | -16.9 |
| 2022 | 100 | -45.8 | -2.7 | -19.2 | 1.7 | -25.6 |

All values in percentage points relative to 2005 = 100.

### Approach 2: Year-on-year chained

**What it does:** For each consecutive pair of years (2005-2006, 2006-2007, ..., 2021-2022), take all firms present in both years and compute the one-year change. Then chain these changes multiplicatively to build a cumulative index from 2005.

**Same example:** Instead of comparing 2015 to 2005 directly, we compare 2006 to 2005 (using all firms in both), then 2007 to 2006 (using all firms in both), etc. Each pair can use a different set of firms. The cumulative change from 2005 to 2015 is the product of all the year-on-year changes.

**Advantage:** Each year-on-year step uses the maximum available sample (~160-190 firms per pair), so there is no attrition problem.

**Problem:** The year-on-year version cannot cleanly separate within-sector reallocation from within-firm abatement. Firm-level output shares fluctuate substantially from year to year (a firm has a good year, then a bad year), creating enormous and offsetting reallocation and technique terms that are meaningless. We can only reliably decompose at the sector level: between-sector reallocation vs. within-sector residual (which bundles abatement and reallocation together).

**Results (key years):**

| Year | Firms (pair) | Total change | Between-sector | Within-sector residual |
|------|-------------|-------------|----------------|----------------------|
| 2005 | 162 | 0.0 | 0.0 | 0.0 |
| 2008 | 145 | -12.4 | 13.3 | -25.6 |
| 2012 | 161 | -32.3 | 10.1 | -42.3 |
| 2016 | 162 | -23.9 | 1.0 | -25.0 |
| 2019 | 156 | -21.3 | -7.0 | -14.3 |
| 2022 | 149 | -46.4 | -22.9 | -23.5 |

All values in percentage points relative to 2005 = 100.

---

## How we arrive at the summary numbers

### Total decline: ~46%

Both approaches agree: -45.8 (fixed-base) and -46.4 (year-on-year). The small difference comes from the year-on-year version capturing firms that enter the clean sample after 2005.

### Between-sector reallocation: 20-23 pp

The fixed-base approach gives -19.2 pp by 2022; the year-on-year gives -22.9 pp. The range reflects the different sample composition. This channel was actually *positive* (wrong direction — shares shifted toward dirtier sectors) through Phase I and Phase II, only turning negative from ~2017 onward. The positive early period likely reflects differential impacts of the 2008-2009 financial crisis across sectors, not carbon policy.

### Within-firm abatement: 23-26 pp

The fixed-base approach directly measures this at -25.6 pp by 2022. The year-on-year approach gives a within-sector residual of -23.5 pp, which bundles abatement and within-sector reallocation. Since the fixed-base version tells us within-sector reallocation is ~0, the year-on-year within-sector residual is essentially all abatement.

### Within-sector reallocation: ~0

The fixed-base approach is the only one that can measure this directly. It shows values between +1.7 and +7.2 pp across all years — small and if anything *positive*, meaning dirtier firms slightly gained share within their sectors. There is no evidence that carbon pricing shifted market shares from dirty to clean firms within the same narrowly defined sector.

---

## Data caveats

### Sample coverage

The Belgian EUTL contains 281 firms in every year (2005-2023). Our analysis uses a subset:

| Filter | Firms lost | Reason |
|--------|-----------|--------|
| Zero emissions in 2005 | 80 | Installations with allowances but no verified emissions that year. 78 of 80 have positive emissions in other years. |
| Missing revenue | 55 | No match to Annual Accounts data (missing Belgian VAT linkage) |
| Missing NACE code | 53 | Almost entirely overlaps with missing revenue — same underlying cause |
| Missing PPI deflator | ~9 | NACE code not covered by Statbel or Eurostat PPI |

After filtering, the sample covers **88.4% of total Belgian ETS emissions** in 2005. The clean sample ranges from 162-194 firms per year, depending on year.

### Panel attrition in fixed-base approach

The fixed-base approach requires firms to be present in both 2005 and year t. The sample shrinks from 162 (2005) to 100 (2022) — a 38% loss. This is **not** because firms exit the ETS (all 281 are in the EUTL every year) but because Annual Accounts matching varies over time. The year-on-year approach mitigates this by using all available firms in each consecutive pair.

### Zero-emission firms

80 firms have zero verified emissions in 2005 and are excluded from the decomposition (log emission intensity is undefined). Most (78/80) have positive emissions in other years — they are real firms that simply didn't emit in the base year (e.g., installations under construction or temporarily shut down). These firms are captured by the year-on-year approach in years when they do emit.

---

## Sector-level heterogeneity

The aggregate zero for within-sector reallocation masks substantial heterogeneity across sectors. Using the fixed-base (2005) decomposition applied separately to each NACE 2-digit sector through 2021:

| NACE | Sector | Em. share (2005) | Reallocation (pp) | Technique (pp) | Direction |
|------|--------|-----------------|-------------------|----------------|-----------|
| 35 | Electricity | 36% | +25 | -24 | Toward dirtier plants |
| 24 | Basic metals (steel) | 22% | **-17** | -90 | Toward cleaner firms |
| 23 | Non-metallic minerals (cement, glass) | 18% | **-19** | -28 | Toward cleaner firms |
| 19 | Petroleum refining | 11% | +27 | +40 | Toward dirtier refineries |
| 20 | Chemicals | 9% | +46 | +16 | Toward dirtier firms |

Steel (24) and cement/glass (23) show large reallocation toward cleaner firms. Electricity (35) and petroleum (19) show the opposite. Chemicals (20) also show dirtier firms gaining share. These roughly cancel in aggregate.

**Important caveat:** Most sectors have fewer than 30 firms, and some drop to 2-3 survivors by 2021. The reallocation numbers for small sectors are driven by individual firm movements and should not be over-interpreted.

---

## Melitz-Polanec decomposition (entry and exit)

We also implemented the dynamic Olley-Pakes decomposition from Melitz & Polanec (2015, RAND), which cleanly handles firms entering and exiting the sample by splitting them into survivors, entrants, and exiters.

**Key finding:** Entry and exit contributions are consistently small — in the single digits as a percentage of base-year emission intensity across all rolling 5-year windows. The changing sample composition is not driving the results.

**Limitation:** The Melitz-Polanec decomposition splits the aggregate into an unweighted mean (within-firm) plus an Olley-Pakes covariance (reallocation). With highly skewed emission intensities (some firms at 0.00001, others at 0.03), the unweighted mean is dominated by a handful of high-intensity firms. When one of these firms' intensity changes dramatically, the within-firm and reallocation terms swing wildly in opposite directions. This makes the decomposition unstable for horizons longer than ~5 years.

For this reason, the Grossman-Krueger decomposition (which works with share-weighted quantities throughout) is more reliable for our data. We use the Melitz-Polanec decomposition only to confirm that entry/exit are quantitatively unimportant.

**Script:** `analysis/phase0_melitz_polanec.R`

---

## Is within-sector reallocation correlated with carbon cost exposure?

If carbon pricing drives within-sector reallocation, we should see more reallocation in sector-years where carbon costs actually bite. We test this by correlating the year-on-year change in the Olley-Pakes covariance (our within-sector reallocation measure) with two measures of carbon cost exposure at the sector-year level:

1. **Carbon cost share:** (allowance shortage × EUA price) / sector revenue
2. **Percent of emissions priced:** allowance shortage / total emissions

**Result: no correlation.**

| Specification | Measure | Coefficient | t-stat | p-value |
|--------------|---------|------------|--------|---------|
| OLS | Carbon cost share | 4.53 | 0.54 | 0.59 |
| Sector + Year FE | Carbon cost share | 7.58 | 0.60 | 0.55 |
| OLS | % emissions priced | -0.0001 | -0.06 | 0.95 |
| Sector + Year FE | % emissions priced | -0.0016 | -0.32 | 0.75 |

Raw correlations: 0.039 (carbon cost share) and -0.005 (% emissions priced). The scatter plot is flat — sector-years with higher carbon cost exposure show no more reallocation toward cleaner firms than sector-years with low exposure.

This null result reinforces the aggregate finding: within-sector reallocation among ETS firms is not driven by carbon pricing. Firms abate in place regardless of how much carbon costs bite in their sector.

**Caveat:** 195 sector-year observations across 16 sectors with 3+ firms. Limited statistical power, especially for within-sector variation. EUA prices are approximate annual averages.

**Script:** Standalone analysis (to be integrated into `analysis/phase0_melitz_polanec.R`).

---

## Interpretation

This decomposition is **purely mechanical** — it attributes emission changes to accounting channels but says nothing about what *caused* those changes. The between-sector reallocation could reflect carbon policy, trade shocks, demand shifts, or technology trends. The within-firm abatement could be driven by carbon pricing, energy prices, regulation, or autonomous technical change. Causal attribution requires the identification strategies in Phase 1 and Phase 2.

However, the additional finding that within-sector reallocation is **uncorrelated with carbon cost exposure** across sector-years provides suggestive (though not causal) evidence that carbon pricing is not driving reallocation among ETS firms. This is consistent with Colmer, Martin, Muuls & Wagner (2024), who find that French ETS firms reduced emissions without any contraction in economic activity.

---

## ETS vs. non-ETS output share analysis

An important limitation of the within-ETS decomposition is that non-ETS firms competing in the same sectors are invisible. We address this using the full firm panel: the training sample (ETS firms, ~241) combined with the deployment panel (all non-ETS firms, ~120k per year). This allows us to track whether ETS firms lost market share to non-ETS competitors within the same narrowly defined sector.

### Aggregate ETS share

ETS firms' share of total revenue in sectors containing ETS firms rose from ~49% (2005) to ~55% (2010 peak), then declined steadily to ~43% (2017), before partially recovering to ~49% by 2021. The net decline over 2005-2021 is modest.

### Sector-level patterns (NACE 2-digit)

The aggregate decline is driven almost entirely by **NACE 35 (electricity)**, where the ETS share fell from ~65% to ~25%, reflecting the entry of non-ETS renewable energy producers (wind, solar). This is a structural energy transition, not a competitive reallocation driven by carbon costs.

In manufacturing sectors where ETS firms face the highest carbon costs:
- **NACE 19 (petroleum):** 100% ETS throughout — no non-ETS competitors
- **NACE 24 (steel):** ~90% ETS, stable
- **NACE 20 (chemicals):** ~58% to ~53%, modest decline

### NACE 4-digit analysis: the right level of competition

At the 2-digit level, ETS and non-ETS firms are often in completely different subsectors (e.g., within NACE 23, cement producers are ETS-regulated while concrete product manufacturers are not). The competitive margin is within 4-digit sectors where both types coexist.

We identify **80 mixed NACE 4-digit sectors** with both ETS and non-ETS firms. Among these:
- Some sectors show large ETS share declines (e.g., several sectors where the single ETS firm exited or was reclassified)
- Others show large ETS share gains (e.g., NACE 2332 bricks: +44pp, NACE 2017 specialty chemicals: +47pp)
- There is no systematic pattern

### Correlation with carbon cost exposure

We test whether ETS share changes correlate with carbon cost exposure (allowance shortage × EUA price / sector revenue) at the NACE 4-digit level, with sector and year fixed effects:

| Lag | Coefficient | Std. Error | t-stat | p-value |
|-----|------------|-----------|--------|---------|
| 0 (contemporaneous) | -0.257 | 0.894 | -0.29 | 0.774 |
| 1 year | +2.880 | 1.700 | 1.69 | 0.091 |
| 2 years | +3.064 | 2.034 | 1.51 | 0.133 |
| 3 years | -2.643 | 3.254 | -0.81 | 0.417 |

No significant relationship. The marginally significant lag-1 coefficient is *positive* — meaning higher lagged carbon cost is associated with ETS firms *gaining* share, the opposite of what a carbon cost competition story would predict. This likely reflects reverse causality (larger ETS firms have both higher carbon costs and higher market share) rather than a causal effect.

**Script:** `analysis/phase0_ets_share_shift.R`

---

## Interpretation

The reallocation channel appears inactive in Belgium across every margin we examine:
1. **Within ETS firms** (GK decomposition): within-sector reallocation ≈ 0
2. **Between ETS and non-ETS firms** (full panel): ETS share changes uncorrelated with carbon cost
3. **Across sectors**: between-sector reallocation driven by structural factors (energy transition), not carbon costs

The exception is electricity (NACE 35), where a structural shift from thermal to renewable generation reduced ETS firms' share. This is driven by the energy transition and renewable energy support policies (as documented by Mulier, Ovaere & Stimpfle 2024), not by carbon cost competition per se.

These findings are consistent with:
- Colmer et al. (2024): French ETS firms reduced emissions without output contraction
- Martinsson et al. (2024): highest emitters have the lowest carbon pricing elasticities, reducing the scope for competitive reallocation
- Mulier et al. (2024): cost compensation for energy-intensive firms weakens the carbon price signal, further dampening reallocation incentives

### Does the story change after the 2017 MSR reform?

We tested whether the MSR reform — which made the ETS substantially more binding (EUA prices rose from ~5 to 50+ EUR) — produced a visible shift in within-sector output shares. Following De Jonghe et al. (2021) and Mulier et al. (2024), we classify ETS firms by their pre-MSR allowance shortage intensity (2013-2016 average of max(emissions - free allowances, 0) / revenue) and track their output shares over time.

**Three versions of the eyeball test:**

1. **Binary split within NACE 2-digit:** High-exposure firms' share drops ~17% post-2017. But this largely reflects between-subsector composition (mixing cement producers with concrete manufacturers within the same 2-digit code). When redone at NACE 4-digit, the divergence mostly disappears.

2. **Binary split within NACE 4-digit:** Both lines stay close to 1.0 after 2017, with the high-exposure line slightly below but well within pre-period volatility. No visible break.

3. **Terciles of shortage intensity (across the whole economy):** Clear monotonic gradient — high-exposure firms lose share, low-exposure firms gain. But this is a secular trend starting in 2005, well before carbon pricing was binding. The 2017 reform does not produce a visible acceleration.

4. **Within-sector terciles (the definitive test):** Each firm's output share is computed within its NACE 4-digit sector, then averaged across sectors by tercile. This isolates pure within-sector reallocation. Result: the same long-run convergence pattern. High-exposure firms have been gradually losing within-sector share since 2005. **The post-2017 period shows no break — if anything, the divergence slowed down after the MSR reform.**

**Script:** `analysis/phase1a_output_share_by_exposure.R`

### Summary of all reallocation tests

| Test | Level | Finding |
|------|-------|---------|
| GK decomposition (Phase 0) | Within NACE 2d, ETS firms | Within-sector reallocation ≈ 0 |
| OP covariance vs. carbon cost | Sector-year panel | No correlation |
| ETS vs. non-ETS share | NACE 4d, full panel | No correlation with carbon cost |
| Binary split, NACE 4d | Within NACE 4d, ETS firms | Flat post-2017 |
| Terciles, within-sector | Within NACE 4d, ETS firms | Long-run trend, no post-2017 break |

The reallocation channel is inactive in Belgium. Carbon pricing induced within-firm abatement but did not shift market shares within sectors, even after prices became meaningful in 2017. The long-run trend of high-exposure firms losing within-sector share predates carbon pricing and likely reflects other factors (productivity differences, structural transformation).

---

---

## Phase 4 — Firm-level panel response to carbon policy shocks × firm emissions intensity

Added 2026-04-22. Spec 1.A of [REALLOCATION_MECHANISM_PLAN.md](REALLOCATION_MECHANISM_PLAN.md) under identification ID-A (annual CPShock). Spec 1.B (pass-through moderator), 1.C (realized `β̂_s`), and 1.D (ETS vs non-ETS) are not yet run; pre-trend horizons are not yet run; Angle 4 (B2B) is not yet run.

### Specification

Script: `analysis/phase4_firm_output_reallocation.R`. Sample: 215 ETS firms with a defined firm-level carbon cost share, 2005–2019 (Känzig CPShock sample window); 2,163 firm-years at h = 0 after requiring ≥3 years per firm. LHS is Δlog(real_rev), constructed LP-style as `log(real_rev)_{i,t+h} − log(real_rev)_{i,t−1}` for h ∈ {0, 1, 2, 3}.

```
Δlog(real_rev)_{i,s,t,h} = β · (Signal_t × firm_dev_{i,s}) + α_{s,t} + α_i + ε
```

where:
- `firm_cost_share_i = mean_{t ∈ 2013..16}[shortage_{i,t} × EUA_t] / mean_{t ∈ 2010..12}[total_cost_{i,t}]` — firm analog of sector-level `intensity_base_s`. Fallback to earliest 3-year window for firms without 2010–12 coverage, matching [phase3_build_exposure_panel.R](analysis/phase3_build_exposure_panel.R).
- `firm_dev_{i,s} = firm_cost_share_i − mean(firm_cost_share) within NACE4d sector`. SD across firms = 0.037 (3.7pp of total-cost share).
- `Signal_t ∈ {cpshock_surprise_t, cpshock_shock_t}`, both aggregated from Känzig monthly series (see [phase3_build_cpshock.R](analysis/phase3_build_cpshock.R)).
- `α_{s,t}` = NACE4d × year fixed effect; `α_i` = firm fixed effect.
- Two-way clustering on firm and sector-year.

Verification of the treatment build: aggregating `firm_cost_share_i` with total-cost weights to NACE4d reproduces sector `intensity_base_s` with correlation 0.98 across 79 sectors (max absolute difference 0.003).

### Source of variability

- Firm FE absorbs each firm's mean Δlog(real_rev).
- NACE4d × year FE absorbs every sector-year aggregate, including the `Signal_t` main effect and all sector-common macro movement in year t.
- β is identified from cross-firm variation within the same sector-year: conditional on the sector's aggregate response, do firms with larger within-sector emissions-intensity deviation have larger Δlog(real_rev)?
- `Signal_t` enters only multiplicatively; its time-series variance scales the interaction.
- Series standard deviations in the 2005–2019 panel: `cpshock_surprise` SD = 0.53, `cpshock_shock` SD = 2.4.

### Identification assumption

- `Signal_t` is exogenous to firm-specific Belgian demand shocks conditional on sector-year FE. For `cpshock_surprise` this is the Känzig (2025) high-frequency event-study identification on discrete EU ETS regulatory announcement days. For `cpshock_shock` it is the Känzig external-instruments VAR using Surprise as the instrument — so the resulting series inherits VAR-level persistence rather than being a clean high-frequency instrument.
- `firm_cost_share_i` is built from 2010–16 firm data that pre-date any 2017+ ETS tightening, so there is no within-sample reverse-causality channel from Δlog(real_rev) to the treatment. Survivorship bias through the 2010–12 and 2013–16 base-period filters is not addressed.
- Pre-trend placebo (h = −2) has not been run.

### Results

β on `Signal_t × firm_dev_{i,s}`, with two-way cluster-robust standard errors (firm, sector-year). Output tables: [output/tables/phase4_spec1A_ida_surprise.txt](output/tables/phase4_spec1A_ida_surprise.txt) and [output/tables/phase4_spec1A_ida_shock.txt](output/tables/phase4_spec1A_ida_shock.txt).

| Horizon | `cpshock_surprise` | `cpshock_shock` |
|---|---|---|
| h = 0 | −5.66 (SE 0.90), t = −6.28, p < 0.001 | +0.58 (SE 0.22), t = 2.66, p = 0.008 |
| h = 1 | −1.81 (SE 2.72), t = −0.67, p = 0.51 | +1.08 (SE 0.33), t = 3.28, p = 0.001 |
| h = 2 | −2.32 (SE 3.46), t = −0.67, p = 0.50 | +1.66 (SE 0.40), t = 4.10, p < 0.001 |
| h = 3 | −2.65 (SE 3.32), t = −0.80, p = 0.42 | +1.60 (SE 0.37), t = 4.34, p < 0.001 |

N = 2,163 / 1,988 / 1,808 / 1,629 across h = 0 / 1 / 2 / 3.

Robustness: replacing `firm_cost_share_i` with `firm_emint_physical_i = mean_{2013..16} shortage / mean_{2010..12} total_cost` (no EUA price in the treatment) preserves signs and significance levels at every horizon for both signal variants.

Levels verification (no shock): regressing `log(real_rev)_{i,t}` on `firm_dev_share` with NACE4d × year FE (no firm FE, since `firm_dev_share` is firm-invariant) yields β = −5.81 (t = −1.65, p = 0.10) pooled. Adding `firm_dev_share × post-MSR(2017+)`: base β = −7.55 (t = −1.99, p = 0.05); interaction = +6.38 (t = 3.46, p < 0.001). The post-MSR interaction is positive and significant; the pooled base coefficient is negative and marginally significant.

---

---

## Phase 4 (cont.) — Sample split of Spec 1.A by realized sector pass-through

Added 2026-04-22. Spec 1.C of [REALLOCATION_MECHANISM_PLAN.md](REALLOCATION_MECHANISM_PLAN.md): re-estimate Spec 1.A separately on sectors classified by whether their monthly PPI actually moves with CPShock.

### Step 1 — Per-sector pass-through classification

Script: `analysis/phase4_sector_passthrough_classification.R`. Output: `data/processed/phase4_sector_passthrough.RData`.

Spec (interacted panel LP at h = 12 months, monthly sample 2005–2019):

```
Δlog(PPI)_{s,m+12} − Δlog(PPI)_{s,m-1} = Σ_s [ γ_s · CPShock_m · I(sector=s) ]
                                       + α_s + δ_m + ε
```

FE: NACE4d + year-month. Clustered on `year_month` (the shock is month-common; clustering on nace4d would be degenerate since each γ_s lives within a single sector cluster). 133 sectors obtained coefficients (1 dropped for collinearity).

Distribution of γ_s across sectors:

| Variant | Mean γ_s | Median γ_s | Mean t |
|---|---|---|---|
| `cpshock_shock`   | +0.0050 | +0.0050 | +0.76 |
| `cpshock_surprise` | −0.0077 | −0.0072 | −0.33 |

Classification counts (133 sectors):

| Cutoff | `cpshock_shock` | `cpshock_surprise` |
|---|---|---|
| γ_s > 0 (sign) | 118 high / 15 no | 35 high / 98 no |
| top tercile | 45 high / 88 no | 45 high / 88 no |
| γ_s > 0 & t > 1.645 | 10 high / 123 no | 0 high / 133 no |
| γ_s > 0 & t > 1.96  |  6 high / 127 no | 0 high / 133 no |

Intersection (γ_s > 0 on sign under both variants): 28 sectors.

### Step 2 — Sample-split Spec 1.A

Script: `analysis/phase4_firm_output_reallocation.R`. Output: `output/tables/phase4_spec1C_sample_split.txt`.

Re-run Spec 1.A (`Δlog(real_rev) = β·(Signal_t × firm_dev_share) + α_vat + α_{nace4d × year}`) restricting the firm panel to the two subsamples defined by each sector classification. Signal variants `cpshock_surprise` and `cpshock_shock` run separately in the firm-level regression, independently of which variant defined the classification.

Selected cells (see full table for all combinations). β reported with two-way cluster-robust (firm and sector-year) SEs.

**Split by `cpshock_shock` sign (high: 41 sectors, 122 firms, 1,509 panel rows; no: 7 sectors, 10 firms, 119 rows):**

| Horizon | High / Signal=surprise | High / Signal=shock | No / Signal=surprise | No / Signal=shock |
|---|---|---|---|---|
| h=0 | −9.49 (SE 7.84), p=0.23 | +1.63 (SE 0.98), p=0.10 | +2.12 (SE 101.5), p=0.98 | −31.8 (SE 9.48), p=0.03 |
| h=1 | −12.83 (SE 11.75), p=0.28 | +1.02 (SE 1.33), p=0.44 | +225.5 (SE 126.0), p=0.15 | −65.0 (SE 28.7), p=0.09 |
| h=2 | **−37.67 (SE 14.71), p=0.012** | **+4.14 (SE 1.35), p=0.003** | +162.6 (SE 261.1), p=0.57 | −132.0 (SE 18.3), p=0.002 |
| h=3 | **−35.85 (SE 14.31), p=0.014** | **+2.91 (SE 1.40), p=0.04** | +150.0 (SE 303.2), p=0.65 | −124.8 (SE 21.4), p=0.004 |

N in high subsample: 1,167 / 1,069 / 970 / 870 across h = 0 / 1 / 2 / 3. N in no subsample: 70 / 65 / 60 / 55.

**Split by `cpshock_shock` top tercile (high: 18 sectors, 74 firms, 824 rows; no: 30 sectors, 67 firms, 804 rows):**

| Horizon | High / Signal=surprise | High / Signal=shock | No / Signal=surprise | No / Signal=shock |
|---|---|---|---|---|
| h=0 | −9.14 (SE 7.84), p=0.25 | +1.62 (SE 0.99), p=0.11 | −145.6 (SE 111.6), p=0.20 | +9.73 (SE 13.16), p=0.46 |
| h=1 | −12.85 (SE 11.82), p=0.28 | +1.00 (SE 1.34), p=0.46 | +8.16 (SE 39.81), p=0.84 | +10.20 (SE 19.83), p=0.61 |
| h=2 | **−37.59 (SE 14.80), p=0.013** | **+4.10 (SE 1.37), p=0.004** | −50.26 (SE 89.32), p=0.58 | +21.78 (SE 25.89), p=0.41 |
| h=3 | **−35.86 (SE 14.39), p=0.015** | **+2.88 (SE 1.42), p=0.046** | −16.96 (SE 74.55), p=0.82 | +11.86 (SE 26.72), p=0.66 |

N in high subsample: 662 / 605 / 545 / 485. N in no subsample: 573 / 529 / 485 / 440.

**Split by `cpshock_shock` 10% significance (high: 5 sectors, 18 firms, 159 rows; no: 43 sectors, 120 firms, 1,469 rows):**

| Horizon | High / Signal=surprise | No / Signal=surprise | High / Signal=shock | No / Signal=shock |
|---|---|---|---|---|
| h=0 | −27.25 (SE 62.00), p=0.67 | −8.97 (SE 7.85), p=0.26 | +1.65 (SE 9.17), p=0.86 | +1.66 (SE 0.98), p=0.10 |
| h=1 | −52.57 (SE 87.78), p=0.56 | −11.67 (SE 12.04), p=0.34 | −1.64 (SE 6.47), p=0.80 | +1.11 (SE 1.31), p=0.40 |
| h=2 | −36.27 (SE 67.57), p=0.60 | **−37.47 (SE 15.07), p=0.015** | +3.53 (SE 6.46), p=0.59 | **+4.19 (SE 1.35), p=0.003** |
| h=3 | small-sample SE degenerate | **−36.29 (SE 14.53), p=0.014** | +5.76 (SE 14.02), p=0.69 | **+2.92 (SE 1.39), p=0.038** |

**Split by `cpshock_surprise` sign (high: 14 sectors, 49 firms, 571 rows; no: 34 sectors, 86 firms, 1,057 rows):**

| Horizon | High / Signal=surprise | High / Signal=shock | No / Signal=surprise | No / Signal=shock |
|---|---|---|---|---|
| h=0 | −41.44 (SE 33.99), p=0.23 | −7.52 (SE 5.22), p=0.16 | −7.78 (SE 7.84), p=0.32 | **+2.07 (SE 0.92), p=0.028** |
| h=1 | +10.26 (SE 54.38), p=0.85 | **−13.94 (SE 6.32), p=0.033** | −14.03 (SE 12.01), p=0.25 | +1.75 (SE 1.12), p=0.12 |
| h=2 | −78.71 (SE 62.74), p=0.22 | −6.85 (SE 7.84), p=0.39 | **−35.52 (SE 15.49), p=0.025** | **+4.57 (SE 1.28), p=0.001** |
| h=3 | −61.82 (SE 52.77), p=0.25 | −15.73 (SE 9.91), p=0.12 | **−34.47 (SE 15.28), p=0.027** | **+3.67 (SE 1.20), p=0.003** |

**Split by intersection of signs (both variants γ_s > 0): high 11 sectors, 44 firms, 507 rows; no 37 sectors, 91 firms, 1,121 rows.** Pattern matches the `cpshock_surprise` sign split closely.

### Caveats on magnitudes and significance

- Coefficient magnitudes when `Signal = cpshock_surprise` are very large (β ≈ −37 at h=2). With `firm_dev_share` SD = 0.037 and `cpshock_surprise` SD = 0.53, a 1-SD × 1-SD combination implies −72% cumulative log real-revenue change over two years, which is implausible as a point estimate. The sign and significance are stable across shock-based classification schemes; the magnitude should not be taken at face value.
- `cpshock_shock` and `cpshock_surprise` continue to deliver opposite-sign β, consistent with [PASSTHROUGH_CPSHOCK.md](PASSTHROUGH_CPSHOCK.md)'s S7–S11 pathology and with the pooled Spec 1.A reported above.
- The "no" subsample under `class_shock_sign` has only 7 sectors and 10 firms; estimates there should be read as a power-and-outlier residual, not as a clean contrast.
- The `class_shock_10` high subsample (5 sectors, 18 firms) produces degenerate cluster SEs at h=3 (SE ≈ 0, reported `t` enormous).

---

## Phase 0 (addendum) — Six-channel pairwise decomposition

Added 2026-04-23. Script: `analysis/phase0_pairwise_decomposition.R`. Output: `output/tables/phase0_pairwise_decomposition.csv`.

Motivation. The fixed-base and year-on-year SCT decompositions (above) cannot cleanly answer "between year $a$ and year $b$, what share of the emissions change came from each channel, including entry and exit?" The fixed-base table always anchors at 2005, and drops entrants/exiters. The Melitz–Polanec decomposition handles entry/exit but uses an unweighted survivor mean that is unstable beyond $\sim$5-year horizons.

This addendum runs a direct six-channel decomposition for an arbitrary $(t_{\text{base}}, t_{\text{end}})$ pair. Survivors = firms with positive emissions in both years (joined on `vat`, sector change allowed — t_base NACE 2d is used for the sector split). Entrants = firms with positive emissions only in $t_{\text{end}}$. Exiters = firms with positive emissions only in $t_{\text{base}}$. By construction:
$$E_{t_{\text{end}}} - E_{t_{\text{base}}} = \text{Scale}_S + \text{Between}_S + \text{Within}_S + \text{Technique}_S + \text{Entry} - \text{Exit}.$$
All channels reported in pp of $E_{t_{\text{base}}}$.

### Results

Six-channel pp columns sum to **Total**. `z_ent` and `z_exit` report group-average emission intensity in tCO₂ per million EUR of real revenue (entrants measured in $t_{\text{end}}$, exiters in $t_{\text{base}}$). The bottom three rows restrict to the 101-firm **triple-balanced panel** — firms with positive emissions in all of 2005, 2012, and 2020 — so entry/exit are zero by construction on those rows.

| Pair | n_surv | n_ent | n_exit | Total | Scale | Between | Within | Technique | Entry | Exit | z_ent | z_exit |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2005 → 2007 | 154 | 8  | 8  | −4.1  | +18.2 | +11.5 | +3.3  | **−38.1** | +1.0  | −0.1 | 183 | 130 |
| 2005 → 2012 | 127 | 37 | 35 | −16.4 | +10.8 | +7.4  | +10.5 | **−49.6** | +10.8 | −6.4 | 671 | 382 |
| 2005 → 2020 | 105 | 55 | 57 | −20.3 | +1.6  | −14.3 | +11.1 | −21.5     | +10.3 | −7.4 | 466 | 298 |
| 2005 → 2022 ᶜ | 99 | 49 | 61 | **−24.9** | +15.9 | −35.1 | +4.9  | **−11.6** | +10.2 | −9.2 | 369 | 286 |
| 2007 → 2012 | 129 | 35 | 33 | −12.8 | −6.6  | −3.9  | +4.0  | −10.4     | +10.8 | −6.7 | 804 | 362 |
| 2007 → 2020 | 109 | 51 | 53 | −16.8 | −12.6 | −18.5 | +9.3  | **+2.6**  | +9.5  | −7.1 | 534 | 231 |
| 2007 → 2022 ᶜ | 103 | 45 | 57 | **−21.1** | +0.7  | −32.0 | +5.0  | **+4.8**  | +9.4  | −9.0 | 442 | 227 |
| 2012 → 2020 | 126 | 34 | 38 | −4.7  | −7.0  | −17.1 | +14.5 | **+4.2**  | +3.1  | −2.3 | 383 | 158 |
| 2012 → 2022 ᶜ | 120 | 28 | 41 | **−12.6** | +6.8  | −29.5 | +11.1 | **−0.9**  | +2.9  | −2.9 | 334 | 170 |
| **2005 → 2012 [triple-bal]** | **101** | 0 | 0 | **−22.2** | +12.5 | +9.2  | +9.8  | **−53.7** | 0 | 0 | — | — |
| **2012 → 2020 [triple-bal]** | **101** | 0 | 0 | **−3.3**  | −9.1  | −16.2 | +12.5 | **+9.5**  | 0 | 0 | — | — |
| **2005 → 2020 [triple-bal]** | **101** | 0 | 0 | **−24.8** | +2.2  | −15.9 | +12.0 | −23.1     | 0 | 0 | — | — |

ᶜ **Rows ending in 2022 exclude three contaminated VATs from every year.** One NACE 24 installation (likely ArcelorMittal Gent) and two NACE 20 installations come off EUTL reporting in 2021 while their Annual Accounts revenue continues or grows — diagnosed as installation-level reclassification, not real abatement (see finding 5 below). The unrestricted 2005→2022 row was Total $-37.3$ with Technique $-25.6$; excluding the three VATs yields Total $-24.9$ with Technique $-11.6$, i.e.\ $\sim 12$ pp of Total and $\sim 14$ pp of Technique in the unrestricted row were artefact. The unrestricted 2007→2022 and 2012→2022 rows are not reported.

### Key findings

1. **Within-firm abatement reverses post-2012 on the same firms.** The triple-balanced panel makes this unambiguous: among the 101 firms present in all three years, technique is **−53.7 pp over 2005→2012 and +9.5 pp over 2012→2020**. The intensity gains accumulated in Phase I/II partially *reversed* from 2012 onward. The full-window technique of −23.1 pp is the net. The near-identical-sample comparison across windows rules out sample composition as the explanation for the difference seen earlier (−49.6 in 2005→2012 vs +4.2 in 2012→2020). Among the same firms, the reversal is larger (+9.5 vs +4.2) when measured cleanly.

2. **Between-sector reallocation is carrying the post-2012 decline.** On the triple-balanced sample, between = −16.2 over 2012→2020 while technique is +9.5 — the manufacturing-mix shift of the Belgian economy is more than offsetting the within-firm intensity drift.

3. **Within-sector reallocation remains consistently positive.** +9.2 to +14.5 pp across every window, including on the triple-balanced panel. Dirtier firms have been slowly gaining share within their NACE 2d — reinforces the main null finding on within-sector reallocation even under the strictest sample.

4. **Entrants are consistently more emission-intensive than exiters.** `z_ent` exceeds `z_exit` in every unrestricted pair, with ratios ranging from 1.4x (2005→2007) to 2.4x (2012→2020). This is the opposite of what a "dirty firms die under ETS pressure, clean firms enter" story would predict. Likely mechanisms: (i) "exit" in our data is data-loss, not literal firm death (Annual Accounts missingness); (ii) "entrants" include firms that came online after $t_{\text{base}}$ and may be in their capacity ramp-up phase with elevated intensity; (iii) firms whose emissions toggled past the zero threshold between the two years. In net emissions terms, entry and exit still roughly cancel (|Entry − Exit| ≤ 4.4 pp in every unrestricted row), because emissions-weighted contributions depend on both mean intensity *and* size, and exiters tend to be larger.

5. **Three large post-2020 EUTL reclassifications distort the 2022 picture.** Diagnosed 2026-04-23: one NACE 24 firm (likely ArcelorMittal Gent: 4.6 Mt → 0.09 Mt over 2020→2022 while revenue rose 3,399 → 6,476 M€) and two NACE 20 firms show emissions and free allocation collapsing to near-zero in 2021 while their revenue continues or grows. This is installation-level reporting change, not real abatement or firm closure. NACE 21's 2021 free-allocation cut is the intended Phase IV benchmark reset, not a data break. Excluding the three firms from every year of the analysis and re-running the pair decomposition yields the `[ex. 3 VATs]` rows: **the 2005→2022 Total shrinks from −37.3 to −24.9 pp, and Technique from −25.6 to −11.6 pp** — most of the apparent "abatement" over 2005→2022 is actually reclassification. Between-sector reallocation strengthens slightly (−31.7 → −35.1) on the clean panel, confirming it is the genuine driver of the post-2012 decline. The 2012→2022 clean row (−12.6 total, Tech −0.9) makes the paper's headline sharp: on the non-reclassified sample, there is essentially no within-firm abatement over 2012–2022.

### Caveats

- Exit ≠ firm death: a firm is an "exiter" if its emissions are missing or zero in $t_{\text{end}}$, which usually reflects Annual Accounts data availability rather than an actual plant closure. The 281-firm EUTL roster is nearly stable in every year.
- "Between" here uses only survivors' sector aggregates, not the full panel (unlike the fixed-base Table 1). Numbers are therefore not directly comparable to Table 1's `between_sector` column even for overlapping years.
- The triple-balanced panel (101 firms) is a selected sample — firms with continuous emissions *and* Annual Accounts coverage across 15 years are likely larger and more established than the broader population. The direction of the 2012→2020 technique reversal is however consistent with the 126-firm pair-wise estimate (+4.2), so selection is not driving the sign.

---

*Generated by `analysis/phase0_decomposition.R`, `analysis/phase0_melitz_polanec.R`, `analysis/phase0_ets_share_shift.R`, `analysis/phase0_pairwise_decomposition.R`, `analysis/phase1a_output_share_by_exposure.R`, `analysis/phase4_sector_passthrough_classification.R`, and `analysis/phase4_firm_output_reallocation.R`. April 2026.*
