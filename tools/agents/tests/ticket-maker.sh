#!/bin/bash
# Offline test for the per-game ticket-maker mode (docs/agents/hive.md rule 11): hive_tm_mode reading the studio's
# hive/ticket-maker.conf from HIVE_STUDIO_CACHE (this game's $REPO line wins, other repos and bad values ignored, comments,
# spaces, CRLF), the local fallback file (on -> full, off -> suggestions, default full), hive-ticketmaker.sh (prints the
# mode; the setter is refused with STUDIO_REPO), the status-line suffix, and the triage watcher per mode: IDLE_SLOTS only
# with a startable ticket unless full, PEER_QUEUE_LOW only when full, no DISCORD_BUG wake when off.
# Stub gh, curl and hive-discord-bugs.sh, scratch state. No network.   bash tools/agents/tests/ticket-maker.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-tmaker-test.XXXXXX") || exit 1
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
TMC=$T/studio/ticket-maker.conf
mode() { HIVE_ACCOUNT=alice bash "$AG/hive-ticketmaker.sh" 2>/dev/null; }

# --- the studio file: this game's line wins; other repos, bad values, comments and CRLF
check "sync list has the file" "$(HIVE_ACCOUNT=alice bash -c '. "$1/hive-env.sh"; echo "$HIVE_STUDIO_FILES"' _ "$AG" | grep -c 'hive/ticket-maker.conf')" 1
check "no file: default full" "$(mode)" full
printf '# per game\nexample/other=off\nexample/project=suggestions\n' > "$TMC"
check "matched by REPO" "$(mode)" suggestions
printf 'example/other=off\nexample/projects=off\nx/example/project=off\n' > "$TMC"
check "other repos ignored" "$(mode)" full
printf '# header\r\n  example/project = off  # quiet week\r\n' > "$TMC"
check "spaces, comment, CRLF" "$(mode)" off
printf 'Example/Project=suggestions\n' > "$TMC"
check "repo case ignored" "$(mode)" suggestions
printf 'example/project=off\nexample/project=maybe\nexample/project=\nexample/project\n' > "$TMC"
check "bad values ignored" "$(mode)" off
printf 'example/project=off\nexample/project=full\n' > "$TMC"
check "last line wins" "$(mode)" full
printf 'example/project=FULL\n' > "$TMC"
check "value case ignored" "$(mode)" full
check "nocasematch restored" "$(HIVE_ACCOUNT=alice bash -c '. "$1/hive-env.sh"; hive_tm_mode; shopt -q nocasematch && echo on || echo off' _ "$AG")" off

# --- the setter: refused with a studio, nothing written
HIVE_ACCOUNT=alice bash "$AG/hive-ticketmaker.sh" off >/dev/null 2>"$T/err"; check "studio: setter exit 3" "$?" 3
check "studio: setter says where" "$(grep -c 'set in the hive hub (Ticket-maker panel)' "$T/err")" 1
check "studio: nothing written" "$([ -e "$T/state/ticketmaker" ] && echo written || echo none)" none
HIVE_ACCOUNT=alice bash "$AG/hive-ticketmaker.sh" maybe >/dev/null 2>&1; check "bad arg: exit 2" "$?" 2

# --- the local fallback: no line for this game, or no studio
: > "$TMC"; echo off > "$T/state/ticketmaker"
check "empty studio file: local off = suggestions" "$(mode)" suggestions
printf 'example/other=off\n' > "$TMC"; echo on > "$T/state/ticketmaker"
check "no line: local on = full" "$(mode)" full
printf 'example/project=off\n' > "$TMC"
check "studio line wins over local" "$(mode)" off
sed -i.bak 's/^STUDIO_REPO=.*/STUDIO_REPO=/' "$T/repo/hive.conf"
check "no STUDIO_REPO: cache ignored, local on" "$(mode)" full
check "no studio: set suggestions" "$(HIVE_ACCOUNT=alice bash "$AG/hive-ticketmaker.sh" suggestions)" suggestions
check "no studio: set off = suggestions" "$(HIVE_ACCOUNT=alice bash "$AG/hive-ticketmaker.sh" off)" suggestions
check "no studio: set full" "$(HIVE_ACCOUNT=alice bash "$AG/hive-ticketmaker.sh" full)" full
check "no studio: set on" "$(HIVE_ACCOUNT=alice bash "$AG/hive-ticketmaker.sh" on)" full
sed -i.bak 's/^STUDIO_REPO=.*/STUDIO_REPO=example\/studio/' "$T/repo/hive.conf"
rm -f "$T/state/ticketmaker"

# --- the status-line suffix
st() { printf 'example/project=%s\n' "$1" > "$TMC"; HIVE_ACCOUNT=alice bash "$AG/hive-at-mode.sh" | sed 's/^AT·[a-z ]*//'; }
check "status: full" "$(st full)" ""
check "status: suggestions" "$(st suggestions)" "·TM sugg"
check "status: off" "$(st off)" "·TM off"

# --- the watcher, per mode. A wake file ends the first poll so it never blocks.
watch() {   # watch <account> <mode>: the first line, after one poll and one 1 s tick
  printf 'example/project=%s\n' "$2" > "$TMC"
  rm -f "$T/state/.slots-last" "$T/state/.triage-seen"; echo 0 > "$T/state/.msg-wake-handled"; date +%s > "$T/state/.tmcheck-last"
  echo "SENTINEL" > "$T/state/msg-wake.txt"
  HIVE_ACCOUNT=$1 HIVE_TICK=1 WATCH_INTERVAL=1 bash "$AG/hive-triage-watch.sh" 2>/dev/null | head -n 1
}
echo carol > "$T/state/triagemaster"
# bob idle, the only ready ticket is carol's: not startable for bob
echo '[{"number":903,"labels":[{"name":"ready-for-agent"},{"name":"p2"}],"assignees":[{"login":"carol"}],"pull_request":null}]' > "$T/issues.json"
check "full: IDLE_SLOTS" "$(watch bob full)" "IDLE_SLOTS 0/3 active work packages"
check "suggestions: no IDLE_SLOTS without a startable ticket" "$(watch bob suggestions)" SENTINEL
check "off: no IDLE_SLOTS without a startable ticket" "$(watch bob off)" SENTINEL
echo '[{"number":904,"labels":[{"name":"ready-for-agent"},{"name":"p2"}],"assignees":[],"pull_request":null}]' > "$T/issues.json"
check "off: IDLE_SLOTS with a startable ticket" "$(watch bob off)" "IDLE_SLOTS 0/3 active work packages"
# the triagemaster at its 5h stop (worker target 0, no IDLE_SLOTS): peers' queues are refilled only when full
echo alice > "$T/state/triagemaster"
echo '{"rate_limits":{"five_hour":{"used_percentage":95,"resets_at":'$(( $(date +%s) + 3600 ))'},"seven_day":{"used_percentage":10,"resets_at":'$(( $(date +%s) + 4 * 86400 ))'}}}' > "$T/state/usage-snapshot.json"
echo '[{"number":905,"labels":[{"name":"p2"}],"assignees":[{"login":"alice"}],"pull_request":null}]' > "$T/issues.json"
check "full: PEER_QUEUE_LOW" "$(watch alice full | cut -d' ' -f1)" PEER_QUEUE_LOW
check "suggestions: no PEER_QUEUE_LOW" "$(watch alice suggestions)" SENTINEL
check "off: no PEER_QUEUE_LOW" "$(watch alice off)" SENTINEL

# --- Discord: the triagemaster wakes on new reports in full and suggestions, never while off. A WATCH_HOOKS line on the
# second poll ends the run when nothing woke during the first poll's six 1 s ticks (the Discord check runs on tick 6).
printf 'HIVE_DISCORD_TOKEN=fake\n' > "$T/state/discord.conf"; chmod 600 "$T/state/discord.conf"
printf '#!/bin/bash\n[ "$1" = --dev ] && exit 1\necho "%s" >> "%s/dcalls"\n[ "$1" = check ] && { echo 2; exit 0; }\nexit 1\n' x "$T" > "$AG/hive-discord-bugs.sh"
echo '[]' > "$T/issues.json"
dwatch() {   # dwatch <mode>
  printf 'example/project=%s\n' "$1" > "$TMC"; rm -f "$T/hook1" "$T/state/msg-wake.txt"; date +%s > "$T/state/.slots-last"; date +%s > "$T/state/.tmcheck-last"
  HIVE_ACCOUNT=alice HIVE_TICK=1 WATCH_INTERVAL=6 WATCH_HOOKS="[ -e '$T/hook1' ] && echo HOOKED || touch '$T/hook1'" \
    bash "$AG/hive-triage-watch.sh" 2>/dev/null | head -n 1
}
check "full: DISCORD_BUG" "$(dwatch full)" "DISCORD_BUG 2 new in #change-requests"
check "suggestions: DISCORD_BUG" "$(dwatch suggestions)" "DISCORD_BUG 2 new in #change-requests"
: > "$T/dcalls"
check "off: no Discord wake" "$(dwatch off)" HOOKED
check "off: Discord not read" "$(grep -c . "$T/dcalls")" 0

echo "ticket-maker: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
