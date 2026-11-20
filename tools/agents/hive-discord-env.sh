#!/bin/bash
# Sourced by hive-discord.sh, hive-discord-bugs.sh and hive-dev-idle-alert.sh (after hive-env.sh): the bot conf and the one
# curl wrapper. Discord is on only with DISCORD=1 in hive.conf (never in PRIVATE mode).
# Secrets live in $HIVE_STATE/discord.conf (per account and machine, never committed): HIVE_DISCORD_TOKEN=<bot token> and
# HIVE_DISCORD_ID_<account>=<discord user id>, one per dev who opted in to pings (account non-alphanumerics become _).
# The server and channel ids are not secret: DISCORD_GUILD, DISCORD_BUGS_CHANNEL and DISCORD_DEV_CHANNEL in hive.conf; the
# same keys prefixed HIVE_ in discord.conf override them for one machine. Read without sourcing, tolerating CRLF and quotes.
HIVE_DISCORD_CONF=$HIVE_STATE/discord.conf
HIVE_DISCORD_API=${HIVE_DISCORD_API:-https://discord.com/api/v10}
hive_discord_conf() { [ -f "$HIVE_DISCORD_CONF" ] && sed -n "s/^$1=//p" "$HIVE_DISCORD_CONF" | tr -d '\r"'"'"' ' | head -n 1; }
HIVE_DISCORD_TOKEN=$(hive_discord_conf HIVE_DISCORD_TOKEN)
HIVE_DISCORD_GUILD=$(hive_discord_conf HIVE_DISCORD_GUILD); HIVE_DISCORD_GUILD=${HIVE_DISCORD_GUILD:-${DISCORD_GUILD:-}}
HIVE_DISCORD_BUGS=$(hive_discord_conf HIVE_DISCORD_BUGS_CHANNEL); HIVE_DISCORD_BUGS=${HIVE_DISCORD_BUGS:-${DISCORD_BUGS_CHANNEL:-}}
HIVE_DISCORD_DEV=$(hive_discord_conf HIVE_DISCORD_DEV_CHANNEL); HIVE_DISCORD_DEV=${HIVE_DISCORD_DEV:-${DISCORD_DEV_CHANNEL:-}}
# dcurl <path> [curl args]: the token goes in on stdin (`curl -K -`), never in argv where `ps` shows it.
dcurl() { local path=$1 t=${HIVE_DISCORD_TIMEOUT:-15} a; shift
  for a in "$@"; do [ "$a" = -X ] && t=${HIVE_DISCORD_WRITE_TIMEOUT:-45}; done   # reads and polls 15 s; a write gets longer so a slow post is not retried into a duplicate
  printf 'header = "Authorization: Bot %s"\nurl = "%s%s"\n' "$HIVE_DISCORD_TOKEN" "$HIVE_DISCORD_API" "$path" | curl -s -m "$t" -K - "$@"; }
# hive_discord_on: 0 when Discord may be used at all (DISCORD=1, not private, a token)
hive_discord_on() { [ "${DISCORD:-0}" = 1 ] && [ "${PRIVATE:-0}" != 1 ] && [ -n "$HIVE_DISCORD_TOKEN" ]; }
hive_discord_need_token() {
  { [ "${DISCORD:-0}" = 1 ] && [ "${PRIVATE:-0}" != 1 ]; } || { echo "$1: Discord is off (DISCORD=1 in hive.conf turns it on; never in PRIVATE mode)" >&2; exit 2; }
  [ -n "$HIVE_DISCORD_TOKEN" ] || { echo "$1: no HIVE_DISCORD_TOKEN in $HIVE_DISCORD_CONF (ask the owner for the bot token)" >&2; exit 2; }; }
# hive_discord_mentions <text>: the allowed_mentions JSON for a post. Pings only users written as <@id> in the text who are
# also the value of a HIVE_DISCORD_ID_<account> line in the conf (the one opt-in per dev; kept out of the repo).
# Ids quoted from untrusted reports never ping; @everyone and roles never do.
hive_discord_ping_ids() { [ -f "$HIVE_DISCORD_CONF" ] && sed -n 's/^HIVE_DISCORD_ID_[A-Za-z0-9_]*=//p' "$HIVE_DISCORD_CONF" | tr -d '\r"'"'"' ' | tr '\n' ,; }
hive_discord_mentions() { jq -nc --arg t "$1" --arg ok "$(hive_discord_ping_ids)" \
  '($ok | split(",") | map(select(length > 0))) as $ok | {parse: [], users: ([$t | scan("<@!?([0-9]+)>") | .[0]] | unique | map(select(. as $i | $ok | index($i))))}' 2>/dev/null || echo '{"parse":[],"users":[]}'; }
# hive_discord_id_of <account>: that dev's opted-in Discord user id, empty when none or malformed
hive_discord_id_of() { local k id; k=$(printf '%s' "$1" | tr -c 'A-Za-z0-9' _); id=$(hive_discord_conf "HIVE_DISCORD_ID_$k"); case $id in *[!0-9]*) id="";; esac; echo "$id"; }
