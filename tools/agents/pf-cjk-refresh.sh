#!/bin/bash
# Re-runs tools/subset_cjk_font.py when this branch changed translations/strings.csv against origin/main, and commits
# the refreshed art/fonts subsets. Without it, a new string with a CJK character missing from the bundled subset
# turns main red on cjk_subsets_cover_every_translated_character_849 (10-22, PR #888).
#   pf-cjk-refresh.sh [worktree]   default: current directory; pf-ship.sh calls it before pushing
# Keeps fontTools in a venv outside the repo ($PF_VENV, default $PF_STATE/pf-venv, else
# ${XDG_STATE_HOME:-~/.local/state}/pickfight/pf-venv). Works with a POSIX (bin/) or Windows (Scripts/) venv and
# python3, python or py -3. Exits 1 if the venv, the fontTools install or the subset run fails.
set -euo pipefail
cd "${1:-.}"
git diff --quiet origin/main...HEAD -- translations/strings.csv && exit 0
V=${PF_VENV:-${PF_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/pickfight}/pf-venv}
venv_python() {
  local p
  for p in "$V/bin/python3" "$V/bin/python" "$V/Scripts/python.exe" "$V/Scripts/python"; do
    [ -x "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}
VPY=$(venv_python || true)
if [ -z "$VPY" ] || ! "$VPY" -c 'import fontTools' 2>/dev/null; then
  PY=()
  for cand in python3 python "py -3"; do
    read -ra try <<<"$cand"
    if "${try[@]}" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then PY=("${try[@]}"); break; fi
  done
  [ ${#PY[@]} -gt 0 ] || { echo "CJK subset refresh: no working Python 3 (python3, python, py -3)"; exit 1; }
  mkdir -p "$(dirname "$V")"
  "${PY[@]}" -m venv "$V" || { echo "CJK subset refresh: could not create the venv at $V"; exit 1; }
  VPY=$(venv_python) || { echo "CJK subset refresh: the venv at $V has no python"; exit 1; }
  "$VPY" -m pip -q --disable-pip-version-check install fonttools || { echo "CJK subset refresh: pip install fonttools failed"; exit 1; }
fi
"$VPY" -I tools/subset_cjk_font.py >/dev/null || { echo "CJK subset refresh failed"; exit 1; }
git diff --quiet -- art/fonts && exit 0
git add art/fonts
git commit -qm "fix: refresh CJK font subsets for new strings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
echo "CJK subsets refreshed"
