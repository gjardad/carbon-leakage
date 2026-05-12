# Plan — Replicate Coster–Méjean–di Giovanni (2024) empirical specs on Belgian data, extend to domestic B2B

## Context

Coster, di Giovanni & Méjean (FRBNY SR #1136, rev. Nov 2025, "Firms' Supply Chain Adaptation to Carbon Taxes") document carbon leakage in French firms' *imports*: after the EU ETS, French manufacturers shifted sourcing of regulated (ETS-scope) products from ETS to non-ETS countries. Belgium has all the data ingredients to replicate their Section 3 reduced-form identification, **and** — because NBB publishes firm-to-firm transactions — the opportunity to extend their specification to *domestic* supplier switching, which France cannot study.

The paper's structural model and €100-carbon-tax counterfactuals (Sections 4–6) are explicitly **out of scope** per user instruction. This plan focuses on:

1. PPI pass-through (their Figure 1)
2. Firm-level input switching on imports (their Table 1 + Figures 3–4 + Appendix B)
3. A new B2B extension using Belgian firm-to-firm data

Detailed paper notes are at [articles/split_coster_mejean_digiovanni/notes.md](c:\Users\jota_\Documents\carbon-leakage\articles\split_coster_mejean_digiovanni\notes.md).

## Scope and non-goals

**In scope:** PPI event study; customs-panel PPML DiD with six FE specifications; event-study variant; alternative-control variant with 2011 Intrastat break; robustness (ETS-firm split, leave-one-country-out, de Chaisemartin–D'Haultfœuille); B2B domestic analog.

**Out of scope:** AFT sourcing model, SMM estimation, carbon-tax / CBAM counterfactuals, welfare decomposition, carbon-damage utility calibration.

## Data landscape

**Already in project (usable as-is):**
- `NBB_data/processed/b2b_selected_sample.RData` — B2B pairs 2005–2022 (full on RMD, downsampled on local 1)
- `firm_year_belgian_euets.RData` — 281 ETS firms, 2005–2023, via EUTL → VAT matching pipeline in `analysis/prodcom_passthrough_stata/01-02_*.do`
- `annual_accounts_selected_sample_key_variables.RData` — firm NACE-5d, revenue
- `NBB_data/processed/deflator_nace4d_2005base.RData` — PPI, Statbel 4d 2010+ chained with Eurostat 2d 2005-2009, built in `analysis/phase0_build_deflator.R`
- `analysis/phase4_b2b_supplier_switching.R` — Angle 4 event-study, buyer×seller pair panel with contaminated-VAT filter, EUA prices, deflator join. Reuse substantially.

**Must build (this plan creates):**
- NBB firm-level customs panel (VAT × CN8 × partner × year). Raw table exists on RMD per CLAUDE.md; no pipeline script pulls it yet.
- HS/CN → NACE-BEL concordance, ETS activity → HS mapping (copy CDGM Tables A.2–A.3), CBAM product list
- Belgian IO table-based regulated-intensive sector list (10% rule)
- Core-input filter per downstream NACE
- Intrastat threshold history for Belgium

**Known data caveats:**
- 3 contaminated VATs in NACE 20/24 must be excluded post-2020 (per `memory/project_nace24_eutl_break_post2020.md`; already hard-coded in `phase4_b2b_supplier_switching.R:89-93`)
- RMD has no browser; all RMD code must be self-contained and produce exportable summary outputs

## Phase 0 — Concordances, IO, sector tagging (local 1, ~1 week)

Directory layout to create:
```
data/concordances/
  regulated_products_cn8.csv       # ETS-derived (CDGM Table A.2) ∪ CBAM-listed (Reg. 2023/956 Annex I)
                                   # Union is flagged `is_regulated`. CBAM supplements the ETS
                                   # list by catching CN8 codes the activity→HS mapping missed;
                                   # CBAM only covers goods whose production is ETS-regulated.
  hs_cn8_to_nacebel.csv            # Derived from GRANTPA's product_id_pc8plus_pc8_cn8_final
                                   # family-tree concordance (see "Concordance source" below).
                                   # CN8 → product_id → PC8 → first 4 digits = NACE Rev.2 4d
                                   # (NACE-BEL 4d = NACE Rev.2 4d). Needed for core-input filter
                                   # (CN8 → NACE).
  hs_to_bec.csv                    # UN HS2002→BEC Rev.4. Needed to drop capital goods (BEC 41, 521).
  country_ets_status.csv           # EU27 + EEA (IS, LI, NO); UK through 2020; handle 2007/2013 accessions
  intrastat_threshold_be.csv       # year × BE arrival threshold EUR, with break flags for Figure 4
data/io/
  belgian_io.csv                   # Eurostat national Use table at basic prices for BE
                                   # (naio_10_cp1610), 2015 anchor (or 2014-16 avg), A*64
                                   # industry x CPA product. Local file:
                                   # NBB_data/raw/Eurostat/naio_10_cp1610__custom_21179157_linear.csv
                                   # Note: 2018 missing from Eurostat release.
                                   # FIGARO MRIO (naio_10_fcp_*) as cross-border robustness;
                                   # Exiobase 163-industries as granularity robustness if needed.
  regulated_producing_nace.csv     # derived: NACE sectors producing ≥1 regulated CN8, via
                                   #   regulated_products_cn8 ∩ hs_cn8_to_nacebel
  regulated_intensive_nace.csv     # derived from Belgian IO: downstream NACE sectors with ≥10%
                                   # intermediate consumption from regulated_producing_nace.
                                   # NOT lifted from CDGM Table A.5 — recomputed from BE data.
  core_inputs_by_downstream.csv    # derived from Belgian IO: downstream-NACE → {upstream NACE}
                                   # at ≥10%, mapped to CN8 via hs_cn8_to_nacebel, capital excluded
```

NAF vs. NACE: CDGM work in NAF (French extension of NACE Rev.2); Belgium uses NACE-BEL (Belgian
extension). Both are identical to NACE Rev.2 at 4-digit. We work in NACE Rev.2 at 4-digit
throughout; no classification reinterpretation is needed beyond stripping national 5th digits
where they exist.

Scripts to create (all R, local 1):
- `analysis/phase0_lift_cdgm_cn8_list.R` — lift CDGM's regulated CN8 list from their published
  Table A.2 (ETS-derived) and Table A.3 (CBAM). Validate against Table A.4 (HS-chapter distribution
  should concentrate in HS 25, 27, 28-29, 31, 47-48, 69-70, 72-76).
- `analysis/phase0_build_concordances.R` — parse the GRANTPA family-tree concordance (see
  "Concordance source" below) into a long table `(product_id, year, cn8, pc8, nace4d)` with
  `nace4d = substr(pc8, 1, 4)`. CN revisions 1995-2018 are auto-handled because all CN8 codes
  in a "family" share a `product_id`. CN8→BEC via UN (separate input, not in GRANTPA).
- `analysis/phase0_build_country_status.R` — country×year ETS flag. Bulgaria/Romania 2007,
  Croatia 2013, UK exit end-2020, EFTA EEA from 2008.
- `analysis/phase0_build_intrastat.R` — Belgian Intrastat threshold history from NBB/Statbel docs.
  Flag break years.
- `analysis/phase0_build_io_sectors.R` — loads Belgian IO; derives `regulated_producing_nace`
  (via CN8→NACE mapping of the regulated product list), `regulated_intensive_nace`
  (10% rule on BE IO), and `core_inputs_by_downstream` (10% upstream rule). Run the 10% and 5%
  thresholds both.

**Granularity check — DONE (2026-04-26).** Parsed Table A.5 to
[data/concordances/cdgm_table_a5_ri_naf.csv](data/concordances/cdgm_table_a5_ri_naf.csv) (62 NAF-138
rows; ETS, R-I, CBAM flags). The 44 R-I sectors (col (2) ∪ col (5) = 1) span **20 distinct
NACE-2d parents** (NACE 11, 14-33). Verdict: 20 falls in the borderline 15-24 zone —
**A*64 acceptable as baseline, but NBB national SUT (P65) is now promoted to a co-primary
robustness specification** (run alongside A*64; not optional). Risk specifically at NACE-2d
codes where some 3-digit children are R-I and others are not (C25: 4 of 5 R-I; C26: 6 of 7
R-I; C30: 3 of 5 R-I; C20: 3 of 3 R-I, harmless). Exiobase 163 demoted to "only if NBB SUT
also collapses too much".

Decisions to confirm (see end of plan): IO source (Eurostat A*64 BE Use table baseline +
NBB SUT P65 co-primary robustness; Exiobase as fallback); core-input threshold (10% baseline,
5% robustness).

### Concordance source — GRANTPA

Our CN8 ↔ PC8 ↔ NACE 4d concordance comes from the **GRANTPA** (Granular Trade and
Production Activities) database by Bradley, Larch, Flórez Mendoza & Yotov (wiiw Working
Paper 248, June 2024). GRANTPA extends the Van Beveren-Bernard-Vandenbussche (2012) /
Pierce-Schott (2012) family-tree methodology to a 1995-2018 panel of 3,124 stable
"PC8+" synthetic products, with each product mapped to its full set of historical
PC8 (PRODCOM) and CN8 (Combined Nomenclature) codes.

We use a single file from GRANTPA:

- **File:** `Correspondences_and_dictionaries/product_id_pc8plus_pc8_cn8_final(ID-PC8-CN8 codes final).csv`
- **Source:** Bradley, S., Larch, M., Flórez Mendoza, J., & Yotov, Y. V. (2024).
  *The Granular Trade and Production Activities (GRANTPA) Database*. wiiw Working
  Paper 248, June 2024. The file is hyperlinked from page 20 of the working paper
  (https://wiiw.ac.at/the-granular-trade-and-production-activities-grantpa-database-dlp-6911.pdf)
  and from the technical appendix
  (https://wiiw.ac.at/technical-appendix-the-granular-trade-and-production-activities-grantpa-database-dlp-6912.pdf).
  Authors' contact for database access: grantpadatabase@gmail.com.
- **Schema:** 3,124 rows × 4 columns (`product_id`, `product_over_time`, `prodcom`, `CN8`).
  Each row is one stable family-tree product; the `prodcom` and `CN8` columns are
  space-separated lists of the codes belonging to that product, with `(YYYY)` markers
  indicating transition years.
- **Year coverage:** 1995-2018 (markers observed `(1995)` through `(2018)`).
  2019 is the only gap inside our 2000-2019 target window.

Why GRANTPA over alternatives:

1. **One row = one persistent product across all years.** No need to chain pairwise
   year-on-year correspondences ourselves.
2. **Both classifications in one file.** PC8 (for Phase 1 PPI / PRODCOM joins) and
   CN8 (for Phase 2 customs panel) come from the same `product_id`, so the bridge is
   internally consistent.
3. **NACE 4d derives directly from PC8** (first 4 digits of PC8 = NACE Rev.2 4d
   post-2008), so we get the CN8→NACE mapping without a separate RAMON CN8→CPA→NACE
   two-step.
4. **HS / CN revision noise auto-handled.** All CN8 codes affected by an HS revision
   (2002, 2007, 2012, 2017) sit in the same `product_id` family — we just take the
   union.

Trade-offs vs. Magerman (2022) `Concordances_CN_PC`:

- Magerman preserves year-by-year m:n detail (`oto/otm/mto/mtm` flags) but covers only
  2001-2014. Better for within-year price-index work, which we don't do.
- GRANTPA collapses to family trees but covers 1995-2018, gives us NACE for free, and
  is internally consistent across CN and PC. We keep Magerman's files as a robustness
  cross-check (validate that GRANTPA's families don't disagree with Magerman's
  year-on-year correspondences for 2001-2014).

### Concordance source — BLM 2018 (Bergounhon-Lenoir-Méjean)

CDGM's harmonized-product universe (their "7,051 codes") is built using the **C³**
"connected components concordance" algorithm by Behrens-Martin (2015), as implemented
in the Bergounhon-Lenoir-Méjean (2018) "A Guideline to French Firm-Level Trade Data"
companion code. The companion package is publicly downloadable and contains:

- **Raw EU CN8 nomenclature files 1995-2018** (`nom_nc8/CN_yyyy.csv`, one per year).
  Used as the **canonical CN universe in [analysis/phase0_build_regulated_cn8.R](analysis/phase0_build_regulated_cn8.R)** —
  complete EU coverage with no PRODCOM restriction (resolves the GRANTPA HS27
  mineral-fuels gap).
- **Year-on-year CN-CN correspondence tables 1993-2018** (`tablescorresp/corres_yyyy.txt`).
  Equivalent to Magerman's `cn8_concord.tsv` but with the 2015-2018 gap filled.
- **C³ algorithm** (`corres_nc8.do`, Stata) — produces a CN-only family-tree (layer 3)
  stable-code mapping when run on the inputs above. Available for direct use if we
  later want a CDGM-comparable harmonized-product count.

Source URL: https://www.isabellemejean.com/Website_nc8corresp.zip (linked from
[FrenchCustomsData.html](https://www.isabellemejean.com/FrenchCustomsData.html) on Mejean's site).
Cite as Bergounhon, F., Lenoir, C., & Méjean, I. (2018). *A Guideline to French
Firm-Level Trade Data*.

Local path:
`NBB_data/raw/Correspondences_and_dictionaries/Website_nc8corresp/`.

Use in our pipeline:
- **Step 1** (CN universe for regulated-products list): primary source.
- **Step 2** (CN ↔ NACE 4d bridge): not used; GRANTPA is the bridge of choice.
- **Future robustness**: if we want CDGM-style CN-only family trees, run `corres_nc8.do`
  on the bundled inputs.

**Phase 0 verification:** `summary(regulated_products_cn8)` shows ~1–1.5k tagged CN8s with HS-chapter distribution matching CDGM Table A.4 (concentration in HS 25, 27, 28–29, 31, 47–48, 69–70, 72–76). `nrow(regulated_intensive_nace)` in [30, 50].

## Phase 1 — PPI pass-through (Figure 1 analog, local 1, ~3 days)

Fast, fully unblocked once Phase 0.1 is done. Uses existing `deflator_nace4d_2005base.RData`.

Create `analysis/phase1_ppi_passthrough_cdgm.R`:
- Spec: `log PPI_{s,t} = Σ_{τ=2005..2022} β_τ · 1(s ∈ regulated_producing) · 1(year = τ) + α_s + δ_t + ε_{s,t}`
- Reference year: 2004 (or 2005 if unavailable)
- FE: `nace4d`, `year`; cluster on `nace4d`
- Run on full sample and on manufacturing only (NACE 10–33)
- Output: event-study coefficient plot + regression table in `output/figures/` and `output/tables/`
- If a monthly-frequency PPI file is available in the deflator build, add sector×month + year FE (true CDGM Figure 1 equivalent)

**Phase 1 verification:** β_τ positive and growing in Phases 2–3 of ETS (2009+); no significant pre-trend before 2005. CDGM see clear divergence from ~2006.

## Phase 2 — Customs-based import switching (Table 1, Figures 3–4, Appendix B; RMD, ~2 weeks)

Blocker: NBB customs panel not yet in pipeline.

### 2.1 Build script: `analysis/phase2_build_customs_panel.do` (Stata on RMD)

Inputs (RMD): raw NBB customs table, `firm_year_belgian_euets.dta`, annual accounts, concordances from Phase 0.

Build steps:
1. Restrict to imports.
2. Drop non-manufacturing firms (buyer NACE not in 10–33).
3. Filter buyers by `nace4d ∈ regulated_intensive_nace`.
4. For each buyer NACE, keep only CN8s whose implied upstream NACE ∈ `core_inputs_by_downstream[nace]`.
5. Drop capital goods (BEC 41, 521).
6. Balance the panel in (firm, CN8, partner) triplets ever observed 2000–2019; zero-fill missing (firm, CN8, partner, year) cells.
7. Attach flags: `is_regulated_product`, `is_non_ets_country`, `is_ets_firm`, `contaminated_vat` (for post-2020 exclusion).

Output: `customs_import_panel_regulated.dta` (RMD). Expected size: ~1.5–3M rows, 4–8k buyer firms (FR had 7.5M rows, 27k firms).

### 2.2 Descriptive Figure 2: `analysis/phase2_cdgm_figure2.R` (RMD)

**Trade-side analog of Figure 1.** Pure descriptive — no FE, no regression. Two panels:

- Panel (a): aggregate import **share** by year, treatment vs. control group.
- Panel (b): aggregate **probability of sourcing** by year (extensive margin = fraction of firm × product × country triplets active).

Treatment group: `1(regulated_product) × 1(non_ets_country)`. Control group: `1(unregulated_product) × 1(non_ets_country)` (CDGM's preferred control). Both groups computed by aggregating the customs panel by year and treatment-group label, then plotting two lines per panel.

Output: `output/figures/phase2_cdgm_figure2.png` (two-panel figure replicating CDGM Fig 2). Motivates the formal regression in 2.3.

### 2.3 Regression script: `analysis/phase2_cdgm_table1.R` (RMD)

Using `fixest::fepois`. CDGM Eq (1), phase-aggregated, 2000–04 reference:

```
y_fpit = exp[ β_1 · 1(non_ets × regulated × 2005–08)
            + β_2 · 1(non_ets × regulated × 2009–12)
            + β_3 · 1(non_ets × regulated × 2013–19)
            + FE ]
```

Two outcomes:
- Panel A: `share_fpit = value_fpit / Σ_{p,i} value_fpit` (firm-year denominator).
- Panel B: `prob_fpit = 1(value_fpit > 0)`.

Six FE columns (match CDGM Table 1):

| Col | Fixed effects |
|---:|---|
| 1 | `product^country + year` |
| 2 | `firm^product^country + year` |
| 3 | `firm^product^country + country^year` |
| 4 | `firm^product^country + sector^year` |
| 5 | `firm^product^country + country^year + sector^year` |
| 6 | `firm^product^country + year^is_ets_firm` |

Cluster SE: two-way `firm + country`. Export coefficients + SEs to `output/tables/phase2_cdgm_table1_{A,B}.csv`.

### 2.4 Event study: `analysis/phase2_cdgm_figure3.R`

Same as column (5) but with year-by-year τ dummies (2000–04 reference). Plot β_τ ± 1.96·SE.

### 2.5 Alternative control: `analysis/phase2_cdgm_figure4.R`

Treatment flipped: `1(ets_country × regulated)`. Add `1(intra_eu × post_intrastat_break)` dummy using the Belgian break year from Phase 0.

### 2.6 Robustness: `analysis/phase2_cdgm_appendixB.R`

- **B.1** ETS vs non-ETS firm split (column (5) on subsamples).
- **B.3** de Chaisemartin–D'Haultfœuille (`did_multiplegt_dyn`), binarised at phase cutoffs.
- **B.4** Leave-one-partner-country-out, plot β_3 ± SE.
- **B.5** MNE-affiliate split — deferred if ORBIS linkage not on RMD.

**Phase 2 verification:** Column (5) Phase 3 share coefficient in [0.05, 0.20] (CDGM: 0.121, SE 0.029). Probability Phase 3 in [0.03, 0.10] (CDGM: 0.071, SE 0.015). Event-study flat pre-2005, divergence 2009+. Phase 1 near-zero or negative (ETS non-binding).

## Phase 3 — B2B domestic supplier-switching extension (RMD, ~1.5 weeks)

Novel contribution. Leverages existing Angle 4 code.

**Design choice:** B2B has no product code, only seller NACE. CDGM's "regulated product × non-ETS country" becomes **"seller NACE ∈ regulated-producing × seller is ETS-covered"**. Treatment is the 2×2 discrete interaction, directly mirroring CDGM's binary DiD — cleaner and more CDGM-comparable than Angle 4's continuous `firm_cost_share_j`.

### 3.1 Build script: `analysis/phase3_build_b2b_cdgm_panel.R` (RMD)

Consumes `b2b_selected_sample`, `firm_year_belgian_euets`, annual accounts, Phase 0 outputs. Output: `b2b_cdgm_panel.RData` with columns:
- `seller_vat`, `buyer_vat`, `year`
- `seller_nace4d`, `buyer_nace4d`
- `seller_is_ets` (binary), `seller_is_regulated_nace` (binary)
- `buyer_is_regulated_intensive` (sample filter)
- `is_core_input` (seller_nace ∈ core_inputs[buyer_nace])
- `corr_sales_real`, `share_j_within_buyer_sellerNACE`

Sample: buyer ∈ regulated-intensive sectors; (seller, buyer) ∈ core-input; 2005–2022; drop contaminated VATs post-2020.

Balancing: for each (seller, buyer) ever active, zero-fill missing years (mirrors `phase4_b2b_supplier_switching.R` logic).

### 3.2 Regression script: `analysis/phase3_b2b_cdgm_did.R`

Spec A (intensive margin, PPML):
```
share_{j,b,t} ~ TREAT_j × { 2005–08, 2009–12, 2013–22 } + FE
where TREAT_j = 1(seller_is_ets) · 1(seller_is_regulated_nace)
```
Outcome = buyer's share of spending within seller_nace4d going to this seller.

Six FE columns paralleling Phase 2:

| Col | FE |
|---:|---|
| 1 | `seller_nace4d^year` |
| 2 | `seller_vat^buyer_vat + year` |
| 3 | `seller_vat^buyer_vat + seller_nace4d^year` |
| 4 | `seller_vat^buyer_vat + buyer_nace4d^year` |
| 5 | `seller_vat^buyer_vat + seller_nace4d^year + buyer_nace4d^year` |
| 6 | `seller_vat^buyer_vat + year^buyer_is_ets` |

Cluster: two-way `seller + buyer`.

Spec B (extensive margin): `1(pair_active_{j,b,t})` LPM with same RHS + FE.

Companion event-study: `analysis/phase3_b2b_cdgm_eventstudy.R` — year-by-year τ dummies, 2005 reference, Figure 3 analog for B2B.

### 3.3 Reuse from `phase4_b2b_supplier_switching.R`

Lift unchanged: contaminated-VAT filter, EUA price series, sector-map build from annual accounts, deflator join, buyer-sector-year share-denominator logic, pair balancing / zero-fill.

Replace: continuous `firm_cost_share_j` → discrete `TREAT_j`; shift from long-difference to phase-aggregated panel PPML to mirror CDGM Table 1 exactly.

**Phase 3 verification:** Expected sign β_2, β_3 **< 0** (ETS-regulated Belgian sellers lose buyer share post-ETS). Magnitude: if domestic leakage parallels cross-border, β_3 in [−0.05, −0.15]. Small or null β would suggest domestic reshuffling is weaker than cross-border leakage — still a publishable finding. Cross-check sign with existing Angle 4 Spec 4.B-event-h at horizons 5–7.

## Sequencing and machines

| Phase | Machine | Blockers | ETA | Output |
|---|---|---|---:|---|
| 0.1 Concordances | local 1 | none | 3 d | `data/concordances/*` |
| 0.2 IO & sector lists | local 1 | FIGARO download | 2 d | `data/io/*` |
| 1 PPI Figure 1 analog | local 1 | Phase 0 | 2 d | Fig 1, reg table |
| 2.1 Customs panel build | RMD | Phase 0 | 3 d | `customs_import_panel_regulated.dta` |
| 2.2 Table 1 + Fig 3–4 | RMD | 2.1 | 3 d | 6-col Table 1, Fig 3, Fig 4 |
| 2.3 Appendix B robustness | RMD | 2.2 | 3 d | B.1, B.3, B.4 |
| 3.1 B2B CDGM panel | RMD | Phase 0 | 2 d | `b2b_cdgm_panel.RData` |
| 3.2 B2B regs + event study | RMD | 3.1 | 3 d | B2B Table + Figure |

Phases 1 and 2 proceed in parallel across local 1 and RMD. Phase 3 can start as soon as Phase 0 completes; independent of Phase 2 but cross-checks with it.

## Decisions to confirm before starting

1. **IO source**: Eurostat national Use table at basic prices for BE (`naio_10_cp1610`),
   A*64 industry x CPA product, 2015 anchor (or 2014-16 average for stability), is the **baseline**.
   This is the BE national-accounts Use table directly, with no bilateral MRIO machinery we don't
   need. **NBB national SUT (P65, BE-native) is co-primary robustness** — run alongside the A*64
   baseline because the granularity check (see Phase 0) found CDGM's 44 NAF-138 R-I sectors
   collapse to 20 NACE-2d parents (borderline zone), with mixed-R-I 3-digit children at C25, C26,
   C30 that A*64 cannot resolve. FIGARO BE (`naio_10_fcp_*`, official EU MRIO) as robustness if
   cross-border sourcing of intermediates matters. Exiobase (163 industries, unofficial but more
   granular) as a fallback only if NBB SUT P65 also collapses too much. Granularity check
   (completed 2026-04-26): the 44 R-I NAF sectors collapse to 20 distinct NACE-2d parents
   (NACE 11, 14-33). Borderline (rule of thumb: ≥25 fine, <15 escalate, 15-24 mixed). Hence the
   co-primary NBB SUT P65 robustness above. Source list parsed to
   [data/concordances/cdgm_table_a5_ri_naf.csv](data/concordances/cdgm_table_a5_ri_naf.csv).
   Note: 2018 is missing from the Eurostat release for `cp1610` BE.
2. **Regulated-product definition**: union of ETS-activity-derived HS codes (CDGM Table A.2) and
   CBAM CN8 list (CDGM Table A.3 / Reg. 2023/956). CBAM supplements rather than extends scope,
   because CBAM only covers goods whose production is ETS-regulated.
3. **Core-input threshold**: run both 10% (CDGM-aligned) and 5% (power robustness for smaller BE sample).
4. **B2B baseline year** (Phase 3): 2005 (CDGM-aligned, ETS Phase 1) as primary; keep 2015 (Angle 4
   MSR baseline) as secondary robustness.
5. **B2B control group** (Phase 3): same-NACE non-ETS seller (preferred, mirrors CDGM's
   unregulated-non-ETS control) vs. ETS seller of unregulated NACE (alternative). Report both.

## End-to-end verification bundle

A successful replication produces:
1. **Table 1 (Belgium)** — 6 FE columns, Phase 3 share coef positive ~0.05–0.20, probability ~0.03–0.10.
2. **Figure 3 (Belgium)** event study — flat pre-2005, visible divergence 2009+.
3. **Figure 4 (Belgium)** with Intrastat break dummy.
4. **Figure B.1 (Belgium)** — leakage concentrated in non-ETS firms.
5. **B2B CDGM Table** (novel) — negative coefficient on `ETS_seller × regulated_NACE_seller × post-ETS`.
6. **B2B event study** — parallel pre-trends; Phase 2/3 divergence.

Benchmark: CDGM's French estimates (Table 1 col (5)): Phase 1 share 0.074**, Phase 2 0.110***, Phase 3 0.121***. Belgian β_3 outside [0.03, 0.25] warrants investigation (contaminated sample, concordance error, or genuinely different mechanism).

## Critical files for implementation

Reference:
- GRANTPA family-tree concordance (CN8↔PC8↔NACE 4d): Bradley, Larch, Flórez Mendoza & Yotov (2024), wiiw WP 248. Local file: `Correspondences_and_dictionaries/product_id_pc8plus_pc8_cn8_final(ID-PC8-CN8 codes final).csv`. Reading notes: [articles/split_concordances_live/notes.md](c:\Users\jota_\Documents\carbon-leakage\articles\split_concordances_live\notes.md) (Magerman 2022 cross-check).
- [articles/split_coster_mejean_digiovanni/notes.md](c:\Users\jota_\Documents\carbon-leakage\articles\split_coster_mejean_digiovanni\notes.md)
- [analysis/phase4_b2b_supplier_switching.R](c:\Users\jota_\Documents\carbon-leakage\analysis\phase4_b2b_supplier_switching.R) — reuse buyer-sector-year share denominator, contaminated-VAT filter, pair balancing
- [analysis/phase0_build_deflator.R](c:\Users\jota_\Documents\carbon-leakage\analysis\phase0_build_deflator.R) — PPI source for Phase 1
- [analysis/phase0_sector_phase_dataset.R](c:\Users\jota_\Documents\carbon-leakage\analysis\phase0_sector_phase_dataset.R) — existing NACE2d allocation-rule list (not a substitute for the 44-sector regulated-intensive filter, but useful for cross-checks)
- [analysis/prodcom_passthrough_stata/02_build_firm_year_euets.do](c:\Users\jota_\Documents\carbon-leakage\analysis\prodcom_passthrough_stata\02_build_firm_year_euets.do) — ETS firm tagging pipeline

New files to create (14 scripts, 11 data artifacts): enumerated in Phases 0–3 above.
