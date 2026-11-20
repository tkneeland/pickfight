#!/bin/bash
# Private account-to-account doorbell over an ntfy topic. The channel only nudges; verify everything on GitHub.
#   hive-msg.sh init                  create $HIVE_STATE/msg.conf with a random secret topic (never commit it)
#   hive-msg.sh send <TYPE> <text>    TYPE: CLAIM RELEASE USAGE ASK ANSWER INFO FIRE HELLO TM
#                                   USAGE is the only usage beacon (hive-beacon.sh); TM "<handle> until <reset ISO>" (hive-succession.sh --post)
#   hive-msg.sh claim|release <n>     send CLAIM / RELEASE <n>
#   hive-msg.sh listen                long-lived: appends to msg-inbox.log, writes CLAIM/ASK/FIRE lines to msg-wake.txt, and
#                                   an ANSWER to a hive-ask.sh question that timed out (its [q<id>] in ask-open.txt) too
#   hive-msg.sh backfill              one pass: append the channel's cached last 12h (ntfy poll) to msg-inbox.log, skipping
#                                   lines already there; hive_usage_backfill runs it when the inbox is missing or 6h+ stale
#   hive-msg.sh claimed <n>           exit 0 when another account CLAIMed <n> in the last 24h and has not RELEASEd it
#   hive-msg.sh heartbeat             one pass: send HELLO when this account sent nothing for 60 min; wake (MSG FIRE peer-silent)
#                                   when a peer sent nothing (any type) for 2h+; ASK a peer whose USAGE has no real weekly numbers (7d ? or reset 1970; r5=1970 alone is fine) to
#                                   fix its status line (every 6h at most)
#   hive-msg.sh run                   supervisor: keeps `listen` alive and runs `heartbeat` every 60 s (screen/launchd/systemd;
#                                   windows/hive-supervise.sh msg on Windows). hive-join.sh restarts it when it is down.
#   hive-msg.sh status [line]         writes msg-status.json (state running, the line, and quota: the 429 backoff's until ISO or null)
# One listener and one supervisor per $HIVE_STATE: `listen` holds msg-listen.pid and `run` msg-run.pid (hive_pidlock); a second
# one exits 0 at once.
# Send budget (issue #111; ntfy.sh's free tier allows about 250 messages a day per IP): send counts this account's sends per
# UTC day in .msg-count. Once 70% of HIVE_MSG_DAILY_MAX (default 100) is used, USAGE, HELLO and INFO are dropped (exit 4,
# logged to beacon.log); CLAIM, RELEASE, ASK, ANSWER, FIRE and TM always go out. On HTTP 429 sends stop until now +
# retry-after (.msg-backoff-until, exit 3, logged once); other failures are logged with their HTTP code (exit 1).
# Conf $HIVE_STATE/msg.conf: HIVE_MSG_TOPIC=..., optional HIVE_MSG_SERVER (default https://ntfy.sh), optional HIVE_MSG_TOKEN
# (an ntfy access token, sent as Authorization: Bearer through the curl config on stdin, for a paid tier or a self-hosted
# server). Off in SINGLE_ACCOUNT (and so PRIVATE) mode: nothing is sent or read.
# Env: HIVE_NOW (epoch override for tests), HIVE_MSG_NOSEND=1 (heartbeat sends nothing), HIVE_MSG_DAILY_MAX.
_s=$0; case $_s in */*) _s=${_s%/*}; [ -n "$_s" ] || _s=/;; *) _s=.;; esac
. "$_s/hive-env.sh" || exit 1
CONF=$HIVE_STATE/msg.conf
INBOX=$HIVE_STATE/msg-inbox.log
WAKE=$HIVE_STATE/msg-wake.txt
ASK_OPEN=$HIVE_STATE/ask-open.txt
# ask_for_me <rest-of-ASK>: true for a broadcast (no leading @) or an ASK addressed @<me> followed by end, space, : or ,
ask_for_me() { case $1 in "@$HIVE_ACCOUNT"|"@$HIVE_ACCOUNT"[\ :,]*) return 0;; @*) return 1;; esac; return 0; }
# 0 when <answer text> starts with the [q<id>] of a hive-ask.sh question from <account> that timed out: the
# question is closed so it wakes once. Open questions older than 24h are dropped.

late_answer() {  # late_answer <account> <answer text>
  local id hit t; t=$(date -u +%s)
  case $2 in "[q"*"]"*) id=${2#[}; id=${id%%]*};; *) return 1;; esac
  [ -f "$ASK_OPEN" ] || return 1
  hit=$(awk -F'|' -v id="$id" -v a="$1" -v t="$t" '$1 == id && $2 == a && $3 + 86400 >= t' "$ASK_OPEN")
  awk -F'|' -v id="$id" -v a="$1" -v t="$t" '!($1 == id && $2 == a) && $3 + 86400 >= t' "$ASK_OPEN" > "$ASK_OPEN.tmp"     && mv "$ASK_OPEN.tmp" "$ASK_OPEN"
  [ -n "$hit" ]
}
now() { echo "${HIVE_NOW:-$(date -u +%s)}"; }
iso() { TZ=UTC hive_fmt "$1" +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "$(iso "$(now)") hive-msg: $*" >> "$HIVE_STATE/beacon.log"; }
conf_val() { sed -n "s/^$1=//p" "$CONF" | tr -d '\r"'"'"' ' | head -n 1; }
load_conf() {
  HIVE_MSG_TOPIC=""; HIVE_MSG_SERVER=""; HIVE_MSG_TOKEN=""
  # read the conf without sourcing it, tolerating CRLF (Windows editors) and quotes
  # one pass over the conf, no sed|tr|head per key (issue #338); the first line of each key wins, CR, quotes and spaces dropped
  local l v t_=0 s_=0 k_=0 _strip=$'\r"\' '
  [ -f "$CONF" ] && while IFS= read -r l || [ -n "$l" ]; do
    case $l in
      HIVE_MSG_TOPIC=*) [ $t_ = 1 ] && continue; t_=1; v=${l#*=}; v=${v//[$_strip]/}; HIVE_MSG_TOPIC=$v;;
      HIVE_MSG_SERVER=*) [ $s_ = 1 ] && continue; s_=1; v=${l#*=}; v=${v//[$_strip]/}; HIVE_MSG_SERVER=$v;;
      HIVE_MSG_TOKEN=*) [ $k_ = 1 ] && continue; k_=1; v=${l#*=}; v=${v//[$_strip]/}; HIVE_MSG_TOKEN=$v;;
    esac
  done < "$CONF"
  HIVE_MSG_SERVER=${HIVE_MSG_SERVER:-https://ntfy.sh}
  [ -n "$HIVE_MSG_TOPIC" ]
}
# The topic URL (and the access token, if any) as curl config lines, fed on stdin (`curl -K -`): in argv the secrets show in
# `ps`. Optional $1 is appended to the URL (a path and query). load_conf has stripped quotes and spaces from all parts.
topic_url_conf() {
  printf 'url = "%s/%s%s"\n' "$HIVE_MSG_SERVER" "$HIVE_MSG_TOPIC" "${1:-}"
  [ -z "$HIVE_MSG_TOKEN" ] || printf 'header = "Authorization: Bearer %s"\n' "$HIVE_MSG_TOKEN"
}
send() {  # send <TYPE> <text...>   exit 0 sent, 1 failed or refused, 2 bad type, 3 quota backoff (429), 4 over the budget
  local type=$1 t day n code hdr ra u max=${HIVE_MSG_DAILY_MAX:-100}; shift
  case $type in CLAIM|RELEASE|USAGE|ASK|ANSWER|INFO|FIRE|HELLO|TM) ;; *) echo "hive-msg: bad type '$type'" >&2; return 2;; esac
  [ "$type" = CLAIM ] && { hive_guard claim || return 1; }
  load_conf || { echo "hive-msg: no topic configured (run hive-msg.sh init); not sent" >&2; return 0; }
  case "$*" in *"$HIVE_MSG_TOPIC"*) echo "hive-msg: refusing to send text containing the topic" >&2; return 1;; esac
  if [ -n "$HIVE_MSG_TOKEN" ]; then case "$*" in *"$HIVE_MSG_TOKEN"*) echo "hive-msg: refusing to send text containing the access token" >&2; return 1;; esac; fi
  t=$(now)
  hive_msg_quota_until >/dev/null && return 3   # paused after a 429 (logged once, when it started)
  day=$(TZ=UTC hive_fmt "$t" +%Y-%m-%d)
  n=$(cat "$HIVE_STATE/.msg-count" 2>/dev/null | tr -d '\r'); case $n in "$day "[0-9]*) n=${n#* };; *) n=0;; esac
  case $n in ''|*[!0-9]*) n=0;; esac
  case $type in USAGE|HELLO|INFO)
    if [ $((n * 100)) -ge $((max * 70)) ]; then log "dropped $type: $n of $max daily sends used (USAGE/HELLO/INFO stop at 70%)"; return 4; fi;; esac
  hdr=$HIVE_STATE/.msg-hdr.$$
  code=$(topic_url_conf | curl -s -m 5 -K - -D "$hdr" -o /dev/null -w '%{http_code}' -d "$HIVE_ACCOUNT $type $*" 2>/dev/null)
  ra=$(tr -d '\r' 2>/dev/null < "$hdr" | sed -n 's/^[Rr][Ee][Tt][Rr][Yy]-[Aa][Ff][Tt][Ee][Rr]:[[:space:]]*//p' | tail -n 1); rm -f "$hdr"
  case $code in
    2[0-9][0-9]) ;;
    429) case $ra in ''|*[!0-9]*) ra=3600;; esac; [ "$ra" -gt 86400 ] && ra=86400
         u=$((t + ra)); echo "$u" > "$HIVE_STATE/.msg-backoff-until"
         log "$type failed: HTTP 429 (daily quota); all sends paused until $(iso "$u")"; return 3;;
    *) log "$type failed: HTTP ${code:-000}"; return 1;;
  esac
  echo "$day $((n + 1))" > "$HIVE_STATE/.msg-count"; echo "$t" > "$HIVE_STATE/.msg-last-sent"; touch "$HIVE_STATE/.msg-sent-ok"
}
# epoch of this account's last successful send (.msg-last-sent; .msg-sent-ok's mtime from older versions); 0 when none
last_sent() {
  local s=""; { read -r s; } 2>/dev/null < "$HIVE_STATE/.msg-last-sent"; s=${s//$'\r'/}; s=${s// /}
  case $s in ''|*[!0-9]*) s=$(hive_mtime "$HIVE_STATE/.msg-sent-ok" || true);; esac
  echo "${s:-0}"
}
write_status() {  # write_status <line>: msg-status.json, the liveness signal hive-join.sh and hive-tm-check.sh read
  local q qi=""; q=$(hive_msg_quota_until) && qi=$(iso "$q")
  jq -n --arg a "$HIVE_ACCOUNT" --arg l "${1:-}" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg q "$qi" \
    '{account:$a,state:"running",line:$l,at:$t,quota:(if $q == "" then null else $q end)}' > "$HIVE_STATE/msg-status.json"
}
cmd=${1:-}; [ $# -gt 0 ] && shift
if [ "$SINGLE_ACCOUNT" = 1 ]; then case $cmd in claimed) exit 1;; listen|run|backfill) echo "hive-msg: single-account mode, no channel" >&2; exit 3;; *) exit 0;; esac; fi
case $cmd in
  init)
    if [ ! -f "$CONF" ]; then
      (umask 077; echo "HIVE_MSG_TOPIC=hive-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$CONF")
    fi
    load_conf
    echo "topic: $HIVE_MSG_TOPIC"
    echo "Share it out of band; never commit it. The other machine puts HIVE_MSG_TOPIC=<topic> in its $CONF.";;
  send)
    [ $# -ge 2 ] || { echo "usage: hive-msg.sh send <TYPE> <text...>" >&2; exit 2; }
    send "$@"; exit $?;;
  claim|release)   # issue number only: "#793" -> 793
    n=${1#\#}; case $n in ''|*[!0-9]*) echo "usage: hive-msg.sh $cmd <issue number>" >&2; exit 2;; esac
    if [ "$cmd" = claim ]; then send CLAIM "$n"; else send RELEASE "$n"; fi; exit $?;;
  listen)
    load_conf || { echo "hive-msg: no topic configured; run: bash $HIVE_DIR/hive-msg.sh init" >&2; exit 3; }
    LOCK=$HIVE_STATE/msg-listen.pid
    hive_pidlock "$LOCK" || { echo "hive-msg: listener already running (pid $(cat "$LOCK" 2>/dev/null)); not starting a second" >&2; exit 0; }
    trap 'exit 0' INT TERM; trap 'hive_pidunlock "$LOCK"' EXIT
    delay=5
    while true; do
      since=$(cat "$HIVE_STATE/.msg-last-id" 2>/dev/null); since=${since:-24h}
      began=$(date -u +%s)
      topic_url_conf "/json?since=$since" | curl -sN -m 0 -K - 2>/dev/null | {
        n=0
        while IFS= read -r line; do
          rec=$(printf '%s' "$line" | jq -r 'select(.event=="message") | "\(.id)\t\(.time)\t\(.message|gsub("[[:cntrl:]]";" ")|.[0:300])"' 2>/dev/null) || continue
          [ -n "$rec" ] || continue
          IFS=$'\t' read -r id t msg <<EOT
$rec
EOT
          echo "$id" > "$HIVE_STATE/.msg-last-id"
          from=${msg%% *}; rest=${msg#* }; type=${rest%% *}; rest=${rest#"$type"}; rest=${rest# }
          [ "$from" = "$HIVE_ACCOUNT" ] && continue
          echo "$t|$from|$type|$rest" >> "$INBOX"
          # wake only for fresh events: a reconnect replaying older history must not re-wake the triage watcher
          case $type in
            # an ASK addressed `@other` is not ours to wake on; `@me ...` and an unaddressed broadcast are
            ASK) ask_for_me "$rest" && [ $(( $(date -u +%s) - ${t%.*} )) -le 600 ] && echo "MSG $type $from $rest" > "$WAKE";;
            CLAIM|FIRE) [ $(( $(date -u +%s) - ${t%.*} )) -le 600 ] && echo "MSG $type $from $rest" > "$WAKE";;
            ANSWER) [ $(( $(date -u +%s) - ${t%.*} )) -le 600 ] && late_answer "$from" "$rest" && echo "MSG $type $from $rest" > "$WAKE";; esac
          n=$((n+1))
          if [ $((n % 100)) -eq 0 ] && [ "$(wc -l < "$INBOX")" -gt 2000 ]; then
            tail -n 2000 "$INBOX" > "$INBOX.tmp" && mv "$INBOX.tmp" "$INBOX"
          fi
        done
      }
      [ $(( $(date -u +%s) - began )) -gt 60 ] && delay=5
      sleep "$delay"; delay=$((delay*2)); [ "$delay" -gt 60 ] && delay=60
    done;;
  backfill)
    load_conf || { echo "hive-msg: no topic configured; nothing to backfill" >&2; exit 3; }
    got=$(topic_url_conf "/json?poll=1&since=12h" | curl -sf -m 15 -K - 2>/dev/null) || { echo "hive-msg: backfill poll failed" >&2; exit 1; }
    touch "$INBOX"; : > "$INBOX.new"
    printf '%s\n' "$got" | jq -r --arg me "$HIVE_ACCOUNT" 'select(.event=="message") | (.message|gsub("[[:cntrl:]]";" ")|.[0:300]) as $m
      | ($m|split(" ")) as $w | select($w[0] != $me and ($w|length) >= 2)
      | "\(.time)|\($w[0])|\($w[1])|\($w[2:]|join(" "))"' 2>/dev/null |
      while IFS= read -r l; do grep -qxF -- "$l" "$INBOX" || echo "$l" >> "$INBOX.new"; done
    # merge keeping the inbox time-ordered (claimed/heartbeat read it in file order); stable, so ties keep their order
    if [ -s "$INBOX.new" ]; then
      cat "$INBOX" "$INBOX.new" | sort -s -t'|' -k1,1n > "$INBOX.tmp" && mv "$INBOX.tmp" "$INBOX"
    fi
    rm -f "$INBOX.new"
    exit 0;;
  claimed)
    n=${1:?usage: hive-msg.sh claimed <n>}; n=${n#\#}
    [ -f "$INBOX" ] || exit 1
    awk -F'|' -v now="$(now)" -v n="$n" -v me="$HIVE_ACCOUNT" '
      { split($4, w, " "); if (w[1] != n || $2 == me) next
        if ($3 == "CLAIM") c[$2] = $1
        else if ($3 == "RELEASE") delete c[$2] }
      END { for (a in c) if (now - c[a] <= 86400) exit 0; exit 1 }' "$INBOX"
    exit $?;;
  heartbeat)
    t=$(now)
    # HELLO only when nothing else went out for 60 min: any send proves this account is alive
    if [ -z "${HIVE_MSG_NOSEND:-}" ] && [ $(( t - $(last_sent) )) -ge 3600 ]; then send HELLO "$HIVE_ACCOUNT"; fi
    ok=$(last_sent)
    for peer in $(hive_peers); do
      [ -f "$INBOX" ] || break
      # A peer whose USAGE has no real WEEKLY numbers (7d % "?", or the 7d reset 1970) has a broken status line: ask it to fix,
      # every 6h at most. r5=1970 alone is NOT broken: no 5h window has started yet (0% used); 21 of 25 ASKs in one day were that (#274).
      u=$(awk -F'|' -v p="$peer" '$2==p && $3=="USAGE" {l=$4} END {print l}' "$INBOX")
      read -r _ uw7 ur7 _ <<EOT
$u
EOT
      nl=$(hive_mtime "$HIVE_STATE/.msg-usage-nudge-$peer" || true); nl=${nl:-0}
      if [ -z "${HIVE_MSG_NOSEND:-}" ] && [ -n "$u" ] && { [ "$uw7" = "?%" ] || [ "$uw7" = "?" ] || [[ "$ur7" == 1970-01-01* ]]; } && [ $(( $(date -u +%s) - nl )) -gt 21600 ]; then
        send ASK "@$peer your USAGE reports no real numbers ($u). Point your Claude statusLine at tools/agents/statusline.sh with HIVE_ACCOUNT=$peer (Windows: the Git Bash command in tools/agents/windows/README.md), restart Claude, then reply ANSWER." \
          && touch "$HIVE_STATE/.msg-usage-nudge-$peer"
      fi
      # silent = no message of any type for 2 h (HELLO goes out only after an hour with no other send)
      last=$(hive_peer_heard "$peer")
      [ "$last" -gt 0 ] || continue
      [ $(( t - last )) -gt 7200 ] || continue
      # our own sends work (one goes out at least hourly), so the network is up; not while we are quota-blocked
      [ $(( t - ok )) -lt 4200 ] || continue
      [ "$(cat "$HIVE_STATE/.msg-silent-$peer" 2>/dev/null)" != "$last" ] || continue
      line="MSG FIRE peer-silent $peer (last message $(iso "$last"))"
      echo "$line" > "$WAKE"; echo "$last" > "$HIVE_STATE/.msg-silent-$peer"; echo "$line"
    done
    exit 0;;
  run)
    load_conf || { echo "hive-msg: no topic configured; run: bash $HIVE_DIR/hive-msg.sh init" >&2; exit 3; }
    LOCK=$HIVE_STATE/msg-run.pid   # shared with windows/hive-supervise.sh msg
    hive_pidlock "$LOCK" || { echo "hive-msg: channel supervisor already running (pid $(cat "$LOCK" 2>/dev/null)); not starting a second" >&2; exit 0; }
    lp=""
    # the listener runs in its own process group (set -m) so stopping it also stops its curl | reader pipeline
    stop_listener() { [ -n "$lp" ] && kill -- -"$lp" 2>/dev/null; kill "$lp" 2>/dev/null; }
    trap 'stop_listener; exit 0' INT TERM
    trap 'stop_listener; hive_pidunlock "$LOCK"' EXIT
    while true; do
      if [ -z "$lp" ] || ! kill -0 "$lp" 2>/dev/null; then
        [ -n "$lp" ] && kill -- -"$lp" 2>/dev/null
        set -m; bash "$HIVE_DIR/hive-msg.sh" listen >> "$HIVE_STATE/msg-listen.log" 2>&1 & lp=$!; set +m
      fi
      bash "$HIVE_DIR/hive-msg.sh" heartbeat >> "$HIVE_STATE/msg-heartbeat.log" 2>&1 || true
      # the liveness signal hive-join.sh and hive-tm-check.sh read (windows/hive-supervise.sh msg writes the same file)
      write_status "listener pid $lp"
      sleep 60 & wait $!
    done;;
  status) write_status "${1:-}"; exit 0;;
  *) echo "usage: hive-msg.sh init|send <TYPE> <text>|claim <n>|release <n>|listen|backfill|claimed <n>|heartbeat|run|status [line]" >&2; exit 2;;
esac
