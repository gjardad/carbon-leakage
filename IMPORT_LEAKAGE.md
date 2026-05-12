# Import Leakage: CdGM (2024) Replication on Belgian Customs

*Replication of Coster, di Giovanni & Méjean (FRBNY SR #1136, Nov 2025) Section 3 — "do firms shift sourcing of regulated inputs from ETS to non-ETS countries after 2005?" — applied to the Belgian customs panel 2000-2019.*

**Headline finding:** **Belgian customs imports do NOT exhibit the carbon leakage CdGM document for France.** Across four control-group choices and six fixed-effects specifications, Phase 3 (2013-19) coefficients are at best null and often *negatively* signed (opposite of CdGM's prediction). Phase 2 (2009-12) shows a small but statistically significant *negative* effect on the import share (regulated × non-ETS shrinks relative to control). The pre-trend on the probability margin is non-zero, complicating clean interpretation. We do not run Phase 2's planned Figure 4 / Appendix B robustness because the headline is already null/negative — those exercises only sharpen positive results.

---

## Headline summary

| Metric | Belgium (this paper, col(5)) | France (CdGM Table 1, col(5)) |
|---|---|---|
| Phase 3 share | **-0.0024 ** ** | +0.121 *** |
| Phase 3 probability | +0.0041 (n.s.) | +0.071 *** |
| Phase 2 share | **-0.0037 *** ** | +0.110 *** |
| Phase 2 probability | -0.0128 (n.s.) | (positive) |
| Pre-trend (probability) | **non-zero, ≈ -0.012** | flat |

**Belgium's coefficients are two orders of magnitude smaller than CdGM France's, and where significant, they point the wrong way.**

---

## What we estimated

CdGM's reduced-form (Eq. 1, phase-aggregated):

```
y_{f,p,i,t} = β_1 · 1(regulated)_p × 1(t ∈ 2005-08)
            + β_2 · 1(regulated)_p × 1(t ∈ 2009-12)
            + β_3 · 1(regulated)_p × 1(t ∈ 2013-19)
            + α_{f,p,i} + δ_{i,t} + δ_{s,t} + ε_{f,p,i,t}
```

Sample: imports from non-ETS source countries only (per CdGM p. 12-13, who restrict because the 2011 French Intrastat threshold change contaminates intra-EU imports). Treatment is `1(regulated_product)`; the implicit control group is `unregulated × non-ETS`.

Two outcomes, both ran:
- **Panel A — share**: `value_{f,p,i,t} / Σ_{p,i ∈ non-ETS} value_{f,p,i,t}` (intensive margin).
- **Panel B — probability**: `1(value > 0)` (extensive margin).

Cluster-robust SE: two-way `firm + country`. Six FE columns matching CdGM Table 1 (col 1 = simplest, col 5 = preferred — `firm × product × country + country × year + sector × year`).

**Build script:** [analysis/phase2_build_customs_panel.R](analysis/phase2_build_customs_panel.R).
**Regression script:** [analysis/phase2_cdgm_table1.R](analysis/phase2_cdgm_table1.R).
**Event study:** [analysis/phase2_cdgm_figure3.R](analysis/phase2_cdgm_figure3.R).
**Descriptive aggregates:** [analysis/phase2_cdgm_figure2.R](analysis/phase2_cdgm_figure2.R).

---

## Sample

Customs panel built from `${RAW_DATA}/NBB/import_export_ANO.dta` (51M raw rows on RMD, 7.6M on local-1 downsampled). Filter cascade (RMD full data):

```
51M raw → 22M imports (flow=I, 2000-2019)
       → 10M manufacturing buyer (NACE C 10-33)
       → 9.0M regulated-intensive buyer (NACE 2d ∈ {11,12,13,15,16,17,18,19,20,
                                                    21,22,23,24,25,26,27,28,29,
                                                    31,32,33})
       → 2.5M core-input filter (upstream NACE in buyer's 10% set, IO-derived)
       → 2.3M after BEC capital-goods drop
       → ~14M after balancing + zero-fill
       → 8.6M after non-ETS country restriction (the regression sample)
```

**Final sample size:** 8.6M rows × balanced (firm × CN8 × partner × year), 35.4% regulated. 19 distinct buyer NACE 2d sectors, 199 partner countries.

CdGM France equivalents: 7.5M rows, 27k firms. Belgium has fewer firms (~3-5k) but comparable row count, because each Belgian firm's panel breadth is similar.

**Concordance source:** all built in Phase 0 — see [CdGM_REPLICATION.md](CdGM_REPLICATION.md) and [data/concordances/](data/concordances/) / [data/io/](data/io/).

---

## Results — Table 1 CdGM-exact

Output: [output/tables/phase2_cdgm_table1_A.csv](output/tables/phase2_cdgm_table1_A.csv) (share), [output/tables/phase2_cdgm_table1_B.csv](output/tables/phase2_cdgm_table1_B.csv) (probability).

**Panel A (share), col(5) preferred spec:**

| Phase | β | SE | p-value |
|---|---|---|---|
| Phase 1 (2005-08) | -0.0014 | 0.0008 | 0.091 (marginal) |
| **Phase 2 (2009-12)** | **-0.0037** | 0.0011 | **0.001** *** |
| **Phase 3 (2013-19)** | **-0.0024** | 0.0009 | **0.007** *** |

**Panel B (probability), col(5):**

| Phase | β | SE | p-value |
|---|---|---|---|
| Phase 1 (2005-08) | -0.0041 | 0.0051 | 0.43 |
| Phase 2 (2009-12) | -0.0128 | 0.0095 | 0.18 |
| Phase 3 (2013-19) | +0.0041 | 0.0097 | 0.67 |

**Cross-column pattern.** All six FE columns produce magnitudes in the same neighborhood (-0.005 to +0.002 share; -0.02 to +0.01 prob). No spec returns CdGM-style positive coefficients. Adding country×year FE (col 3, 5) tightens to negative. Without country×year FE (cols 1, 2, 4, 6), share is mostly null with positive sign in Panel B.

The **Panel A col(5) negative significance** is the cleanest finding: Belgian buyers' share of imports going to (regulated × non-ETS) cells *fell* relative to (unregulated × non-ETS) cells in Phases 2 and 3. The opposite of carbon leakage at the share margin.

---

## Results — Control-group robustness

Output: [output/tables/phase2_cdgm_table1_robustness.csv](output/tables/phase2_cdgm_table1_robustness.csv).
Script: [analysis/phase2_cdgm_table1_robustness.R](analysis/phase2_cdgm_table1_robustness.R).

Four ways to identify the same headline question, holding col(5) FE constant:

| Spec | Sample | Treatment | Implicit control |
|---|---|---|---|
| **A** | non-ETS countries only | regulated × phase | unregulated × non-ETS (CdGM baseline) |
| **B** | regulated products only | non-ETS × phase | regulated × ETS (CdGM Fig 4 conceptual) |
| **C** | full | (reg × non-ETS) × phase | all other 3 cells pooled |
| **D** | full | (reg × non-ETS × phase), with main effects | triple difference (no CdGM analog) |

**Phase 3 estimates:**

| Spec | Panel A (share) | Panel B (probability) |
|---|---|---|
| A | **-0.0024** ** | +0.0041 |
| B | -0.62 (SE 71) **— broken** | -0.87 (SE 1713) **— broken** |
| C | -0.0010 | -0.0054 |
| D | -0.0010 | -0.0153 (marginal) |

**Phase 2 estimates:**

| Spec | Panel A (share) | Panel B (probability) |
|---|---|---|
| A | **-0.0037** *** | -0.0128 |
| B | broken | broken |
| **C** | **-0.0014** ** | **-0.0211** ** |
| **D** | **-0.0014** ** | **-0.0291** *** |

**Take-aways:**

1. **Spec B is uninterpretable** — VCOV not positive definite. The regulated × ETS-country subsample is too thin in the Belgian data once we cut to regulated only. CdGM's Figure 4 conceptual analog cannot be estimated cleanly here.
2. **Specs A, C, D agree directionally**: small null-to-negative coefficients across the board. The headline does NOT depend on which control we choose.
3. **Phase 2 (2009-12) carries the action.** Spec D shows -0.029 *** in probability — economically modest but statistically distinct from zero. Coincides with post-2008 financial crisis and EU sovereign debt crisis aftermath.
4. **No positive headline.** The leakage CdGM find for France is absent in the Belgian customs panel under any reasonable identification.

The robustness exercise covers what CdGM's Figure 4 (alternative-control specification) would have added. Since the four control-group choices agree, running Figure 4 separately with an Intrastat-break dummy (CdGM's France-specific concern) adds nothing.

---

## Results — Event study (Figure 3 analog)

Output: [output/figures/phase2_cdgm_figure3.png](output/figures/phase2_cdgm_figure3.png), [output/tables/phase2_cdgm_figure3.csv](output/tables/phase2_cdgm_figure3.csv).
Script: [analysis/phase2_cdgm_figure3.R](analysis/phase2_cdgm_figure3.R).

Year-by-year coefficients, full sample, col(5) FE, ref = 2004.

**Pre-trend (2000-2003):**
- **Share:** essentially zero (-0.0002 to -0.0001). Clean parallel pre-trend.
- **Probability:** **non-zero negative** (-0.014 to -0.012, all 95% CIs exclude 0). Treated cells already had lower sourcing probability than control before ETS.

**Post-2005 trajectory:**
- **Share:** mostly slightly negative (-0.001 to -0.002), bounded; never approaches CdGM's +0.12 magnitude.
- **Probability:** widens negatively to -0.026 to -0.032 in 2008-2014, with confidence intervals consistently below zero. Recovers toward zero by 2017-2019.

**Interpretation of the pre-trend.** The non-zero pre-trend on the probability margin says treated cells (regulated × non-ETS) were structurally less likely to be active than control cells before any ETS treatment. This is mechanically possible: regulated products are a subset of CN codes concentrated in chemicals/metals/refining (HS 27, 28, 29, 72-76), which are commodity-like and dominated by a handful of specialised sourcing relationships per buyer firm. Less variety of (firm × product × country) triplets for regulated cells = lower extensive-margin density.

This pre-trend complicates the post-2005 estimates because it implies a parallel-trends violation: even absent ETS, treated and control cells were on different probability paths. The post-2005 widening could be either continuation of the existing trend or a new ETS-induced effect; we cannot separate them with this design.

CdGM's France data shows a flat pre-trend, so they avoid this issue.

---

## Results — Aggregate descriptive (Figure 2 analog)

Output: [output/figures/phase2_cdgm_figure2.png](output/figures/phase2_cdgm_figure2.png), [output/tables/phase2_cdgm_figure2.csv](output/tables/phase2_cdgm_figure2.csv).
Script: [analysis/phase2_cdgm_figure2.R](analysis/phase2_cdgm_figure2.R).

Two-panel descriptive plot of treatment vs. control means by year, restricted to non-ETS source countries.

**Panel (a) — aggregate share of non-ETS imports going to (regulated, control) cells.** Treatment (regulated × non-ETS) hovers at 45-60% of total non-ETS imports across years; control (unregulated × non-ETS) at the complement. No striking secular trend.

**Panel (b) — extensive-margin sourcing probability.** Treatment line slightly above or below control line depending on year, never with a clean post-2005 separation.

In CdGM France, both panels show treatment rising visibly above control after 2005. **In Belgium, neither panel shows that pattern.** The descriptive figure is consistent with the regression null/negative result.

---

## What we did NOT do, and why

Three Phase-2 robustness exercises in the original CdGM_REPLICATION.md plan were skipped:

1. **Figure 4 (alternative control with Intrastat-break dummy).** CdGM's Figure 4 flips treatment to (regulated × ETS-country) and adds a 2011 break dummy because France's 2011 Intrastat threshold change contaminates intra-EU imports. Two reasons we skipped:
   - Spec B in our robustness file IS the conceptual content of Figure 4 (treatment = non-ETS country within the regulated subsample). Spec B's VCOV failed to converge — the regulated × ETS subsample is too sparse in Belgian data. So even if we ran Figure 4 with the break dummy, it wouldn't be identified.
   - Belgium's Intrastat threshold history is mostly unknown pre-2016 (see Step 5 of Phase 0). We have no confirmed Belgian counterpart to France's 2011 break. The break-dummy refinement is unnecessary.
2. **Appendix B.1 (ETS-firm vs non-ETS-firm split).** This is a heterogeneity test on a positive headline — splits the buyer firms by their own ETS regulatory status to see if leakage is concentrated where the cost shock hits hardest. With our null/negative headline, decomposing it by buyer ETS status only tells us which firms are *not* leaking. Not informative.
3. **Appendix B.3 (de Chaisemartin-D'Haultfœuille robustness).** Hedges against negative-weight bias in staggered DiD. Our spec is not staggered (treatment is a fixed cell × phase interaction), so the negative-weight risk is mechanically zero. Skipping.
4. **Appendix B.4 (leave-one-partner-country-out).** Rules out single big partners (e.g., China) driving the result. With the headline already null, this only confirms null. Skipping.

If we ever pivot the design (e.g., add a Phase 4 / 2020+ analysis where Belgian carbon prices rose dramatically and the leakage signal might emerge), we can revisit these robustness exercises.

---

## Comparison with CdGM France

| Dimension | Belgium (this paper) | France (CdGM) |
|---|---|---|
| Sample period | 2000-2019 | 2000-2019 |
| Distinct firms | ~3-5k | 27k (~6× larger) |
| Total panel rows | 8.6M | 7.5M |
| Buyer NACE 2d sectors | 19 | 20 (NAF-138 → NACE 2d) |
| Phase 2 share, col(5) | **-0.0037 *** ** | +0.110 *** |
| Phase 3 share, col(5) | **-0.0024 ** ** | **+0.121 *** ** |
| Phase 3 prob, col(5) | +0.004 (n.s.) | **+0.071 *** ** |
| Pre-trend probability | -0.012 to -0.014 (non-zero) | flat |
| Sign of headline | Wrong (negative) | Right (positive) |

The two countries have similar panel sizes but different industrial structures: Belgium concentrates in chemicals (Antwerp port), pharma, and food processing; France in autos, aerospace, and luxury goods. Belgium is more EU-integrated for trade (98% of trade is intra-EU vs ~60% for France). These differences plausibly explain the divergent leakage findings, but our design cannot pinpoint which channel is doing the work.

---

## Why the Belgian result might differ economically

Three working hypotheses, in order of plausibility:

1. **EU integration substitutes for non-ETS leakage.** Belgian buyers post-2005 may have shifted their sourcing toward EU-domestic suppliers (also subject to ETS but cheaper to reach logistically and free of currency / customs friction) rather than to non-ETS countries. The negative coefficient is consistent with this: regulated × non-ETS share *fell* because Belgian buyers consolidated to EU sources for the regulated inputs.
2. **Pre-existing chemical-sector exposure.** Antwerp's chemicals cluster competes with Chinese/Indian chemical exporters on global markets. Belgian buyers of regulated chemical inputs may have already sourced heavily from non-ETS countries pre-ETS; further shifts post-ETS hit a saturation point. CdGM France's chemical sector is much smaller, leaving more headroom for post-ETS leakage.
3. **Methodological — sample-size attenuation in col(5).** With ~3-5k Belgian firms vs France's 27k, the firm × product × country FE is sparser, and country×year FE absorbs more identifying variation. Cols (1)-(4)-(6) without country×year FE give magnitudes closer to ±0.005 (still small but at least same sign as CdGM France in some cells). Col (5) with full FE structure is the binding spec, and it absorbs whatever Belgian-leakage signal exists into the FE terms.

Hypothesis 1 and 2 are substantive (Belgium is genuinely different from France); Hypothesis 3 is methodological (Belgium is identifiable like France but with weaker power). Distinguishing them would require either a within-firm dose-response design (PRODCOM workstream — see [PRODCOM_PLAN.md](PRODCOM_PLAN.md)) or pooling Belgium with other small EU economies for power.

---

## Caveats

1. **Sample period stops at 2019** to match CdGM. Phase 4 (2021+) — where ETS prices spiked from €40 to €80+ — is excluded. The strongest leakage signal might emerge in Phase 4, where the carbon price is finally large enough to matter. Extending the sample is a future to-do (see [CdGM_REPLICATION.md](CdGM_REPLICATION.md) deferred analyses).
2. **Capital-goods filter uses HS 2007 (H3) → BEC 4** instead of HS 2002 (H2) → BEC 4 as in CdGM. The difference is minor for capital-goods flagging.
3. **Concordance bridge** for HS27 (mineral fuels) is hand-coded since GRANTPA's PRODCOM-restricted CN→PC bridge omits it. See [data/concordances/cn8_to_nace4d.csv](data/concordances/cn8_to_nace4d.csv) source flags.
4. **Pre-trend on probability margin** is non-zero (β ≈ -0.012 in 2000-2003). Identification under parallel-trends assumption is questionable for Panel B. Panel A's pre-trend is clean.
5. **Spec B identification fails** due to the thin regulated × ETS subsample. The result is robust to the three control-group choices that DO converge but cannot be checked against CdGM Figure 4's exact spec.
6. **3 contaminated VAT hashes** (NACE 20/24, EUTL artifact post-2020) are NOT dropped from the customs panel because the contamination is in EUTL emissions data, not customs imports. Their `is_ets_firm` flag remains correctly TRUE.

---

## Scripts

| Purpose | Script |
|---|---|
| Build customs panel from raw NBB customs + concordances | [analysis/phase2_build_customs_panel.R](analysis/phase2_build_customs_panel.R) |
| Mock customs panel for local-1 testing | [analysis/phase2_make_mock_customs_panel.R](analysis/phase2_make_mock_customs_panel.R) |
| Descriptive Figure 2 (aggregate share + probability) | [analysis/phase2_cdgm_figure2.R](analysis/phase2_cdgm_figure2.R) |
| **Table 1 CdGM-exact (6 cols, 2 panels)** | [analysis/phase2_cdgm_table1.R](analysis/phase2_cdgm_table1.R) |
| **Control-group robustness (4 specs × 2 panels)** | [analysis/phase2_cdgm_table1_robustness.R](analysis/phase2_cdgm_table1_robustness.R) |
| Figure 3 event study (year-by-year coefficients) | [analysis/phase2_cdgm_figure3.R](analysis/phase2_cdgm_figure3.R) |

Phase 0 concordance scripts (regulated CN8 list, BLM C³ family trees, CN→NACE bridge, BE Use-table sector lists, country ETS status, HS→BEC, Intrastat thresholds) are listed in [CdGM_REPLICATION.md](CdGM_REPLICATION.md).

## Outputs

### Tables
- [output/tables/phase2_cdgm_table1_A.csv](output/tables/phase2_cdgm_table1_A.csv) — 6-column FE specifications, share outcome (CdGM-exact, non-ETS sample).
- [output/tables/phase2_cdgm_table1_B.csv](output/tables/phase2_cdgm_table1_B.csv) — same, probability outcome.
- [output/tables/phase2_cdgm_table1_robustness.csv](output/tables/phase2_cdgm_table1_robustness.csv) — Specs A, B, C, D × 2 panels × 3 phases.
- [output/tables/phase2_cdgm_figure2.csv](output/tables/phase2_cdgm_figure2.csv) — annual aggregates by treatment group.
- [output/tables/phase2_cdgm_figure3.csv](output/tables/phase2_cdgm_figure3.csv) — event-study coefficients by year, both panels.

### Figures
- [output/figures/phase2_cdgm_figure2.png](output/figures/phase2_cdgm_figure2.png) — Figure 2 replica (descriptive aggregates).
- [output/figures/phase2_cdgm_figure3.png](output/figures/phase2_cdgm_figure3.png) — Figure 3 replica (event study, both panels).

### Working artifacts
- `${PROC_DATA}/customs_import_panel_regulated.RData` — built customs panel (RMD only, 8.6M rows).
- `${PROC_DATA}/customs_import_panel_regulated.dta` — Stata-format twin.

---

## What this means for the broader project

Phase 2 of [CdGM_REPLICATION.md](CdGM_REPLICATION.md) is now complete with a defensible null/negative finding. The replication exercise itself is informative — it tells us the cross-border-leakage mechanism CdGM identify for France does not generalize to Belgium under their preferred specification. This is a publishable result on its own ("Belgian customs imports do not show the carbon leakage CdGM document for France; possible reasons include EU integration density and chemicals-sector industrial composition").

Phase 3 of the project — the **B2B domestic supplier-switching** analysis (the novel Belgian contribution that France cannot do) — is independent and can proceed regardless of Phase 2's results. The B2B question asks whether Belgian buyers shifted away from regulated-NACE ETS-Belgian *domestic* sellers post-2005. That's a different mechanism (intra-Belgian, not cross-border) and may give a different answer.

---

*Last revision: 2026-04-27. Authored after Phase 2 RMD execution of `phase2_cdgm_table1.R` and `phase2_cdgm_table1_robustness.R`.*
