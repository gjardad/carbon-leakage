# Stocktake — Plan B (stickiness vs concentration vs shock-too-small)

This doc records the Plan B test results. **Headline:** the leakage null is driven by **shock-too-small**, not by stickiness or concentration. The stickiness branch of the original two-way framing is set aside — interesting on its own merits but not a paper claim. Concentration is ruled out cleanly by the Test G followup.

For the planning context behind these tests, see [SHOCK_AND_SUBSTITUTION_PLAN.md](SHOCK_AND_SUBSTITUTION_PLAN.md). For the magnitude evidence that anchors the "small shock" verdict, see [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md).

## Verdict

The carbon shock is too small to drive observable substitution among Belgian buyers. The G followup adds two new facts that reinforce this:

1. **9% of all Belgian B2B buyers (27,053 firms) buy from at least one ETS-treated supplier inside a NACE 4d where they also have alternative suppliers.** This is a substantial slice of the economy facing a real substitution decision — not a rare edge case.
2. **70% of all buyers have multi-supplier alternatives within an ETS-relevant NACE 4d** — concentration is *not* the binding constraint on substitution. The substitution opportunity exists for most buyers; they just don't take it because the cost shock is below their noise floor.

The conclusion that follows: even when the substitution decision is structurally feasible (count [3] of the followup) and even when the buyer faces an ETS supplier (the 9%), the buyer doesn't reweight away from heavily-exposed sellers — because the cost shock at the buyer-total-cost level is below the buyer's σ_share input-cost noise floor (per [SHOCK_MAGNITUDE.md](SHOCK_MAGNITUDE.md)). This is a clean magnitude story, not a behavioral or institutional friction story.

## What's used in the paper

- **Test G (feasibility-restricted)** — the substitution test cannot be powered: only 1 cell passes the default thresholds even on the full 112M-row B2B universe. This is itself a result: high-power "feasibility AND material exposure" cells are vanishingly rare. The threshold-grid robustness across (θ_spread, θ_shock_total) confirms it.
- **Test G followup (substitution universe diagnostic)** — three counts:
  - 117 NACE 4d sectors have ≥1 ETS firm (22% of the 540 NACE 4d sectors in B2B).
  - 1,574,640 (buyer × NACE 4d × year) cells with ≥2 suppliers in the same NACE 4d in the treated set; 214,675 distinct buyers (70% of 307K).
  - 146,892 cells with [2] AND ≥1 ETS supplier; **27,053 buyers (9%)**.
  - 44,680 cells with [2] AND ≥2 ETS suppliers (Test G's strict filter); 8,480 buyers (3%).

The 9% and 70% numbers go in the paper. The 3% number sets up Test G's empty filter.

## What's parked (not in paper)

These results are noted for completeness but are not load-bearing for the paper claim. They are not strong enough on their own and the paper does not need a stickiness narrative to explain the null.

### Test C — Heise life-cycle moments
Belgian B2B exhibits Heise (2024 AER) relational dynamics:

- **C1.** Pairs older than 5 years are 18% of pairs but **79% of trade by value** (full RMD universe; non-left-censored).
- **C2.** Within total-duration cohorts, mean log(corr_sales) rises monotonically with pair age (from 0 at age 0 to +1.24 at age 15 in the 11-21y cohort). No terminal-year "hump" of the kind Heise documented; trade volume scales up through the final year.
- **C3.** Break-up hazard falls monotonically with age: 46% at age 0 → 19% at age 5 → 14% at age 18.

Verdict: Heise-style relational dynamics are present in Belgian B2B (especially C3's declining hazard). This is a precondition for a stickiness story, not a stickiness verdict. Not used.

### Test A — new-pair carbon-intensity tilt
n = 544,592 new pairs in the Phase 3 universe.

- A2 rank, p_p2 (2017+): β = −4.7×10⁻⁴, p = 0.065. Right sign for stickiness, marginally significant, **economically tiny** (∼0.05 percentile points lower NACE-4d intensity rank).
- A1 R3 (with buyer-NACE2d × year FE): β collapses to −0.39 (p = 0.93). The marginal tilt is driven by buyer-side timing, not seller-side selection within input sectors.
- Stock-vs-flow: flow-mean is consistently ~26-52% of stock-mean during 2017-2022 (vs ~57-100% pre-2013). Heise's "stickiness on stock, substitution on flow" signature is visible but small.

Verdict: marginal evidence for a stickiness-style new-pair tilt, but not enough to anchor a claim. Not used.

### Test B — survival hazard by intensity × pair age (winsorized)
n = 7,422,187 pair-year observations after the Phase 3 filter.

- intensity_only spec: treat_1_3 = +6.89 (p=0.35), treat_4_7 = −2.52 (p=0.64), treat_8plus = +2.33 (p=0.39).
- Sign pattern (young pair coefficient positive) has the right direction for stickiness; pooled magnitudes are statistically null.
- Winsorization at p99 of `firm_cost_share_regressor` brought down the original |coefs| > 4000 sector outliers but did not change the pooled story.

Verdict: pooled null. Not used.

### Phase-3-universe pair persistence (incidental)
Of ~680K distinct pairs in the Phase 3 universe (regulated-intensive buyer + core-input pair), only 5,327 had a formation year observable in 2003-2022 — i.e., **~99% of Phase-3-universe pairs are left-censored at 2002.** The regulated-intensive supply network is dominated by relationships that predate B2B's start.

This is a striking persistence fact in its own right but isn't load-bearing for the paper.

## What's still to do

The Plan B test battery as designed leaves a gap: none of the existing tests directly asks "**among the 9% of buyers facing the substitution decision, do they reweight away from the most-heavily-carbon-exposed ETS supplier?**"

Test G's filter (`n_ets_sellers ≥ 2`) excludes the 6,500 buyer-year cells where exactly one of the buyer's NACE-4d suppliers is ETS-treated — most of count [3]. And Test G's outcome is each seller's share of the cell, not "the share of the *most-exposed* ETS supplier" specifically. A targeted DiD on the 9% subset is the natural next test (see "Next test" below).

## Next test (planned)

**Buyer-level DiD on the most-exposed ETS supplier.** For each `(buyer × NACE 4d × year)` cell in count [3] of the followup (≥2 suppliers, ≥1 ETS):

- Identify the seller `j*(b,n)` with the highest `firm_cost_share` among ETS suppliers in the cell. (Time-invariant if using the regressor flavor.)
- Outcome: `share_{j*,b,n,t} = corr_sales_{j*,b,t} / Σ_{j' in cell} corr_sales_{j',b,t}`.
- Spec: `share ~ β · firm_cost_share_{j*} × Post_t + α_{j*,b,n} + δ_{n,t} + ε`.
- Predicted sign under substitution: β < 0 (the most-exposed ETS supplier loses share to its NACE-4d alternatives post-shock).
- Predicted sign under shock-too-small: β ≈ 0.

Sample size: ~147K cell-years across ~27K buyers — far larger than Test G's 1-29 cells. Power should be adequate for detecting modest substitution.

If β ≈ 0 in this test, the shock-too-small story is fully nailed down: buyers facing a real substitution decision aren't acting on it. If β < 0, the shock-too-small claim has to be qualified.
