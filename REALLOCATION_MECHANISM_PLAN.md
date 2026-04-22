# Plan — Distinguishing Within-Sector Reallocation (H1) vs Inelastic-Demand Shield (H2)

## Context

[PASSTHROUGH_CPSHOCK.md](PASSTHROUGH_CPSHOCK.md) establishes positive sector-level PPI pass-through (S12 monthly panel-LP: **+4.08 at h=12 months, t=6.39**, conditional on Känzig's VAR). [REALLOCATION_FINDINGS.md](REALLOCATION_FINDINGS.md) establishes that within-sector reallocation of output across ETS firms is approximately zero on average, and uncorrelated with sector carbon cost exposure.

These two facts leave open:
- **H1** — high-exposure firms *do* lose output to low-exposure firms, but only inside the sectors that are passing costs through. The aggregate null hides a pass-through-conditional pattern.
- **H2** — sectors that pass through most are precisely those with inelastic downstream demand; high-emission firms there do not lose output because nobody loses output.

This plan operationalizes two within-sector tests that discriminate these hypotheses:
- **Angle 1** — firm-level output response × firm emissions intensity × sector pass-through.
- **Angle 4** — B2B buyer-level supplier switching × seller emissions intensity × sector pass-through.

A third section documents where PRODCOM product-firm-month data would add value beyond what firm-year + B2B can deliver — documentation only for future reference.

---

## Data inventory (already produced)

| File | Frequency | Content | Script |
|---|---|---|---|
| [NBB_data/processed/firm_year_belgian_euets.RData](NBB_data/processed/) | annual | firm × year: emissions, free allocation, revenue, NACE, wage bill, costs | existing |
| [NBB_data/processed/b2b_selected_sample.RData](NBB_data/processed/) | annual | supplier VAT × buyer VAT × year, corr_sales | existing |
| [data/processed/phase3_sector_exposure.RData](data/processed/) | annual | NACE4d × year exposure, `intensity_base` (2013–16 mean) | [phase3_build_exposure_panel.R](analysis/phase3_build_exposure_panel.R) |
| [NBB_data/processed/deflator_nace4d_2005base_monthly.RData](NBB_data/processed/) | monthly | NACE4d PPI 2005m1–2024m6 | [phase0_build_deflator_monthly.R](analysis/phase0_build_deflator_monthly.R) |
| [NBB_data/raw/carbonPolicyShocks.xlsx](NBB_data/raw/) | monthly | Känzig `Surprise` / `Shock` 2005–2019 | — |
| [data/processed/frozen_weights_matrices.RData](data/processed/) | base period | A (upstream) and B (downstream) matrices, avg costs | [network_exposure_regs_1_build_frozen_weights.R](analysis/network_exposure_regs_1_build_frozen_weights.R) |

**Main sample:** 2005–2019 Shock column (clean identification). Phase-IV extension is deferred until the log-return surprise is residualized (TODO.md; also blocks S12b).

**Firm-level treatment variables:**
- `firm_emint_i` = firm's own pre-MSR average emissions intensity (emissions / real revenue, 2013–16 mean). Mirrors the `shortage_intensity` construction in [phase1a_output_share_by_exposure.R](analysis/phase1a_output_share_by_exposure.R).
- `firm_dev_{i,s}` = `firm_emint_i` minus its NACE4d sector mean — the within-sector deviation that is the actual H1 object.
- `intensity_base_s` = NACE4d pre-MSR shortage-cost share (reused from S12).

---

## Angle 1 — Firm-level output × firm emissions × sector pass-through

**Script:** new file [analysis/phase4_firm_output_reallocation.R](analysis/phase4_firm_output_reallocation.R)

### Panel build
Start from `firm_year_belgian_euets` (ETS firms only for Angle 1), join NACE4d PPI deflator, compute `log(real_revenue)`. Merge annual CPShock (sum of Känzig monthly Shock over calendar year) and `intensity_base_s`. Restrict to firms with ≥3 years of data and non-missing `firm_emint_i`. Sample ≈ 200 ETS firms × 15 years = ~3000 obs.

### Spec 1.A — Base H1 test (within sector × year)
```
Δlog(real_rev)_{i,s,t,h} = β · (CPShock_t × firm_dev_{i,s}) + α_{s,t} + α_i + ε
```
- `s × t` FE absorbs the sector-level aggregate response (including every aggregate macro shock)
- identification: within sector × year, do firms whose pre-MSR emissions intensity exceeds their sector mean contract more when the aggregate shock hits?
- clustering: firm and sector-year two-way
- horizons: h ∈ {0, 1, 2, 3}

**H1 → β < 0 significant.** **H2 → β ≈ 0.** This alone is a clean test.

### Spec 1.B — Pass-through interaction (distinguishes H1 mechanism)
```
Δlog(real_rev)_{i,s,t,h} =
    β1 · (CPShock_t × firm_dev_{i,s})
  + β2 · (CPShock_t × firm_dev_{i,s} × intensity_base_s)
  + α_{s,t} + α_i + ε
```
- `intensity_base_s` is the sector-level scale on pass-through (by S12 linearity, it proxies realized pass-through per unit shock)
- H1 pure: β2 < 0 (reallocation concentrates in high-pass-through sectors)
- H2: β1 ≈ 0 and β2 ≈ 0

### Spec 1.C — Realized pass-through as moderator (robustness)
Replace `intensity_base_s` in Spec 1.B with a sector-specific LP coefficient `β̂_s` from a per-sector version of [phase3_ppi_passthrough_monthly.R](analysis/phase3_ppi_passthrough_monthly.R) at h=12 months. Estimated noise in `β̂_s` is a concern at NACE4d — do a shrinkage version (post-LASSO or empirical-Bayes) as well.

### Spec 1.D — ETS vs non-ETS margin (already-partial evidence)
Repeat Spec 1.A on the **full** firm panel (ETS + non-ETS in the same NACE4d), with the ETS dummy × CPShock × intensity_base_s interaction. Closes the loop with [phase0_ets_share_shift.R](analysis/phase0_ets_share_shift.R): is the null there masking heterogeneity by sector pass-through?

### Reporting
- Coefficient tables for Specs 1.A–1.D, each horizon
- Binscatter of firm-level Δlog(real_rev) on `firm_dev` within pass-through terciles of sectors (visual check)
- Dose-response plot: β by decile of `intensity_base_s`

---

## Angle 4 — B2B buyer-level supplier switching

**Script:** new file [analysis/phase4_b2b_supplier_switching.R](analysis/phase4_b2b_supplier_switching.R)

### Panel build
From `b2b_selected_sample`: restrict the **seller** side to ETS firms with known `firm_emint_i` (~200 sellers). Buyer side can be any firm. For each (seller_j, buyer_b, year_t):
- `flow_{j,b,t}` = corr_sales
- `share_{j,b,t}` = `flow_{j,b,t}` / Σ over sellers in the same seller-sector selling to b in year t (within-buyer within-seller-sector share)

Merge on CPShock_t (annual), `firm_emint_j`, `intensity_base_{s(j)}`.

### Spec 4.A — Flow-level pair panel
```
Δlog(flow)_{j,b,t,h} = β · (CPShock_t × firm_emint_j) + α_{b,t} + α_{j,b} + ε
```
- Buyer × year FE absorbs all aggregate buyer demand shocks (this is the key piece the sector-level reallocation test can't use)
- Pair FE absorbs time-invariant relationship intensity
- Identification: within a buyer, across its suppliers in a given year, do high-emissions suppliers lose flow when the shock hits?
- clustering: two-way on seller and buyer

H1 → β < 0. H2 → β ≈ 0.

### Spec 4.B — Within-sector supplier share
```
Δshare_{j,b,t,h} = β · (CPShock_t × firm_dev_{j,s(j)}) + α_{b,s(j),t} + α_{j,b} + ε
```
- `b × s(j) × t` FE absorbs the buyer's total spending in seller-sector s in year t — so β isolates within-sector supplier substitution
- This is the tightest possible H1 test: at fixed buyer, at fixed seller-sector, at fixed year, does share shift from dirtier to cleaner suppliers?

### Spec 4.C — Pass-through interaction
Add `× intensity_base_{s(j)}` triple interaction to 4.A and 4.B. Same H1/H2 split as in Spec 1.B.

### Extensive margin
Separately estimate a linear probability model on relationship continuation:
```
P(flow_{j,b,t+h} > 0 | flow_{j,b,t} > 0) = β · (CPShock × firm_emint_j) + FE + ε
```
Tests whether buyers *drop* high-emissions suppliers rather than just shrinking them.

### Data hazards
- Local 1 has the downsampled B2B. All specifications will be developed and unit-tested on local 1, then deployed to RMD for the real panel. Downsampled estimates are not reportable (sparsity destroys pair FE).
- The `frozen_weights_matrices` base-period averaging is for a different purpose (Leontief exposure) and is not reused here; Angle 4 uses the raw year-by-year B2B panel.

---

## Further analysis — PRODCOM product-firm-month enhancement

**Status: documentation only, no scripts in this round.** Kept here so the content is picked up when the PRODCOM workstream advances; eventual home is a "Reallocation extension" section of [PRODCOM_PLAN.md](PRODCOM_PLAN.md).

PRODCOM adds three pieces of granularity that neither the firm-year panel (Angle 1) nor the B2B panel (Angle 4) can deliver:

### 1. Within-product quantity dose-response (direct H1 vs H2 test)

The firm-year panel in Angle 1 aggregates across a firm's entire product mix; the NACE4d sector heterogeneity of products is absorbed by sector FE but within-firm product mix shifts are invisible. PRODCOM's firm × PC8 × month grain lets us run:

```
log(quantity)_{i,p,y} = β · firm_emint_i + α_{p,y} + α_i + ε
```

mirroring [PRODCOM_PLAN.md](PRODCOM_PLAN.md)'s Spec 1 but with **quantity** (not price) on the LHS. `p × y` FE absorbs every product-specific demand shock. If H1 is right and the null in [REALLOCATION_FINDINGS.md](REALLOCATION_FINDINGS.md) is an aggregation artefact, it shows here: high-exposure firms should lose quantity to low-exposure firms producing the same PC8 product in the same period. If H2 is right, β ≈ 0 at PC8 × month granularity as well.

**This is the highest-leverage PRODCOM regression for this research question.** At PC8 × month FE granularity, heterogeneous demand elasticities across products are absorbed, and any residual quantity response genuinely reflects within-product firm-level reallocation.

### 2. Joint price–quantity test (decomposes H1 vs H2 directly)

PRODCOM gives both value and quantity, so unit price = value / quantity and quantity are jointly observable at firm-product-month. Running Spec 1 from [PRODCOM_PLAN.md](PRODCOM_PLAN.md) (price) and the quantity analog (above) on the same sample produces two coefficients that discriminate H1 and H2 sharply:

| β on `firm_emint_i` | price | quantity | Interpretation |
|---|---|---|---|
| H1 (reallocation active) | + sig | − sig | high-exposure firms raise prices; low-exposure firms capture quantity share |
| H2 (inelastic shield) | + sig | ≈ 0 | pass-through without quantity substitution |
| No pass-through at all | ≈ 0 | ≈ 0 | MMS 2024-style null (they only tested the price half) |

Firm-year data cannot do this joint test because firm-year turnover = price × quantity is not observable separately. PRODCOM is the unique dataset that separates the two at the same grain as the exposure measure.

### 3. Extensive margin on products

Does a firm drop PC8 codes after the shock? PRODCOM's firm × PC8 × year presence/absence measures product-line exits, which firm-year revenue cannot decompose. Complements B2B extensive-margin (relationship exit) with product-mix exit — a different reallocation channel.

### Where PRODCOM does *not* add

- **Angle 4 B2B**: PRODCOM is firm × product, not transactional. The buyer substitution story cannot be tested in PRODCOM. B2B and PRODCOM are complementary, not substitutable.
- **Extending 2020–2024**: PRODCOM covers the Phase IV period but the CPShock series for that period is still contaminated (same issue as S12b). PRODCOM does not fix identification, only grain.

### Why MMS 2024 didn't already answer this

MMS 2024 (NBB WP 467) regressed Δ log(price) on a binary ETS dummy with firm×year averages and found +0.14 (SE 0.15), insignificant. They (a) used a binary treatment, not continuous `firm_emint_i`; (b) ran annual; (c) never ran the quantity regression. The quantity test and the continuous dose-response are both in-scope for us and both discriminate H1 from H2.

### Future execution (not part of this round)
Eventual implementation would slot into the existing Stata pipeline at [analysis/prodcom_passthrough_stata/](analysis/prodcom_passthrough_stata/). Step 05 already produces monthly value and quantity at firm × PC8 × month, so the quantity regressions require only new regression `.do` files that consume that panel. Development on local 1 against mock `prod.dta`, execution on RMD by the co-author.

---

## Execution sequence

1. **Spec 1.A** on local 1 against full training sample — this is the cleanest single test and doesn't depend on sector pass-through at all. If β is significantly negative, H1 is directly supported.
2. **Spec 1.B** adds the pass-through interaction.
3. **Spec 4.A / 4.B** on RMD (downsampled B2B on local 1 is for code dev only — pair FE collapses).
4. **Spec 4.C** pass-through triple interaction.
5. Assemble a results table comparing firm-year (Angle 1) and B2B (Angle 4) coefficients on `(CPShock × firm emissions intensity)`. Consistent signs across the two datasets are the publishable result.
6. At that point, move the PRODCOM "Further analysis" section into [PRODCOM_PLAN.md](PRODCOM_PLAN.md) as a deferred extension.

## Verification

- **Spec 1.A sanity**: without the shock interaction, β on `firm_dev` alone with sector FE should recover the within-sector output-share correlation already in [phase1a_output_share_by_exposure.R](analysis/phase1a_output_share_by_exposure.R) (high-exposure firms slightly gaining within-sector share pre-shock). Deviation from that is a build bug.
- **Spec 4.A sanity**: aggregate pair-level flow, summed over all (j, b) pairs by year, should reconcile with the totals already in the phase0 B2B aggregates.

## Out of scope for this plan

- Independent proxies of demand elasticity (import penetration, markups, product differentiation). The S12 sector-by-sector regression heterogeneity in [phase3_ppi_heterogeneity.R](analysis/phase3_ppi_heterogeneity.R) is the closest existing artefact; extending that is worth doing but is a separate workstream.
- Export vs domestic market pass-through (requires customs panel on RMD).
- Phase IV extension. Depends on either BKR refined surprise or Bauer-Swanson residualization — TODO.md item.
