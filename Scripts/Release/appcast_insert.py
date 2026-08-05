#!/usr/bin/env python3
"""Insert one <item> at the top of appcast.xml, or validate the feed.

    appcast_insert.py appcast.xml --check-only
    appcast_insert.py appcast.xml --max-version
    appcast_insert.py appcast.xml --in-place --short 1.4.0 --build 19 ...

The insert is a text splice, not an XML re-serialisation: `ElementTree` would
rewrite the whole file (attribute order, self-closing tags, indentation) and turn
every release into an unreviewable diff. We parse only to *validate* — before and
after — and let the bytes of the existing items through untouched.

Stdlib only, like the rest of Scripts/.
"""

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
NS = {"sparkle": SPARKLE_NS}

# Matches the existing 1.2.5 item: an empty element, not self-closing.
CRITICAL_LINE = "            <sparkle:criticalUpdate></sparkle:criticalUpdate>\n"

TEMPLATE = """\
        <item>
            <title>{short}</title>
            <pubDate>{pubdate}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{short}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{minos}</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>
                {notes_url}
            </sparkle:releaseNotesLink>
{critical}\
            <enclosure url="{url}" length="{length}" type="application/octet-stream"\
 sparkle:edSignature="{sig}"/>
        </item>
"""

# Sparkle Ed25519 signatures are 64 raw bytes -> 86 base64 chars plus "==".
SIG_RE = re.compile(r"[A-Za-z0-9+/]{86}==")
# RFC 822, as emitted by `LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z"`.
PUBDATE_RE = re.compile(
    r"[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} [+-]\d{4}"
)


def fail(msg):
    sys.exit(f"appcast: {msg}")


def channel(text):
    """Parse and return the single <channel>, rejecting anything unexpected."""
    try:
        root = ET.fromstring(text)
    except ET.ParseError as exc:
        fail(f"not well-formed XML: {exc}")

    channels = root.findall("channel")
    if len(channels) != 1:
        fail(f"expected exactly 1 <channel>, found {len(channels)}")

    titles = channels[0].findall("title")
    if len(titles) != 1:
        fail(
            f"<channel> has {len(titles)} <title> elements, expected 1 — "
            "delete the duplicate <title>Applite</title> in appcast.xml"
        )
    return channels[0]


def item_versions(text):
    """Validate item ordering/uniqueness and return build numbers, newest first."""
    items = channel(text).findall("item")
    if not items:
        fail("feed has no <item> elements")

    versions = []
    for item in items:
        raw = item.findtext("sparkle:version", namespaces=NS)
        short = item.findtext("sparkle:shortVersionString", namespaces=NS) or "?"
        if raw is None:
            fail(f"item {short} has no <sparkle:version>")
        try:
            versions.append(int(raw.strip()))
        except ValueError:
            fail(f"item {short} has a non-numeric <sparkle:version>: {raw!r}")

    if len(set(versions)) != len(versions):
        fail(f"duplicate sparkle:version values in the feed: {versions}")
    if versions != sorted(versions, reverse=True):
        fail(f"items are not ordered newest-first: {versions}")
    return versions


def short_versions(text):
    return [
        (i.findtext("sparkle:shortVersionString", namespaces=NS) or "").strip()
        for i in channel(text).findall("item")
    ]


ITEM_RE = re.compile(r"^[ \t]*<item>.*?^[ \t]*</item>[ \t]*\r?\n", re.S | re.M)


def drop_item(text, short):
    """Remove the <item> for `short`, returning (new_text, was_present).

    A text splice again, so the surrounding items keep their exact bytes.
    """
    for match in ITEM_RE.finditer(text):
        if f"<sparkle:shortVersionString>{short}</sparkle:shortVersionString>" in match.group(0):
            return text[: match.start()] + text[match.end():], True
    return text, False


def validate_new_item(args, text, published, replacing):
    build = int(args.build)
    # When replacing, the item being replaced is not competition for itself.
    others = [v for v in published if v != build] if replacing else published
    if others and build <= max(others):
        fail(f"build {build} must be greater than the published maximum {max(others)}")
    if not replacing and args.short in short_versions(text):
        fail(f"version {args.short} is already in the feed "
             "(pass --replace-existing to rewrite it)")
    if not SIG_RE.fullmatch(args.sig or ""):
        fail(f"edSignature is not a Sparkle Ed25519 signature: {args.sig!r}")
    if not (args.length or "").isdigit():
        fail(f"length is not a number: {args.length!r}")
    if int(args.length) < 1_000_000:
        fail(f"implausible enclosure length ({args.length} bytes) — wrong file?")
    if not PUBDATE_RE.fullmatch(args.pubdate or ""):
        fail(
            f"pubDate is not RFC 822: {args.pubdate!r}\n"
            "        generate it with: LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z'"
        )
    if not re.fullmatch(r"\d+\.\d+(\.\d+)?", args.minos or ""):
        fail(f"minimumSystemVersion looks wrong: {args.minos!r}")
    if not (args.notes_url or "").startswith("https://"):
        fail(f"release notes URL must be https: {args.notes_url!r}")
    if not (args.url or "").startswith("https://"):
        fail(f"enclosure URL must be https: {args.url!r}")
    return build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("appcast", type=Path)
    parser.add_argument("--check-only", action="store_true",
                        help="validate the feed and exit")
    parser.add_argument("--max-version", action="store_true",
                        help="print the highest published sparkle:version")
    parser.add_argument("--signature-of", metavar="SHORTVERSION",
                        help="print '<edSignature> <length>' for a published version")
    parser.add_argument("--list-versions", action="store_true",
                        help="print published shortVersionStrings, newest first")
    parser.add_argument("--in-place", action="store_true",
                        help="rewrite the file (default: print to stdout)")
    parser.add_argument("--critical", action="store_true",
                        help="mark the update critical")
    parser.add_argument("--replace-existing", action="store_true",
                        help="rewrite the item for this version if it is already present")
    for flag in ("short", "build", "minos", "notes-url", "url", "length", "sig", "pubdate"):
        parser.add_argument("--" + flag)
    args = parser.parse_args()

    text = args.appcast.read_text(encoding="utf-8")
    published = item_versions(text)  # the feed must be valid before we touch it

    if args.check_only:
        return
    if args.max_version:
        print(max(published))
        return
    if args.list_versions:
        print("\n".join(short_versions(text)))
        return
    if args.signature_of:
        for item in channel(text).findall("item"):
            short = (item.findtext("sparkle:shortVersionString", namespaces=NS) or "").strip()
            if short != args.signature_of:
                continue
            enc = item.find("enclosure")
            if enc is None:
                fail(f"item {short} has no <enclosure>")
            print(enc.get(f"{{{SPARKLE_NS}}}edSignature"), enc.get("length"))
            return
        fail(f"version {args.signature_of} is not in the feed")

    missing = [f for f in ("short", "build", "minos", "notes_url", "url", "length", "sig",
                           "pubdate") if not getattr(args, f)]
    if missing:
        fail("missing required options: " + ", ".join("--" + m.replace("_", "-")
                                                      for m in missing))

    replaced = False
    if args.replace_existing:
        text, replaced = drop_item(text, args.short)
        if replaced:
            published = item_versions(text) if "<item>" in text else []

    build = validate_new_item(args, text, published, replaced)

    item = TEMPLATE.format(
        short=args.short,
        build=build,
        minos=args.minos,
        notes_url=args.notes_url,
        url=args.url,
        length=args.length,
        sig=args.sig,
        pubdate=args.pubdate,
        critical=CRITICAL_LINE if args.critical else "",
    )

    # Insert above the newest item, or — if replacing left the feed empty —
    # just before </channel>.
    anchor = re.search(r"^[ \t]*<item>[ \t]*\r?\n", text, re.M) \
        or re.search(r"^[ \t]*</channel>", text, re.M)
    if not anchor:
        fail("could not find an insertion point")
    out = text[: anchor.start()] + item + text[anchor.start():]

    after = item_versions(out)  # and it must still be valid afterwards
    if after[0] != build or len(after) != len(published) + 1:
        fail("post-insert validation failed — the splice landed in the wrong place")

    if args.in_place:
        args.appcast.write_text(out, encoding="utf-8")
    else:
        sys.stdout.write(out)


if __name__ == "__main__":
    main()
