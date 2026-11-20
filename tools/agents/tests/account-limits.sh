#!/bin/bash
# Offline test for the per-account ticket limits (hive-env.sh hive_limits, hive_weekly_capped): the hub's studio file
# (hive/account-limits.conf in STUDIO_REPO, cached in HIVE_STUDIO_CACHE) wins over the account conf, for this account and
# for peers; bad values are ignored; the weekly limit is ignored inside RESET_GRACE_HOURS; hive_studio_sync caches the
# file and keeps the last copy when GitHub fails. Stub gh. No network.   bash tools/agents/tests/account-limits.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-limits-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
hive_fixture "$T" "STUDIO_REPO=example/studio" || exit 1
mkdir -p "$T/bin" "$T/state" "$T/studio"
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state HIVE_STUDIO_CACHE=$T/studio
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
printf '\n%s\n' "MIN_WEEKLY_REMAINING_FOR_TICKETS=30" "FIVE_H_STOP_USED=80" >> "$AG/accounts/bob.conf"
lim() { HIVE_ACCOUNT=${2:-alice} bash -c '. "$1/hive-env.sh" || exit 1; hive_limits "$2"; echo "$l_5h $l_wmin"' _ "$AG" "$1"; }
own() { HIVE_ACCOUNT=$1 bash -c '. "$1/hive-env.sh" || exit 1; echo "$FIVE_H_STOP_USED $MIN_WEEKLY_REMAINING_FOR_TICKETS $FIVE_H_SLOW_USED"' _ "$AG"; }

# no studio file: account conf, then _shared.conf, then 0
check "peer from conf" "$(lim bob)" "80 30"
check "peer from shared" "$(lim carol)" "90 0"
check "own from conf" "$(own bob)" "80 30 70"
# studio file wins; weekly=W means W% used, i.e. min remaining 100-W; one key alone leaves the other to the conf
cat > "$T/studio/account-limits.conf" <<'EOF'
# comment
bob five_h=60 weekly=75
carol weekly=90
alice five_h=abc weekly=0
EOF
check "peer from studio" "$(lim bob)" "60 25"
check "peer partial studio" "$(lim carol)" "90 10"
check "bad studio values ignored" "$(lim alice bob)" "90 0"
check "own from studio, slow pulled under stop" "$(own bob)" "60 25 60"
check "own partial studio" "$(own carol)" "90 10 70"
# STUDIO_REPO empty: the studio cache is not read
sed -i.bak 's/^STUDIO_REPO=.*/STUDIO_REPO=/' "$T/repo/hive.conf"
check "no STUDIO_REPO: conf only" "$(own bob)" "80 30 70"
sed -i.bak 's/^STUDIO_REPO=.*/STUDIO_REPO=example\/studio/' "$T/repo/hive.conf"

# hive_weekly_capped <used7> <reset epoch> <min remaining>
cap() { HIVE_ACCOUNT=alice bash -c '. "$1/hive-env.sh" || exit 1; hive_weekly_capped "$2" "$3" "$4" && echo capped || echo ok' _ "$AG" "$@"; }
now=$(date +%s)
check "under limit" "$(cap 69 $((now + 3 * 86400)) 30)" "ok"
check "at limit, reset far" "$(cap 70 $((now + 3 * 86400)) 30)" "capped"
check "at limit, last 24h" "$(cap 95 $((now + 20 * 3600)) 30)" "ok"
check "unknown used" "$(cap '' $((now + 3 * 86400)) 30)" "ok"
check "unknown reset" "$(cap 70 0 30)" "capped"
check "limit 0, 100 used" "$(cap 100 $((now + 3 * 86400)) 0)" "capped"

# hive_studio_sync: caches the file, keeps the last copy when gh fails, caches empty on 404, and waits 5 min between fetches
sync() { HIVE_ACCOUNT=alice bash -c '. "$1/hive-env.sh" || exit 1; hive_studio_sync' _ "$AG"; }
rm -f "$T/studio/"*
printf '#!/bin/bash\necho "bob five_h=50"\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
sync; check "sync writes the cache" "$(cat "$T/studio/account-limits.conf")" "bob five_h=50"
printf '#!/bin/bash\necho "bob five_h=40"\n' > "$T/bin/gh"
sync; check "sync waits 5 min" "$(cat "$T/studio/account-limits.conf")" "bob five_h=50"
rm -f "$T/studio/.synced-at"; printf '#!/bin/bash\necho "error connecting to api.github.com" >&2; exit 1\n' > "$T/bin/gh"
sync; check "failed fetch keeps the last copy" "$(cat "$T/studio/account-limits.conf")" "bob five_h=50"
rm -f "$T/studio/.synced-at"; printf '#!/bin/bash\necho "gh: Not Found (HTTP 404)" >&2; exit 1\n' > "$T/bin/gh"
sync; check "404 caches empty" "$(cat "$T/studio/account-limits.conf")" ""

echo "account-limits: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
