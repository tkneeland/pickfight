#!/bin/bash
# The #hive text for a DEV_IDLE wake (autotriage.md rule 21, #1233).
#   pf-dev-idle-alert.sh <account> <idle minutes> "<what waits, e.g. #1240, PR #1241>" [--post]
# Prints the message; --post sends it to #hive through pf-discord.sh post. The dev is written as <@id> when this machine's
# $PF_STATE/pf-discord.conf has PF_DISCORD_ID_<account>=<discord user id> (account non-alphanumerics become _; never
# committed), else by name only. The id pings only when it is also in the conf's PF_DISCORD_PING_IDS (pf-discord.sh post
# allows only those, #1237). At 120 minutes or more the message offers to reassign the account's unclaimed tickets.
. "$(dirname "$0")/pf-env.sh" || exit 1
. "$PF_DIR/pf-discord-env.sh"
acct=${1:-}; mins=${2:-}; what=${3:-}
case $mins in ''|*[!0-9]*) echo "usage: pf-dev-idle-alert.sh <account> <idle minutes> \"<what waits>\" [--post]" >&2; exit 2;; esac
[ -n "$acct" ] && [ -n "$what" ] || { echo "usage: pf-dev-idle-alert.sh <account> <idle minutes> \"<what waits>\" [--post]" >&2; exit 2; }
case $acct in schans2) nm=Sam;; agage-JG) nm=Austin;; tkneeland|tommykneeland) nm=Tommy;; *) nm=$acct;; esac
key=$(printf '%s' "$acct" | tr -c 'A-Za-z0-9' _)
id=$(pf_discord_conf "PF_DISCORD_ID_$key"); case $id in *[!0-9]*) id="";; esac
who="$nm ($acct)"; [ -n "$id" ] && who="<@$id> $who"
if [ "$mins" -ge 60 ]; then t="$((mins / 60))h$(printf %02d $((mins % 60)))m"; else t="${mins}m"; fi
msg="$who: your Claude session has been idle for $t and work is waiting on you: $what. Reply here if you are away on purpose."
[ "$mins" -ge 120 ] && msg="$msg Want me to reassign your unclaimed tickets? Say yes and I will."
printf '%s\n' "$msg"
[ "${4:-}" = --post ] && bash "${PF_DISCORD_SH:-$PF_DIR/pf-discord.sh}" post "$PF_DISCORD_DEV" "$msg"
exit 0
