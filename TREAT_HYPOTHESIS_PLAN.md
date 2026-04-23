# Plan — Testing the "Carbon Price Threat" Hypothesis

*Do firms invest in cleaner technology in response to the threat of future carbon prices, rather than (only) the realized carbon price?*

---

## 1. Reframe the hypothesis in identification language

The hypothesis has a clean econometric translation: **firm investment responds to news about future carbon policy, not only to the realized carbon price level**. In impulse-response language:

- **Threat channel:** coefficient on `CPShock_t` (news about future policy, holding current EUA fixed) is non-zero and positive for abatement outcomes.
- **Realized-price channel:** coefficient on innovations to `EUA_t` orthogonal to `CPShock` captures pure price-level surprises.

Känzig's CPShock series is almost tailor-made for this. `CPShock_t` by construction captures *news* that moves EUA futures *and* expectations about future tightening — that's the threat. What's missing from the current project is the *outcome*: existing work uses PPI (pass-through), but the threat hypothesis is about **investment and efficiency**, not prices.

**Core test:** same S12 panel-LP machinery, new LHS: capex intensity, energy intensity, and (if available) verified emissions per unit output.

## 2. Outcomes — what "investment in cleaner technology" looks like in our data

| Outcome | Source | Construction | Strength |
|---|---|---|---|
| Tangible-asset capex / revenue | Annual Accounts | Δ in fixed-asset stock or flow proxy | Direct measure of physical investment |
| Energy-cost share | Annual Accounts | energy expenditure / total cost | Falling share ≈ abatement paying off |
| Emissions intensity | EUTL verified + PRODCOM volume | CO2 / physical output | Cleanest, but only for ETS firms, and PRODCOM is co-author-only |
| Input-mix shift via B2B | B2B network | share of inputs sourced from green vs brown suppliers | Novel but requires supplier-classification |
| Green-tech imports | Customs | HS codes for heat pumps, insulation, efficient machinery | Hard because import = intermediate consumption at BE, not firm-level |

**Recommended primary outcome:** log(capex + energy-efficient assets) / revenue, with energy-cost share as the secondary. Emissions intensity is the cleanest test but narrows the sample to EUTL-matched firms.

## 3. Three identification strategies, ordered by cleanness

### Strategy A — Direct S12 analog on investment (cleanest, reuses validated pipeline)

```
Δ log(capex_{i,t+h}) = γ_h · (CPShock_t × intensity_base_i) + α_i + δ_t + ε
```

Sector or firm FE plus year-month FE → identification from **within-period cross-firm variation in exposure**. `intensity_base_i` is 2013–2016 shortage intensity (already built for S12).

**Threat channel test:** γ_h > 0 for h in 6–36 months says higher-exposure firms invest more after carbon-policy news, even before the price arrives. This is the primary threat test.

**Placebo to validate:** run the same spec on non-ETS firms matched by size × sector × region. γ_h should be null for them.

### Strategy B — Horse race: threat vs realized-price channel

Split the EUA price into "news component" (cumulative CPShock) and "residual":
```
EUA_t = a + b · cum_CPShock_t + u_t
```
Then:
```
Δ log(capex_{i,t+h}) = γ₁ · (CPShock_t × intensity_base_i)
                     + γ₂ · (û_t       × intensity_base_i)
                     + α_i + δ_t + ε
```

Hypothesis: **γ₁ >> γ₂**, possibly γ₂ ≈ 0. If γ₂ dominates, firms respond to realized price only. This is the *direct* formal test.

### Strategy C — Sectoral allocation-rule changes from Känzig's event catalog (the sharpest cross-sectional test)

Känzig's 114-event list plus BKR's extension catalog regulatory events, but not all of them are sectorally differentiated. The ones that *are* differentiate treatment by NACE sector:

| Event window | Sectorally differentiated policy news | Treated sectors |
|---|---|---|
| 2008 (Phase II start) | Power sector starts facing tighter cap; no auctioning yet | NACE 35.11 |
| 2011-01-14 | Commission benchmark decision for Phase III | All ETS sectors, differentiated by benchmark |
| 2013-01-01 | Phase III: power sector fully auctioned | NACE 35.11 (big treatment) |
| 2014-05-05 | Carbon-leakage-list decision (2014/746/EU) — sectors on list keep 100% free allocation, off-list sectors phase down to 30% by 2020 | Dozens of NACE4d sectors moved on/off list |
| 2015-10-06 | MSR adoption | All, but pollutant-heavy hit more |
| 2019-02-15 | Revised carbon-leakage list (2019/708/EU) for Phase IV — narrower scope, tighter benchmarks | Sectors leaving the list: strong effective-price hike even though EUA_t unchanged |
| 2023 (Fit-for-55 enactment) | CBAM + free-allocation phase-out for CBAM sectors, scope expansion to maritime | Cement, steel, aluminum, fertilizer, electricity, hydrogen |

The **2014 and 2019 carbon-leakage-list revisions** are the best natural experiments: they are discrete, sector-specific, explicitly about *future* allocation (not current prices), and mapped to NACE4d. Sectors removed from the list face an announced phase-down of free allocation — pure threat, no current-period price change.

```
Δ log(capex_{i,t}) = Σ_h β_h · 1{t = event + h} × lost_CL_status_s(i) + α_i + δ_t + ε
```

Event study around 2014-05 and 2019-02 announcements. Pre-trends from h = -3 to -1; post from h = 0 to +5. The `lost_CL_status` dummy comes from comparing annexes of the 2009 baseline CL list, the 2014 revision, and the 2019 revision.

The **deliverable** should include a sector crosswalk table: NACE4d × {CL-status history 2009, 2014, 2019} → treatment cohort.

## 4. Concrete task list, in dependency order

1. **Build the NACE × CL-status panel.** Parse the annexes of Commission Decisions 2009/161/EC, 2014/746/EU, and 2019/708/EU into a sector-year dataset of free-allocation status. (Input: the Decisions themselves, public. Output: `data/processed/cl_status_by_nace4d.csv`.) ~1 day.
2. **Add investment/capex measures to the firm panel.** Pull tangible-asset lines from Annual Accounts; build log(capex/revenue) and energy-cost share. Use the already-built `intensity_base` from S12. ~1 day.
3. **Strategy A on firm-level investment** (direct S12 analog). Reuse `phase3_ppi_passthrough_monthly.R` as template, swap LHS. ~1 day.
4. **Strategy B horse race.** Decompose `EUA_t` into news + residual, rerun. ~half day.
5. **Strategy C event studies** on 2014 and 2019 CL-list revisions, firm-level, with non-ETS placebos. ~2 days.
6. **Pre-trend + placebo robustness.** Run on non-ETS firms matched on size × sector × region; check pre-event parallel trends on investment.

## 5. Main risks / knowledge gaps

- **Capex is lumpy and noisy at firm-year level.** May need to aggregate to 3-year windows or use stocks rather than flows. This is an empirical surprise I'd want to diagnose with variance decomposition before picking the final LHS.
- **Identifying which Känzig events are "future-policy" vs "current-price".** Every ETS announcement moves both — the news is about the future, but EUA_t moves today. The horse race in Strategy B is the honest way to disentangle; the event-study carbon-leakage-list design in Strategy C is cleaner because current EUA_t doesn't change much on those dates.
- **Känzig's 114-event table is dated by day, not by sector-specific attribute.** The CL-list event dates are known; sector-differentiation has to come from the Commission Decisions themselves, not from Känzig's catalog. The catalog helps with *time-series* identification, the Decisions with *cross-sectional*.
- **2014 CL-list event was largely expected.** Announcements were phased through 2013. Use the *earliest* credible announcement date (a Commission proposal, not the final Decision) to avoid a "the market already knew" attenuation.
- **Pre-2005 counterfactual is thin.** Can't test "firms invested in 2003 in anticipation of 2005" with much power — annual accounts coverage and exposure measures both get weaker.

## 6. What this would deliver

If Strategy A gives γ_h > 0 AND Strategy B gives γ₁ >> γ₂ AND Strategy C gives clean positive capex response to CL-list removal with non-ETS placebo null → strong support for the threat hypothesis. If Strategy B gives γ₂ dominating and Strategy C is null, the hypothesis fails the Belgian test.

---

**Tradeoff.** This plan reuses the S12 pipeline heavily, which is attractive for speed but inherits the Känzig VAR structural assumption (see caveats in `PASSTHROUGH_CPSHOCK.md`). Strategy C (CL-list event studies) is the one part that avoids that dependency and would stand on its own. If forced to pick one, start with **Strategy C** — it's the clean cross-sectional answer and doesn't require more Känzig machinery.

---

*Drafted 2026-04-22. Deferred — no implementation yet.*
