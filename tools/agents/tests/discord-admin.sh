#!/bin/bash
# Offline test for pf-discord.sh (autotriage.md rule 20): a stub curl answers by URL from canned JSON, logs every call.
# No network. macOS, Linux and Git Bash.   bash tools/agents/tests/discord-admin.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-discord-admin.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
export PF_STATE_DIR=$T/state PF_ACCOUNT=tommykneeland PF_DISCORD_POLL=0; mkdir -p "$PF_STATE_DIR" "$T/bin"
cat > "$T/channels.json" <<'J'
[{"id":"11","type":4,"name":"🎮 Game","position":2},{"id":"12","type":0,"name":"🐛・bug-reports","parent_id":"11","position":3},
 {"id":"13","type":0,"name":"💬・general","position":1},{"id":"14","type":0,"name":"🔒・dev-chat","position":4}]
J
echo '[{"id":"900","name":"@everyone","position":0},{"id":"901","name":"Dev","position":1}]' > "$T/roles.json"
echo '[{"id":"501","timestamp":"2026-11-10T20:00:00","author":{"username":"sam"},"content":"hi","attachments":[]}]' > "$T/msgs.json"
# stub: first stdin line has the header, second the url; argv logged after it
cat > "$T/bin/curl" <<EOF
#!/bin/bash
cfg=\$(cat); url=\$(printf '%s\n' "\$cfg" | sed -n 's/^url = "\(.*\)"/\1/p')
printf '%s | %s\n' "\$url" "\$(printf '%s' "\$*" | tr -d ' \n')" >> "$T/curl.log"
case " \$* " in *" -w "*) printf 204; exit;; esac
case \$url in */guilds/*/channels) [ -n "\$(printf '%s' "\$*" | grep -- '-X POST')" ] && echo '{"id":"77","name":"new"}' || cat "$T/channels.json";;
  */roles) cat "$T/roles.json";; *"/messages?limit=1") echo '[{"id":"500"}]';; *"after=500"*) cat "$T/msgs.json";;
  */messages*) [ -n "\$(printf '%s' "\$*" | grep -- '-X POST')" ] && echo '{"id":"600"}' || cat "$T/msgs.json";;
  */channels/12) echo '{"id":"12","name":"🐛・bug-reports","topic":"t"}';; *) echo '{"message":"Unknown","code":10003}';; esac
EOF
chmod +x "$T/bin/curl"; export PATH=$T/bin:$PATH
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
D="$AG/pf-discord.sh"
bash "$D" channels >/dev/null 2>&1; check "no conf" $? 2
echo 'PF_DISCORD_TOKEN=tok' > "$PF_STATE_DIR/pf-discord.conf"
check "channels sorted with category" "$(bash "$D" channels | head -n 1)" "13  text  💬・general"
check "child shows category" "$(bash "$D" channels | grep -c '🎮 Game / 🐛・bug-reports')" 1
check "read by name fragment" "$(bash "$D" read bug 5 | grep -c '^hi$')" 1
grep -q 'channels/12/messages?limit=5' "$T/curl.log"; check "read hits resolved id" $? 0
bash "$D" read e >/dev/null 2>&1; check "ambiguous name refused" $? 2
check "watch wakes on a post" "$(bash "$D" watch bug)" "DISCORD 🐛・bug-reports 1 new (pf-discord.sh read 12 1)"
check "post returns id" "$(bash "$D" post general 'hello @everyone')" 600
grep 'messages | ' "$T/curl.log" | grep -- '-XPOST' | grep -q '"parse":\[\]'; check "post pings nobody" $? 0
check "topic" "$(bash "$D" topic 12 'new topic')" "#🐛・bug-reports topic: t"
check "create private" "$(bash "$D" create text secret 11 private)" "77 new"
grep -- '-XPOST' "$T/curl.log" | grep 'guilds/' | grep -q '"deny":"1024"'; check "private hides from everyone" $? 0
grep -- '-XPOST' "$T/curl.log" | grep 'guilds/' | grep -q '"id":"901","type":0,"allow":"1024"'; check "private shows Dev role" $? 0
check "role-add by name" "$(bash "$D" role-add 42 dev)" "role-add 42 dev: 204"
grep -q 'members/42/roles/901 | .*-XPUT' "$T/curl.log"; check "role-add PUTs role id" $? 0
bash "$D" role-add 42 nosuch >/dev/null 2>&1; check "unknown role refused" $? 2
bash "$D" api GET /channels/999 >/dev/null; check "api surfaces Discord error" $? 1
check "token never in argv" "$(grep -c 'tok' "$T/curl.log")" 0
echo "discord-admin: $pass passed, $fail failed"; [ "$fail" = 0 ]
