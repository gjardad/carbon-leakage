# Skeleton: Within-NACE-4d reallocation section

This document is a working skeleton for the within-NACE-4d intensive-margin section of the paper. It captures the structure of the argument before we write polished prose. Source material for what each subsection should contain is largely in [WITHIN_NACE.md](WITHIN_NACE.md).

When this skeleton is validated, it moves to `paper/leakage_within_across/sections/` (or replaces the current within-intensive-margin block).

---

## 1. Motivation: what we need from the data

We want to test the leakage hypothesis on the intensive margin within NACE-4d: when carbon pricing raises the cost of regulated suppliers, do buyers shift their expenditure within an input category toward less-exposed alternatives?

Identification requires a source of variation in the supplier-level carbon-cost shock that is plausibly exogenous to within-cell expenditure trends. We use a **continuous-treatment difference-in-differences** design where the treatment intensity for supplier *s* is its predetermined exposure ω_s, and the activating shock is the MSR-induced EUA price hike. Identification rests on three conditions:

1. **Predetermined dose.** ω is fixed before the activating shock. We discuss this in §3.
2. **Exogenous shock.** The MSR-induced EUA price change is exogenous to demand-side factors at the buyer-seller level. We discuss this in §2.
3. **Parallel trends across dose levels.** Suppliers with different ω would have followed parallel within-cell share trajectories in the absence of MSR. We test this with an event study and bound its possible failure with HonestDiD (Rambachan and Roth 2023). We discuss this in §6.

The continuous-treatment DiD framework with these identification conditions is formalized by Callaway, Goodman-Bacon, and Sant'Anna (2024).

---

## 2. Exogeneity of the EUA price variation: the MSR

The EUA price response to MSR is plausibly exogenous to demand-side factors in the buyer-seller relationships we study. The Market Stability Reserve was adopted in October 2015 (Decision 2015/1814) with formal activation scheduled for January 2019. Markets initially did not price in its bite, given the large pre-existing allowance surplus (~2 billion tonnes). The price response started in 2017, driven by the anticipation of the **Phase 4 reform** negotiated through 2017 and adopted in February 2018, which doubled the MSR intake rate (from 12% to 24% for the first five years of operation). EUA prices rose from ~5 EUR/t in mid-2017 to ~25 EUR/t by end-2018, and peaked above 80 EUR/t in 2022.

We follow **De Jonghe et al. (2020)** in treating this tightening as exogenous to firm-level demand-side outcomes. Their identification language is "exploit the tightening in EU ETS regulation in 2017, which led to a steep price increase of emission allowances" — a framing we adopt directly: τ = 2017 captures the start of the price response, even though most of the price action accumulates 2018-2022.

Key references:
- **De Jonghe, Mulier, Schepens (2020).** "Going green by putting a price on pollution: Firm-level evidence from the EU." NBB Working Paper 390.
- **Aldy and Pizer (2016).** "The Impact of the European Union Emissions Trading Scheme on Regulated Firms: What Is the Evidence after Ten Years?" *Review of Environmental Economics and Policy*.
- (Add: Känzig 2023, *AER*, on EUA price shocks as monetary-like shocks; Colmer et al. 2024, *Restud*, on EU ETS treatment effects.)

**[DONE: footnote on MSR mechanics (TNAC, 833M/400M thresholds, 12%→24% intake doubling under 2018/410, cancellation rule) added to `paper/leakage_within_across/sections/leakage_msr.tex`.]**

---

## 3. Cross-supplier variation in exposure: allowance shortage / cost ω

To translate the common EUA price shock into a supplier-specific cost shock, we use the firm's **allowance shortage as a share of total cost** — call this ω. Specifically, for firm s in year t:

```
ω_{s,t}  =  max(emissions_s − free_allocation_s, 0)  ×  EUA_t  /  total_cost_s
```

The numerator is the firm's *net* carbon cost: emissions minus free allowances, times the carbon price. The denominator is total operating cost. ω captures what fraction of the firm's total operating cost is taken up by the carbon price.

### Why this is the right exposure measure

- For an ETS-regulated firm with shortage > 0, ω equals the per-euro cost burden of carbon pricing — the cost the firm pays in the market for each euro of revenue.
- For an ETS firm with surplus allocation (more permits than emissions), shortage ≤ 0 → ω = 0. The firm doesn't pay net carbon costs in the market.
- For a non-ETS firm, ω = 0 by definition.

### Why ω measured in 2015-16 is predetermined

Free allowance allocation in 2015-16 was set under the Phase 3 benchmark methodology, with rules adopted in 2011 (Commission Decision 2011/278/EU) based on emissions data from 2007-2008. So the 2015-16 free-allocation values are **fixed before the MSR reform was even discussed**.

Emissions in 2015-16 are determined by the firm's production technology and output level, both of which are predetermined relative to MSR's effective price impact (2018+).

Total cost in 2015-16 is from the firm's annual accounts, also predetermined.

Result: ω measured in 2015-16 is a function of pre-MSR quantities. It is not a response to the MSR.

**[DONE: footnote in `paper/leakage_within_across/sections/data.tex` cites Commission Decision 2011/278/EU, the top-10\% / 2007--08 benchmark basis, and the predetermined character of the 2014 leakage-list revision.]**

---

## 4. Top-omega and bottom-omega suppliers within a cell

### Sample

A **cell** is a (buyer *b*, NACE 4-digit *n*) pair — a single buyer's sourcing market in one input category. Cells qualify for the sample if:

- The buyer sourced from at least two distinct suppliers active in some year of **2010-2014** (the pre-window).
- At least one of those suppliers was active in some year of **2015-2016** (the ω-measurement window) and had ω > 0 in that window.
- min ω < max ω across suppliers in the cell (meaningful within-cell exposure gap).

Why both windows? The 2010-2014 requirement ensures the relationship existed in a stable pre-policy period; it is not a relationship that appeared in 2015-16 for unrelated reasons. The 2015-16 requirement ensures the supplier was real when the price shock hit — buyers can't fail to substitute away from a supplier that no longer exists.

We argue elsewhere (Section 4 of WITHIN_NACE.md) that the asymmetric anchor approach in raw alternatives produces a mechanical pre-trend artifact; the dual-window approach fixes this.

### Top and bottom assignment

Within each cell:

- **Top-ω supplier**: the single supplier with the highest ω in the 2015-16 window. Sales tiebreaker (descending). In practice, top-end ties are 0% of cells under the shortage-based ω measure (so the tiebreaker is empirically irrelevant for top).

- **Bottom-ω portfolio**: the set of suppliers with the lowest ω in the cell. In most cells (~95% on RMD), the minimum ω is 0, so the bot portfolio consists of all unregulated (or surplus-allowance) suppliers active in the cell. In the ~5% of cells where all suppliers are regulated, the bot is the set of suppliers with the lowest positive ω.

For each cell-year, the **bot share** is the **mean** of the individual within-cell expenditure shares of the suppliers in the bot portfolio. The portfolio approach handles tied suppliers symmetrically: when multiple suppliers qualify as bot (lowest ω), we average their shares rather than arbitrarily picking one via the sales tiebreaker (which would systematically bias bot toward small/fragile relationships — see Section 4 of WITHIN_NACE.md).

**[DONE: 4,997 cells / 22,909 unique pairs / 81,164 cell-role-year obs filled into the sample-sizes table in `paper/leakage_within_across/sections/data.tex`. Across-NACE-4d row remains `\notrun{}`.]**

---

## 5. Descriptive statistics

### 5.1 Distributions of ω by role

Figure: overlaid kernel densities of `ω_top` and `ω_bot` (across cells, one observation per pair per role). On a log x-axis.

Purpose: show that top suppliers have substantially higher carbon-cost exposure than bot suppliers. The mass at ω = 0 (almost all bot) versus the tail of positive ω (top) makes the within-cell exposure contrast vivid.

**[TODO: code this figure. Outputs: `phase4_within_nace4d_descriptive_omega_density.pdf`. ω_top and ω_bot pair-level values are already in the sample construction in `phase4_within_intensive_pretrend_present_in_2010_14.R`.]**

### 5.2 Distribution of the within-cell exposure gap

Figure: kernel density of `ω_top − ω_bot` (one observation per cell). On a log x-axis.

Purpose: show that the within-cell exposure contrast is well-defined and varies meaningfully across cells. The exposure gap is the "treatment intensity" driving the cross-cell variation in our DiD.

**[TODO: code this figure. Outputs: `phase4_within_nace4d_descriptive_exposure_gap_density.pdf`. The exposure gap is already in the cell-level data from `phase4_within_intensive_pretrend_present_in_2010_14.R`.]**

### 5.3 Summary statistics table: top vs bot suppliers

Table: pre-period (averaged 2010-2016) means and medians of supplier characteristics by role.

| Variable | Top-ω (mean / median) | Bot-ω (mean / median) |
|---|---|---|
| Revenue (€M) | ... | ... |
| Employment | ... | ... |
| Firm age (years) | ... | ... |
| Relationship age (years since first observed) | ... | ... |
| Annual emissions (tCO2e) | ... | ... |
| Emission intensity (tCO2e / €M revenue) | ... | ... |
| ω (carbon-cost intensity in 2015-16) | ... | ... |

Purpose: characterise the two groups. Expected pattern: top-ω suppliers are larger, older, more capital-intensive, and more emissions-intensive than bot-ω suppliers.

**[TODO: code this table. Outputs: `phase4_within_nace4d_descriptive_summary_table.tex`. Will require joining additional firm-level data from Annual Accounts (revenue, employment, age) and EUTL (emissions). Need to check whether firm age is available — may need to use first observed year in B2B as a proxy.]**

**Note for prose — EUTL bot firms have higher emissions than EUTL top firms.** A quirk of the RMD summary table that deserves a sentence in the paper: among bot-portfolio members who are in the EUTL registry (only ~7% of the bot pool, vs ~86% of the top group), mean annual emissions are *higher* than for top suppliers in EUTL (RMD: 412k tCO2e bot vs 251k tCO2e top). This is not a contradiction. ω is defined as `max(emissions − free allocation, 0) / total cost` — bot is "lowest ω in cell," and in cells where any supplier is regulated, the lowest-ω bot pool member is typically a firm with ω = 0 because *emissions ≤ free allocation* (surplus allocation), not because it's a small emitter. Under the Phase 3 free-allocation rules, several large emitters in carbon-intensive sectors (cement, steel, refineries) received generous free allowances that fully covered or exceeded their actual emissions, so they appear in EUTL as regulated but face no marginal carbon cost. These firms anchor the bot side of the within-cell comparison. The implication: "least exposed" in our setup means "facing no marginal carbon cost," not "low emissions." A footnote in §3 (definition of ω) or §5.3 (summary stats) should make this explicit.

### 5.4 Within-cell expenditure-share trajectory (τ = 2017 panel)

Figure: mean within-cell expenditure share over 2002-2022 for top-ω vs bot-ω portfolio (single panel, τ = 2017 only).

This is a modified version of `phase4_within_nace4d_intensive_topbot_present_in_2010_14_trajectory.pdf`. Two changes:
- Drop the τ = 2005 panel (the EU ETS launch is conceptually different; for the main paper we focus on MSR).
- Change legend from "Most exposed supplier" / "Least exposed supplier (lowest-ω portfolio)" to "Most exposed supplier" / "Least exposed supplier".

Purpose: visually present the headline pattern — top and bot trajectories over time, with the post-2017 window where the policy effect should appear.

**[TODO: modify `phase4_within_intensive_pretrend_present_in_2010_14.R` or write a small variant that produces only the τ = 2017 panel with the cleaner legend. Outputs: `phase4_within_nace4d_intensive_topbot_present_in_2010_14_trajectory_2017only.pdf`.]**

### 5.5 Differential attrition between top and bot

Figure: age-stratified survival rates of top-ω vs bot-ω relationships in pre-policy and post-policy windows (the existing `phase4_within_intensive_attrition_did_age_stratified.pdf`).

Text discussion (drawing from WITHIN_NACE.md Section on differential attrition):

- We document that top and bot relationships have differential survival rates.
- Pre-policy: top and bot survival curves at the same age are roughly similar (mild gap).
- Post-policy: the gap widens — bot relationships die faster than top relationships at the same age.
- The pre-period survival DiD shows γ_survival > 0 (top survives more than bot post-policy, holding age fixed).
- This matters because it creates **differential trends in observed shares** in the absence of any behavioural reallocation. When a bot pair dies, its share is zero; when a top pair survives, its share is nonzero. The mean within-cell share for top will mechanically pull away from the mean for bot, even with no policy effect on within-relationship allocation.
- The implication is that a naive DiD on within-cell shares would be biased by this differential attrition. We need a specification that controls for the structural pre-trend before identifying the policy effect.

**[Existing figure: `phase4_within_intensive_attrition_did_age_stratified.pdf`. Existing analysis: see WITHIN_NACE.md and the script `phase4_within_intensive_attrition_did.R`.]**

---

## 6. DiD specification

### 6.1 Sample window

Headline DiD window: **2012-2020**. The window starts at 2012 because the raw event study (without any detrending) shows clean, flat pre-period coefficients from 2012 onward, while 2010-2011 are noisy as cells "fill in" toward the 2010-14 pre-window. The window ends at 2020 to keep the post-period inside the MSR price rise (EUA went from ~7 EUR/t in 2016 to ~25 EUR/t at end-2018 to ~30 EUR/t in 2020) without contaminating the comparison with COVID-disrupted 2021-2022 or the 2021-2022 energy crisis. We include 2012-2022 as an appendix robustness.

### 6.2 Specification

The headline regression is at the (cell, role, year) level:

```
share_{c,r,t}  =  α_{c,r}  +  δ_t  +  γ · (post × top)_{r,t}  +  ε_{c,r,t}
```

with:
- α_{c,r}: cell-by-role fixed effects (absorb time-invariant level differences between top and bot in each cell).
- δ_t: year fixed effects (absorb aggregate year shocks affecting all cells equally).
- (post × top)_{r,t} = 1 if t ≥ 2017 and r = top, else 0.
- γ: the treatment effect — the post-2017 change in the top-vs-bot share gap, after netting out cell-role levels and aggregate year shocks.
- Standard errors clustered at the cell level.

Outcome `share_{c,r,t}` is the within-cell expenditure share. For role = top, it's the share of the top-ω supplier. For role = bot, it's the *portfolio mean* across all suppliers tied at the cell's minimum ω.

### 6.3 Identifying assumption and source of variation

The identifying assumption is **parallel trends conditional on cell-role and year fixed effects**: in the absence of the MSR price rise, the post-2017 evolution of the top-bot share gap would have continued along the pre-period trajectory.

The variation that identifies γ comes from cross-supplier heterogeneity in carbon-cost exposure interacted with the post-2017 timing:

- *Cross-cross-cell*: the same calendar year's variation across cells — some cells have higher within-cell ω contrast than others, so the post-2017 change differs across cells under leakage.
- *Cross-year*: within each cell, post-2017 contrast vs pre-2017 contrast.

After absorbing cell-role and year FE, γ identifies the *break* in the top-bot gap at the policy date, on the assumption that the gap would have continued at its pre-period level (constant in expectation) absent MSR. We argue this assumption is plausible because (a) the descriptive trajectory shows roughly flat pre-period top-bot trajectories from 2012 onward (Figure 5.4 cropped), and (b) the cross-supplier exposure variation ω is predetermined by 2015-16 (§3), so cells with high vs low within-cell ω contrast cannot have responded to the post-2017 EUA price rise before it happened.

### 6.4 Three result presentations (RMD numbers)

**(A) Event-study figure** ([`phase4_within_intensive_did_eventstudy.pdf`](output_rmd/figures/phase4_within_intensive_did_eventstudy.pdf), source `phase4_within_intensive_did.R`):

| Year | k | β_k | SE | 95% CI |
|---|---|---|---|---|
| 2012 | −5 | −0.0018 | 0.0079 | [−0.017, +0.014] |
| 2013 | −4 | −0.0005 | 0.0075 | [−0.015, +0.014] |
| 2014 | −3 | −0.0094 | 0.0069 | [−0.023, +0.004] |
| 2015 | −2 | −0.0030 | 0.0067 | [−0.016, +0.010] |
| 2016 | −1 | 0 (ref) | — | — |
| 2017 | 0 | −0.0072 | 0.0055 | [−0.018, +0.004] |
| 2018 | 1 | **+0.0141** | 0.0063 | [+0.002, +0.026] |
| 2019 | 2 | +0.0139 | 0.0071 | [+0.000, +0.028] |
| 2020 | 3 | **+0.0185** | 0.0075 | [+0.004, +0.033] |

Pre-trends: clean and flat at zero. Post-2017: small positive deviations (+1.4 to +1.9 pp), opposite of the leakage prediction. 2018 and 2020 are marginally significant.

**(B) DiD coefficient table with heterogeneity cuts** ([`phase4_within_intensive_did_mht_heterogeneity.tex`](output_rmd/tables/phase4_within_intensive_did_mht_heterogeneity.tex), source `phase4_within_intensive_did_mht.R`):

| Cut | N cells | γ̂ | SE | unadj p | RW p |
|---|---|---|---|---|---|
| Pooled | 4,997 | +0.0080 | 0.0056 | 0.155 | 0.732 |
| **Cost shock top-Q** | 1,249 | **−0.0527** | 0.0105 | < 0.001 | 0.462 |
| **Cost shock top-D** | 500 | **−0.0473** | 0.0151 | 0.002 | 0.606 |
| Input share top-Q | 1,249 | +0.0076 | 0.0075 | 0.31 | 0.776 |
| Input share top-D | 500 | +0.0030 | 0.0098 | 0.76 | 0.792 |
| Exposure gap top-Q | 1,274 | +0.0069 | 0.0103 | 0.50 | 0.792 |
| Exposure gap top-D | 589 | +0.0277 | 0.0155 | 0.07 | 0.732 |

Cost-shock cuts go to the leakage direction at −5 pp; other cuts go opposite. None survive Romano-Wolf multiplicity correction (all RW p > 0.10).

**Companion two-column DiD** ([`phase4_within_intensive_did_coefs.tex`](output_rmd/tables/phase4_within_intensive_did_coefs.tex)): pooled naive vs pair-level with age × top FE.

| Spec | γ̂ | SE | sig |
|---|---|---|---|
| Naive DiD | +0.0123 | 0.0055 | ** |
| Pair-level + age × top FE | +0.0031 | 0.0056 | n.s. |

**(C) HonestDiD bounds** ([`phase4_within_intensive_did_honestdid_bounds.pdf`](output_rmd/figures/phase4_within_intensive_did_honestdid_bounds.pdf), source `phase4_within_intensive_did_honestdid.R`):

Avg post-period γ = +0.0097.

| M̄ | 95% CI |
|---|---|
| 0 (original) | **[−0.001, +0.020]** — marginal exclusion of zero |
| 0.25 | [−0.012, +0.032] — includes zero |
| 0.50 | [−0.028, +0.048] |
| 1.00 | [−0.062, +0.082] |

**Breakdown M̄ ≈ 0.25.** Even tiny pre-trend slack collapses the CI to zero.

### 6.5 Story for the paper

The within-NACE-4d intensive margin response to MSR is **small and not robustly identified**:

- **Pre-trends are clean** in the 2012-2020 window — no ad-hoc detrending needed.
- **Pooled effect is small** (+1.2 pp, anti-leakage direction) and **fragile** to pre-trend slack (breakdown M̄ ≈ 0.25).
- **Suggestive leakage** appears in cost-shock cuts (γ̂ ≈ −5 pp where the carbon-cost incentive is largest), but doesn't survive multiplicity correction.
- **Big effects in either direction are rejected** at reasonable M̄ values.

The most obvious substitution channel — swap your steel mill for a cleaner steel mill within the same input category — is not where carbon leakage shows up. Whatever reallocation the policy did induce operated on other margins (extensive, across-NACE, or imports).

---

## Implementation status

| Section | Artifact | Status |
|---|---|---|
| 2. MSR mechanics footnote | `leakage_msr.tex` | **DONE** |
| 3. Phase 3 benchmark provenance footnote | `data.tex` | **DONE** |
| 4. Sample numbers in headline table | `data.tex` (within-NACE-4d row) | **DONE** |
| 5.1 ω density | `phase4_within_nace4d_descriptive_omega_density.pdf` | **DONE** |
| 5.2 exposure gap | `phase4_within_nace4d_descriptive_exposure_gap_density.pdf` | **DONE** |
| 5.3 summary table | `phase4_within_nace4d_descriptive_summary_table.tex` | **DONE** |
| 5.4 trajectory (2017 only) | `phase4_within_nace4d_descriptive_trajectory_2017_2012_2022.pdf` | **DONE** |
| 5.5 attrition figure | `phase4_within_intensive_attrition_did_age_stratified.pdf` | **DONE** |
| 6. DiD spec, event study, MHT, HonestDiD | `leakage_domestic.tex` | **DONE** |

**Remaining open items**:
1. EUTL-bot-higher-emissions footnote in §5.3 prose — the summary table makes the quirk visible (bot mean 412k vs top 251k tCO₂e) but no prose addresses it; reader may read it as a contradiction. *Deferred.*
2. Across-NACE-4d sample sizes still `\notrun{}` in `data.tex` (outside this skeleton's scope but flagged for completeness).

---

## References to cite

- Callaway, B., Goodman-Bacon, A., and Sant'Anna, P. H. C. (2024). "Difference-in-Differences with a Continuous Treatment." [forthcoming — confirm citation]
- De Jonghe, O., Mulier, K., and Schepens, G. (2020). [Title — confirm citation]
- Rambachan, A. and Roth, J. (2023). "A More Credible Approach to Parallel Trends." *Review of Economic Studies*, 90(5): 2555-2591.
- Silva, J. M. C. S. and Tenreyro, S. (2006). "The Log of Gravity." *Review of Economics and Statistics*, 88(4): 641-658.
- (More to add as we draft each subsection.)
