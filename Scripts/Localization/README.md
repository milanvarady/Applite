# Localization tooling

Four stdlib-only Python scripts for maintaining `Localizable.xcstrings`. Run them from the repo
root. None of them are part of the build; `Scripts/` sits outside the app target.

| Script | What it does |
|---|---|
| `sync_catalog.py <objdir>` | Merge the compiler's extracted keys + comments into the catalog |
| `apply_translations.py <batch.py>` | Apply a batch of translations or corrections |
| `glossary_audit.py` | Check the catalog against the glossary in `TRANSLATING.md` |
| `apple_terms.py <term>…` | Print how macOS itself renders a term, per language |

## Why `sync_catalog.py` exists

**`xcodebuild` never writes back to `Localizable.xcstrings`.** Only building inside Xcode updates
the catalog. Extraction still runs on the command line (`SWIFT_EMIT_LOC_STRINGS=YES`) — it just
leaves the result in `.stringsdata` files and stops there. So if you add or change a localized
literal and only ever build from the CLI, the catalog silently falls behind: new keys never appear,
and changed keys are never marked stale.

    xcodebuild -project Applite.xcodeproj -scheme Applite -configuration Debug \
        -destination 'platform=macOS' -derivedDataPath /tmp/dd build
    python3 Scripts/Localization/sync_catalog.py \
        /tmp/dd/Build/Intermediates.noindex/Applite.build/Debug/Applite.build/Objects-normal/arm64 \
        --apply

It adds new keys, refreshes comments from source, marks vanished keys `stale`, and **never touches
`localizations`** — translations are only ever changed by a translator. It preserves the file's key
order, because Xcode sorts with a locale-aware collation (punctuation first) that a naive sort does
not reproduce, and re-sorting churns the whole file.

## Batch format for `apply_translations.py`

```python
TRANSLATIONS = {"<source key>": {"hu": "…", "fr": "…"}}   # refuses to overwrite an existing value
FIXES        = {"<source key>": {"hu": "…"}}              # overwrites deliberately
```

A value may also be `{"one": …, "other": …}` for a language that inflects after a numeral, or
`{"_raw": {…}}` to pass a localization object through verbatim (two-count strings need
`substitutions`).

**It refuses to run if a key appears twice in one dict.** That is not hypothetical: a batch grouped
by language put the same key in two sections, Python kept only the last, and 15 corrections were
silently dropped while the applied count still looked right.

## `apple_terms.py`

macOS ships its own localizations as `.loctable` plists — one per string table, keyed by language.
This finds the keys whose `en` value matches your term exactly, reads those same keys back out of
`hu` / `fr` / `ja` / `zh_CN` / `zh_HK` / `tr`, and counts each rendering.

    python3 Scripts/Localization/apple_terms.py "Install" "Uninstall" "Advanced"

Frequency is evidence, not a verdict. The same English word is usually several UI concepts: `Note`
resolves to the Notes **app**, `Utilities` most often to Launchpad's "Other" grouping. Always read
the alternates before adopting the top hit — see the deviations section of `TRANSLATING.md`.
