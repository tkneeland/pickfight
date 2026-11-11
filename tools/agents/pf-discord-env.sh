#!/bin/bash
# Sourced by pf-discord.sh and pf-discord-bugs.sh (after pf-env.sh): the bot conf and the one curl wrapper.
# Conf $PF_STATE/pf-discord.conf (never commit it): PF_DISCORD_TOKEN=<bot token>, optional PF_DISCORD_GUILD and
# PF_DISCORD_BUGS_CHANNEL and PF_DISCORD_DEV_CHANNEL. Read without sourcing, tolerating CRLF and quotes (same as pf-msg.sh).
PF_DISCORD_CONF=$PF_STATE/pf-discord.conf
PF_DISCORD_API=https://discord.com/api/v10
PF_DISCORD_DEFAULT_GUILD=1569873613526405190      # the PickFight server
PF_DISCORD_DEFAULT_BUGS=1569876514017779794       # its public #change-requests channel (was #bug-reports; ids survive renames)
PF_DISCORD_DEFAULT_DEV=1569919897591611552        # its private #hive channel (Dev role only)
pf_discord_conf() { [ -f "$PF_DISCORD_CONF" ] && sed -n "s/^$1=//p" "$PF_DISCORD_CONF" | tr -d '\r"'"'"' ' | head -n 1; }
PF_DISCORD_TOKEN=$(pf_discord_conf PF_DISCORD_TOKEN)
PF_DISCORD_GUILD=$(pf_discord_conf PF_DISCORD_GUILD); PF_DISCORD_GUILD=${PF_DISCORD_GUILD:-$PF_DISCORD_DEFAULT_GUILD}
PF_DISCORD_BUGS=$(pf_discord_conf PF_DISCORD_BUGS_CHANNEL); PF_DISCORD_BUGS=${PF_DISCORD_BUGS:-$PF_DISCORD_DEFAULT_BUGS}
PF_DISCORD_DEV=$(pf_discord_conf PF_DISCORD_DEV_CHANNEL); PF_DISCORD_DEV=${PF_DISCORD_DEV:-$PF_DISCORD_DEFAULT_DEV}
# dcurl <path> [curl args]: the token goes in on stdin (`curl -K -`), never in argv where `ps` shows it.
dcurl() { local path=$1 t=${PF_DISCORD_TIMEOUT:-15} a; shift
  for a in "$@"; do [ "$a" = -X ] && t=${PF_DISCORD_WRITE_TIMEOUT:-45}; done   # reads and polls 15 s; a write gets longer so a slow post is not retried into a duplicate
  printf 'header = "Authorization: Bot %s"\nurl = "%s%s"\n' "$PF_DISCORD_TOKEN" "$PF_DISCORD_API" "$path" | curl -s -m "$t" -K - "$@"; }
pf_discord_need_token() { [ -n "$PF_DISCORD_TOKEN" ] || { echo "$1: no PF_DISCORD_TOKEN in $PF_DISCORD_CONF (ask the owner for the bot token)" >&2; exit 2; }; }
# pf_discord_mentions <text>: the allowed_mentions JSON for a post. Pings only users written as <@id> in the text who are
# also listed in the conf's PF_DISCORD_PING_IDS (comma-separated, devs who asked to be pinged; kept out of the public repo).
# Ids quoted from untrusted reports never ping; @everyone and roles never do.
PF_DISCORD_PING_IDS=$(pf_discord_conf PF_DISCORD_PING_IDS)
pf_discord_mentions() { jq -nc --arg t "$1" --arg ok "$PF_DISCORD_PING_IDS" \
  '($ok | split(",") | map(select(length > 0))) as $ok | {parse: [], users: ([$t | scan("<@!?([0-9]+)>") | .[0]] | unique | map(select(. as $i | $ok | index($i))))}'; }
