#!/usr/bin/env python3
"""Apply a batch of translations to Localizable.xcstrings.

Batch format (a module exposing TRANSLATIONS and optionally FIXES):

    TRANSLATIONS = { "<source key>": {"hu": "...", "fr": "...", ...}, ... }
    FIXES        = { "<source key>": {"hu": "...", ...}, ... }   # overwrites existing values

TRANSLATIONS refuses to overwrite an existing value (that's what FIXES is for), so re-running a
batch is safe and a typo'd key is reported rather than silently creating a dead entry.
"""
import importlib.util
import json
import sys
from pathlib import Path

CATALOG = Path("Localizable.xcstrings")
LANGS = ("hu", "fr", "ja", "zh-Hans", "zh-HK", "tr")


def localization(text):
    """A batch value is either a plain string, or a dict for a language that inflects by count:
    {"one": …, "other": …} for one counted argument, or {"_raw": {…}} to pass a localization
    object through verbatim (used for two-count strings, which need `substitutions`)."""
    if isinstance(text, str):
        return {"stringUnit": {"state": "translated", "value": text}}
    if "_raw" in text:
        return text["_raw"]
    return {"variations": {"plural": {
        cat: {"stringUnit": {"state": "translated", "value": v}}
        for cat, v in text.items()
    }}}


def reject_duplicate_keys(path: Path) -> None:
    """A dict literal with the same key twice keeps only the last one — silently. Grouping a batch
    by language makes that easy to do (one key touched from two sections) and impossible to see:
    the applied count still looks right because the duplicates are gone before it's taken. So parse
    the source and refuse to run rather than trust the dict."""
    import ast
    from collections import Counter

    tree = ast.parse(path.read_text())
    problems = []
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name)
                and node.targets[0].id in ("TRANSLATIONS", "FIXES")
                and isinstance(node.value, ast.Dict)):
            continue
        keys = [k.value for k in node.value.keys if isinstance(k, ast.Constant)]
        for key, n in Counter(keys).items():
            if n > 1:
                problems.append(f"{node.targets[0].id}: {key!r} appears {n}×")
    if problems:
        raise SystemExit("Duplicate keys — merge them into one entry:\n  "
                         + "\n  ".join(problems))


def load(path: Path):
    reject_duplicate_keys(path)
    spec = importlib.util.spec_from_file_location("batch", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, "TRANSLATIONS", {}), getattr(mod, "FIXES", {})


def main() -> int:
    translations, fixes = load(Path(sys.argv[1]))
    cat = json.loads(CATALOG.read_text())
    S = cat["strings"]

    unknown, collisions, added, changed = [], [], 0, 0

    for key, values in translations.items():
        if key not in S:
            unknown.append(key)
            continue
        loc = S[key].setdefault("localizations", {})
        for lang, text in values.items():
            if lang not in LANGS:
                unknown.append(f"{key} -> bad language {lang!r}")
                continue
            if lang in loc:
                collisions.append(f"{key} [{lang}]")
                continue
            loc[lang] = localization(text)
            added += 1

    for key, values in fixes.items():
        if key not in S:
            unknown.append(key)
            continue
        loc = S[key].setdefault("localizations", {})
        for lang, text in values.items():
            new = localization(text)
            if loc.get(lang) == new:
                continue
            loc[lang] = new
            changed += 1

    print(f"translations added : {added}")
    print(f"existing fixed     : {changed}")
    if collisions:
        print(f"SKIPPED (already had a value; use FIXES): {len(collisions)}")
        for c in collisions[:10]:
            print("   ", c)
    if unknown:
        print(f"UNKNOWN KEYS ({len(unknown)}) — nothing written:")
        for k in unknown:
            print("   ", repr(k))
        return 1

    # Preserve key order; Xcode re-sorts on its next save.
    CATALOG.write_text(json.dumps(cat, indent=2, ensure_ascii=False, separators=(",", " : ")) + "\n")
    print("written:", CATALOG)
    return 0


if __name__ == "__main__":
    sys.exit(main())
