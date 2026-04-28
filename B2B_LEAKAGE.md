# B2B Leakage: CMdG-Style Replication on Belgian Domestic Supplier Switching

*Phase 3 of [CMdG_REPLICATION.md](CMdG_REPLICATION.md). Asks whether Belgian buyers shifted away from regulated-NACE ETS-Belgian sellers post-2005 — the domestic analog of CMdG's cross-border carbon-leakage hypothesis. The novel piece France can't do because they lack firm-to-firm transaction data.*

**Headline finding:** **No identifiable B2B leakage in Belgium.** A binary diff-in-diff initially suggests treated sellers (ETS × regulated-NACE) GAINED domestic buyer share post-2005 by ~36 percentage points (p < 0.005). But this finding does not survive (a) switching to a continuous-intensity treatment that exploits cross-firm cost-share variation among ETS sellers, or (b) the parallel-trends test using 2002-04 leads. The binary result reflects **market structure** — large regulated-NACE ETS sellers are the dominant Belgian suppliers in their NACE regardless of treatment intensity — not a causal ETS response. Combined with [IMPORT_LEAKAGE.md](IMPORT_LEAKAGE.md)'s null cross-border finding, **Belgium shows no leakage at either the international or the domestic dimension** under any cleanly identified specification.

---

## Headline summary

| Specification | Phase 3 share, β | Phase 3 prob, β | Interpretation |
|---|---|---|---|
| Binary, col(5) FE | **+0.358** *** | **+0.829** *** | Looks like consolidation toward ETS-regulated sellers |
| Binary robustness Specs A/C/D | all positive *** | all positive *** | Robust across control choices |
| **Continuous, col(5) FE** | **-76 (SE 348)** | n/a | **VCOV near-singular; effectively unidentified** |
| **Continuous, col(1) FE** | **-0.5 (SE 1.6)** | n/a | **Null in P3** |
| **Continuous, col(1) — pre-trend** | **β_pre = +32, β_p1 = +29** | n/a | **Pre-period and Phase 1 indistinguishable; parallel trends violated** |
| Event-study leads (continuous, col 5) | +4.5 in 2003 (pre) | n/a | Pre-trend ≠ 0; no kink at 2005 |

**The binary headline is an artifact of the binary spec absorbing market structure as treatment.** The continuous spec — which uses firm-level cost-share intensity, the variable that should pick up actual ETS exposure — produces nothing identifiable.

---

## What we estimated

### Binary spec (Spec C — full sample, double diff)

```
y_{j,b,t} = β_1 · TREAT_j × 1(t ∈ 2005-08)
          + β_2 · TREAT_j × 1(t ∈ 2009-12)
          + β_3 · TREAT_j × 1(t ∈ 2013-19)
          + α_{j,b} + δ_{sn4d, t} + δ_{bn4d, t} + ε

TREAT_j = 1(seller_is_ets) × 1(seller_is_regulated_NACE)
```

Implicit control: all other (seller, year) cells (non-ETS sellers, non-regulated-NACE sellers, both). Two outcomes — **share** (within-buyer-NACE) and **probability** (pair active). Six FE columns paralleling Phase 2 Table 1, plus four-spec robustness across control-group choices.

### Continuous spec

```
y_{j,b,t} = β_pre · firm_cost_share_j × 1(t ∈ 2002-04)
          + β_1   · firm_cost_share_j × 1(t ∈ 2005-08)
          + β_2   · firm_cost_share_j × 1(t ∈ 2009-12)
          + β_3   · firm_cost_share_j × 1(t ∈ 2013-19)
          + α_{j,b} + δ_{sn4d, t} + δ_{bn4d, t} + ε
```

`firm_cost_share_j = mean_{2013-15}(shortage × EUA) / mean_{2010-12}(total_cost)` per ETS seller; 0 for non-ETS sellers. Sample: active pairs only (no balance/zero-fill). Pre-period 2002-2004 included via raw `B2B_ANO.dta` instead of the `b2b_selected_sample` (which restricts to 2005+).

**Build script:** [analysis/phase3_build_b2b_cmdj_panel.R](analysis/phase3_build_b2b_cmdj_panel.R) (binary).
**Binary regression script:** [analysis/phase3_b2b_cmdj_did.R](analysis/phase3_b2b_cmdj_did.R).
**Binary event study:** [analysis/phase3_b2b_cmdj_eventstudy.R](analysis/phase3_b2b_cmdj_eventstudy.R).
**Continuous regression + event study:** [analysis/phase3_b2b_cmdj_did_continuous.R](analysis/phase3_b2b_cmdj_did_continuous.R).

---

## Sample

### Binary spec sample (built from `b2b_selected_sample.RData`, 2005-2022)

Filter cascade:

```
b2b_selected_sample (2005-2022)
  → restrict to regulated-intensive buyer NACE (Phase 0 Step 6 list)
  → restrict to core-input pairs (seller's NACE 2d ∈ buyer's core inputs at 10%)
  → balance: every (seller, buyer) pair ever observed × all years
  → drop missing NACE
```

Final: 7,826 unique pairs × 18 years = ~140k cells. Cell counts:

| seller_is_ets | seller_is_regulated_nace | N cells |
|---|---|---|
| 1 (ETS) | 1 (regulated) | 26,587 (treated) |
| 1 (ETS) | 0 | 4,427 |
| 0 (non-ETS) | 1 (regulated) | 32,994 |
| 0 (non-ETS) | 0 | 76,860 |

### Continuous spec sample (built from raw `B2B_ANO.dta`, 2002-2022)

Filter cascade:

```
B2B_ANO.dta raw (2002-2022, 555,399 rows)
  → year + positive corr_sales filter → 478,524 rows
  → NACE join + drop NA → 469,229
  → regulated-intensive buyer + core-input pair → 44,279
  → drop ETS sellers without computable firm_cost_share → 43,982 rows
```

ETS firms with `firm_cost_share`: 224 (out of ~280 total Belgian ETS firms).
`firm_cost_share` distribution: median 0.000041, 90th pct 0.0020, 99th pct 0.096. Heavy right tail; most ETS sellers have very small intensity.

**Sample is active-pairs-only** — no balance/zero-fill. The intensive-margin share regression therefore estimates within-active-period reallocation, not the activation decision.

---

## Results — Binary spec (the +0.36 finding)

Output: [output/tables/phase3_b2b_cmdj_table_A.csv](output/tables/phase3_b2b_cmdj_table_A.csv) (share), [output/tables/phase3_b2b_cmdj_table_B.csv](output/tables/phase3_b2b_cmdj_table_B.csv) (probability).

### Six-FE-column table — Panel A (share)

| Col | Phase 1 | Phase 2 | Phase 3 |
|---|---|---|---|
| col 1 (sn4d^year) | +0.033 (n.s.) | +0.077 *** | +0.069 *** |
| col 2 (seller^buyer + year) | +0.213 * | +0.220 * | +0.197 . |
| col 3 (seller^buyer + sn4d^year) | +0.323 *** | +0.369 *** | +0.355 *** |
| col 4 (seller^buyer + bn4d^year) | +0.329 *** | +0.339 *** | +0.315 *** |
| **col 5 (preferred)** | **+0.330** ** | **+0.375** ** | **+0.358** ** |
| col 6 (seller^buyer + year^buyer_ets) | +0.214 * | +0.221 * | +0.198 . |

### Six-FE-column table — Panel B (probability)

| Col | Phase 1 | Phase 2 | Phase 3 |
|---|---|---|---|
| col 1 | +0.029 (n.s.) | +0.080 *** | +0.078 *** |
| col 2 | +0.268 (n.s.) | +0.278 (n.s.) | +0.276 (n.s.) |
| col 3 | +0.747 *** | +0.801 *** | +0.790 *** |
| col 4 | +0.488 *** | +0.503 *** | +0.498 *** |
| **col 5** | **+0.787** *** | **+0.842** *** | **+0.829** *** |
| col 6 | +0.266 (n.s.) | +0.279 (n.s.) | +0.274 (n.s.) |

### Control-group robustness (binary, col 5 FE)

Output: [output/tables/phase3_b2b_cmdj_robustness.csv](output/tables/phase3_b2b_cmdj_robustness.csv).

| Spec | Sample | Phase 3 share | Phase 3 prob |
|---|---|---|---|
| A — vs unreg in ETS | within ETS sellers | **+0.271** *** | **+0.567** *** |
| B — vs non-ETS in reg | within regulated-NACE | -4.76 (SE 3.0) — broken | -2.84 (SE 3.7) — broken |
| **C — full sample** | full | **+0.358** *** | **+0.829** *** |
| D — triple diff | full | **+0.344** *** | **+0.813** *** |

Spec B fails (VCOV not pos. def.) — same pattern as Phase 2's Spec B; the within-regulated-NACE non-ETS subsample is too sparse. Specs A, C, D agree directionally (positive, statistically significant).

### Initial reading

Treated sellers (ETS × regulated-NACE) **gain** within-buyer-NACE share by ~36 percentage points and pair-active probability by ~83 percentage points after 2005. Coefficient signs are the **opposite** of the leakage hypothesis (β < 0 expected). Magnitudes are very large — three times CMdG's France share coefficient — which is the first warning sign.

---

## Results — Continuous-intensity spec (the null + pre-trend violation)

Output: [output/tables/phase3_b2b_cmdj_continuous_phase.csv](output/tables/phase3_b2b_cmdj_continuous_phase.csv), [output/tables/phase3_b2b_cmdj_continuous_eventstudy.csv](output/tables/phase3_b2b_cmdj_continuous_eventstudy.csv).
Figure: [output/figures/phase3_b2b_cmdj_continuous_eventstudy.png](output/figures/phase3_b2b_cmdj_continuous_eventstudy.png).

### Phase-aggregated coefficients

| Phase | col 1 FE (sn4d^year) | col 4 FE (seller^buyer + bn4d^year) | col 5 FE (preferred) |
|---|---|---|---|
| **Pre (2002-04)** | **+32 (SE 17), p = 0.057** | -45 (SE 270), n.s. | -71 (SE 348), n.s. |
| 1 (2005-08) | **+29 (SE 14), p = 0.048** | -39 (SE 270), n.s. | -68 (SE 348), n.s. |
| 2 (2009-12) | +3 (SE 4), n.s. | -40 (SE 270), n.s. | -76 (SE 348), n.s. |
| 3 (2013-19) | -0.5 (SE 1.6), n.s. | -42 (SE 270), n.s. | -76 (SE 348), n.s. |

Three observations:

1. **col 5 (preferred) and col 4 produce SEs of 270-350 — effectively unidentified.** Treatment coefficients differ from each other by 5-10 units within noise of size 350. The pair-level FE absorbs almost all variation in `firm_cost_share` (which is constant within seller).
2. **col 1 has tight SEs** because it doesn't include `seller^buyer` FE — it identifies off cross-pair variation, which is exactly where market-structure / scale variation lives.
3. **In col 1, the pre-period coefficient is +32, identical in size to the Phase 1 coefficient (+29).** Phase 2 and 3 collapse toward zero. **The Phase 1 "effect" cannot be distinguished from the pre-existing trend.**

### Event study (col 5 FE, year-by-year)

```
2002: -0.4 ± 3.9     (pre)
2003: +4.5 ± 2.8     (pre, ≈ same magnitude as Phase 1)
2004:  0             (reference)
2005: +3.9 ± 3.3
2006: +3.6 ± 3.9
2007: +3.3 ± 4.2
2008: +5.6 ± 5.7
2009: +3.3 ± 8.7
2010: -1.0 ± 8.4
2011: -2.4 ± 7.5
2012: -7.4 ± 7.6
2013: -4.3 ± 7.6
2014: -5.5 ± 7.6
2015: -2.5 ± 7.2
2016: -6.4 ± 7.1
2017: -5.6 ± 7.2
2018: -5.7 ± 7.0
2019: -5.8 ± 6.9
```

The pre-period (2003) is +4.5, the same order as Phase 1 (2005-2008 average ≈ +4). Post-2009 the coefficient drifts to -5 to -7 but stays well within sampling noise. **No clean break at 2005.** The pre-existing trajectory continues smoothly through the policy.

---

## Why the binary headline doesn't survive

Three independent pieces of evidence say the binary +0.36 share / +0.83 prob is not measuring an ETS effect:

### 1. Continuous intensity wipes the result

The binary spec treats all 224 ETS sellers as one homogeneous treated group. The continuous spec exploits the fact that some ETS sellers had `firm_cost_share` near 0 (small allocation deficit relative to total cost) while others had cost share above 5%. If ETS-induced supplier displacement were the mechanism, high-cost-share sellers should lose buyer share faster than low-cost-share ones. They don't — within-pair cross-cost-share variation gives effectively zero coefficient (col 5: SE > 348 makes any reading impossible).

The binary +0.36 was therefore not "ETS sellers lost X percentage points relative to non-ETS sellers" but rather "ETS-regulated-NACE Belgian sellers ARE the dominant suppliers in their NACE." When buyer-buyer-pair FE is added (col 5 binary), the effect is huge because the FE doesn't absorb the time-varying within-pair share variation — but that variation is concentrated in pairs where the treated cell happens to dominate baseline.

### 2. Pre-trends fail

In the col 1 continuous spec — the only one with tight SEs — the pre-period coefficient (+32) is statistically indistinguishable from the Phase 1 coefficient (+29). Whatever process drove cost-share-correlated-share-changes in 2002-04 continued through 2005-08. There's nothing distinctive about the post-policy period.

If we extrapolated the pre-trend forward, the entire post-2005 "effect" disappears. The pre-trend is also visible in the event study: 2003 = +4.5, 2005 = +3.9, 2008 = +5.6 — flat through the policy boundary.

### 3. CSS critique applies

The Callaway-Goodman-Bacon-Sant'Anna (NBER WP 32117, 2024) critique of continuous-treatment DiD: under heterogeneous treatment effects, the TWFE coefficient is a weighted average across intensity levels with weights that overweight the modal intensity. In our data, the modal `firm_cost_share` is ≈ 0 (most ETS sellers have tiny exposure), and the variation around 0 is uninformative. The col 1 coefficient is essentially "movement around 0" which doesn't say anything about high-intensity sellers.

Even if we trusted the col 1 coefficient, we couldn't read it as "average causal response per unit intensity" without additional assumptions (monotonicity of dose-response, parallel trends at every intensity level, no compositional drift) that aren't testable.

---

## Cross-section comparison with Phase 2 (cross-border)

| Dimension | Treatment | Phase 3 binary β | Phase 3 continuous β | Interpretation |
|---|---|---|---|---|
| **Cross-border** ([IMPORT_LEAKAGE.md](IMPORT_LEAKAGE.md)) | regulated × non-ETS country | -0.0024 (n.s. or marg negative) | n/a | No leakage to non-ETS countries |
| **Domestic B2B** (this doc) | ETS × regulated-NACE seller | +0.358 *** | -0.5 (n.s.) | Binary inflated by market structure; null when properly identified |

So Belgium shows no leakage in either direction:
- Belgian buyers did not shift toward non-ETS-COUNTRY sources for regulated products (Phase 2).
- Belgian buyers did not (cleanly) shift away from regulated-NACE-ETS BELGIAN sellers (Phase 3 continuous).

The binary +0.36 finding for Phase 3 was real in a descriptive sense (ETS-regulated Belgian sellers ARE more dominant by 2019 than they were in 2005), but the increase coincides with a pre-existing trend and cannot be attributed to ETS treatment.

CMdG France's Section 3 finding (positive cross-border leakage) does NOT generalize to Belgium on either margin.

---

## Caveats

1. **Belgian B2B starts at 2002, not earlier.** We have only 3 pre-treatment years (2002, 2003, 2004). Pre-trend tests are based on a short window. A pre-policy series back to 1995 would let us test parallel trends more powerfully.
2. **Continuous treatment is not the right primary identification strategy** under known DiD critiques (CSS 2024, dCdH). The continuous spec is used here only as a robustness check on the binary spec, and to test pre-trends. For a primary continuous-DiD result we'd need CSS or `did_multiplegt_dyn` aggregation.
3. **Active-pairs-only sample** (continuous spec) ignores extensive-margin responses. Buyers may have stopped sourcing from high-cost-share ETS sellers entirely, which the share regression on active pairs would miss. The probability outcome on a 2002+ balanced panel would address this — currently not built.
4. **`firm_cost_share` uses a fixed 2013-15 window** (Angle 4 convention), so the treatment intensity is anchored to mid-Phase 2. Sellers whose carbon exposure changed materially after 2015 are not captured.
5. **3 contaminated VATs** (NACE 20/24 EUTL artifact post-2020) were NOT dropped from the B2B panel — same logic as Phase 2 (the contamination is in EUTL emissions data, which we use only for the `is_ets_firm` flag here, not for any analytical computation). Their `is_ets_firm` flag remains correctly TRUE.
6. **Spec B (within-regulated-NACE, treat = is_ets) fails to identify** in both binary and continuous versions — same VCOV degeneracy as Phase 2's Spec B. The within-regulated-NACE non-ETS subsample is too sparse.
7. **No CSS / dCdH / staggered DiD robustness** on either binary or continuous. Treatment is not staggered (it's a fixed cell × phase interaction), so negative-weights bias is mechanically zero — but the continuous-DiD critique about weighted averages of heterogeneous effects still applies.

---

## What we did NOT do, and why

1. **Build a 2002+ balanced B2B panel** for the probability/extensive-margin continuous regression. Would require a buyer × seller × year cross-join with substantially more rows than the 2005+ version. Worth doing if Phase 3 ever becomes a load-bearing finding; not needed for the null story.
2. **Tercile heterogeneity** by `firm_cost_share` (low / mid / high vs control). Would let us see whether dose-response is monotonic. Likely null under the same logic as the linear continuous spec.
3. **Extensive-margin Cox / hazard model** for pair separation. CMdG don't run one either; their probability margin is a simple LPM.
4. **Comparison with the existing Angle 4 `phase4_b2b_supplier_switching.R` long-difference design** at horizons 5-7. The Angle 4 spec uses a different baseline year (2015) and different identification (event-study long differences around the MSR decision). That's a separate research question — short-horizon Phase IV reallocation under the post-MSR price spike, not the CMdG Phase 1-3 leakage question. Worth cross-checking when both finalized.

---

## Scripts

| Purpose | Script |
|---|---|
| Build binary-treatment B2B panel (balanced, 2005-2022) | [analysis/phase3_build_b2b_cmdj_panel.R](analysis/phase3_build_b2b_cmdj_panel.R) |
| Binary diff-in-diff: 6 FE columns + 4-spec robustness | [analysis/phase3_b2b_cmdj_did.R](analysis/phase3_b2b_cmdj_did.R) |
| Binary event study (col 5 FE, ref = 2005) | [analysis/phase3_b2b_cmdj_eventstudy.R](analysis/phase3_b2b_cmdj_eventstudy.R) |
| Continuous-intensity regression + event study (active pairs, 2002-2019, pre-period included) | [analysis/phase3_b2b_cmdj_did_continuous.R](analysis/phase3_b2b_cmdj_did_continuous.R) |
| One-click runner for the binary pipeline | [analysis/phase3_run_all.R](analysis/phase3_run_all.R) |

## Outputs

### Tables
- [output/tables/phase3_b2b_cmdj_table_A.csv](output/tables/phase3_b2b_cmdj_table_A.csv) — binary, 6 FE × share.
- [output/tables/phase3_b2b_cmdj_table_B.csv](output/tables/phase3_b2b_cmdj_table_B.csv) — binary, 6 FE × probability.
- [output/tables/phase3_b2b_cmdj_robustness.csv](output/tables/phase3_b2b_cmdj_robustness.csv) — binary, 4 control-group specs × 2 panels × 3 phases.
- [output/tables/phase3_b2b_cmdj_eventstudy.csv](output/tables/phase3_b2b_cmdj_eventstudy.csv) — binary event study, 2005-2019.
- [output/tables/phase3_b2b_cmdj_continuous_phase.csv](output/tables/phase3_b2b_cmdj_continuous_phase.csv) — continuous, phase-aggregated, 3 FE specs.
- [output/tables/phase3_b2b_cmdj_continuous_eventstudy.csv](output/tables/phase3_b2b_cmdj_continuous_eventstudy.csv) — continuous event study, 2002-2019.

### Figures
- [output/figures/phase3_b2b_cmdj_eventstudy.png](output/figures/phase3_b2b_cmdj_eventstudy.png) — binary event study, two-panel.
- [output/figures/phase3_b2b_cmdj_continuous_eventstudy.png](output/figures/phase3_b2b_cmdj_continuous_eventstudy.png) — continuous event study, share only.

### Working artifacts
- `${PROC_DATA}/b2b_cmdj_panel.RData` — built binary B2B panel (RMD only, 2005-2022 balanced).

---

## What this means for the project

Combined with [IMPORT_LEAKAGE.md](IMPORT_LEAKAGE.md):

**Belgium does not exhibit measurable carbon leakage at the firm-import-flows level under any cleanly identified specification.** The cross-border channel (CMdG's France finding) is null. The domestic B2B channel — the novel research question that France can't answer — initially looked positive in the wrong direction (consolidation toward ETS sellers, not away) but does not survive the continuous-intensity test or pre-trend diagnostics.

Two ways to read this:

1. **Substantively:** Belgium is too small, too EU-integrated, and too concentrated in chemicals exporters for the cross-border-leakage mechanism CMdG document for France to operate. Domestically, ETS-regulated firms are the structural supply backbone — buyers had no realistic alternatives within Belgium, regardless of cost-share intensity. The post-2005 "consolidation" reflects pre-existing market structure dynamics that pre-date and survive the policy.
2. **Methodologically:** Belgian B2B + customs panels are too small to distinguish leakage from market-structure effects at the firm level. CMdG's identification depends on French-style firm count (27k vs Belgium's ~3-5k). Smaller economies need different identification strategies (country panels, structural models, or larger pooled samples).

---

*Last revision: 2026-04-27. Authored after Phase 3 RMD execution of `phase3_b2b_cmdj_did.R`, `phase3_b2b_cmdj_eventstudy.R`, and `phase3_b2b_cmdj_did_continuous.R`.*
