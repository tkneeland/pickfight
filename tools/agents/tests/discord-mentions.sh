#!/bin/bash
# hive_discord_mentions: only allowlisted <@id>s ping; no mentions -> users []. Run: bash tools/agents/tests/discord-mentions.sh
D=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
HIVE_STATE=$T; printf 'HIVE_DISCORD_TOKEN=x\nHIVE_DISCORD_ID_carol=111\nHIVE_DISCORD_ID_bob=222\n' > "$T/discord.conf"
. "$D/hive-discord-env.sh"; f=0
chk() { [ "$(hive_discord_mentions "$1")" = "$2" ] && echo "PASS $3" || { echo "FAIL $3: $(hive_discord_mentions "$1")"; f=1; }; }
chk 'hi <@111> and <@!222>' '{"parse":[],"users":["111","222"]}' 'allowlisted ids ping'
chk 'quoted <@999> @everyone' '{"parse":[],"users":[]}' 'unlisted id and everyone never ping'
chk 'plain text' '{"parse":[],"users":[]}' 'no mentions'
printf 'HIVE_DISCORD_TOKEN=x\n' > "$T/discord.conf"; . "$D/hive-discord-env.sh"
chk 'hi <@111>' '{"parse":[],"users":[]}' 'no allowlist pings nobody'
exit $f
