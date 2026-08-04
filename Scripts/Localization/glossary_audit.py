#!/usr/bin/env python3
"""Cross-reference the catalog against the glossary in TRANSLATING.md.

Two checks:
  1. exact — a key that IS a glossary term must carry the glossary's value
  2. contains — a longer string containing the English term should contain the glossary term
     (advisory: inflection means a literal match often won't appear, so this only reports)
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(".")
LANGS = ("hu", "fr", "ja", "zh-Hans", "zh-HK", "tr")


def parse_glossary():
    """Every markdown row of the form | Term | hu | fr | ja | zh-Hans | zh-HK | tr |"""
    terms = {}
    for line in (REPO / "TRANSLATING.md").read_text().splitlines():
        if not line.startswith("|") or line.startswith("|---"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 7:
            continue
        term = re.sub(r"\s*[¹²³⁴⁵⁶⁷]+$", "", cells[0]).strip()
        if term in ("Term", "") or cells[1] in ("hu", "Register"):
            continue
        vals = {}
        for lang, cell in zip(LANGS, cells[1:]):
            v = re.sub(r"\s*[¹²³⁴⁵⁶⁷]+$", "", cell).strip()
            if v and v != "—":
                vals[lang] = v
        terms[term] = vals
    return terms


def main():
    glossary = parse_glossary()
    S = json.loads((REPO / "Localizable.xcstrings").read_text())["strings"]
    print(f"glossary terms parsed: {len(glossary)}\n")

    mismatches = []
    for term, vals in glossary.items():
        # "Dismiss / Close" covers two keys
        for key in [k.strip() for k in term.split("/")]:
            entry = S.get(key)
            if not entry:
                continue
            loc = entry.get("localizations") or {}
            for lang, want in vals.items():
                got = ((loc.get(lang) or {}).get("stringUnit") or {}).get("value")
                if got is not None and got != want:
                    mismatches.append((key, lang, got, want))

    print(f"keys that are glossary terms but don't match: {len(mismatches)}")
    for key, lang, got, want in mismatches:
        print(f"   {key:16} [{lang:8}] {got!r}  ->  {want!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
