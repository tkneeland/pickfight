#!/bin/bash
# Offline test for hive-failover.sh (hive.md rule 21): ONE shared stub Discord (a message list in $T/msgs.json,
# POST appends, DELETE removes) and one scratch HIVE_STATE_DIR per simulated account, fixture ranks in $T/acc.
# No network. macOS, Linux and Git Bash.   bash tools/agents/tests/hive-failover.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-failover-test.XXXXXX") || exit 1; hive_test_guard
hive_fixture "$T" || exit 1
mkdir -p "$T/bin" "$T/acc"
for p in "alice 1" "bob 2" "carol 3" "dave 4"; do set -- $p; echo "SUCCESSION_RANK=$2" > "$T/acc/$1.conf"; done
echo "HANDOFF=1" > "$T/acc/_shared.conf"
export HIVE_NOW=1800000000 HIVE_ACCOUNTS_DIR=$T/acc
echo 1 > "$T/counter"
# stub curl: token on stdin config; GET /messages?limit=50 -> msgs.json; POST /messages appends (race-inject first adds a rival
# notice with a lower id); DELETE removes; anything else (ntfy) is logged, 200.
cat > "$T/bin/curl" <<EOF2
#!/bin/bash
case " \$* " in *" -K "*) cfg=\$(cat);; *) cfg=;; esac; url=\$(printf '%s\n' "\$cfg" | sed -n 's/^url = "\(.*\)"/\1/p')
printf '%s\n' "\$*" >> "$T/args.log"
method=GET; body=""; prev=""
for a in "\$@"; do [ "\$prev" = -X ] && method=\$a; [ "\$prev" = -d ] && body=\$a; prev=\$a; done
case \$url in
  */channels/*/messages?limit=50) cat "$T/msgs.json";;
  */channels/*/messages) c=\$(cat "$T/counter"); echo \$((c+2)) > "$T/counter"
    ref=\$(echo "\$body" | jq -r .message_reference.message_id); txt=\$(echo "\$body" | jq -r .content)
    if [ -f "$T/race" ]; then rid=\$(( \$(cat "$T/rivalbase") + c ))
      jq --arg id "\$rid" --arg r "\$ref" '. + [{id: \$id, author: {bot: true}, content: "taking over from alice (now bob)", message_reference: {message_id: \$r}}]' "$T/msgs.json" > "$T/m2" && mv "$T/m2" "$T/msgs.json"; fi
    id=\$(( \$(cat "$T/rivalbase") + c + 1 ))
    jq --arg id "\$id" --arg r "\$ref" --arg t "\$txt" '. + [{id: \$id, author: {bot: true}, content: \$t, message_reference: {message_id: \$r}}]' "$T/msgs.json" > "$T/m2" && mv "$T/m2" "$T/msgs.json"
    if [ -f "$T/postlost" ]; then exit 28; fi   # the post landed but the response timed out
    echo "{\"id\":\"\$id\"}";;
  */channels/*/messages/*) [ "\$method" = DELETE ] && { id=\${url##*/}; jq --arg id "\$id" 'map(select(.id != \$id))' "$T/msgs.json" > "$T/m2" && mv "$T/m2" "$T/msgs.json"; };;
  *) printf '%s %s\n' "\$url" "\$body" >> "$T/ntfy.log";;
esac
exit 0
EOF2
chmod +x "$T/bin/curl"; hive_noop_stub "$T/bin" gh; hive_stub_jq "$T/bin"; export PATH=$T/bin:$PATH
hive_require_stub "$T/bin" curl gh
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
mkid() { echo $(( ( ($1 * 1000 - 1420070400000) << 22 ) + $2 )); }   # id for epoch seconds $1, sequence $2
H=$AG/hive-failover.sh
# acct <name>: switch to that account's state dir, token set up
acct() { export HIVE_ACCOUNT=$1 HIVE_STATE_DIR=$T/state-$1; mkdir -p "$HIVE_STATE_DIR"
  echo "HIVE_MSG_TOPIC=hive-test" > "$HIVE_STATE_DIR/msg.conf"
  [ -f "$HIVE_STATE_DIR/discord.conf" ] || echo "HIVE_DISCORD_TOKEN=tok-$1" > "$HIVE_STATE_DIR/discord.conf"; }
# inbox for an account: HELLO ages given per peer
hello() { echo "$(( HIVE_NOW - $2 ))|$1|HELLO|$1" >> "$HIVE_STATE_DIR/msg-inbox.log"; }
setup_inboxes() {  # $1 = age of bob's last HELLO
  for a in alice bob carol; do acct $a; : > "$HIVE_STATE_DIR/msg-inbox.log"
    hello alice 60; hello bob "$1"; hello carol 120; rm -f "$HIVE_STATE_DIR"/.hive-failover-*
    echo alice > "$HIVE_STATE_DIR/triagemaster"; done; }
human() { jq -n --arg id "$1" '{id: $id, author: {bot: false, username: "carol"}, content: "please look at the lobby bug"}'; }
bot() { jq -n --arg id "$1" --arg r "$2" --arg c "$3" '{id: $id, author: {bot: true}, content: $c, message_reference: {message_id: $r}}'; }
M=$(mkid $((HIVE_NOW - 700)) 1)           # a dev message 11 minutes old
echo "$(mkid $HIVE_NOW 0)" > "$T/rivalbase"   # ids for new bot posts are above any fixture id
wake() { acct "$1"; bash "$H" check 2>/dev/null; echo "rc=$?"; }
tm() { for a in alice bob carol; do wake $a; done | tr '\n' ' '; }

# A) the triagemaster answered: nobody wakes
setup_inboxes 100; { human "$M"; bot "$(mkid $((HIVE_NOW - 650)) 2)" "$M" "Filed as #5"; } | jq -s '.' > "$T/msgs.json"
check "answered wakes nobody" "$(tm)" "rc=1 rc=1 rc=1 "
# B) unanswered 11 min, bob live: only bob wakes (not the holder, not rank 3)
setup_inboxes 100; human "$M" | jq -s '.' > "$T/msgs.json"
check "only the next-ranked live account wakes" "$(tm)" "rc=1 HIVE_TAKEOVER $M rc=0 rc=1 "
# B2) the same wake does not repeat inside 5 min
check "debounced" "$(wake bob)" "rc=1"
# C) bob silent for 2h: carol is next
setup_inboxes 7200
# (bob's machine is down: only the machines that run the watcher are asked)
check "stale heartbeat skipped" "$(for a in alice carol; do wake $a; done | tr '\n' ' ')" "rc=1 HIVE_TAKEOVER $M rc=0 "
# D) message under 10 minutes old: nobody
setup_inboxes 100; human "$(mkid $((HIVE_NOW - 300)) 1)" | jq -s '.' > "$T/msgs.json"
check "under 10 min wakes nobody" "$(tm)" "rc=1 rc=1 rc=1 "
# E) older than 24h: ignored
setup_inboxes 100; human "$(mkid $((HIVE_NOW - 90000)) 1)" | jq -s '.' > "$T/msgs.json"
check "over 24h ignored" "$(tm)" "rc=1 rc=1 rc=1 "
# F) stand-in holder (bob holds): carol next, then wrap to alice
setup_inboxes 100; human "$M" | jq -s '.' > "$T/msgs.json"
for a in alice bob carol; do echo bob > "$T/state-$a/triagemaster"; done
check "successor of a stand-in" "$(tm)" "rc=1 rc=1 HIVE_TAKEOVER $M rc=0 "
for a in alice bob carol; do echo carol > "$T/state-$a/triagemaster"; done
check "wraps to the lowest rank" "$(tm)" "HIVE_TAKEOVER $M rc=0 rc=1 rc=1 "
# H) takeover: notice posted, role recorded, message still unanswered, clock restarts from the notice
setup_inboxes 100; human "$M" | jq -s '.' > "$T/msgs.json"; rm -f "$T/race"
acct bob; out=$(bash "$H" takeover "$M"); check "takeover wins" "$out" "TAKEOVER_OK from alice"
check "role recorded" "$(cat "$HIVE_STATE_DIR/triagemaster")" bob
check "notice names the old holder" "$(jq -r '.[-1].content' "$T/msgs.json")" "taking over from alice (now bob)"
check "notice is a reply to the message" "$(jq -r '.[-1].message_reference.message_id' "$T/msgs.json")" "$M"
# the notice is not an answer; nobody wakes for 10 min after it ...
check "fresh notice wakes nobody" "$(tm)" "rc=1 rc=1 rc=1 "
# ... then a dead taker is failed over in turn (notice names bob as holder: carol next)
export HIVE_NOW=$((HIVE_NOW + 700)); rm -f "$T"/state-*/.hive-failover-*
check "dead taker failed over in turn" "$(for a in alice carol; do wake $a; done | tr '\n' ' ')" "rc=1 HIVE_TAKEOVER $M rc=0 "
export HIVE_NOW=1800000000
check "role taken through the private channel" "$(grep -c 'TM bob until failover 18' "$T/ntfy.log")" 1
check "local takeover marker" "$(cut -d' ' -f1 "$T/state-bob/takeover")" bob
# the next hive-succession run keeps the taker (it used to recompute the role away); an expired marker does not
acct carol; real=$(date +%s)
printf '%s|bob|TM|bob until failover %s (from alice)\n' "$real" $((real + 3600)) >> "$HIVE_STATE_DIR/msg-inbox.log"
echo alice > "$HIVE_STATE_DIR/triagemaster"
check "succession honours a live takeover" "$(bash "$AG/hive-succession.sh" 2>/dev/null)" bob
check "and writes it to the role file" "$(cat "$HIVE_STATE_DIR/triagemaster")" bob
: > "$HIVE_STATE_DIR/msg-inbox.log"; printf '%s|bob|TM|bob until failover %s\n' "$real" $((real - 5)) >> "$HIVE_STATE_DIR/msg-inbox.log"
echo alice > "$HIVE_STATE_DIR/triagemaster"
check "an expired takeover is not honoured" "$(bash "$AG/hive-succession.sh" 2>/dev/null)" alice
# takeover re-checks on fresh data: a second machine acting on a stale wake exits 3 and posts nothing
setup_inboxes 100; human "$M" | jq -s '.' > "$T/msgs.json"
acct bob; bash "$H" takeover "$M" >/dev/null
nb=$(jq '[.[] | select(.author.bot)] | length' "$T/msgs.json")
acct carol; bash "$H" takeover "$M" >/dev/null; check "second takeover (fresh notice) exits 3" $? 3
check "and posts no notice" "$(jq '[.[] | select(.author.bot)] | length' "$T/msgs.json")" "$nb"
# a machine that is not the designated successor refuses even with an old, unanswered message
setup_inboxes 100; human "$M" | jq -s '.' > "$T/msgs.json"
acct carol; bash "$H" takeover "$M" >/dev/null; check "non-successor takeover exits 3" $? 3
# and a message under 10 minutes old is not due
human "$(mkid $((HIVE_NOW - 200)) 1)" | jq -s '.' > "$T/msgs.json"
acct bob; bash "$H" takeover "$(mkid $((HIVE_NOW - 200)) 1)" >/dev/null; check "young message takeover exits 3" $? 3
check "dcurl has a timeout" "$(grep -c -- '-m 15' "$T/args.log" | awk '{print ($1 > 0)}')" 1
# a stale local marker never outvotes a newer takeover, and an expired or superseded one is removed
acct carol; real=$(date +%s); : > "$HIVE_STATE_DIR/msg-inbox.log"
echo "bob $((real + 3000)) $((real - 1000))" > "$HIVE_STATE_DIR/takeover"
printf '%s|alice|TM|alice until failover %s (from bob)\n' "$((real - 10))" $((real + 7200)) >> "$HIVE_STATE_DIR/msg-inbox.log"
check "newer TM beats an older local marker" "$(bash "$AG/hive-succession.sh" 2>/dev/null)" alice
check "superseded marker removed" "$([ -f "$HIVE_STATE_DIR/takeover" ] && echo kept || echo gone)" gone
: > "$HIVE_STATE_DIR/msg-inbox.log"; echo "bob $((real + 3000)) $((real - 10))" > "$HIVE_STATE_DIR/takeover"
printf '%s|alice|TM|alice until failover %s\n' "$((real - 500))" $((real + 7200)) >> "$HIVE_STATE_DIR/msg-inbox.log"
check "newer local marker beats an older TM" "$(bash "$AG/hive-succession.sh" 2>/dev/null)" bob
echo "bob $((real - 5)) $((real - 9000))" > "$HIVE_STATE_DIR/takeover"; : > "$HIVE_STATE_DIR/msg-inbox.log"; echo alice > "$HIVE_STATE_DIR/triagemaster"
check "expired local marker ignored" "$(bash "$AG/hive-succession.sh" 2>/dev/null)" alice
check "expired marker removed" "$([ -f "$HIVE_STATE_DIR/takeover" ] && echo kept || echo gone)" gone
# writes get the longer limit, reads the 15 s one
check "post uses the write limit" "$(grep -c -- '-m 45' "$T/args.log" | awk '{print ($1 > 0)}')" 1
# a notice POST that times out but landed is found, not posted twice
setup_inboxes 100; human "$M" | jq -s '.' > "$T/msgs.json"; touch "$T/postlost"
acct bob; out=$(bash "$H" takeover "$M"); check "lost post response: takeover still wins" "$out" "TAKEOVER_OK from alice"
check "and posted exactly one notice" "$(jq '[.[] | select(.author.bot)] | length' "$T/msgs.json")" 1
rm -f "$T/postlost"
# retry after a lost post whose first run died before claiming: the existing notice is ours, so finish the claim
setup_inboxes 100; { human "$M"; bot "$(mkid $((HIVE_NOW - 60)) 2)" "$M" "taking over from alice (now bob)"; } | jq -s '.' > "$T/msgs.json"
acct bob; rm -f "$HIVE_STATE_DIR/takeover"; : > "$T/ntfy.log"
out=$(bash "$H" takeover "$M"); check "retry finishes the claim" "$out" "TAKEOVER_OK (notice already posted)"
check "retry wrote the marker" "$(cut -d' ' -f1 "$HIVE_STATE_DIR/takeover")" bob
check "retry sent the TM" "$(grep -c 'TM bob until failover' "$T/ntfy.log")" 1
bash "$H" takeover "$M" >/dev/null; check "retry again sends no second TM" "$(grep -c 'TM bob until failover' "$T/ntfy.log")" 1
check "and posted no new notice" "$(jq '[.[] | select(.author.bot)] | length' "$T/msgs.json")" 1
# hive-succession.sh keeps its own args (--post) when a (here expired) failover marker is in the inbox: the weekly handoff still sends TM
acct carol; rt=$(date +%s); : > "$T/ntfy.log"; rm -f "$HIVE_STATE_DIR/takeover" "$HIVE_STATE_DIR/triagemaster"
printf '%s|bob|TM|bob until failover %s\n' "$rt" $((rt - 5)) > "$HIVE_STATE_DIR/msg-inbox.log"
printf '%s|alice|USAGE|10%% 96%% 2099-01-01T00:00:00Z r5=2099-01-01T00:00:00Z at=%s\n' "$rt" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$HIVE_STATE_DIR/msg-inbox.log"
echo '{"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":4102444800},"five_hour":{"used_percentage":5,"resets_at":4102444800}}}' > "$HIVE_STATE_DIR/usage-snapshot.json"
check "handoff picks the stand-in" "$(HIVE_ACCOUNTS_DIR= bash "$AG/hive-succession.sh" --post 2>/dev/null)" carol
check "handoff TM still sent with --post" "$(grep -c 'TM carol until' "$T/ntfy.log")" 1
# I) two machines never both take over: a rival's earlier notice lands while bob posts
setup_inboxes 100; human "$M" | jq -s '.' > "$T/msgs.json"; touch "$T/race"
acct bob; out=$(bash "$H" takeover "$M"); rc=$?
check "loser exits 3" "$rc" 3
check "loser removed its notice" "$(jq '[.[] | select(.author.bot)] | length' "$T/msgs.json")" 1
check "loser keeps the old role" "$(cat "$HIVE_STATE_DIR/triagemaster")" alice
rm -f "$T/race"
# J) already answered by the time takeover runs
{ human "$M"; bot "$(mkid $((HIVE_NOW - 10)) 2)" "$M" "Done"; } | jq -s '.' > "$T/msgs.json"
acct carol; bash "$H" takeover "$M" >/dev/null; check "takeover after an answer exits 3" $? 3
# K) no discord.conf: asks the owner once, never silent
acct dave; rm -f "$HIVE_STATE_DIR/discord.conf" "$HIVE_STATE_DIR/.hive-noconf-asked"
printf 'HIVE_MSG_TOPIC=hive-test\n' > "$HIVE_STATE_DIR/msg.conf"; : > "$T/ntfy.log"
bash "$H" check >/dev/null 2>&1; check "no conf exits 2" $? 2
bash "$H" check >/dev/null 2>&1
check "asked the owner once" "$(grep -c 'ASK' "$T/ntfy.log")" 1
# L) Discord failing: no wake
setup_inboxes 100; echo '{"message":"401","code":0}' > "$T/msgs.json"
check "Discord failure wakes nobody" "$(tm)" "rc=2 rc=2 rc=2 "
echo "hive-failover: $pass passed, $fail failed"; [ "$fail" = 0 ]
