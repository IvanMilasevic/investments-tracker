#!/usr/bin/env python3
"""
sync_issues.py
--------------
Idempotent sync: ideas/*.md → GitHub Issues.

Replaces the old create_github_issues.sh. Reads every idea file dynamically
(no hardcoded content), so issues stay in sync automatically as files evolve.

State is stored in .github/.issue_sync — commit this file.
User edits below a <!-- MANUAL --> divider in any issue are preserved on updates.

Prerequisites:
  gh auth login   (one-time interactive setup)

Usage:
  python scripts/sync_issues.py             # live run
  python scripts/sync_issues.py --dry-run   # preview only, no changes
"""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT       = Path(__file__).parent.parent
IDEAS_DIR  = ROOT / "ideas"
SYNC_FILE  = ROOT / ".github" / ".issue_sync"
SKIP_FILES = {"_template.md", "watchlist.md"}
MANUAL_SEP = "<!-- MANUAL -->"


def load_hashes() -> dict:
    if SYNC_FILE.exists():
        return json.loads(SYNC_FILE.read_text(encoding="utf-8"))
    return {}


def save_hashes(hashes: dict) -> None:
    SYNC_FILE.parent.mkdir(parents=True, exist_ok=True)
    SYNC_FILE.write_text(json.dumps(hashes, indent=2, sort_keys=True), encoding="utf-8")


def extract_title(path: Path) -> str:
    """Use the first H1 heading; fall back to prettified filename."""
    text = path.read_text(encoding="utf-8")
    m = re.match(r"^#\s+(.+)", text, re.MULTILINE)
    if m:
        return m.group(1).strip()
    stem = path.stem  # e.g. "MSFT-microsoft"
    ticker = stem.split("-")[0]
    rest   = " ".join(p.capitalize() for p in stem.split("-")[1:])
    return f"{ticker} — {rest}" if rest else ticker


def content_hash(title: str, body: str) -> str:
    return hashlib.sha256(f"{title}\n{body}".encode()).hexdigest()[:16]


def gh(*args) -> subprocess.CompletedProcess:
    return subprocess.run(["gh", *args], capture_output=True, text=True)


def find_issue(title: str) -> int | None:
    r = gh("issue", "list", "--state", "open",
           "--search", title, "--json", "title,number", "--limit", "30")
    if r.returncode != 0:
        return None
    for issue in json.loads(r.stdout or "[]"):
        if issue["title"] == title:
            return issue["number"]
    return None


def get_issue_body(number: int) -> str:
    r = gh("issue", "view", str(number), "--json", "body")
    if r.returncode != 0:
        return ""
    return (json.loads(r.stdout or "{}") or {}).get("body", "") or ""


def merge_manual(new_body: str, existing_body: str) -> str:
    """Preserve everything below <!-- MANUAL --> from the existing issue body."""
    if MANUAL_SEP in existing_body:
        manual_section = existing_body.split(MANUAL_SEP, 1)[1]
        return f"{new_body}\n\n{MANUAL_SEP}{manual_section}"
    return new_body


def main():
    dry_run = "--dry-run" in sys.argv
    hashes  = load_hashes()

    idea_files = sorted(
        f for f in IDEAS_DIR.glob("*.md")
        if f.name not in SKIP_FILES
    )
    if not idea_files:
        print("No idea files found in ideas/")
        return

    created = updated = skipped = errors = 0
    new_hashes = dict(hashes)

    for path in idea_files:
        title = extract_title(path)
        body  = path.read_text(encoding="utf-8")
        h     = content_hash(title, body)

        if hashes.get(title) == h:
            skipped += 1
            continue

        if dry_run:
            action = "UPDATE" if find_issue(title) else "CREATE"
            print(f"  [DRY RUN] {action}: {title}")
            continue

        existing_num = find_issue(title)
        if existing_num:
            existing_body = get_issue_body(existing_num)
            merged = merge_manual(body, existing_body)
            r = gh("issue", "edit", str(existing_num), "--title", title, "--body", merged)
            if r.returncode == 0:
                print(f"  ✅ Updated #{existing_num}: {title}")
                new_hashes[title] = h
                updated += 1
            else:
                print(f"  ❌ Failed to update #{existing_num}: {r.stderr.strip()}")
                errors += 1
        else:
            r = gh("issue", "create", "--title", title, "--body", body)
            if r.returncode == 0:
                num = r.stdout.strip().rstrip("/").split("/")[-1]
                print(f"  ✅ Created #{num}: {title}")
                new_hashes[title] = h
                created += 1
            else:
                print(f"  ❌ Failed to create '{title}': {r.stderr.strip()}")
                errors += 1

    if not dry_run:
        save_hashes(new_hashes)
        print(f"\nDone: {created} created · {updated} updated · {skipped} skipped · {errors} errors")


if __name__ == "__main__":
    main()
