# Asset Allocation

> Last updated: [DATE] | Rebalance cadence: **Annual** (target: January) + band-breach mid-year
> Monthly DCA: [AMOUNT/PLAN — update to match your savings plan]

## Allocation Template Options

Choose a starting allocation that matches your risk tolerance and horizon, then
adjust the bands to suit. Update the **Target Allocation** table below to match.

| Profile | Core ETF | Regional Equities | Single Names | Alternatives | Cash/Bonds |
|---------|----------|-------------------|--------------|--------------|------------|
| Conservative (short horizon, low risk) | 40% | 10% | 10% | 10% | 30% |
| Balanced (medium horizon) | 55% | 15% | 10% | 5% | 15% |
| Growth (long horizon, high tolerance) | 55% | 15% | 20% | 5% | 5% |
| Aggressive (10+ yr, max equity) | 65% | 20% | 15% | 0% | 0% |

> The current target below reflects the **Growth** profile with a Quality Compounders sleeve.
> Edit the **Target Allocation** table to match your chosen profile.

## Strategy Revision — [DATE]

Allocation rebuilt to reflect:
1. **Investment horizon**: [X years] — adjust equity/bond tilt accordingly
2. **Real-estate exposure**: [describe any property holdings that count as RE exposure]
3. **Income stability**: [describe emergency fund / income buffer that affects bond allocation]
4. **Drawdown tolerance**: [confirmed / TBD] — must hold through 40%+ drop on intact thesis
5. **Concentration goal**: [Quality Compounders sleeve / single names / etc.]

## Target Allocation

| Asset Class | Target % | Tolerance Band | Benchmark / Proxy | Vehicles |
|-------------|----------|----------------|-------------------|----------|
| Global Equities (core ETF) | **55%** | ±5% (50–60%) | MSCI World / S&P 500 | e.g. CSPX (S&P 500 Acc) |
| European Equities | **15%** | ±5% (10–20%) | MSCI Europe | e.g. IMEA |
| **Quality Compounders** (single names) | **15%** | ±3% (12–18%) | bespoke (2–3 names, 4–6% each) | e.g. MSFT |
| **Asymmetric / Home-runs** | **5%** | ±3% (2–8%) | bespoke (1 name max, 2–3% max each) | [your picks] |
| Emerging / Thematic | **5%** | ±3% (2–8%) | varies | [your picks] |
| Cash / Bonds | **5%** | ±3% (2–8%) | short-duration | [your picks] |

### Hard rules (unchanged from philosophy)

- No leverage / margin
- No short selling
- No macro-cycle timing
- **No single position > 10% of total portfolio** (Quality Compounders @ 4–6% each = fine; flag breach within 30 days for cure)
- Min trade size €500
- Min hold horizon 2 years
- Drawdown tolerance: must hold positions through 40%+ drop unless thesis breaks

---

## Broker Allocation

| Broker | Primary Use | Notes |
|--------|-------------|-------|
| [Your broker 1] | Core ETF holdings, fractional savings plans | e.g. auto-invest plans; fractional shares enable small lots |
| [Your broker 2] | Individual stocks | lower cost for whole-share single equities |
| [Your broker 3] | Index fund DCA | e.g. bank-held index fund |

Any broker name used in `portfolio/transactions.csv` is valid — the script tracks
positions per (ticker, broker) pair.

---

## Annual Rebalancing Rules

1. **Trigger**: Review each January, or if any asset class drifts beyond its tolerance band mid-year, or single name breaches 10% cap.
2. **Direction**: Trim winners above band → buy laggards below band. Do **not** add fresh cash to overweight positions.
3. **Tax awareness**: Check your jurisdiction's rules before selling — see `strategy/stock-evaluation-framework.md` §4. If capital gains are taxed, lot selection and hold period matter.
4. **Minimum trade size**: Don't rebalance lots smaller than €500 — transaction costs won't justify it.
5. **Document**: After each rebalance, log the date and actions taken in the section below.

---

## Rebalancing Log

| Date | Action | Broker | Notes |
|------|--------|--------|-------|
| YYYY-MM-DD | Example: BUY 10 CSPX @ €420 — seeds Global Equities sleeve | [Broker] | — |

---

## Current vs Target (update after each portfolio export)

| Asset Class | Target % | Current % | Drift | Action |
|-------------|----------|-----------|-------|--------|
| Global Equities | 55% | — | — | — |
| European Equities | 15% | — | — | — |
| Quality Compounders | 15% | — | — | — |
| Asymmetric / Home-runs | 5% | — | — | — |
| Emerging / Thematic | 5% | — | — | — |
| Cash / Bonds | 5% | — | — | — |

*Run `scripts/update_charts.py` to auto-populate the Current % column.*

---

## Long-Term Target Math

| Variable | Your Value |
|---|---|
| Starting book | €___ |
| Monthly contribution | €___ |
| Annual contribution (total) | €___ |
| Horizon | ___ years |
| Target | €___ |
| Required blended return | ~___% |

*Run a future-value calculator with your own numbers: [FV = PV×(1+r)^n + PMT×((1+r)^n−1)/r]*
