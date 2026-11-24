#!/bin/bash
# Offline test for the idle-dev alert: hive_claude_at, the claude_at field in the USAGE beacon, hive_peer_claude_at and
# hive_dev_idle_check (the DEV_IDLE wake of hive-triage-watch.sh). Scratch HIVE_STATE_DIR with a stubbed msg-inbox.log, stub gh
# and curl first on PATH. No network. macOS, Linux and Git Bash.   bash tools/agents/tests/dev-idle.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-devidle-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cfg=$(cat); echo "curl $* | $cfg" >> "$HIVE_TEST_LOG"; exit 0
STUB
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "pr list"*) cat "$HIVE_TEST_PRS" 2>/dev/null || echo '[]';;
  "api --paginate"*timeline*) cat "$HIVE_TEST_TL" 2>/dev/null || echo '[]';;
  *) exit 1;;
esac
STUB
chmod +x "$T/bin/curl" "$T/bin/gh"
git init -q "$T/repo"; git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state REPO_PATH=$T/repo HIVE_TEST_LOG=$T/calls.log HIVE_TEST_PRS=$T/prs.json HIVE_TEST_TL=$T/tl.json
export HIVE_ACCOUNT=alice
. "$AG/hive-env.sh" || exit 1
. "$AG/hive-triage-watch.sh" --functions || exit 1
hive_quiet() { [ "${TEST_DN:-day}" = night ]; }
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
now=$(date +%s); export HIVE_NOW=$now; iso() { TZ=UTC hive_epoch_fmt "$1" +%Y-%m-%dT%H:%M:%SZ; }
INBOX=$T/state/msg-inbox.log
far=$(iso $((now + 4 * 86400))); soon=$(iso $((now + 3600))); r5=$(iso $((now + 7200)))

# --- T1: hive_claude_at scans every project folder, subagents included, paths with spaces, backslashes
P=$T/home/.claude/projects; mkdir -p "$P/p1 dir/s/subagents" "$P/p2"
touch -t "$(hive_epoch_fmt $((now - 7200)) +%Y%m%d%H%M.%S)" "$P/p1 dir/a.jsonl"
touch -t "$(hive_epoch_fmt $((now - 1200)) +%Y%m%d%H%M.%S)" "$P/p1 dir/s/subagents/b.jsonl"
touch -t "$(hive_epoch_fmt $((now - 600)) +%Y%m%d%H%M.%S)" "$P/p2/c.jsonl"
cmt=$(hive_mtime "$P/p2/c.jsonl")
echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":12,\"resets_at\":$((now+7200))},\"seven_day\":{\"used_percentage\":34,\"resets_at\":$((now+400000))}},\"transcript_path\":\"$P/p1 dir/a.jsonl\"}" > "$T/state/usage-snapshot.json"
check "T1 newest across folders" "$(hive_claude_at)" "$cmt"
bs=$(printf '%s' "$P/p1 dir/a.jsonl" | tr / '\\')   # backslash form of the same path (Windows)
mkdir -p "$T/st2" "$T/st3"
jq --arg p "$bs" '.transcript_path=$p' "$T/state/usage-snapshot.json" > "$T/st2/usage-snapshot.json"
jq 'del(.transcript_path)' "$T/state/usage-snapshot.json" > "$T/st3/usage-snapshot.json"
check "T1 backslash path" "$(HIVE_STATE_DIR=$T/st2 bash -c ". '$AG/hive-env.sh'; hive_claude_at")" "$cmt"
check "T1 no transcript_path" "$(HIVE_STATE_DIR=$T/st3 bash -c ". '$AG/hive-env.sh'; hive_claude_at")" ""

# --- T2: beacon carries claude_at; hive_beacon parses the line as before
echo "HIVE_MSG_TOPIC=hive-testtopic" > "$T/state/msg.conf"
bash "$AG/hive-beacon.sh"
check "T2 beacon claude_at" "$(grep -o 'claude_at=[0-9TZ:-]*' "$HIVE_TEST_LOG" | head -n 1)" "claude_at=$(iso "$cmt")"
line="$now|bob|USAGE|10% 20% $far r5=$r5 agents=1 at=$(iso $now) claude_at=$(iso $cmt)"
echo "$line" > "$INBOX"; hive_beacon bob
check "T2 hive_beacon fields" "$b_p5 $b_used $b_at" "10 20 $(iso $now)"

# --- helpers for T3+
ISS_READY='[{"number":900,"labels":[{"name":"ready-for-agent"},{"name":"p2"}],"assignees":[{"login":"bob"}],"pull_request":null}]'
ISS_P1=${ISS_READY//p2/p1}
ISS_NONE='[{"number":901,"labels":[{"name":"p2"}],"assignees":[{"login":"bob"}],"pull_request":null}]'
reset_state() { rm -f "$T"/state/.dev-idle-*; : > "$INBOX"; echo '[]' > "$HIVE_TEST_PRS"; echo '[]' > "$HIVE_TEST_TL"; TEST_DN=day; }
# beacon <5h> <7d> <7d reset> <claude_at age s> [usage age s] [r5]
beacon() { echo "$((now - ${5:-300}))|bob|USAGE|$1% $2% $3 r5=${6:-$r5} agents=1 at=$(iso $((now - ${5:-300}))) claude_at=$(iso $((now - $4)))" >> "$INBOX"; }
hello() { echo "$((now - ${1:-120}))|bob|HELLO|hi" >> "$INBOX"; }
run() { hive_dev_idle_check "$1" "${2:-}" "${3:-0}"; }

# --- T3: live heartbeats, old claude_at, ready work: exactly one wake
reset_state; hello 120; beacon 10 20 "$far" 3000
check "T3 wake" "$(run "$ISS_READY")" "DEV_IDLE bob 50"
# --- T4: throttle
check "T4 second call at once" "$(run "$ISS_READY")" ""
echo "$((now - 7201)) 1" > "$T/state/.dev-idle-bob"
check "T4 after 2h" "$(run "$ISS_READY")" "DEV_IDLE bob 50"
reset_state; hello 120; beacon 10 20 "$far" 7500   # 125 min idle
echo "$((now - 4800)) 1" > "$T/state/.dev-idle-bob"   # stage-1 wake 80 min ago, same stretch
check "T4 stage-2 wake at 2h idle" "$(run "$ISS_READY")" "DEV_IDLE bob 125"
check "T4 stage-2 once" "$(run "$ISS_READY")" ""
# --- T4b (#255): claude_at moving forward hourly while idle stays 45+ min never re-wakes within 2 h
reset_state; hello 120; beacon 10 20 "$far" 3000
check "T4b first wake" "$(run "$ISS_READY")" "DEV_IDLE bob 50"
# poll_at <seconds after now>: fresh heartbeats at that moment, claude_at 50 min before it (moved forward), then the check
poll_at() { local n=$((now + $1)); : > "$INBOX"; echo "$((n - 120))|bob|HELLO|hi" >> "$INBOX"
  echo "$((n - 300))|bob|USAGE|10% 20% $far r5=$r5 agents=1 at=$(iso $((n - 300))) claude_at=$(iso $((n - 3000)))" >> "$INBOX"
  HIVE_NOW=$n run "$ISS_READY"; }
check "T4b +30 min, claude_at moved" "$(poll_at 1800)" ""
check "T4b +60 min, claude_at moved" "$(poll_at 3600)" ""
check "T4b +119 min, claude_at moved" "$(poll_at 7140)" ""
check "T4b after 2h a new wake" "$(poll_at 7200)" "DEV_IDLE bob 50"
# stage-2 still fires once when idle reaches 2 h in one stretch (claude_at unchanged)
reset_state; hello 120; beacon 10 20 "$far" 3000
check "T4b stretch: stage-1 wake" "$(run "$ISS_READY")" "DEV_IDLE bob 50"
check "T4b stretch: none at 90 min" "$(HIVE_NOW=$((now + 2400)) run "$ISS_READY")" ""
check "T4b stretch: stage-2 at 2h idle" "$(HIVE_NOW=$((now + 4200)) run "$ISS_READY")" "DEV_IDLE bob 120"
check "T4b stretch: stage-2 once" "$(HIVE_NOW=$((now + 4300)) run "$ISS_READY")" ""
# --- T5: no work, or the ticket has a PR
reset_state; hello 120; beacon 10 20 "$far" 3000
check "T5 no ready ticket" "$(run "$ISS_NONE")" ""
check "T5 ticket has a PR" "$(run "$ISS_READY" "900")" ""
check "T5 meta ticket" "$(META_TICKETS="900" run "$ISS_READY")" ""
check "T5 conflict-risk held" "$(run "${ISS_READY//p2/conflict-risk}" "" 1)" ""
# --- T6: review-blocked PR
reset_state; hello 120; beacon 10 20 "$far" 3000
echo '[{"number":77,"labels":[{"name":"review-blocked"},{"name":"p2"}]}]' > "$HIVE_TEST_PRS"
echo '[{"event":"labeled","label":{"name":"review-blocked"},"created_at":"2026-11-11T10:00:00Z"}]' > "$HIVE_TEST_TL"
check "T6 blocked, no fix since" "$(run "$ISS_NONE")" "DEV_IDLE bob 50"
reset_state; hello 120; beacon 10 20 "$far" 3000
echo '[{"number":77,"labels":[{"name":"review-blocked"}]}]' > "$HIVE_TEST_PRS"
echo '[{"event":"labeled","label":{"name":"review-blocked"},"created_at":"2026-11-11T10:00:00Z"},{"event":"committed","committer":{"date":"2026-11-11T11:00:00Z"}}]' > "$HIVE_TEST_TL"
check "T6 fix pushed since" "$(run "$ISS_NONE")" ""
echo '[{"event":"labeled","label":{"name":"review-blocked"},"created_at":"2026-11-11T10:00:00Z"},{"event":"head_ref_force_pushed","created_at":"2026-11-11T11:00:00Z"}]' > "$HIVE_TEST_TL"
check "T6 force-push since" "$(run "$ISS_NONE")" ""
# --- T7: quiet hours only p1
reset_state; hello 120; beacon 10 20 "$far" 3000; TEST_DN=night
check "T7 night p2" "$(run "$ISS_READY")" ""
check "T7 night p1" "$(run "$ISS_P1")" "DEV_IDLE bob 50"
# --- T8: negatives
reset_state; hello 120; beacon 10 20 "$far" 1800
check "T8 claude_at 30 min" "$(run "$ISS_READY")" ""
reset_state; hello 120; echo "$((now - 300))|bob|USAGE|10% 20% $far r5=$r5 agents=1 at=$(iso $((now - 300)))" >> "$INBOX"
check "T8 no claude_at field" "$(run "$ISS_READY")" ""
reset_state; hello 120; beacon 10 20 "$far" 9000 1500; echo "$((now - 300))|bob|USAGE|10% 20% $far r5=$r5 agents=1 at=$(iso $((now - 300)))" >> "$INBOX"
check "T8 newest USAGE lacks field (older value not reused)" "$(run "$ISS_READY")" ""
reset_state; beacon 10 20 "$far" 3000 4000; hello 100
check "T8 USAGE over 1h old, fresh HELLO" "$(run "$ISS_READY")" ""
reset_state; hello 7200; beacon 10 20 "$far" 3000 7200
check "T8 heartbeat 2h old" "$(run "$ISS_READY")" ""
reset_state; hello 120; beacon 95 20 "$far" 3000
check "T8 5h at stop" "$(run "$ISS_READY")" ""
reset_state; hello 120; beacon 10 90 "$(iso $((now + 3 * 86400)))" 3000
check "T8 weekly 90%, no weekly stop set (stop is 100%)" "$(run "$ISS_READY")" "DEV_IDLE bob 50"
reset_state; hello 120; beacon 10 100 "$(iso $((now + 3 * 86400)))" 3000
check "T8 weekly 100%, reset 3 days away" "$(run "$ISS_READY")" ""
echo "MIN_WEEKLY_REMAINING_FOR_TICKETS=15" >> "$AG/accounts/bob.conf"
reset_state; hello 120; beacon 10 90 "$(iso $((now + 3 * 86400)))" 3000
check "T8 weekly stop (bob stop 85%), reset 3 days away" "$(run "$ISS_READY")" ""
reset_state; hello 120; beacon 10 90 "$(iso $((now + 12 * 3600)))" 3000
check "T8 control: weekly 90% over stop, reset 12h away (grace)" "$(run "$ISS_READY")" "DEV_IDLE bob 50"
sed -i.bak '/^MIN_WEEKLY_REMAINING_FOR_TICKETS=15$/d' "$AG/accounts/bob.conf"; rm -f "$AG/accounts/bob.conf.bak"
reset_state; echo "$((now - 300))|alice|USAGE|10% 20% $far r5=$r5 agents=1 at=$(iso $((now - 300))) claude_at=$(iso $((now - 3000)))" >> "$INBOX"
check "T8 this account itself" "$(run '[{"number":900,"labels":[{"name":"ready-for-agent"}],"assignees":[{"login":"alice"}],"pull_request":null}]')" ""
# --- T10: the #hive alert text (hive-dev-idle-alert.sh): <@id> from the local conf only, name otherwise; 120 min offers reassignment
AL=$AG/hive-dev-idle-alert.sh
a=$(bash "$AL" carol 50 "#900")
check "T10 no id: name only" "${a%%:*}" "Carol (carol)"
printf 'HIVE_DISCORD_TOKEN=x\nHIVE_DISCORD_ID_carol=123456789\nHIVE_DISCORD_ID_bob=987654321\n' > "$T/state/discord.conf"
a=$(bash "$AL" carol 50 "#900, PR #901")
check "T10 id known" "${a%%:*}" "<@123456789> Carol (carol)"
check "T10 no reassign offer under 2h" "$(echo "$a" | grep -c reassign)" 0
a=$(bash "$AL" bob 125 "#900")
check "T10 account with a dash" "${a%%:*}" "<@987654321> Bob (bob)"
check "T10 2h: idle time and reassign offer" "$(echo "$a" | grep -c '2h05m.*reassign your unclaimed')" 1
printf 'HIVE_DISCORD_TOKEN=x\nHIVE_DISCORD_ID_carol=12ab\n' > "$T/state/discord.conf"
check "T10 bad id ignored" "$(bash "$AL" carol 50 "#900" | cut -c1-13)" "Carol (carol)"
printf '#!/bin/bash\necho "post $*" >> "$HIVE_TEST_LOG"\n' > "$T/bin/pfd"; chmod +x "$T/bin/pfd"; : > "$HIVE_TEST_LOG"
HIVE_DISCORD_SH=$T/bin/pfd bash "$AL" carol 50 "#900" --post >/dev/null
check "T10 --post goes to #hive" "$(grep -c "^post post 3000000000000000002 " "$HIVE_TEST_LOG")" 1
# failed post: non-zero exit and the throttle stamp is cleared so the next poll wakes again
printf '#!/bin/bash\nexit 2\n' > "$T/bin/pfd-fail"; chmod +x "$T/bin/pfd-fail"; echo "$now 1" > "$T/state/.dev-idle-carol"
HIVE_DISCORD_SH=$T/bin/pfd-fail bash "$AL" carol 50 "#900" --post >/dev/null 2>&1; rc=$?
check "T10 transient post failure exits non-zero" "$rc" 1
check "T10 transient post failure clears the throttle" "$([ -e "$T/state/.dev-idle-carol" ] && echo kept || echo cleared)" cleared
# not configured: exits 2, nothing posted, stamp kept, and the watcher does not wake DEV_IDLE again within 2 h
notcfg() { # <name> <hive.conf to use> <grep for the reason>
  echo "$now 1" > "$T/state/.dev-idle-carol"; : > "$HIVE_TEST_LOG"
  HIVE_CONF=$2 HIVE_DISCORD_SH=$T/bin/pfd bash "$AL" carol 50 "#900" --post >/dev/null 2>"$T/err.txt"; rc=$?
  check "T10 $1 exits 2" "$rc" 2
  check "T10 $1 keeps the throttle" "$([ -e "$T/state/.dev-idle-carol" ] && echo kept || echo cleared)" kept
  check "T10 $1 posts nothing" "$(grep -c '^post ' "$HIVE_TEST_LOG")" 0
  check "T10 $1 says why" "$(grep -c "$3" "$T/err.txt")" 1
}
printf 'HIVE_DISCORD_ID_carol=123456789
' > "$T/state/discord.conf"
sed 's/^DISCORD=.*/DISCORD=1/' "$HIVE_CONF" > "$T/on.conf"
sed 's/^DISCORD=.*/DISCORD=0/' "$HIVE_CONF" > "$T/off.conf"
grep -v '^DISCORD_DEV_CHANNEL=' "$HIVE_CONF" > "$T/nodev.conf"
notcfg "no token" "$T/on.conf" "no HIVE_DISCORD_TOKEN"
printf 'HIVE_DISCORD_TOKEN=x
HIVE_DISCORD_ID_carol=123456789
' > "$T/state/discord.conf"
notcfg "DISCORD=0" "$T/off.conf" "Discord is off"
notcfg "empty DISCORD_DEV_CHANNEL" "$T/nodev.conf" "no DISCORD_DEV_CHANNEL"
reset_state; hello 120; beacon 10 20 "$far" 3000; echo "$now 1" > "$T/state/.dev-idle-bob"
check "T10 stamp kept: no DEV_IDLE re-wake within 2h" "$(HIVE_NOW=$((now + 1800)) run "$ISS_READY")" ""
rm -f "$T/state/.dev-idle-bob"
check "T10 control: stamp gone wakes again" "$(HIVE_NOW=$((now + 1800)) run "$ISS_READY")" "DEV_IDLE bob 80"
printf 'HIVE_DISCORD_TOKEN=x
HIVE_DISCORD_ID_carol=123456789
' > "$T/state/discord.conf"
# 2h+ with a very long list: the reassignment offer is still in the first 1990 characters
long=$(printf 'x%.0s' $(seq 1 3000))
a=$(bash "$AL" carol 130 "$long"); check "T10 long list keeps the offer" "$(echo "${a:0:1990}" | grep -c reassign)" 1
check "T10 reserve account name" "$(bash "$AL" dave 50 "#1" | cut -c1-20)" "Dave (reserve) (dave"
# the real hive-discord.sh post: allowed_mentions.users carries the opted-in id (HIVE_DISCORD_ID_<account>), no one else
printf 'HIVE_DISCORD_TOKEN=x\nHIVE_DISCORD_ID_carol=123456789\n' > "$T/state/discord.conf"; : > "$HIVE_TEST_LOG"
bash "$AG/hive-discord.sh" post 3000000000000000002 "hi <@123456789> and <@555>" >/dev/null 2>&1
check "T10 real post JSON: users" "$(tr -d ' \n' < "$HIVE_TEST_LOG" | grep -o '"users":\[[^]]*\]' | head -n 1)" '"users":["123456789"]'
echo "dev-idle: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
