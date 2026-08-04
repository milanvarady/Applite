#!/usr/bin/env python3
"""Sync Localizable.xcstrings from the compiler's extracted .stringsdata.

Xcode updates the String Catalog only when you build inside the IDE; `xcodebuild` still runs
extraction (SWIFT_EMIT_LOC_STRINGS=YES) but writes the result to .stringsdata and never back to the
catalog. This reads those files — the authoritative key + comment for every localized literal — and
merges them in.

Never touches `localizations`: translations are only ever added or removed by a translator.
"""
import json
import plistlib
import subprocess
import sys
from pathlib import Path

REPO = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
OBJDIR = Path(sys.argv[2])
CATALOG = REPO / "Localizable.xcstrings"
APPLY = "--apply" in sys.argv


def extracted() -> dict[str, str | None]:
    """key -> comment, across every .stringsdata the Applite target produced.

    One key can be used at several call sites with different comments (e.g. "Error"); Xcode joins
    those with newlines into one comment, so we do the same rather than letting the last one win.
    """
    seen: dict[str, list[str]] = {}
    for f in sorted(OBJDIR.glob("*.stringsdata")):
        # The files vary between binary/XML plist and JSON; plutil normalizes all of them.
        cp = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(f)],
                            capture_output=True, text=True)
        if cp.returncode != 0 or not cp.stdout.strip():
            continue
        data = json.loads(cp.stdout)
        for entries in (data.get("tables") or {}).values():
            for e in entries:
                key = e.get("key")
                if key is None:
                    continue
                bucket = seen.setdefault(key, [])
                c = e.get("comment")
                if c and c not in bucket:
                    bucket.append(c)
    return {k: ("\n".join(v) if v else None) for k, v in seen.items()}


def main() -> int:
    live = extracted()
    cat = json.loads(CATALOG.read_text())
    S = cat["strings"]

    added, recomment, revived, staled = [], [], [], []

    for key, comment in sorted(live.items()):
        if key not in S:
            added.append(key)
        entry = S.setdefault(key, {})
        if entry.get("extractionState") == "stale":
            del entry["extractionState"]
            revived.append(key)
        existing = entry.get("comment")
        # Same set of lines in a different order isn't a change worth churning the file for.
        same = existing and set(existing.split("\n")) == set(comment.split("\n")) if comment else False
        if comment and not same and existing != comment:
            recomment.append((key, existing, comment))
            entry["comment"] = comment

    for key, entry in S.items():
        if key in live:
            continue
        # 'manual' entries are author-added and legitimately absent from source; leave them.
        if entry.get("extractionState") in (None,):
            entry["extractionState"] = "stale"
            staled.append(key)

    print(f"extracted from source : {len(live)}")
    print(f"catalog keys          : {len(S)}")
    print(f"  + added             : {len(added)}")
    print(f"  ~ comment set/changed: {len(recomment)}")
    print(f"  ^ revived from stale : {len(revived)}")
    print(f"  - newly marked stale : {len(staled)}")
    for k in added:
        print("   ADD  ", repr(k[:80]))
    for k in staled:
        print("   STALE", repr(k[:80]))

    if APPLY:
        # Preserve the file's existing key order: Xcode sorts with a locale-aware collation
        # (punctuation first), not codepoint order, so re-sorting here would churn the whole
        # file. New keys land at the end; Xcode normalizes the order on its next save.
        CATALOG.write_text(json.dumps(cat, indent=2, ensure_ascii=False, separators=(",", " : ")) + "\n")
        print("\nwritten:", CATALOG)
    else:
        print("\n(dry run — pass --apply to write)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
