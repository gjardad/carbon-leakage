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
| [data/processed/eua_price.csv](data/processed/) | daily→annual | EUA secondary-market price | existing (used in [phase3_build_exposure_panel.R](analysis/phase3_build_exposure_panel.R)) |
| event dates | year | MSR Commission proposal 2014-01, Phase IV Council approval 2018-02 | new, code-constant in [phase4_firm_output_reallocation.R](analysis/phase4_firm_output_reallocation.R) |
| [data/processed/frozen_weights_matrices.RData](data/processed/) | base period | A (upstream) and B (downstream) matrices, avg costs | [network_exposure_regs_1_build_frozen_weights.R](analysis/network_exposure_regs_1_build_frozen_weights.R) |

**Main sample:** 2005–2019 Shock column (clean identification). Phase-IV extension is deferred until the log-return surprise is residualized (TODO.md; also blocks S12b).

**Firm-level treatment variables (cost-based, analog of `intensity_base_s`):**

The firm-level analog of the sector-level `intensity_base_s` — not the revenue-normalized `shortage_intensity` in [phase1a_output_share_by_exposure.R](analysis/phase1a_output_share_by_exposure.R). Revenue is the wrong denominator here because it is endogenous to the ETS shock itself: H1 predicts revenue falls for high-emitters (denominator shrinks, treatment inflates); H2 predicts revenue rises (treatment compresses). Either direction contaminates the treatment variable, even if we take a 2013–16 average. The sector-level machinery was deliberately built with a fixed cost denominator in [phase3_build_exposure_panel.R:177-222](analysis/phase3_build_exposure_panel.R) — the firm analog must match.

- **`firm_cost_share_i`** — *primary treatment.* Firm-level carbon cost share; numerator averaged 2013–16 (post-auctioning, pre-MSR), denominator averaged 2010–12 (fixed, pre-ETS-tightening). Exactly mirrors `intensity_base_s = mean_{2013-16}(exposure_alt_total) = mean_{2013-16}(total_carbon_cost) / mean_{2010-12}(total_cost)` from [phase3_build_exposure_panel.R:152,217-222](analysis/phase3_build_exposure_panel.R) and [phase3_ppi_passthrough_monthly.R:113-117](analysis/phase3_ppi_passthrough_monthly.R):
  ```
  firm_cost_share_i = mean_{t ∈ 2013..16} [ shortage_{i,t} × EUA_t ]
                    / mean_{t ∈ 2010..12} [ total_cost_{i,t} ]
  ```
  where `shortage = max(emissions - allocated_free, 0)` and `total_cost = mat_inputs + wage_bill`. Fallback to earliest 3-year window for firms without 2010–12 coverage (same as sector-level fallback at [phase3_build_exposure_panel.R:188-208](analysis/phase3_build_exposure_panel.R)). Units: share.
- **`firm_emint_physical_i`** — *robustness variant.* Shortage per € of cost, no EUA price baked in:
  ```
  firm_emint_physical_i = mean_{t ∈ 2013..16} [ shortage_{i,t} ]
                        / mean_{t ∈ 2010..12} [ total_cost_{i,t} ]
  ```
  Units: tCO₂ per €. Cleaner because it doesn't pre-load EUA-price variation from the base period into the treatment. Use as a robustness check — signs should match `firm_cost_share_i`.
- **`firm_dev_{i,s}`** — within-NACE4d-sector demeaning of `firm_cost_share_i` (or `firm_emint_physical_i`). This is the actual H1 object: across two firms in the same sector-year, does the one with larger `firm_dev` lose output when the carbon-price signal moves? Sector-year FE absorb the common component; `firm_dev` isolates cross-firm heterogeneity.
- **`intensity_base_s`** — NACE4d pre-MSR shortage-cost share (reused from S12). Also cost-based, so firm and sector scales are comparable.

Verification before any regression: `firm_cost_share_i`, aggregated to NACE4d with firm total-cost weights, should reproduce `intensity_base_s` up to the ETS-firm-only rounding. If it doesn't, one of the two builds has a bug.

---

## Angle 1 — Firm-level output × firm emissions × sector pass-through

**Script:** new file [analysis/phase4_firm_output_reallocation.R](analysis/phase4_firm_output_reallocation.R)

### Panel build
Start from `firm_year_belgian_euets`, join NACE4d PPI deflator, compute `log(real_revenue)`. Merge `firm_cost_share_i` (treatment), `intensity_base_s` (sector pass-through moderator), and the time-series forcing variables defined below. Restrict to firms with ≥3 years of data and non-missing `firm_cost_share_i`. ETS-only sample ≈ 200 firms × 15 years ≈ 3000 obs; ETS + non-ETS sample (for Spec 1.D and EUA-level placebo) ≈ 30k firms × 15 years depending on sector filter.

### Identification strategies

We run each spec below under **three identifications of the time-series carbon-price signal**, not one. Reason: the annual Känzig CPShock has SD 0.53 and already failed in [PASSTHROUGH_CPSHOCK.md](PASSTHROUGH_CPSHOCK.md) S7–S11 (first-stage cluster-F ≤ 0.05, wrong-sign reduced forms) — the headline S12 result works only because it runs monthly, and firm data is only annual. We need complementary strategies that don't hinge on annual CPShock variation.

- **ID-A: Annual CPShock.** `CPShock^ann_t = Σ_{m ∈ year t} CPShock_m` from Känzig 2005–2019. Clean identification (monetary-shock-style), but thin power. Included for direct comparability with S12 and for the Känzig pedigree — if β flips sign here vs other IDs, we learn something.
- **ID-B: EUA level × firm_cost_share.** Interact the *level* of the annual EUA price with firm treatment; identify off within-sector-year cross-firm heterogeneity plus a non-ETS matched placebo. Sector×year FE absorb all aggregate macro confounds. High power because EUA level has one-to-two orders of magnitude more variation than CPShock. Identification rests on: (i) the Bartik/shift-share logic that `firm_dev_{i,s}` is orthogonal to contemporaneous firm-specific demand shocks by construction (pre-MSR average), (ii) the non-ETS placebo (Spec 1.D) pinning down what "no-carbon-exposure" firms look like in the same sector-year. Close in spirit to Fabra-Reguant / Colmer et al. *Note from [feedback_fabra_reguant_iv_distinction.md](memory/feedback_fabra_reguant_iv_distinction.md): our setup already relies on aggregate EUA exogeneity, which the memo flagged as legitimate in our context.*
- **ID-C: Event study.** Binary treatment `Post_t` = I(t ≥ T*), T* ∈ {2014 (MSR Commission proposal), 2018 (Phase IV Council approval 2018-02)}, interacted with `firm_cost_share_i`. Pre-trends h = −3…−1, post h = 0…+5. Sharper and easier to visualize than continuous shocks; a discrete large move concentrated in known dates. Earliest credible announcement date (Commission proposal, not final adoption) — per [TREAT_HYPOTHESIS_PLAN.md](TREAT_HYPOTHESIS_PLAN.md) risks section.
- **ID-D (deferred): BKR-extended CPShock.** Känzig is our advisor per [memory/project_advisors_and_collaborators.md](memory/project_advisors_and_collaborators.md); direct path to the refined/extended series (if it adds pre-2019 variation, not just Phase IV extension, it helps; if only extension, it doesn't help the annual-frequency power problem). Ask before committing.

Each spec below is estimated under ID-A, ID-B, and ID-C. Report all three side by side; the publishable result is sign consistency across identifications, not statistical significance in any one.

### Spec 1.A — Base H1 test (within sector × year)
```
Δlog(real_rev)_{i,s,t,h} = β · (Signal_t × firm_dev_{i,s}) + α_{s,t} + α_i + ε
```
where `Signal_t ∈ {CPShock^ann_t, EUA_t, Post_t}` per ID-A/B/C.
- `s × t` FE absorbs the sector-level aggregate response (every aggregate macro shock).
- identification: within sector × year, do firms whose pre-MSR carbon-cost share exceeds their sector mean contract more when the carbon-price signal moves?
- clustering: firm and sector-year two-way
- horizons: h ∈ {0, 1, 2, 3}

**H1 → β < 0 significant.** **H2 → β ≈ 0.** This is the core test.

### Spec 1.B — Pass-through interaction (distinguishes H1 mechanism)
```
Δlog(real_rev)_{i,s,t,h} =
    β1 · (Signal_t × firm_dev_{i,s})
  + β2 · (Signal_t × firm_dev_{i,s} × intensity_base_s)
  + α_{s,t} + α_i + ε
```
- `intensity_base_s` is the sector-level pass-through scale (by S12 linearity, proxies realized pass-through per unit signal).
- H1 pure: β2 < 0 (reallocation concentrates in high-pass-through sectors).
- H2: β1 ≈ 0 and β2 ≈ 0.

### Spec 1.C — Sample split on realized sector pass-through (sharpest test)

Replaces the earlier continuous-moderator version. The S12 pooled coefficient +4.08 at h=12 is a weighted average across NACE4d sectors under the assumption that realized pass-through is linear in `intensity_base_s`. If pass-through is actually heterogeneous *across* the `intensity_base_s` loading — some sectors pass through, others don't, independently of their carbon-cost scale — S12 won't show it. The sharper question for H1 is: in the sectors where the PPI actually moves when CPShock hits, does the firm-level reallocation show up there?

Procedure:

1. Build per-sector pass-through coefficients `β̂_s` via an interacted panel LP at h = 12 months:
   ```
   Δlog(PPI)_{s,m+12} − Δlog(PPI)_{s,m-1} = Σ_s [ γ_s · CPShock_m · I(sector=s) ] + α_s + δ_m + ε
   ```
   using the same monthly panel as S12 ([phase3_ppi_passthrough_monthly.R](analysis/phase3_ppi_passthrough_monthly.R)). Interaction-with-sector-dummies form preserves month FE (so identification is from cross-sector response in the same month, not from time-series within sector). Two CPShock variants: `cpshock_shock` (primary, matches S12 headline) and `cpshock_surprise` (robustness). Note: unlike S12, the RHS here is CPShock alone (not `CPShock × intensity_base_s`), so `γ_s` absorbs the `intensity_base_s` scale. That's what we want — we're measuring realized pass-through, not pass-through *per unit of exposure*.
2. Classify sectors into three buckets using `γ_s` and its SE:
   - **High-pass-through:** `γ_s > 0` and significant at 10%.
   - **No-pass-through:** `γ_s ≤ 0` or not significantly positive.
   - **Unclassified:** no ETS firm in sector / insufficient observations for a coefficient.
   Robustness: also report a 5% cutoff and a top-tercile cutoff.
3. Run Spec 1.A **on firms in high-pass-through sectors only**. H1 predicts a significantly negative β (reallocation where pass-through is real). Run on no-pass-through sectors as contrast — expected null under both H1 and H2.

Known limitations:
- NACE4d monthly LP with ~180 months per sector is noisy; the "no-pass-through" bucket will include sectors that pass through but where the sector LP lacked power. Classification is therefore conservative in the H1 direction (false negatives likely, false positives less likely).
- Sample size in the high-pass-through firm panel will be smaller than Spec 1.A's 215 firms.
- Sign of `cpshock_shock` vs `cpshock_surprise` heterogeneity carries over here — report classification under both and intersect.

### Spec 1.D — ETS vs non-ETS margin (and the placebo that ID-B needs)
Run Spec 1.A on the **full** firm panel (ETS + non-ETS in the same NACE4d), with an ETS-dummy × Signal × `intensity_base_s` triple interaction, and `firm_cost_share_i = 0` for non-ETS firms.

Under ID-B (EUA level) this serves double duty: it IS the placebo test. Sector×year FE already absorb macro confounds, so if non-ETS firms within the same sector also respond to EUA level × placebo-exposure, the ID-B estimate is confounded. If they don't respond, ID-B is clean.

Under ID-A (CPShock) and ID-C (Event study), this closes the loop with [phase0_ets_share_shift.R](analysis/phase0_ets_share_shift.R): is the null there masking heterogeneity by sector pass-through?

### Reporting
- Coefficient tables for Specs 1.A–1.D × ID-A/B/C, each horizon.
- Binscatter of Δlog(real_rev) on `firm_dev` within pass-through terciles of sectors (visual check).
- Dose-response plot: β by decile of `intensity_base_s`.
- Event-study plot (ID-C): β_h for h = −3…+5, with 90% CIs, for MSR and Phase IV events.
- Robustness column: all specs re-run with `firm_emint_physical_i` in place of `firm_cost_share_i`.

---

## Angle 4 — B2B buyer-level supplier switching

**Script:** new file [analysis/phase4_b2b_supplier_switching.R](analysis/phase4_b2b_supplier_switching.R)

### Panel build
From `b2b_selected_sample`: restrict the **seller** side to ETS firms with known `firm_cost_share_j` (~200 sellers). Buyer side can be any firm. For each (seller_j, buyer_b, year_t):
- `flow_{j,b,t}` = corr_sales
- `share_{j,b,t}` = `flow_{j,b,t}` / Σ over sellers in the same seller-sector selling to b in year t (within-buyer within-seller-sector share)

Merge the same three time-series signals as Angle 1: `CPShock^ann_t` (ID-A), `EUA_t` (ID-B), `Post_t` (ID-C), plus `firm_cost_share_j`, `firm_dev_{j,s(j)}`, `intensity_base_{s(j)}`.

Note: the B2B cross-section is vastly larger than Angle 1 (pair-years, not firm-years), so the annual-shock power problem bites less here. ID-A is more likely to work in Angle 4 than in Angle 1. Still run all three.

### Spec 4.A — Flow-level pair panel
```
Δlog(flow)_{j,b,t,h} = β · (Signal_t × firm_cost_share_j) + α_{b,t} + α_{j,b} + ε
```
where `Signal_t ∈ {CPShock^ann_t, EUA_t, Post_t}`.
- Buyer × year FE absorbs all aggregate buyer demand shocks (the piece the firm-level test can't use)
- Pair FE absorbs time-invariant relationship intensity
- Identification: within a buyer, across its suppliers in a given year, do high-carbon-cost-share suppliers lose flow when the signal moves?
- clustering: two-way on seller and buyer

H1 → β < 0. H2 → β ≈ 0.

### Spec 4.B — Within-sector supplier share (tightest H1 test)
```
Δshare_{j,b,t,h} = β · (Signal_t × firm_dev_{j,s(j)}) + α_{b,s(j),t} + α_{j,b} + ε
```
- `b × s(j) × t` FE absorbs the buyer's total spending in seller-sector s in year t — so β isolates within-sector supplier substitution
- At fixed buyer × seller-sector × year, does share shift from dirtier to cleaner suppliers?

### Spec 4.C — Pass-through interaction
Add `× intensity_base_{s(j)}` triple interaction to 4.A and 4.B. Same H1/H2 split as in Spec 1.B. Run under all three identifications.

### Spec 4.D — ETS vs non-ETS seller placebo (ID-B cleanliness check)
Enlarge the seller side to include non-ETS sellers (set `firm_cost_share_j = 0` for them); add ETS-dummy × Signal_t interaction. Under ID-B (EUA level), non-ETS sellers should not systematically gain/lose share from EUA movements conditional on buyer × sector × year FE. If they do, ID-B is confounded in Angle 4 (not just Angle 1).

### Extensive margin
Separately estimate a linear probability model on relationship continuation:
```
P(flow_{j,b,t+h} > 0 | flow_{j,b,t} > 0) = β · (Signal × firm_cost_share_j) + FE + ε
```
Tests whether buyers *drop* high-cost-share suppliers rather than just shrinking them. Run under all three identifications.

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

MMS 2024 (NBB WP 467) regressed Δ log(price) on a binary ETS dummy with firm×year averages and found +0.14 (SE 0.15), insignificant. They (a) used a binary treatment, not continuous `firm_cost_share_i`; (b) ran annual; (c) never ran the quantity regression. The quantity test and the continuous dose-response are both in-scope for us and both discriminate H1 from H2.

### Future execution (not part of this round)
Eventual implementation would slot into the existing Stata pipeline at [analysis/prodcom_passthrough_stata/](analysis/prodcom_passthrough_stata/). Step 05 already produces monthly value and quantity at firm × PC8 × month, so the quantity regressions require only new regression `.do` files that consume that panel. Development on local 1 against mock `prod.dta`, execution on RMD by the co-author.

---

## Execution sequence

1. **Build treatment + signals** (local 1): `firm_cost_share_i`, `firm_emint_physical_i`, `firm_dev_{i,s}`, `CPShock^ann_t`, `EUA_t` (annual mean), `Post_t` dummies for MSR (T*=2014) and Phase IV (T*=2018).
2. **Verify treatment build**: aggregate `firm_cost_share_i` with firm total-cost weights to NACE4d and confirm it reproduces `intensity_base_s` up to ETS-firm-only rounding.
3. **Spec 1.A under all three IDs** on local 1 against full training sample — cleanest single test, no pass-through moderator. Read direction from sign consistency across ID-A/B/C; ID-B likely has the most power, ID-C the sharpest visual, ID-A the cleanest identification but weakest.
4. **Spec 1.B** (pass-through interaction) and **1.C** (realized β̂_s) under all three IDs.
5. **Spec 1.D** (ETS + non-ETS full panel). Under ID-B this is the placebo test for EUA-level identification — check non-ETS response is null before trusting ID-B.
6. **Spec 4.A / 4.B / 4.C / 4.D** on RMD (downsampled B2B on local 1 is for code dev only — pair FE collapses). Repeat all three IDs. ID-A is more likely to work here than in Angle 1 because of the huge cross-section.
7. **Extensive margin** (Angle 4).
8. **Assemble final table**: Angle 1 × Angle 4 × (ID-A, ID-B, ID-C). Publishable result = sign consistency of β on `(Signal × firm_cost_share)` across 6 cells; cross-ID consistency matters more than p-values in any single cell.
9. Ask Känzig (advisor) for BKR-extended CPShock. If pre-2019 annual variation is larger, re-run ID-A as a check. If only Phase IV extension, skip.
10. Move the PRODCOM "Further analysis" section into [PRODCOM_PLAN.md](PRODCOM_PLAN.md) as a deferred extension.

## Verification

- **Treatment build**: firm-level `firm_cost_share_i` aggregated to NACE4d with total-cost weights reproduces `intensity_base_s`. This is the first sanity check before any regression.
- **Spec 1.A sanity**: without the signal interaction, β on `firm_dev` alone with sector FE should recover the within-sector output-share correlation already in [phase1a_output_share_by_exposure.R](analysis/phase1a_output_share_by_exposure.R) (high-exposure firms slightly gaining within-sector share pre-shock). Deviation from that is a build bug. *Caveat:* phase1a uses revenue-normalized `shortage_intensity`; sign should match but magnitude will not.
- **Spec 1.D / 4.D placebo**: under ID-B, non-ETS-firm coefficient should be null. If non-null, EUA-level identification is confounded and ID-B results should be downweighted.
- **Spec 4.A sanity**: aggregate pair-level flow, summed over all (j, b) pairs by year, should reconcile with the totals already in the phase0 B2B aggregates.

## Out of scope for this plan

- Independent proxies of demand elasticity (import penetration, markups, product differentiation). The S12 sector-by-sector regression heterogeneity in [phase3_ppi_heterogeneity.R](analysis/phase3_ppi_heterogeneity.R) is the closest existing artefact; extending that is worth doing but is a separate workstream.
- Export vs domestic market pass-through (requires customs panel on RMD).
- Phase IV extension. Depends on either BKR refined surprise or Bauer-Swanson residualization — TODO.md item.
