#!/bin/bash
# Private account-to-account doorbell over an ntfy topic. The channel only nudges; verify everything on GitHub.
#   pf-msg.sh init                  create $PF_STATE/pf-msg.conf with a random secret topic (never commit it)
#   pf-msg.sh send <TYPE> <text>    TYPE: CLAIM RELEASE USAGE ASK ANSWER INFO FIRE HELLO
#   pf-msg.sh claim|release <n>     send CLAIM / RELEASE <n>
#   pf-msg.sh listen                long-lived: appends to msg-inbox.log, writes CLAIM/ASK/FIRE lines to msg-wake.txt
#   pf-msg.sh claimed <n>           exit 0 when another account CLAIMed <n> in the last 24h and has not RELEASEd it
#   pf-msg.sh heartbeat             one pass: send HELLO every 15 min; wake (MSG FIRE peer-silent) when a peer is silent 1h+
# Conf $PF_STATE/pf-msg.conf: PF_MSG_TOPIC=..., optional PF_MSG_SERVER (default https://ntfy.sh).
# Env: PF_NOW (epoch override for tests), PF_MSG_NOSEND=1 (heartbeat sends nothing).
. "$(dirname "$0")/pf-env.sh" || exit 1
CONF=$PF_STATE/pf-msg.conf
INBOX=$PF_STATE/msg-inbox.log
WAKE=$PF_STATE/msg-wake.txt
now() { echo "${PF_NOW:-$(date -u +%s)}"; }
load_conf() {
  PF_MSG_TOPIC=""; PF_MSG_SERVER=""
  # read the conf without sourcing it, tolerating CRLF (Windows editors) and quotes
  [ -f "$CONF" ] && { PF_MSG_TOPIC=$(sed -n 's/^PF_MSG_TOPIC=//p' "$CONF" | tr -d '\r"'"'"' ' | head -n 1)
    PF_MSG_SERVER=$(sed -n 's/^PF_MSG_SERVER=//p' "$CONF" | tr -d '\r"'"'"' ' | head -n 1); }
  PF_MSG_SERVER=${PF_MSG_SERVER:-https://ntfy.sh}
  [ -n "$PF_MSG_TOPIC" ]
}
# The topic URL as a curl config line, fed on stdin (`curl -K -`): in argv the secret topic shows in `ps`.
# Optional $1 is appended to the URL (a path and query). load_conf has stripped quotes and spaces from both parts.
topic_url_conf() { printf 'url = "%s/%s%s"\n' "$PF_MSG_SERVER" "$PF_MSG_TOPIC" "${1:-}"; }
send() {  # send <TYPE> <text...>
  local type=$1; shift
  case $type in CLAIM|RELEASE|USAGE|ASK|ANSWER|INFO|FIRE|HELLO) ;; *) echo "pf-msg: bad type '$type'" >&2; return 2;; esac
  load_conf || { echo "pf-msg: no topic configured (run pf-msg.sh init); not sent" >&2; return 0; }
  case "$*" in *"$PF_MSG_TOPIC"*) echo "pf-msg: refusing to send text containing the topic" >&2; return 1;; esac
  topic_url_conf | curl -sf -m 5 -K - -d "$PF_ACCOUNT $type $*" >/dev/null 2>&1 || return 1
  touch "$PF_STATE/.msg-sent-ok"
}
cmd=${1:-}; [ $# -gt 0 ] && shift
case $cmd in
  init)
    if [ ! -f "$CONF" ]; then
      (umask 077; echo "PF_MSG_TOPIC=pf-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$CONF")
    fi
    load_conf
    echo "topic: $PF_MSG_TOPIC"
    echo "Share it out of band; never commit it. The other machine puts PF_MSG_TOPIC=<topic> in its $CONF.";;
  send)
    [ $# -ge 2 ] || { echo "usage: pf-msg.sh send <TYPE> <text...>" >&2; exit 2; }
    send "$@"; exit $?;;
  claim|release)   # issue number only: "#793" -> 793
    n=${1#\#}; case $n in ''|*[!0-9]*) echo "usage: pf-msg.sh $cmd <issue number>" >&2; exit 2;; esac
    if [ "$cmd" = claim ]; then send CLAIM "$n"; else send RELEASE "$n"; fi; exit $?;;
  listen)
    load_conf || { echo "pf-msg: no topic configured; run: bash $PF_DIR/pf-msg.sh init" >&2; exit 3; }
    delay=5
    while true; do
      since=$(cat "$PF_STATE/.msg-last-id" 2>/dev/null); since=${since:-24h}
      began=$(date -u +%s)
      topic_url_conf "/json?since=$since" | curl -sN -m 0 -K - 2>/dev/null | {
        n=0
        while IFS= read -r line; do
          rec=$(printf '%s' "$line" | jq -r 'select(.event=="message") | "\(.id)\t\(.time)\t\(.message|gsub("[[:cntrl:]]";" ")|.[0:300])"' 2>/dev/null) || continue
          [ -n "$rec" ] || continue
          IFS=$'\t' read -r id t msg <<EOT
$rec
EOT
          echo "$id" > "$PF_STATE/.msg-last-id"
          from=${msg%% *}; rest=${msg#* }; type=${rest%% *}; rest=${rest#"$type"}; rest=${rest# }
          [ "$from" = "$PF_ACCOUNT" ] && continue
          echo "$t|$from|$type|$rest" >> "$INBOX"
          # wake only for fresh events: a reconnect replaying older history must not re-wake the triage watcher
          case $type in CLAIM|ASK|FIRE) [ $(( $(date -u +%s) - ${t%.*} )) -le 600 ] && echo "MSG $type $from $rest" > "$WAKE";; esac
          n=$((n+1))
          if [ $((n % 100)) -eq 0 ] && [ "$(wc -l < "$INBOX")" -gt 2000 ]; then
            tail -n 2000 "$INBOX" > "$INBOX.tmp" && mv "$INBOX.tmp" "$INBOX"
          fi
        done
      }
      [ $(( $(date -u +%s) - began )) -gt 60 ] && delay=5
      sleep "$delay"; delay=$((delay*2)); [ "$delay" -gt 60 ] && delay=60
    done;;
  claimed)
    n=${1:?usage: pf-msg.sh claimed <n>}; n=${n#\#}
    [ -f "$INBOX" ] || exit 1
    awk -F'|' -v now="$(now)" -v n="$n" -v me="$PF_ACCOUNT" '
      { split($4, w, " "); if (w[1] != n || $2 == me) next
        if ($3 == "CLAIM") c[$2] = $1
        else if ($3 == "RELEASE") delete c[$2] }
      END { for (a in c) if (now - c[a] <= 86400) exit 0; exit 1 }' "$INBOX"
    exit $?;;
  heartbeat)
    t=$(now)
    hl=$(pf_mtime "$PF_STATE/.msg-hello-last" || true); hl=${hl:-0}
    if [ -z "${PF_MSG_NOSEND:-}" ] && [ $(( $(date -u +%s) - hl )) -gt 900 ]; then
      send HELLO "$PF_ACCOUNT" && touch "$PF_STATE/.msg-hello-last"
    fi
    ok=$(pf_mtime "$PF_STATE/.msg-sent-ok" || true); ok=${ok:-0}
    for peer in ${WATCH_PEERS:-agage-JG}; do
      [ -f "$INBOX" ] || break
      last=$(awk -F'|' -v p="$peer" '$2==p && $3=="HELLO" && $1>m {m=$1} END {print m+0}' "$INBOX")
      [ "$last" -gt 0 ] || continue
      [ $(( t - last )) -gt 3600 ] || continue
      [ $(( $(date -u +%s) - ok )) -lt 1200 ] || continue
      [ "$(cat "$PF_STATE/.msg-silent-$peer" 2>/dev/null)" != "$last" ] || continue
      line="MSG FIRE peer-silent $peer (last HELLO $(TZ=UTC pf_epoch_fmt "$last" +%Y-%m-%dT%H:%M:%SZ))"
      echo "$line" > "$WAKE"; echo "$last" > "$PF_STATE/.msg-silent-$peer"; echo "$line"
    done
    exit 0;;
  *) echo "usage: pf-msg.sh init|send <TYPE> <text>|claim <n>|release <n>|listen|claimed <n>|heartbeat" >&2; exit 2;;
esac
