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
| **2020 → 2022 [triple-bal, ex. 3 VATs]** | 96 | 0 | 3 | **−3.8** | +12.5 | −13.5 | −8.7 | **+6.4** | 0 | −0.4 | — | — |

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

## Phase 4 (B2B network) — within-NACE4d reallocation

> **Bottom line.** Six independent identification strategies on the full NBB-RMD B2B panel — intensive-margin DiD, top-quartile heterogeneity (NACE4d input share, omega gap), extensive-margin DiD on supplier survival, buyer-side coverage, total-variation-distance placebo, and new-supplier omega-rank DiD — all return a null or anti-leakage signal at every ETS event year (2008, 2013, 2017). The single positive-direction estimate (top-Q-by-omega-gap at τ = 2013, β = −0.10, p = 0.009) is small (10pp), thin (214 cells), and absent at 2008 and 2017. **Within-NACE4d substitution between EUTL-regulated suppliers and their non-EUTL peers is empirically inactive.** Section closed.

Added 2026-05-12. Body of seven scripts running on full NBB-RMD data: `analysis/phase4_within_nace4d_reallocation_did.R`, `_topQ.R`, `_topQ_heterogeneity.R`, `_placebo.R`, `_plots.R`, `phase4_within_nace4d_extensive_DiD.R`, `phase4_within_nace4d_extensive_margin.R`, plus the new-supplier-pick family `phase4_new_relationships_omega_rank*.R`. All ask one version of the question: *within a NACE4d, do buyers shift expenditure or supplier choice away from carbon-cost-exposed (high-omega) firms after each ETS event year (2008 Phase II onset, 2013 Phase III auctioning, 2017 MSR decision)?*

### Section 1: Top-omega vs bottom-omega supplier DiD (intensive margin)

Script: `analysis/phase4_within_nace4d_reallocation_did.R`. Output: [`phase4_within_nace4d_reallocation_did_coefs.tex`](output_rmd/tables/phase4_within_nace4d_reallocation_did_coefs.tex), [`_did_sanity.tex`](output_rmd/tables/phase4_within_nace4d_reallocation_did_sanity.tex).

For each treatment year τ ∈ {2008, 2013, 2017}, build (buyer, NACE4d, interval-period) cells using the 2-year pre-interval (2006–07 / 2011–12 / 2015–16). Cell must have ≥2 distinct suppliers in the interval *and* ≥1 supplier with omega > 0. Within each cell, identify the **top-omega** and **bottom-omega** supplier (ties broken by larger interval sales, then VAT). The bottom-omega supplier is the within-cell control — in ~85–98% of cells it has omega = 0 (a non-EUTL firm or an EUTL firm with surplus allocation in the interval).

```
share_ijt = α_ij + δ_t + β·(top_i × post_t) + ε
```

`α_ij` is cell × role FE; `δ_t` is year FE; SE clustered at the cell (buyer × NACE4d) level. β estimates how the top-omega supplier's expenditure share moved relative to the within-cell alternative after τ.

Results (RMD, post = post-τ):

| τ | n_obs | n_treated_cells | β (top × post) | SE | t-stat | p |
|---|---:|---:|---:|---:|---:|---:|
| 2008 | 113,946 | 4,515 | **+0.086** | 0.0082 | +10.5 | <0.001 |
| **2013** | **22,472** | **813** | **−0.003** | **0.0202** | **−0.14** | **0.89** |
| 2017 | 216,916 | 8,275 | **+0.145** | 0.0067 | +21.5 | <0.001 |

- **2013 is a clean null** (β = −0.003, p = 0.89): when Phase III auctioning begins, top-omega suppliers' within-cell expenditure share does not shift relative to the within-cell control. The small treated-cell count (813) reflects a substantive feature of the EU-ETS, not a power problem — see [`phase4_phase2_overallocation_table.tex`](output_local/tables/phase4_phase2_overallocation_table.tex). In Phase II, the 2008-09 financial crisis collapsed industrial emissions while the cap was only modestly tightened from Phase I, leaving the median Belgian EUTL firm with allocated_free / emissions = 1.33 and 89% of firms with `allocated ≥ emissions`. Only **24 of 168 firms** (14%) with full 2011-12 data had positive interval-averaged ω, vs 24% in Phase I and 70% in Phase III. The relaxed-filter DiD ([`phase4_within_nace4d_2013_diagnostic_relaxed_did_coefs.tex`](output_rmd/tables/phase4_within_nace4d_2013_diagnostic_relaxed_did_coefs.tex)) confirms the 2013 null at full power: dropping the ω > 0 requirement expands the cell sample to 290k and gives β = −0.00003, p = 0.89.
- **2008 and 2017 show top-omega suppliers GAINING share** (+0.086 and +0.145). The sign is the *opposite* of what the leakage hypothesis predicts. Two candidate stories: (i) mean reversion (top-omega suppliers had unusually low interval shares in the pre-period); (ii) the "winners' curse" of post-event-year share growth among the suppliers that were largest in pre-period.

Sanity diagnostic ([`_did_sanity.tex`](output_rmd/tables/phase4_within_nace4d_reallocation_did_sanity.tex)): in 43–47% of treated cells, the top-omega supplier is also the top-by-sales supplier in the interval. So the "top-omega supplier" identifier is partly capturing size as well as omega. Median within-cell Spearman correlation between omega and sales rank is 0.30–0.36. This complicates the interpretation of the positive 2008 and 2017 coefficients — they mix omega-driven and size-driven dynamics. Not a problem for the 2013 null since both channels would have to be zero for that result.

### Section 2: Top-quartile heterogeneity

Script: `analysis/phase4_within_nace4d_reallocation_topQ_heterogeneity.R`. Output: [`phase4_within_nace4d_reallocation_topQ_heterogeneity_did_coefs.tex`](output_rmd/tables/phase4_within_nace4d_reallocation_topQ_heterogeneity_did_coefs.tex).

Re-runs the DiD restricting the cell sample to the top quartile under two cuts:

- **By NACE4d input share**: cells where the buyer's interval-period spend on the NACE4d makes up the largest share of the buyer's total cost — i.e., buyers for whom this input matters most.
- **By omega gap**: cells where (omega_top − omega_bot) is largest in the interval — i.e., the supplier choice has the largest within-cell omega heterogeneity.

Results (RMD):

| Cut | τ | n_obs | n_treated_cells | β | p |
|---|---|---:|---:|---:|---:|
| NACE4d input share | 2008 | 31,128 | 1,128 | +0.160 | <0.001 |
| NACE4d input share | 2013 | 5,966 | 204 | −0.024 | 0.46 |
| NACE4d input share | 2017 | 60,332 | 2,065 | +0.067 | <0.001 |
| **Omega gap** | **2008** | 29,812 | 1,130 | **+0.234** | <0.001 |
| **Omega gap** | **2013** | **5,552** | **214** | **−0.103** | **0.009** |
| **Omega gap** | **2017** | 95,530 | 3,967 | **+0.289** | <0.001 |

One result deserves attention: **cells with the largest within-cell omega gap show a small but significant reallocation toward the bottom-omega supplier in 2013 (β = −0.10, p = 0.009)**. This is the single positive-direction evidence for leakage in the whole within-NACE4d body of work. Magnitude is modest (10pp of within-cell share), confined to 214 cells, and not robust across event years — 2008 and 2017 in the same cut show large *positive* coefficients (mean reversion / size effect dominating). For the headline pooled DiD at τ = 2013 this same group is part of the 22k-obs sample that gives β = −0.003, so the topQ-by-omega-gap movement is too small a slice to budge the pooled coefficient.

[`_topQ_buyertotal.png`](output_rmd/figures/phase4_within_nace4d_reallocation_topQ_buyertotal.png), [`_topQ_nace4dshare.png`](output_rmd/figures/phase4_within_nace4d_reallocation_topQ_nace4dshare.png), [`_topQ_omegagap.png`](output_rmd/figures/phase4_within_nace4d_reallocation_topQ_omegagap.png) — three descriptive trajectory plots (mean within-NACE4d share for top-omega vs bottom-omega supplier across event years, top-quartile sample). The omega-gap version makes the 2013 movement visible as a small post-Phase-III separation between the two lines.

### Section 3: Extensive-margin DiD (supplier survival)

Script: `analysis/phase4_within_nace4d_extensive_DiD.R`. Output: [`phase4_within_nace4d_extensive_DiD_coefs.tex`](output_rmd/tables/phase4_within_nace4d_extensive_DiD_coefs.tex), [`_extensive_DiD.png`](output_rmd/figures/phase4_within_nace4d_extensive_DiD.png).

Same cells and identification as Section 1, but the outcome is binary supplier presence:

```
transact_ijt = 1{spend(j, i, t) > 0}
transact_ijt = α_ij + δ_t + β·(top_i × post_t) + ε
```

A buyer "drops" a supplier when transact_ijt switches from 1 to 0. β < 0 with larger magnitude on top-omega than baseline means top-omega suppliers are more likely to be dropped post-τ.

Results (RMD):

| τ | n_obs | β (top × post) | SE | p |
|---|---:|---:|---:|---:|
| 2008 | 162,540 | +0.032 | 0.0068 | <0.001 |
| **2013** | **29,268** | **−0.032** | **0.0172** | **0.06** |
| 2017 | 297,900 | +0.124 | 0.0058 | <0.001 |

Same pattern as the intensive margin: **2008 and 2017 show top-omega suppliers MORE likely to survive (positive β, anti-leakage)**, **2013 shows a marginal negative coefficient** (top-omega suppliers slightly more likely to be dropped after Phase III auctioning). The 2013 effect is small (~3pp lower presence probability) and marginally significant (p = 0.06). Consistent with the topQ-omega-gap intensive result — there's a small post-2013 movement away from top-omega, but it's modest and only shows up at Phase III.

### Section 4: Buyer-level extensive margin (any ETS firm in NACE4d)

Script: `analysis/phase4_within_nace4d_extensive_margin.R`. Output: [`phase4_within_nace4d_extensive_margin.png`](output_rmd/figures/phase4_within_nace4d_extensive_margin.png).

Different unit of analysis. For each year t, the share of buyers active in an ETS-treated NACE4d that pick at least one ETS-regulated firm (EUTL-listed, in-sample) as a supplier within that NACE4d. Asks: of buyers exposed to ETS-treated NACE4d at all, what fraction transact with regulated firms specifically?

The share moves between ~23% and ~34% across 2005–2022 with year-on-year variation, but no monotone trend tied to ETS event years. The series fluctuates within a narrow band and shows no break at 2008, 2013, or 2017. Saturated at the buyer-population level — most variation is in which buyers happen to be active in mixed-treatment NACE4d sectors in any given year, not in selection behaviour.

### Section 5: Placebo — treated cells vs no-EUTL-exposure cells

Script: `analysis/phase4_within_nace4d_reallocation_placebo.R`. Outputs: [`_placebo_anyNACE4d.png`](output_rmd/figures/phase4_within_nace4d_reallocation_placebo_anyNACE4d.png), [`_placebo_etsNACE4d.png`](output_rmd/figures/phase4_within_nace4d_reallocation_placebo_etsNACE4d.png), [`_placebo_pooled.csv`](output_rmd/tables/phase4_within_nace4d_reallocation_placebo_pooled.csv).

A separate test that doesn't isolate top-omega vs bottom-omega within a cell, but rather compares **how much the supplier-share vector in each multi-supplier cell moves over time**, treated vs control. For each cell × year, compute the total-variation distance from the cell's base-year share vector:

```
R_jt = 1 − Σ_i min(s_ij,t, s_ij,base)
```

R ∈ [0, 1] with 0 = identical, 1 = no overlap. By construction R = 0 in the base year (norm year = last year of the interval).

- **Treated cells**: cells with ≥1 supplier in the interval having omega > 0.
- **Placebo cells**: cells where no supplier in the interval is in EUTL at all (no ETS exposure of any kind).

Two universes: all multi-supplier cells (`anyNACE4d`) and only cells where the supplier-NACE4d contains ≥1 ETS firm (`etsNACE4d`).

Reads ([`_placebo_pooled.csv`](output_rmd/tables/phase4_within_nace4d_reallocation_placebo_pooled.csv)): treated and placebo trajectories track each other closely across all three event years. Mean R_jt grows ~0.4–0.55 at any horizon for both groups, with overlapping CIs in essentially every year. **No differential reallocation in treated cells beyond the natural year-to-year share churn that placebo cells also exhibit.** This rules out a "treated cells reshuffle more than untreated cells" story.

### Section 6: New-supplier omega-rank (relational-capital falsification)

Scripts: `analysis/phase4_new_relationships_omega_rank.R`, `_did.R`, `_diagnostics.R`, `_pre2005.R`, `_intensive_overlap.R`, `_supplier_test.R`. All findings below run on full NBB-RMD data under the 2-event (2005, 2017) spec.

Sections 1-5 test reallocation within *existing* supplier portfolios. This section tests reallocation at the **new-relationship margin**, where switching costs are zero by construction. The intended role of this section is a falsification of the "relational capital / switching costs" explanation for the Section 1 null: if switching costs were what suppressed within-NACE4d reallocation, the new-pair margin should show buyers shifting toward cleaner suppliers post-event. It doesn't.

#### Specification

For each (buyer j, supplier i, year_first) triplet, define:

- Pair is "new" in year_first if it is first observed in B2B in year_first. B2B starts in 2002; pairs first observed in 2002 are dropped as left-censored.
- Supplier omega in year t: `omega1_it = shortage_it / total_cost_it` (Def 1, net carbon-cost burden; the headline). Def 2 (`emissions_it / total_cost_it`) is tracked in parallel for descriptives only.
- Omega rank: percentile rank of supplier i within NACE4d N in year t among all EUTL firms with non-missing omega in (N, t). Higher rank = dirtier.
- **Headline LHS (formal DiD)**: supplier's rank in year τ − 1, fixed across all rel-years. For τ = 2017 the reference year is 2016. For τ = 2005, EUTL data starts in 2005 itself so the reference year is 2005 (contemporaneous; the only feasible choice). Fixing the rank by construction strips out within-firm omega evolution: any movement in coefficients across rel-years is composition (which suppliers buyers pick).
- **Descriptive LHS (trajectory plots only)**: supplier's rank in year_first (year-t rank). Used only for the headline trajectory plot. *Not* used as a regression LHS — Test 3 below shows why it is methodologically contaminated.

Sample for the formal DiD: new pairs in ETS-treated NACE4d with `year_first ∈ [τ − 5, τ + 5]` and a non-missing τ−1 supplier rank. SEs two-way clustered on buyer and supplier-NACE4d. We also run a "drop NACE 3511" (electricity) robustness for each τ, and a supplier-tenure-controlled spec (continuous control = `year_first − supplier_first_b2b_year`, absorbs cross-cohort survivor selection in the fixed-rank LHS).

#### Identification independence from Sections 1-5: intensive-overlap diagnostic

[`_intensive_overlap_counts.png`](output_rmd/figures/phase4_new_relationships_intensive_overlap_counts.png), [`_intensive_overlap_size.png`](output_rmd/figures/phase4_new_relationships_intensive_overlap_size.png). Script: `analysis/phase4_new_relationships_intensive_overlap.R`.

Two facts:

1. **Sample disjointness.** Only **4-15% per year** of new omega-matched pairs land in a buyer-NACE4d-year cell with ≥2 omega-able suppliers. The remaining **85-96% are single-seller cells** — buyers entering a NACE4d through one supplier, invisible to the intensive-margin (GK / OP-covariance / output-share-by-tercile) tests by construction.
2. **Cell dominance.** For omega-matched new pairs, the median share of the new supplier within the buyer's total NACE4d spend is **100% throughout 2006-2022**. Mean is 85-92%. The typical new relationship IS the buyer's entire exposure to that NACE4d in that year.

Implication: the omega-rank analysis identifies off **market entry**, not within-portfolio switching. The intensive-margin tests cover existing relationships; this section covers initial entries. The two margins do not share identifying variation, so the absence of intensive-margin reallocation does not pre-determine the new-pair result, and vice versa.

#### Headline DiD: rank fixed at τ−1

Script: `analysis/phase4_new_relationships_omega_rank_did.R`. Output: [`_did_coefs.tex`](output_rmd/tables/phase4_new_relationships_omega_rank_did_coefs.tex), event-study figures [`_did_event_study_2005.png`](output_rmd/figures/phase4_new_relationships_omega_rank_did_event_study_2005.png), [`_did_event_study_2017.png`](output_rmd/figures/phase4_new_relationships_omega_rank_did_event_study_2017.png).

Pooled β at both events, base and tenure-controlled, full and drop-NACE-3511 samples (RMD):

| τ | Sample | spec | n_obs | β | SE | p |
|---|---|---|---:|---:|---:|---:|
| 2005 | Full | base | 40,381 | +0.022 | 0.019 | 0.27 |
| 2005 | Full | +tenure | 40,381 | +0.036 | 0.044 | 0.41 |
| 2005 | Drop NACE 3511 | base | 28,304 | **+0.039** | 0.017 | **0.024** |
| 2005 | Drop NACE 3511 | +tenure | 28,304 | +0.067 | 0.041 | 0.11 |
| **2017** | **Full** | **base** | **45,572** | **+0.019** | **0.013** | **0.15** |
| 2017 | Full | +tenure | 45,572 | −0.064 | 0.052 | 0.22 |
| 2017 | Drop NACE 3511 | base | 24,698 | +0.023 | 0.017 | 0.18 |
| 2017 | Drop NACE 3511 | +tenure | 24,698 | −0.085 | 0.063 | 0.18 |

Three observations:

1. **All base-spec coefficients are positive at both events.** Point estimates point to buyers picking marginally *dirtier* suppliers post-τ (wrong sign for leakage), but each is small (≤+0.04) and only the τ=2005 drop-NACE-3511 row is significant at 5% (and that one becomes null under tenure control).
2. **At τ=2017, the headline is a null** (β = +0.019, p = 0.15). The tenure-controlled spec flips the post coefficient to −0.064 with SE 0.052 — the survivor channel is real and was inflating the base coefficient upward, but the CI is wide enough that we cannot reject zero in either direction.
3. **Pre-trend issues at τ=2017** are visible in the event-study figure. Base spec: rel-year=−5 at −0.17, rel-year=−2 at +0.06 — reference-year (2016) contamination dominates. Tenure control flattens the far-pre by ~40-50% (rel-year=−5 moves from −0.17 to −0.10) but does not fix the rel-year=−2 spike, which is from a different mechanism (next subsection).

#### Cohort-composition diagnostic: the 2016 reporting wave

Outputs: [`_did_cohort_count_2017.png`](output_rmd/figures/phase4_new_relationships_omega_rank_did_cohort_count_2017.png), [`_did_cohort_vintage_2017.png`](output_rmd/figures/phase4_new_relationships_omega_rank_did_cohort_vintage_2017.png), plus τ=2005 counterparts and underlying CSVs.

At τ=2017, the 2016 cohort (year_first = 2016) is anomalous on two dimensions:

- **Cohort size**: ~45k new pairs in 2016 vs ~4-7k in 2012-2015 — a ~10× spike.
- **Supplier vintage**: mean `supplier_first_b2b_year` for the 2016 cohort is ~2002.1 — the *longest-tenured* suppliers in the entire window (vs ~2002.9 for 2014-15 cohorts).

Together these rule out "wave of newly-reporting suppliers" and point to **a wave of buyers entering the B2B panel** in 2016 (the 2015-16 B2B reporting-threshold change), forming relationships with already-established suppliers. Since rel-year=−1 (2016) is the event-study reference category, the pre-trend deviation at rel-year=−2 is a **reference-year artifact**. The fixed-at-τ-1 pooled DiD post coefficient (which averages over rel-years on each side) is not directly affected, but the event-study figure should be read with this in mind.

#### Why we don't lean on year-t-rank as the headline LHS

Script: `analysis/phase4_new_relationships_omega_rank_supplier_test.R`. Output: [`_supplier_test_coefs.tex`](output_rmd/tables/phase4_new_relationships_omega_rank_supplier_test_coefs.tex).

A natural alternative LHS is the supplier's rank in the year the pair forms (year-t rank). The descriptive trajectory shows a ~5pp decline in mean pick rank from pre- to post-2017 (see [`_def2.png`](output_rmd/figures/phase4_new_relationships_omega_rank_def2.png)). Two supplier-level tests rule out interpreting this as buyer-behavior change.

**TEST 3: mean reversion in rank.** Δrank ~ rank_at_(τ−1) | NACE4d FE, where Δrank = rank_at_(τ+5) − rank_at_(τ−1).

| τ | β | SE | p | n | Implied ρ |
|---|---:|---:|---:|---:|---:|
| 2005 | **−0.946** | 0.13 | <0.001 | 89 | 0.05 |
| 2017 | **−0.536** | 0.11 | <0.001 | 120 | 0.46 |

The rank distribution is not stable at the firm level. At τ=2005, rank in 2005 is essentially uncorrelated with rank in 2010 (ρ ≈ 0.05). At τ=2017, modest persistence (ρ ≈ 0.46). Even under unchanged buyer behavior, if buyers slightly prefer high-rank suppliers (descriptive mean pick rank ≈ 0.55) and high-rank suppliers tend to drop in rank, the year-t rank of picks declines mechanically — making any year-t decline observationally consistent with Story A (no behavior change).

**TEST 4: rank-change decomposition.** Why is rank unstable? `omega = (emissions − allocated_free) / total_cost`, so rank can shift because the supplier's emissions, free allocations, or total cost change. We regress Δlog(X)_i ~ rank_pre_i | NACE4d FE for each X.

| τ | Channel | β | SE | p | n |
|---|---|---:|---:|---:|---:|
| 2005 | Δlog(emissions) | **−0.826** | 0.41 | 0.06 | 88 |
| 2005 | Δlog(allocated_free) | −0.008 | 0.20 | 0.97 | 89 |
| 2005 | Δlog(total_cost) | **−0.465** | 0.25 | 0.07 | 89 |
| 2005 | Δlog(emissions/cost) | −0.360 | 0.58 | 0.54 | 88 |
| 2017 | Δlog(emissions) | **−0.423** | 0.16 | **0.02** | 119 |
| 2017 | Δlog(allocated_free) | +0.052 | 0.12 | 0.68 | 110 |
| 2017 | Δlog(total_cost) | −0.186 | 0.28 | 0.51 | 120 |
| 2017 | Δlog(emissions/cost) | −0.229 | 0.36 | 0.53 | 119 |

Three observations:

1. **Allocations are unrelated to rank at both events.** Free-allocation cuts are *not* the mechanism driving rank changes — the rank decline of high-rank firms is not a mechanical policy artefact via allocation revisions.
2. **Emissions decline correlates strongly with high pre-rank.** At τ=2017, β = −0.42 (p = 0.02): a 1-unit increase in rank_pre (full percentile range) is associated with a 42 log-point larger reduction in emissions. At τ=2005, β = −0.83 (p = 0.06).
3. **Part of the emissions decline is output shrinkage, part is intensity reduction.** At τ=2005 cost and emissions decline together (β = −0.47, −0.83) — high-rank firms shrunk. At τ=2017 emissions decline outpaces cost (−0.42 vs −0.19), and intensity Δlog(emissions/cost) is itself negative on rank_pre (β = −0.23, though insignificant) — consistent with some real intensity-reducing abatement among high-rank firms.

**The takeaway**: rank changes are not pure measurement noise — they reflect a behavioural channel (emissions reductions among high-rank firms, mix of output shrinkage and intensity-reducing abatement). Using year-t rank as the LHS would therefore conflate buyer behaviour with this supplier-side abatement channel. The fixed-at-τ−1 LHS (used as a robustness reference in this section) is the cleaner choice by construction; the supplier-level Test 1 below is the cleanest *direct* test of buyer behaviour change.

**TEST 2: popularity ↔ abatement.** Δrank ~ log(1 + n_new_pre) | NACE4d FE.

| τ | β | SE | p | n |
|---|---:|---:|---:|---:|
| 2005 | −0.013 | 0.020 | 0.54 | 89 |
| 2017 | −0.012 | 0.016 | 0.48 | 120 |

Pre-event popular suppliers do not differentially abate at either event. The supplier-side abatement documented in Test 4 is general (correlated with pre-rank itself, not with pre-popularity). Test 4 already rules out year-t rank as a clean LHS; Test 2 just confirms the same conclusion under a tighter framing.

#### TEST 5 — Year-t-rank event study restricted to stable-NACE4d (robustness)

Script: same. Outputs: [`_supplier_test_stable_nace4d_summary.csv`](output_rmd/tables/phase4_new_relationships_omega_rank_supplier_test_stable_nace4d_summary.csv), [`_supplier_test_stable_yeartrank_event_study.png`](output_rmd/figures/phase4_new_relationships_omega_rank_supplier_test_stable_yeartrank_event_study.png).

A complementary check: in NACE4d where supplier rank order is *preserved* between τ−1 and τ+5, year-t rank ≈ rank-at-τ−1 by construction, so the year-t-rank LHS is not confounded by within-firm rank evolution. We identify these NACE4d at τ=2017 by Spearman ρ of (rank_2016, rank_2022) within each NACE4d with ≥ 3 EUTL firms at both endpoints.

Stable-NACE4d counts at τ=2017 (out of 17 NACE4d with ≥ 3 EUTL firms tracked):

| Threshold | # NACE4d stable | # EUTL firms | # new pairs in [2012, 2022] window |
|---|---:|---:|---:|
| ρ = 1.0 | 4 | 13 | small |
| ρ ≥ 0.9 | 5 | 18 | ~950 |
| ρ ≥ 0.8 | 7 | 28 | ~1,030 |

(At τ=2005, no NACE4d are stable at any threshold — consistent with the −0.95 Test 3 coefficient. The stable-NACE4d robustness only applies at τ=2017.)

Within each stable-NACE4d subsample, run the year-t-rank event study:

```
rank_year_first_ij = Σ_{e ≠ −1} β_e · 1{year_first − 2017 = e}
                       + α_buyer + γ_NACE4d + ε_ij      (ref e = −1)
```

SE two-way clustered: buyer × supplier-NACE4d.

The event-study figure shows post-period coefficients hovering near zero (0 to +0.10) at all three thresholds, with CIs straddling zero throughout. Pre-trends are not perfectly flat — rel-year=−5 (2012) shows a ~+0.19 spike at the ρ ≥ 0.8 and ρ ≥ 0.9 thresholds — but the post-period coefficients are small and centred at zero, supporting the headline null. ρ = 1.0 is too noisy (4 NACE4d) to interpret.

Reading: in the subsample of NACE4d where the year-t-rank LHS is logically valid (supplier rank is stable), the post-event coefficients do not differ from zero — consistent with the supplier-level Test 1 null below.

#### Supplier-level Story A vs B DiD

The cleanest direct test of "did buyer behavior change?" — robust to mean reversion (Test 3), survivor bias, and reference-year contamination — is a supplier-level DiD on new-buyer counts:

```
log(1 + n_pairs_it) = β · post_t × abater_i + α_seller + γ_period + ε
```

where `abater_i = 1{Δrank_i < median(Δrank)}` and SEs clustered at supplier (`seller`).

| τ | β (post:abater) | SE | p | n |
|---|---:|---:|---:|---:|
| 2005 | +0.334 | 0.30 | 0.27 | 238 |
| **2017** | **+0.052** | **0.14** | **0.71** | 292 |

**At τ=2017, abaters do not differentially gain new buyers post-event.** A buyer choice rule shifting toward cleaner suppliers would imply a positive coefficient; the data shows essentially zero. Story B (buyer behavior change at the new-pair margin) is rejected at the headline event. At τ=2005 the point estimate is positive (+0.33) but the CI is wide (SE 0.30); we cannot reject either story with the Phase-I-launch sample.

#### Pre-2005 extension and within-firm abatement decomposition

[`_pre2005_hybrid.png`](output_rmd/figures/phase4_new_relationships_omega_rank_pre2005_hybrid.png), [`_pre2005_fixed.png`](output_rmd/figures/phase4_new_relationships_omega_rank_pre2005_fixed.png). Script: `analysis/phase4_new_relationships_omega_rank_pre2005.R`.

EUTL omega starts in 2005 but B2B starts in 2002. We extend the descriptive trajectory to 2003-2022 using the supplier's 2005 within-NACE4d rank for new pairs in 2003-2004. Two versions: **Hybrid** (2005-baseline rank for 2003-04, year-t rank for 2005+) and **Fixed** (2005-baseline rank for all years 2003-2022, strips within-firm evolution).

Two findings persist from the prior 3-event analysis:

1. **The 2003-2005 pre-policy baseline (~0.60) matches the post-2008 long-run level**, while 2006-2007 spikes to 0.81-0.85. The Phase-I peak is a small-N coverage anomaly, not a behavioural signal.
2. **The hybrid − fixed gap from 2018 onward (~−0.08) bounds the within-firm omega channel**: post-2015 the hybrid plot drifts to 0.47 while the fixed plot stays at 0.55 — incumbent suppliers becoming cleaner over time, not buyers picking different suppliers. The within-firm abatement story already documented in §3.1, measured here from the buyer-side. Test 3 generalizes the same finding via mean reversion in the EUTL rank distribution.

#### Leave-one-NACE4d-out and leave-one-buyer-out robustness

Script: `analysis/phase4_new_relationships_omega_rank_diagnostics.R`. Outputs: `_loo_nace4d{,_fixed2005}.{png,pdf}`, `_loo_nace4d_{2005,2017}diff.csv`, `_loo_buyer{,_fixed2005}.{png,pdf}`, `_loo_buyer_{2005,2017}diff.csv`. Two rank panels per event: year-t rank for τ=2017 LOO diffs, fixed-2005 rank for τ=2005 LOO diffs.

LOO trajectories at both events cluster tightly around the main line on the descriptive plots — no single supplier-NACE4d drives the headline trajectory. The drop-NACE-3511 robustness at the pooled-DiD level is already covered in the headline DiD table above and does not change the qualitative conclusion at τ=2017.

#### Bottom line: relational capital does not explain the within-NACE4d null

Three independent pieces of evidence converge at τ=2017:

- **Fixed-at-τ−1 event-study (headline DiD)**: post β = +0.019 (p = 0.15). No composition shift toward suppliers with low τ−1 rank.
- **Tenure-controlled headline DiD**: post β = −0.064 (SE 0.052, p = 0.22). Survivor channel partially absorbed; CI includes zero.
- **Supplier-level Story-A-vs-B DiD (Test 1)**: post:abater = +0.052 (p = 0.71). Abaters do not differentially gain new buyers.

If relational capital / switching costs explained the within-NACE4d intensive-margin null (Sections 1-5), buyers at the new-pair margin — where switching costs are zero — should shift toward cleaner suppliers. They don't, on either the composition (fixed-rank) or behavioral (supplier-level DiD) test. **Switching costs are ruled out as the explanation for the Section 1 null.**

A residual +0.039 (p=0.024) coefficient at τ=2005 drop-NACE-3511 base spec goes away with the tenure control (+0.067, p=0.11) and is not robust to specification. Small sample (n ≈ 20-30 cells in this restricted cut); not interpreted.

### Section 7: Combined interpretation across all six tests

Six distinct identification strategies on the B2B-network panel, each asking a different version of "do buyers shift away from carbon-cost-exposed suppliers within NACE4d?":

| # | Test | Identifying variation | τ = 2008 | τ = 2013 | τ = 2017 |
|---|---|---|---|---|---|
| 1 | Top-omega vs bottom-omega DiD (intensive) | Within multi-supplier cells, share of top-omega vs bottom-omega supplier | **+0.086** (anti-leakage) | −0.003 (null) | **+0.145** (anti-leakage) |
| 2 | Top-Q heterogeneity (by omega gap) | Subset to cells with largest within-cell omega heterogeneity | +0.234 (anti-leakage) | **−0.103** (weak leakage signal) | +0.289 (anti-leakage) |
| 3 | Extensive DiD (supplier survival) | Same cells, binary supplier-presence outcome | +0.032 (anti-leakage) | −0.032 (weak leakage signal, p=0.06) | +0.124 (anti-leakage) |
| 4 | Buyer-extensive: share buying from any ETS firm | All buyers in ETS-NACE4d, binary picked-any-EUTL-firm | flat | flat | flat |
| 5 | Placebo (R_jt total-variation distance) | Treated cells vs no-EUTL-exposure cells, both universes | tracks placebo | tracks placebo | tracks placebo |
| 6 | New-supplier omega-rank DiD (τ−1-fixed rank) | New-pair formation in NACE4d, supplier's rank at τ−1 | +0.034 (p=0.05, gone after dropping 3511) | **+0.002** (clean null) | +0.019 (pre-trend violated) |

Three regularities across the six tests:

1. **2013 is consistently the cleanest event.** Test 1 (β = −0.003, p = 0.89), Test 3 (β = −0.032, p = 0.06), Test 6 (β = +0.002, p = 0.13, CI ±0.5pp) all agree on a null. The Phase III auctioning regime change does not move within-NACE4d supplier choice.

2. **2008 and 2017 show large positive (anti-leakage) coefficients on Tests 1 and 3.** Top-omega suppliers *gained* expenditure share and were *more likely* to be retained around Phase II and the MSR decision. Sanity check from Test 1 ([`_did_sanity.tex`](output_rmd/tables/phase4_within_nace4d_reallocation_did_sanity.tex)): 43–47% of treated cells have top-omega supplier = top-by-sales supplier, so these specifications partly capture size dynamics rather than pure omega effects. Mean reversion of supplier shares plus this size confound is the most parsimonious interpretation. The 2008 spec is further contaminated by the 2006–07 Phase I data quirks (Test 6 makes this explicit); the 2017 spec by the 2015 reporting cohort spike. Neither offers credible identification.

3. **The only positive-direction evidence** for within-NACE4d leakage anywhere in the six tests is the top-quartile-omega-gap cells at τ = 2013 (Test 2: β = −0.10, p = 0.009; Test 3: β = −0.032, p = 0.06). Magnitude is modest, sample is small (214 cells), and the effect doesn't generalise to other event years or other heterogeneity cuts. Worth flagging as the one weak signal but not a paper headline.

Headline mean-rank features in Test 6 that initially looked like reallocation decompose into three known data features, none of them behavioural:

- A **2006–2007 sample/coverage anomaly** in early Phase I (Test 6 Diagnostic 2 — the "Phase II cliff" is reversion to long-run baseline).
- **Within-firm omega cleaning** of incumbent suppliers post-2015 (Test 6 Diagnostic 2 hybrid − fixed gap — the *same* suppliers are abating, not different suppliers being picked).
- A **NACE 3511 (electricity)** sector-specific shift in generation mix (Test 6 Diagnostic 1 — sole sign-flipping sector under LOO).

Combined with the §3.1 evidence — within-sector reallocation ≈ 0 by GK decomposition, OP-covariance × carbon-cost null, output-share-by-exposure-tercile no post-MSR break — the within-NACE4d reallocation channel is empirically inactive on **all four** identification approaches we have tried: emissions-share decompositions, carbon-cost-correlation panels, output-share level tests, and B2B-network supplier-choice tests (intensive, extensive, and new-supplier picks).

**The within-NACE4d analysis is closed.** Remaining margins to test (per [TODO.md §1b](TODO.md)) are across-NACE4d (intensive + extensive) and international supplier substitution (intensive + extensive).

### Section 8: Caveats (whole Phase 4 B2B network within-NACE4d)

- Tests 1–3 and 6 only cover reallocation involving the ~150–200 large EUTL-regulated firms in Belgium per year (the omega-rankable supplier universe). Reallocation among smaller non-ETS firms in the same NACE4d is not measured by this design.
- Tests 1 and 3 use top-omega vs bottom-omega within-cell — but top-omega supplier ≈ top-by-sales supplier in ~45% of cells, so the specifications partly capture size dynamics. Pure omega isolation would require Tests 2 (top-Q by omega gap) or 6 (omega-rank as outcome).
- Test 6 fixed-rank DiD strips within-firm omega evolution by construction. Test 6 also reports the hybrid (year-t rank) trajectory separately to characterise the within-firm channel.
- All p-values are unconditional; we have not adjusted for the multiple hypothesis testing implicit in running six tests × three event years × multiple sample restrictions.

---

## Phase 4 (B2B network) — across-NACE4d reallocation

Added 2026-05-12. Scripts: the `analysis/phase4_across_nace4d_intensive_*.R` family (4 cuts) and `analysis/phase4_across_nace4d_extensive_*.R` family (4 cuts × 2 outcomes). All findings below on full NBB-RMD data.

Companion to the within-NACE4d section. Asks whether buyers shift expenditure or supplier choice **across NACE4d sectors** in response to ETS — e.g., from ETS-treated to non-ETS NACE4d, or from high-shortage to low-shortage ETS-NACE4d. Headline definition: a NACE4d is "ETS-treated" if it contains ≥1 EUTL-listed firm in any year; "high-shortage" if its 2008–12 sum_shortage / sum_total_cost (over EUTL firms in that NACE4d) is positive.

### Four heterogeneity cuts × two margins

| Cut | Intensive margin (share of buyer expenditure) | Extensive margin (share of buyers + count of distinct sectors) |
|---|---|---|
| **#1 Sector shortage** (high vs low ETS-NACE4d) | High-shortage ≈ 3%, low-shortage ≈ 13%, non-ETS ≈ 83%. **All three flat 2005–2022.** [`_intensive_by_shortage.png`](output_rmd/figures/phase4_across_nace4d_intensive_by_shortage.png) | Share: high-shortage drifts ~53% → ~43% pre-2015, then a ~17pp upward step at 2015–16, settling ~60%+ post-2016. **The 2015–16 break survives full sample — a real B2B reporting discontinuity, not downsampling.** Count: both bins flat at ~2.3 / ~2.7. [`_extensive_by_shortage_share.png`](output_rmd/figures/phase4_across_nace4d_extensive_by_shortage_share.png), [`_count.png`](output_rmd/figures/phase4_across_nace4d_extensive_by_shortage_count.png) |
| **#2 Buyer pre-period exposure quartile** | Q3 high-exposure ~13% (2012) → ~10% (2022), monotonic. Q0/Q1/Q2 cluster <4%. **The Q3 decline is the most consistent positive-direction signal but timing doesn't line up with ETS events** — see note below. [`_intensive_by_buyer_exposure.png`](output_rmd/figures/phase4_across_nace4d_intensive_by_buyer_exposure.png) | Share: Q3 stable at 90–95%; Q3 buyer-level count of distinct high-shortage NACE4d *rises* 2.7 → 3.1 post-2018. [`_extensive_by_buyer_exposure_share.png`](output_rmd/figures/phase4_across_nace4d_extensive_by_buyer_exposure_share.png), [`_count.png`](output_rmd/figures/phase4_across_nace4d_extensive_by_buyer_exposure_count.png) |
| **#4 Domestic vs imported** (same NACE4d set via HS→NACE4d concordance) | Domestic ~80%, imports ~20%, **flat across 2005–2018**. No leakage-via-imports signal. [`_domestic_vs_imported.png`](output_rmd/figures/phase4_across_nace4d_domestic_vs_imported.png) | Share of buyers importing any high-shortage product: ~1%, flat. Count of imported high-shortage NACE4d per buyer: 0.36, flat. [`_extensive_domestic_vs_imported_share.png`](output_rmd/figures/phase4_across_nace4d_extensive_domestic_vs_imported_share.png) |
| **#7 Size × exposure** (size quartiles within each pre-period exposure bin) | In the high-exposure facet, Q4 (largest) drifts down ~95% → ~80% across 2010–2022. Q1/Q2/Q3 hold steady. Other facets show no pattern. [`_intensive_by_size_holding_exposure.png`](output_rmd/figures/phase4_across_nace4d_intensive_by_size_holding_exposure.png) | Q4 high-exposure count of distinct high-shortage NACE4d ~4 throughout, slight upward drift. Other facets flat or near-zero. [`_extensive_by_size_holding_exposure_share.png`](output_rmd/figures/phase4_across_nace4d_extensive_by_size_holding_exposure_share.png), [`_count.png`](output_rmd/figures/phase4_across_nace4d_extensive_by_size_holding_exposure_count.png) |

### Interpretation

Seven of ten cells in the table above are clean flats. Two of the three "movement" cells are contaminated by known issues:

- **The pre-2015 decline in cut #1 extensive share** is bracketed by the 2015–16 B2B reporting discontinuity (the same one we identified earlier in supplier-counts diagnostics). The pre-2015 segment isn't paired with a clean post-period, so we can't run a credible DiD.
- **The size-within-exposure Q4 drift in cut #7** is partly mechanical: the Q4 cohort starts near saturation (~95%) and any sectoral diversification mechanically pulls them down; it's also confounded with the same size-omega correlation we flagged in the within-NACE4d Tests 1 and 3.

The remaining candidate signal is cut #2's **Q3 high-exposure intensive decline** (~13% in 2011–12 to ~10% in 2022). We've recorded this pattern but **we don't have a strong reason to believe it's connected to ETS pricing**. The decline starts in 2011, which doesn't line up with any ETS regime change (Phase III begins in 2013; MSR decision in 2017; EUA price jump in 2018), and the magnitude is modest (~3pp over a decade). Most plausibly the trajectory reflects compositional churn in the Q3 cohort, a structural decline in specific high-shortage Belgian sectors over 2012–2022 (steel restructuring, refining contraction), or a denominator effect (Q3 buyers' total B2B spend growing in non-ETS sectors faster than in high-shortage sectors). We have not investigated mechanism — deliberately, because the timing offers no policy hook. Flagging for posterity, not pursuing.

### Formal DiD (added 2026-05-16, updated 2026-05-17)

Buyer-level DiD at the intensive margin: outcome = buyer's share of total B2B spend directed at NACE4d *n*; unit = buyer × NACE4d × year. Two events × three contrasts:

- **2005** (binary, ETS vs non-ETS): `treatment_n = 1{NACE4d n is ETS-treated}`, regression window 2002–22, pre = 2002–04, post = 2005–22, sample = ETS-treated ∪ non-ETS NACE4d the buyer bought from in 2002–04.
- **2017 — high-ω vs low-ω within ETS**: `treatment_n = 1{ω_n > median(ω among ETS)}` where `ω_n = sum_{f, t ∈ 2015-16} shortage_ft / sum total_cost_ft` aggregated to NACE4d. Regression window 2012–22 (the 2017-sym variant; tight 2013–22 and long 2002–22 in the diagnostic CSV). Sample = ETS-treated NACE4d with classifiable ω, bought from in 2015–16.
- **2017 — top-quartile ω vs non-ETS**: `treatment_n = 1{NACE4d in top 25% of ω among ETS} ; control = non-ETS NACE4d`. ETS NACE4d below the Q75 ω threshold are dropped from the sample so the contrast is sharp. Same regression window and cell-inclusion rule as the high-vs-low variant.

Headline FE spec: `α_jn + γ_{2,t}` (cell × NACE2d-year). Absorbs sector-aggregate (NACE2d-by-year) demand cycles; identification moves to within-NACE2d-year cross-NACE4d variation. The cell + year FE column was dropped from the paper output after we showed its 2017 pre-trend was a NACE2d-level demand cycle (collapses under NACE2d × year FE — see [phase4_across_nace4d_intensive_DiD_coefs.csv](output_rmd/tables/phase4_across_nace4d_intensive_DiD_coefs.csv) for the diagnostic comparison).

Script: [analysis/phase4_across_nace4d_intensive_DiD.R](analysis/phase4_across_nace4d_intensive_DiD.R). Paper table: [output_rmd/tables/phase4_across_nace4d_intensive_DiD_paper.tex](output_rmd/tables/phase4_across_nace4d_intensive_DiD_paper.tex). Event-study figure: [output_rmd/figures/phase4_across_nace4d_intensive_DiD.png](output_rmd/figures/phase4_across_nace4d_intensive_DiD.png).

| Variant | β (SE) | N |
|---|---|---|
| **2005** (ETS-treated vs non-ETS) | **+0.0031**\*** (0.0001) | 62.4M |
| **2017** (high-ω vs low-ω, within ETS) | +0.0000 (0.0002) | 4.3M |
| **2017** (top-quartile ω vs non-ETS) | **+0.0044**\*** (0.0001) | 34.4M |

SEs clustered on cell (buyer × NACE4d). Stars: ***p<0.001, **p<0.01, *p<0.05.

**Reading the table.** Statistical significance is mechanical at these sample sizes — focus on sign and magnitude.

- **2005 event** is *anti*-leakage. β = +0.0031, meaning buyers shifted ~0.3pp of total B2B spend **toward** ETS-treated NACE4d post-2005, with a clean flat pre-trend (event-study τ=-3 ≈ +0.0005, τ=-2 ≈ +0.0007 vs τ=-1 reference) and a monotonic rise to +0.0045 by τ=+5.
- **2017 high-ω vs low-ω within ETS** is null. β ≈ 0; event-study coefficients hug zero in ±0.002 range, pre and post.
- **2017 top-quartile ω vs non-ETS** is also *anti*-leakage. β = +0.0044: the most-exposed ETS-treated NACE4d (top 25% ω) gained ~0.4pp of buyer share against unregulated NACE4d post-2017.

**Two cleanest contrasts (ETS vs non-ETS in 2005; top-Q ω vs non-ETS in 2017) point the same way.** Both show modest *gains* for the most-exposed ETS sectors after policy events. The within-ETS-only contrast (high-ω vs low-ω, where both arms are ETS-treated) is null, which is consistent with there being no marginal substitution *within* the regulated bucket — the binding contrast is between regulated and unregulated NACE4d.

**Candidate stories for the anti-leakage signal.** Three readings, none mutually exclusive:

1. *Free-allocation buffering.* Phase I (2005–07) and Phase III continuation (2017+) gave the highest-emitting sectors generous free allowances, neutralizing the marginal-cost pass-through that would otherwise drive substitution.
2. *Inelastic upstream demand.* High-ω NACE4d (refining, cement, basic chemicals, basic metals, electricity) produce intermediate inputs with few network-level substitutes — buyers cannot easily reallocate away, regardless of price.
3. *Compositional drift.* High-ω sectors happen to be on a positive within-NACE2d trend in 2005–22 for non-policy reasons. NACE2d × year FE only absorbs *intra-NACE2d* drift; if the within-NACE2d cross-NACE4d composition is shifting toward high-ω sectors over the whole panel for structural reasons, the design picks that up.

We cannot adjudicate among these three from this regression alone. The within-NACE4d work already documents that **regulated firms maintain or expand market share** under ETS (story 1+2 mechanism); this across-NACE4d finding is the network-level mirror.

**On local-1 vs RMD.** An earlier local-1 (downsampled) run had β_{2005} = −0.0076 (apparent leakage). Full-sample RMD flips the sign to +0.0012 (cell+year FE) and +0.0031 (cell+NACE2d×year FE). Local-1 was too noisy for the 2005 sign; the RMD result is authoritative.

### Bottom line

Across-NACE4d reallocation is **inactive-to-anti-leakage at the intensive margin** on full-sample RMD data. The descriptive four-cuts table from May 2026 reads as inactive; the formal DiD shows that on the two cleanest contrasts — ETS vs non-ETS in 2005, top-Q ω vs non-ETS in 2017 — buyers' portfolios shifted *toward* the most-exposed ETS sectors post-treatment, by small but precisely-estimated margins (+0.3 and +0.4pp respectively). The within-ETS-only heterogeneity (high vs low ω) is null. Mechanism is not identified by this regression but is consistent with the within-NACE4d finding that regulated firms maintain market share under ETS.

### Caveats

- The 2015–16 B2B reporting discontinuity (the "Belgian VAT-reporting threshold change" or similar — origin not yet diagnosed; checking with NBB) contaminates any pre/post comparison that straddles it. Pre-2015 segments can be read cleanly; post-2016 segments require a separate baseline.
- The local-1 downsampled B2B tracks full-RMD on trends for the descriptive cuts but not on levels and not on the DiD coefficients themselves (the 2005 event sign actually flipped between local-1 and RMD; the 2017 event-study pre-trend was 6× larger on local-1 than on RMD). All DiD numbers in the table above are RMD.
- NACE2d × year FE absorbs *intra-NACE2d* sector cycles. Cross-NACE2d composition shifts (e.g., the chemicals NACE2d as a whole expanding relative to other NACE2d) are NOT absorbed. We have not run a full NACE3d × year FE robustness; on the 2017 sample with 68 NACE4d and ~17 top-Q ETS NACE4d, NACE3d × year FE may absorb too much identification.
- The 2005 spec compares ETS-treated NACE4d to non-ETS NACE4d in the full economy. The 2017 high-ω-vs-low-ω spec restricts to ETS-treated only. The 2017 top-Q-vs-non-ETS spec compares the most-exposed ETS NACE4d to non-ETS (drops mid-low ETS NACE4d). The three contrasts therefore answer related but distinct questions and should be read together rather than ranked.

---

*Generated by `analysis/phase0_decomposition.R`, `analysis/phase0_melitz_polanec.R`, `analysis/phase0_ets_share_shift.R`, `analysis/phase0_pairwise_decomposition.R`, `analysis/phase1a_output_share_by_exposure.R`, `analysis/phase4_sector_passthrough_classification.R`, `analysis/phase4_firm_output_reallocation.R`; `analysis/phase4_within_nace4d_reallocation_did.R`, `_topQ.R`, `_topQ_heterogeneity.R`, `_placebo.R`, `_plots.R`, `analysis/phase4_within_nace4d_extensive_DiD.R`, `analysis/phase4_within_nace4d_extensive_margin.R`; `analysis/phase4_across_nace4d_intensive_DiD.R`; and the `analysis/phase4_new_relationships_omega_rank*.R` family. May 2026.*
