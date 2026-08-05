#!/usr/bin/env python3
"""Turn the edited release-notes.md into an AppliteReleaseModel entry.

    notes_to_swift.py release-notes.md --version 1.4.0 --date 2026.08.05. [--critical]

The output is pasted into aerolite's

    Sources/App/PageModels/AppliteReleases/AppliteReleases.swift

so it has to match that file's conventions: bullets are rendered through
`#unsafeHTML(...)` in release.leaf, which means inline HTML is expected and every
bullet is emitted as a Swift raw string (`#"..."#`) because href attributes carry
double quotes. Sections that end up empty are omitted entirely — the
AppliteReleaseModel initialiser already defaults them to [].
"""

import argparse
import re
import sys
from pathlib import Path

# Markdown heading -> AppliteReleaseModel property, in the order the model
# declares them.
SECTIONS = [
    ("New Features", "newFeatures"),
    ("Improvements", "improvements"),
    ("Fixes", "fixes"),
    ("Known Issues", "knownIssues"),
]

DRAFT_SENTINEL = "APPLITE-RELEASE-NOTES-DRAFT"


def inline_html(text):
    """Markdown inlines -> the HTML the Leaf template expects."""
    # Strip trailing commit hashes first, while they are still backticked — they
    # belong on GitHub, not on the marketing page. "(Fixes #97)"-style issue
    # references are deliberately kept; 1.3.1's website notes had them.
    text = re.sub(r"\s*\(`[0-9a-f]{7,40}`\)\s*$", "", text)

    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return text.strip()


def parse(md):
    """Return {property: [bullet, ...]} for every non-empty section."""
    if DRAFT_SENTINEL in md:
        sys.exit(
            f"notes: {DRAFT_SENTINEL} is still present — the notes have not been "
            "finalised yet"
        )

    heading_to_prop = {h.lower(): p for h, p in SECTIONS}
    found = {}
    current = None

    for line in md.splitlines():
        heading = re.match(r"^\s{0,3}#{1,6}\s+(.+?)\s*$", line)
        if heading:
            current = heading_to_prop.get(heading.group(1).strip().lower())
            continue
        bullet = re.match(r"^\s{0,3}[-*+]\s+(.*)$", line)
        if bullet and current:
            body = inline_html(bullet.group(1))
            if body:
                found.setdefault(current, []).append(body)

    if not found:
        sys.exit("notes: no bullets found under any known heading — nothing to publish")
    return found


def swift_raw(text):
    """Emit a Swift raw string, widening the delimiter if the text contains one."""
    hashes = "#"
    while hashes + '"' in text or '"' + hashes in text:
        hashes += "#"
    return f'{hashes}"{text}"{hashes}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("notes", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--date", required=True, help='e.g. 2026.08.05.')
    parser.add_argument("--critical", action="store_true")
    args = parser.parse_args()

    sections = parse(args.notes.read_text(encoding="utf-8"))

    out = [
        "    // Paste into aerolite:",
        "    //   Sources/App/PageModels/AppliteReleases/AppliteReleases.swift",
        f'    "{args.version}": .init(',
        f'        versionString: "{args.version}",',
        f'        dateOfRelease: "{args.date}",',
    ]
    for _, prop in SECTIONS:
        bullets = sections.get(prop)
        if not bullets:
            continue
        out.append(f"        {prop}: [")
        out += [f"            {swift_raw(b)}," for b in bullets]
        out.append("        ],")
    if args.critical:
        out.append("        isCritical: true,")

    # Drop the trailing comma of the final argument.
    out[-1] = out[-1].rstrip(",")
    out.append("    ),")
    print("\n".join(out))


if __name__ == "__main__":
    main()
