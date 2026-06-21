"""
Tests for scripts/reconcile.py — pure ledger accounting, no network.
"""
import pytest
from reconcile import (
    derive_holdings, compute_dividend_summary, compute_realised_pnl,
    compute_twr_index, unadjust_splits, txn_amount, EPS,
)

# ── Fixtures / helpers ────────────────────────────────────────────────────────

INSTRUMENTS = {
    "CSPX": {
        "name": "iShares Core S&P 500", "isin": "IE00B5BMR087",
        "asset_class": "Global Equities", "yf_symbol": "CSPX.AS", "currency": "EUR",
    },
    "ACME": {
        "name": "Acme Holdings NV", "isin": "XX0000000001",
        "asset_class": "Quality Compounders", "yf_symbol": "ACME.AS", "currency": "EUR",
    },
}


def txn(date, action, ticker, shares, total, broker="DEGIRO", fee=0):
    return {
        "date": date, "action": action, "ticker": ticker,
        "shares": str(shares), "total": str(total),
        "broker": broker, "fee": str(fee),
    }


def div(date, ticker, amount, broker="DEGIRO"):
    return {
        "date": date, "action": "DIVIDEND", "ticker": ticker,
        "shares": "0", "total": str(amount), "broker": broker, "fee": "0",
    }


# ── derive_holdings ───────────────────────────────────────────────────────────

class TestDeriveHoldings:
    def test_single_buy(self):
        h, warns, errs = derive_holdings(
            [txn("2024-01-01", "BUY", "CSPX", 10, 1000)], INSTRUMENTS
        )
        assert not errs
        assert len(h) == 1
        assert h[0]["ticker"] == "CSPX"
        assert h[0]["shares"] == 10.0
        assert h[0]["cost_basis"] == 1000.0
        assert h[0]["avg_cost"] == 100.0

    def test_buy_then_partial_sell(self):
        h, _, errs = derive_holdings([
            txn("2024-01-01", "BUY",  "CSPX", 10, 1000),
            txn("2024-06-01", "SELL", "CSPX",  4,  480),
        ], INSTRUMENTS)
        assert not errs
        assert abs(h[0]["shares"] - 6.0) < EPS
        assert abs(h[0]["cost_basis"] - 600.0) < 0.01

    def test_full_sell_closes_position(self):
        h, _, errs = derive_holdings([
            txn("2024-01-01", "BUY",  "CSPX", 5, 500),
            txn("2024-12-01", "SELL", "CSPX", 5, 600),
        ], INSTRUMENTS)
        assert not errs
        assert len(h) == 0  # closed — excluded from live holdings

    def test_oversell_is_hard_error(self):
        _, _, errs = derive_holdings([
            txn("2024-01-01", "BUY",  "CSPX", 3, 300),
            txn("2024-06-01", "SELL", "CSPX", 5, 500),
        ], INSTRUMENTS)
        assert len(errs) == 1
        assert "CSPX" in errs[0]
        assert "reconcile" in errs[0].lower()

    def test_dividend_does_not_affect_shares(self):
        h, _, errs = derive_holdings([
            txn("2024-01-01", "BUY", "CSPX", 10, 1000),
            div("2024-06-01", "CSPX", 25.50),
        ], INSTRUMENTS)
        assert not errs
        assert h[0]["shares"] == 10.0

    def test_missing_instrument_warns_not_errors(self):
        h, warns, errs = derive_holdings(
            [txn("2024-01-01", "BUY", "UNKNOWN", 5, 500)], {}
        )
        assert not errs
        assert len(h) == 1
        assert any("UNKNOWN" in w for w in warns)

    def test_fractional_shares_preserved(self):
        h, _, errs = derive_holdings(
            [txn("2024-01-01", "BUY", "CSPX", 0.123456, 50.00)], INSTRUMENTS
        )
        assert not errs
        assert abs(h[0]["shares"] - 0.123456) < EPS

    def test_same_ticker_different_brokers_tracked_separately(self):
        h, _, errs = derive_holdings([
            txn("2024-01-01", "BUY", "CSPX", 5,  500, broker="DEGIRO"),
            txn("2024-01-02", "BUY", "CSPX", 3,  300, broker="Trade Republic"),
        ], INSTRUMENTS)
        assert not errs
        assert len(h) == 2
        pairs = {(x["ticker"], x["broker"]) for x in h}
        assert ("CSPX", "DEGIRO") in pairs
        assert ("CSPX", "Trade Republic") in pairs

    def test_average_cost_two_lots(self):
        # Buy 2 @ €900 = €1800; buy 1 @ €1050 = €1050; avg = €2850/3 = €950
        h, _, errs = derive_holdings([
            txn("2024-01-01", "BUY", "ACME", 2, 1800),
            txn("2024-03-01", "BUY", "ACME", 1, 1050),
        ], INSTRUMENTS)
        assert not errs
        assert h[0]["shares"] == 3.0
        assert abs(h[0]["avg_cost"] - 950.0) < 0.01

    def test_multiple_tickers_independent(self):
        h, _, errs = derive_holdings([
            txn("2024-01-01", "BUY", "CSPX",  10, 1000),
            txn("2024-01-02", "BUY", "ACME",  2, 1800),
        ], INSTRUMENTS)
        assert not errs
        assert len(h) == 2
        tickers = {x["ticker"] for x in h}
        assert tickers == {"CSPX", "ACME"}

    def test_sell_reduces_cost_basis_proportionally(self):
        # 10 shares @ avg €100 = €1000 cost; sell 5 → remaining cost = €500
        h, _, errs = derive_holdings([
            txn("2024-01-01", "BUY",  "CSPX", 10, 1000),
            txn("2024-06-01", "SELL", "CSPX",  5,  600),
        ], INSTRUMENTS)
        assert not errs
        assert abs(h[0]["cost_basis"] - 500.0) < 0.01

    def test_empty_transactions_returns_empty(self):
        h, warns, errs = derive_holdings([], INSTRUMENTS)
        assert h == []
        assert warns == []
        assert errs == []

    def test_asset_class_taken_from_instruments(self):
        h, _, _ = derive_holdings(
            [txn("2024-01-01", "BUY", "ACME", 1, 900)], INSTRUMENTS
        )
        assert h[0]["asset_class"] == "Quality Compounders"


# ── compute_dividend_summary ──────────────────────────────────────────────────

class TestDividendSummary:
    def test_totals_and_per_ticker(self):
        txns = [
            div("2024-03-01", "CSPX",  10.0),
            div("2024-06-01", "CSPX",  12.0),
            div("2024-06-01", "ACME",  5.0),
            txn("2024-01-01", "BUY", "CSPX", 10, 1000),  # BUYs are ignored
        ]
        total, by_ticker = compute_dividend_summary(txns)
        assert total == 27.0
        assert by_ticker["CSPX"]  == 22.0
        assert by_ticker["ACME"] == 5.0

    def test_empty(self):
        total, by_ticker = compute_dividend_summary([])
        assert total == 0.0
        assert by_ticker == {}

    def test_only_buys_no_dividends(self):
        txns = [txn("2024-01-01", "BUY", "CSPX", 5, 500)]
        total, by_ticker = compute_dividend_summary(txns)
        assert total == 0.0
        assert by_ticker == {}


# ── compute_realised_pnl ──────────────────────────────────────────────────────

class TestRealisedPnl:
    def test_profitable_full_exit(self):
        txns = [
            txn("2024-01-01", "BUY",  "CSPX", 10, 1000),
            txn("2024-12-01", "SELL", "CSPX", 10, 1200),
        ]
        pnl, _ = compute_realised_pnl(txns)
        assert abs(pnl - 200.0) < 0.01

    def test_partial_sell_realised(self):
        # Buy 10 @ avg €100; sell 5 @ €120 → realised = 5*(120-100) = €100
        txns = [
            txn("2024-01-01", "BUY",  "CSPX", 10, 1000),
            txn("2024-06-01", "SELL", "CSPX",  5,  600),
        ]
        pnl, _ = compute_realised_pnl(txns)
        assert abs(pnl - 100.0) < 0.01

    def test_loss_on_sell(self):
        txns = [
            txn("2024-01-01", "BUY",  "CSPX", 10, 1000),
            txn("2024-12-01", "SELL", "CSPX", 10,  800),
        ]
        pnl, _ = compute_realised_pnl(txns)
        assert abs(pnl - (-200.0)) < 0.01

    def test_fees_accumulated_across_all_actions(self):
        txns = [
            txn("2024-01-01", "BUY",      "CSPX", 10, 1000, fee=1.50),
            div("2024-06-01", "CSPX", 25.0),  # dividends don't have fee field → 0
            txn("2024-12-01", "SELL",     "CSPX", 10, 1200, fee=1.50),
        ]
        _, fees = compute_realised_pnl(txns)
        assert abs(fees - 3.0) < 0.01

    def test_no_sells_zero_pnl(self):
        txns = [txn("2024-01-01", "BUY", "CSPX", 5, 500)]
        pnl, _ = compute_realised_pnl(txns)
        assert pnl == 0.0

    def test_empty_transactions(self):
        pnl, fees = compute_realised_pnl([])
        assert pnl == 0.0
        assert fees == 0.0


# ── compute_twr_index ─────────────────────────────────────────────────────────

def hist(pv, inv, div=0.0):
    return {"portfolio_value": pv, "net_invested": inv, "cum_dividends_net": div}


class TestTwrIndex:
    def test_first_valued_sample_is_100(self):
        assert compute_twr_index([hist(1000, 1000)]) == [100.0]

    def test_leading_empty_months_are_none(self):
        out = compute_twr_index([hist(0, 0), hist(0, 0), hist(500, 500)])
        assert out == [None, None, 100.0]

    def test_pure_deposit_is_not_performance(self):
        # Month 2: deposit 1000, prices flat → index must stay 100
        out = compute_twr_index([hist(1000, 1000), hist(2000, 2000)])
        assert out == [100.0, 100.0]

    def test_pure_price_gain(self):
        # No flows, value +10% → index 110
        out = compute_twr_index([hist(1000, 1000), hist(1100, 1000)])
        assert out == [100.0, 110.0]

    def test_deposit_plus_gain_strips_flow(self):
        # Deposit 1000 at period start, then +10% on the 2000 base
        out = compute_twr_index([hist(1000, 1000), hist(2200, 2000)])
        assert out == [100.0, 110.0]

    def test_withdrawal_is_not_a_loss(self):
        # Sell half (proceeds 500 leave), prices flat → index stays 100
        out = compute_twr_index([hist(1000, 1000), hist(500, 500)])
        assert out == [100.0, 100.0]

    def test_dividend_counts_as_return(self):
        # Prices flat, 20 net dividend received on 1000 → +2%
        out = compute_twr_index([hist(1000, 1000), hist(1000, 1000, div=20.0)])
        assert out == [100.0, 102.0]

    def test_chaining_two_periods(self):
        # +10% then -10% → 100 * 1.1 * 0.9 = 99
        out = compute_twr_index([
            hist(1000, 1000), hist(1100, 1000), hist(990, 1000),
        ])
        assert out == [100.0, 110.0, 99.0]

    def test_full_liquidation_carries_index_flat(self):
        # Everything sold at fair value → base ~0 next period, index holds
        out = compute_twr_index([hist(1000, 1000), hist(0, 0), hist(0, 0)])
        assert out[0] == 100.0
        assert out[1] == out[2] == 100.0

    def test_empty_history(self):
        assert compute_twr_index([]) == []

    def test_realistic_dca_sequence(self):
        # 200/mo DCA, steady +1%/mo market: index compounds ~1.01/mo
        # regardless of growing contributions
        rows, pv, inv = [], 0.0, 0.0
        for _ in range(12):
            inv += 200.0
            pv = (pv + 200.0) * 1.01
            rows.append(hist(round(pv, 2), round(inv, 2)))
        out = compute_twr_index(rows)
        assert abs(out[-1] - 100.0 * 1.01 ** 11) < 0.1


# ── unadjust_splits ───────────────────────────────────────────────────────────

class TestUnadjustSplits:
    def test_no_splits_passthrough(self):
        from datetime import date
        prices = {date(2022, 4, 22): 45.6}
        assert unadjust_splits(prices, {}) == prices

    def test_price_before_split_scaled_up(self):
        # SHOP 10:1 on 2022-06-29 — April adjusted close ~45.6 was really ~456
        from datetime import date
        prices = {date(2022, 4, 22): 45.6, date(2022, 7, 1): 31.0}
        out = unadjust_splits(prices, {date(2022, 6, 29): 10.0})
        assert abs(out[date(2022, 4, 22)] - 456.0) < 0.01
        assert out[date(2022, 7, 1)] == 31.0  # after split: untouched

    def test_split_date_itself_not_scaled(self):
        # yfinance closes ON the split date are already in post-split units
        from datetime import date
        prices = {date(2022, 6, 29): 35.0}
        out = unadjust_splits(prices, {date(2022, 6, 29): 10.0})
        assert out[date(2022, 6, 29)] == 35.0

    def test_multiple_splits_compound(self):
        from datetime import date
        prices = {date(2020, 1, 1): 10.0}
        out = unadjust_splits(prices, {
            date(2021, 1, 1): 2.0, date(2022, 1, 1): 3.0,
        })
        assert abs(out[date(2020, 1, 1)] - 60.0) < 1e-9


# ── txn_amount: canonical columns + legacy _eur back-compat ───────────────────

class TestTxnAmount:
    def test_reads_canonical_column(self):
        assert txn_amount({"total": "827.50"}, "total") == 827.50

    def test_falls_back_to_legacy_eur_column(self):
        assert txn_amount({"total_eur": "827.50"}, "total") == 827.50
        assert txn_amount({"fee_eur": "2.50"}, "fee") == 2.50

    def test_canonical_wins_over_legacy(self):
        assert txn_amount({"total": "10", "total_eur": "99"}, "total") == 10.0

    def test_missing_and_blank_are_zero(self):
        assert txn_amount({}, "total") == 0.0
        assert txn_amount({"total": ""}, "total") == 0.0

    def test_legacy_eur_ledger_still_reconciles(self):
        # A pre-rename CSV row uses total_eur/fee_eur — must still derive holdings.
        legacy = [{
            "date": "2024-01-01", "action": "BUY", "ticker": "CSPX",
            "shares": "10", "total_eur": "1000", "broker": "DEGIRO", "fee_eur": "1.50",
        }]
        h, _, errs = derive_holdings(legacy, INSTRUMENTS)
        assert not errs
        assert h[0]["cost_basis"] == 1000.0
        _, fees = compute_realised_pnl(legacy)
        assert abs(fees - 1.50) < 0.01
