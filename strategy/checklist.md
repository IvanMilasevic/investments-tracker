# Trade Checklist

Use this before opening or closing any position. Takes 5 minutes. Saves regret.

---

## Pre-Buy Checklist

### Thesis
- [ ] I can explain the investment thesis in 2-3 sentences
- [ ] I know what the key catalysts are (what has to happen for this to work)
- [ ] I know what the main risks are (what kills the thesis)

### Valuation
- [ ] I've looked at current valuation (P/E, P/B, EV/EBITDA, or FFO for REITs)
- [ ] I've compared it to historical valuation and sector peers
- [ ] I have a rough fair value / target price in mind

### Portfolio fit
- [ ] This position is < 10% of total portfolio
- [ ] I'm not doubling up on a sector already overweight
- [ ] I know which broker I'll use and why

### Conviction
- [ ] I'd still buy this at +10% from today's price
- [ ] I'm comfortable if this drops 40% — I'd either hold or add, not panic sell
- [ ] I know my intended hold period (minimum 2 years)

### Admin
- [ ] Idea is filed in `ideas/` with thesis notes
- [ ] `portfolio/transactions.csv` will be updated after execution (holdings are derived — run `scripts/update_charts.py`)
- [ ] Position entry is added to `strategy/asset-allocation.md` rebalancing log

---

## Pre-Sell Checklist

- [ ] Has the original thesis changed, or are my emotions talking?
- [ ] If trimming: is this above my 10% cap or outside my allocation band?
- [ ] Tax: checked the implications for my jurisdiction (see `stock-evaluation-framework.md` §4) — capital gains, lot selection, reference dates.
- [ ] Am I selling to rebalance (good) or because of a short-term price move (bad)?
- [ ] After selling, will I update `transactions.csv` and re-run `scripts/update_charts.py`?

---

## Pass Criteria (reasons it's okay to skip a position)

- I don't understand the business model well enough
- The thesis depends entirely on macro timing
- I'm buying because of social media buzz or FOMO
- Position would overlap > 70% with something I already hold
