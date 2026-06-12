# Contributing

Contributions that improve the **framework, automation, or dashboard** are welcome.
Contributions that are personal investment-specific (specific tickers, theses,
personal allocations) are out of scope.

## What to contribute

- Bug fixes in `scripts/` (reconciliation, price fetching, dashboard)
- Improvements to `strategy/` docs that apply universally (not jurisdiction-specific)
- New features in `docs/index.html` or `update_charts.py`
- Improvements to `ideas/_template.md`
- Documentation fixes in `SETUP.md`

## What not to contribute

- Your personal transactions or holdings data
- Idea files for specific tickers (those belong in your own fork)
- Jurisdiction-specific tax rules as defaults (document them in your own fork's §4)

## How to contribute

1. Fork the repo
2. Create a branch: `git checkout -b feat/your-improvement`
3. Make changes; run `python -m pytest tests/ -q` to verify accounting logic
4. Open a PR with a clear description of what the improvement does

## Code style

- Python: follow PEP 8; no external dependencies beyond `yfinance` and `pandas`
- JavaScript: vanilla ES2020; no build step, no npm
- Markdown: sentence-per-line for easy diffs
