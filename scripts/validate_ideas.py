#!/usr/bin/env python3
"""
validate_ideas.py
-----------------
CI check: every idea file in ideas/ (except _template.md and watchlist.md)
must contain the required template sections.

Required fields (derived from ideas/_template.md):
  - Status: field in the header block
  - ## Valuation section
  - ## Decision section
  - At least one conviction star (⭐)

Exits 1 with a report if any file is missing required sections.
"""
import sys
from pathlib import Path

ROOT      = Path(__file__).parent.parent
IDEAS_DIR = ROOT / "ideas"
SKIP      = {"_template.md", "watchlist.md"}

REQUIRED = [
    ("Status:",       "Status: field missing (add to header block)"),
    ("## Valuation",  "## Valuation section missing"),
    ("## Decision",   "## Decision section missing"),
    ("⭐",            "Conviction rating missing (add ⭐ stars to header)"),
]


def main():
    idea_files = sorted(f for f in IDEAS_DIR.glob("*.md") if f.name not in SKIP)
    if not idea_files:
        print("No idea files found — nothing to validate.")
        return 0

    errors: list[str] = []
    for path in idea_files:
        text = path.read_text(encoding="utf-8")
        for token, message in REQUIRED:
            if token not in text:
                errors.append(f"{path.name}: {message}")

    if errors:
        print(f"❌  Idea file validation failed ({len(errors)} issue(s)):\n")
        for e in errors:
            print(f"  • {e}")
        print(f"\nFix the above files to match ideas/_template.md")
        return 1

    passed = len(idea_files)
    print(f"✅  {passed} idea file(s) validated — all required sections present.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
