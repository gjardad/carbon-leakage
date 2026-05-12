# Plan to address `[Not yet run]` sections in the joint paper

This document is the implementation plan for the eight subsections marked `[Not yet run.]` in `paper/leakage_within_across/`. It is the result of a local-1 diagnostic run (see `analysis/phase5_diagnostic_for_unrun_sections.R`) and is meant to be the handoff document for RMD execution.

---

## Diagnostic findings (local-1, 2026-05-01)

### (1) Phase II `firm_cost_share` does NOT exist

`firm_cost_share_flavors.RData` contains only two flavors:
- `cost_share_outcome` (time-varying, 2,936 firm-years)
- `cost_share_regressor` (time-invariant pre-shock 2013–16 / 2010–12, 211 firms)

There is **no 2005–2008 / Phase II flavor**. We need a third flavor `cost_share_regressor_phase2` constructed with:
- Numerator: 2005–2008 average shortage × EUA
- Denominator: 2003–2005 average total cost (or earliest available 3-year window)

### (2) Customs panel: structure exists, two-bloc version does not

The customs panel `customs_import_panel_regulated.RData` has the right granularity (importer × CN8 × source country × year) but is restricted to non-ETS source countries only — the CdGM identifying sample. For the buyer-supplier analysis (§5.2.2 onward) we need both EU and non-ETS rows.

### (2b) Customs panel: deliberately truncated to 2019

The processed customs panel ends in 2019 because it was built to match CdGM's 2000--2019 window. **This is not a data-availability constraint** — earlier turns in this conversation incorrectly attributed the truncation to a 2020 administrative discontinuity, which does not exist. Per `IMPORT_LEAKAGE.md`: "Sample period stops at 2019 to match CdGM. ... Extending the sample is a future to-do." The raw NBB customs data extends through 2022+ and a 2000--2022 rebuild is straightforward (no NBB reconciliation request needed).

### (3) Customs panel: quantity is MISSING

The processed customs panel does not retain a quantity column (only `value` in EUR). Unit-values cannot be computed from the existing panel. The raw NBB customs data does record quantity (per `IMPORT_LEAKAGE.md`); it was dropped during panel construction.

---

## Prerequisite RMD tasks (Day 0, ~1.5 days total)

### P1. Build Phase II firm cost-share

Modify `analysis/phase5_attach_firm_cost_share.R` (or create a sibling) to add a third flavor:
```
cost_share_regressor_phase2_{j}
  = (avg_2005-2008 shortage_j × avg_2005-2008 EUA) / avg_2003-2005 total_cost_j
```
With the same fallback to the earliest available 3-year window for firms missing 2003–2005 cost data. Save into `firm_cost_share_flavors.RData` alongside the existing two flavors.

**Verification:** the resulting flavor should yield a non-empty distribution; expect right-tail at ~0.5%–1% (Phase II EUA ranged €0.7–€22, much smaller than Phase IV).

### P2. Rebuild customs panel preserving quantity, both blocs, and extending to 2022

Modify `analysis/phase2_build_customs_panel.R` (or create `phase6_build_customs_two_bloc_panel.R`) to:
- Preserve quantity (kg) from the raw data alongside value (EUR).
- Drop the non-ETS-country filter (keep both EU and non-EU rows).
- **Extend the sample window to 2022** (the headline CdGM-replication panel stops at 2019 to match CdGM, but the raw NBB data is available through 2022; the buyer-supplier analyses in B1--B4 should run on the full 2000--2022 window to align with the within-country B2B sample and capture the Phase IV price spike).

Save into a new file `customs_import_panel_two_bloc.RData` so it does not collide with the existing CdGM-replication panel.

**Diagnostic to run on the rebuilt panel:** the original §3 of `phase5_diagnostic_for_unrun_sections.R` — fraction of (HS6 × country × year) cells with both value > 0 and quantity > 0, for the regulated and unregulated subsets separately. Also verify the year range extends through 2022 and that 2020--2022 row counts are consistent with prior years.

---

## Group A: Domestic horizon and Phase II identification

### A1 (§5.1.2) — HTE by time horizon, within-NACE-4d

**Spec.** Horizon-h LP on Test H sample, h ∈ {-9, …, 0, …, +7} relative to 2014:
```
share_top_{b,n,t+h} − share_top_{b,n,t-1}
  = γ_h · pair_exposure_{b,n} × 1[t = 2014]
  + α_{b,n} + δ_{n,t} + ε
```

**Identification.** Pre-trend test on leads h < 0 must be flat. Two-way clustering on buyer + supplier-NACE-4d. Two specs: intensive-only (j* active throughout window) and extensive-margin LPM at each h.

**Effort.** ~1 day. Modify the existing event-study script to output γ_h with proper SE.

**Deliverable.** IRF figure of γ_h vs. h with 95% CIs, P&R Figure 4 analog.

### A2 (§5.1.4) — HTE on across-category margin

**Spec.** (a) Horizon-h LP on Test I; (b) buyer-level quartile splits on `buyer_reg_exposure_b = Σ_n regulated_n × pre-shock_share_{b,n}`. The category-level quartile split is degenerate (most NACE 4-digits have nace_exposure = 0), hence the buyer-level split.

**Effort.** ~1.5 days. The 71M-obs sample size makes the LP heavier; budget RMD time accordingly.

### A3 (§5.1.6) — Phase II event-study

**Prerequisites.** P1 (Phase II cost-share flavor).

**Spec.** Same Test H and Test I equations but with `Post = 1[t ≥ 2008]` and the Phase II exposure regressor. Sample: 2003–2019.

**Identification.** Pre-trend window is short (2003–2007 = 5 years). Phase II shock is small (population p99 firm cost share = 0.46%). 2008–2010 contaminated by financial crisis: report year-by-year coefficients to show the crisis years vs. the recovery years explicitly. Same clustering as A1/A2.

**Effort.** ~2 days.

### A4 (§5.1.7) — Short-run vs long-run in Phase II

**Prerequisites.** A3.

**Spec.** Horizon-h LP on A3, h ∈ {0, …, 11} years post-2008. Terminal h=11 is the 2008→2019 long-difference (BLP/P&R-style long-run elasticity).

**Identification.** Composition change at long h. Run intensive-only and balanced-subsample versions. Permanence assumption: cite Fit-for-55 (2021) and CBAM (2023+) as evidence the Phase II→IV regime is permanent under EU institutional commitment.

**Effort.** ~1 day on top of A3.

**Deliverable.** Joint A3+A4 IRF figure of γ_h vs. h, h ∈ {-5, …, +11}.

---

## Group B: International buyer-supplier analysis

### B1 (§5.2.2) — Buyer-supplier customs analysis

**Prerequisites.** P2 (two-bloc customs panel).

**Spec.** Customs analog of equation (5.1.2):
```
share_top_{f,p,t} = β · pair_exposure^{EU}_{f,p} × 1[t ≥ 2015]
                   + α_{f,p} + δ_{p,t} + ε
```
- f = Belgian importer, p = HS6 regulated product
- share_top_{f,p,t} = importer's share of regulated-product spending going to most-exposed EU source country
- pair_exposure^{EU}_{f,p} = importer's pre-shock dependence on EU sources for product p

**Sample.** (importer, HS6) cells with positive imports from at least one EU and one non-EU source in some pre-shock year. Drop cells where the EU source is itself non-ETS (Cyprus, Malta) — small but worth a robustness flag.

**Identification.** Pre-determined regressor (constructed pre-2015), buyer-product and product-year FE, pre-trend test on 2000–2014. Two-way clustering on importer + HS6.

**Effort.** ~3 days. Construction of pair_exposure^{EU}_{f,p} is the main novel piece.

### B2 (§5.2.3) — HTE on customs analysis

**Spec.** (a) Horizon-h LP, h ∈ {0, …, 7} years post-2015 on the **2000–2022** rebuilt customs panel from P2. (b) Quartile splits of pair_exposure^{EU}_{f,p}.

**Note.** A Phase-II-cutoff customs version (2008 cutoff with horizons up to h=14 on the 2008→2022 window) would be a direct analog of A3+A4 on the international margin and is now feasible with the rebuilt panel. Worth running as a follow-up parallel to A3+A4.

**Effort.** ~1.5 days on top of B1.

### B3 (§5.2.4) — Non-EU supplier price response

**Prerequisites.** P2 (panel preserving quantity).

**Spec.**
```
log p^unit_{p,i,t} = β · regulated_p × 1[t ≥ 2015] + α_{p,i} + δ_{i,t} + ε
```
where p_unit = value / quantity, computed at the HS6 × source country × year level (collapsed across importers).

**Identification.** Quality compositional change absorbed by HS6 × source country FE. Currency pass-through controlled with EUR/USD, source-country GDP growth, or HS6 × country × year FE for triple-difference. Restrict to non-ETS source countries. Two-way clustering on HS6 + source country.

**Effort.** ~2 days.

### B4 (§5.2.5) — σ from observed customs prices

**Prerequisites.** P2 (panel preserving quantity).

**Spec.** Importer × HS6 CES nest with EU and non-EU as the two arms:
```
log(s_{f,p,EU,t} / s_{f,p,nonEU,t})
  = (1 − σ) · log(p_{p,EU,t} / p_{p,nonEU,t}) + α_{f,p} + δ_t + ε
```
**IV.** Use HS6 carbon intensity × Känzig CPShock_t as the relative-price shifter. First stage: log(p_EU/p_nonEU) on (carbon_intensity_p × CPShock_t). Exclusion restriction: CPShock × carbon-intensity affects relative quantities only through the relative-price channel.

**Effort.** ~3 days. Builds on B3's unit-value construction.

**Headline.** Comparison of σ^customs to the domestic σ in §5.1.1 — direct validation (or contradiction) of the assumed pass-through ρ ∈ [0.5, 1].

---

## Critical-path sequencing

```
Day 0   : P1 (Phase II FCS) + P2 (two-bloc customs panel rebuild) [~1.5 days]
Days 1-2: A1 + A2 [~2.5 days, parallelizable]
Days 3-5: A3 + A4 [Phase II horizon LP, ~3 days]
Days 5-9: B1 + B2 [customs buyer-supplier analysis, ~4 days]
Days 5-9: B3 + B4 [non-EU price response + σ, ~5 days, parallel to B1/B2]
```

**Wall time with two parallel RMD streams: ~10 days.**

**Single-stream wall time: ~13.5–15 days.**

## Group C: Additional import-margin analyses (added 2026-05-01)

### C1 (§5.2.6) — Imports vs.\ domestic substitution

**Spec.** At the (Belgian buyer × upstream NACE 4-digit × year) level, regress
import share on (carbon-cost regressor × Post). Numerator from customs panel
aggregated to NACE 4d via CN8 concordance; denominator base from B2B panel.

**Sample.** Cells with positive pre-shock spending in BOTH channels (substitution feasibility).

**FE.** buyer × NACE 4d (cell mean), buyer × year (buyer-year scale).

**Clustering.** Two-way: buyer + NACE 4d.

**Effort.** ~2 days (script written, tested locally; needs RMD run on full panels).

### C2 (§5.2.7) — Parallel-trends investigation for B1

**Motivation.** B1 finds EU-share rises post-2015 — wrong-signed for substitution toward non-EU. Test whether this is a pre-existing trend.

**Specs.**
1. Pre-trend regression: regress share_eu on pair_exposure_EU × year_centered over 2000-2014 only.
2. Full event study with leads back to 2000.
3. Raw-trajectory plot: mean share_eu by year × quartile of pair_exposure_EU.

**Effort.** ~1 day (script written; tested locally — pre-trend β = +0.073, p < 10^-50, suggesting the EU-share result is largely confounding, not causal).

### C3 (§5.2.8) — Within-EU substitution toward less emission-intensive sources

**Prerequisites.** Build emission intensity at the (NACE 2d × EU country × year) level from Eurostat ENV_AC_AINAH_R2 (air emissions) / NAMA_10_A64 (GVA). Helper script `phase6_build_eu_emission_intensity.R` written; needs internet to download Eurostat data (~30 minutes).

**Spec.** Importer × HS6 × EU-country × year panel, restricted to regulated products and EU sources:
```
share_{f,p,c,t}^{within-EU} = β · low_intensity_{p,c} × Post
                              + α_{f,p,c} + δ_{c,t} + ε
```
where low_intensity_{p,c} is the bottom-tercile dummy of country c's NACE 2d emission intensity for the NACE 2d corresponding to HS6 p.

**FE.** importer × HS6 × source-country (cell mean), source-country × year (country-year shocks).

**Clustering.** Two-way: importer + source country.

**Effort.** ~2-3 days (Eurostat data build + analysis; both scripts written, not yet tested).

## Open questions for the co-author

1. **PRODCOM**: B3/B4 use customs unit-values. PRODCOM has firm-level domestic unit-values that could complement the customs analysis on the within-country side (do regulated Belgian producers raise their prices in response to ETS, at the unit-value level rather than the PPI level?). This is closer to `martin2014`'s firm-level pass-through specification. Deferred per user direction; revisit later.

(A previously listed open question about extending the customs panel past 2019 is removed: the 2019 truncation in the existing processed panel is a deliberate match to CdGM's window, not an administrative discontinuity. Extending to 2022 is folded into prerequisite P2 above.)

---

*Generated 2026-05-01. Local-1 diagnostic at `analysis/phase5_diagnostic_for_unrun_sections.R`.*
