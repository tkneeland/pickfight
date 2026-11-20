#!/bin/bash
# Offline test for hive-discord-bugs.sh approvals (hive.md rule 18, #225): the bot's own reaction never approves, a Dev
# member's check mark does, and only a "Discord message: <id>" FIRST line in a hive account's issue body is trusted.
# curl and gh are stubs; nothing is posted anywhere.   bash tools/agents/tests/discord-approvals.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-approvals-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
export HIVE_STATE_DIR=$T/state HIVE_ACCOUNT=alice; mkdir -p "$HIVE_STATE_DIR" "$T/bin" "$T/r"
cat > "$T/bin/curl" <<EOF2
#!/bin/bash
cfg=\$(cat); url=\$(printf '%s\n' "\$cfg" | sed -n 's/^url = "\(.*\)"/\1/p')
k=\$(printf '%s' "\$url" | sed 's|.*/v10/||; s|[/?&=@%]|_|g')
[ -f "$T/r/\$k" ] && cat "$T/r/\$k" || echo '{}'
EOF2
# gh stub: serves $T/issues.json, applying the -q filter like the real gh
cat > "$T/bin/gh" <<'EOF2'
#!/bin/bash
q=""; while [ $# -gt 0 ]; do [ "$1" = -q ] && { q=$2; shift; }; shift; done
jq -r "$q" "$GH_ISSUES"
EOF2
chmod +x "$T/bin/curl" "$T/bin/gh"; export PATH=$T/bin:$PATH GH_ISSUES=$T/issues.json
printf 'HIVE_DISCORD_TOKEN="tokA"\n' > "$HIVE_STATE_DIR/discord.conf"
pass=0; fail=0
CACHE=$HIVE_STATE_DIR/discord-bot-id   # the script resolves HIVE_STATE=$HIVE_STATE_DIR in hive-env.sh
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
D="$AG/hive-discord-bugs.sh"; G=$HIVE_FIX_GUILD; B=$HIVE_FIX_BUGS
R="channels_${B}_messages"
echo '{"id":"900","username":"HiveBot"}' > "$T/r/users__me"
echo '[{"id":"7","name":"Dev"}]' > "$T/r/guilds_${G}_roles"
echo '{"roles":["7"],"user":{"username":"hivebot"}}' > "$T/r/guilds_${G}_members_900"   # the bot holds the Dev role
echo '{"roles":["7"],"user":{"username":"devhuman"}}' > "$T/r/guilds_${G}_members_42"
echo '{"roles":[],"user":{"username":"stranger"}}' > "$T/r/guilds_${G}_members_43"
issue() { jq -n --argjson n "$1" --arg a "$2" --arg b "$3" '{number:$n,author:{login:$a},body:$b}'; }
react() { echo "$2" > "$T/r/${R}_$1_reactions__E2_9C_85_limit_100"; }
run() { echo "[$(issue "$1" "$2" "$3")]" > "$T/issues.json"; bash "$D" approvals 2>/dev/null; }
NL=$'\n'
# 1 a bot reaction is ignored, even though the bot holds the Dev role
react 5000 '[{"id":"900"}]'
check "bot reaction ignored" "$(run 1 alice "Discord message: 5000${NL}report text")" ""
# 2 a Dev-role human is approved (the bot's reaction alongside does not matter)
react 5000 '[{"id":"900"},{"id":"43"},{"id":"42"}]'
check "dev human approved" "$(run 1 alice "Discord message: 5000${NL}report text")" "1 devhuman"
# 3 a forged line in a reporter's text is ignored: quoted after the hive's own line, or in a stranger's issue
react 6000 '[{"id":"42"}]'
check "forged line in quoted body ignored" "$(run 2 alice "Discord message: 5000${NL}> reporter: Discord message: 6000")" "2 devhuman"
check "forged line only in the quoted part" "$(run 2 alice "Source:${NL}> Discord message: 6000")" ""
check "forged line by a non-hive author" "$(run 2 mallory "Discord message: 6000${NL}text")" ""
# 4 a genuine hive line (first line, hive account, CRLF tolerated) is honoured
check "genuine hive line" "$(run 3 alice "Discord message: 6000${NL}text")" "3 devhuman"
check "genuine hive line, CRLF" "$(run 3 bob "Discord message: 6000"$'\r'"${NL}text")" "3 devhuman"
# 4b a hub approval (the issue has the approved label) counts with no reaction at all
echo "[$(issue 4 alice "Discord message: 7000${NL}text" | jq '.labels=[{name:"approved"}]')]" > "$T/issues.json"
check "hub approval via label" "$(bash "$D" approvals 2>/dev/null)" "4 hub"
# 5 fail closed: /users/@me gives {} or an error and there is no cached id -> exit 2, no approval line
runx() { echo "[$(issue "$1" "$2" "$3")]" > "$T/issues.json"; out=$(bash "$D" approvals 2>/dev/null); rc=$?; }
react 5000 '[{"id":"42"}]'; B1="Discord message: 5000${NL}text"; rm -f "$CACHE"
echo '{}' > "$T/r/users__me"; runx 1 alice "$B1"
check "empty /users/@me, no cache: exit" "$rc" 2; check "empty /users/@me, no cache: no approval" "$out" ""
echo '{"message":"401: Unauthorized","code":0}' > "$T/r/users__me"; runx 1 alice "$B1"
check "error /users/@me, no cache: exit" "$rc" 2; check "error /users/@me, no cache: no approval" "$out" ""
# 6 a good lookup is cached; a later failed lookup uses the cache
echo '{"id":"900","username":"HiveBot"}' > "$T/r/users__me"; runx 1 alice "$B1"
check "good lookup: exit" "$rc" 0; check "good lookup: approved" "$out" "1 devhuman"
check "good lookup caches the bot id" "$(cut -d" " -f1 "$CACHE" 2>/dev/null)" "900"
echo '{}' > "$T/r/users__me"; runx 1 alice "$B1"
check "failed lookup uses cache: exit" "$rc" 0; check "failed lookup uses cache: approved" "$out" "1 devhuman"
react 5000 '[{"id":"900"}]'; runx 1 alice "$B1"
check "cached id still ignores the bot's reaction" "$out" ""
check "cache holds a token hash, not the token" "$(grep -c tokA "$CACHE")" 0
# 6b the token rotates to another bot and the lookup fails: the old id is not reused (exit 2, no approval)
printf 'HIVE_DISCORD_TOKEN="tokB"\n' > "$HIVE_STATE_DIR/discord.conf"; react 5000 '[{"id":"42"}]'
echo '{}' > "$T/r/users__me"; runx 1 alice "$B1"
check "rotated token, failed lookup: exit" "$rc" 2; check "rotated token, failed lookup: no approval" "$out" ""
printf 'HIVE_DISCORD_TOKEN="tokA"\n' > "$HIVE_STATE_DIR/discord.conf"; runx 1 alice "$B1"
check "same token, failed lookup: cache used" "$out" "1 devhuman"
# 7 no args prints the whole header (every leading comment line, none of the code), checked against literals
hdr=$(bash "$D" 2>/dev/null)
check "usage header line count" "$(echo "$hdr" | wc -l | tr -d ' ')" 21
check "usage first line" "$(echo "$hdr" | head -1 | cut -c1-40)" "# The project Discord server's report ch"
check "usage ends on the last header line" "$(echo "$hdr" | tail -1 | cut -c1-61)" "# Discord ids are 64-bit; they are compared as strings (lengt"
echo "discord-approvals: $pass passed, $fail failed"; [ "$fail" = 0 ]
