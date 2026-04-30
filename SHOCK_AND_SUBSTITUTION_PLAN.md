# Combined Plan: Shock Magnitude (Plan A) → Stickiness vs Concentration (Plan B)

## Overall context

[B2B_LEAKAGE.md](B2B_LEAKAGE.md) and [IMPORT_LEAKAGE.md](IMPORT_LEAKAGE.md) document a robust null leakage finding for Belgium. To turn that null into a meaningful empirical claim, two distinct things must be established in sequence:

1. **The cost shock at the firms in our test sample is large enough to make the null informative.** If the shock is too small to plausibly induce substitution, "no substitution" is uninterpretable — neither stickiness nor concentration is implied. **Plan A** establishes this.
2. **Conditional on the shock being real, the null reflects relational stickiness (Heise 2024 mechanism) rather than absence of alternative suppliers (concentration / monopoly).** **Plan B** runs the empirical battery to differentiate.

The two plans are sequential, not parallel: there is no point running B if A returns "shock is too small." Output is two docs, [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md) (Plan A) and [STICKINESS_VS_CONCENTRATION.md](STICKINESS_VS_CONCENTRATION.md) (Plan B).

---

## Plan A — How big is the cost shock?

### Why this comes first

The headline `firm_cost_share` summary statistics from the existing Angle 4 convention (median ≈ 0.000041, p90 ≈ 0.0020, p99 ≈ 0.096) suggest the shock might be tiny in expectation. But three structural features of that measure make the headline numbers misleading for the leakage question:

1. **Time-invariance.** Original `firm_cost_share` uses mean carbon cost 2013–15 over mean total cost 2010–12 — both Phase II / early Phase III windows when EUA was depressed (€2–€10) and free allocation generous. The shock in Phase IV (2021–22, EUA €26–€39, allocation curtailed) is multiples larger.
2. **Heavy right skew.** The median is the wrong moment. The leakage test is identified off the regulated-NACE ETS sellers in our B2B core-input pairs, which are concentrated in the right tail.
3. **Cost-share is per-seller, not per-pair.** Pair-level shock = seller's intensity × buyer's exposure share. The true "what % of buyer's input bill is at risk" can be much smaller than the seller-level intensity.

### Moment 0 — Definition of `firm_cost_share` for Plan A

Plan A is purely descriptive: it characterizes how big the cost shock is as a fraction of firms' costs over time. Since no treatment effect is being estimated here, the Bartik-style endogeneity concern that motivates the original Angle 4 (different years for numerator and denominator) does not apply. Plan A uses the simplest possible definition:

```
firm_cost_share_{j,t} = (shortage_{j,t} × EUA_t) / total_cost_{j,t}
```

with both numerator and denominator measured in the **same year t**.

This sidesteps three issues at once:
- **Pre-2012 years are not a special case.** Same-year is well-defined back to 2005.
- **2005 vs 2017 shock-date is not assumed.** No pre-period denominator means no implicit assumption about when the shock starts binding.
- **Inflation is automatic.** A same-year ratio is unitless; numerator and denominator inflate together at the firm's own price level.

Plan B uses the *original Angle 4 time-invariant* version (numerator mean 2013–15, denominator mean 2010–12) for treatment intensity in regressions, because Bartik-style exogeneity of the denominator is load-bearing there. Plan A and Plan B use different definitions because they answer different questions, and Plan A's verdict on shock size is independent of the regression spec.

**If we later want a Bartik-like instrument as a main result** (e.g., for a structural pass-through estimation), we revisit the denominator definition then with the endogeneity issue handled deliberately.

### Plan A — Six descriptive moments

Each is a table or figure. No regression. Output should fit on two screens.

#### Moment 1 — Time-varying firm-cost-share by phase
Compute the same-year `firm_cost_share_{j,t}` per ETS seller per year. Report distribution (p25, p50, p75, p90, p99, mean, sales-weighted mean) by phase: I (2005–07), II (2008–12), III pre-MSR (2013–17), III post-MSR (2018–20), IV (2021–22).

Headline question: **does p90 in Phase IV exceed 5%? Does p99 exceed 20%?** That range means a real shock at the upper-tail sellers.

Source: [analysis/phase3_build_exposure_panel.R](analysis/phase3_build_exposure_panel.R) outputs and `firm_year_belgian_euets.RData`. New script: `analysis/phase5_shock_distribution_byphase.R`.

#### Moment 2 — Cost-share at the regulated-NACE sellers in the B2B test sample
Restrict to the 224 ETS sellers with computable `firm_cost_share` who appear as treated sellers in [analysis/phase3_b2b_cmdj_did_continuous.R](analysis/phase3_b2b_cmdj_did_continuous.R). Report time-varying distribution for this subset by phase, cross-tabulated by NACE 2d.

Expected per [PASSTHROUGH.md](PASSTHROUGH.md) selection: NACE 19 (refining), 20 (chemicals), 23 (cement), 24 (basic metals) high-cost-share. NACE 21 (pharma), 27 (electrical), 28 (machinery) low-cost-share. If the latter dominates by sales weight, the leakage null is on a near-zero shock.

#### Moment 3 — Effective carbon price per tonne emitted, by phase
Reproduce and extend the table in [PASSTHROUGH.md](PASSTHROUGH.md):

| Phase | EUA range | Free-alloc share | Effective €/tonne | % emissions priced |
|---|---|---|---|---|
| I | €0.07–€3.12 | high | €0.01–€2.74 | 12% |
| II | €0.86–€2.91 | high | €0.13–€2.47 | 15% |
| III pre-MSR | €1.46–€2.67 | falling | €0.49–€2.14 | 34% |
| III post-MSR | €5.62–€9.56 | low | €1.91–€7.18 | — |
| IV | €26.33–€39.39 | low | €13.16–€19.30 | 49% |

The point: **the cost shock 2021–22 is ~40× larger emissions-weighted than 2005–07.** Anchors the headline framing on Phase IV.

#### Moment 4 — Pair-level shock magnitude in the B2B leakage sample
The leakage substitution incentive is the **buyer's exposure to the seller's cost shock**:
```
pair_shock_{j,b,t} = firm_cost_share_{j,t}
                   × (corr_sales_{j,b,t} / Σ_{j' in same NACE 4d as j} corr_sales_{j',b,t})
```
Report distribution (p50, p90, p99, mean, sales-weighted mean) by phase × NACE 2d.

Headline question: **at the p90 pair, what fraction of the buyer's input bill is exposed to ETS-driven cost increases?** < 1% pair-shock even in Phase IV → buyer has no economic reason to switch → null is uninterpretable. > 5% at p90 → null is informative.

New script: `analysis/phase5_pair_shock_magnitude.R`.

#### Moment 5 — Comparison to substitution-relevant benchmarks
Calibrate against three benchmarks of "what cost difference induces a switch":
- (a) Median cross-source-country price gap for the same CN8 in [IMPORT_LEAKAGE.md](IMPORT_LEAKAGE.md) (back-of-envelope; full version is Test F of Plan B).
- (b) Year-over-year input-cost volatility per buyer (σ of Δlog material costs from Annual Accounts).
- (c) Heise 2024 typical FX shock magnitude expressed as % of total cost.

If pair-shock p90 < benchmarks (a)–(c), buyers face a within-noise shock — null is the rational response regardless of mechanism. If pair-shock > benchmarks, null is informative.

#### Moment 6 — Phase IV stress test
Restrict to 2021–22 only. Report Moments 2 and 4, Phase IV only. The most defensible identifying variation. SE wide given only 2 complete years.

### Plan A — Decision rule

| Pair-shock p90 in Phase IV | Verdict | Implication for Plan B |
|---|---|---|
| > 5% | Shock is real | Proceed to Plan B as designed; null is informative |
| 1–5% | Shock is moderate | Proceed but flag in paper that magnitude bounds null interpretability |
| < 1% | Shock is small | Reframe paper to Phase IV only, OR concede null is mechanically driven and pivot the research question |

### Plan A — Files to create

- `analysis/phase5_shock_distribution_byphase.R` — Moments 1, 3, 6
- `analysis/phase5_pair_shock_magnitude.R` — Moments 2, 4
- `analysis/phase5_shock_benchmarks.R` — Moment 5
- [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md) — consolidated doc with verdict at the head

### Plan A — Verification

1. Phase IV p90 sanity check: should be 5–15% for high-intensity NACE. >50% means computation error; <1% means EUA price merge bug.
2. Pair-shock = 0 for non-ETS sellers (mechanical).
3. Cross-check Moment 3 against existing [PASSTHROUGH.md](PASSTHROUGH.md) shock-size diagnostics. Reconcile if any discrepancy.
4. Sales-weighted vs unweighted distributions: weighted mean of pair-shock should be much higher (sales concentrated at high-intensity sellers). If similar, large suppliers are not the regulated emitters — worth flagging.
5. Sector decomposition: cement, refining, basic metals, chemicals should have order-of-magnitude higher cost-shares than pharma, electrical, machinery. If not, regulated-NACE flag is mis-built.
6. Verdict consistency: Moment 1 (population) ≤ Moment 2 (B2B-test subset) ≤ Moment 4 (high-share pairs). If reversed, recheck weighting.
7. Drop firm-years where `total_cost_{j,t} ≤ 0` (loss-making firms make the same-year ratio meaningless or negative). Flag the count of dropped observations.

---

## Plan B — Stickiness vs concentration: the empirical battery

### Why this comes second

Conditional on Plan A returning "shock is real," the null leakage finding is consistent with two stories with overlapping intensive-margin predictions but **opposite-signed predictions on multiple testable margins**.

- **Relational stickiness (Heise 2024 AER):** match-specific relationship capital makes the incumbent supplier strictly preferred even when a cheaper alternative exists. Sellers in young, low-capital relationships absorb cost shocks via lower markups; old, high-capital relationships pass shocks through. Stock looks frozen because *capital* is sticky, not because alternatives don't exist.
- **Concentration / no alternatives:** within the relevant input NACE 4d there are no viable alternative Belgian suppliers. Buyer outside option uniformly low; seller participation constraint never binds; pass-through uniformly complete; stock frozen because nowhere to go.

The downstream paper claim depends on the joint pattern. A coherent stickiness story requires Tests A, B, D, E to point in the stickiness direction. A coherent concentration story is the residual when those tests are null and Test F shows alternative sources/suppliers are not meaningfully cheaper.

### Plan B — Required infrastructure (two prep steps)

#### Prep 1 — Pair-age derivation
The B2B panel built in [analysis/phase3_build_b2b_cmdj_panel.R](analysis/phase3_build_b2b_cmdj_panel.R) lacks a pair-age column. New script `analysis/phase5_build_pair_age.R`:
- Read raw `B2B_ANO.dta` (RMD) or `b2b_selected_sample` (local-1 testing).
- Compute `first_year_pair = min(year)` per (seller, buyer).
- Derive `pair_age = year - first_year_pair` and `is_new_pair_t = (year == first_year_pair)`.
- Save as `b2b_pair_age.RData` keyed on (seller, buyer); join into both Phase 3 binary and continuous panels.
- **Caveat for the doc:** B2B starts 2002. Pairs with `first_year_pair = 2002` may be left-censored. Treat as separate "left-censored" stratum.

#### Prep 2 — Build the two `firm_cost_share` flavors
Each test in Plan B uses a different definition because each test answers a different question. Move both constructions out of [analysis/phase3_b2b_cmdj_did_continuous.R](analysis/phase3_b2b_cmdj_did_continuous.R) into a single utility script `analysis/phase5_attach_firm_cost_share.R` that produces two columns on the seller-year level and joins both into the panel:

- **`firm_cost_share_outcome_{j,t}`** — used as outcome in Test A. `firm_cost_share` is on the LHS so Bartik exogeneity is not needed; we just want a clean per-year exposure measure that is interpretable for all years 2003–2022. Definition: `(shortage_{j,t} × EUA_t) / total_cost_{j,t-1}`. Numerator in year t, denominator lagged one year. Works for all years where the seller has a t-1 observation.
- **`firm_cost_share_regressor_j`** — used as regressor in Test B. Treatment intensity needs to be pre-shock and not endogenous. Single time-invariant value per seller, computed as `mean_{2012-14}(shortage × EUA) / mean_{2012-14}(total_cost)`. Anchored to a window that precedes the 2015 binding-shock date but is late enough that shortage starts to be meaningful (free-allocation share has fallen). **Plan B Test B runs only the post-2015 version** because pre-2012 numerator does not reflect a real cost shock under the generous Phase II free-allocation regime — there is no defensible way to define a comparable pre-period treatment intensity for a 2005-binding shock with our data.

### Plan B — Test battery

Four tests. **G is the foundational test ("if substitution happens anywhere, it should happen here").** A and B are the broader cleanest separators; C is a descriptive precondition. Tests D, E, F from the original draft are deferred — see "Deferred tests" subsection below for why.

#### Test G — Feasibility-restricted substitution test (foundational; load-bearing)

**The least-demanding empirical test of substitution.** Restricts to buyer × NACE 4d cells where substitution should be most feasible if it happens anywhere: large pair-shock + multiple ETS suppliers within the same input NACE 4d + substantial intensity spread among them. If substitution is null even on this favorable subset, the broader-sample tests (A, B) are unlikely to find anything either. If substitution shows up here, then A and B identify whether stickiness selectively suppresses it elsewhere.

**Cell construction.** Unit: `(buyer × input-NACE 4d × year)`. For each cell compute:
- `n_ets_sellers` = number of ETS sellers j whose seller-NACE 4d == cell's input NACE 4d.
- `spread` = `max_j firm_cost_share_j − min_j firm_cost_share_j` over the ETS sellers in the cell.
- `max_pair_shock` = `max_j (firm_cost_share_j × corr_sales_{j,b,t} / Σ_{j' in cell} corr_sales_{j',b,t})`. Within-NACE-4d shock magnitude (option (b) in shock-magnitude framing).
- `max_pair_shock_total` = `max_j (firm_cost_share_j × corr_sales_{j,b,t} / inputs_VAT_{b,t})`. Total-input shock magnitude (option (c)). Apples-to-apples with σ_share.

**High-power subset filter:**
1. `n_ets_sellers ≥ 2` (alternative ETS supplier exists; required for substitution to be feasible).
2. `spread ≥ θ_spread` — meaningful intensity gap. Starting threshold: `θ_spread = 0.005` (50 bp of cost-share). Robustness: also try `θ_spread = 0.01` and a relative-spread alternative `max_j / min_j ≥ 5×`.
3. `max_pair_shock_total ≥ θ_shock_total` — the cell's biggest ETS position must materially affect the buyer's TOTAL cost structure, not just within-NACE costs. Starting threshold: `θ_shock_total = 0.005` (0.5% of buyer's total input bill). This is the binding filter: it ensures the buyer would actually notice the shock at their total-cost level, against their σ_share noise floor of ~15%.

**Why filter on `max_pair_shock_total` rather than `max_pair_shock`:** A cell with a 5% pair-shock at NACE-4d level but only 1% NACE-share-of-total-inputs gives a buyer-total exposure of 0.05% — too small to motivate switching effort, however large it looks within-NACE. The substitution decision is made *given* that the buyer cares about this NACE 4d at the total-cost level. Filtering on `max_pair_shock_total` ensures we select cells where the buyer would actually act.

**Empirical expectation.** Per [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md), pair-shock-total p90 is 1.16% across all Phase IV ETS pair-years; only cement-buyer cells (NACE 23) have p90 in the meaningful 5–10% range. The high-power subset will therefore be **predominantly cement-buyer cells, with a handful of NACE 32 (other manufacturing) cells and other oddballs**. The threshold-based filter is preserved (rather than a sector-based filter) so we don't exclude a buyer at the upper percentile of pair-shock-total just because they're not in cement — but *de facto* the test will be cement-heavy.

**Expected sample size.** With `θ_shock_total = 0.005` (0.5%), we expect roughly the top 5–8% of Phase IV ETS pair-years (≈ 200–300 distinct cells) to survive the filter, dominated by cement. Robustness with looser thresholds (θ_shock_total = 0.001) would expand to ~500 cells; stricter (θ_shock_total = 0.02) restricts to <100 cells, mostly cement-input-heavy buyers.

**Sample for the regression.** All `(seller × buyer × year)` rows where the corresponding `(buyer, NACE 4d, year)` cell satisfies the high-power filter. **Includes non-ETS sellers in the same NACE 4d as zero-intensity rows** (`firm_cost_share = 0`). They are the dominant substitution path in many cells and serve as the natural "control" trajectory.

**Specification G1 (granular, headline):**
```
share_{j,b,n,t} = β · firm_cost_share_j × Post_t
                + α_{j,b} + δ_{n × t} + ε

share_{j,b,n,t} = corr_sales_{j,b,t} / Σ_{j' in cell n} corr_sales_{j',b,t}
firm_cost_share_j = time-invariant pre-shock value (mean 2012-14, from Prep 2)
                  = 0 for non-ETS sellers
Post_t          = 1(t ≥ 2015)        # MSR-binding date, consistent with Test B
α_{j,b}         = pair fixed effect
δ_{n × t}       = NACE 4d × year FE
```
Cluster on `seller × buyer` (two-way) per Phase 3 convention.

**The dependent variable is each seller's share — heavy and light.** β is identified off the differential trajectory of high-vs-low-intensity sellers within the same buyer-NACE-4d portfolio post-shock.

**Predictions:**
- *Substitution exists:* β < 0. After the shock binds, high-intensity sellers lose share within the buyer's NACE-4d spending; low-intensity sellers (including non-ETS at zero intensity) gain. **This is the substitution signature.**
- *Stickiness or shock-too-small:* β ≈ 0. No reweighting on intensity even where substitution is most feasible.
- *Counterintuitive (rare):* β > 0. Heavy sellers gaining share post-shock. Would only happen for unrelated reasons (e.g., heavy sellers happen to be growing).

**Specification G2 (aggregated, descriptive):**
```
weighted_intensity_{b,n,t} = Σ_j (share_{j,b,n,t} × firm_cost_share_j)

weighted_intensity_{b,n,t} = β · Post_t + α_{b,n} + δ_{n,t} + ε
```
G2 is the cell-level intensity-weighted average exposure (single number per cell). Substitution toward low-intensity sellers makes this fall. Same logical content as G1; G2 is what to plot over time.

**Predictions:** β < 0 (substitution) vs β ≈ 0 (null), parallel to G1.

**Robustness:**
- Threshold sensitivity: report estimates for grids of `θ_spread ∈ {0.001, 0.005, 0.01, 0.02}` and `θ_shock_total ∈ {0.001, 0.005, 0.01, 0.02}`. The high-power subset shrinks with stricter thresholds; we want the result to be stable, or at least to move monotonically (stronger substitution at stricter filters = good — substitution should be strongest where the shock is biggest).
- Pre-2012 placebo: re-run on the 2005–2014 window with `Post_t = 1(t ≥ 2010)` or similar. Should give β ≈ 0 if the post-2015 estimate is causal.
- Sector decomposition: split by buyer NACE 2d. Per [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md), cement (NACE 23 buyers) is where the shock is large enough relative to background noise to be detectable (signal-to-noise ≈ 0.68σ). The high-power subset will be predominantly cement-buyer cells — report the cement-only estimate as the load-bearing result. The handful of non-cement cells that survive the filter (NACE 32 and oddball cement-input-heavy buyers in non-cement sectors) are useful for confirming the result isn't sector-specific to cement.
- Also report the broader "any pair-shock-total > θ" sample without the spread/n_ets filter, as a sanity check that the within-NACE substitution feasibility filter isn't doing all the work.

**Output:** `output/tables/phase5_test_g_feasibility_restricted.csv` with G1 estimates across threshold combinations, plus G2 cell-level series (descriptive). `output/figures/phase5_test_g_weighted_intensity_by_year.pdf` plots `weighted_intensity` over time within high-power cells, by NACE 2d.

**Sample size caveat:** the high-power filter is restrictive **by design**. The whole point is to identify where substitution should be most plausible. With `θ_shock_total = 0.005` we expect ~200–300 cell-years in Phase IV, dominated by cement-buyer cells. SE will be wide. That is the cost of running the test on the right subsample. If the resulting power is too low to reject moderate β values, that itself is a finding — the universe of "feasible-substitution AND meaningful-buyer-cost-impact" cells in Belgian B2B is small, dominated by cement, and concentrated in Phase IV.

#### Test A — New-pair carbon-intensity tilt (the extensive-margin separator)

**Cleanest single separator. Headline test.**

**Sample:** Universe of new (seller, buyer) pairs formed in year t (`is_new_pair_t == 1`). Restrict to regulated-intensive buyer NACE (Phase 0 list) and core-input pairs as in Phase 3.

**Outcome:** seller's carbon intensity at the time of match. Since cost-share is on the LHS, the Bartik exogeneity argument that motivates the original Angle 4 convention does not apply — we just need a clean per-year measure of the seller's actual exposure interpretable for all years. Use:
- (A1) `firm_cost_share_outcome_{j,t}` (continuous; numerator year t, denominator year t-1; defined in Prep 2).
- (A2) Within-NACE4d intensity rank of seller in year t, normalized to [0,1], where intensity is (A1).

**Specification:**
```
intensity_seller = α + β1·1(t ∈ 2005-2016) + β2·1(t ∈ 2017+)
                 + δ_{seller_NACE4d × year} + ε
```
Cluster on seller_NACE4d. Pre-period 2002–2004 omitted reference. The 2017 break uses post-MSR Phase III + Phase IV when shortage starts pricing — consistent with Plan A's framing of the binding shock.

**Predictions:**
- *Stickiness:* β1 < 0 (mild), β2 < 0 (stronger). New buyers — choosing fresh, not locked into a sticky relationship — tilt toward lower-intensity sellers.
- *Concentration:* β1 ≈ 0, β2 ≈ 0. New buyers also have to match with whoever exists.

**Robustness:**
- Weighted by initial pair sales (β reflects new-trade-value composition).
- Within-buyer-NACE × year FE (test from buyer's perspective).
- Restrict to non-left-censored pairs (drop 2002 first-year pairs).
- Conditional-logit choice version (A3): each new pair as discrete choice over potential same-NACE4d sellers, with seller intensity as regressor. Secondary.

**Output:** `output/tables/phase5_test_a_new_pair_tilt.csv`, `output/figures/phase5_test_a_event_study.pdf` (year-by-year coefficients). Plus stock-vs-flow plot per Heise §4.2 logic: average seller-intensity in (i) all active pairs and (ii) new pairs only, by year. The two series diverging post-ETS *is* the stickiness-on-stock-substitution-on-flow signature.

#### Test B — Survival hazard by seller intensity × pair age

**Why:** stickiness predicts old pairs are *less* responsive to ETS shocks than young pairs (Heise's break-up hazard falls with age, constraint binds harder for low-capital pairs). Concentration predicts hazard uncorrelated with seller intensity at any age.

**Sample:** All (seller, buyer) pairs with `pair_age ≥ 1`, 2012–2022. Regulated-intensive buyer NACE.

**Outcome:** `pair_dies_t = 1` if pair active in t-1 but not in t (or never re-appears).

**Specification (linear probability):**
```
pair_dies_t = γ · firm_cost_share_regressor_j × 1(t ≥ 2015) × pair_age_bucket
            + α_{pair} + δ_{NACE4d × year} + ε
```
where `firm_cost_share_regressor_j` is the time-invariant pre-shock measure from Prep 2 (mean 2012–14 numerator and denominator), `pair_age_bucket ∈ {1-3, 4-7, 8+ years}`, and the post-shock indicator is single-period (`t ≥ 2015`).

**No pre-2015 / 2005–2014 specification is run.** With Phase II's generous free allocation, the numerator (shortage × EUA) does not reflect a real cost shock for the population of ETS sellers in that window. There is no defensible way to define a comparable treatment intensity for a 2005-binding shock with these data; we revisit this only if a Phase 1 result becomes load-bearing.

**Predictions:**
- *Stickiness:* γ > 0 strongest for young pairs (the 1–3 year bucket). Young pairs at high-intensity sellers die more after 2015; old pairs persist.
- *Concentration:* γ ≈ 0 across all age buckets.

**Output:** `output/tables/phase5_test_b_hazard.csv` with γ by age bucket.

#### Test C — Heise life-cycle moments on Belgian B2B (descriptive precondition)

**Why:** if Belgian B2B doesn't have *any* of Heise's life-cycle features, a stickiness story isn't plausible to begin with. This test establishes whether Heise-type relational dynamics exist before claiming they explain the null.

**Moments (descriptive, no regression):**
- (C1) Distribution of pair lengths and trade-value share by length bucket. Analog of Heise Figure 1a.
- (C2) Cross-sectional and within-total-duration trade-volume life-cycle (Heise Figure 2a). Within τ*=N year cohorts, plot mean log(corr_sales) by relationship-year, normalized to year 1. Hump = relational dynamics; flat = pure scale persistence.
- (C3) Break-up hazard by pair age (Heise Figure 2b).

(Heise's product-count moment is not reproducible — Belgian B2B records only total annual sales between a pair, not the product mix.)

**Output:** `output/figures/phase5_test_c_lifecycle.pdf` (multi-panel) and a paragraph in the doc.

**Decision rule:** if life-cycle is essentially flat and trade-share of long-duration pairs small, stickiness story is weak — concentration is the more parsimonious explanation regardless of A/B/D/E.

#### Deferred tests (D, E, F)

**Tests D and E (pair-level value response by relationship age, and buyer outside-option heterogeneity).** Both rely on a clean, exogenous, time-varying carbon-cost shock interacted with `firm_cost_share`. Using `ΔEUA_t` directly is contaminated by general macro/oil/gas conditions that also affect sales. The natural fix is Känzig's CPShock or Surprise — but [PASSTHROUGH.md](PASSTHROUGH.md) S7–S10 already documents that Surprise has dead first stages at the annual frequency (cluster-F ≈ 0.05) and Shock-based identification imports Känzig's 8-variable VAR structure. Defer until Tests A, B, C tell us whether the stickiness narrative is worth deepening; if yes, reopen the Känzig-shock-vs-surprise question deliberately.

**Test F (cross-border alternative-source price diagnostic).** Dropped. The original framing (small gap + no switching = stickiness; large gap + no switching = concentration) is testing whether non-ETS *country* sourcing is a feasible alternative to ETS *country* sourcing. That is a different question than whether *Belgian* high-intensity sellers can be substituted by other *Belgian* sellers in the same NACE 4d (the domestic stickiness-vs-concentration question). The cross-border price gap doesn't speak to the domestic-substitution null at the heart of [B2B_LEAKAGE.md](B2B_LEAKAGE.md).

#### Add-on test (open) — Across-NACE-category substitution under ETS exposure

The existing battery (Tests A, B, G) operates at the **within-NACE-4d, between-Belgian-sellers** level — does buyer reroute among sellers of the same product category? The China-shock work in [ALTERNATIVE_SHOCKS_TO_ESTIMATE_ELASTICITY.md](ALTERNATIVE_SHOCKS_TO_ESTIMATE_ELASTICITY.md) (E3 Version A) raises a complementary question we have not asked of the ETS shock:

> **Do Belgian buyers shift their input *category* mix away from ETS-regulated NACE 4d categories toward non-regulated ones in response to ETS-driven cost increases?**

The China shock has natural product-level variation (different HS6 categories saw different ChinaShare gains), which makes a category-level reduced form natural. The ETS shock has natural firm-level variation (different sellers within an NACE 4d have different `firm_cost_share`), which is why the existing battery is firm-level. But the ETS shock also has category-level variation: average `firm_cost_share` differs across NACE 4ds (cement vs pharma vs machinery), and the regulated-vs-not distinction is itself a category-level variable.

A future test — call it **Test H** — would regress:
```
Δlog(B2B sales to Belgian buyers from sellers in NACE 4d n) ~ avg_firm_cost_share_n × Post + ε
```
or the cleaner regulated-vs-not version. Identification is across NACE 4d categories, pooled across sellers within each category. Negative slope = buyers shift away from regulated/high-cost categories at the input-category level. Together with Test G (within-category seller substitution), Test H would close the loop on whether the leakage null is a within-category null, an across-category null, or both.

Not implemented yet. Logged here for symmetry with the China-shock E3 design and as a candidate addition once the China-shock work establishes whether category-level substitution is a meaningful margin in Belgian B2B. If the China shock E3 Version A returns a clean negative slope, Test H becomes more interesting — it would let us compare the across-category substitution elasticity for two very different shocks (carbon, China) on the same Belgian B2B network.

### Plan B — Decision rule (joint pattern)

Summary table at head of `STICKINESS_VS_CONCENTRATION.md`:

| Test | Substitution / stickiness sign | Concentration / no-substitution sign |
|---|---|---|
| **G — feasibility-restricted** | **β < 0** (substitution exists where most feasible) | **β ≈ 0** (no substitution even on the favorable subset) |
| A — new-pair tilt | β2 significantly < 0 | β2 ≈ 0 |
| B — hazard by age | γ > 0, concentrated in young pairs | γ ≈ 0 |
| C — life-cycle moments | hump trade volume, declining hazard | flat profile |

**Test G is the foundational decision point.** Run G first.

Per [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md), the high-power subset Test G operates on is **predominantly cement-buyer cells** — that's the only sector where the pair-shock-total reaches a meaningful fraction of buyer total inputs (cement-buyer p90 = 8.80%, signal-to-noise 0.68σ). The threshold-based filter (rather than a sector-based filter) keeps the door open for non-cement cells that happen to clear the bar (NACE 32, oddball construction-adjacent buyers in NACE 22/13/etc.), but expect cement to dominate.

- **G's β < 0**: substitution exists where it's most feasible AND meaningful at the buyer's total cost. Then run A, B, C: A tells whether the *new-formation* margin tilts the same way; B tells whether *break-up rates* respond to intensity; C tells whether relational dynamics exist generally. The set of (G, A, B, C) tells you whether substitution is broad-based or restricted to the high-power subset.
- **G's β ≈ 0**: no substitution even where most feasible AND most exposed. Two interpretations:
  - *Stickiness dominates*: relational capital is so strong that even cement buyers facing 0.68σ pair-shock-totals don't reweight. This is the most economically meaningful case — Belgian buyers are sticky enough to absorb a near-detectable shock without acting.
  - *Shock still too small*: even at 0.68σ, the cement signal isn't quite enough to motivate switching effort against natural cost noise. Plausible but weaker — at this magnitude relative to noise, a sophisticated buyer would notice.
  Tests A and B then become diagnostics on which of these is operative — A tells whether new pairs (where stickiness is absent) tilt low-intensity (would rule out shock-too-small if we see substitution there), B tells whether young pairs at high-intensity sellers die more (would point to stickiness-by-age).

Coherent stickiness narrative requires G null + A negative on new-pairs + B positive on hazard + C shows life-cycle. Coherent shock-too-small requires G null + A null + B null + C flat. Coherent concentration is the residual when alternatives are absent — Test G's filter `n_ets_sellers ≥ 2` already excludes most of the concentration story, so a null G *cannot* be due to concentration alone within its subset.

Mixed signals across A, B, C with a non-null G likely mean **both channels operate, varying by sector** — split G, A, B by NACE 2d. Empirical expectation: cement (NACE 23) is the only sector with enough Phase IV exposure to make the test meaningful; non-cement sectors will likely have insufficient power for a clean reading.

If the joint pattern is consistent with stickiness, the deferred Tests D and E become the natural next step (with Känzig-shock-vs-surprise resolved deliberately). If consistent with concentration or shock-too-small, the deferred tests are unlikely to add — the paper's story is concentration- or magnitude-driven and the ancillary battery is small.

### Plan B — Files to create

- `analysis/phase5_build_pair_age.R` — Prep 1
- `analysis/phase5_attach_firm_cost_share.R` — Prep 2 (both `firm_cost_share_outcome_{j,t}` and `firm_cost_share_regressor_j`)
- `analysis/phase5_test_g_feasibility_restricted.R` — **Test G (run first)**
- `analysis/phase5_test_a_new_pair_tilt.R` — Test A
- `analysis/phase5_test_b_hazard.R` — Test B
- `analysis/phase5_test_c_lifecycle.R` — Test C
- [STICKINESS_VS_CONCENTRATION.md](STICKINESS_VS_CONCENTRATION.md) — consolidated doc

Each script reuses patterns from [analysis/phase3_b2b_cmdj_did_continuous.R](analysis/phase3_b2b_cmdj_did_continuous.R) and [analysis/phase3_b2b_cmdj_eventstudy.R](analysis/phase3_b2b_cmdj_eventstudy.R): `fixest::feols`, two-way clustering on (seller, buyer), col(5)-style FE structure, `data.table` for prep, `ggplot2` + `patchwork` for figures. Same output conventions as Phase 3 (CSV in `output/tables/`, PDF in `output/figures/`).

### Plan B — Verification

1. **Prep 1 sanity:** spot-check 10 random pairs; verify `pair_age = year - first_year_pair` is monotone within (seller, buyer) and `is_new_pair_t == 1` exactly once per pair.
2. **Test G runs FIRST:** the foundational test. Report β at multiple threshold combinations (`θ_spread × θ_shock` grid). If β < 0 robustly, substitution exists on the high-power subset. If β ≈ 0 across the grid, the substitution channel is null even where it should be most feasible — proceed to A and B as diagnostics for *why*.
3. **Test G high-power subset size:** report the cell count and the implied SE. If the subset is ≤ 100 cell-years even at the loosest thresholds, flag this as a structural feature of Belgian B2B — there are simply few feasible-substitution opportunities. That observation is itself a finding.
4. **Test C runs next:** if life-cycle is flat (no hump, flat hazard), abort the stickiness narrative and write the doc as "either shock-too-small or concentration; no evidence of relational stickiness in Belgian B2B."
5. **Test A is the broader headline:** β2 sign + magnitude + significance is the load-bearing number for the new-pair channel. Run with two intensity definitions (continuous A1 and rank A2) and three sample restrictions (full, drop-left-censored, ETS-buyers-only).
6. **Test B's single post-2015 spec:** the result depends on this single specification. Document explicitly that a 2005-binding-shock version was not run because pre-2012 numerator does not capture a real cost shock under generous Phase II free allocation.
7. **Sector decomposition:** run G, A, and B split by NACE 2d. Expectation per [PASSTHROUGH.md](PASSTHROUGH.md) selection and [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md): NACE 23 (cement) is where the shock is largest and where Test G should have most identifying power. NACE 24 (basic metals), 19 (refining) likely concentration-bound; NACE 20 (chemicals), 21, 27, 28 likely stickiness-bound or shock-too-small.
8. **Cross-check with [PASSTHROUGH.md](PASSTHROUGH.md) Section B (S12):** the +4.08 monthly LP coefficient at h=12 implies *some* pass-through at the sector level. Whether this is consistent with the joint G+A+B+C pattern is part of the doc's interpretation.
9. **Sanity vs Heise:** Test C (C1, life-cycle distribution) should yield a plausible Belgian analog of Heise's 33%/57%/9% Figure 1a numbers. Dramatic differences (e.g., almost all pairs >5 years) should be flagged as setup difference.

---

## Combined hardware / data caveats

- **B2B coverage:** local-1 has downsampled B2B + full training sample; full universe only on RMD. Pair-level distributions need full data for tail reliability. Plan: prototype on local-1 downsampled, run final numbers on RMD.
- **ETS firm-year panel:** full on RMD and full on local-1.
- **PRODCOM is mocked on local-1 and RMD** (only co-author has the real data). Plan A and Plan B's three tests do not depend on PRODCOM; the deferred Test D's price-decomposition robustness would.
- **B2B starts 2002.** 2002 first-year cohort is left-censored; treat as separate stratum throughout. Test A's `firm_cost_share_outcome_{j,t}` is undefined for t = 2002 because it needs t-1 = 2001 — so the effective sample for Test A starts in 2003.
- **3 contaminated VAT hashes in NACE 20/24 post-2020** (per MEMORY.md). Drop these from `firm_cost_share` computation and from any sample where seller is one of these VATs.
- **Pre-2012 cost-share computation (Plan A):** same-year ratio works for all years 2005–2022 with no special case.

The doc closes (Plan B) with a short statement of which story (or which mix) the joint pattern supports, framed as a contribution to the relationship-stickiness literature (Heise 2024; Bernard et al. 2022 JPE; Macchiavello–Morjaria 2015) and to the carbon-leakage policy literature (Coster–di Giovanni–Méjean 2025; Fabra–Reguant 2014).
