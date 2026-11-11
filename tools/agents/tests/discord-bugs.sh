#!/bin/bash
# Offline test for pf-discord-bugs.sh (autotriage.md rule 18): a stub curl serves canned Discord messages, a scratch
# PF_STATE_DIR holds the conf and read marker. No network. macOS, Linux and Git Bash.   bash tools/agents/tests/discord-bugs.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-discord-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
export PF_STATE_DIR=$T/state PF_ACCOUNT=tommykneeland; mkdir -p "$PF_STATE_DIR" "$T/bin"
# stub curl: logs its stdin config (url + header) and serves $T/reply.json, or a 200 code for -w
cat > "$T/bin/curl" <<EOF
#!/bin/bash
cat >> "$T/curl.log"; printf "%s\n" "\$*" >> "$T/curl.log"
case " \$* " in *" -w "*) printf 200;; *) cat "$T/reply.json";; esac
EOF
chmod +x "$T/bin/curl"; export PATH=$T/bin:$PATH
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
D="$AG/pf-discord-bugs.sh"
bash "$D" check >/dev/null 2>&1; check "no conf" $? 2
printf 'PF_DISCORD_TOKEN="tok123"\r\n' > "$PF_STATE_DIR/pf-discord.conf"
msg() { echo "{\"id\":\"$1\",\"timestamp\":\"2026-11-10T20:00:00\",\"author\":{\"username\":\"$2\",\"bot\":$3},\"content\":\"$4\",\"attachments\":[]}"; }
echo "[$(msg 100 sam false "posted before the watcher")]" > "$T/reply.json"
check "first run sees the backlog" "$(bash "$D" check)" 1
check "first read shows it" "$(bash "$D" read | grep -c 'before the watcher')" 1
check "marker" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 100
echo "[$(msg 102 bot true "filed #5"),$(msg 101 sam false "crash on join")]" > "$T/reply.json"
check "check counts people only" "$(bash "$D" check)" 1
check "check leaves marker" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 100
grep -q 'after=100' "$T/curl.log"; check "asks after marker" $? 0
check "token on stdin, quotes/CR stripped" "$(grep -c 'Bot tok123"$' "$T/curl.log")" 3
check "token never in argv" "$(grep -v '^header\|^url' "$T/curl.log" | grep -c tok123)" 0
out=$(bash "$D" read)
check "read shows report" "$(echo "$out" | grep -c 'crash on join')" 1
check "read hides bot" "$(echo "$out" | grep -c 'filed #5')" 0
check "read advances marker" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 102
echo '{"message":"Missing Access","code":50001}' > "$T/reply.json"
bash "$D" check >/dev/null 2>&1; check "discord error" $? 2
check "reply" "$(bash "$D" reply 101 'Filed as #5, thanks')" "discord reply: 200"
grep -q '"parse": \[\]' "$T/curl.log"; check "reply pings nobody" $? 0
# status: the stub answers the token, channel and history probes by URL
stub() {  # stub <answer for /users/@me> <answer for /channels/<id>> <answer for messages>
  printf '#!/bin/bash\ncfg=$(cat)\ncase "$cfg" in *users/@me*) echo %q;; *messages*) echo %q;; *) echo %q;; esac\n' \
    "$1" "$3" "$2" > "$T/bin/curl"; chmod +x "$T/bin/curl"; }
stub '{"username":"ClaudeChat"}' '{"name":"bug-reports"}' '[]'
out=$(bash "$D" status); check "status ok" $? 0
check "status names channel" "$(echo "$out" | grep -c 'PASS bot can read #bug-reports')" 1
stub '{"username":"ClaudeChat"}' '{"message":"Missing Access","code":50001}' '{"message":"Missing Access"}'
out=$(bash "$D" status); check "status not in server" $? 2
check "status says why" "$(echo "$out" | grep -c 'FAIL bot ClaudeChat cannot see')" 1
stub '{"message":"401: Unauthorized"}' '{}' '{}'
bash "$D" status >/dev/null; check "status bad token" $? 2
# pf-tm-check.sh turns that into a FAIL saying Discord is not watched (process checks skipped, gh stubbed)
stub '{"username":"ClaudeChat"}' '{"message":"Missing Access","code":50001}' '{"message":"Missing Access"}'
printf '#!/bin/bash\necho 0\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
out=$(PF_TM_CHECK_SKIP_PROCS=1 bash "$AG/pf-tm-check.sh" --quiet); check "tm-check fails" $? 1
check "tm-check flags discord" "$(echo "$out" | grep -c 'FAIL Discord #bug-reports is NOT being watched')" 1
rm "$PF_STATE_DIR/pf-discord.conf"
check "tm-check flags missing conf" "$(PF_TM_CHECK_SKIP_PROCS=1 bash "$AG/pf-tm-check.sh" --quiet | grep -c 'is NOT being watched')" 1
echo "discord-bugs: $pass passed, $fail failed"; [ "$fail" = 0 ]
