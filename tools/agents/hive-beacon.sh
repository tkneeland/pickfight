#!/bin/bash
# Sends this account's usage beacon, in the foreground, when it is due: a USAGE message on the private channel (hive-msg.sh),
# the only usage beacon (nothing is posted on GitHub). Built from $HIVE_STATE/usage-snapshot.json (saved by statusline.sh or
# hive-usage.sh). Format: "<5h>% <7d>% <7d reset ISO> r5=<5h reset ISO> agents=<n> at=<snapshot ISO> [claude_at=<ISO>]".
# pace=<AHEAD|ON_PACE|BEHIND> [win5=<last window's final 5h %> idle=<its idle minutes with ready work>] come from hive-pace.sh (issue #274).
# tmaker=on|off from hive-ticketmaker.sh (the hub shows it). The old mode=AT|MT field is retired (issue #58): whether an
# account works on its own is the studio's in/out switch, which the hub reads itself.
# claude_at = newest Claude transcript write on this account (hive_claude_at), omitted when unknown; the triagemaster wakes
# DEV_IDLE when it is old while work waits.
# Change-only gate (issue #111, the ntfy daily quota): due when the 5h % or the 7d % moved 5 points or more, the 5h reset
# moved (by over 5 min; the status line and the usage endpoint disagree by seconds), or agents= changed since the last USAGE
# sent; else hourly as a keepalive; never within 10 min of the last one. The last sent values are in .usage-last-sent
# ("<epoch> <5h> <7d> <5h reset> <agents>"). Not due: exit 0, sends nothing. HIVE_NOW overrides now (tests).
# Errors go to $HIVE_STATE/beacon.log; exit 1 when a due beacon was not sent. A no-op in SINGLE_ACCOUNT (and PRIVATE) mode.
# Run by statusline.sh, hive-usage.sh, and `windows/hive-supervise.sh beacon`, which outlives the status line: all go
# through this gate, so they only refresh the snapshot as often as they like.
# Fork budget (issue #338): a process spawn costs 6-20 s per call on Git Bash, so this script avoids $(...) in the gate, parses
# the snapshot with one jq call, and gets the pace state and last window from one hive-pace.sh process; its output is unchanged.
_s=$0; case $_s in */*) _s=${_s%/*};; *) _s=.;; esac
. "$_s/hive-env.sh" || exit 1
hive_studio_sync   # the hub's studio settings (ticket limits, in/out and the triagemaster queue), at most every 5 min
[ "$SINGLE_ACCOUNT" = 1 ] && exit 0
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$HIVE_STATE/beacon.log"; }
snap=$HIVE_STATE/usage-snapshot.json
[ -s "$snap" ] || { log "no usage snapshot yet (status line not run?)"; exit 1; }
t=${HIVE_NOW:-}; [ -n "$t" ] || t=$(date -u +%s)
# running worker agents = live worktrees on an issue branch (hive_live_agents; the status line counts them the same way)
agents=0; while read -r _a; do [ -n "$_a" ] && agents=$((agents + 1)); done <<EOT
$(hive_live_agents)
EOT
# Pace telemetry (issue #274, zero tokens): one row per tick in pace-log.csv, and a window close + tuning when the 5h window rolled.
# Runs on every tick, before the send gate and even with no channel, so the log is dense; failures never stop the beacon.
( HIVE_PACE_LIB=1; HIVE_NOW=$t; . "$HIVE_DIR/hive-pace.sh" && cmd_log "$agents" ) >/dev/null 2>>"$HIVE_STATE/beacon.log" || true
[ -f "$HIVE_STATE/msg.conf" ] || { log "no channel configured (hive-msg.sh init); USAGE not sent"; exit 1; }
# one jq call: "<5h> <7d> <5h reset>" and, after a tab, the message head ("<5h>% <7d>% <7d reset ISO> r5=<ISO>"); the snapshot age is added below
cur=$(jq -r '"\(.rate_limits.five_hour.used_percentage // 0|floor) \(.rate_limits.seven_day.used_percentage // 0|floor) \(.rate_limits.five_hour.resets_at // 0|floor)\t\(.rate_limits.five_hour.used_percentage // 0|floor)% \(.rate_limits.seven_day.used_percentage // 0|floor)% \(.rate_limits.seven_day.resets_at // 0|floor|todate) r5=\(.rate_limits.five_hour.resets_at // 0|floor|todate)"' "$snap") \
  || { log "bad snapshot"; exit 1; }
mh=${cur#*$'\t'}; cur=${cur%%$'\t'*}
read -r p5 p7 r5 <<EOT
$cur
EOT
last=$HIVE_STATE/.usage-last-sent
lt=0; l5=0; l7=0; lr=0; la=""
[ -r "$last" ] && read -r lt l5 l7 lr la < "$last"
# num <var>: a non-number becomes 0 (no subshell)
num() { eval "case \${$1:-} in ''|*[!0-9]*) $1=0;; esac"; }
num lt; num l5; num l7; num lr
# absdiff <a> <b>: sets D (no subshell)
absdiff() { D=$(( $1 - $2 )); [ $D -lt 0 ] && D=$(( -D )); return 0; }
age=$(( t - lt ))
[ "$age" -ge 600 ] || exit 0
due=0
[ "$age" -ge 3600 ] && due=1
[ "$agents" != "$la" ] && due=1
if [ $due = 0 ]; then
  absdiff "$p5" "$l5"; [ "$D" -ge 5 ] && due=1
  absdiff "$p7" "$l7"; [ "$D" -ge 5 ] && due=1
  absdiff "$r5" "$lr"; [ "$D" -gt 300 ] && due=1
fi
[ $due = 1 ] || exit 0
# Stamp the beacon with when the snapshot was taken, not now: if the status line stops running, the
# beacon must look stale instead of republishing old numbers as fresh.
sat=$(hive_mtime "$snap"); sat=${sat:-0}
msg="$mh agents=$agents at=$(TZ=UTC hive_fmt "$sat" +%Y-%m-%dT%H:%M:%SZ)"
# pace=<state> and the last closed window's final used5 and idle minutes (win5=, idle=): the triagemaster sees who paces well
pace=$( exec 2>/dev/null; HIVE_PACE_LIB=1; HIVE_NOW=$t; . "$HIVE_DIR/hive-pace.sh" && cmd_statewin ) || pace=ON_PACE
ps=${pace%%$'\n'*}; lw=""; case $pace in *$'\n'*) lw=${pace#*$'\n'};; esac
msg="$msg pace=${ps:-ON_PACE}"
[ -n "$lw" ] && msg="$msg win5=${lw% *} idle=${lw#* }"
ca=$(hive_claude_at)
[ -n "$ca" ] && msg="$msg claude_at=$(TZ=UTC hive_fmt "$ca" +%Y-%m-%dT%H:%M:%SZ)"
msg="$msg tmaker=$(bash "$HIVE_DIR/hive-ticketmaker.sh")"
# hive-msg.sh logs its own failures (budget drop, 429 backoff, HTTP code) to beacon.log
bash "$HIVE_DIR/hive-msg.sh" send USAGE "$msg" >/dev/null 2>>"$HIVE_STATE/beacon.log" || exit 1
echo "$t $p5 $p7 $r5 $agents" > "$last"
