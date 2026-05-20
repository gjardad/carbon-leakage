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

**[TODO: add a brief footnote on MSR mechanics — surplus indicator, threshold, intake rule.]**

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

**[TODO: more precise dates on Phase 3 benchmark rules; cite the EU regulation.]**

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

**[TODO: include sample numbers — N cells, N pairs, N pair-years on RMD.]**

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

**[Deferred — to be discussed.]** The natural candidates are:

1. **Naive DiD (level shares)**: `share ~ post:top | cell_role + year`. No pre-trend correction. Biased by differential attrition.
2. **Linear pre-trend DiD**: adds `(year − 2017) × top` to absorb a linear differential trend.
3. **Age × top FE DiD**: controls for age-dependent differential between top and bot. Has collinearity issues with full event study but works for the single-coefficient DiD.
4. **Option 2A**: pre-policy baseline `f_role(age)` subtracted from share; restrict to ages 0-6 (no extrapolation).
5. **Option 2B**: pre-policy baseline with geometric extrapolation to ages 7-12.
6. **HonestDiD bounds**: report Rambachan-Roth-style bounds on the post-period treatment effect under varying assumptions about the pre-trend.
7. **Structural CES (PPML)**: estimate the elasticity of substitution σ directly, with `share ~ post:omega | cell_role + year, family = poisson`.

**Suggested discussion points for picking the spec(s) to include:**
- Which is the "headline" (probably HonestDiD on the linear-pre-trend or Option 2B event study).
- Which to include as robustness in main text vs appendix.
- How to frame the disagreement between specs (sign-sensitive to specification).
- Whether to also show the structural CES σ estimate in main text or appendix.

---

## Implementation status

| Section | Artifact | Status |
|---|---|---|
| 5.1 ω density | `phase4_within_nace4d_descriptive_omega_density.pdf` | **TODO** |
| 5.2 exposure gap | `phase4_within_nace4d_descriptive_exposure_gap_density.pdf` | **TODO** |
| 5.3 summary table | `phase4_within_nace4d_descriptive_summary_table.tex` | **TODO** |
| 5.4 trajectory (2017 only) | `phase4_within_nace4d_intensive_topbot_present_in_2010_14_trajectory_2017only.pdf` | **TODO** (small edit to existing) |
| 5.5 attrition figure | `phase4_within_intensive_attrition_did_age_stratified.pdf` | **Exists** |
| 6. DiD spec | Various | **Exists** in WITHIN_NACE.md, decision deferred |

**Proposed next steps**:
1. Write a single new script `analysis/phase4_within_nace4d_descriptive.R` that produces 5.1, 5.2, and 5.3 (the ω densities, exposure gap density, and summary stats table). All three share the same sample construction.
2. Write a small variant or argument to existing `phase4_within_intensive_pretrend_present_in_2010_14.R` for 5.4 (only the τ = 2017 panel, simpler legend).
3. Confirm 5.5 figure (`phase4_within_intensive_attrition_did_age_stratified.pdf`) is the right one — or discuss whether we want a different attrition visual.
4. Validate this skeleton with the user, then re-discuss Section 6 (DiD spec).

---

## References to cite

- Callaway, B., Goodman-Bacon, A., and Sant'Anna, P. H. C. (2024). "Difference-in-Differences with a Continuous Treatment." [forthcoming — confirm citation]
- De Jonghe, O., Mulier, K., and Schepens, G. (2020). [Title — confirm citation]
- Rambachan, A. and Roth, J. (2023). "A More Credible Approach to Parallel Trends." *Review of Economic Studies*, 90(5): 2555-2591.
- Silva, J. M. C. S. and Tenreyro, S. (2006). "The Log of Gravity." *Review of Economics and Statistics*, 88(4): 641-658.
- (More to add as we draft each subsection.)
