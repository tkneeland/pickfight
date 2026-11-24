#!/bin/bash
# Pace governor (issue #274), zero tokens: plain shell/awk/jq over the usage snapshot, never an LLM call.
# Goal: use this machine's 5h window in exactly 5 hours (not 1-2 h and then dead, not under budget), without blowing the 7d cap.
#   hive-pace.sh [state]   prints AHEAD | ON_PACE | BEHIND
#       elapsed5 = (5h - (r5 - now)) / 5h; the target is used5 ~= elapsed5 x 100
#       AHEAD   used5 > target + PACE_MARGIN (the tuned knob, 5..20, default 10; or the weekly guard below): start no new workers; prefer cheap work
#       BEHIND  used5 < target - PACE_BEHIND_MARGIN (fixed, default 10), or no 5h window yet (r5 = 1970 / past): start another worker, up to MAX_WORKERS
#       ON_PACE otherwise: keep the current number of workers
#       Weekly guard (wins over the 5h pace), with stop = the account's weekly stop % (100 - MIN_WEEKLY_REMAINING_FOR_TICKETS, set in
#       the hub): used7 > elapsed7 x stop + 5, or used7 at the stop, outside the RESET_GRACE_HOURS before the reset -> AHEAD; and
#       used7 at 100% before the reset -> AHEAD even inside that window (hive_weekly_stopped).
#       Missing, unreadable or stale (> PACE_STALE_SECS, default 1800) snapshot -> ON_PACE (never start a burst on bad data).
#   hive-pace.sh start     same output as state, but refused (exit 1) in a control-panel session (issue #300): run it before every worker start
#   hive-pace.sh target    the 5h target percent now (elapsed5 x 100, rounded), empty when there is no window or no fresh snapshot
#   hive-pace.sh explain   one line with every number behind the state
#   hive-pace.sh max       the effective max workers: this account's max_workers (hive/account-limits.conf, set in the hub; else the conf's
#                          MAX_WORKERS, default 3) is the ceiling, and pace-tuning.conf may only lower it
#   hive-pace.sh log       one beacon tick: appends a row to $HIVE_STATE/pace-log.csv (epoch,used5,elapsed5,used7,elapsed7,agents,
#                          pace_state,ready_tickets; header row first; rows older than 60 days pruned on write; at most one row per
#                          minute), and when the 5h window has rolled over closes it with one row in $HIVE_STATE/pace-windows.csv
#                          (window_start,final_used5,minutes_to_100,idle_min_with_ready_work,margin,max_workers) and runs `tune`.
#                          Args: <agents> [ready_tickets]; ready_tickets defaults to the status cache (no GitHub poll).
#   hive-pace.sh tune      once per window close, from the last 10 windows (needs 3+): if most hit 100% before minute 270, tighten
#                          one knob (max_workers -1, else margin -5); if most closed under 90% while ready work sat idle (idle_min > 0),
#                          loosen one knob (max_workers +1, else margin +5). One change per window, margin 5..20, max_workers 1..ceiling,
#                          written to $HIVE_STATE/pace-tuning.conf (local, never committed).
#   hive-pace.sh lastwin   "<final_used5> <idle_min>" of the newest closed window (for the beacon); empty when none
#   hive-pace.sh statewin  `state` then `lastwin` (one line each) from one process; hive-beacon.sh calls it to save two spawns
#   hive-pace.sh report    per-account table (5h used, pace, last window final used5 and idle minutes, beacon age) from the newest
#                          USAGE line of each account in the channel inbox
# Settings: PACE_MARGIN (default 10), MAX_WORKERS (the ceiling, default 3), PACE_STALE_SECS. HIVE_NOW overrides now (tests).
_s=$0; case $_s in */*) _s=${_s%/*}; [ -n "$_s" ] || _s=/;; *) _s=.;; esac
# HIVE_PACE_LIB=1: sourced by hive-beacon.sh in a subshell (hive-env.sh is already loaded there): only the functions are defined, so
# a beacon tick does not start two more bash processes (issue #338)
[ -n "${HIVE_PACE_LIB:-}" ] || . "$_s/hive-env.sh" || exit 1
now=${HIVE_NOW:-$(date -u +%s)}
snap=$HIVE_STATE/usage-snapshot.json
PLOG=$HIVE_STATE/pace-log.csv; PWIN=$HIVE_STATE/pace-windows.csv; PTUNE=$HIVE_STATE/pace-tuning.conf; PCUR=$HIVE_STATE/.pace-window
WIN5=18000; WIN7=604800
: "${PACE_MARGIN:=10}" "${PACE_BEHIND_MARGIN:=10}" "${PACE_STALE_SECS:=1800}"
: "${MAX_WORKERS:=3}"
isnum() { case $1 in ''|*[!0-9]*) return 1;; esac; return 0; }
# the local tuning override: only the two known keys, numbers only (never sourced)
# tv <KEY>: sets TVV to the key's last numeric value (no subshell, no sed|tail; issue #338); fails when there is none
tv() { local l; TVV=""
  [ -r "$PTUNE" ] && while IFS= read -r l || [ -n "$l" ]; do case $l in "$1="[0-9]*) TVV=${l#*=}; TVV=${TVV%%[!0-9]*};; esac; done < "$PTUNE"
  [ -n "$TVV" ]; }
# MAX_CEIL: the studio's (or the conf's) max workers, 1..6; the tuned value may only lower it
isnum "$MAX_WORKERS" || MAX_WORKERS=3
[ "$MAX_WORKERS" -lt 1 ] && MAX_WORKERS=1; [ "$MAX_WORKERS" -gt 6 ] && MAX_WORKERS=6
MAX_CEIL=$MAX_WORKERS
tuned_max() { tv MAX_WORKERS && [ "$TVV" -ge 1 ] && { MAX_WORKERS=$TVV; [ "$MAX_WORKERS" -gt "$MAX_CEIL" ] && MAX_WORKERS=$MAX_CEIL; }; return 0; }
tv PACE_MARGIN && PACE_MARGIN=$TVV
tuned_max
isnum "$PACE_MARGIN" || PACE_MARGIN=10

# read_snap: sets s_ok (1 = fresh and readable), u5 r5 u7 r7 (integers, empty when unknown) and s_age
read_snap() {
  s_ok=0; u5=""; r5=""; u7=""; r7=""; s_age=""
  [ -s "$snap" ] || return 0
  local mt line; mt=$(hive_mtime "$snap") || return 0; isnum "$mt" || return 0
  s_age=$(( now - mt ))
  [ "$s_age" -gt "$PACE_STALE_SECS" ] && return 0
  line=$(jq -r 'def n: if type=="number" then floor else "-" end;
    [(.rate_limits.five_hour.used_percentage|n), (.rate_limits.five_hour.resets_at|n),
     (.rate_limits.seven_day.used_percentage|n), (.rate_limits.seven_day.resets_at|n)] | join(" ")' "$snap" 2>/dev/null) || return 0
  read -r u5 r5 u7 r7 <<EOT
$line
EOT
  [ "$u5" = - ] && u5=""; [ "$r5" = - ] && r5=""; [ "$u7" = - ] && u7=""; [ "$r7" = - ] && r7=""
  [ -z "$r5" ] && [ -z "$u5" ] && return 0     # no five_hour data at all (status line before its first API response): not a window
  [ -n "$r5" ] && [ "$r5" -le 86400 ] && r5=""    # 1970: no 5h window started yet
  [ -n "$r7" ] && [ "$r7" -le 86400 ] && r7=""
  s_ok=1
}
# compute: sets state, e5 e7 (3-decimal fractions of the 5h / 7d window gone, or empty when the reset is unknown or past), tgt
# (integer target % or empty). One awk call does the arithmetic of what used to be five (issue #338): same formulas and rounding.
compute() {
  state=ON_PACE; e5=""; e7=""; tgt=""
  read_snap; [ "$s_ok" = 1 ] || return 0
  # no 5h window yet, or it is over: BEHIND (nothing used, so catch up). Window but no percentage: the 5h pace cannot be judged
  # (the weekly guard below still applies). PACE_MARGIN is the AHEAD margin (the knob the tuner moves); BEHIND uses its own fixed margin.
  local wk
  read -r e5 e7 tgt state wk <<EOT
$(awk -v r5="$r5" -v r7="$r7" -v n="$now" -v u5="$u5" -v u7="$u7" -v m="$PACE_MARGIN" -v b="$PACE_BEHIND_MARGIN" -v w5=$WIN5 -v w7=$WIN7 \
      -v ws=$(( 100 - ${MIN_WEEKLY_REMAINING_FOR_TICKETS:-0} )) -v g=$(( ${RESET_GRACE_HOURS:-24} * 3600 )) '
  function el(r, w,   e) { if (r == "" || r + 0 <= n + 0) return ""; e = (w - (r - n)) / w; if (e < 0) e = 0; if (e > 1) e = 1; return sprintf("%.3f", e) }
  BEGIN { e5 = el(r5, w5); e7 = el(r7, w7); tgt = ""; st = "ON_PACE"
    if (e5 == "") st = "BEHIND"
    else { tgt = sprintf("%d", e5 * 100 + 0.5)
      if (u5 != "") { t = e5 * 100; if (u5 + 0 > t + m) st = "AHEAD"; else if (u5 + 0 < t - b) st = "BEHIND"; else st = "ON_PACE" } }
    wk = (u7 != "" && e7 != "" && r7 - n > g && u7 + 0 > e7 * ws + 5) ? 1 : 0
    print (e5 == "" ? "-" : e5), (e7 == "" ? "-" : e7), (tgt == "" ? "-" : tgt), st, wk }')
EOT
  [ "$e5" = - ] && e5=""; [ "$e7" = - ] && e7=""; [ "$tgt" = - ] && tgt=""
  # weekly guard: the weekly pace wins over the 5h pace. The on-pace line is elapsed7 x the weekly stop (+5), and neither it nor
  # the stop applies in the reset grace window (that window spends what is left); 100% always does.
  if [ -n "$u7" ]; then
    [ "$wk" = 1 ] && state=AHEAD
    hive_weekly_stopped "$u7" "$r7" "${MIN_WEEKLY_REMAINING_FOR_TICKETS:-0}" && state=AHEAD
  fi
  return 0
}

# ready tickets from the status line's cache (hive-status-refresh.sh wrote it; never a GitHub call): "ready me N" or "ready N"
ready_cached() {
  local n l=""; { read -r l; } 2>/dev/null < "$HIVE_STATE/status-cache.txt"
  case $l in *"ready me "*) n=${l#*ready me };; *"ready "*) n=${l#*ready };; esac
  n=${n%%[!0-9]*}
  isnum "$n" && echo "$n" || echo 0
}
prune_log() {   # drop rows older than 60 days, only when the oldest data row is old (no rewrite per tick)
  local cut=$(( now - 60 * 86400 )) first
  { read -r first; read -r first; } < "$PLOG"; first=${first%%,*}; isnum "$first" && [ "$first" -ge "$cut" ] && return 0
  awk -F, -v c="$cut" 'NR == 1 || $1 + 0 >= c' "$PLOG" > "$PLOG.tmp.$$" && mv "$PLOG.tmp.$$" "$PLOG" || rm -f "$PLOG.tmp.$$"
}
# close_window <window_start> <window_end> <margin> <max_workers>: summarises the log rows of that window into one pace-windows.csv row
close_window() {
  local ws=$1 we=$2 mg=$3 mw=$4 res
  [ -f "$PWIN" ] || echo "window_start,final_used5,minutes_to_100,idle_min_with_ready_work,margin,max_workers" > "$PWIN"
  grep -q "^$ws," "$PWIN" && return 0
  res=$(awk -F, -v ws="$ws" -v we="$we" 'NR > 1 && $1 + 0 >= ws && $1 + 0 <= we {
      if ($2 != "" && $2 + 0 > fin) fin = $2 + 0
      if ($2 != "" && $2 + 0 >= 100 && !hit) hit = $1 + 0
      if (have) { d = $1 - pe; if (d > 900) d = 900; if (pa == 0 && pr > 0) idle += d }
      have = 1; pe = $1 + 0; pa = $6 + 0; pr = $8 + 0 }
    END { printf "%d,%s,%d", fin, (hit ? int((hit - ws) / 60) : ""), int(idle / 60 + 0.5) }' "$PLOG" 2>/dev/null) || return 0
  [ -n "$res" ] || return 0
  echo "$ws,$res,$mg,$mw" >> "$PWIN"
}
cmd_tune() {
  [ -s "$PWIN" ] || return 0
  local last t0 n hit under mg mw new what
  last=$(tail -n 1 "$PWIN" | cut -d, -f1); isnum "$last" || return 0
  tv PACE_TUNED_WINDOW; [ "$TVV" = "$last" ] && return 0     # one change per window
  read -r n hit under <<EOT
$(tail -n 10 "$PWIN" | awk -F, '$1 ~ /^[0-9]+$/ { n++; if ($3 != "" && $3 + 0 < 270) hit++; if ($2 + 0 < 90 && $4 + 0 > 0) under++ } END { print n + 0, hit + 0, under + 0 }')
EOT
  mg=$PACE_MARGIN; mw=$MAX_WORKERS; what=none
  if [ "$n" -ge 3 ]; then
    if [ $(( hit * 2 )) -gt "$n" ]; then          # most windows hit 100% early: tighten one knob
      if [ "$mw" -gt 1 ]; then mw=$(( mw - 1 )); what="max_workers-1"; elif [ "$mg" -gt 5 ]; then mg=$(( mg - 5 )); what="margin-5"; fi
    elif [ $(( under * 2 )) -gt "$n" ]; then      # most closed under 90% with ready work idle: loosen one knob
      if [ "$mw" -lt "$MAX_CEIL" ]; then mw=$(( mw + 1 )); what="max_workers+1"; elif [ "$mg" -lt 20 ]; then mg=$(( mg + 5 )); what="margin+5"; fi
    fi
  fi
  [ "$mg" -lt 5 ] && mg=5; [ "$mg" -gt 20 ] && mg=20
  { echo "# local per-machine pace tuning (hive-pace.sh tune); never committed"
    echo "PACE_MARGIN=$mg"; echo "MAX_WORKERS=$mw"; echo "PACE_TUNED_WINDOW=$last"; echo "# last change: $what"; } > "$PTUNE.tmp.$$" && mv "$PTUNE.tmp.$$" "$PTUNE"
  echo "tune: $what (margin $mg, max_workers $mw, $n windows)"
}
cmd_log() {
  local ag=${1:-0} rdy=${2:-} cur=0 row sr5 smg smw d v
  isnum "$ag" || ag=0
  [ -n "$rdy" ] || rdy=$(ready_cached)
  compute; [ "$s_ok" = 1 ] || return 0
  [ -f "$PLOG" ] || echo "epoch,used5,elapsed5,used7,elapsed7,agents,pace_state,ready_tickets" > "$PLOG"
  # window rollover: the stored window's reset moved (by over 5 min; the status line and the usage endpoint disagree by seconds)
  [ -n "$r5" ] && cur=$r5
  if [ -f "$PCUR" ] && read -r sr5 smg smw < "$PCUR" && isnum "$sr5"; then
    d=$(( cur - sr5 )); [ $d -lt 0 ] && d=$(( -d ))
    if [ "$d" -gt 300 ] && [ "$now" -ge $(( sr5 - 300 )) ]; then
      close_window $(( sr5 - WIN5 )) "$sr5" "${smg:-$PACE_MARGIN}" "${smw:-$MAX_WORKERS}"
      rm -f "$PCUR"; cmd_tune >/dev/null
      tv PACE_MARGIN && PACE_MARGIN=$TVV; tuned_max
    fi
  fi
  [ -f "$PCUR" ] || { [ "$cur" -gt "$now" ] && echo "$cur $PACE_MARGIN $MAX_WORKERS" > "$PCUR"; }
  # at most one row per minute (the status line and the supervisor both tick)
  row=$(tail -n 1 "$PLOG"); row=${row%%,*}
  if ! { isnum "$row" && [ $(( now - row )) -lt 60 ]; }; then
    echo "$now,$u5,${e5},$u7,${e7},$ag,$state,$rdy" >> "$PLOG"
  fi
  prune_log
  return 0
}
cmd_report() {
  [ -s "$HIVE_INBOX" ] || { echo "no channel inbox ($HIVE_INBOX): nothing to report"; return 0; }
  printf '%-18s %6s %-8s %10s %9s %s\n' account 5h pace final5 idle_min beacon
  awk -F'|' '$3 == "USAGE" && $1 + 0 >= m[$2] { m[$2] = $1 + 0; l[$2] = $4 } END { for (a in l) print a "|" m[a] "|" l[a] }' "$HIVE_INBOX" | sort |
  while IFS='|' read -r a e rest; do
    p5=${rest%%%*}; ps=$(echo "$rest" | sed -n 's/.* pace=\([A-Z_]*\).*/\1/p')
    fw=$(echo "$rest" | sed -n 's/.* win5=\([0-9]*\).*/\1/p'); im=$(echo "$rest" | sed -n 's/.* idle=\([0-9]*\).*/\1/p')
    ag=$(( now - ${e%.*} ))
    printf '%-18s %6s %-8s %10s %9s %s\n' "$a" "${p5:-?}%" "${ps:--}" "${fw:--}" "${im:--}" "$([ "$ag" -ge 3600 ] && echo "$((ag / 3600))h old" || echo "$((ag / 60))m old")"
  done
}
cmd_statewin() {   # state, then lastwin (one line each)
  compute; echo "$state"; [ -s "$PWIN" ] && tail -n 1 "$PWIN" | awk -F, '$1 ~ /^[0-9]+$/ { print $2, $4 }'; return 0
}
[ -n "${HIVE_PACE_LIB:-}" ] && return 0
case ${1:-state} in
  state) compute; echo "$state";;
  start) hive_guard worker-start || exit 1; compute; echo "$state";;
  target) compute; echo "$tgt";;
  explain) compute; echo "$state used5=${u5:-?} target=${tgt:-?} margin=$PACE_MARGIN used7=${u7:-?} elapsed7=${e7:-?} max_workers=$MAX_WORKERS snapshot=$([ "$s_ok" = 1 ] && echo fresh || echo "missing-or-stale")";;
  max) echo "$MAX_WORKERS";;
  log) shift; cmd_log "$@";;
  tune) cmd_tune;;
  statewin) cmd_statewin;;   # state, then lastwin: one call for the beacon (issue #338)
  lastwin) [ -s "$PWIN" ] && tail -n 1 "$PWIN" | awk -F, '$1 ~ /^[0-9]+$/ { print $2, $4 }';;
  report) cmd_report;;
  *) echo "usage: hive-pace.sh [state|start|target|explain|max|log <agents> [ready]|tune|lastwin|statewin|report]" >&2; exit 2;;
esac
