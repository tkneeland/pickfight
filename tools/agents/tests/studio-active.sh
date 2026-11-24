#!/bin/bash
# Offline test for the hub's in/out switch and triagemaster queue (issue #58): the studio's hive/accounts-active.conf, cached
# in HIVE_STUDIO_CACHE, read by hive-env.sh (hive_is_out, hive_queue, hive_peers, hive_worker_target, hive_mt), the triage
# watcher (no MYTICKET or IDLE_SLOTS while out) and hive-succession.sh (first account in the file's order that is in and
# viable; down the list and back; the all-non-viable fallback, said once). Without the file, the same by SUCCESSION_RANK.
# Stub gh and curl, scratch state. No network.   bash tools/agents/tests/studio-active.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-studio-test.XXXXXX") || exit 1
hive_test_guard
hive_fixture "$T" "STUDIO_REPO=example/studio" || exit 1
mkdir -p "$T/bin" "$T/state" "$T/studio"
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "api --paginate repos/"*"/issues?"*) cat "$HIVE_TEST_ISSUES" 2>/dev/null || echo '[]';;
  "pr list"*) echo '[]';;
  *) exit 1;;
esac
STUB
printf '#!/bin/bash\ncat >/dev/null; exit 0\n' > "$T/bin/curl"
chmod +x "$T/bin/gh" "$T/bin/curl"; hive_stub_jq "$T/bin"
git init -q "$T/root"; git -C "$T/root" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state HIVE_STUDIO_CACHE=$T/studio REPO_PATH=$T/root HIVE_TEST_ISSUES=$T/issues.json
hive_require_stub "$T/bin" gh curl
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
env_do() { HIVE_ACCOUNT=$1 bash -c '. "$1/hive-env.sh" || exit 1; eval "$2"' _ "$AG" "$2"; }   # env_do <account> '<code>'
ACT=$T/studio/accounts-active.conf

# --- reading the file: comments, CRLF, spaces, unknown handles, the last value of a repeated handle, unlisted = in
printf '# header\r\ncarol=on\r\n  bob = off  # out for the day\nghost=on\n_shared=on\nalice=on\nbob=off\n' > "$ACT"
check "queue: file order, out and unknown skipped, unlisted by rank" "$(env_do alice 'hive_queue | tr "\n" " "')" "carol alice dave "
check "out" "$(env_do alice 'hive_is_out bob && echo out || echo in')" out
check "in" "$(env_do alice 'hive_is_out carol && echo out || echo in')" in
check "unlisted is in" "$(env_do alice 'hive_is_out dave && echo out || echo in')" in

# --- out: worker target 0, never a peer, MT label
check "out: worker target 0" "$(env_do bob 'hive_worker_target')" 0
check "in: worker target" "$(env_do alice 'hive_worker_target')" 3
echo "alice max_workers=2" > "$T/studio/account-limits.conf"
check "in: worker target is the account's hub max_workers" "$(env_do alice 'hive_worker_target')" 2
rm -f "$T/studio/account-limits.conf"
check "out: not a peer" "$(env_do alice 'hive_peers | tr "\n" " "')" "carol dave "
check "out: hive_mt" "$(env_do bob 'hive_mt && echo MT || echo AT')" MT
check "out: at-mode label" "$(HIVE_ACCOUNT=bob bash "$AG/hive-at-mode.sh")" MT
HIVE_ACCOUNT=bob bash "$AG/hive-at-mode.sh" AT >/dev/null 2>&1; check "studio: at-mode switch refused" "$?" 2
check "out: not the triagemaster" "$(echo bob > "$T/state/triagemaster"; env_do bob 'hive_is_triagemaster && echo yes || echo no')" no

# --- the watcher: out emits no MYTICKET and no IDLE_SLOTS; in does. A wake file ends the first poll so it never blocks.
watch() {   # watch <account>: the watcher's first line, after one poll and one 1 s tick
  rm -f "$T/state/.slots-last" "$T/state/.triage-seen"; echo 0 > "$T/state/.msg-wake-handled"
  echo "SENTINEL" > "$T/state/msg-wake.txt"; echo carol > "$T/state/triagemaster"
  HIVE_ACCOUNT=$1 HIVE_TICK=1 WATCH_INTERVAL=1 bash "$AG/hive-triage-watch.sh" 2>/dev/null | head -n 1
}
echo '[{"number":900,"labels":[{"name":"ready-for-agent"},{"name":"p2"}],"assignees":[{"login":"bob"}],"pull_request":null}]' > "$T/issues.json"
check "out: no MYTICKET" "$(watch bob)" SENTINEL
sed -i.bak 's/^bob=off/bob=on/; s/bob = off/bob=on/' "$ACT"
check "in: MYTICKET" "$(watch bob)" "MYTICKET 900"
echo '[]' > "$T/issues.json"
check "in: IDLE_SLOTS" "$(watch bob)" "IDLE_SLOTS 0/3 active work packages"
printf 'bob=off\n' > "$ACT"
check "out: no IDLE_SLOTS" "$(watch bob)" SENTINEL

# --- succession by the file's order. Beacons: alice, bob, carol from the inbox; run as dave (no snapshot of its own).
now=$(date +%s)
iso() { env_do alice "TZ=UTC hive_epoch_fmt $1 +%Y-%m-%dT%H:%M:%SZ"; }   # via hive-env.sh: portable (no date -r)
far=$(iso $((now + 4 * 86400))); r5=$(iso $((now + 3600))); r5b=$(iso $((now + 7200)))
fresh=$((now - 600)); stale=$((now - 7 * 3600))
usage() { echo "$1|$2|USAGE|$3% $4% $5 r5=${6:-$r5} agents=1"; }   # usage <epoch> <handle> <5h> <7d> <7d reset> [5h reset]
INBOX=$T/state/msg-inbox.log
tm() { HIVE_ACCOUNT=${1:-dave} bash "$AG/hive-succession.sh" ${2:-}; }
rm -f "$T/state/triagemaster"
printf '# queue\ncarol=on\nbob=on\nalice=on\n' > "$ACT"
{ usage $fresh alice 10 20 "$far"; usage $fresh bob 10 20 "$far"; usage $fresh carol 10 20 "$far"; } > "$INBOX"
check "order: top account that is in" "$(tm)" carol
printf 'bob=on\ncarol=on\nalice=on\n' > "$ACT"
check "reorder: new top claims it" "$(tm)" bob
printf 'bob=off\ncarol=on\nalice=on\n' > "$ACT"
check "out: skipped" "$(tm)" carol
printf 'carol=on\nbob=on\nalice=on\n' > "$ACT"
{ usage $fresh alice 10 20 "$far"; usage $fresh bob 10 20 "$far"; usage $fresh carol 95 20 "$far"; } > "$INBOX"
check "non-viable: 5h stop skips to the next" "$(tm)" bob
{ usage $fresh alice 10 20 "$far"; usage $fresh bob 10 20 "$far"; usage $stale carol 10 20 "$far"; } > "$INBOX"
check "non-viable: offline skips to the next" "$(tm)" bob
# the weekly stop is the hub's (the studio default here: 90% used)
printf '* five_h=95 weekly=90 auto_file=1\n' > "$T/studio/account-limits.conf"
soon=$(iso $((now + 3600)))
{ usage $fresh alice 10 20 "$far"; usage $fresh bob 10 90 "$far"; usage $stale carol 10 20 "$far"; } > "$INBOX"
check "non-viable: weekly ticket stop skips again" "$(tm)" alice
{ usage $fresh alice 10 20 "$far"; usage $fresh bob 10 89 "$far"; usage $stale carol 10 20 "$far"; } > "$INBOX"
check "viable: under its weekly ticket stop, over the 85% handoff" "$(tm)" bob
{ usage $fresh alice 10 20 "$far"; usage $fresh bob 10 96 "$soon"; usage $stale carol 10 20 "$far"; } > "$INBOX"
check "viable: stop ignored in the last day, like tickets" "$(tm)" bob
{ usage $fresh alice 10 20 "$far"; usage $fresh bob 10 100 "$soon"; usage $stale carol 10 20 "$far"; } > "$INBOX"
check "non-viable: 100% weekly even in the last day" "$(tm)" alice
printf 'bob five_h=95 weekly=80\n* five_h=95 weekly=90\n' > "$T/studio/account-limits.conf"
{ usage $fresh alice 10 20 "$far"; usage $fresh bob 10 85 "$far"; usage $stale carol 10 20 "$far"; } > "$INBOX"
check "non-viable: its own weekly stop wins over the default" "$(tm)" alice
rm -f "$T/studio/account-limits.conf"
{ usage $fresh alice 10 20 "$far"; usage $fresh bob 10 20 "$far"; usage $fresh carol 10 20 "$far"; } > "$INBOX"
check "returns to the higher account" "$(tm)" carol
check "...and the file says so" "$(cat "$T/state/triagemaster")" carol

# --- nobody in is viable: the one whose stop lifts soonest holds it, and says so once (outbox: no Discord token here)
{ usage $fresh alice 95 20 "$far" "$r5b"; usage $fresh bob 95 20 "$far" "$r5"; usage $stale carol 10 20 "$far"; } > "$INBOX"
check "fallback: soonest reset" "$(tm)" bob
: > "$T/state/outbox.log"
echo '{"rate_limits":{"five_hour":{"used_percentage":95,"resets_at":'$((now + 3600))'},"seven_day":{"used_percentage":20,"resets_at":'$((now + 4 * 86400))'}}}' > "$T/state/usage-snapshot.json"
tm bob --post >/dev/null; tm bob --post >/dev/null
check "fallback: said once" "$(grep -c 'No account that is in can hold the triagemaster role' "$T/state/outbox.log")" 1
check "fallback: names the holder" "$(grep -c 'Bob (bob) holds it' "$T/state/outbox.log")" 1
{ usage $fresh alice 10 20 "$far"; usage $fresh bob 10 20 "$far"; usage $fresh carol 10 20 "$far"; } > "$INBOX"
tm bob --post >/dev/null; check "fallback over: marker cleared" "$([ -e "$T/state/.tm-fallback" ] && echo kept || echo cleared)" cleared
rm -f "$T/state/usage-snapshot.json"
{ usage $stale alice 10 20 "$far"; usage $stale bob 10 20 "$far"; usage $fresh carol 10 20 "$far"; } > "$INBOX"
printf 'alice=on\nbob=on\ncarol=off\n' > "$ACT"
check "fallback: nobody fresh, the top holds it" "$(tm)" alice

# --- no studio file (or an empty one, the studio's 404; or no STUDIO_REPO): the same rules over SUCCESSION_RANK
rm -f "$ACT" "$T/state/triagemaster"
{ usage $fresh alice 10 85 "$far"; usage $fresh bob 10 20 "$far"; usage $fresh carol 10 20 "$far"; } > "$INBOX"
check "no file: rank 1 under its weekly stop keeps the role" "$(tm)" alice
{ usage $stale alice 10 20 "$far"; usage $fresh bob 10 20 "$far"; usage $fresh carol 10 20 "$far"; } > "$INBOX"
check "no file: rank 1 offline, rank 2" "$(tm)" bob
{ usage $fresh alice 10 100 "$far"; usage $fresh bob 10 20 "$far"; usage $fresh carol 10 20 "$far"; } > "$INBOX"
check "no file: rank 1 at 100% weekly, rank 2" "$(tm)" bob
{ usage $fresh alice 95 20 "$far"; usage $fresh bob 95 20 "$far"; usage $fresh carol 10 20 "$far"; } > "$INBOX"
check "no file: 5h stops pass the role down" "$(tm)" carol
{ usage $fresh alice 10 20 "$far"; usage $fresh bob 10 20 "$far"; usage $fresh carol 10 20 "$far"; } > "$INBOX"
check "no file: back to rank 1" "$(tm)" alice
: > "$ACT"
check "empty file: SUCCESSION_RANK" "$(tm)" alice
check "empty file: nobody out" "$(env_do alice 'hive_peers | tr "\n" " "')" "bob carol dave "
printf 'carol=on\nalice=off\n' > "$ACT"
sed -i.bak 's/^STUDIO_REPO=.*/STUDIO_REPO=/' "$T/repo/hive.conf"
check "no STUDIO_REPO: the cache is ignored" "$(tm)" alice
check "no STUDIO_REPO: worker target" "$(env_do alice 'hive_worker_target')" 3
HIVE_ACCOUNT=alice bash "$AG/hive-at-mode.sh" MT >/dev/null
check "no studio: local MT still works" "$(env_do alice 'hive_mt && echo MT || echo AT')" MT

echo "studio-active: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
