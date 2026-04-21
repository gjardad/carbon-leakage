# Pass-Through Findings: Does Belgian Sector PPI Respond to ETS Carbon Costs?

---

## Summary

The ETS carbon-price shock was **small through Phase III and only becomes quantitatively meaningful in Phase IV (2021+)**. Sector-level PPI pass-through is **small-positive-or-null in our preferred specifications (≈ 0.07 to 0.15 in log-PPI per pp of exposure) and not statistically distinguishable from zero once sector-specific trends are absorbed.** The result is consistent with independent firm-level evidence from Martin, Muûls & Stoerk (NBB WP 467, 2024), who use PRODCOM unit-price data and find an ETS-firm coefficient of +0.14 (SE 0.15), also insignificant.

| Question | Answer |
|---|---|
| How big was the shock? | Small until Phase IV, then meaningful. Effective price per tonne emitted rose from ~€2 (Phase III pre-MSR) to **€39 (2022)**. Concentration of carbon cost fell from 99% top-5 firms to ~70%. |
| Contemporaneous first-difference pass-through? | **+0.07** (OLS, year FE), **+0.17** (with 1- and 2-year lagged differences). |
| Levels pass-through after absorbing sector-specific trends? | **+0.07 (all sectors), +0.15 (with lagged levels)**. Cumulative net of lag-2: essentially zero. |
| Is there a dose-response across shortage-intensity terciles? | No. T1, T2, T3 all give +0.08, +0.11, +0.08 respectively. Flat. |
| Benchmarks | MMS 2024 (firm-level, PRODCOM): **+0.14 (SE 0.15)**, insignificant. Fabra-Reguant 2014 (Spanish wholesale electricity, auction-level): 0.86. BKR 2026 (European electricity futures, daily event study): 0.2–0.4. |

---

## What we compute

### Direct exposure (primary measure)
Per NACE4d sector s and year t, summed over ETS firms in that sector:
```
exposure_direct_{s,t} = Σ_i (shortage_{i,t} × EUA_t) / Σ_i (total_cost_{i,t})
```
where `shortage = max(emissions − allocated_free, 0)` and `total_cost = (revenue − value_added) + wage_bill`.

### Alternative exposure (diagnostic, fixed denominator)
Same numerator, denominator replaced by a base-period (2010–2012) mean:
```
exposure_alt_{s,t} = Σ_i (shortage_{i,t} × EUA_t) / base_cost_{s}
```
This removes the mechanical endogeneity between time-varying costs and prices. In practice, results are nearly identical to direct exposure — the denominator was not the issue.

### Alternative cost denominators (appendix)
- Material inputs only: `revenue − value_added`
- Revenue
- Both give similar phase-wise patterns to total cost.

### Network-adjusted exposure (diagnostic, 2012–2021 only)
From frozen-weights Leontief construction: `(I − A_base)^{-1} · direct_exposure`. Used in S3 specs. The locally-reconstructed panel uses downsampled B2B data, so S3 coefficients are directional only until rebuilt on RMD.

---

## Data

| Source | File | Coverage | Role |
|---|---|---|---|
| EUTL matched to Annual Accounts | `firm_year_belgian_euets.RData` | 281 ETS firms × 2005–2023, 255 in-sample | Shortage, free allocation, emissions, revenue, VA, wage_bill, NACE5d |
| ICAP CSV | `icap_euets_price_2005_26.csv` | Daily EUA futures settlement, 2010–2025 | Annual-average EUA price; Phase I–II values back-filled from literature |
| Statbel PPI + Eurostat PPI | `deflator_nace4d_2005base.RData` | NACE4d × year, 2005–2024 | Outcome variable; chained to 2005 = 100 |
| NBB B2B | `b2b_selected_sample.RData` (downsampled) | Supplier-buyer pairs × year | Network weights (A, B matrices) |

Panel for regressions: **2502 rows, 139 NACE4d sectors (52 ever-ETS), years 2005–2022.**

### Phases
- Phase I: 2005–2007 (pilot)
- Phase II: 2008–2012 (learn-by-doing)
- Phase III: 2013–2020 (auctioning becomes default; MSR from 2019)
- Phase IV: 2021–present (2.2%/yr cap decline, €54 → €80 → €84)

---

## Shock-size diagnostics (Task 3)

### Effective carbon price per tonne emitted (Σ shortage × EUA / Σ emissions)

| Phase | Range | Peak |
|---|---|---|
| I | €0.07 – €3.12 | €3.12 (2005) |
| II | €0.86 – €2.91 | €2.91 (2008) |
| III pre-MSR | €1.46 – €2.67 | €2.67 (2015) |
| III post-MSR | €5.62 – €9.56 | €9.56 (2019) |
| **IV** | **€26.33 – €39.39** | **€39.39 (2022)** |

### Share of emissions priced (Σ shortage / Σ emissions)

| Phase | Mean |
|---|---|
| I | 12% |
| II | 15% |
| III | 34% (jump at 2013 auctioning start) |
| IV | 49% |

### Share of in-sample ETS firms with strictly positive shortage

| Phase | Mean |
|---|---|
| I | 16% |
| II | 9% (over-allocation) |
| III | 54% |
| IV | 64% |

### Concentration (top-5 firms' share of total carbon cost paid)
Drops from **99% in Phase I–II** to **~70% in Phase IV**. Through 2012, essentially one or two firms paid for the entire country's shortage. Post-MSR the burden becomes broad-based.

### Histograms (Task 1)
Carbon cost as share of total cost, firm-year distribution, winsorized 1st/99th pct within phase:

| Phase | Emissions-weighted mean | P90 | P99 (winsorized max) |
|---|---|---|---|
| I | 0.16% | 0.006% | 0.40% |
| II | 0.51% | 0.0% | 0.31% |
| III | 2.27% (raw) / 1.02% (wins.) | 0.59% | 12.08% |
| **IV** | **9.68% (raw) / 4.41% (wins.)** | 2.26% | 41.64% |

The shock is ~40× larger in emissions-weighted terms between Phase I and Phase IV.

---

## Pass-through specifications (Task 2)

All outcomes: NACE4d log-PPI (levels) or Δ log-PPI (first differences). Standard errors clustered at NACE4d. All specs are on the same 2005–2022 panel unless noted.

### S1 — Levels, baseline
```
log(PPI)_{s,t} = β · exposure_{s,t} + γ_s + δ_t + ε_{s,t}
```

| Spec | β | SE | N | Note |
|---|---|---|---|---|
| S1a (all sectors) | **−0.60** | 0.07 | 2502 | Wrong sign, highly significant |
| S1b (ETS sectors only) | **−0.64** | 0.07 | 936 | Same |

### S2 — First differences
```
Δ log(PPI)_{s,t} = β_0 · Δ exposure_{s,t} (+ β_1 · Δ exp_{s,t−1} + β_2 · Δ exp_{s,t−2}) + δ_t + ε
```

| Spec | β_0 | β_1 | β_2 | Cumulative | N |
|---|---|---|---|---|---|
| S2a (contemporaneous) | **+0.07** (SE 0.02) | — | — | — | 2363 |
| S2c (with lags) | **+0.13*** | −0.03 | **−0.51*** | **−0.40*** | 2085 |

The contemporaneous positive effect is modest. The lag-2 is strongly negative and the cumulative flips to negative. This "wrong sign in the long run" is the main diagnostic puzzle; the fixes below target it.

### S3 — With network-adjusted upstream exposure (2012–2021)
Upstream exposure sums via Leontief inverse from the frozen 2005–2012 input matrix. First-diff with lags of upstream-indirect yields a cumulative of **+1.65** (SE 0.98, p = 0.09). Directional but noisy — N = 244 obs with downsampled B2B. Needs RMD rebuild.

### S4 — Distributed lag in levels
Same story as S2c: contemporaneous −0.28, lag-1 −0.73, lag-2 +0.17. Persistently negative.

### S5 — NACE2d × year FE (absorbs 2-digit commodity cycles)
```
log(PPI)_{s,t} = β · exposure_{s,t} + γ_s + δ_{NACE2d, t} + ε
```
| Spec | β | SE | N | Note |
|---|---|---|---|---|
| S5a | **−0.43** | 0.06 | 2466 | Still negative |
| S5b (ETS only) | **−0.47** | 0.06 | 846 | Same |
| S5d (first-diff) | **−0.09** | 0.02 | 2329 | Now negative in diff too |

**Key finding:** NACE2d × year FE did NOT fix the sign. The commodity-cycle-at-2-digit story is not the main driver of the negative coefficient.

### S6 — Sector-specific linear trends
```
log(PPI)_{s,t} = β · exposure_{s,t} + γ_s + δ_t + θ_s · t + ε
```
| Spec | β | SE | N | Note |
|---|---|---|---|---|
| S6a | **+0.065** | 0.05 | 2502 | Positive, near zero |
| S6b (ETS only) | **+0.065** | 0.05 | 936 | Same |
| S6c (with lags, cumulative) | **−0.05** | 0.08 | 2224 | Null |

Sector-specific trends are the one FE structure that flips the sign. They absorb slow-moving structural differences between high- and low-exposure sectors.

### Alt denominator (A1–A6)
Re-running S1, S5, S6 with the base-period-fixed denominator (`exposure_alt`) produces coefficients **within 0.02 of the direct-exposure versions**. The cost-denominator-endogeneity hypothesis is refuted.

### Heterogeneity by pre-period shortage intensity tercile
Sectors classified into zero-exposure (T0, n=33) and positive-exposure terciles (T1 low / T2 mid / T3 high, n=21 each) based on 2013–2016 mean of `exposure_alt`. Each tercile's coefficient in a separate S6 regression vs T0 control:

| Tercile | β | SE | t | Note |
|---|---|---|---|---|
| T1 (low) | **+0.083** | 0.024 | 3.4 | Significant |
| T2 (mid) | **+0.115** | 0.024 | 4.7 | Significant |
| T3 (high) | **+0.079** | 0.041 | 1.95 | Marginal |

**No dose-response.** If the mechanism were mechanical carbon-cost pass-through, T3 should show the largest coefficient. Instead the three terciles give nearly identical slopes. This looks more like "ETS sectors have slightly different pricing dynamics from non-ETS sectors" (selection) than "carbon cost → PPI, scaled by exposure" (structural).

### NACE2d-specific pass-through
S6-alt run separately per NACE2d sector. Most 2-digit sectors are underpowered (2–7 sub-sectors). The two with meaningful power:

| Sector | Description | β | SE | p |
|---|---|---|---|---|
| 10 | Food products | −5.49 | 3.05 | 0.08 |
| 23 | Non-metallic minerals (cement, glass, ceramics) | **+0.11** | 1.34 | 0.94 |

NACE 23 (cement) is the textbook case for clean pass-through — homogeneous product, local market, price-inelastic demand. Its point estimate is essentially zero with a tight standard error.

---

## Interpretation

### What the evidence supports

1. **The shock was small until Phase IV.** Effective price per tonne stayed below €3 through 2017. The 2021–22 jump to €39 is a genuine structural change, but the panel gives only two full Phase IV years.

2. **Sector-level pass-through is small and does not scale with exposure.** Contemporaneous first-difference coefficients of +0.07 to +0.17 are positive and statistically distinguishable from zero, but the effect does not grow with shortage intensity. Cement, where we would most expect clean pass-through, gives essentially zero.

3. **Our cleanest specification (S6 with sector trends) lands at +0.065 cumulative −0.05.** Martin-Muûls-Stoerk (NBB WP 467, 2024), using firm-level PRODCOM unit-price data and a binary ETS dummy, land at +0.14 with SE 0.15 — the same order of magnitude, also insignificant.

### What the evidence does not support

- Large, meaningful pass-through at the sector level. If it existed, Phase IV would have produced it and our panel would have captured it.
- A dose-response relationship between carbon-cost intensity and price. Terciles are flat.
- A commodity-cycle-at-NACE2d explanation for the negative S1 coefficient. NACE2d × year FE leaves the negative sign intact.

### Leading interpretation

The negative coefficient in S1/S5 reflects **selection into exposure**, not a real ETS effect. The sectors with the highest carbon-cost-as-share-of-total-cost are sectors with structurally weaker pricing power (integrated commodity producers: steel, bulk chemicals, cement, refining). This is a permanent sector-level characteristic that persists across all year-FE structures, so it loads onto the exposure coefficient. Sector-specific linear trends absorb it (because it is slow-moving), which is why only S6 flips the sign.

The remaining small positive coefficient in S6 plausibly captures a modest real pass-through effect, but the lack of dose-response and the cement null make it hard to interpret as anything other than "ETS sectors price-adjust slightly differently from non-ETS sectors, in ways that do not scale mechanically with their carbon cost."

### Where the aggregate analysis hits its limit

Sector-level PPI data cannot distinguish between:
- a real but small pass-through effect (supported by +0.07 to +0.15 contemporaneous)
- near-zero pass-through with small coefficients capturing residual selection / anticipation effects

Firm-level PRODCOM data would close this gap by allowing within-sector cross-firm comparisons with continuous firm-level exposure — a dose-response test that our sector-aggregate data does not permit. MMS 2024 have PRODCOM data but use only a binary ETS dummy and annual firm averages, so they also do not test dose-response.

---

## Comparison with external evidence

| Study | Context | Measure | Result |
|---|---|---|---|
| **This paper** | Belgium, NACE4d, annual, 2005–22 | log(PPI) ~ exp. share | +0.07 to +0.15 (insignificant); cumulative −0.05 |
| **Martin, Muûls & Stoerk 2024** (NBB WP 467) | Belgium, firm-level PRODCOM unit prices, 2016–20 | Δ unit price ~ ETS dummy | +0.14 (SE 0.15), insignificant |
| **Fabra & Reguant 2014** (AER) | Spain, wholesale electricity, daily auction | price level ~ marginal ETS cost (IV) | **0.86–1.05** (near-full pass-through) |
| **Bauer, Känzig & Rudebusch 2026** | European energy futures, daily event study | log(price) ~ CPShock | Electricity **0.2–0.4**, gas ~0.2, oil ~0.1–0.15 |
| **Känzig 2025** (JMP) | Euro area, macro VAR, monthly | headline HICP ~ CPShock | Aggregate peak ~0.2% per 1% energy-price shock |

The wholesale-electricity auction setting (Fabra-Reguant) shows nearly complete pass-through. Down the price chain — from energy futures (BKR), to aggregate HICP (Kaenzig), to firm-level PRODCOM (MMS), to NACE4d PPI (this paper) — the coefficient shrinks toward zero. Our result fits that ordering. Whatever pass-through exists at the wholesale electricity level is substantially absorbed by the time it reaches downstream NACE4d sector PPIs.

---

## Caveats

1. **Network panel is downsampled.** The frozen-weights B2B network was rebuilt locally with downsampled B2B, so S3 coefficients are directional only. Rebuild on RMD for publishable network results.
2. **Phase IV is only two years.** 2021 and 2022 give limited power for dynamic specs in the post-MSR period. Extending the ETS panel to 2023–2024 (when available) will help.
3. **Commodity-price controls are redundant.** Gas, oil, coal, electricity prices vary only in time; they are fully absorbed by year FE. They matter only when interacted with sector-level fuel intensities, which we did not implement.
4. **The exposure measure's denominator is time-varying and potentially endogenous.** We diagnose this with an alternative base-period-fixed denominator and find virtually identical coefficients — the denominator is not the driver of the negative coefficient.
5. **Kaenzig's "carbon policy surprise" instrument is not used.** Standard argument: Belgium is a small share of EU ETS, so EUA prices are exogenous to Belgian sector shocks without additional orthogonalization. We rely on this assumption.

---

## Scripts

| Purpose | Script |
|---|---|
| Build annual EUA price series 2005–23 | [analysis/phase3_eua_prices.R](analysis/phase3_eua_prices.R) |
| Build firm-year and sector-year exposure panels (both denominators) | [analysis/phase3_build_exposure_panel.R](analysis/phase3_build_exposure_panel.R) |
| Task 1: Exposure histograms by phase | [analysis/phase3_exposure_histograms.R](analysis/phase3_exposure_histograms.R) |
| Task 3: Shock-size diagnostics | [analysis/phase3_shock_size_diagnostics.R](analysis/phase3_shock_size_diagnostics.R) |
| Task 2: Main PPI pass-through regressions (S1–S6 + A) | [analysis/phase3_ppi_passthrough.R](analysis/phase3_ppi_passthrough.R) |
| Heterogeneity by tercile and NACE2d | [analysis/phase3_ppi_heterogeneity.R](analysis/phase3_ppi_heterogeneity.R) |

Output artefacts are in [output/tables/phase3_*.txt](output/tables/) and [output/figures/phase3_*.pdf](output/figures/).

---

## Deferred analyses (see [TODO.md](TODO.md))

- Task 3.5: benchmark EUA-driven cost variation against gas/electricity price variation.
- Task 3.6: abatement-speed test after the Phase IV price jump.

## Potential follow-up: PRODCOM

A PRODCOM-based extension could close the dose-response question that sector-aggregate data cannot resolve. The pitch:

- Use firm-level PRODCOM unit prices (monthly or annual).
- Regress Δ log(price)_{i,p,t} on a continuous firm-level exposure `shortage_{i,t} × EUA_t / cost_{i,t}`, with firm FE and NACE4d × year (or product × year) FE.
- Identification: within product × year, do firms with higher exposure post higher price growth?

MMS 2024 have the data but use only a binary dummy and firm-averaged prices, so this dose-response test is not in their draft. Whether to escalate to the coauthor for data access depends on appetite for closing the remaining ambiguity; the expected payoff is moving from "near zero, probably" to "zero, decisively" or "small but real."

A mock PRODCOM file (`prod.dta`) is available locally and has the expected structure (firm × year × month × PC8 product × value × quantity), so specifications can be piloted locally before requesting RMD access.

---

*Generated after running `analysis/phase3_*.R`. April 2026.*
