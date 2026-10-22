#!/bin/bash
# Re-runs tools/subset_cjk_font.py when this branch changed translations/strings.csv against origin/main, and commits
# the refreshed art/fonts subsets. Without it, a new string with a CJK character missing from the bundled subset
# turns main red on cjk_subsets_cover_every_translated_character_849 (10-22, PR #888).
#   pf-cjk-refresh.sh [worktree]   default: current directory; pf-ship.sh calls it before pushing
# Keeps fontTools in a venv outside the repo ($PF_VENV, default $TMPDIR/pf-venv). Exits 1 if the subset run fails.
set -euo pipefail
cd "${1:-.}"
git diff --quiet origin/main...HEAD -- translations/strings.csv && exit 0
V=${PF_VENV:-${TMPDIR:-/tmp}/pf-venv}
[ -x "$V/bin/python3" ] && "$V/bin/python3" -c 'import fontTools' 2>/dev/null \
  || { python3 -m venv "$V" && "$V/bin/pip" -q install fonttools 2>&1 | grep -v -i "pip version\|upgrade" || true; }
"$V/bin/python3" -I tools/subset_cjk_font.py >/dev/null || { echo "CJK subset refresh failed"; exit 1; }
git diff --quiet -- art/fonts && exit 0
git add art/fonts
git commit -qm "fix: refresh CJK font subsets for new strings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
echo "CJK subsets refreshed"
