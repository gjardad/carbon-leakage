# Greenflation — Literature Review

*What the empirical and theoretical literature says about whether carbon pricing is inflationary, and where Belgian firm × ETS data can extend these findings.*

---

## One-paragraph synthesis

The empirical literature is split: cross-country panel studies of **carbon taxes** (Konradt & Weder di Mauro 2023; Metcalf & Stock 2020) find **null or small** aggregate inflation effects, while studies of the **EU ETS** using high-frequency identification (Känzig 2022; Känzig & Konradt 2023) find **sizable, persistent** pass-through to headline and energy inflation. Bettarelli et al. (2025) argue the ETS/tax gap reflects coverage (taxes are often revenue-recycled and narrow; the ETS covers the power sector which has near-complete pass-through). Hensel, Mangiante & Moretti (2024) bring firm-level survey evidence from France: carbon-policy shocks raise firms' inflation expectations and their own expected/realized price growth, with heterogeneity by energy intensity and profit margins. On the theory side, Del Negro, di Giovanni & Dogra (2025) show that a multi-sector NK model with input–output linkages and heterogeneous stickiness reverses the "Aoki (2001) two-sector" conclusion — a \$100/tCO₂ tax produces a 1 pp+ inflation overshoot for ~6 years under accommodating policy, because energy is central in the I/O network and directly/indirectly affected sectors have unusually flexible prices. **None of these papers observe firm × sector × year pass-through for a full national economy with ETS-firm identifiers, PPI, input–output linkages, and network-level spillovers jointly** — which is the gap this project addresses.

---

## 1. Bettarelli, Furceri, Pisano & Pizzuto (2025) — *European Economic Review*
### "Greenflation: Empirical evidence using macro, regional and sectoral data"

**Data.** 177 countries (1989–2022), 78 sub-national regions in US/China/Canada, 17 sectors across 38 countries (1990–2022). Main policy variables: Dolphin (2022) emissions-weighted carbon-tax and ETS rates; OECD EPS (Environmental Policy Stringency) index decomposed into market-based, non-market-based, and technology-support components.

**Strategy.** Jordà local projections on cumulative log-CPI changes with country and year FE, lagged dependent variable, and an extended controls battery (GDP, unemployment, policy rate, oil, food, FX, deficit). Smooth-transition nonlinear LP à la Auerbach–Gorodnichenko for inflation-regime heterogeneity. Bartik IV using global drought counts × agricultural land/capita as a robustness check. Regional (94 regions × 1990–2021) and sectoral (38 × 17) specifications add country × year FE and exploit within-country variation.

**Headline results.**
| Shock | Effect on price level |
|---|---|
| 1 sd carbon tax (~\$5/tCO₂) | **+0.7 %** at 1 yr, **+1.6 %** peak at 4 yr, persistent |
| 1 sd ETS price | **~0 %** across all horizons (insignificant) |
| Market-based EPS | **+4 %** at 5-yr peak |
| Non-market / tech-support EPS | Null |
| Carbon tax × high initial inflation | **+4 %** peak (≈ 2× baseline) |
| Carbon tax × low inflation | Null |
| Carbon tax × high-emissions region | ~0.5 pp more than low-emissions region |
| Carbon tax × low-innovation region | ~0.3 pp more than high-innovation |
| Sectoral (1 sd ≈ \$9/tCO₂) | ~4 % peak in sector price level |

**Take-away.** Carbon taxes are inflationary on average, and the effect amplifies when initial inflation is high, emissions are high, and innovation capacity is low. ETS and non-price instruments do not show up as inflationary in their identification.

**Weakness for our purposes.** The sectoral panel is 38-country × 17 broad sectors and uses country × year FE that absorb most of the relevant ETS variation. Their null ETS result is identified off the cross-sectional/time-series variation that survives those fixed effects — not off firm-level exposure differences within a country.

---

## 2. Konradt & Weder di Mauro (2023) — *JEEA*
### "Carbon Taxation and Greenflation: Evidence from Europe and Canada"

**Data.** 18 carbon taxes: 15 European countries (1985–2018) and 3 Canadian provinces (BC, Quebec, Alberta; 2000–2018). Annual macro data; Canadian data also at quarterly. World Bank Carbon Pricing Dashboard tax rates and coverage; OECD CPI (headline, core, energy-and-food); BIS policy rates; Eurostat for labor and trade.

**Strategy.** Panel local projections with country FE, year FE in some specs, GDP-growth and policy-rate controls. Effective tax = rate × 2019 emissions coverage. They benchmark a **counterfactual \$40/tCO₂ tax covering 30 %** of emissions (roughly ~\$2.4 at-pump). They compare a standard TWFE estimator to Dube–Girardi–Jordà–Taylor (2022) to handle staggered adoption, and run panel-VARs and synthetic-control event studies as robustness.

**Headline results.** Headline CPI cumulative response over 5 years ≈ **0 pp for Europe**, **slightly negative for Canada**. Core CPI response ≈ zero everywhere. Energy-and-food component responds **+1 pp on impact in Europe**, fading over 5 years, and **+1.5 pp at quarterly horizons in Canada**, persistent. Response of producer prices and oil prices is **zero** following tax changes (contrast with ETS — see paper 4).

**Cross-section heterogeneity.** Non-revenue-recycling carbon taxes (France, Ireland, UK, Portugal) lead to larger medium-term headline and core responses (+1.16 pp at 3–5 yr) than revenue-recycling Scandinavian countries (near zero). Countries *without* independent monetary policy (Euro-area + Denmark peg) show larger inflation responses than countries with independent central banks — consistent with monetary policy accommodating in the EA.

**Mechanism interpretation.** Carbon taxes change **relative** prices (energy-food ↑), but the broader basket is insulated because (i) ETS already prices power, (ii) taxes are often narrow (transport, heating), (iii) revenue recycling cushions demand, and (iv) monetary policy responds. They explicitly argue this is consistent with Aoki (2001) — i.e. pass-through is confined to the "flexible" component.

**Note for our project.** The authors' benchmark \$40 tax × 30 % coverage mechanically ≈ \$12/tCO₂ effective — comparable in magnitude to our Belgian effective-price-per-tonne series rising from ~\$2 (Phase III pre-MSR) to **\$39 (2022)**. In their framework, Belgium (Euro-area, no revenue recycling for ETS, power-sector coverage) should sit in the *high*-response quadrant of their cross-section. Our null-to-small PPI result is therefore a data point they'd predict to be *larger* and isn't; the discrepancy is worth investigating.

---

## 3. Hensel, Mangiante & Moretti (2024) — *Journal of Monetary Economics*
### "Carbon pricing and inflation expectations: Evidence from France"

**Data.** French INSEE *Enquête Trimestrielle de Conjoncture dans l'Industrie* (manufacturing firm survey), 1999–2019: ~2,500 firms/quarter, ~9,700 unique firms, ~280k firm-quarter observations. Variables: 3-month-ahead aggregate inflation expectations (qualitative), own-price expectations (qualitative + quantitative), realized own-price growth (qualitative + quantitative). Merged with French balance-sheet (FICUS/FARE) for size/profit-margin/energy intensity and EACEI energy-consumption survey. Identification variable: **Känzig (2023) carbon-policy shock series** — high-frequency surprises from EUA futures in narrow windows around EU regulatory events, extracted as shocks from a proxy-VAR.

**Strategy.** Panel local projections `Σ_k I{E_t+k y_t+k+1} = α_i + β_h CPShock_t + controls + ε` with firm FE, Driscoll–Kraay SEs. Impulse normalized to +1 % HICP-energy on impact. Heterogeneity interacted with firm-level energy intensity (bottom vs top quartile), size, profit-margin quartile, and food-sector (NACE 10) dummy.

**Headline results.**
- **Aggregate inflation expectations** rise sharply and persist 10+ quarters after a CPShock that raises HICP-energy by 1 % — size and shape similar to an oil-price shock.
- **Own expected and realized price growth** both rise ~0.05 pp on impact, cumulating to ~0.15–0.20 pp after 8 quarters. The two move together.
- **Forecast errors (realized − expected)**: positive in first 4 quarters (firms *under*-react), then turn negative (firms over-extrapolate). Consistent with rational-inattention + over-extrapolation à la Angeletos–Huo–Sastry (2020).
- **Heterogeneity**: Low-energy-intensity firms make *larger* forecast errors (rational inattention — they track energy less closely). Low-profit-margin firms have *weaker* price pass-through and *smaller* forecast errors (more competitive → more attention to macro but less pricing power). Food-sector firms have larger expectations and realized pass-through.

**Take-away.** Carbon-policy shocks *do* feed into firms' pricing decisions, and information frictions amplify persistence. This argues against monetary policy "looking through" carbon shocks when inflation expectations are a target.

**Note for our project.** This paper is the closest to ours in spirit — firm-level, Känzig-shock-identified — but uses **expectations and qualitative own-price changes**, not realized NACE4d PPI changes driven by measured ETS exposure. Their Belgian analogue (firm-level ETS shortage × EUA) would let us check both (i) whether pass-through in realized prices matches their expectations-based pass-through, and (ii) whether the heterogeneity by energy intensity / margins they find in *expectations* also shows up in *realized* B2B and PPI prices.

---

## 4. Känzig & Konradt (2023) — *NBER WP 31260 / IMF Economic Review*
### "Climate Policy and the Economy: Evidence from Europe's Carbon Pricing Initiatives"

**Data.** 28 EU ETS countries including UK, 1999–2019. 14 of them also have national carbon taxes. EU ETS prices from Datastream + EUTL verified emissions. Carbon-tax data from World Bank Pricing Dashboard. Macro + financial controls: HICP-energy, headline HICP, GHG emissions, real GDP, industrial production, unemployment, policy rate, Euro Stoxx, Brent, EU GDP.

**Strategy.** Two identification approaches run in parallel on the same panel:
1. **High-frequency identification**: Känzig (2022) carbon-policy shocks (aggregated to annual), used in LPs with country FE and national controls.
2. **Control-based identification** (Metcalf–Stock style): coverage-weighted real ETS price / carbon-tax rate with lagged macro controls + global/EU controls or time FE.

They also instrument ETS prices with the HFI shocks in a robustness check (F-stat ~105).

**Headline results.**
| Shock (normalized to +1 % HICP-energy) | Output | Headline CPI | Emissions |
|---|---|---|---|
| **EU ETS price** (HFI + control-based) | −0.5 % peak | +0.3 pp peak, persistent | −0.5 % |
| **Carbon taxes** (control-based, W/N Europe) | Small, imprecise | ≈ 0 pp | −0.4 % at national level but near-zero at EU level (leakage) |

Both policies reduce emissions; ETS causes larger macro pain per unit of energy-price increase. Variance decomposition: ETS price explains ~33 % of 4-yr variation in HICP-energy and ~17 % of GHG emissions; carbon taxes explain ~6 % and ~1 %.

**Four channels they propose for the ETS–tax gap.**
1. **Revenue recycling.** ETS revenues are earmarked for climate tech; tax revenues often cut income taxes. They demonstrate this directly by splitting W/N European tax countries into recyclers vs non-recyclers.
2. **Sectoral coverage and pass-through.** ETS covers power and oil refineries; taxes skip the power sector. Power-sector pass-through is near-complete (Fabra & Reguant 2014), manufacturing much less (Ganapati, Shapiro & Walker 2020). ETS shocks raise PPI and Brent significantly; tax shocks do not.
3. **Spillovers/leakage.** National tax → national emissions ↓ but EU emissions only partly ↓ (leakage to other EU countries). ETS is union-wide, so no intra-EU leakage.
4. **Monetary policy.** ECB tightens in response to ETS shocks; no measurable response to national tax shocks.

**Regional heterogeneity.** Countries with more free allowances → muted pass-through; countries with concentrated electricity retail markets → larger pass-through; countries with browner energy mix → larger price response; countries in second per-capita-GDP quartile (below-median income but above poorest) are hit hardest — because they receive few free allowances AND have concentrated power markets.

**Note for our project.** Belgium is moderate on every dimension (moderate free allowances, moderate power-market concentration, browner-than-EU-average mix). Their cross-country results predict *some* pass-through for Belgium; our null-to-small Belgian PPI pass-through (S1–S6) is informative about *within-Belgium* heterogeneity that country-level LPs cannot see.

---

## 5. Del Negro, di Giovanni & Dogra (2025) — *NBER WP / FRBNY SR*
### "Is the Green Transition Inflationary?"

**Data + calibration.** 69-sector U.S. model calibrated to 2012 BEA Input-Output tables; sectoral price-change frequencies from Cotton & Garga (2022) built on Nakamura–Steinsson (2008); sectoral CO₂ emissions from EIA+EPA matched to BEA via Shapiro (2021) method. Energy sectors (oil, gas, coal extraction; petroleum/coal products; utilities) separated out from BEA summary codes.

**Model.** Multi-sector NK with Calvo pricing, I/O linkages, labor–intermediates–energy CES nesting, and a carbon tax levied upstream on fossil-fuel extraction. Monetary policy rule nests strict output-gap targeting, strict inflation targeting, and intermediate mixes.

**Analytical result (linearized, flex wage).** CPI inflation along a constant-tax-growth path is

$$\pi^c = \left( \boldsymbol{\gamma}' - \frac{\boldsymbol{\lambda}' K^{-1}}{\boldsymbol{\lambda}' K^{-1} \mathbf{1}} \right) (I - \Omega)^{-1} \boldsymbol{\epsilon} \cdot g,$$

where λ' = γ'(I − Ω)⁻¹ are Domar weights and K is diag(κᵢ) with κᵢ ↑ in price flexibility. Two necessary conditions for taxes to be inflationary: (i) energy sectors are **central in the I/O network** (so (I − Ω)⁻¹ε ≠ ε alone), and (ii) directly/indirectly taxed sectors have **more flexible prices than average** (so the bracket is positive). If stickiness were homogeneous the carbon tax would have *zero or negative* effect on CPI under accommodating policy.

**Empirical validation.** Their U.S. data satisfy both: (a) energy is central to the BEA I/O network, (b) sector-level price-change frequency is strongly positively correlated with total (Leontief-adjusted) CO₂ emissions over gross output. Oil, gas, coal, petroleum & coal products are all at the high-flexibility, high-emissions corner of the scatter.

**Quantitative result.** A gradual \$100/tCO₂ (2012 \$) carbon tax over 100 months, announced 20 months in advance:
- Under output-gap targeting: 12-m headline CPI above +1 pp for 6+ years; 12-m core CPI above +0.5 pp for 10 years.
- Keeping headline inflation below +0.6 pp avg requires a −1 % avg output gap for the 6-yr increase period.
- Keeping core below +0.5 pp avg requires −0.6 % avg output gap.
- Cutting I/O network (sectors become "islands" except for energy inputs) reduces the core-CPI response by ~2/3 — confirming the network-propagation channel is quantitatively dominant.

**Validation against Känzig (2021).** Their calibrated (non-estimated) model matches the empirical response shapes of HICP-energy, core goods and services to an oil-price shock over 2 years.

**Take-away.** The "Aoki 2001" intuition — carbon taxes are just a relative-price shock you can look through — is an artifact of the two-sector assumption. Production networks plus heterogeneous stickiness can generate a sizable policy trade-off. This paper's analytical formula is what one should have in mind when deciding what to measure empirically.

---

## Summary table: empirical strategies

| Paper | Unit | Horizon | Identification | Shock | Outcome(s) |
|---|---|---|---|---|---|
| Bettarelli '25 | country/region/sector × yr | 1989–2022 | LP + controls; smooth-transition; Bartik IV | Dolphin carbon-tax & ETS, coverage-weighted | log-CPI |
| Konradt–WdM '23 | country × yr/qtr | 1985–2018 | TWFE + DGJT LPs | coverage × real rate (control-based) | headline, core, energy-food CPI, PPI, oil |
| Hensel et al. '24 | firm × qtr | 1999–2019 | LP w/ Driscoll–Kraay | Känzig HFI CP shock | firm-level inflation & own-price expectations + forecast errors |
| Känzig–Konradt '23 | country × yr | 1999–2019 | HFI CP shocks + control-based, in parallel | Känzig CP shock; ETS price; carbon tax | HICP-energy, headline, PPI, Brent, real GDP, IP, U, emissions |
| DDD '25 | 69 U.S. sectors | calibration to 2012 BEA | Non-linear IO-NK model | Announced \$100/tCO₂ path | Headline, core, sectoral, wages, output gap |

---

## How this project's data can extend this literature

The project has a feature combination that **none of the five papers has**: firm-level identification of ETS participation within a single country, matched to NACE4d PPI, annual accounts, B2B transactions, PRODCOM (with co-author), and customs data, covering all ETS phases 2005–2022.

### 1. Firm-level test of Hensel-style pass-through on *realized* prices
Hensel et al. document that CPShocks raise French firms' inflation and own-price *expectations* and own *realized* price growth in survey data, with heterogeneity in energy intensity and margins. We can run the same regressions on **Belgian realized unit prices (PRODCOM) and sector PPI** using (i) the firm-specific ETS shortage × EUA exposure as the continuous right-hand-side variable, and (ii) the Känzig CPShock as an IV. If the firm-level effect survives with energy-intensity / margin heterogeneity, their forecast-error pattern (positive → negative, rational-inattention) should show up in realized prices with a lag structure — which is testable against their quarterly France findings.

### 2. Decomposing the ETS–tax gap that Känzig–Konradt (2023) identified
Their four channels (revenue recycling, pass-through/coverage, leakage, monetary policy) are identified **across** countries. Belgium alone isolates (i) a single monetary regime (Eurosystem), (ii) a single fiscal regime (no revenue recycling for ETS), so any within-Belgium variation in pass-through across NACE4d sectors is driven by channels 2 and 3 only — pass-through depth (power vs industry vs downstream) and intra-EU leakage. Our B2B network lets us decompose "direct" vs "network-propagated" exposure at the sector and firm level, giving direct empirical content to their assertion that the ETS covers the power sector whose pass-through is near-complete.

### 3. Empirical test of the DDD (2025) analytical formula
Their conclusion hinges on two empirical facts for the U.S.: energy sectors are central in the I/O network, and emission-intensive sectors have above-average price flexibility. Both are measurable for Belgium: the BEA I/O table can be replaced with Eurostat/Belgian supply-use tables or our own B2B-derived input-share matrices, and sector-level PPI change frequency (via Cotton–Garga methodology or from our Statbel PPI micro-data if available) can map onto NACE4d. If the U.S. pattern replicates in Belgium, DDD's quantitative prediction — that a Belgian-scale tax should generate a multi-year inflation overshoot unless policy leans hard — is testable against our actual PPI data post-Phase-IV (2021+). If the pattern does *not* replicate, that explains the Belgian null.

### 4. The regional-heterogeneity prediction from Känzig–Konradt
They find larger ETS pass-through in countries with concentrated electricity retail and fewer free allowances. Belgium has sector-level variation in both (power sector was fully allocated at auction by Phase III; industrial sectors retained benchmark-based free allocation). Our firm-level EUTL match tracks free allocation per firm-year, so we can within-Belgium reproduce their cross-country allocation result — sectors/firms with lower free-allocation ratios should have higher pass-through in PPI and B2B prices.

### 5. Greenflation vs carbon leakage — the two-sided question
Bettarelli et al. treat carbon-leakage as a leakage of *emissions*. For a small open economy deeply integrated in EU supply chains, the flip side is **leakage of price increases** — to the extent Belgian firms cannot pass through ETS costs (because competitors elsewhere don't face them), the effect is on margins/output, not prices. Our customs data + B2B + PRODCOM lets us measure this directly: does pass-through rise in sectors with low import exposure? This is a cleaner test than the cross-country leakage result Känzig–Konradt pull from aggregate EU emissions.

### 6. Phase IV as a natural experiment
All five papers work with data ending 2017–2022. Phase IV (2021+) is the first time the EUA price was high enough (>\$40/tCO₂) for the nominal magnitudes in Konradt–WdM and DDD counterfactuals to materialize. Our Belgian panel runs through 2022 and can provide the first high-tax test of the greenflation hypothesis within a single-country, identified-at-firm-level setup.

---

## Open questions worth flagging

1. **Why do Bettarelli et al. and Konradt–WdM get opposite signs on carbon-tax inflation?** Bettarelli's result is strongly shaped by the inclusion of emerging economies and high-inflation regimes; Konradt–WdM stick to OECD Europe + Canada. Does the result survive in OECD-only versions of the Bettarelli panel? This matters because our Belgian tests are OECD-European and should inherit the Konradt–WdM benchmark.
2. **What does "pass-through" mean at each layer of the chain?** Fabra–Reguant (Spanish electricity wholesale, 0.86), BKR (European electricity futures, 0.2–0.4), Känzig (European HICP, 0.2–0.3), Konradt–WdM (national CPI, ~0), MMS 2024 Belgian firm PRODCOM (+0.14 SE 0.15), and our own S12 monthly panel-LP (+4.08 at 12-m) are **different objects** — wholesale vs futures vs CPI vs firm unit prices vs NACE4d PPI with a structural shock. A clean side-by-side mapping between them is missing from the literature and is something this project is positioned to deliver.
3. **Network-propagated vs direct exposure.** DDD show in counterfactuals that IO propagation accounts for ~2/3 of core inflation response; no empirical paper separately estimates direct vs IO-propagated pass-through using firm-level data. Our B2B-derived Leontief allows this decomposition, with the caveat that the downsampled version on Local 1 produces directional-only estimates until rebuilt on RMD.
