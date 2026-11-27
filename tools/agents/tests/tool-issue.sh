#!/bin/bash
# Offline tests for hive-tool-issue.sh: files once, a repeat title prints the existing issue and files nothing, PRIVATE=1
# refuses, a missing from-field label files without it. gh is a stub first on PATH that records calls; nothing is filed.
#   bash tools/agents/tests/tool-issue.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-tool-issue-test.XXXXXX") && [ -d "$T" ] || { echo "tool-issue: no scratch dir" >&2; exit 1; }
T=$(cd "$T" && pwd) && case $T in */hive-tool-issue-test.*) ;; *) echo "tool-issue: odd scratch dir" >&2; exit 1;; esac
trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
echo "gh $*" | tr "\n" " " >> "$HIVE_TEST_LOG"; echo >> "$HIVE_TEST_LOG"
case "$1 $2" in
  "issue list") [ -f "$HIVE_TEST_FILED" ] && echo "#7 OPEN $(cat "$HIVE_TEST_FILED") https://example.test/7";;
  "label list") [ "${HIVE_TEST_LABEL:-1}" = 1 ] && echo from-field;;
  "issue create") while [ $# -gt 0 ]; do [ "$1" = --title ] && echo "$2" > "$HIVE_TEST_FILED"; shift; done; echo https://example.test/7;;
esac
exit 0
STUB
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state HIVE_TEST_LOG=$T/calls.log HIVE_TEST_FILED=$T/filed.txt HIVE_ACCOUNT=carol
[ "$(command -v gh)" = "$T/bin/gh" ] || { echo "tool-issue: stub gh not first on PATH" >&2; exit 1; }
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
run() { bash "$AG/hive-tool-issue.sh" "$@"; }
creates() { grep -c '^gh issue create' "$HIVE_TEST_LOG" 2>/dev/null; }
out=$(run "setup misses the widget step" "evidence: log line" 2>&1); rc=$?
check "first run exit" $rc 0
check "first run files once" "$(creates)" 1
case $out in *"filed: https://example.test/7"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL first run output: $out";; esac
c=$(grep '^gh issue create' "$HIVE_TEST_LOG")
case $c in *"-R tkneeland/claude-hive"*"--label from-field"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL create args: $c";; esac
case $c in *"example/project"*"carol"*"evidence: log line"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL body lacks project/account/evidence: $c";; esac
out=$(run "setup misses the widget step" "again" 2>&1); rc=$?
check "repeat exit" $rc 0
check "repeat files nothing more" "$(creates)" 1
case $out in *"https://example.test/7"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL repeat output: $out";; esac
grep -q 'issue list -R tkneeland/claude-hive -s all' "$HIVE_TEST_LOG" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL dupe check must search open and closed"; }
# missing label: file without it, print a note, create no label
rm -f "$HIVE_TEST_FILED" "$HIVE_TEST_LOG"
out=$(HIVE_TEST_LABEL=0 run "another gap" "e" 2>&1); rc=$?
check "no-label exit" $rc 0
check "no-label files" "$(creates)" 1
grep '^gh issue create' "$HIVE_TEST_LOG" | grep -q -- '--label' && { fail=$((fail+1)); echo "FAIL label passed though missing"; } || pass=$((pass+1))
grep -q '^gh label create' "$HIVE_TEST_LOG" && { fail=$((fail+1)); echo "FAIL created a label"; } || pass=$((pass+1))
case $out in *"from-field"*"not created"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL no note: $out";; esac
# PRIVATE refuses, touches nothing
rm -f "$HIVE_TEST_FILED" "$HIVE_TEST_LOG"; echo "PRIVATE=1" >> "$HIVE_CONF"
out=$(run "private gap" "e" 2>&1); rc=$?
check "private exit" $rc 2
check "private makes no gh call" "$(cat "$HIVE_TEST_LOG" 2>/dev/null | grep -c '^gh issue')" 0
case $out in *PRIVATE*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL private message: $out";; esac
echo "tool-issue: $pass passed, $fail failed"; [ $fail -eq 0 ]
