#!/bin/bash
# The #hive text for a DEV_IDLE wake (autotriage.md rule 21, #1233).
#   pf-dev-idle-alert.sh <account> <idle minutes> "<what waits, e.g. #1240, PR #1241>" [--post]
# Prints the message; --post sends it to #hive through pf-discord.sh post. The dev is written as <@id> when this machine's
# $PF_STATE/pf-discord.conf has PF_DISCORD_ID_<account>=<discord user id> (account non-alphanumerics become _; never
# committed), else by name only. That same line is the one opt-in: pf-discord.sh post lets only PF_DISCORD_ID_* ids ping (#1237). At 120 minutes or more the message offers to reassign the account's unclaimed tickets.
. "$(dirname "$0")/pf-env.sh" || exit 1
. "$PF_DIR/pf-discord-env.sh"
acct=${1:-}; mins=${2:-}; what=${3:-}
case $mins in ''|*[!0-9]*) echo "usage: pf-dev-idle-alert.sh <account> <idle minutes> \"<what waits>\" [--post]" >&2; exit 2;; esac
[ -n "$acct" ] && [ -n "$what" ] || { echo "usage: pf-dev-idle-alert.sh <account> <idle minutes> \"<what waits>\" [--post]" >&2; exit 2; }
mins=$((10#$mins))   # base 10: 08 and 09 are not octal
lbl=$acct
case $acct in schans2) nm=Sam;; agage-JG) nm=Austin;; tkneeland) nm=Tommy;; tommykneeland) nm=Tommy; lbl="reserve, tommykneeland";; *) nm=$acct;; esac
key=$(printf '%s' "$acct" | tr -c 'A-Za-z0-9' _)
id=$(pf_discord_conf "PF_DISCORD_ID_$key"); case $id in *[!0-9]*) id="";; esac
who="$nm ($lbl)"; [ -n "$id" ] && who="<@$id> $who"
if [ "$mins" -ge 60 ]; then t="$((mins / 60))h$(printf %02d $((mins % 60)))m"; else t="${mins}m"; fi
# the reassignment offer goes before the list of what waits, so post's 1990-character cut never drops it
msg="$who: your Claude session has been idle for $t."
[ "$mins" -ge 120 ] && msg="$msg Want me to reassign your unclaimed tickets? Say yes and I will."
msg="$msg Work is waiting on you: ${what:0:600}. Reply here if you are away on purpose."
printf '%s\n' "$msg"
[ "${4:-}" = --post ] || exit 0
bash "${PF_DISCORD_SH:-$PF_DIR/pf-discord.sh}" post "$PF_DISCORD_DEV" "$msg" >/dev/null || { echo "0 0 $(( $(date +%s) + 600 ))" > "$PF_STATE/.dev-idle-$acct"; echo "pf-dev-idle-alert: post failed; the next DEV_IDLE wake retries in 10 min" >&2; exit 1; }
exit 0
