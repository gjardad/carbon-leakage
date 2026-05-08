# Käenzig CPShock: how it is built and what it actually represents

*Reference: [Käenzig (2023/2025) JMP](articles/kaenzig_jmp.pdf), "The Unequal Economic Consequences of Carbon Pricing." Replication archive ships two columns in `${RAW_DATA}/carbonPolicyShocks.xlsx`: `Surprise` (high-frequency event-day series) and `Shock` (SVAR-identified structural shock). We use `Shock` in our local-projections; this note documents what that object is.*

## Verdict in one paragraph

The `Shock` series is **not** the supply-side EUA-price news component of monthly EUA price moves. That object is the `Surprise` series. The `Shock` is the SVAR's reconstruction of the latent structural carbon-policy shock that is most consistent with both (i) the event-day surprises and (ii) the joint dynamics of 8 EU macro variables over 1999–2019. It is computed as a fixed linear combination of monthly reduced-form macro innovations, applied every month including pre-2005. Pre-2005 values are not carbon policy (no EU ETS yet) — they are mechanical SVAR residual projections. Post-2005 the Shock correlates with Surprise at only 0.24, much less than 1, because Surprise is censored to zero outside event months while Shock has full-sample variance.

## Step 1: Build the daily Surprise series (raw event-day signal)

For each of the **114 EU-ETS regulatory event days** $d$ between 2005 and 2019 (cap revisions, NAP approvals, MSR decisions, auction-calendar announcements, international-credit rule changes; sourced from the EU Climate Action news archive, the Official Journal of the EU, and Mansanet-Bataller-Pardo 2009; 12 events that coincided with oil shocks / sovereign-debt headlines / Brexit are dropped), define the raw daily surprise as the change in EUA front-month futures price scaled by lagged electricity price:

```
CPSurprise_d = (F^carbon_d − F^carbon_{d−1}) / P^elec_{d−1}
```

The denominator $P^{\text{elec}}_{d-1}$ is included to handle the near-zero EUA prices of late Phase I (where percentage changes blow up). On non-event days, $\text{CPSurprise}_d = 0$.

**Bauer-Swanson (2023) orthogonalization.** Regress daily $\text{CPSurprise}_d$ on observable pre-event macro / financial / oil / climate variables to strip out the part explained by contemporaneous non-policy news. The residual is the *refined* surprise; this is the baseline. $R^2 \le 18\%$, correlation with raw $= 0.90$.

**Monthly aggregation.** Sum daily refined surprises within each month:

```
Surprise_m = Σ_{d ∈ month m}  refined CPSurprise_d
```

Months with no events have $\text{Surprise}_m = 0$. The series starts in 2005 (the EU ETS launch); pre-2005 months are zero by construction (no events).

## Step 2: External-instrument SVAR

Käenzig estimates a monthly **8-variable VAR** on 1999m1–2019m12 with 6 lags:

$$
y_t = c + A(L) y_{t-1} + u_t, \qquad \mathbb{E}[u_t u_t'] = \Sigma
$$

with $y_t = $ (HICP energy, GHG emissions, HICP headline, industrial production, unemployment, 2y rate, stock index, deflated Brent). Plus a dummy for the 2011m7–2012m3 sovereign-debt-crisis window.

The vector $u_t \in \mathbb{R}^8$ is the *reduced-form innovation* — the part of each variable that the VAR's own past lags can't explain.

**Structural form.** Decompose $u_t = B \, e_t$ where $e_t$ are mutually-uncorrelated structural shocks ($\mathbb{E}[e_t e_t'] = I$), so $\Sigma = B B'$. We want to identify *one* column of $B$, namely $b^1$ — the impact response of all 8 variables to a unit carbon-policy shock $e_t^{\text{cp}}$.

**Identifying assumption** (external instrument, Stock-Watson 2018 / Mertens-Ravn 2013): the monthly Surprise series $z_t \equiv \text{Surprise}_m$ is correlated with the carbon-policy structural shock and uncorrelated with all other structural shocks:

$$
\mathbb{E}[z_t \, e_t^{\text{cp}}] \neq 0, \qquad \mathbb{E}[z_t \, e_t^{j}] = 0 \quad \forall j \neq \text{cp}.
$$

Then $\mathbb{E}[z_t u_t'] = \mathbb{E}[z_t e_t^{\text{cp}}] \cdot (b^1)'$, so a regression of each component of $u_t$ on $z_t$ identifies $b^1$ up to scale. Sign-and-scale normalize so that **the HICP-energy element of $b^1$ equals $+0.01$** (i.e., a unit shock raises HICP energy by 1% on impact).

**Recovery of the structural-shock series.** Project the reduced-form innovations onto the identified direction:

$$
\hat{e}_t^{\text{cp}} \;=\; \frac{(b^1)' \, \Sigma^{-1} \, u_t}{(b^1)' \, \Sigma^{-1} \, b^1}.
$$

Equivalently: $\hat{e}_t^{\text{cp}} = w' u_t$ for a fixed weight vector $w \in \mathbb{R}^8$ that depends only on $b^1$ and $\Sigma$. This formula is applied for **every month $t \in [1999\text{m}1, 2019\text{m}12]$** — including all pre-2005 months, where $z_t = 0$ but $u_t$ is well-defined.

The recovered series $\{\hat{e}_t^{\text{cp}}\}_{t=1999\text{m}1}^{2019\text{m}12}$ is the `Shock` column in `carbonPolicyShocks.xlsx`.

## Intuitive explanation

**Step 1 (Surprise) is the part that is intuitive.** Watch EUA futures on 114 specific days when EU regulators did something visible. Take the price jump on those days, strip out the part that's explained by other concurrent news, and aggregate to monthly totals. Months with events get a number; months without get zero. This *is* the supply-side news component — it's what a financial-news high-frequency identification scheme literally records.

**Step 2 (Shock) is more subtle and is where intuition breaks down.** The SVAR procedure asks: "Each month, the 8 macro variables move in ways the VAR's lags didn't predict (the residuals $u_t$). Among those residuals, what linear combination $w' u_t$ behaves the way carbon-policy news behaves — i.e., correlates with our event-day Surprise series?" Solve for $w$ once on the full sample, then apply it every month.

The resulting Shock series is **not** "did a regulator do something this month?" It is **"did the macro economy this month wiggle in the direction that the SVAR has learned to associate with carbon-policy news?"** Two months can have identical Shock values for very different reasons: one might have an actual policy event, the other might just have macro residuals that happen to point the same direction.

This is why:

- **The Shock is nonzero in every month, 1999m1 through 2019m12** — including the 66 pre-EU-ETS months where no policy could possibly exist. The SVAR doesn't know there's no policy; it mechanically applies $w$ to whatever $u_t$ is each month.
- **The post-2005 correlation between Shock and Surprise is only 0.24.** They are related but not equal. Most of the Shock's monthly variance comes from generic macro residuals that happen to project onto the carbon-policy direction.
- **The Shock is sign-symmetric.** It flips between positive and negative across months in roughly balanced numbers — as any structural shock should under SVAR conventions.

## Empirical features in the replication data

From `carbonPolicyShocks.xlsx` (sheet "Monthly"):

| Era | Surprise | Shock |
|---|---|---|
| 1999–2004 (no EU ETS) | mean = 0, sd = 0, **0/66 nonzero** | sd = 0.62, range $[-1.79, +1.52]$, **66/66 nonzero** |
| 2005–2019 | sd = 0.19, **78/180 nonzero** (event months only) | sd = 0.69, **180/180 nonzero** |

Post-2005 correlation: $\text{cor}(\text{Shock}, \text{Surprise}) = 0.24$.

## What this means for our use of `Shock` in the local projections

We use `Shock` (not `Surprise`) as the regressor in §4 of the paper. The trade-off is well-defined:

- **Why we use Shock**: it has variance in every month (180 vs 78 effective shock months in 2005–2019), so the LP has more identifying observations and tighter standard errors. Käenzig's HICP IRF replicates cleanly using Shock (we verified: HICP-energy peak +1.5%, headline peak +0.35%, ratio 0.23 — matches his Figure 3).
- **Why this complicates the EUA-price interpretation**: the recovered Shock has been smoothed and shaped by SVAR macro dynamics, so its impact response on EUA prices is small (R_0 ≈ 0–2.5% per unit Shock) compared to what a pure-Surprise IRF would give (R_0 ≈ 13% per unit Surprise on 2005–2019, statistically significant at 90%). The Shock-based first-stage R̄ over h ∈ [12, 24] is ~11% on the 2013–2019 sample.
- **Why we don't use Surprise directly**: only 78 nonzero months 2005–2019 makes the LP-IV first stage too weak (F < 2 in our experiments) to identify a sectoral pass-through elasticity. Käenzig himself documents the same weak-IV problem in his App. C.5 LP-IV variant and caps that variant at $h \le 12$ months for the same reason.

A reader of §4 should understand: when we report $\widehat{\gamma}_h$ on $(\omega_s \times \text{CPShock}_m)$, we are reporting **the response of sector PPI to a unit SVAR-recovered structural carbon-policy shock**, not "the response per unit EUA-price news event." The two are related — the SVAR-recovered shock is identified by the event-day surprises — but the Shock series as deployed has more variance (most of which is macro-residual reconstruction) and a smaller direct EUA-price impact than the Surprise-only object would have.

## Why $\gamma_h$ on $(\omega \times \text{Shock})$ is an attenuated estimate of the true Shephard gradient

The cross-sectional ω-gradient — the prediction that high-emission-intensity sectors' PPI rises more than low-intensity sectors' PPI when carbon prices move — is theoretically grounded in **Shephard's lemma applied to an actual EUA-price change**:

$$
\Delta \log \text{PPI}_s \;=\; \omega_s^{\text{old}} \cdot \Delta \log \text{EUA} \;=\; \omega_s \cdot \text{EUA} \cdot \Delta \log \text{EUA}
$$

This logic requires the regressor on the right-hand side to track *real EUA-price changes* (or, equivalently, real changes in the marginal opportunity cost of emissions). In months with an actual carbon-policy event, the Shock series captures such a change. In months without an event, the Shock is the SVAR's macro-residual projection — there is no actual EUA-price jump driven by policy, no change in any sector's marginal carbon cost, and **no theoretical reason for high-$\omega$ sectors to respond more than low-$\omega$ sectors**.

So when we estimate $\gamma_h$ on $(\omega_s \times \text{Shock}_m)$, we are averaging two distinct objects:

1. **In policy-event months** (post-2005, ~78/180 months in 2005–2019): the Shock is correlated with actual policy news, so a Shephard ω-gradient is predicted. This component contributes positive signal to $\gamma_h$.
2. **In non-event months and pre-2005 months** (~168/246 of the full series): the Shock is macro-residual variation projected onto the policy direction. There is no Shephard prediction here — the conditional expectation of $\Delta \log \text{PPI}_s$ given $(\omega_s \times \text{Shock}_m)$ should be zero. This component contributes variance to the regressor without contributing signal, **attenuating** $\widehat{\gamma}_h$ toward zero.

The variance-share of policy news in the Shock is small. Empirically, $\text{cor}(\text{Shock}, \text{Surprise}) = 0.24$ post-2005, so $\text{cor}^2 \approx 0.058$ — roughly **6% of the Shock's monthly variance is policy news; ~94% is macro-residual reconstruction**. Under classical-measurement-error attenuation logic, the ω-cross-sectional regression's coefficient is biased toward zero by approximately this signal-share factor.

This explains every empirical pattern we struggled with in the sectoral panel-LP:

- $\widehat{\gamma}_h > 0$ but smaller than full-Shephard would predict — **attenuation**.
- Wide confidence intervals at every horizon — the 94% noise component inflates standard errors without contributing identifying signal to the ω-gradient.
- Phase-III-only ($n = 84$ months) noisier than 2008–2019 ($n = 144$ months) — fewer absolute event months in the smaller sample, lower signal-to-total-variance ratio.
- The aggregate Shock-PPI IRF (no $\omega$) being more defensible — at the aggregate level, the Shock can be interpreted as a structural shock under the SVAR's identifying assumptions, and the SVAR's joint identification gives a coherent IRF interpretation that does not require any single month to track a real policy event in particular.

**Implication for §4 of the paper**: the sectoral $\widehat{\gamma}_h$ on $(\omega \times \text{Shock})$ should be read as **an attenuated lower bound on the true Shephard cross-sectional gradient**, with the attenuation factor approximately equal to the post-2005 share of Shock variance attributable to actual policy news. The aggregate Shock-PPI IRF — which does not depend on cross-sectional ω-content for identification — is the cleaner exhibit. The "right" cross-sectional regression would use Surprise (which has the correct cross-sectional content under Shephard) rather than Shock; that regression is just too underpowered at the monthly frequency, as Käenzig himself acknowledges in App. C.5.

## References

- Käenzig, D. R. (2023/2025). "The Unequal Economic Consequences of Carbon Pricing." JMP. Local copy: [articles/kaenzig_jmp.pdf](articles/kaenzig_jmp.pdf). Notes file: [articles/split_kaenzig_jmp/notes.md](articles/split_kaenzig_jmp/notes.md). Methodology Section 2–3, identification in eq. (1)–(4); Appendix C.5 for LP-IV variant.
- Stock, J. H., and M. W. Watson (2018). "Identification and Estimation of Dynamic Causal Effects in Macroeconomics Using External Instruments." *Economic Journal* 128(610): 917–948. (External-instrument SVAR identification.)
- Mertens, K., and M. Ravn (2013). "The Dynamic Effects of Personal and Corporate Income Tax Changes in the United States." *AER* 103(4): 1212–1247. (Same identification approach.)
- Bauer, M. D., and E. T. Swanson (2023). "A Reassessment of Monetary Policy Surprises and High-Frequency Identification." *NBER Macroeconomics Annual* 37. (Orthogonalization step.)
- Mansanet-Bataller, M., and Á. Pardo (2009). "Impacts of Regulatory Announcements on CO2 Prices." *Journal of Energy Markets* 2(2): 1–33. (Event date list for pre-2010.)
