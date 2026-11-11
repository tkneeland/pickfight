#!/bin/bash
# Offline test for pf-discord-bugs.sh (autotriage.md rule 18) and pf-tm-check.sh's Discord lines (rule 19): a stub curl
# serves canned Discord JSON by URL from $T/r/, a scratch PF_STATE_DIR holds the conf and handled marker. No network.
# macOS, Linux and Git Bash.   bash tools/agents/tests/discord-bugs.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-discord-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
export PF_STATE_DIR=$T/state PF_ACCOUNT=tommykneeland; mkdir -p "$PF_STATE_DIR" "$T/bin" "$T/r"
# stub curl: logs url + compact argv; answers -w with 200; else the file named for the URL's last part, else default.json
cat > "$T/bin/curl" <<EOF
#!/bin/bash
cfg=\$(cat); url=\$(printf '%s\n' "\$cfg" | sed -n 's/^url = "\(.*\)"/\1/p')
printf '%s | %s\n' "\$url" "\$(printf '%s' "\$*" | tr -d ' \n')" >> "$T/curl.log"
printf '%s\n' "\$cfg" | grep '^header' >> "$T/headers.log"
case " \$* " in *" -w "*) printf 200; exit;; esac
k=\$(printf '%s' "\$url" | sed 's|.*/v10/||; s|[/?&=@]|_|g')
[ -f "$T/r/\$k" ] && cat "$T/r/\$k" || cat "$T/r/default.json"
EOF
chmod +x "$T/bin/curl"; export PATH=$T/bin:$PATH
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
D="$AG/pf-discord-bugs.sh"; CH=1569876514017779794; M="channels_${CH}_messages_limit_50"
msg() { echo "{\"id\":\"$1\",\"timestamp\":\"2026-11-10T20:00:00\",\"author\":{\"username\":\"$2\",\"bot\":$3},\"content\":\"$4\",\"attachments\":[],\"embeds\":[]}"; }
echo '{"message":"Unknown","code":0}' > "$T/r/default.json"
bash "$D" check >/dev/null 2>&1; check "no conf" $? 2
printf 'PF_DISCORD_TOKEN="tok123"\r\n' > "$PF_STATE_DIR/pf-discord.conf"
# first run, no marker: the newest 50 (reports from before the watcher) count as new
echo "[$(msg 1569876514017779900 sam false "posted before the watcher")]" > "$T/r/$M"
check "first run sees the backlog" "$(bash "$D" check)" 1
check "read shows it" "$(bash "$D" read | grep -c 'before the watcher')" 1
check "read marks nothing" "$(bash "$D" check)" 1
check "reply" "$(bash "$D" reply 1569876514017779900 'Filed as #5, thanks')" "discord reply: 200"
check "reply marks handled" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017779900
grep '_messages | \|/messages | ' "$T/curl.log" | grep -q '"parse":\[\]'; check "reply pings nobody" $? 0
# 19-digit ids stay exact (jq numbers would round them) and the marker only moves forward
A="${M}_after_1569876514017779900"
echo "[$(msg 1569876514017779902 bot true "filed #5"),$(msg 1569876514017779901 sam false "crash on join")]" > "$T/r/$A"
check "check counts people only" "$(bash "$D" check)" 1
check "check leaves marker" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017779900
check "read oldest first" "$(bash "$D" read | head -n 1 | cut -d' ' -f2)" 1569876514017779901
bash "$D" ack 1569876514017779901 >/dev/null; check "ack exact id" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017779901
bash "$D" ack 999 >/dev/null; check "ack never moves back" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017779901
bash "$D" ack abc >/dev/null 2>&1; check "ack rejects non-id" $? 2
# a full page of bot replies after the marker: check pages on and still finds the report behind them
B="${M}_after_1569876514017779901"; L=""
for i in $(seq 10 59); do L="$L$(msg 15698765140177799$i bot true reply),"; done
echo "[${L%,}]" > "$T/r/$B"
echo "[$(msg 1569876514017780000 sam false "behind the bot replies")]" > "$T/r/${M}_after_1569876514017779959"
check "pages past 50 bot replies" "$(bash "$D" check)" 1
check "read finds it" "$(bash "$D" read | grep -c 'behind the bot replies')" 1
# bot-only: check steps the marker past them so they are not fetched again
echo '[]' > "$T/r/${M}_after_1569876514017779959"
bash "$D" check >/dev/null; check "bot-only: nothing new" $? 1
check "bot-only: marker steps on" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017779959
check "token on stdin only" "$(grep -c 'Bot tok123"$' "$T/headers.log")" "$(grep -c . "$T/headers.log")"
check "token never in argv" "$(grep -c tok123 "$T/curl.log")" 0
rm "$T/r/${M}_after_1569876514017779959"
bash "$D" check >/dev/null 2>&1; check "discord error" $? 2
# status: token, channel, history, permissions, message text
echo '{"id":"42","username":"ClaudeChat"}' > "$T/r/users__me"
echo '{"name":"bug-reports"}' > "$T/r/channels_$CH"
echo "[$(msg 1569876514017779901 sam false "crash on join")]" > "$T/r/channels_${CH}_messages_limit_10"
echo '{"roles":["7"]}' > "$T/r/guilds_1569873613526405190_members_42"
echo '[{"id":"7","permissions":"8"},{"id":"1569873613526405190","permissions":"0"}]' > "$T/r/guilds_1569873613526405190_roles"
out=$(bash "$D" status); check "status ok" $? 0
check "status admin may reply" "$(echo "$out" | grep -c 'PASS bot may read #bug-reports and reply')" 1
check "status text visible" "$(echo "$out" | grep -c 'Message Content intent on')" 1
echo '[{"id":"7","permissions":"1024"},{"id":"1569873613526405190","permissions":"0"}]' > "$T/r/guilds_1569873613526405190_roles"
out=$(bash "$D" status); check "status missing send" $? 2
check "status says which" "$(echo "$out" | grep -c 'FAIL bot lacks View Channel, Send Messages')" 1
echo '[{"id":"7","permissions":"1024"},{"id":"1569873613526405190","permissions":"67584"}]' > "$T/r/guilds_1569873613526405190_roles"
bash "$D" status >/dev/null; check "status ORs @everyone perms" $? 0
echo "[$(msg 1569876514017779901 sam false "")]" > "$T/r/channels_${CH}_messages_limit_10"
out=$(bash "$D" status); check "status blank text" $? 2
check "status names intent" "$(echo "$out" | grep -c 'Message Content intent')" 1
echo '{"message":"Missing Access","code":50001}' > "$T/r/channels_$CH"
out=$(bash "$D" status); check "status not in server" $? 2
check "status says why" "$(echo "$out" | grep -c 'FAIL bot ClaudeChat cannot see')" 1
echo '{"message":"401: Unauthorized"}' > "$T/r/users__me"
bash "$D" status >/dev/null; check "status bad token" $? 2
# pf-tm-check.sh turns a Discord failure into a FAIL that says it is not watched (watcher checks skipped, gh stubbed)
printf '#!/bin/bash\necho "[]"\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
out=$(PF_TM_CHECK_SKIP_PROCS=1 bash "$AG/pf-tm-check.sh" --quiet); check "tm-check fails" $? 1
check "tm-check flags discord" "$(echo "$out" | grep -c 'FAIL Discord #bug-reports is NOT being watched')" 1
check "tm-check keeps levels" "$(echo "$out" | grep -c '^FAIL discord token rejected')" 1
rm "$PF_STATE_DIR/pf-discord.conf"
check "tm-check flags missing conf" "$(PF_TM_CHECK_SKIP_PROCS=1 bash "$AG/pf-tm-check.sh" --quiet | grep -c 'is NOT being watched')" 1
echo "discord-bugs: $pass passed, $fail failed"; [ "$fail" = 0 ]
