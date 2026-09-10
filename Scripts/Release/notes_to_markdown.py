#!/usr/bin/env python3
"""Write website-notes.md into applite-site as a release-notes page.

    notes_to_markdown.py website-notes.md --version 1.4.3 --date 2026-10-01 \
        --out ~/GitHub/applite-site/src/content/releases

Replaces notes_to_swift.py, which emitted a Swift dictionary entry to paste into
the Vapor app that used to serve aerolite.dev. That app is gone; applite.app is a
static site whose release notes are markdown files in a content collection.

The conversion is mostly nothing, which is the point: website-notes.md already
uses the four headings and the bullet style the site renders. This adds
frontmatter, drops the instructional comments, and orders the sections. It does
not touch the prose.

The filename is the published URL. src/pages/releases/[version].astro fails the
build if a filename disagrees with its `version` frontmatter, so the two are
written from the same value here.
"""

import argparse
import re
import sys
from pathlib import Path

# Rendered in this order regardless of the order they were written in, so the
# archive reads consistently across versions.
SECTIONS = ["New Features", "Improvements", "Fixes", "Known Issues"]

DRAFT_SENTINEL = "APPLITE-RELEASE-NOTES-DRAFT"


def parse(md):
    """Split the notes into {heading: [bullets]}, keyed case-insensitively."""
    if DRAFT_SENTINEL in md:
        sys.exit(
            f"notes: {DRAFT_SENTINEL} is still present — the notes have not been "
            "written yet."
        )

    known = {h.lower(): h for h in SECTIONS}
    found = {}
    current = None

    for line in md.splitlines():
        heading = re.match(r"\s*#{1,6}\s+(.+?)\s*$", line)
        if heading:
            current = known.get(heading.group(1).lower())
            if current and current not in found:
                found[current] = []
            continue
        bullet = re.match(r"\s*[-*+]\s+(.+?)\s*$", line)
        if bullet and current:
            found[current].append(bullet.group(1))

    if not any(found.values()):
        sys.exit(
            "notes: no bullets found under any of "
            f"{', '.join(SECTIONS)} — nothing to publish."
        )
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("notes", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--date", required=True, help="ISO, e.g. 2026-10-01")
    parser.add_argument("--critical", action="store_true")
    parser.add_argument("--out", required=True, type=Path, help="content/releases dir")
    args = parser.parse_args()

    if not re.fullmatch(r"\d+(\.\d+)*", args.version):
        sys.exit(f"notes: version {args.version!r} must look like 1.4.3 or 1.2")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.date):
        sys.exit(f"notes: date {args.date!r} must be ISO, e.g. 2026-10-01")
    if not args.out.is_dir():
        sys.exit(f"notes: {args.out} is not a directory — is applite-site checked out?")

    sections = parse(args.notes.read_text(encoding="utf-8"))

    body = []
    for heading in SECTIONS:
        bullets = sections.get(heading)
        if not bullets:
            continue
        body.append(f"### {heading}\n")
        body.extend(f"- {b}" for b in bullets)
        body.append("")

    front = [
        "---",
        f'version: "{args.version}"',
        f"date: {args.date}",
    ]
    if args.critical:
        front.append("critical: true")
    front += ["---", ""]

    target = args.out / f"{args.version}.md"
    target.write_text("\n".join(front) + "\n".join(body).rstrip() + "\n", encoding="utf-8")
    print(target)


if __name__ == "__main__":
    main()
