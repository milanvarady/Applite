#!/usr/bin/env python3
"""How does macOS itself render a given English UI string?

Modern macOS keeps localizations in .loctable files — one plist per table, keyed by language, so a
single file holds every language's copy of the same keys. Find the keys whose "en" value matches,
then read those keys out of each target language. Falls back to .strings pairs for older bundles.
"""
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path

LANGS = {"hu": ["hu"], "fr": ["fr"], "ja": ["ja"],
         "zh-Hans": ["zh_CN", "zh-Hans"], "zh-HK": ["zh_HK", "zh-HK", "zh_TW"], "tr": ["tr"]}

ROOTS = [
    "/System/Library/Frameworks",
    "/System/Library/PrivateFrameworks",
    "/System/Applications",
    "/System/Library/CoreServices",
]


def load(path: Path):
    cp = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)],
                        capture_output=True, text=True)
    if cp.returncode != 0 or not cp.stdout.strip():
        return None
    try:
        return json.loads(cp.stdout)
    except json.JSONDecodeError:
        return None


def loctables():
    for root in ROOTS:
        yield from Path(root).rglob("*.loctable")


def main(targets):
    hits = {t: {lang: Counter() for lang in LANGS} for t in targets}
    scanned = 0
    for f in loctables():
        table = load(f)
        if not isinstance(table, dict) or "en" not in table:
            continue
        en = table["en"]
        if not isinstance(en, dict):
            continue
        scanned += 1
        for target in targets:
            keys = [k for k, v in en.items() if isinstance(v, str) and v == target]
            if not keys:
                continue
            for lang, codes in LANGS.items():
                for code in codes:
                    loc = table.get(code)
                    if not isinstance(loc, dict):
                        continue
                    for k in keys:
                        v = loc.get(k)
                        if isinstance(v, str) and v and v != target:
                            hits[target][lang][v] += 1
                    break
    print(f"(scanned {scanned} localization tables)\n")
    out = {}
    for target in targets:
        print(f"=== {target!r}")
        out[target] = {}
        for lang in LANGS:
            top = hits[target][lang].most_common(4)
            out[target][lang] = top
            print(f"  {lang:8}", ", ".join(f"{v}  ×{n}" for v, n in top) if top else "(not found)")
        print()
    Path("apple_terms.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print("saved: apple_terms.json")


if __name__ == "__main__":
    main(sys.argv[1:])
