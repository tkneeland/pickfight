#!/bin/bash
# Offline test for the idle-dev alert (#1233): pf_claude_at, the claude_at field in the USAGE beacon, pf_peer_claude_at and
# pf_dev_idle_check (the DEV_IDLE wake of pf-triage-watch.sh). Scratch PF_STATE_DIR with a stubbed msg-inbox.log, stub gh
# and curl first on PATH. No network. macOS, Linux and Git Bash.   bash tools/agents/tests/dev-idle.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-devidle-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cfg=$(cat); echo "curl $* | $cfg" >> "$PF_TEST_LOG"; exit 0
STUB
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "pr list"*) cat "$PF_TEST_PRS" 2>/dev/null || echo '[]';;
  "api --paginate"*timeline*) cat "$PF_TEST_TL" 2>/dev/null || echo '[]';;
  *) exit 1;;
esac
STUB
chmod +x "$T/bin/curl" "$T/bin/gh"
git init -q "$T/repo"; git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export PATH="$T/bin:$PATH" PF_STATE_DIR=$T/state REPO_PATH=$T/repo PF_TEST_LOG=$T/calls.log PF_TEST_PRS=$T/prs.json PF_TEST_TL=$T/tl.json
export PF_ACCOUNT=tkneeland
. "$AG/pf-env.sh" || exit 1
. "$AG/pf-triage-watch.sh" --functions || exit 1
pf_daynight() { echo "${TEST_DN:-day}"; }
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
now=$(date +%s); iso() { TZ=UTC pf_epoch_fmt "$1" +%Y-%m-%dT%H:%M:%SZ; }
INBOX=$T/state/msg-inbox.log
far=$(iso $((now + 4 * 86400))); soon=$(iso $((now + 3600))); r5=$(iso $((now + 7200)))

# --- T1: pf_claude_at scans every project folder, subagents included, paths with spaces, backslashes
P=$T/home/.claude/projects; mkdir -p "$P/p1 dir/s/subagents" "$P/p2"
touch -t "$(pf_epoch_fmt $((now - 7200)) +%Y%m%d%H%M.%S)" "$P/p1 dir/a.jsonl"
touch -t "$(pf_epoch_fmt $((now - 1200)) +%Y%m%d%H%M.%S)" "$P/p1 dir/s/subagents/b.jsonl"
touch -t "$(pf_epoch_fmt $((now - 600)) +%Y%m%d%H%M.%S)" "$P/p2/c.jsonl"
cmt=$(pf_mtime "$P/p2/c.jsonl")
echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":12,\"resets_at\":$((now+7200))},\"seven_day\":{\"used_percentage\":34,\"resets_at\":$((now+400000))}},\"transcript_path\":\"$P/p1 dir/a.jsonl\"}" > "$T/state/usage-snapshot.json"
check "T1 newest across folders" "$(pf_claude_at)" "$cmt"
bs=$(printf '%s' "$P/p1 dir/a.jsonl" | tr / '\\')   # backslash form of the same path (Windows)
mkdir -p "$T/st2" "$T/st3"
jq --arg p "$bs" '.transcript_path=$p' "$T/state/usage-snapshot.json" > "$T/st2/usage-snapshot.json"
jq 'del(.transcript_path)' "$T/state/usage-snapshot.json" > "$T/st3/usage-snapshot.json"
check "T1 backslash path" "$(PF_STATE_DIR=$T/st2 bash -c ". '$AG/pf-env.sh'; pf_claude_at")" "$cmt"
check "T1 no transcript_path" "$(PF_STATE_DIR=$T/st3 bash -c ". '$AG/pf-env.sh'; pf_claude_at")" ""

# --- T2: beacon carries claude_at; pf_beacon parses the line as before
echo "PF_MSG_TOPIC=pf-testtopic" > "$T/state/pf-msg.conf"
bash "$AG/pf-beacon.sh"
check "T2 beacon claude_at" "$(grep -o 'claude_at=[0-9TZ:-]*' "$PF_TEST_LOG" | head -n 1)" "claude_at=$(iso "$cmt")"
line="$now|agage-JG|USAGE|10% 20% $far r5=$r5 agents=1 at=$(iso $now) claude_at=$(iso $cmt)"
echo "$line" > "$INBOX"; pf_beacon agage-JG
check "T2 pf_beacon fields" "$b_p5 $b_used $b_at" "10 20 $(iso $now)"

# --- helpers for T3+
ISS_READY='[{"number":900,"labels":[{"name":"ready-for-agent"},{"name":"p2"}],"assignees":[{"login":"agage-JG"}],"pull_request":null}]'
ISS_P1=${ISS_READY//p2/p1}
ISS_NONE='[{"number":901,"labels":[{"name":"p2"}],"assignees":[{"login":"agage-JG"}],"pull_request":null}]'
reset_state() { rm -f "$T"/state/.dev-idle-*; : > "$INBOX"; echo '[]' > "$PF_TEST_PRS"; echo '[]' > "$PF_TEST_TL"; TEST_DN=day; }
# beacon <5h> <7d> <7d reset> <claude_at age s> [usage age s] [r5]
beacon() { echo "$((now - ${5:-300}))|agage-JG|USAGE|$1% $2% $3 r5=${6:-$r5} agents=1 at=$(iso $((now - ${5:-300}))) claude_at=$(iso $((now - $4)))" >> "$INBOX"; }
hello() { echo "$((now - ${1:-120}))|agage-JG|HELLO|hi" >> "$INBOX"; }
run() { pf_dev_idle_check "$1" "${2:-}" "${3:-0}"; }

# --- T3: live heartbeats, old claude_at, ready work: exactly one wake
reset_state; hello 120; beacon 10 20 "$far" 3000
check "T3 wake" "$(run "$ISS_READY")" "DEV_IDLE agage-JG 50"
# --- T4: throttle
check "T4 second call at once" "$(run "$ISS_READY")" ""
echo "$((now - 7201)) 1" > "$T/state/.dev-idle-agage-JG"
check "T4 after 2h" "$(run "$ISS_READY")" "DEV_IDLE agage-JG 50"
reset_state; hello 120; beacon 10 20 "$far" 7500   # 125 min idle
echo "$((now - 4800)) 1" > "$T/state/.dev-idle-agage-JG"   # stage-1 wake 80 min ago, same stretch
check "T4 stage-2 wake at 2h idle" "$(run "$ISS_READY")" "DEV_IDLE agage-JG 125"
check "T4 stage-2 once" "$(run "$ISS_READY")" ""
# --- T5: no work, or the ticket has a PR
reset_state; hello 120; beacon 10 20 "$far" 3000
check "T5 no ready ticket" "$(run "$ISS_NONE")" ""
check "T5 ticket has a PR" "$(run "$ISS_READY" "900")" ""
check "T5 meta ticket" "$(META_TICKETS="900" run "$ISS_READY")" ""
check "T5 conflict-risk held" "$(run "${ISS_READY//p2/conflict-risk}" "" 1)" ""
# --- T6: review-blocked PR
reset_state; hello 120; beacon 10 20 "$far" 3000
echo '[{"number":77,"labels":[{"name":"review-blocked"},{"name":"p2"}]}]' > "$PF_TEST_PRS"
echo '[{"event":"labeled","label":{"name":"review-blocked"},"created_at":"2026-11-11T10:00:00Z"}]' > "$PF_TEST_TL"
check "T6 blocked, no fix since" "$(run "$ISS_NONE")" "DEV_IDLE agage-JG 50"
reset_state; hello 120; beacon 10 20 "$far" 3000
echo '[{"number":77,"labels":[{"name":"review-blocked"}]}]' > "$PF_TEST_PRS"
echo '[{"event":"labeled","label":{"name":"review-blocked"},"created_at":"2026-11-11T10:00:00Z"},{"event":"committed","committer":{"date":"2026-11-11T11:00:00Z"}}]' > "$PF_TEST_TL"
check "T6 fix pushed since" "$(run "$ISS_NONE")" ""
echo '[{"event":"labeled","label":{"name":"review-blocked"},"created_at":"2026-11-11T10:00:00Z"},{"event":"head_ref_force_pushed","created_at":"2026-11-11T11:00:00Z"}]' > "$PF_TEST_TL"
check "T6 force-push since" "$(run "$ISS_NONE")" ""
# --- T7: night only p1
reset_state; hello 120; beacon 10 20 "$far" 3000; TEST_DN=night
check "T7 night p2" "$(run "$ISS_READY")" ""
check "T7 night p1" "$(run "$ISS_P1")" "DEV_IDLE agage-JG 50"
# --- T8: negatives
reset_state; hello 120; beacon 10 20 "$far" 1800
check "T8 claude_at 30 min" "$(run "$ISS_READY")" ""
reset_state; hello 120; echo "$((now - 300))|agage-JG|USAGE|10% 20% $far r5=$r5 agents=1 at=$(iso $((now - 300)))" >> "$INBOX"
check "T8 no claude_at field" "$(run "$ISS_READY")" ""
reset_state; hello 120; beacon 10 20 "$far" 9000 1500; echo "$((now - 300))|agage-JG|USAGE|10% 20% $far r5=$r5 agents=1 at=$(iso $((now - 300)))" >> "$INBOX"
check "T8 newest USAGE lacks field (older value not reused)" "$(run "$ISS_READY")" ""
reset_state; beacon 10 20 "$far" 3000 4000; hello 100
check "T8 USAGE over 1h old, fresh HELLO" "$(run "$ISS_READY")" ""
reset_state; hello 7200; beacon 10 20 "$far" 3000 7200
check "T8 heartbeat 2h old" "$(run "$ISS_READY")" ""
reset_state; hello 120; beacon 95 20 "$far" 3000
check "T8 5h at stop" "$(run "$ISS_READY")" ""
reset_state; hello 120; beacon 10 90 "$(iso $((now + 3 * 86400)))" 3000
check "T8 weekly stop, reset 3 days away" "$(run "$ISS_READY")" ""
reset_state; hello 120; beacon 10 90 "$(iso $((now + 12 * 3600)))" 3000
check "T8 control: weekly 90% reset 12h away" "$(run "$ISS_READY")" "DEV_IDLE agage-JG 50"
reset_state; echo "$((now - 300))|tkneeland|USAGE|10% 20% $far r5=$r5 agents=1 at=$(iso $((now - 300))) claude_at=$(iso $((now - 3000)))" >> "$INBOX"
check "T8 this account itself" "$(run '[{"number":900,"labels":[{"name":"ready-for-agent"}],"assignees":[{"login":"tkneeland"}],"pull_request":null}]')" ""
# --- T10: the #hive alert text (pf-dev-idle-alert.sh): <@id> from the local conf only, name otherwise; 120 min offers reassignment
AL=$AG/pf-dev-idle-alert.sh
a=$(bash "$AL" schans2 50 "#900")
check "T10 no id: name only" "${a%%:*}" "Sam (schans2)"
printf 'PF_DISCORD_TOKEN=x\nPF_DISCORD_ID_schans2=123456789\nPF_DISCORD_ID_agage_JG=987654321\n' > "$T/state/pf-discord.conf"
a=$(bash "$AL" schans2 50 "#900, PR #901")
check "T10 id known" "${a%%:*}" "<@123456789> Sam (schans2)"
check "T10 no reassign offer under 2h" "$(echo "$a" | grep -c reassign)" 0
a=$(bash "$AL" agage-JG 125 "#900")
check "T10 account with a dash" "${a%%:*}" "<@987654321> Austin (agage-JG)"
check "T10 2h: idle time and reassign offer" "$(echo "$a" | grep -c '2h05m.*reassign your unclaimed')" 1
printf 'PF_DISCORD_TOKEN=x\nPF_DISCORD_ID_schans2=12ab\n' > "$T/state/pf-discord.conf"
check "T10 bad id ignored" "$(bash "$AL" schans2 50 "#900" | cut -c1-13)" "Sam (schans2)"
printf '#!/bin/bash\necho "post $*" >> "$PF_TEST_LOG"\n' > "$T/bin/pfd"; chmod +x "$T/bin/pfd"; : > "$PF_TEST_LOG"
PF_DISCORD_SH=$T/bin/pfd bash "$AL" schans2 50 "#900" --post >/dev/null
check "T10 --post goes to #hive" "$(grep -c "^post post 1569919897591611552 " "$PF_TEST_LOG")" 1
echo "dev-idle: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
