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
echo "discord-bugs: $pass passed, $fail failed"; [ "$fail" = 0 ]
