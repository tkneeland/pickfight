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
own() { HIVE_ACCOUNT=$1 bash -c '. "$1/hive-env.sh" || exit 1; echo "$FIVE_H_STOP_USED $MIN_WEEKLY_REMAINING_FOR_TICKETS"' _ "$AG"; }

# no studio file: account conf, then _shared.conf, then 0
check "peer from conf" "$(lim bob)" "80 30"
check "peer from shared" "$(lim carol)" "90 0"
check "own from conf" "$(own bob)" "80 30"
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
check "own from studio" "$(own bob)" "60 25"
check "own partial studio" "$(own carol)" "90 10"
# STUDIO_REPO empty: the studio cache is not read
sed -i.bak 's/^STUDIO_REPO=.*/STUDIO_REPO=/' "$T/repo/hive.conf"
check "no STUDIO_REPO: conf only" "$(own bob)" "80 30"
sed -i.bak 's/^STUDIO_REPO=.*/STUDIO_REPO=example\/studio/' "$T/repo/hive.conf"

# auto_file: studio wins (0|1 only), else the conf (alice has none -> 0); own AUTO_FILE follows; hive.sh limits prints all three
printf '\n%s\n' "AUTO_FILE=1" >> "$AG/accounts/carol.conf"
auto() { HIVE_ACCOUNT=${2:-alice} bash -c '. "$1/hive-env.sh" || exit 1; hive_limits "$2"; echo "$l_auto"' _ "$AG" "$1"; }
ownauto() { HIVE_ACCOUNT=$1 bash -c '. "$1/hive-env.sh" || exit 1; echo "$AUTO_FILE"' _ "$AG"; }
check "auto_file from conf" "$(auto carol)" "1"
check "auto_file default 0" "$(auto bob)" "0"
printf '%s\n' "bob five_h=60 weekly=75 auto_file=1" "carol weekly=90 auto_file=0" "alice auto_file=7" > "$T/studio/account-limits.conf"
check "auto_file from studio" "$(auto bob)" "1"
check "studio auto_file=0 beats conf 1" "$(auto carol)" "0"
check "bad auto_file ignored" "$(auto alice bob)" "0"
check "own AUTO_FILE from studio" "$(ownauto bob)" "1"
check "own AUTO_FILE studio 0" "$(ownauto carol)" "0"
check "hive.sh limits" "$(HIVE_ACCOUNT=alice bash "$AG/hive.sh" limits bob carol)" "bob five_h_stop=60 weekly_stop=75 auto_file=1
carol five_h_stop=90 weekly_stop=90 auto_file=0"
check "hive.sh limits default: self" "$(HIVE_ACCOUNT=alice bash "$AG/hive.sh" limits)" "alice five_h_stop=90 weekly_stop=100 auto_file=0"

# "*": the studio default for everyone, under each handle's own line
printf '%s\n' "* five_h=95 weekly=90 auto_file=1" "bob five_h=60" "carol auto_file=0" > "$T/studio/account-limits.conf"
check "studio default for a peer" "$(lim dave)" "95 10"
check "own line beats default, rest from default" "$(lim bob)" "60 10"
check "own auto_file=0 beats default 1" "$(auto carol)" "0"
check "default auto_file" "$(auto bob)" "1"
check "own from studio default" "$(own alice)" "95 10"
check "own AUTO_FILE from studio default" "$(ownauto alice)" "1"

# hive_weekly_capped <used7> <reset epoch> <min remaining>
cap() { HIVE_ACCOUNT=alice bash -c '. "$1/hive-env.sh" || exit 1; hive_weekly_capped "$2" "$3" "$4" && echo capped || echo ok' _ "$AG" "$@"; }
now=$(date +%s)
check "under limit" "$(cap 69 $((now + 3 * 86400)) 30)" "ok"
check "at limit, reset far" "$(cap 70 $((now + 3 * 86400)) 30)" "capped"
check "at limit, last 24h" "$(cap 95 $((now + 20 * 3600)) 30)" "ok"
check "unknown used" "$(cap '' $((now + 3 * 86400)) 30)" "ok"
check "unknown reset" "$(cap 70 0 30)" "capped"
check "limit 0, 100 used" "$(cap 100 $((now + 3 * 86400)) 0)" "capped"

# hive_weekly_stopped <used7> <reset epoch> <min remaining>: the weekly stop, plus 100% as a hard stop even in the grace window
stp() { HIVE_ACCOUNT=alice bash -c '. "$1/hive-env.sh" || exit 1; hive_weekly_stopped "$2" "$3" "$4" && echo stop || echo ok' _ "$AG" "$@"; }
check "stopped: under the stop" "$(stp 69 $((now + 3 * 86400)) 30)" "ok"
check "stopped: at the stop" "$(stp 70 $((now + 3 * 86400)) 30)" "stop"
check "stopped: at the stop, last 24h" "$(stp 95 $((now + 20 * 3600)) 30)" "ok"
check "stopped: 100% in the last 24h" "$(stp 100 $((now + 20 * 3600)) 30)" "stop"
check "stopped: 100% with no stop set" "$(stp 100 $((now + 20 * 3600)) 0)" "stop"
check "stopped: 99% with no stop set" "$(stp 99 $((now + 3 * 86400)) 0)" "ok"
check "stopped: 100% after the reset" "$(stp 100 $((now - 60)) 0)" "ok"

# hive/settings.conf: the studio-wide settings replace the conf values; bad or out-of-range values and unknown keys are ignored
set_() { HIVE_ACCOUNT=alice bash -c '. "$1/hive-env.sh" || exit 1; echo "$RESET_GRACE_HOURS $MAX_WORKERS $BEACON_FRESH_HOURS $PEER_QUEUE_MIN"' _ "$AG"; }
check "settings: defaults without the file" "$(set_)" "24 3 6 5"
printf '%s\r\n' "# studio settings" "reset_spend_hours=12" " offline_hours = 3 # comment" "max_workers=5" "ready_ticket_min=0" > "$T/studio/settings.conf"
check "settings: every key (CRLF, spaces, comments); max_workers is per account, not here" "$(set_)" "12 3 3 0"
printf '%s\n' "reset_spend_hours=73" "max_workers=7" "offline_hours=0" "ready_ticket_min=51" > "$T/studio/settings.conf"
check "settings: out of range ignored" "$(set_)" "24 3 6 5"
printf '%s\n' "reset_spend_hours=-1" "max_workers=two" "offline_hours=" "ready_ticket_min=4.5" "bogus" > "$T/studio/settings.conf"
check "settings: not numbers ignored" "$(set_)" "24 3 6 5"
printf '%s\n' "reset_spend_hours=0" "offline_hours=48" "ready_ticket_min=50" > "$T/studio/settings.conf"
check "settings: range edges" "$(set_)" "0 3 48 50"
printf '\n%s\n' "MAX_WORKERS=2" "RESET_GRACE_HOURS=10" >> "$AG/accounts/alice.conf"
check "settings: the studio wins over the account conf" "$(set_)" "0 2 48 50"
: > "$T/studio/settings.conf"
check "settings: empty file, the confs" "$(set_)" "10 2 6 5"
# max_workers: the account's own line in account-limits.conf, then its "*" line, then the conf; 1-6 only
cp "$T/studio/account-limits.conf" "$T/al.bak" 2>/dev/null || : > "$T/al.bak"
printf '%s\n' "* max_workers=4" > "$T/studio/account-limits.conf"
check "max_workers: the studio default line" "$(set_)" "10 4 6 5"
printf '%s\n' "* max_workers=4" "alice five_h=90 max_workers=1" > "$T/studio/account-limits.conf"
check "max_workers: the account's own line wins" "$(set_)" "10 1 6 5"
printf '%s\n' "* max_workers=7" "alice max_workers=0" > "$T/studio/account-limits.conf"
check "max_workers: out of range, the conf" "$(set_)" "10 2 6 5"
printf '%s\n' "* max_workers=4" > "$T/studio/account-limits.conf"
printf '%s\n' "max_workers=4" > "$T/studio/settings.conf"
sed -i.bak 's/^STUDIO_REPO=.*/STUDIO_REPO=/' "$T/repo/hive.conf"
check "settings: no STUDIO_REPO, the confs" "$(set_)" "10 2 6 5"
sed -i.bak 's/^STUDIO_REPO=.*/STUDIO_REPO=example\/studio/' "$T/repo/hive.conf"
check "max_workers: back with STUDIO_REPO" "$(set_)" "10 4 6 5"
check "max_workers: hive-pace.sh max follows" "$(HIVE_ACCOUNT=alice HIVE_STATE_DIR=$T/state bash "$AG/hive-pace.sh" max)" 4
cp "$T/al.bak" "$T/studio/account-limits.conf"
rm -f "$T/studio/settings.conf"

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
check "settings.conf is synced too" "$([ -e "$T/studio/settings.conf" ] && echo yes || echo no)" yes

echo "account-limits: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
