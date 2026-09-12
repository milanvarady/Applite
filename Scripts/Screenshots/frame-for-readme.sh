#!/usr/bin/env bash
#
# Adds edge definition to raw window screenshots for use in the GitHub README.
#
# Raw `screencapture -w` output is cropped tight to the window with no shadow,
# which is a problem on GitHub: the light window chrome is #ffffff and so is
# GitHub's light background, so the window dissolves into the page. A plain drop
# shadow only fixes that case -- on GitHub's #0d1117 dark background a black
# shadow is invisible, so the dark variant gets a light hairline instead (which
# is what macOS dark-mode windows have anyway).
#
# Both effects are derived from the PNG's own alpha channel, so they follow the
# window's rounded corners exactly.
#
# The applite-site copies stay unframed on purpose -- the website applies its
# own shadow in CSS, and baking one in would double up.
#
# Usage: ./frame-for-readme.sh <light.png> <dark.png> <outdir>

set -euo pipefail

command -v magick >/dev/null || { echo "needs ImageMagick 7 (brew install imagemagick)" >&2; exit 1; }
[ $# -eq 3 ] || { sed -n '/^# Usage:/s/^# //p' "$0" >&2; exit 1; }

light=$1 dark=$2 outdir=$3
mkdir -p "$outdir"

pad=120                       # room for the shadow; keep > 3 * sigma or it clips
read -r w h < <(magick identify -format "%w %h\n" "$light")
canvas="$((w + 2 * pad))x$((h + 2 * pad))"

magick "$light" \
  \( +clone -background black -shadow 55x35+0+22 \) \
  +swap -background none -layers merge +repage \
  -gravity center -background none -extent "$canvas" \
  "$outdir/discover-light.png"

magick "$dark" \
  \( +clone -alpha extract -write mpr:mask +delete \) \
  \( mpr:mask -morphology erode octagon:2 -negate mpr:mask -compose multiply -composite \
     -background white -alpha shape -channel A -evaluate multiply 0.22 +channel \) \
  -compose over -composite \
  \( +clone -background black -shadow 45x35+0+22 \) \
  +swap -background none -layers merge +repage \
  -gravity center -background none -extent "$canvas" \
  "$outdir/discover-dark.png"

echo "wrote $outdir/discover-{light,dark}.png at $canvas"
