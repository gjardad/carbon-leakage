# PRODCOM Pass-Through — Research Plan

*Written 2026-04-22 after S1–S11 established that annual sector-PPI data is underpowered for identifying ETS pass-through, even with exogenous CPShock instrumentation.*

## Why PRODCOM

Three things the NACE4d annual PPI panel cannot do, which PRODCOM product-firm-month data lets us do:

1. **Dose-response.** Firm-level continuous exposure (`shortage_{i,t} × EUA_t / cost_{i,t}`) varies *within* a product × month cell. Testing whether high-exposure firms post higher prices than low-exposure firms selling the same PC8 product in the same month is the dose-response test our sector-aggregate data cannot run. It is the test that would decisively distinguish "small pass-through" from "zero pass-through."

2. **Monthly event studies at BKR/Känzig frequency.** BKR identify pass-through from daily windows around 45 regulatory events. Monthly PRODCOM prices give us ~12× more time-series observations than annual PPI, and let us run event-study-style regressions with event-month indicators — closer to BKR/Känzig in spirit than annual regressions can be.

3. **Price rigidity (Fabra-Reguant Section III.C).** Frequency of price changes at firm × product × month lets us compute how much of the "incomplete pass-through" is absorbed by simply-not-changing-prices vs. absorbed in markups. Fabra-Reguant dismiss rigidity in Spanish electricity (80% daily bid-change frequency); for Belgian manufacturing the answer is open, and MMS 2024 did not measure it.

## What MMS 2024 did with PRODCOM (and why we can do more)

Martin, Muûls & Stoerk (2024, NBB WP 467) use PRODCOM unit prices matched to EUTL ETS status, regress Δ log(price) on a **binary** ETS-dummy with annual firm averages. They find +0.14 (SE 0.15), insignificant.

Three degrees of freedom we can exploit that they did not:
- **Continuous firm-level exposure** (`shortage × EUA / cost`) rather than a 0/1 ETS indicator. This recovers the dose-response.
- **Monthly frequency** rather than annual firm averages. This 12×'s the time dimension.
- **Product × month FE** rather than sector × year FE. Within-product-month variation identifies off much cleaner cross-sectional firm heterogeneity.

## Data

All inputs already produced by the existing Stata pipeline at [analysis/prodcom_passthrough_stata/](analysis/prodcom_passthrough_stata/):

| File | Content | Frequency | Scope |
|---|---|---|---|
| `firm_year_belgian_euets.dta` | firm-year exposure (shortage, EUA cost, total cost) | annual | ~281 ETS firms |
| `prodcom_analysis_panel.dta` | firm × PC8 × year × month value/quantity | **monthly** | all PRODCOM respondents |
| `deflator_nace4d_2005base.dta` | NACE4d PPI | annual (monthly available from source) | 139 sectors |
| `eua_prices_annual.dta` | annual EUA | annual | 2005–2023 |

For BKR-style event-study specs we would additionally need:
- Daily EUA series (already have, from investing.com)
- BKR event list (already extracted to [articles/bkr_event_list.csv](articles/bkr_event_list.csv))
- Derived monthly CPShock (already have, from Känzig xlsx for 2005–2019; can extend to 2020–2024 by aggregating our Phase IV daily surprises to monthly)

**No new data acquisition required.** Everything needed is either already in the pipeline or already downloaded.

## Unit-price construction

For each firm × PC8 × month: `unit_price = value_EUR / quantity_physical_unit`. Known hazards:
- Quantity units vary by PC8 code (tonnes, litres, number, etc.). Unit prices are only comparable within PC8.
- Very low quantities produce outlier unit prices. Winsorize at firm × PC8 1st/99th pct, or drop observations with quantity below a threshold.
- Missing values / reporting gaps: some firms report intermittently. Spec needs to be robust to unbalanced panels (fixest handles this).

These are all standard PRODCOM issues — MMS 2024's appendix is the reference for how to handle them.

## Specifications

Four specs, in priority order. All run on the monthly firm × PC8 × month panel with unit prices as LHS.

### Spec 1 (priority 1) — Within-product dose-response, annual

```
log(unit_price)_{i,p,y} = β · exposure_{i,y} + α_{p,y} + α_i + ε
```
- `i` = firm, `p` = PC8 product, `y` = year
- `exposure_{i,y}` = firm-level shortage-cost-share (continuous, from `firm_year_belgian_euets.dta`)
- FE: product × year, firm. The PC8 × year FE controls for every product-specific shock in every year.
- SE clustered at firm (or firm × PC8)
- **Identification:** within PC8 × year, do firms with higher carbon-cost share post higher unit prices?

This is the spec MMS 2024 should have run and did not. It is the single most valuable regression in the whole PRODCOM workstream. If β is significantly positive and dose-response is monotone, pass-through is demonstrated.

### Spec 2 (priority 2) — Monthly first-difference event study

```
Δ log(unit_price)_{i,p,m} = β · (CPShock_m × intensity_base_i) + α_{p,m} + α_i + ε
```
- `m` = calendar month
- `CPShock_m` = monthly sum of daily surprises (Känzig 2005–2019 monthly sheet, extended 2020–2024 from our Phase IV daily series)
- `intensity_base_i` = firm-level mean of exposure over a pre-period (e.g., 2013–2016)
- FE: PC8 × month, firm
- **Identification:** in months with positive CPShock, do high-intensity firms post larger price changes?

Twelve times the time dimension of the annual spec; event-study-style using Känzig's own instrument. This is the frequency-match to BKR.

### Spec 3 (priority 3) — Price rigidity (Fabra-Reguant III.C analogue)

```
P(price change at i,p,m) = F(γ · exposure_{i,y} + α_{p,m} + α_i + ε)
```
- Binary LHS: did firm `i` change its reported unit price for product `p` between month `m−1` and `m`? (tolerance for small numerical changes)
- Plus conditional on changing, what is the size?

Measures what fraction of pass-through incompleteness is rigidity vs markup absorption. Fabra-Reguant found ~80% daily bid changes; manufacturing firms presumably have much lower frequency. If rigidity is very high, that *alone* explains weak annual pass-through and we don't need a markup story.

### Spec 4 (priority 4) — Cement / homogeneous-product subset

Re-run Spec 1 restricted to PC8 codes within NACE 23 (cement, glass, bulk ceramics). This is our cleanest-setting test: homogeneous products with inelastic local demand should give the largest pass-through if any mechanism is operating. In the sector-aggregate specs, NACE 23 at 4-digit gave point estimate +0.11 (SE 1.34) — null but underpowered. PRODCOM within-product variation should resolve it.

## Execution — two-phase plan

### Phase A (local, this machine)

The Stata pipeline already runs locally on the mock `prod.dta` for structure testing. Before touching RMD, build and sanity-check the specs on the mock file:

1. Port the `firm_year_belgian_euets` + `prodcom_analysis_panel` joins into an R or Stata regression script (06_regressions.do / phase3_prodcom_regressions.R).
2. Implement Spec 1 (within-product dose-response, annual). Confirm the spec compiles, FE structure loads, sample size is non-trivial. Coefficient magnitude on mock data is not meaningful but the code must run end-to-end.
3. Run against [verify_against_R.R](analysis/prodcom_passthrough_stata/verify_against_R.R)-style sanity checks — row counts, non-NA counts, clustered SE convergence.

### Phase B (RMD, real data)

1. Deploy the regression script to RMD.
2. Run Spec 1. Report β, SE, dose-response plot (log price on exposure decile within PC8 × year).
3. If Spec 1 is promising (β > 0 significant or dose-response monotone): run Specs 2, 3, 4.
4. If Spec 1 is null (β ≈ 0 with tight SE): that *is* the answer. Write it up as "firm-level dose-response is null — sector-aggregate null is not a power issue."

## What "promising" looks like and what it would change

Benchmarks for Spec 1 β:

| β on firm exposure | Interpretation |
|---|---|
| ~+0.5 to +1.0 significant | Near-full pass-through at firm level; disagrees with our sector null; selection story confirmed. Publish separately. |
| ~+0.1 to +0.3 significant | Partial pass-through; matches BKR electricity (0.2–0.4) and Känzig HICP (~0.2); consistent with sector null reflecting aggregation. **Most likely outcome if there is pass-through.** |
| ~0 with SE < 0.1 | Firm-level null with tight precision; sector-aggregate null is not an aggregation artefact — pass-through is genuinely absent. Publishes as a negative result alongside MMS. |
| ~0 with SE > 0.2 | Still underpowered. PRODCOM coverage / unit-price noise is the bottleneck, not the regression design. |

## Deferred / out of scope

- **Network / upstream exposure through PRODCOM.** Mapping firm-level input costs onto suppliers' ETS exposure via B2B is a separate project — the full B2B panel is on RMD only.
- **Pass-through into input costs** (vs output prices). PRODCOM is on outputs. Input-side analysis would need customs/B2B data.
- **Cross-country comparison.** Belgian PRODCOM only. A comparison with German, French, Italian PRODCOM would be a new paper.

## Dependencies on other workstreams

- Extending the Phase IV CPShock series to monthly requires ~30 min of work (we already have the daily surprises; just aggregate to monthly).
- Extending the firm-year exposure panel from 2022 to 2023–2024 would increase Spec-1 sample. Depends on when NBB releases annual accounts 2023–2024.
