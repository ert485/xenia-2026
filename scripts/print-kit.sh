#!/usr/bin/env bash
# Usage: scripts/print-kit.sh
# Writes the QR code for the kit site (team-kit/print/qr.png and qr.svg, committed) and, when Google
# Chrome is installed, PDFs of the join flyer, the sign-up sheet, and the about-me card from the
# built site (generated, gitignored). PYTHON and CHROME override the binaries.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
cd "$KIT_ROOT"

url=https://26.cohack.tetl.ca
py="${PYTHON:-.venv/bin/python}"
[[ -x "$py" ]] || die "no python at $py (make tools creates .venv with segno)"
mkdir -p team-kit/print
"$py" -m segno --scale 12 --output team-kit/print/qr.png "$url"
"$py" -m segno --scale 12 --output team-kit/print/qr.svg "$url"
log "wrote team-kit/print/qr.png and qr.svg for $url"

pages="11-join-flyer 09-team-signup-sheet 01-about-me"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [[ -x "$chrome" ]]; then
  [[ -d site/dist/team-kit ]] || scripts/build-site.sh
  for page in $pages; do
    "$chrome" --headless=new --disable-gpu --no-pdf-header-footer \
      --print-to-pdf="team-kit/print/$page.pdf" "file://$PWD/site/dist/team-kit/$page/index.html"
  done
  log "wrote team-kit/print/{$(echo "$pages" | tr ' ' ',')}.pdf"
else
  echo "Chrome not found at $chrome. Print these pages to PDF from a browser instead:"
  for page in $pages; do echo "  $url/team-kit/$page/"; done
fi
