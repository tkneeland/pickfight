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
pf_digest_mark_sent 1794492000
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
echo "digest-due: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
