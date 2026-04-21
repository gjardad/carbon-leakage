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

*Generated by `analysis/phase0_decomposition.R`, `analysis/phase0_melitz_polanec.R`, `analysis/phase0_ets_share_shift.R`, and `analysis/phase1a_output_share_by_exposure.R`. April 2026.*
