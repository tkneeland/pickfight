#!/bin/bash
# The dev-channel text for a DEV_IDLE wake (docs/agents/hive.md rule 21).
#   hive-dev-idle-alert.sh <account> <idle minutes> "<what waits, e.g. #1240, PR #1241>" [--post]
# Prints the message; --post sends it to the private dev channel (DISCORD_DEV_CHANNEL) through hive-discord.sh post. The dev
# is written as <@id> when this machine's $HIVE_STATE/discord.conf has HIVE_DISCORD_ID_<account>=<discord user id> (account
# non-alphanumerics become _; never committed), else by name only (DISPLAY_NAME in the account conf, else the handle). That
# same line is the one opt-in: hive-discord.sh post lets only HIVE_DISCORD_ID_* ids ping. At 120 minutes or more the
# message offers to reassign the account's unclaimed tickets.
. "$(dirname "$0")/hive-env.sh" || exit 1
. "$HIVE_DIR/hive-discord-env.sh"
acct=${1:-}; mins=${2:-}; what=${3:-}
case $mins in ''|*[!0-9]*) echo "usage: hive-dev-idle-alert.sh <account> <idle minutes> \"<what waits>\" [--post]" >&2; exit 2;; esac
[ -n "$acct" ] && [ -n "$what" ] || { echo "usage: hive-dev-idle-alert.sh <account> <idle minutes> \"<what waits>\" [--post]" >&2; exit 2; }
who=$(hive_display_name "$acct")
id=$(hive_discord_id_of "$acct"); [ -n "$id" ] && who="<@$id> $who"
if [ "$mins" -ge 60 ]; then t="$((mins / 60))h$(printf %02d $((mins % 60)))m"; else t="${mins}m"; fi
# the reassignment offer goes before the list of what waits, so post's 1990-character cut never drops it
msg="$who: your Claude session has been idle for $t."
[ "$mins" -ge 120 ] && msg="$msg Want me to reassign your unclaimed tickets? Say yes and I will."
msg="$msg Work is waiting on you: ${what:0:600}. Reply here if you are away on purpose."
printf '%s\n' "$msg"
[ "${4:-}" = --post ] || exit 0
# Not configured (Discord off, no token, or no dev channel): a permanent config error, so exit 2 like hive-discord.sh and keep
# the throttle stamp; the normal 2 h / stage-2 cadence applies instead of waking DEV_IDLE every poll. Only a failed post
# (below, exit 1) clears it.
hive_discord_need_token hive-dev-idle-alert
[ -n "$HIVE_DISCORD_DEV" ] || { echo "hive-dev-idle-alert: no DISCORD_DEV_CHANNEL in hive.conf; not posted, throttle kept" >&2; exit 2; }
bash "${HIVE_DISCORD_SH:-$HIVE_DIR/hive-discord.sh}" post "$HIVE_DISCORD_DEV" "$msg" >/dev/null || { rm -f "$HIVE_STATE/.dev-idle-$acct"; echo "hive-dev-idle-alert: post failed; throttle cleared so the next poll wakes again" >&2; exit 1; }
exit 0
