# Setup Guide

Get your own portfolio tracker running in ~15 minutes.

## Prerequisites

- Python 3.11+
- A GitHub account (for GitHub Pages dashboard)
- `pip install yfinance pandas` (or `pip install -r scripts/requirements.txt`)

---

## Step 1 — Fork and clone

1. Click **"Use this template"** (or fork the repo) on GitHub.
2. Clone your fork: `git clone https://github.com/YOUR-USERNAME/investments-tracker`
3. `cd investments-tracker`

---

## Step 2 — Define your instruments

Edit `portfolio/instruments.csv`. Add one row per instrument you hold or plan to track.

Required columns:
| Column | Example | Notes |
|--------|---------|-------|
| `ticker` | `CSPX` | Your internal ticker key — must match `transactions.csv` |
| `name` | `iShares Core S&P 500 UCITS ETF` | Human-readable name |
| `isin` | `IE00B5BMR087` | Optional but useful for audit |
| `asset_class` | `Global Equities` | Must match a key in `TARGETS` in `docs/index.html` |
| `yf_symbol` | `CSPX.AS` | Yahoo Finance ticker — test with `yf.Ticker("CSPX.AS").history(period="5d")` |
| `currency` | `EUR` | The currency the instrument is **quoted** in. Anything ≠ your base currency is auto-converted via yfinance FX (`<CUR><BASE>=X`). |
| `notes` | `accumulating ETF` | Free text |

For instruments not on any exchange (e.g. bank index funds), use `—` as the `yf_symbol` — they will be priced at cost basis.

Closed positions: keep them in the file with `notes: closed; ...` — this preserves dividend history.

**Verify the yfinance symbol before adding**: open Python and run:
```python
import yfinance as yf
print(yf.Ticker("YOUR_SYMBOL").history(period="5d"))
```
If the result is an empty DataFrame, the symbol is wrong — try appending `.AS`, `.L`, `.DE` for European ETFs.

---

## Step 3 — Enter your first trades

Edit `portfolio/transactions.csv`. Append one row per trade event (BUY / SELL / DIVIDEND).

Required columns:
| Column | Format | Example |
|--------|--------|---------|
| `date` | YYYY-MM-DD | `2024-01-15` |
| `ticker` | string | `CSPX` |
| `name` | string | `iShares Core S&P 500` |
| `isin` | string | `IE00B5BMR087` |
| `action` | `BUY` / `SELL` / `DIVIDEND` | `BUY` |
| `shares` | decimal | `2.5` |
| `price` | decimal (base currency) | `412.50` |
| `total` | decimal (base currency, **includes fee**) | `827.50` |
| `broker` | string | `DEGIRO` |
| `fee` | decimal (base currency) | `2.50` |
| `notes` | string | optional |

All money columns (`price` / `total` / `fee`) are in your **base currency**
(default EUR — see Step 4b). Legacy files using `price_eur` / `total_eur` /
`fee_eur` headers still load unchanged.

Important: `total` must be the **total amount debited/credited from your account**, inclusive of broker fees. This is what the reconciliation uses for average-cost accounting.

For instruments quoted in another currency: record `total` as the base-currency
amount your broker actually moved (it already did the FX). Live valuation then
converts the instrument's market price from its `currency` (in `instruments.csv`)
back into your base currency automatically.

---

## Step 4 — Update your target allocation

Edit `docs/index.html` — find the `const TARGETS` object near line 270 and update it to match your `strategy/asset-allocation.md`. The keys must exactly match the `asset_class` values in `instruments.csv`.

Example:
```javascript
const TARGETS = {
  "Global Equities":     55,
  "European Equities":   15,
  "Quality Compounders": 15,
  "Emerging / Thematic":  5,
  "Cash / Bonds":         5,
  "Real Estate":          5,
};
```

Also edit `strategy/asset-allocation.md` to document your chosen allocation and rationale. See `strategy/` for guidance.

---

## Step 4b — (Optional) Pick a base currency

EUR is the default reporting currency. To report in another currency, set the
`BASE_CURRENCY` env var (ISO code) — it drives every figure, the dashboard
symbol/locale, and FX conversion:

```bash
BASE_CURRENCY=USD python scripts/update_charts.py
```

Make it permanent for the GitHub Action by adding it under `env:` in
`.github/workflows/refresh-portfolio.yml`, or export it in your shell profile.
Symbol and number formatting auto-resolve from the currency; override with
`CURRENCY_SYMBOL` / `NUMBER_LOCALE` if you want something different.

---

## Step 5 — Run the script

```bash
python scripts/update_charts.py
```

Expected output:
```
📊 Portfolio Update — 2024-01-15

Derived 3 live position(s) from 12 ledger rows.
  Base currency: EUR
  FX USD→EUR 0.8719

💼 Portfolio value:      €4,230.00
   Unrealised P&L:       €185.20
   ...

✅ Done. Open docs/index.html in your browser.
```

If the script exits with an error:
- **"LEDGER DOES NOT RECONCILE"** → a SELL row exceeds the shares held at that (ticker, broker) pair. Check `transactions.csv` against your broker statement.
- **"no row in instruments.csv"** → add the missing ticker to `instruments.csv`.
- **"No FX history for `<CUR><BASE>=X`"** → that currency pair didn't resolve on Yahoo; those positions fall back to cost basis. Check the instrument's `currency` code.

Open `docs/index.html` in your browser to see the dashboard.

---

## Step 6 — Enable GitHub Pages (automatic dashboard)

1. Push your changes to GitHub: `git add . && git commit -m "init: portfolio data" && git push`
2. In your GitHub repo: **Settings → Pages → Source → GitHub Actions**
3. The `refresh-portfolio.yml` workflow runs weekdays at 17:00 UTC and auto-deploys.
4. Your dashboard URL will be: `https://YOUR-USERNAME.github.io/REPO-NAME/`

The workflow also opens a GitHub Issue if the script fails — check **Issues** if the dashboard stops updating.

> **Privacy note**: a GitHub Pages site is publicly accessible — anyone with the URL
> can see your dashboard. If you track real money here, keep the repo private and be
> aware that private-repo Pages requires a paid GitHub plan.

---

## Step 7 — Add your investment ideas

1. Copy `ideas/_template.md` → `ideas/[TICKER]-[name].md`
2. Fill every section (thesis, valuation, kill-switch, decision)
3. Add a row to `ideas/watchlist.md`
4. (Optional) Run `python scripts/sync_issues.py` to create a GitHub Issue tracking thread

The `validate-ideas.yml` CI workflow will check that each file has the required sections on every push.

---

## Step 8 — Personalise the AI co-pilot (CLAUDE.md)

If you use Claude or another LLM as an investment research assistant:

1. Open `CLAUDE.md`
2. Set your mission / target in the **Mission** section
3. Update the **Target allocation** reference to match your `strategy/asset-allocation.md`
4. Replace the **Tax** section reference with your jurisdiction details (see `strategy/stock-evaluation-framework.md §4`)

The file is pre-configured to make Claude act as a rigorous buy-side analyst. The hard rules (no leverage, no shorting, 10% cap, etc.) are already set — adjust them to your own constraints.

---

## Ongoing Workflow

### After a trade
1. Append rows to `portfolio/transactions.csv`
2. New instrument → add to `instruments.csv` first
3. Run `python scripts/update_charts.py` — fix any errors before committing
4. Commit: `git add portfolio/ && git commit -m "trade: BUY 2 CSPX @ €420"`

### New idea
1. `cp ideas/_template.md ideas/TICKER-name.md` and fill it in
2. Add a row to `ideas/watchlist.md`
3. Push — CI validates the file structure

### Annual rebalance (January)
Run the script → compare Current vs Target in `strategy/asset-allocation.md` → plan trades within bands → execute → log in the rebalancing log.
