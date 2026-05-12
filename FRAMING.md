# Paper framing

Working document for how we position the paper. Captures the agreed framing, the contribution claims we can defend, and the open framing questions we still need to resolve.

## Research question

> Does carbon pricing induce reallocation of economic activity away from targeted firms?

## Motivation

Three reasons reallocation is the policy-relevant outcome:

1. **International leakage** — emissions shifting abroad is the canonical concern (motivates CBAM, free allowance allocation, etc.).
2. **Domestic leakage** — carbon pricing in practice has incomplete sectoral coverage within a jurisdiction. Targeted firms competing with untargeted firms in the same product market can lose share even when the policy is "domestic only".
3. **Output and price effects on targeted firms** — even if coverage were complete, policymakers worry the policy depresses output and raises prices at the targeted firms themselves.

## Shock magnitude: precondition, not contribution

Before any reallocation result is interpretable, we have to show the shock is big enough to be worth studying. §3 of the paper ("How Big Is the Shock?") documents that EUA price movements over our sample generate cost shocks that are large for at least a non-trivial subset of buyer-supplier relationships — concentrated where allocation tightened or emissions intensity is high. This is **not** a contribution; every reallocation paper has to do this. Its role in the framing is to pre-empt the most immediate referee question — "is this shock something to even spend energy on?" — before the reader gets to the null.

## Contribution claims

We extend the existing ETS reallocation literature (Colmer et al. for France, Dechezleprêtre, Wagner, others). Three pieces are genuinely additive:

1. **Reallocation within treated firms exploiting heterogeneous exposure.**
   Colmer-style designs compare treated (ETS-covered) firms to untreated controls. They estimate the *average* treated effect and difference out heterogeneity in exposure inside the treated group. Two treated firms with very different shock intensity (driven by allocation tightness, sector emissions-intensity, free-allowance trajectory) are pooled together. The average-treated null is silent on whether more-exposed treated firms lose share to less-exposed treated firms. Our continuous-omega specification compares treated firms along a continuous exposure axis and directly tests this.

   *This is the strongest of the three contributions: it has the most variation, and the cleanest interpretation as "does the policy reallocate from those it bites harder to those it bites less".*

2. **First reallocation evidence in the high-price ETS period.**
   Prior nulls in the ETS literature largely cover Phase II / early Phase III, when EUA prices were low (often below €10/t) and the policy was plausibly not binding enough to drive reallocation. Our sample spans the MSR-driven price run-up and Phase IV, when prices were genuinely biting. A null in this period is a much harder test of the leakage story.

3. **Domestic vs international reallocation in the same dataset.**
   B2B + customs in one panel lets us look at both margins jointly. **Caveat:** this is only a standalone contribution if there are meaningful differences between the two margins. If both produce the same null, this becomes a robustness section, not a separate contribution.

## Results overview

- **No reallocation throughout** — domestic B2B and customs margins.
- **Mechanisms tested and ruled out (or weakened):** main piece of evidence against relational capital is the omega-rank analysis. Other mechanisms remain open hypotheses (see `TODO.md` / `WHY_NO_LEAKAGE.md`).
- **Framing of the null:** the paper should not read as "we looked for leakage and didn't find it." It should read as "we tested leakage under conditions where it should appear most clearly — high prices, continuous-exposure variation within the treated group — and the null persists." The mechanism section then explains why the null is structural rather than a power problem.

## Open framing questions

1. **Domestic vs international as separate contribution.** Conditional on what the numbers show — if both margins give the same null, demote (iii) to robustness.
2. **Mechanism section depth.** Which mechanisms do we test vs leave as hypothesis? The published version needs at least one mechanism affirmatively ruled out (omega rank → relational capital is the candidate). Others stay as discussion.
3. **Relation to Colmer's specific design.** Worth pinning down exactly what Colmer matches on (sector × size × covariates within sector?) before leaning on the "market definition" caveat — "firms that look similar on covariates" ≠ "firms that compete in the same product market", and NACE4d is a proxy for market, not a definition.
4. **What we don't claim.** We don't claim a global no-leakage result — sample is Belgium, one country, one ETS jurisdiction. The price-period and within-treated-heterogeneity contributions are the things that travel; the country-level estimate is local.

## What NOT to claim (corrections to avoid)

- ❌ "First paper to look at reallocation within treated firms" — too broad; the precise claim is "first to exploit continuous exposure heterogeneity within the treated group."
- ❌ "Colmer's null leaves the regulated-vs-unregulated competitor channel open" — false. If treated firms had lost share to untreated competitors in the same market, treated firms would have shrunk relative to control, and Colmer would have measured it. The valid loophole is on the within-treated exposure-heterogeneity margin, not on the binary regulated/unregulated margin.
