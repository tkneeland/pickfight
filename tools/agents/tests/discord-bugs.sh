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
check "reply marks that one handled" "$(grep -c 1569876514017779900 "$PF_STATE_DIR/.discord-bugs-handled")" 1
check "reply is logged" "$(grep -c 'reply: Filed as #5' "$PF_STATE_DIR/discord-bugs.log")" 1
bash "$D" check >/dev/null; check "check steps the marker past it" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017779900
grep '_messages | \|/messages | ' "$T/curl.log" | grep -q '"parse":\[\]'; check "reply pings nobody" $? 0
# 19-digit ids stay exact (jq numbers would round them) and the marker only moves forward
A="${M}_after_1569876514017779900"
echo "[$(msg 1569876514017779902 bot true "filed #5"),$(msg 1569876514017779901 sam false "crash on join")]" > "$T/r/$A"
check "check counts people only" "$(bash "$D" check)" 1
check "check leaves marker" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017779900
check "read oldest first" "$(bash "$D" read | head -n 1 | cut -d' ' -f2)" 1569876514017779901
bash "$D" ack 1569876514017779901 >/dev/null 2>&1; check "ack needs a reason" $? 2
bash "$D" ack 1569876514017779901 "chat: thanks" >/dev/null; bash "$D" check >/dev/null
check "ack steps past it and the bot reply after it" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017779902
bash "$D" ack 999 "test" >/dev/null; bash "$D" check >/dev/null; check "ack never moves back" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017779902
bash "$D" ack abc "x" >/dev/null 2>&1; check "ack rejects non-id" $? 2
# a full page of bot replies after the marker: check pages on and still finds the report behind them
B="${M}_after_1569876514017779902"; L=""
for i in $(seq 10 59); do L="$L$(msg 15698765140177799$i bot true reply),"; done
echo "[${L%,}]" > "$T/r/$B"
echo "[$(msg 1569876514017780000 sam false "behind the bot replies")]" > "$T/r/${M}_after_1569876514017779959"
check "pages past 50 bot replies" "$(bash "$D" check)" 1
check "read finds it" "$(bash "$D" read | grep -c 'behind the bot replies')" 1
# bot-only: check steps the marker past them so they are not fetched again
echo '[]' > "$T/r/${M}_after_1569876514017779959"
bash "$D" check >/dev/null; check "bot-only: nothing new" $? 1
check "bot-only: marker steps on" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017779959
# a reply to a later report leaves an earlier one unhandled (owner, 2026-11-10: feature requests were skipped)
C="${M}_after_1569876514017779959"
echo "[$(msg 1569876514017780001 sam false "add a countdown"),$(msg 1569876514017780002 kenobi false "ping is laggy")]" > "$T/r/$C"
bash "$D" reply 1569876514017780002 "Filed as #9" >/dev/null
check "earlier report still pending" "$(bash "$D" check)" 1
check "read shows only it" "$(bash "$D" read | grep -c '^--- ')" 1
check "it is the earlier one" "$(bash "$D" read | grep -c 'add a countdown')" 1
check "marker waits for it" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017779959
bash "$D" reply 1569876514017780001 "Filed as #10" >/dev/null; bash "$D" check >/dev/null; check "both handled" $? 1
check "marker past both" "$(cat "$PF_STATE_DIR/.discord-bugs-last")" 1569876514017780002
echo '[]' > "$T/r/$C"; rm -f "$T/r/${M}_after_1569876514017780002"
# --dev: the private #hive channel keeps its own marker and handled list
DV="channels_1569919897591611552_messages_limit_50"
echo "[$(msg 1569919897591611600 austin false "dev: lobby crash")]" > "$T/r/$DV"
check "dev check" "$(bash "$D" --dev check)" 1
bash "$D" --dev reply 1569919897591611600 "Filed as #11" >/dev/null; bash "$D" --dev check >/dev/null
check "dev marker is its own" "$(cat "$PF_STATE_DIR/.discord-dev-last")" 1569919897591611600
check "dev reply is logged as dev" "$(grep -c "dev reply: Filed as #11" "$PF_STATE_DIR/discord-bugs.log")" 1
# #1219: a newly promoted triagemaster (succession or failover takeover) has no marker or handled list; its first --dev
# check must not wake on the backlog the previous holder already answered. A failover notice is not an answer.
rep() { echo "{\"id\":\"$1\",\"timestamp\":\"2026-11-10T20:00:00\",\"author\":{\"username\":\"ClaudeChat\",\"bot\":true},\"content\":\"$3\",\"message_reference\":{\"message_id\":\"$2\"},\"attachments\":[],\"embeds\":[]}"; }
rm -f "$PF_STATE_DIR/.discord-dev-last" "$PF_STATE_DIR/.discord-dev-handled"
echo "[$(msg 1569919897591611700 austin false "dev: lobby crash"),$(rep 1569919897591611701 1569919897591611700 "Filed as #11"),
  $(msg 1569919897591611702 sam false "status"),$(rep 1569919897591611703 1569919897591611702 "tkneeland: on 5m")]" > "$T/r/$DV"
check "promotion: read shows nothing" "$(bash "$D" --dev read | grep -c '^--- ')" 0
bash "$D" --dev check >/dev/null; check "promotion: answered backlog pends nothing" $? 1
check "promotion: marker seeded past it" "$(cat "$PF_STATE_DIR/.discord-dev-last")" 1569919897591611703
rm -f "$PF_STATE_DIR/.discord-dev-last"
echo "[$(msg 1569919897591611700 austin false "dev: lobby crash"),$(rep 1569919897591611701 1569919897591611700 "Filed as #11"),
  $(msg 1569919897591611704 sam false "is the build broken?"),$(rep 1569919897591611705 1569919897591611704 "taking over from tkneeland (now schans2)")]" > "$T/r/$DV"
check "promotion: it is the unanswered one" "$(bash "$D" --dev read | grep -c 'build broken')" 1
check "promotion: notice-only still pending" "$(bash "$D" --dev check)" 1
check "promotion: marker stops before it" "$(cat "$PF_STATE_DIR/.discord-dev-last")" 1569919897591611701
# #1239: an ack reacts ☑️ on Discord, so a promoted triagemaster skips acked messages too; anyone else's ☑️ is not the bot's
ack_out=$(bash "$D" --dev ack 1569919897591611704 "chat, no ticket" 2>&1)
check "ack: handled" "$ack_out" "handled 1569919897591611704"
check "ack: bot reacts ☑️" "$(grep -c 'messages/1569919897591611704/reactions/%E2%98%91%EF%B8%8F/@me | .*-XPUT' "$T/curl.log")" 1
rx() { echo "{\"id\":\"$1\",\"timestamp\":\"2026-11-10T20:00:00\",\"author\":{\"username\":\"$2\",\"bot\":false},\"content\":\"$3\",\"reactions\":[{\"emoji\":{\"name\":\"☑️\"},\"count\":1,\"me\":$4}],\"attachments\":[],\"embeds\":[]}"; }
rm -f "$PF_STATE_DIR/.discord-dev-last" "$PF_STATE_DIR/.discord-dev-handled"
echo "[$(rx 1569919897591611710 sam "lol" true),$(rx 1569919897591611711 austin "is it up?" false)]" > "$T/r/$DV"
check "promotion: acked one skipped, other ☑️ pending" "$(bash "$D" --dev read | grep -c '^--- ')" 1
check "promotion: the pending one is not the acked" "$(bash "$D" --dev read | grep -c 'is it up')" 1
check "promotion: ack count" "$(bash "$D" --dev check)" 1
check "promotion: marker past the acked one" "$(cat "$PF_STATE_DIR/.discord-dev-last")" 1569919897591611710
rm "$T/r/$DV"
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
