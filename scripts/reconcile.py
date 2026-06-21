"""
reconcile.py
------------
Pure ledger accounting — no network calls, no file output.

Import this module to derive holdings and compute P&L from the CSV
source-of-truth files without touching the network. Designed so tests
can run offline and so update_charts.py can fail on network errors
without corrupting the accounting layer.
"""

import csv
import os
from pathlib import Path
from typing import Dict

ROOT             = Path(__file__).parent.parent
TRANSACTIONS_CSV = ROOT / "portfolio" / "transactions.csv"
INSTRUMENTS_CSV  = ROOT / "portfolio" / "instruments.csv"

# ~15% US dividend withholding tax under treaty. NOT a tax calculation.
WHT_NET_FACTOR = 0.85
# Share-count tolerance for fractional ETF savings plans
EPS = 1e-6

# ── Base currency configuration ─────────────────────────────────────────────
# Every ledger amount (the price/total/fee columns, cost basis, market value,
# all dashboard figures) is denominated in this currency. Instruments quoted in
# any OTHER currency are converted into it via yfinance FX (see
# update_charts.fetch_fx). Override with the BASE_CURRENCY env var, e.g.
#   BASE_CURRENCY=USD python scripts/update_charts.py
# Default EUR — change the env var, not this line.
BASE_CURRENCY = (os.environ.get("BASE_CURRENCY") or "EUR").strip().upper()

# Symbol + number locale used to format figures on the CLI and dashboard.
# Auto-resolved from BASE_CURRENCY; override with CURRENCY_SYMBOL / NUMBER_LOCALE.
_CURRENCY_SYMBOLS = {
    "EUR": "€",  "USD": "$",  "GBP": "£",  "JPY": "¥",   "CHF": "CHF ",
    "CAD": "C$", "AUD": "A$", "NZD": "NZ$", "SGD": "S$", "HKD": "HK$",
    "SEK": "kr ", "NOK": "kr ", "DKK": "kr ", "PLN": "zł ", "CZK": "Kč ",
    "INR": "₹",  "BRL": "R$", "ZAR": "R",  "KRW": "₩",  "CNY": "¥",
}
CURRENCY_SYMBOL = (os.environ.get("CURRENCY_SYMBOL")
                   or _CURRENCY_SYMBOLS.get(BASE_CURRENCY, BASE_CURRENCY + " "))
# de-DE preserves the original EUR formatting (1.234,56); everything else
# defaults to en-US (1,234.56). Override with NUMBER_LOCALE.
NUMBER_LOCALE = (os.environ.get("NUMBER_LOCALE")
                 or ("de-DE" if BASE_CURRENCY == "EUR" else "en-US"))


def txn_amount(row, name):
    """Read a ledger money column by its canonical name, falling back to the
    legacy ``<name>_eur`` header so pre-rename CSVs (and forks) keep loading.
    ``name`` is one of ``price`` / ``total`` / ``fee``. Returns a float."""
    val = row.get(name)
    if val in (None, ""):
        val = row.get(f"{name}_eur")
    return float(val or 0)


def load_instruments(path=INSTRUMENTS_CSV) -> Dict[str, dict]:
    inst: Dict[str, dict] = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            t = row["ticker"].strip()
            if not t:
                continue
            inst[t] = {
                "name":        row.get("name", "").strip(),
                "isin":        row.get("isin", "").strip(),
                "asset_class": row.get("asset_class", "Other").strip() or "Other",
                "yf_symbol":   row.get("yf_symbol", "").strip() or t,
                "currency":    (row.get("currency", "").strip() or BASE_CURRENCY).upper(),
            }
    return inst


def load_transactions(path=TRANSACTIONS_CSV):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get("ticker") and row.get("ticker") != "EXAMPLE":
                rows.append(row)
    return rows


def derive_holdings(transactions, instruments):
    """
    Average-cost method, tracked per (ticker, broker).

      BUY  : cost basis += total; shares += shares
      SELL : shares and cost basis reduced at the running average cost

    Returns (holdings, warnings, errors).
    A negative net share count is a hard error — the ledger does not reconcile.
    """
    book: Dict[tuple, dict] = {}
    order: list = []
    warnings: list = []
    errors: list = []

    for r in transactions:
        action = r.get("action", "")
        if action not in ("BUY", "SELL"):
            continue
        ticker = r["ticker"].strip()
        broker = r.get("broker", "").strip() or "Unknown"
        shares = float(r.get("shares") or 0)
        total  = txn_amount(r, "total")
        key = (ticker, broker)
        if key not in book:
            book[key] = {"shares": 0.0, "cost": 0.0}
            order.append(key)
        h = book[key]

        if action == "BUY":
            h["shares"] += shares
            h["cost"]   += total
        elif action == "SELL":
            if shares - h["shares"] > EPS:
                errors.append(
                    f"{ticker} @ {broker}: SELL {shares:g} but only "
                    f"{h['shares']:g} held — ledger does not reconcile "
                    f"(date {r.get('date')})"
                )
            avg = (h["cost"] / h["shares"]) if h["shares"] > EPS else 0.0
            h["cost"]   = max(0.0, h["cost"] - avg * shares)
            h["shares"] = h["shares"] - shares

    holdings = []
    for key in order:
        ticker, broker = key
        h = book[key]
        if h["shares"] <= EPS:
            continue  # closed position — excluded from live holdings
        meta = instruments.get(ticker)
        if meta is None:
            warnings.append(f"{ticker}: no row in instruments.csv — using defaults")
            meta = {"name": ticker, "isin": "", "asset_class": "Other",
                    "yf_symbol": ticker, "currency": BASE_CURRENCY}
        shares   = round(h["shares"], 6)
        cost     = round(h["cost"], 2)
        avg_cost = round(cost / shares, 4) if shares else 0.0
        holdings.append({
            "ticker":      ticker,
            "name":        meta["name"],
            "isin":        meta["isin"],
            "asset_class": meta["asset_class"],
            "broker":      broker,
            "shares":      shares,
            "avg_cost":    avg_cost,
            "cost_basis":  cost,
            "currency":    meta["currency"],
            "yf_symbol":   meta["yf_symbol"],
        })
    return holdings, warnings, errors


def allocation_by(holdings, field) -> Dict[str, float]:
    out: Dict[str, float] = {}
    for h in holdings:
        k = h.get(field, "Other")
        out[k] = round(out.get(k, 0) + h["market_value"], 2)
    return out


def compute_dividend_summary(transactions):
    div_rows = [r for r in transactions if r.get("action") == "DIVIDEND"]
    total = sum(txn_amount(r, "total") for r in div_rows)
    by_ticker: Dict[str, float] = {}
    for r in div_rows:
        t = r["ticker"]
        by_ticker[t] = round(by_ticker.get(t, 0.0) + txn_amount(r, "total"), 2)
    return round(total, 2), by_ticker


def unadjust_splits(prices, splits):
    """Convert split-adjusted prices back to the share units in effect on each
    date. yfinance closes are always split-adjusted to today's units, but the
    ledger records splits as same-total SELL/BUY pairs, so historical share
    counts are in the units of their own date. Valuing those shares needs
    price_unadjusted(d) = price_adjusted(d) × Π ratio for all splits after d.

    prices: {date: adjusted_price}; splits: {date: ratio} (e.g. 10.0 for 10:1).
    """
    if not splits:
        return dict(prices)
    out = {}
    for d, p in prices.items():
        f = 1.0
        for sd, ratio in splits.items():
            if sd > d and ratio:
                f *= ratio
        out[d] = p * f
    return out


def compute_twr_index(history):
    """Time-weighted return index (100 = first valued sample), chained per period.

    Each history row needs portfolio_value, net_invested and cum_dividends_net.
    External flows are derived from net_invested deltas and assumed to occur at
    the start of the period, so new cash earns the period return but is never
    counted as performance. Dividends received count as return, not flow.

    Returns a list (same length as history) of index values; None until the
    portfolio has a value. If a period's flow-adjusted base is ~0 (e.g. full
    liquidation), the index carries flat — a return is undefined there.
    """
    out = []
    index = None
    prev_v = prev_inv = prev_div = 0.0
    for row in history:
        v   = float(row.get("portfolio_value") or 0.0)
        inv = float(row.get("net_invested") or 0.0)
        div = float(row.get("cum_dividends_net") or 0.0)
        if index is None:
            if v > EPS:
                index = 100.0
                out.append(100.0)
                prev_v, prev_inv, prev_div = v, inv, div
            else:
                out.append(None)
            continue
        flow  = inv - prev_inv
        denom = prev_v + flow
        if denom > EPS:
            r = (v - prev_v - flow + (div - prev_div)) / denom
            index *= 1.0 + r
        out.append(round(index, 2))
        prev_v, prev_inv, prev_div = v, inv, div
    return out


def compute_realised_pnl(transactions):
    book: Dict[tuple, dict] = {}
    realised = 0.0
    fees = 0.0
    for r in transactions:
        action = r.get("action", "")
        fees += txn_amount(r, "fee")
        if action not in ("BUY", "SELL"):
            continue
        key = (r["ticker"], r.get("broker", ""))
        shares = float(r.get("shares") or 0)
        total  = txn_amount(r, "total")
        h = book.setdefault(key, {"shares": 0.0, "cost": 0.0})
        if action == "BUY":
            h["shares"] += shares
            h["cost"]   += total
        elif action == "SELL":
            avg = (h["cost"] / h["shares"]) if h["shares"] > EPS else 0.0
            realised   += total - avg * shares
            h["cost"]   = max(0.0, h["cost"] - avg * shares)
            h["shares"] = max(0.0, h["shares"] - shares)
    return round(realised, 2), round(fees, 2)
