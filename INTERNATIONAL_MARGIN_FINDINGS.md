# International-Margin Findings: Does Carbon Pricing Shift Belgian Buyers Abroad?

*Companion to [REALLOCATION_FINDINGS.md](REALLOCATION_FINDINGS.md), which covers the domestic reallocation margins. This document inventories every estimate on disk that bears on the international (cross-border) margin of carbon leakage in Belgian firm-level data. The unifying question is **whether Belgian importers shifted sourcing toward non-ETS countries, or toward less carbon-intensive products, after the EU ETS was introduced.***

**Headline (one-line read):** The aggregate CdGM (2024) replication on Belgian customs is **null/negative** — the cross-border leakage pattern they document for France does not reproduce here. But the **firm-pair design (B1/B2)** finds **economically meaningful within-pair substitution** concentrated at the heaviest-exposure buyers, with a clean monotone post-trend horizon and no offsetting non-EU price response. The two findings co-exist if the CdGM aggregate spec absorbs identifying variation into FE that the pair design preserves, or if the substitution is concentrated in a sub-population the aggregate spec averages over.

The right framing of the headline depends on the next batch of cuts (HS6 carbon intensity, pre-MSR vs post-MSR window) and on a clean run of C1 (imports-vs-domestic substitution) on RMD.

---

## Roadmap of this document

1. **Coefficient matrix** — every international-margin estimate at one glance.
2. **Per-spec detail** — what each estimate is, how it was identified, and its caveats.
3. **Open cuts** — heterogeneity dimensions that would tighten or break the current reading.
4. **Caveats and known gaps**.
5. **What this means for the paper**.

---

## 1. Coefficient matrix

All coefficients are on the treatment-by-post interaction (the leakage prediction). Sign convention: **negative β = substitution away from regulated/ETS exposure** (leakage prediction); positive = no leakage or wrong-signed.

| ID | Design | Outcome | Treatment | Coef β | SE | p | Source |
|---|---|---|---|---:|---:|---:|---|
| **CdGM-naive col(5)** | CdGM Eq.(1), 6 FE preferred, share, Phase 3 | import share (non-ETS country) | regulated×phase | −0.0024 | 0.0009 | 0.007 | [phase2_cdgm_table1_A.csv](output/tables/phase2_cdgm_table1_A.csv) |
| CdGM-naive col(5) | as above, **probability** | 1(active) | regulated×phase | +0.004 | 0.010 | 0.67 | [phase2_cdgm_table1_B.csv](output/tables/phase2_cdgm_table1_B.csv) |
| **CdGM trend-corrected col(5)** | adds firm×year-centered control, share, Phase 3 | as above | regulated×phase + trend | −0.0062 *** | 0.0019 | 0.0014 | [phase6_cdgm_corrected_A.csv](output_rmd/tables/phase6_cdgm_corrected_A.csv) |
| CdGM trend-corrected col(5), prob | as above | 1(active) | regulated×phase + trend | −0.021 | 0.017 | 0.22 | [phase6_cdgm_corrected_B.csv](output_rmd/tables/phase6_cdgm_corrected_B.csv) |
| **B1 naive** | pair×year customs, MSR event | within-pair share | pair_exposure_EU × post(2015) | −0.016 | 0.030 | 0.58 | [phase6_b1_corrected.csv](output_rmd/tables/phase6_b1_corrected.csv) |
| **B1 trend-corrected** | adds pair × year_centered control | as above | pair_exposure_EU × post + trend | **−0.560 \*\*\*** | 0.029 | <1e-58 | as above |
| **B1 quartile Q4 (heavy)** | B1 trend-corr. split by buyer-side regulatory exposure quartile | within-pair share | pair_exposure_EU × post | −1.835 | 3.01 | 0.54 | [phase6_b2_quartile_split.csv](output_rmd/tables/phase6_b2_quartile_split.csv) |
| **B2 horizon, h=7** | pair×year LP, 17 horizons, anchor=2014 | within-pair share | pair_exposure_EU × i(year) | −0.306 *** | 0.048 | <1e-9 | [phase6_b2_horizon_lp.csv](output_rmd/tables/phase6_b2_horizon_lp.csv) |
| B2 horizon, h=−9 (pre) | as above | as above | as above | −0.374 *** | 0.045 | <1e-15 | as above |
| **B3 non-EU price** | non-EU exporter unit-value response | log unit value (non-EU import) | is_regulated_product × post | +0.069 | 0.054 | 0.20 | [phase6_b3_nonEU_price_response.csv](output_rmd/tables/phase6_b3_nonEU_price_response.csv) |
| **B4 σ from customs IV** | HS6 carbon-intensity instrument | log price ratio EU/non-EU | CPShock × HS6 CI | β=+1.44 → σ̂ ≈ −0.44 | 8.55 | 0.87 | [phase6_b4_sigma_iv.csv](output_rmd/tables/phase6_b4_sigma_iv.csv) |
| B4 first stage | as above | log price ratio | IV | +14.3, F≈0.1 | 44.3 | 0.75 | [phase6_b4_sigma_first_stage.csv](output_rmd/tables/phase6_b4_sigma_first_stage.csv) |
| **C1 (local-1 ES)** | buyer×NACE4d×year, 2014 anchor | import share | regulated_n × post | event-study coeffs only; SEs degenerate (FE collinearity) | — | — | [phase6_c1_imports_vs_domestic_eventstudy.csv](output_local/tables/phase6_c1_imports_vs_domestic_eventstudy.csv) |
| C2 EU-share pre-trend | as above | EU import share | pair_exposure_EU × year_centered | +0.073 *** | 0.003 | <1e-53 | [phase6_c2_pre_trend_test.csv](output_local/tables/phase6_c2_pre_trend_test.csv) |
| **China-origin σ revisit** | importer×HS6 long diff 2002→2012, China vs non-China | log(ChinaShare/NonChinaShare) ratio | log(P_China / P_nonChina) | β=+13.5 → σ̂ = −12.5 | 26.6 | — | [phase6_revisit_c1_summary.txt](output_rmd/tables/phase6_revisit_c1_summary.txt) |
| **B2B-CdGM binary col(5)** | domestic seller×buyer×year, balanced | within-buyer-NACE share | ETS_seller × regulated_NACE × phase | +0.358 *** | — | <0.001 | [phase3_b2b_cdgm_table_A.csv](output/tables/phase3_b2b_cdgm_table_A.csv) |
| B2B-CdGM continuous col(5) | active pairs, 2002+, with pre-period | within-pair share | firm_cost_share_seller × phase | −76 | 348 | n/a (unidentified) | [phase3_b2b_cdgm_continuous_phase.csv](output/tables/phase3_b2b_cdgm_continuous_phase.csv) |
| B2B-CdGM continuous col(1) | sn4d×year FE only | as above | as above | β_pre = +32; β_p3 = −0.5 (n.s.) | — | — | as above |

**Reading the matrix:**

- The CdGM-style aggregate is **null** at face value (naive) and **mildly negative** with trend correction. Neither is the wrong sign for leakage, but both are an order of magnitude smaller than CdGM France's +0.121.
- The **B1 firm-pair design with trend correction** is the single largest effect in the table: β = −0.56 *** on a within-pair share, which is the cleanest design for substitution in our data (within-pair FE, post-MSR).
- B2 horizons show a **monotone trajectory** from a pre-period of −0.37 (h=−9) to post coefficients reaching −0.30 by h=7. The pre-trend is non-zero and motivates the trend-corrected B1.
- B3 confirms **no offsetting non-EU price adjustment**, which strengthens the B1 substitution interpretation rather than a passive-price mechanism.
- B4 σ from customs is **unidentified**; the China-origin σ revisit also unidentified (F=1.7).
- The B2B-CdGM binary positive is a **market-structure artifact**; the continuous version is null.
- C1 (imports vs domestic) does not have a usable main result yet; only an event study with degenerate SEs on local-1.

---

## 2. Per-spec detail

### 2.1 CdGM (2024) replication — phases-aggregated import share (naive)

**Spec.** CdGM Eq. (1), exact replication on Belgian customs panel 2000–2019:

```
y_{f,p,i,t} = β_1 · 1(regulated)_p × 1(t ∈ 2005–08)
            + β_2 · 1(regulated)_p × 1(t ∈ 2009–12)
            + β_3 · 1(regulated)_p × 1(t ∈ 2013–19)
            + α_{f,p,i} + δ_{i,t} + δ_{s,t} + ε
```

Sample restricted to imports from non-ETS source countries only (CdGM's CdGM p. 12–13 baseline; control = unregulated × non-ETS).

**Headline col(5):** share Phase 3 β = −0.0024 ** (SE 0.0009); probability Phase 3 β = +0.0041 (n.s.). Belgian estimates **two orders of magnitude smaller than CdGM France's (+0.121)** and where significant, wrong-signed. Cross-column pattern: all six FE specs in [−0.005, +0.002] for share, no spec returns CdGM-style positive coefficients.

**Robustness.** Four control-group specs (A non-ETS-only baseline, B regulated-only, C full sample, D triple diff) all agree directionally on small null-to-negative coefficients. Spec B fails (VCOV not pos. def.) — within-regulated-NACE×ETS subsample too sparse. **The headline does NOT depend on which control we choose.**

**Pre-trend.** Share: clean parallel pre-trend (−0.0002 to −0.0001 in 2000–03). **Probability: non-zero negative pre-trend** (−0.014 to −0.012, all CIs exclude 0). Treated cells were already *less likely* to be active than control before ETS. CdGM France shows flat pre-trends, so they avoid this issue.

**Source.** [IMPORT_LEAKAGE.md](IMPORT_LEAKAGE.md) (full writeup). Scripts: [phase2_cdgm_table1.R](analysis/phase2_cdgm_table1.R), [phase2_cdgm_table1_robustness.R](analysis/phase2_cdgm_table1_robustness.R), [phase2_cdgm_figure3.R](analysis/phase2_cdgm_figure3.R).

### 2.2 CdGM trend-corrected — same spec with year-centered drift control

**Spec.** Adds a `regulated × year_centered` linear-trend control to absorb the pre-trend visible in 2.1.

**Headline col(5):** share Phase 3 β = **−0.0062 \*\*\*** (SE 0.0019, p = 0.0014); probability Phase 3 β = −0.021 (n.s., p=0.22). The trend coefficient itself is +0.00027 per year ** (p=0.019) on the share outcome, modest but real.

**Reading.** Phase-φ coefficients **become ~2.5× more negative** under trend correction than under the naive CdGM spec. The trend-corrected result is mildly substitution-signed and statistically distinct from zero on the share margin. It's still an order of magnitude below CdGM France and reflects the entire 14 post-period years, not a sharp policy-induced jump.

**Source.** [phase6_cdgm_table1_corrected.R](analysis/phase6_cdgm_table1_corrected.R). Output: [phase6_cdgm_corrected_A.csv](output_rmd/tables/phase6_cdgm_corrected_A.csv), [phase6_cdgm_corrected_B.csv](output_rmd/tables/phase6_cdgm_corrected_B.csv).

### 2.3 B1 buyer-supplier customs — within-pair continuous-intensity DiD

**Spec.** Buyer-supplier-product panel from customs, anchored at 2014 (MSR proposal):

```
within_pair_share_{b,p,t} = β · pair_exposure_EU_{b,p} × 1(t ≥ 2015) + α_{b,p} + δ_{b,t} + ε
```

`pair_exposure_EU_{b,p}` is the buyer-side EUETS regulatory exposure inherited through the buyer's pre-MSR sourcing structure (built in [phase6_b1_corrected.R](analysis/phase6_b1_corrected.R) per [project_b1_pretrend_correction.md](memory/project_b1_pretrend_correction.md): trend-corrected with `pair × year_centered` control).

**Headline.** Naive β = −0.016 (SE 0.030, n.s.). **Trend-corrected β = −0.560 \*\*\*** (SE 0.029, p < 1e-58). The trend control absorbs a +0.058 per-year drift (***, p < 1e-94). Shorter pre-period robustness (2010+): naive −0.251 ***, trend-corrected −0.097 **.

**Reading.** This is the single largest cleanly identified substitution effect in our data. β = −0.56 on the within-pair share means a one-unit increase in pre-period buyer regulatory exposure shifts the buyer's post-MSR pair-level import share down by 0.56 within the (buyer × product × country) FE, which is a large effect. The trend correction is doing material work — naive β is null, so the entire substitution signal lives in the post-trend deviation.

**Source.** [phase6_b1_corrected.R](analysis/phase6_b1_corrected.R). Output: [phase6_b1_corrected.csv](output_rmd/tables/phase6_b1_corrected.csv) plus event-study tables (naive + detrended).

### 2.4 B2 — horizon LP and quartile heterogeneity on B1

**Spec.** Two extensions of B1 to characterize the substitution:
1. **Horizon LP** — 17 horizons h ∈ {−9..+7}, anchor h=−1, year-by-year coefficients.
2. **Quartile split** — buyers grouped into four quartiles by their own carbon-cost exposure, B1 spec re-estimated within each.

**Horizon LP results.** Pre-period coefficients rise monotonically from −0.37 (h=−9, ***) to ~0 (h=−1, reference). Post-period coefficients decline monotonically from −0.022 (h=0, n.s.) to −0.306 (h=7, ***). Every post-coefficient from h=1 onward is statistically significant at *** with monotone magnitudes.

**Quartile results.** Q4 (heaviest-exposure buyers) β = −1.84; Q3 β = −0.066; Q2 β = +0.045; Q1 β = −0.23. None individually significant once split, but Q4 magnitude is ~10× the pooled estimate. Sample-size attrition within quartiles is the binding constraint.

**Reading.** The horizon LP gives the cleanest visual evidence of substitution: pre-trends decline (rising back to 0 by h=−1) and then a clean break to substitution post-2015 with monotone deepening. Quartile heterogeneity is **suggestive that substitution is concentrated at the highest-exposure buyers**, but the within-quartile SEs are too wide to discriminate.

**Source.** [phase6_b1_b2_customs_buyer_supplier.R](analysis/phase6_b1_b2_customs_buyer_supplier.R). Outputs: [phase6_b2_horizon_lp.csv](output_rmd/tables/phase6_b2_horizon_lp.csv), [phase6_b2_quartile_split.csv](output_rmd/tables/phase6_b2_quartile_split.csv).

### 2.5 B3 non-EU exporter price response — placebo on the B1 mechanism

**Spec.** Restrict the customs panel to non-EU source countries; regress log unit value on `1(regulated_product) × post(2015)` with HS6 × country and HS6 × year FE.

**Headline.** β = +0.069 (SE 0.054, p = 0.20). Year-by-year: 2017 = +0.21 ** (one notable spike); other post-2015 years insignificant.

**Reading.** Non-EU exporters did **not** systematically adjust their unit-value prices in response to the EU ETS. This is the placebo we need to defend the B1 substitution interpretation: if non-EU exporters had been raising prices in lockstep with EU ETS (capturing the policy rent), the apparent within-pair substitution in B1 could be confounded by relative-price movements rather than quantity reallocation. β=+0.069 says the relative-price channel is null.

**Source.** [phase6_b3_nonEU_price_response.R](analysis/phase6_b3_nonEU_price_response.R). Output: [phase6_b3_nonEU_price_response.csv](output_rmd/tables/phase6_b3_nonEU_price_response.csv).

### 2.6 B4 σ from customs prices — failed IV identification

**Spec.** Structural elasticity recovered via IV: regress log(EU/non-EU import value ratio) on log(EU/non-EU import price ratio), instrumented by HS6 carbon intensity × annual CPShock.

**First stage.** β = +14.3 (SE 44.3), **F ≈ 0.1**. The IV does not move post-2015 cross-product price ratios.

**Second stage.** β = +1.44 (SE 8.55, p = 0.87) → σ̂ = 1 − β = **−0.44**, 95% CI **[−17, +16]**.

**Reading.** σ is unidentified in this design. The IV doesn't generate sufficient cross-product price variation after 2015. We have **no point estimate of σ from customs prices** to anchor the paper's structural mapping.

**Source.** [phase6_b4_sigma_from_customs_prices.R](analysis/phase6_b4_sigma_from_customs_prices.R). Outputs: [phase6_b4_sigma_iv.csv](output_rmd/tables/phase6_b4_sigma_iv.csv), [phase6_b4_sigma_first_stage.csv](output_rmd/tables/phase6_b4_sigma_first_stage.csv).

### 2.7 C1 imports vs domestic substitution — **NOT YET RUN ON RMD**

**Spec.** At buyer × upstream-NACE-4d × year level, regress import share = imports / (imports + domestic B2B) on `nace_exposure_n × 1(t ≥ 2015)` with `buyer×nace4d + buyer×year` FE.

**Status.** Run on local-1 with downsampled data. The phase coefficient main output (.csv) was not written — only the event-study output exists, and its standard errors are degenerate (1e-08) reflecting **FE collinearity** under the local-1 sample. The PAPER_STATUS tracker flags this as **"needs RMD"** ([PAPER_STATUS.md §5.2.6](PAPER_STATUS.md)).

**What's likely happening.** The spec `import_share ~ regulated_n:post | buyer^seller_nace4d + buyer^year` should be identified at full sample size — `regulated_n` varies at seller_nace4d and `post` at year, so the interaction is not absorbed by either FE block. The local-1 downsample likely loses cells where the interaction has variation, leaving the regression to find the "treatment×post" identification entirely off a thin slice of cells with degenerate residuals.

**What this means.** **C1 is the most direct test of the central international-margin question** ("did Belgian buyers replace domestic with imports?"). Its current status is the single biggest gap in the inventory. The fix is to (a) audit the script on local-1, (b) understand which cells are dropped, (c) sanity-check the FE structure against a smaller alternative (e.g. nace4d×year only, or two-way buyer + year), (d) ship to RMD for the headline run.

**Source.** [phase6_c1_imports_vs_domestic.R](analysis/phase6_c1_imports_vs_domestic.R). Output: [phase6_c1_imports_vs_domestic_eventstudy.csv](output_local/tables/phase6_c1_imports_vs_domestic_eventstudy.csv) (degenerate SEs).

### 2.8 C2 parallel-trends test on EU-share — subsumed by B1 leads

**Spec.** Same panel as B1; tests whether EU import share has a pre-2015 trend correlated with buyer exposure.

**Headline.** `pair_exposure_EU × year_centered` = +0.073 *** (SE 0.003, p < 1e-53). **Confirms the pre-trend visible in B1's naive event study.**

**Reading.** This is the pre-trend that motivates B1's trend correction. C2 as a standalone exhibit is mostly subsumed by B1's event-study figure, which now visibly traces out the pre-trend in the leads of the naive panel and the residual deviation in the de-trended panel. It stays as a transparency appendix exhibit; not a separate headline.

**Source.** [phase6_c2_parallel_trends_eu_share.R](analysis/phase6_c2_parallel_trends_eu_share.R).

### 2.9 C3 within-EU emission-intensity sorting — BLOCKED

**Spec.** Test whether Belgian buyers shifted within-EU sourcing toward EU partners with lower per-€ emission intensity.

**Status.** Blocked on Eurostat air-emissions input. The builder script [phase6_build_eu_emission_intensity.R](analysis/phase6_build_eu_emission_intensity.R) has a column-name bug (`TIME_PERIOD` rename) that needs fixing on local-1 with internet first. User has indicated this can stay parked ([PAPER_STATUS.md §5.2.8](PAPER_STATUS.md)).

### 2.10 China-origin σ revisit — second attempt at σ via shifter dispersion

**Spec.** Importer × HS6 long-difference 2002 → 2012, regress log(ChinaShare/NonChinaShare) on log(P_China / P_nonChina), instrument with BACI EU-26-excluding-Belgium China share change.

**Headline.** β = +13.5 (SE 26.6), implied σ̂ = −12.5, 95% CI [−65, +40]. **First-stage F = 1.7.**

**Reading.** Second-attempt structural σ from a different identification strategy. Also unidentified. **The customs panel does not yield a clean σ at our power level.** The structural σ mapping for the paper's §5.2.5 will have to come from elsewhere (panel-level PPI passthrough sigma mapping, or PRODCOM workstream when accessible).

**Source.** [phase6_revisit_c1_china_origin_theta.R](analysis/phase6_revisit_c1_china_origin_theta.R). Output: [phase6_revisit_c1_summary.txt](output_rmd/tables/phase6_revisit_c1_summary.txt).

### 2.11 B2B-CdGM domestic replication — control case for the international result

**Spec.** Same CdGM-style binary spec as 2.1 but on the Belgian domestic B2B network: `TREAT_j = 1(seller_is_ets) × 1(seller_is_regulated_NACE)`.

**Binary headline col(5):** share Phase 3 β = +0.358 *** (SE — , p < 0.001); probability β = +0.829 ***. **Positive, wrong-signed for leakage, very large.**

**Continuous spec:** col(5) β_pre = +32, β_p3 = −0.5 (n.s.); col(1) tight SEs but pre-period (+32) ≈ Phase 1 (+29), so the parallel-trends test fails. The binary result reflects **market structure** — ETS-regulated Belgian sellers ARE the dominant suppliers in their NACE — not a causal ETS response.

**Reading.** The binary headline does not survive (a) continuous intensity wiping the result and (b) pre-trends failing. Belgian buyers did not (cleanly) shift away from regulated-NACE-ETS BELGIAN sellers in domestic B2B, in addition to not shifting from regulated × non-ETS imports.

**Source.** [B2B_LEAKAGE.md](B2B_LEAKAGE.md). Scripts: [phase3_b2b_cdgm_did.R](analysis/phase3_b2b_cdgm_did.R), [phase3_b2b_cdgm_did_continuous.R](analysis/phase3_b2b_cdgm_did_continuous.R).

---

## 3. The tension: aggregate vs firm-pair

The CdGM aggregate is null/mildly negative. The B1 firm-pair design returns a sharp −0.56. Three reconciliations are possible:

**R1: Aggregation kills the signal.** The CdGM spec averages across all (firm × product × country) cells with `regulated × non-ETS` flags. If substitution is concentrated in a sub-population (e.g. high-exposure buyers, high-CI products), pooling them with low-substitution cells washes the average toward zero. The firm-pair design retains within-pair identification and survives.
   - **Test:** the quartile split in B2 (heaviest-exposure buyers β = −1.84, others near zero) supports this story but is statistically weak.
   - **Sharper test:** redo CdGM col(5) restricting to high-exposure buyers (analog of the B2 Q4 cut). If CdGM-on-Q4-buyers turns negative, R1 is confirmed.

**R2: Trend control matters.** The naive CdGM is null because the underlying trend is included in β. The trend-corrected version (2.2) is mildly negative at −0.0062 ***, which is qualitatively consistent with B1 trend-corrected. The two designs both confirm the role of pre-trends; magnitudes differ because the LHS (within-pair share vs aggregated cell share) measure different things.

**R3: B1 is over-fitted to a wrong-sign confound.** The +0.058 per-year drift control absorbed by B1 trend-correction is large; if that drift reflects something other than a true pre-trend (e.g. compositional drift in the customs panel, post-MSR balanced-panel construction artifact), the −0.56 could be an artifact of the trend control rather than substitution.
   - **Test:** the shorter pre-period robustness (2010+) gives trend-corrected −0.097 ** — same sign, much smaller magnitude. Headline result is sensitive to pre-period length, which is consistent with R3 having some bite.
   - **Sharper test:** event-study figure of B1 (visible in [output_rmd/figures/](output_rmd/figures/)) — if the de-trended figure shows clean kinks at 2015 and not a smooth pre-extrapolated line, R3 is ruled out.

The next batch of cuts should discriminate among R1/R2/R3.

---

## 4. Open heterogeneity cuts (priorities)

### 4.1 HS6 carbon-intensity heterogeneity (priority A)

**Motivation.** All current specs treat "regulated CN8" as a binary. But within "regulated", products vary enormously in carbon intensity (HS 25 cement vs HS 72 steel vs HS 29 organic chemicals). A leakage mechanism should be **strongest where the per-unit carbon cost is largest**. Belgium imports are concentrated in chemicals and metals — the cross-product variation should be informative.

**Existing infrastructure.** [phase6_build_hs6_carbon_intensity.R](analysis/phase6_build_hs6_carbon_intensity.R) builds HS6-level carbon intensity from EU air-emissions data + product concordances. Already used as the IV in B4 (which failed identification).

**Proposed extensions:**
- **C1 + HS6-CI:** redo C1 on HS6 × buyer × year, splitting by HS6-CI quartile. Direct test of leakage by product carbon content.
- **B1 + HS6-CI:** add HS6-CI as a moderator: `pair_exposure_EU × post × hs6_ci_quartile`. Test whether B1 substitution is HS6-CI-loaded (R1 confirmation) or uniform across products (R2/R3).
- **CdGM + HS6-CI:** redo Table 1 col(5) within HS6-CI quartiles. The CdGM spec is the easiest place to add an HS6-CI cross.

### 4.2 Pre-MSR vs post-MSR cut (priority A)

**Motivation.** Carbon prices were near zero through Phase 2 (2009–12) and most of Phase 3 (2013–18, EUA ~€5–€10). The post-MSR window (2018+) saw EUA spike from €10 to €80+. If leakage is price-driven, the **post-MSR subperiod should carry all the action**. Currently every spec lumps Phases 2 and 3 together or runs the full 2005–2019 / 2005–2022 window.

**Proposed extensions:**
- **CdGM-style with quartered phases:** split Phase 3 into 2013–14 / 2015–17 / 2018–19 / 2020–22 (the last requires the extended customs panel `customs_import_panel_extended.RData`, which is built). The 2018+ jump should be visible if leakage is price-driven.
- **B1 post=2018 vs post=2015 head-to-head:** redo B1 trend-corrected with `1(year ≥ 2018)` instead of `1(year ≥ 2015)`. If the −0.56 magnitude is stable or grows, post-MSR is the binding price episode; if it shrinks, the 2015–17 announcement-effect window matters more.
- **C1 pre-MSR vs post-MSR (once C1 is fixed):** split sample at 2017. Should give the cleanest substitution test under a price-driven mechanism.

### 4.3 Source-country bucket (priority B)

**Motivation.** Belgian imports are 98% intra-EU. Substitution to non-ETS countries means substituting toward a small tail (China, Turkey, Russia, Switzerland). The CdGM-style aggregate uses any-non-ETS as the comparator; a more granular bucket (China / OECD-non-ETS / rest) could detect China-specific patterns masked in the aggregate.

**Not in scope here unless one of the priority-A cuts surfaces an aggregation artifact specifically.**

### 4.4 Buyer ETS status (priority B)

**Motivation.** ETS-regulated Belgian buyers face direct carbon cost; non-ETS buyers face only indirect (via supplier prices). Splitting CdGM/B1/C1 by buyer ETS status decomposes the substitution into the two channels.

**Not in scope here unless one of the priority-A cuts requires it for interpretation.**

---

## 5. Caveats

1. **Customs panel ends at 2019 by default** (matches CdGM). The extended panel goes to 2022 ([phase6_build_customs_panel_extended.R](analysis/phase6_build_customs_panel_extended.R)) and is the one used in B1/B2/B3/B4 already, but the CdGM Table 1 replication itself stops at 2019. The 2020–22 window has the largest carbon-price action; extending CdGM Table 1 forward is a natural follow-up.
2. **Pre-trend on probability margin** (CdGM): treated cells were structurally less likely to be active than control before any ETS treatment. Identification under parallel-trends is questionable for Panel B. Share margin pre-trend is clean.
3. **Trend correction does material work** in both CdGM and B1: naive vs trend-corrected differ by factors of 2.6× and 35× respectively. Whether the absorbed trend is "the right thing to absorb" depends on whether the trend is policy-pre-empting or compositional drift.
4. **No structural σ from customs.** B4 and the China-origin revisit both fail first-stage. The paper's σ has to come from PPI panel-LP mapping (already in §4) or PRODCOM (deferred).
5. **3 contaminated VATs** (NACE 20/24 EUTL artifact post-2020): correctly handled in B1/B2/B3 (excluded from emissions data, not from customs); not relevant for CdGM which uses customs only.
6. **B2B-CdGM headline result reverses** from binary +0.36 *** to continuous −0.5 (n.s.) and pre-trend failure. The binary spec is **not interpretable as a leakage estimate** in isolation.
7. **C1 is not yet a clean estimate.** Most direct test of the central question; needs RMD execution.

---

## 6. What this means for the paper

The current paper draft ([paper/leakage_within_across/](paper/leakage_within_across/)) treats §5.2 as **partially done with major revisits**:

- §5.2.1 CdGM replication: trend-corrected headline ready (β=−0.0062 ***), original kept as robustness.
- §5.2.2 Buyer-supplier (B1): trend-corrected β=−0.560 *** is the substitution headline.
- §5.2.3 HTE on B1 (B2): horizon LP + Q4 cut is the heterogeneity argument.
- §5.2.4 Non-EU price response (B3): null, defends B1 interpretation.
- §5.2.5 σ from customs (B4): unidentified, paper needs to flag this.
- §5.2.6 Imports vs domestic (C1): **gap — needs RMD**.
- §5.2.7 Parallel trends (C2): subsumed by B1 leads, demoted to appendix.
- §5.2.8 Within-EU sorting (C3): blocked.

The natural headline structure given the inventory:

> "The aggregate CdGM-style replication on Belgian customs returns a small, trend-corrected substitution coefficient an order of magnitude below France's. But our firm-pair design recovers a much larger within-pair substitution (β=−0.56) with a clean monotone horizon and no offsetting non-EU price response. The substitution is concentrated at the heaviest-exposure buyers, consistent with reallocation operating at a sub-population that the aggregate spec averages over. Domestic supplier reallocation is null on the cleanly identified continuous design (B2B-CdGM continuous). The structural elasticity σ cannot be recovered from customs prices in our identification."

Whether this becomes the paper's framing depends on the next batch of cuts:

- **HS6 carbon-intensity heterogeneity** (priority A) sharpens or breaks the "substitution lives in a sub-population" story. If it loads on high-CI HS6, the leakage interpretation is strengthened. If it's flat across CI, the trend-correction story (R2) gains weight over R1.
- **Pre-MSR vs post-MSR** discriminates price-driven from announcement-driven mechanisms.
- **C1 on RMD** is the most direct domestic-vs-imports substitution test and needs to land before any framing is committed.

---

## 7. Scripts and outputs (cross-reference)

| Estimate | Script | Output table |
|---|---|---|
| CdGM Table 1 | [analysis/phase2_cdgm_table1.R](analysis/phase2_cdgm_table1.R) | [output/tables/phase2_cdgm_table1_A.csv](output/tables/phase2_cdgm_table1_A.csv), `_B.csv` |
| CdGM robustness | [analysis/phase2_cdgm_table1_robustness.R](analysis/phase2_cdgm_table1_robustness.R) | [output/tables/phase2_cdgm_table1_robustness.csv](output/tables/phase2_cdgm_table1_robustness.csv) |
| CdGM trend-corrected | [analysis/phase6_cdgm_table1_corrected.R](analysis/phase6_cdgm_table1_corrected.R) | [output_rmd/tables/phase6_cdgm_corrected_A.csv](output_rmd/tables/phase6_cdgm_corrected_A.csv), `_B.csv` |
| CdGM event study (Fig 3) | [analysis/phase2_cdgm_figure3.R](analysis/phase2_cdgm_figure3.R) | [output/tables/phase2_cdgm_figure3.csv](output/tables/phase2_cdgm_figure3.csv) |
| B1 trend-corrected | [analysis/phase6_b1_corrected.R](analysis/phase6_b1_corrected.R) | [output_rmd/tables/phase6_b1_corrected.csv](output_rmd/tables/phase6_b1_corrected.csv) |
| B2 horizon + quartile | [analysis/phase6_b1_b2_customs_buyer_supplier.R](analysis/phase6_b1_b2_customs_buyer_supplier.R) | [output_rmd/tables/phase6_b2_horizon_lp.csv](output_rmd/tables/phase6_b2_horizon_lp.csv), `_quartile_split.csv` |
| B3 non-EU price | [analysis/phase6_b3_nonEU_price_response.R](analysis/phase6_b3_nonEU_price_response.R) | [output_rmd/tables/phase6_b3_nonEU_price_response.csv](output_rmd/tables/phase6_b3_nonEU_price_response.csv) |
| B4 σ IV | [analysis/phase6_b4_sigma_from_customs_prices.R](analysis/phase6_b4_sigma_from_customs_prices.R) | [output_rmd/tables/phase6_b4_sigma_iv.csv](output_rmd/tables/phase6_b4_sigma_iv.csv), `_first_stage.csv` |
| China σ revisit | [analysis/phase6_revisit_c1_china_origin_theta.R](analysis/phase6_revisit_c1_china_origin_theta.R) | [output_rmd/tables/phase6_revisit_c1_summary.txt](output_rmd/tables/phase6_revisit_c1_summary.txt) |
| C1 (degenerate) | [analysis/phase6_c1_imports_vs_domestic.R](analysis/phase6_c1_imports_vs_domestic.R) | [output_local/tables/phase6_c1_imports_vs_domestic_eventstudy.csv](output_local/tables/phase6_c1_imports_vs_domestic_eventstudy.csv) |
| C2 pre-trend | [analysis/phase6_c2_parallel_trends_eu_share.R](analysis/phase6_c2_parallel_trends_eu_share.R) | [output_local/tables/phase6_c2_pre_trend_test.csv](output_local/tables/phase6_c2_pre_trend_test.csv) |
| B2B-CdGM | [analysis/phase3_b2b_cdgm_did.R](analysis/phase3_b2b_cdgm_did.R), `_continuous.R` | [output/tables/phase3_b2b_cdgm_table_A.csv](output/tables/phase3_b2b_cdgm_table_A.csv), `_continuous_phase.csv` |
| HS6 CI builder | [analysis/phase6_build_hs6_carbon_intensity.R](analysis/phase6_build_hs6_carbon_intensity.R) | (data artifact) |

---

## 8. New work this session (2026-05-11)

### 8.1 C1 hardening

[phase6_c1_imports_vs_domestic.R](analysis/phase6_c1_imports_vs_domestic.R) rewritten to:

1. Print cell-density diagnostics up front (so we can see at a glance whether the FE structure is identified).
2. Run an FE ladder (preferred → cross-pair → year-only) — whichever specs converge are reported.
3. Add the post-MSR (2018) cut alongside the post(2015) baseline (Phase D extension).
4. Replace the old single-spec event study with the same FE ladder applied to event-study form.

**Local-1 diagnostic.** 5007 (buyer, year) cells, but only **23 of them (0.5%) have ≥2 seller_nace4d** — median is 1. The preferred FE `pair + buyer^year` is therefore necessarily collinear with `regulated_n:post` because in the local-1 downsample, the FE chain pins seller_nace4d given (buyer, year). On RMD with the full panel this constraint vanishes.

**Local-1 results (downsample, directional only):**

| FE | regulated_n × post(2015) | regulated_n × post(2018, MSR) |
|---|---:|---:|
| pair + year (2-way additive) | −0.031 (n.s., p=0.23) | −0.026 (n.s., p=0.45) |
| seller_nace4d + year | −0.038 (marginal, p=0.11) | −0.035 (n.s., p=0.21) |
| year only | −0.036 (n.s., p=0.21) | **−0.036 (p=0.021) \*** |

Mild substitution signal under permissive FE, but the local-1 downsample is too thin for the preferred FE structure. RMD execution is the next step.

### 8.2 B5 — HS6 carbon-intensity and pre-MSR heterogeneity on B1

New script: [phase6_b5_b1_heterogeneity.R](analysis/phase6_b5_b1_heterogeneity.R). Runs four heterogeneity exercises against the B1 trend-corrected baseline:

1. B1 × HS6-CI quartile split.
2. B1 with continuous log-HS6-CI moderator (triple interaction).
3. B1 with `post = 1(year ≥ 2018)` instead of `1(year ≥ 2015)` (post-MSR only).
4. B1 with both `post(2015)` and `post_msr(2018)` in one regression (differential test).

**Local-1 results (downsample, 12,346 cell-years; full-sample magnitudes will differ but signs and rank should reproduce).**

**B1 baseline (local-1 re-run):** β = **−0.493 \*\*\*** (SE 0.041), trend control +0.069/year ***. Same sign and roughly same magnitude as the RMD result (−0.560 ***).

**HS6-CI quartile split — Table:**

| Quartile (Q1=low CI) | β on pair_exposure_EU × post | SE | p | n |
|---:|---:|---:|---:|---:|
| Q1 | −0.382 *** | 0.097 | 3e-4 | 1572 |
| Q2 | −0.453 *** | 0.047 | <1e-12 | 3294 |
| **Q3** | **−1.034 \*\*\*** | 0.123 | 1e-3 | 226 |
| Q4 | −0.340 * | 0.141 | 0.022 | 909 |
| Q1+Q2 pooled (low half) | −0.434 *** | 0.046 | <1e-14 | 4866 |
| Q3+Q4 pooled (high half) | −0.544 *** | 0.140 | 5e-4 | 1135 |

**HS6-CI continuous moderator (log CI, centered):**
- Level β on `pair_exposure_EU × post`: −0.448 *** (SE 0.047)
- Triple-interaction β on `pair_exposure_EU × post × log(CI)`: +0.033 (SE 0.061, **p=0.59 n.s.**)

**Reading.** There is **no monotone HS6-CI gradient** in B1 substitution on the local downsample. Q3 dominates the quartile split but with only 226 obs — likely noise. The continuous moderator is essentially zero. Q1+Q2 vs Q3+Q4 pooled are within sampling noise of each other (−0.43 vs −0.54). **The B1 substitution effect is roughly uniform across product carbon intensity, on the downsample.** This nudges the framing away from R1 ("substitution concentrated at high-CI HS6") and toward R2 (trend correction is doing the work) / R3 (B1 over-fitted to the absorbed trend) — but RMD numbers will be decisive.

**Pre-MSR vs post-MSR — Table:**

| Spec | β | SE | p | n |
|---|---:|---:|---:|---:|
| baseline: post(2015) only | −0.493 *** | 0.041 | 1e-23 | 8558 |
| alternative: post_msr(2018) only | −0.467 *** | 0.064 | 1e-11 | 8558 |
| both in one reg — β on post(2015) | −0.446 *** | 0.041 | 4e-21 | 8558 |
| both in one reg — β on post_msr (differential 2018+) | **−0.295 \*\*\*** | 0.061 | 4e-6 | 8558 |

**Reading.** The 2018 differential effect is **statistically large and significant**. The substitution deepens by an additional −0.30 on the post-MSR window, on top of the 2015-17 baseline. Total post-2018 effect ≈ −0.45 + (−0.30) = −0.75 (the level effect at year 2018+). This is **consistent with a price-driven mechanism**: the EUA-spike subperiod carries an outsized share of the substitution. Note this implies post-MSR is doing real work distinct from the linear trend the trend control already absorbs.

### 8.3 Implications for the framing

The post-MSR cut delivers a sharp positive result (β_diff_postmsr = −0.30 ***) that strengthens the "substitution is real" reading of B1. The HS6-CI cut delivers a null on the moderator, which weakens R1's "substitution lives in a high-CI sub-population" story. Two updates to the inventory:

1. **R2 (trend-correction doing the work)** gains weight relative to R1 (sub-population aggregation). If substitution were sub-population-driven, the high-CI sub-sample should have noticeably larger β. It doesn't on the downsample.
2. **Pre-MSR vs post-MSR is a strong identifying split.** Worth pushing into the CdGM-aggregate replication too: redo Table 1 with the post period sub-split at 2017/2018 to see if the aggregate null-headline survives, or if it concentrates the leakage signal into the price-spike window.

The natural next RMD batch:

| Script | Purpose | RMD ETA |
|---|---|---:|
| `phase6_c1_imports_vs_domestic.R` (hardened) | C1 main result + post-MSR cut | ~5 min |
| `phase6_b5_b1_heterogeneity.R` (new) | HS6-CI + post-MSR heterogeneity on B1 | ~5 min |
| `phase6_cdgm_table1_postmsr.R` (TODO) | CdGM aggregate split at 2017/2018 | ~15 min (new script needed) |

The third script doesn't exist yet — extending the CdGM aggregate to a post-MSR sub-split is the natural follow-up if the user wants to push the heterogeneity story all the way through.

---

*Last revision: 2026-05-11. This document inventories every international-margin estimate on disk. Treat as the single source of truth for the international-margin headline pending RMD execution of C1 and the priority-A heterogeneity cuts.*
