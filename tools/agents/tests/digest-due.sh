#!/bin/bash
# Offline test for the 9 AM digest wake (#1257): pf_digest_due and pf_digest_mark_sent from pf-triage-watch.sh, at fixed
# times in the account's TZ (America/New_York), in winter (EST) and summer (EDT). Scratch PF_STATE_DIR. No network.
# macOS, Linux and Git Bash.   bash tools/agents/tests/digest-due.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-digest-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state"
export PF_STATE_DIR=$T/state PF_ACCOUNT=tkneeland
. "$AG/pf-env.sh" || exit 1
. "$AG/pf-triage-watch.sh" --functions || exit 1
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
due() { pf_digest_due "$1" || echo none; }
# 2026-11-12 (EST, UTC-5): 13:59Z is 8:59 ET, 14:00Z is 9:00 ET; 04:59Z on 11-13 is 23:59 ET on 11-12
check "before 9 AM" "$(due 1794491940)" none
check "at 9 AM" "$(due 1794492000)" 2026-11-12
check "late evening, still unsent" "$(due 1794545940)" 2026-11-12
pf_digest_mark_sent "" 1794492000
check "marked sent" "$(due 1794492000)" none
check "marked sent, evening" "$(due 1794545940)" none
# the next day: before 9 AM nothing (yesterday's mark does not carry), from 9 AM it wakes again
check "next day, 00:01" "$(due 1794546060)" none
check "next day, 9 AM" "$(due $((1794492000 + 86400)))" 2026-11-13
# summer (EDT, UTC-4): 12:59Z is 8:59 ET, 13:00Z is 9:00 ET
check "summer before 9" "$(due 1782910740)" none
check "summer at 9" "$(due 1782910800)" 2026-07-01
# DIGEST_HOUR moves it; a Windows CRLF in the file still counts as marked
check "DIGEST_HOUR=10 at 9" "$(DIGEST_HOUR=10 due 1782910800)" none
printf '2026-07-01\r\n' > "$PF_STATE/digest-sent"
check "CRLF mark" "$(due 1782910800)" none
# #1259: marking after midnight marks the digest that fell due (yesterday's), so today's still wakes
rm -f "$PF_STATE/digest-sent"
check "due date at 00:01" "$(pf_digest_due_date 1794546060)" 2026-11-12
check "due date at 9 AM" "$(pf_digest_due_date 1794492000)" 2026-11-12
pf_digest_mark_sent "" 1794546060
check "marked after midnight" "$(cat "$PF_STATE/digest-sent")" 2026-11-12
check "today still wakes" "$(due $((1794492000 + 86400)))" 2026-11-13
# an explicit date; a malformed one is refused and changes nothing
pf_digest_mark_sent 2026-11-13
check "explicit date" "$(due $((1794492000 + 86400)))" none
pf_digest_mark_sent 13/11/2026 2>/dev/null; check "bad date exit" "$?" 2
check "bad date kept mark" "$(cat "$PF_STATE/digest-sent")" 2026-11-13
# a missing state folder is created
PF_STATE=$T/new/state pf_digest_mark_sent 2026-11-14 && check "mkdir state" "$(cat "$T/new/state/digest-sent")" 2026-11-14
# a non-numeric or out-of-range DIGEST_HOUR falls back to 9, with a warning
check "DIGEST_HOUR=abc" "$(DIGEST_HOUR=abc pf_digest_hour 2>/dev/null)" 9
check "DIGEST_HOUR=25" "$(DIGEST_HOUR=25 pf_digest_hour 2>/dev/null)" 9
check "DIGEST_HOUR=08" "$(DIGEST_HOUR=08 pf_digest_hour)" 8
check "warning" "$(DIGEST_HOUR=abc pf_digest_hour 2>&1 >/dev/null | grep -c 'not an hour')" 1
# the poll loop's wake: once, then not again until DIGEST_REWAKE_MIN has passed; never once marked
rm -f "$PF_STATE/digest-sent" "$PF_STATE/.digest-woke"
wake() { pf_digest_wake "$1" || echo none; }
check "wake at 9 AM" "$(wake 1794492000)" "DIGEST_DUE 2026-11-12"
check "no wake 5 min later" "$(wake $((1794492000 + 300)))" none
check "wake 30 min later" "$(wake $((1794492000 + 1800)))" "DIGEST_DUE 2026-11-12"
check "DIGEST_REWAKE_MIN=60" "$(DIGEST_REWAKE_MIN=60 wake $((1794492000 + 3000)))" none
pf_digest_mark_sent 2026-11-12
check "no wake once marked" "$(wake $((1794492000 + 7200)))" none
check "no wake before 9" "$(wake 1794491940)" none
echo "digest-due: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
