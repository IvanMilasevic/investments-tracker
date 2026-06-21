"""
update_charts.py
-----------------
Orchestrator — ties ledger reconciliation, live prices, benchmark data,
and dashboard generation together.

Pure accounting logic lives in reconcile.py (importable, no network).
This file owns: network calls, file output, and main().

Source of truth:
  - portfolio/transactions.csv  ← full trade/dividend ledger (you edit this)
  - portfolio/instruments.csv   ← static metadata: name, class, yf symbol, currency

Derived (never hand-edit):
  - portfolio/holdings_generated.csv
  - portfolio/nav_log.csv         ← NAV snapshot per run — commit this file
  - docs/portfolio_data.json / .js

Requirements: pip install yfinance pandas
"""

import csv
import json
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Dict, Optional

import urllib3
urllib3.disable_warnings(urllib3.exceptions.NotOpenSSLWarning)

try:
    import yfinance as yf
    import pandas as pd  # noqa: F401
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False
    print("⚠️  yfinance / pandas not installed. Run: pip install yfinance pandas")

# Import pure accounting layer (no network, fully testable)
sys.path.insert(0, str(Path(__file__).parent))
from reconcile import (
    BASE_CURRENCY, CURRENCY_SYMBOL, NUMBER_LOCALE,
    EPS, WHT_NET_FACTOR,
    INSTRUMENTS_CSV, TRANSACTIONS_CSV,
    allocation_by, compute_dividend_summary, compute_realised_pnl,
    compute_twr_index, derive_holdings, load_instruments, load_transactions,
    txn_amount, unadjust_splits,
)

SYM = CURRENCY_SYMBOL  # short alias for f-string formatting

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT         = Path(__file__).parent.parent
HOLDINGS_OUT = ROOT / "portfolio" / "holdings_generated.csv"
NAV_LOG      = ROOT / "portfolio" / "nav_log.csv"
DOCS_DIR     = ROOT / "docs"
DATA_OUT     = DOCS_DIR / "portfolio_data.json"
DATA_OUT_JS  = DOCS_DIR / "portfolio_data.js"
WATCHLIST_MD = ROOT / "ideas" / "watchlist.md"

# Benchmark ETFs as (yfinance symbol, listing currency). Prices are converted
# into the base currency just like holdings, so the indexed comparison reflects
# what a base-currency investor actually experiences (FX drift included).
BENCHMARK_SYMBOLS = {
    "benchmark_msci_world": ("IWDA.AS", "EUR"),  # iShares Core MSCI World UCITS ETF
    "benchmark_sp500":      ("CSPX.AS", "EUR"),  # iShares Core S&P 500 UCITS ETF
}

UNLISTED_SENTINELS = {"", "—", "–", "-", "n/a", "N/A", "NA", "None"}


def is_unlisted(yf_symbol: str) -> bool:
    return (yf_symbol or "").strip() in UNLISTED_SENTINELS


# ── FX ────────────────────────────────────────────────────────────────────────
def fetch_fx(currencies, base: str = BASE_CURRENCY):
    """Fetch FX history for every non-base currency vs the base currency.

    Returns (by_date, latest):
      by_date[CUR] = {date: rate}   latest[CUR] = rate
    where `rate` is units of base per 1 unit of CUR (yfinance "<CUR><BASE>=X"
    Close). The base currency itself maps to rate 1.0. Missing currencies are
    simply absent — callers fall back to cost basis when a rate is unavailable.
    """
    by_date: Dict[str, Dict] = {base: {}}
    latest:  Dict[str, float] = {base: 1.0}
    if not HAS_DEPS:
        return by_date, latest
    wanted = sorted({(c or base).upper() for c in currencies} - {base})
    for cur in wanted:
        symbol = f"{cur}{base}=X"
        try:
            hist = yf.Ticker(symbol).history(period="max", auto_adjust=False)
            if hist.empty:
                print(f"  ⚠️  No FX history for {symbol}")
                continue
            close = hist["Close"].dropna()
            by_date[cur] = {idx.date(): float(p) for idx, p in close.items()}
            latest[cur]  = float(close.iloc[-1])
        except Exception as e:
            print(f"  ⚠️  Could not fetch {symbol}: {e}")
    return by_date, latest


def to_base(amount: float, currency: str, fx_rate: Optional[float],
            base: str = BASE_CURRENCY):
    """Convert `amount` (in `currency`) into the base currency.
    `fx_rate` = base per 1 unit of `currency`. Returns None when conversion is
    required but no rate is available (caller falls back to cost basis)."""
    if (currency or base).upper() == base:
        return amount
    if not fx_rate:
        return None
    return amount * fx_rate


def fetch_price(yf_symbol: str) -> Optional[float]:
    """Fetch latest price. Falls back to fast_info.last_price on stale history().
    Returns None for unlisted-sentinel symbols (caller uses cost-basis silently)."""
    if not HAS_DEPS:
        return None
    if is_unlisted(yf_symbol):
        return None
    try:
        t = yf.Ticker(yf_symbol)
        hist = t.history(period="5d")
        if not hist.empty:
            close = hist["Close"].dropna()
            if not close.empty:
                return round(float(close.iloc[-1]), 4)
        try:
            px = t.fast_info.last_price
            if px is not None and px == px:  # not NaN
                return round(float(px), 4)
        except Exception:
            pass
        return None
    except Exception as e:
        print(f"  ⚠️  Could not fetch {yf_symbol}: {e}")
        return None


# ── Price holdings and compute stats ──────────────────────────────────────────
def compute_portfolio(holdings, latest_fx):
    total_value = 0.0
    fallbacks = []

    for h in holdings:
        native = fetch_price(h["yf_symbol"])
        price = None
        if native is not None:
            cur = (h["currency"] or BASE_CURRENCY).upper()
            price = to_base(native, cur, latest_fx.get(cur))

        if price is None:
            price = h["avg_cost"]
            if is_unlisted(h["yf_symbol"]):
                h["price_source"] = "unlisted_cost_basis"
            else:
                h["price_source"] = "fallback_avg_cost"
                fallbacks.append(f"{h['ticker']} @ {h['broker']} ({h['yf_symbol']})")
        else:
            h["price_source"] = "live"

        price        = round(price, 4)
        market_value = round(h["shares"] * price, 2)
        cost_basis   = h["cost_basis"]
        pnl          = round(market_value - cost_basis, 2)
        pnl_pct      = round((pnl / cost_basis * 100) if cost_basis else 0, 2)

        h["current_price"]  = price
        h["market_value"]   = market_value
        h["unrealised_pnl"] = pnl
        h["pnl_pct"]        = pnl_pct
        total_value += market_value

    for h in holdings:
        h["weight_pct"] = round(h["market_value"] / total_value * 100, 2) if total_value else 0
    return holdings, round(total_value, 2), fallbacks


# ── Monthly history (FX-aware) + benchmark comparison ─────────────────────────
def compute_history(transactions, instruments, fx_by_date):
    """
    Reconstruct monthly portfolio value from the ledger + yfinance history.
    Also fetches monthly MSCI World and S&P 500 benchmark prices for comparison.
    Each entry includes benchmark_msci_world and benchmark_sp500 in base currency.

    fx_by_date maps currency → {date: rate} (base per 1 unit of currency), as
    produced by fetch_fx().
    """
    if not HAS_DEPS:
        return []
    txns = sorted(
        [r for r in transactions if r.get("action") in ("BUY", "SELL", "DIVIDEND")],
        key=lambda r: r["date"],
    )
    if not txns:
        return []

    start  = datetime.strptime(txns[0]["date"], "%Y-%m-%d").date()
    today  = date.today()
    traded = sorted({r["ticker"] for r in txns if r.get("action") in ("BUY", "SELL")})

    price_cache: Dict[str, Dict] = {}
    for t in traded:
        meta = instruments.get(t, {"yf_symbol": t})
        if is_unlisted(meta.get("yf_symbol", "")):
            continue
        try:
            # auto_adjust=False required: auto_adjust=True returns NaN Close for many
            # non-US tickers (yfinance bug since 2025)
            hist = yf.Ticker(meta["yf_symbol"]).history(period="max", auto_adjust=False)
            if not hist.empty:
                close  = hist["Close"].dropna()
                prices = {idx.date(): float(p) for idx, p in close.items()}
                sp     = hist.get("Stock Splits")
                splits = ({idx.date(): float(r) for idx, r in sp.items() if r}
                          if sp is not None else {})
                price_cache[t] = unadjust_splits(prices, splits)
        except Exception:
            pass

    # Benchmark history (native listing prices — converted to base below)
    bm_cache: Dict[str, Dict] = {}
    bm_ccy:   Dict[str, str]  = {}
    for key, (symbol, ccy) in BENCHMARK_SYMBOLS.items():
        bm_ccy[key] = ccy.upper()
        try:
            hist = yf.Ticker(symbol).history(period="max", auto_adjust=False)
            if not hist.empty:
                close = hist["Close"].dropna()
                bm_cache[key] = {idx.date(): float(p) for idx, p in close.items()}
        except Exception:
            pass

    def lookup(cache, d):
        for i in range(7):
            p = cache.get(d - timedelta(days=i))
            if p is not None:
                return p
        return None

    def fx_on(currency, d):
        """base-per-unit rate for `currency` on/just-before date `d`."""
        cur = (currency or BASE_CURRENCY).upper()
        if cur == BASE_CURRENCY:
            return 1.0
        table = fx_by_date.get(cur)
        if not table:
            return None
        for i in range(7):
            r = table.get(d - timedelta(days=i))
            if r is not None:
                return r
        return None

    sample_dates = []
    y, m = start.year, start.month
    while True:
        last_day = date(y, m + 1, 1) - timedelta(days=1) if m < 12 else date(y, 12, 31)
        cap = min(last_day, today)
        sample_dates.append(cap)
        if cap >= today:
            break
        m += 1
        if m > 12:
            m, y = 1, y + 1

    history = []
    for sd in sample_dates:
        book: Dict[str, dict] = {}
        net_invested = 0.0
        cum_div_net  = 0.0
        for r in txns:
            if r["date"] > str(sd):
                break
            action = r.get("action", "")
            t      = r["ticker"]
            shares = float(r.get("shares") or 0)
            total  = txn_amount(r, "total")
            if action == "BUY":
                book.setdefault(t, {"shares": 0.0})["shares"] += shares
                net_invested += total
            elif action == "SELL":
                h = book.setdefault(t, {"shares": 0.0})
                h["shares"] = max(0.0, h["shares"] - shares)
                net_invested -= total
            elif action == "DIVIDEND":
                cum_div_net += total * WHT_NET_FACTOR

        pv = 0.0
        for t, h in book.items():
            if h["shares"] <= EPS:
                continue
            cache  = price_cache.get(t)
            native = lookup(cache, sd) if cache else None
            if native is None:
                continue
            cur = instruments.get(t, {}).get("currency", BASE_CURRENCY)
            px  = to_base(native, cur, fx_on(cur, sd))
            if px is None:
                continue
            pv += h["shares"] * px

        bm_vals = {}
        for key, cache in bm_cache.items():
            native = lookup(cache, sd)
            px = to_base(native, bm_ccy[key], fx_on(bm_ccy[key], sd)) if native is not None else None
            bm_vals[key] = round(px, 4) if px is not None else None

        history.append({
            "date":              str(sd),
            "portfolio_value":   round(pv, 2),
            "net_invested":      round(net_invested, 2),
            "cum_dividends_net": round(cum_div_net, 2),
            "total_return":      round(pv - net_invested + cum_div_net, 2),
            **bm_vals,
        })

    twr = compute_twr_index(history)
    for row, ti in zip(history, twr):
        row["twr_index"] = ti
    return history


# ── Watchlist ─────────────────────────────────────────────────────────────────
def parse_watchlist():
    ideas = []
    try:
        import re
        with open(WATCHLIST_MD, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if (not line.startswith("|") or line.startswith("| Ticker")
                        or set(line.replace("|", "").replace("-", "").replace(" ", "")) == set()):
                    continue
                parts = [p.strip() for p in line.strip("|").split("|")]
                if len(parts) < 7:
                    continue
                mtk = re.match(r"\[([^\]]+)\]", parts[0])
                if mtk:
                    ticker = mtk.group(1)
                else:
                    plain = re.match(r"^([A-Z][A-Z0-9.]{0,9})$", parts[0])
                    if not plain:
                        continue
                    ticker = plain.group(1)
                ideas.append({
                    "ticker":     ticker,
                    "name":       parts[1],
                    "type":       parts[2],
                    "status":     parts[3],
                    "conviction": parts[4].count("⭐"),
                    "broker":     parts[5],
                    "thesis":     parts[6],
                    "issue_url":  parts[7] if len(parts) > 7 else "",
                })
    except FileNotFoundError:
        pass
    return ideas


# ── Writers ───────────────────────────────────────────────────────────────────
def write_holdings_snapshot(holdings):
    if not holdings:
        return
    cols = ["ticker", "name", "isin", "asset_class", "broker", "shares",
            "avg_cost", "current_price", "market_value",
            "weight_pct", "unrealised_pnl", "pnl_pct", "currency",
            "price_source", "cost_basis"]
    with open(HOLDINGS_OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(holdings)
    print(f"  ✅ Written {HOLDINGS_OUT} (generated — do not hand-edit)")


def write_snapshot(total_value: float, net_invested: float,
                   holdings_count: int, base_currency: str) -> None:
    """Append a NAV row to portfolio/nav_log.csv — commit this file to track actual portfolio history.
    Amounts are in `base_currency` (recorded per row so the series is self-describing)."""
    write_header = not NAV_LOG.exists()
    with open(NAV_LOG, "a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["date", "total_value", "net_invested",
                                           "positions", "base_currency"])
        if write_header:
            w.writeheader()
        w.writerow({
            "date":          str(date.today()),
            "total_value":   total_value,
            "net_invested":  round(net_invested, 2),
            "positions":     holdings_count,
            "base_currency": base_currency,
        })
    print(f"  ✅ NAV snapshot appended → {NAV_LOG.name} (commit this file)")


def write_dashboard(data):
    with open(DATA_OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, default=str)
    with open(DATA_OUT_JS, "w", encoding="utf-8") as f:
        f.write("window.PORTFOLIO_DATA = ")
        json.dump(data, f, indent=2, default=str)
        f.write(";\n")
    print(f"  ✅ Written {DATA_OUT} + .js")


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    print(f"\n📊 Portfolio Update — {date.today()}\n")

    instruments  = load_instruments()
    transactions = load_transactions()
    if not transactions:
        print("No transactions found. Populate portfolio/transactions.csv first.")
        return 1

    holdings, warnings, errors = derive_holdings(transactions, instruments)

    # ── Reconciliation gate ──────────────────────────────────────────────────
    if errors:
        print("❌ LEDGER DOES NOT RECONCILE — refusing to publish:")
        for e in errors:
            print(f"   • {e}")
        print("\nFix portfolio/transactions.csv against your broker statements.")
        return 1
    for w in warnings:
        print(f"  ⚠️  {w}")

    print(f"Derived {len(holdings)} live position(s) from {len(transactions)} ledger rows.")
    print(f"  Base currency: {BASE_CURRENCY}")

    # Every currency we may need to convert into the base: instrument currencies
    # plus benchmark listing currencies.
    currencies = {meta.get("currency", BASE_CURRENCY) for meta in instruments.values()}
    currencies |= {ccy for _, ccy in BENCHMARK_SYMBOLS.values()}
    needed_ccy = sorted({(c or BASE_CURRENCY).upper() for c in currencies} - {BASE_CURRENCY})

    fx_by_date, latest_fx = fetch_fx(currencies)
    if needed_ccy:
        shown = ", ".join(f"{c}→{BASE_CURRENCY} {latest_fx[c]:.4f}"
                          for c in needed_ccy if latest_fx.get(c))
        print(f"  FX {shown}" if shown else
              f"  ⚠️  FX unavailable for {', '.join(needed_ccy)} — those valuations fall back to cost")
        missing = [c for c in needed_ccy if not latest_fx.get(c)]
        if shown and missing:
            print(f"  ⚠️  FX missing for {', '.join(missing)} — those valuations fall back to cost")
    fx_available = all(latest_fx.get(c) for c in needed_ccy)

    holdings, total_value, fallbacks = compute_portfolio(holdings, latest_fx)

    # ── Weight sanity check ──────────────────────────────────────────────────
    wsum = sum(h["weight_pct"] for h in holdings)
    if holdings and abs(wsum - 100.0) > 0.5:
        print(f"❌ Weights sum to {wsum:.2f}%, expected 100% — aborting.")
        return 1

    by_class  = allocation_by(holdings, "asset_class")
    by_broker = allocation_by(holdings, "broker")
    total_div, div_by_ticker = compute_dividend_summary(transactions)
    realised_pnl, total_fees = compute_realised_pnl(transactions)
    unrealised   = round(sum(h["unrealised_pnl"] for h in holdings), 2)
    net_div      = round(total_div * WHT_NET_FACTOR, 2)
    total_return = round(unrealised + realised_pnl + net_div, 2)
    net_invested = round(sum(
        txn_amount(r, "total") * (1 if r.get("action") == "BUY" else -1)
        for r in transactions if r.get("action") in ("BUY", "SELL")
    ), 2)

    print(f"\n💼 Portfolio value:      {SYM}{total_value:,.2f}")
    print(f"   Unrealised P&L:       {SYM}{unrealised:,.2f}")
    print(f"   Realised P&L:         {SYM}{realised_pnl:,.2f}")
    print(f"   Dividends (gross):    {SYM}{total_div:,.2f}  (net ~{SYM}{net_div:,.2f})")
    print(f"   Fees paid:            {SYM}{total_fees:,.2f}")
    print(f"   Total return (est.):  {SYM}{total_return:,.2f}")
    if fallbacks:
        print(f"\n  ⚠️  Price fallback (cost used, NOT live): {', '.join(fallbacks)}")

    print("\nAllocation by class:")
    for c, v in by_class.items():
        print(f"  {c:<22} {SYM}{v:>10,.2f}  ({v / total_value * 100:.1f}%)")

    ideas   = parse_watchlist()
    history = compute_history(transactions, instruments, fx_by_date)

    data = {
        "updated_at":          datetime.now().isoformat(),
        "base_currency":       BASE_CURRENCY,
        "currency_symbol":     CURRENCY_SYMBOL,
        "number_locale":       NUMBER_LOCALE,
        "total_value":         total_value,
        "unrealised_pnl":      unrealised,
        "realised_pnl":        realised_pnl,
        "dividend_income":     total_div,
        "dividend_income_net": net_div,
        "total_return":        total_return,
        "total_fees":          total_fees,
        "dividend_by_ticker":  div_by_ticker,
        "holdings":            holdings,
        "allocation_by_class": by_class,
        "allocation_by_broker": by_broker,
        "ideas":               ideas,
        "history":             history,
        "data_quality": {
            "fx_rates":                {c: round(latest_fx[c], 6) for c in needed_ccy if latest_fx.get(c)},
            "fx_available":            fx_available,
            "price_fallbacks":         fallbacks,
            "reconciliation_warnings": warnings,
            "weights_sum_pct":         round(wsum, 2),
        },
    }

    write_holdings_snapshot(holdings)
    write_snapshot(total_value, net_invested, len(holdings), BASE_CURRENCY)
    write_dashboard(data)
    print("\n✅ Done. Open docs/index.html in your browser.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
