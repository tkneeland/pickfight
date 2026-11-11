#!/bin/bash
# Offline test for pf-hive-failover.sh (autotriage.md rule 21): ONE shared stub Discord (a message list in $T/msgs.json,
# POST appends, DELETE removes) and one scratch PF_STATE_DIR per simulated account, fixture ranks in $T/acc.
# No network. macOS, Linux and Git Bash.   bash tools/agents/tests/hive-failover.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-hive-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/acc"
for p in "tkneeland 1" "agage-JG 2" "schans2 3" "tommykneeland 4"; do set -- $p; echo "SUCCESSION_RANK=$2" > "$T/acc/$1.conf"; done
echo "HANDOFF=1" > "$T/acc/_shared.conf"
export PF_NOW=1800000000 PF_ACCOUNTS_DIR=$T/acc
echo 1 > "$T/counter"
# stub curl: token on stdin config; GET /messages?limit=50 -> msgs.json; POST /messages appends (race-inject first adds a rival
# notice with a lower id); DELETE removes; anything else (ntfy) is logged, 200.
cat > "$T/bin/curl" <<EOF2
#!/bin/bash
cfg=\$(cat); url=\$(printf '%s\n' "\$cfg" | sed -n 's/^url = "\(.*\)"/\1/p')
printf '%s\n' "\$*" >> "$T/args.log"
method=GET; body=""; prev=""
for a in "\$@"; do [ "\$prev" = -X ] && method=\$a; [ "\$prev" = -d ] && body=\$a; prev=\$a; done
case \$url in
  */channels/*/messages?limit=50) cat "$T/msgs.json";;
  */channels/*/messages) c=\$(cat "$T/counter"); echo \$((c+2)) > "$T/counter"
    ref=\$(echo "\$body" | jq -r .message_reference.message_id); txt=\$(echo "\$body" | jq -r .content)
    if [ -f "$T/race" ]; then rid=\$(( \$(cat "$T/rivalbase") + c ))
      jq --arg id "\$rid" --arg r "\$ref" '. + [{id: \$id, author: {bot: true}, content: "taking over from tkneeland (now agage-JG)", message_reference: {message_id: \$r}}]' "$T/msgs.json" > "$T/m2" && mv "$T/m2" "$T/msgs.json"; fi
    id=\$(( \$(cat "$T/rivalbase") + c + 1 ))
    jq --arg id "\$id" --arg r "\$ref" --arg t "\$txt" '. + [{id: \$id, author: {bot: true}, content: \$t, message_reference: {message_id: \$r}}]' "$T/msgs.json" > "$T/m2" && mv "$T/m2" "$T/msgs.json"
    if [ -f "$T/postlost" ]; then exit 28; fi   # the post landed but the response timed out
    echo "{\"id\":\"\$id\"}";;
  */channels/*/messages/*) [ "\$method" = DELETE ] && { id=\${url##*/}; jq --arg id "\$id" 'map(select(.id != \$id))' "$T/msgs.json" > "$T/m2" && mv "$T/m2" "$T/msgs.json"; };;
  *) printf '%s %s\n' "\$url" "\$body" >> "$T/ntfy.log";;
esac
exit 0
EOF2
chmod +x "$T/bin/curl"; export PATH=$T/bin:$PATH
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
mkid() { echo $(( ( ($1 * 1000 - 1420070400000) << 22 ) + $2 )); }   # id for epoch seconds $1, sequence $2
H=$AG/pf-hive-failover.sh
# acct <name>: switch to that account's state dir, token set up
acct() { export PF_ACCOUNT=$1 PF_STATE_DIR=$T/state-$1; mkdir -p "$PF_STATE_DIR"
  echo "PF_MSG_TOPIC=pf-test" > "$PF_STATE_DIR/pf-msg.conf"
  [ -f "$PF_STATE_DIR/pf-discord.conf" ] || echo "PF_DISCORD_TOKEN=tok-$1" > "$PF_STATE_DIR/pf-discord.conf"; }
# inbox for an account: HELLO ages given per peer
hello() { echo "$(( PF_NOW - $2 ))|$1|HELLO|$1" >> "$PF_STATE_DIR/msg-inbox.log"; }
setup_inboxes() {  # $1 = age of agage-JG's last HELLO
  for a in tkneeland agage-JG schans2; do acct $a; : > "$PF_STATE_DIR/msg-inbox.log"
    hello tkneeland 60; hello agage-JG "$1"; hello schans2 120; rm -f "$PF_STATE_DIR"/.hive-failover-*
    echo tkneeland > "$PF_STATE_DIR/pf-triagemaster"; done; }
human() { jq -n --arg id "$1" '{id: $id, author: {bot: false, username: "sam"}, content: "please look at the lobby bug"}'; }
bot() { jq -n --arg id "$1" --arg r "$2" --arg c "$3" '{id: $id, author: {bot: true}, content: $c, message_reference: {message_id: $r}}'; }
M=$(mkid $((PF_NOW - 700)) 1)           # a dev message 11 minutes old
echo "$(mkid $PF_NOW 0)" > "$T/rivalbase"   # ids for new bot posts are above any fixture id
wake() { acct "$1"; bash "$H" check 2>/dev/null; echo "rc=$?"; }
tm() { for a in tkneeland agage-JG schans2; do wake $a; done | tr '\n' ' '; }

# A) the triagemaster answered: nobody wakes
setup_inboxes 100; jq -s '.' <(human "$M") <(bot "$(mkid $((PF_NOW - 650)) 2)" "$M" "Filed as #5") > "$T/msgs.json"
check "answered wakes nobody" "$(tm)" "rc=1 rc=1 rc=1 "
# B) unanswered 11 min, agage-JG live: only agage-JG wakes (not the holder, not rank 3)
setup_inboxes 100; jq -s '.' <(human "$M") > "$T/msgs.json"
check "only the next-ranked live account wakes" "$(tm)" "rc=1 HIVE_TAKEOVER $M rc=0 rc=1 "
# B2) the same wake does not repeat inside 5 min
check "debounced" "$(wake agage-JG)" "rc=1"
# C) agage-JG silent for 2h: schans2 is next
setup_inboxes 7200
# (agage-JG's machine is down: only the machines that run the watcher are asked)
check "stale heartbeat skipped" "$(for a in tkneeland schans2; do wake $a; done | tr '\n' ' ')" "rc=1 HIVE_TAKEOVER $M rc=0 "
# D) message under 10 minutes old: nobody
setup_inboxes 100; jq -s '.' <(human "$(mkid $((PF_NOW - 300)) 1)") > "$T/msgs.json"
check "under 10 min wakes nobody" "$(tm)" "rc=1 rc=1 rc=1 "
# E) older than 24h: ignored
setup_inboxes 100; jq -s '.' <(human "$(mkid $((PF_NOW - 90000)) 1)") > "$T/msgs.json"
check "over 24h ignored" "$(tm)" "rc=1 rc=1 rc=1 "
# F) stand-in holder (agage-JG holds): schans2 next, then wrap to tkneeland
setup_inboxes 100; jq -s '.' <(human "$M") > "$T/msgs.json"
for a in tkneeland agage-JG schans2; do echo agage-JG > "$T/state-$a/pf-triagemaster"; done
check "successor of a stand-in" "$(tm)" "rc=1 rc=1 HIVE_TAKEOVER $M rc=0 "
for a in tkneeland agage-JG schans2; do echo schans2 > "$T/state-$a/pf-triagemaster"; done
check "wraps to the lowest rank" "$(tm)" "HIVE_TAKEOVER $M rc=0 rc=1 rc=1 "
# H) takeover: notice posted, role recorded, message still unanswered, clock restarts from the notice
setup_inboxes 100; jq -s '.' <(human "$M") > "$T/msgs.json"; rm -f "$T/race"
acct agage-JG; out=$(bash "$H" takeover "$M"); check "takeover wins" "$out" "TAKEOVER_OK from tkneeland"
check "role recorded" "$(cat "$PF_STATE_DIR/pf-triagemaster")" agage-JG
check "notice names the old holder" "$(jq -r '.[-1].content' "$T/msgs.json")" "taking over from tkneeland (now agage-JG)"
check "notice is a reply to the message" "$(jq -r '.[-1].message_reference.message_id' "$T/msgs.json")" "$M"
# the notice is not an answer; nobody wakes for 10 min after it ...
check "fresh notice wakes nobody" "$(tm)" "rc=1 rc=1 rc=1 "
# ... then a dead taker is failed over in turn (notice names agage-JG as holder: schans2 next)
export PF_NOW=$((PF_NOW + 700)); rm -f "$T"/state-*/.hive-failover-*
check "dead taker failed over in turn" "$(for a in tkneeland schans2; do wake $a; done | tr '\n' ' ')" "rc=1 HIVE_TAKEOVER $M rc=0 "
export PF_NOW=1800000000
check "role taken through the private channel" "$(grep -c 'TM agage-JG until failover 18' "$T/ntfy.log")" 1
check "local takeover marker" "$(cut -d' ' -f1 "$T/state-agage-JG/pf-takeover")" agage-JG
# the next pf-succession run keeps the taker (it used to recompute the role away); an expired marker does not
acct schans2; real=$(date +%s)
printf '%s|agage-JG|TM|agage-JG until failover %s (from tkneeland)\n' "$real" $((real + 3600)) >> "$PF_STATE_DIR/msg-inbox.log"
echo tkneeland > "$PF_STATE_DIR/pf-triagemaster"
check "succession honours a live takeover" "$(bash "$AG/pf-succession.sh" 2>/dev/null)" agage-JG
check "and writes it to the role file" "$(cat "$PF_STATE_DIR/pf-triagemaster")" agage-JG
: > "$PF_STATE_DIR/msg-inbox.log"; printf '%s|agage-JG|TM|agage-JG until failover %s\n' "$real" $((real - 5)) >> "$PF_STATE_DIR/msg-inbox.log"
echo tkneeland > "$PF_STATE_DIR/pf-triagemaster"
check "an expired takeover is not honoured" "$(bash "$AG/pf-succession.sh" 2>/dev/null)" tkneeland
# takeover re-checks on fresh data: a second machine acting on a stale wake exits 3 and posts nothing
setup_inboxes 100; jq -s '.' <(human "$M") > "$T/msgs.json"
acct agage-JG; bash "$H" takeover "$M" >/dev/null
nb=$(jq '[.[] | select(.author.bot)] | length' "$T/msgs.json")
acct schans2; bash "$H" takeover "$M" >/dev/null; check "second takeover (fresh notice) exits 3" $? 3
check "and posts no notice" "$(jq '[.[] | select(.author.bot)] | length' "$T/msgs.json")" "$nb"
# a machine that is not the designated successor refuses even with an old, unanswered message
setup_inboxes 100; jq -s '.' <(human "$M") > "$T/msgs.json"
acct schans2; bash "$H" takeover "$M" >/dev/null; check "non-successor takeover exits 3" $? 3
# and a message under 10 minutes old is not due
jq -s '.' <(human "$(mkid $((PF_NOW - 200)) 1)") > "$T/msgs.json"
acct agage-JG; bash "$H" takeover "$(mkid $((PF_NOW - 200)) 1)" >/dev/null; check "young message takeover exits 3" $? 3
check "dcurl has a timeout" "$(grep -c -- '-m 15' "$T/args.log" | awk '{print ($1 > 0)}')" 1
# a stale local marker never outvotes a newer takeover, and an expired or superseded one is removed
acct schans2; real=$(date +%s); : > "$PF_STATE_DIR/msg-inbox.log"
echo "agage-JG $((real + 3000)) $((real - 1000))" > "$PF_STATE_DIR/pf-takeover"
printf '%s|tkneeland|TM|tkneeland until failover %s (from agage-JG)\n' "$((real - 10))" $((real + 7200)) >> "$PF_STATE_DIR/msg-inbox.log"
check "newer TM beats an older local marker" "$(bash "$AG/pf-succession.sh" 2>/dev/null)" tkneeland
check "superseded marker removed" "$([ -f "$PF_STATE_DIR/pf-takeover" ] && echo kept || echo gone)" gone
: > "$PF_STATE_DIR/msg-inbox.log"; echo "agage-JG $((real + 3000)) $((real - 10))" > "$PF_STATE_DIR/pf-takeover"
printf '%s|tkneeland|TM|tkneeland until failover %s\n' "$((real - 500))" $((real + 7200)) >> "$PF_STATE_DIR/msg-inbox.log"
check "newer local marker beats an older TM" "$(bash "$AG/pf-succession.sh" 2>/dev/null)" agage-JG
echo "agage-JG $((real - 5)) $((real - 9000))" > "$PF_STATE_DIR/pf-takeover"; : > "$PF_STATE_DIR/msg-inbox.log"; echo tkneeland > "$PF_STATE_DIR/pf-triagemaster"
check "expired local marker ignored" "$(bash "$AG/pf-succession.sh" 2>/dev/null)" tkneeland
check "expired marker removed" "$([ -f "$PF_STATE_DIR/pf-takeover" ] && echo kept || echo gone)" gone
# writes get the longer limit, reads the 15 s one
check "post uses the write limit" "$(grep -c -- '-m 45' "$T/args.log" | awk '{print ($1 > 0)}')" 1
# a notice POST that times out but landed is found, not posted twice
setup_inboxes 100; jq -s '.' <(human "$M") > "$T/msgs.json"; touch "$T/postlost"
acct agage-JG; out=$(bash "$H" takeover "$M"); check "lost post response: takeover still wins" "$out" "TAKEOVER_OK from tkneeland"
check "and posted exactly one notice" "$(jq '[.[] | select(.author.bot)] | length' "$T/msgs.json")" 1
rm -f "$T/postlost"
# I) two machines never both take over: a rival's earlier notice lands while agage-JG posts
setup_inboxes 100; jq -s '.' <(human "$M") > "$T/msgs.json"; touch "$T/race"
acct agage-JG; out=$(bash "$H" takeover "$M"); rc=$?
check "loser exits 3" "$rc" 3
check "loser removed its notice" "$(jq '[.[] | select(.author.bot)] | length' "$T/msgs.json")" 1
check "loser keeps the old role" "$(cat "$PF_STATE_DIR/pf-triagemaster")" tkneeland
rm -f "$T/race"
# J) already answered by the time takeover runs
jq -s '.' <(human "$M") <(bot "$(mkid $((PF_NOW - 10)) 2)" "$M" "Done") > "$T/msgs.json"
acct schans2; bash "$H" takeover "$M" >/dev/null; check "takeover after an answer exits 3" $? 3
# K) no pf-discord.conf: asks the owner once, never silent
acct tommykneeland; rm -f "$PF_STATE_DIR/pf-discord.conf" "$PF_STATE_DIR/.hive-noconf-asked"
printf 'PF_MSG_TOPIC=pf-test\n' > "$PF_STATE_DIR/pf-msg.conf"; : > "$T/ntfy.log"
bash "$H" check >/dev/null 2>&1; check "no conf exits 2" $? 2
bash "$H" check >/dev/null 2>&1
check "asked the owner once" "$(grep -c 'ASK' "$T/ntfy.log")" 1
# L) Discord failing: no wake
setup_inboxes 100; echo '{"message":"401","code":0}' > "$T/msgs.json"
check "Discord failure wakes nobody" "$(tm)" "rc=2 rc=2 rc=2 "
echo "hive-failover: $pass passed, $fail failed"; [ "$fail" = 0 ]
