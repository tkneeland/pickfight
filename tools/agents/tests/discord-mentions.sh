#!/bin/bash
# pf_discord_mentions: only allowlisted <@id>s ping; no mentions -> users []. Run: bash tools/agents/tests/discord-mentions.sh
D=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PF_STATE=$T; printf 'PF_DISCORD_TOKEN=x\nPF_DISCORD_ID_schans2=111\nPF_DISCORD_ID_agage_JG=222\n' > "$T/pf-discord.conf"
. "$D/pf-discord-env.sh"; f=0
chk() { [ "$(pf_discord_mentions "$1")" = "$2" ] && echo "PASS $3" || { echo "FAIL $3: $(pf_discord_mentions "$1")"; f=1; }; }
chk 'hi <@111> and <@!222>' '{"parse":[],"users":["111","222"]}' 'allowlisted ids ping'
chk 'quoted <@999> @everyone' '{"parse":[],"users":[]}' 'unlisted id and everyone never ping'
chk 'plain text' '{"parse":[],"users":[]}' 'no mentions'
printf 'PF_DISCORD_TOKEN=x\n' > "$T/pf-discord.conf"; . "$D/pf-discord-env.sh"
chk 'hi <@111>' '{"parse":[],"users":[]}' 'no allowlist pings nobody'
exit $f
