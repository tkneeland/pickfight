#!/bin/bash
# Usage: hive-tool-issue.sh "<title>" "<body>"
# File a gap in the hive tooling itself (a script, a rule, a setup step) upstream in TOOL_REPO (hive.conf; default
# tkneeland/claude-hive), labelled from-field, with this project (REPO), account and your evidence in the body. Dupe-checks
# TOOL_REPO's open AND closed issues first (same gh search matching as hive-dupe-check.sh): on a hit it prints the
# existing issue and exits 0 without filing. A missing from-field label is never created: the issue is filed without it.
# Refused (exit 2) in PRIVATE mode: nothing about the hive may reach GitHub. Not subject to AUTO_FILE (hive.md rule 28).
[ $# -eq 2 ] && [ -n "$1" ] || { echo "usage: hive-tool-issue.sh \"<title>\" \"<body>\"" >&2; exit 2; }
. "$(dirname "$0")/hive-env.sh" || exit 2
if [ "$PRIVATE" = 1 ]; then
  echo "hive-tool-issue: refused: PRIVATE=1, so nothing about the hive may go to GitHub. Tell your human about the tooling gap instead." >&2; exit 2
fi
: "${TOOL_REPO:=tkneeland/claude-hive}"
hits=$(gh issue list -R "$TOOL_REPO" -s all --search "$1" -L 5 --json number,state,title,url -q '.[]|"#\(.number) \(.state) \(.title[0:80]) \(.url)"' 2>/dev/null)
if [ -n "$hits" ]; then
  echo "already filed in $TOOL_REPO, not filing again:"; echo "$hits"; exit 0
fi
args=(-R "$TOOL_REPO" --title "$1")
if gh label list -R "$TOOL_REPO" -L 200 --json name -q '.[].name' 2>/dev/null | grep -qx from-field; then args+=(--label from-field)
else echo "note: label from-field does not exist in $TOOL_REPO (not created); filing without it" >&2; fi
printf -v full 'Filed from the field by `hive-tool-issue.sh`.\n\n- Project: %s\n- Account: %s\n\n%s\n' "${REPO:-$PROJECT_NAME}" "$HIVE_ACCOUNT" "$2"
url=$(gh issue create "${args[@]}" --body "$full") || { echo "hive-tool-issue: gh issue create failed" >&2; exit 1; }
echo "filed: $url"
