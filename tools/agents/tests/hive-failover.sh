#!/bin/bash
# Offline test for pf-hive-failover.sh (#1210): a stub curl serves canned Discord JSON, a
# scratch PF_STATE_DIR per simulated account, a fake private-channel inbox for heartbeats. No network.
#   bash tools/agents/tests/hive-failover.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-hive-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/r"
cat > "$T/bin/curl" <<EOS
#!/bin/bash
cfg=\$(cat); url=\$(printf '%s\n' "\$cfg" | sed -n 's/^url = "\(.*\)"/\1/p')
k=\$(printf '%s' "\$url" | sed 's|.*/v10/||; s|[/?&=@]|_|g')
[ -f "$T/r/\$k" ] && cat "$T/r/\$k" || echo '{"message":"Unknown"}'
EOS
chmod +x "$T/bin/curl"; export PATH=$T/bin:$PATH
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
NOW=1794000000   # fixed clock
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S; }
msg() { echo "{\"id\":\"$1\",\"timestamp\":\"$(iso "$2").000000+00:00\",\"author\":{\"username\":\"$3\",\"bot\":$4},\"content\":\"x\"}"; }
HIVE=1569919897591611552   # PF_DISCORD_DEFAULT_DEV
# state dir with the bot conf per account
for a in agage-JG schans2 tkneeland; do mkdir -p "$T/state-$a"; printf 'PF_DISCORD_TOKEN=tok\n' > "$T/state-$a/pf-discord.conf"; done
STALE=""
# inbox: a HELLO per account, 5 min old, or 2 h old for the accounts named in $STALE
inbox() { : > "$1/msg-inbox.log"; for h in agage-JG schans2 tkneeland tommykneeland; do
  case " $STALE " in *" $h "*) t=$((NOW-7200));; *) t=$((NOW-300));; esac; echo "$t|$h|HELLO|$h" >> "$1/msg-inbox.log"; done; }
run() {  # run <account>: one failover pass as that account; tkneeland is the triagemaster
  s=$T/state-$1; echo tkneeland > "$s/pf-triagemaster"; inbox "$s"
  PF_NOW=$NOW PF_ACCOUNT=$1 PF_STATE_DIR=$s bash "$AG/pf-hive-failover.sh" 2>/dev/null; }
reset() { rm -f "$T"/state-*/.hive-takeover-seen; }
CHAN="$T/r/channels_${HIVE}_messages_limit_50"
# 1. one unanswered dev message, 11 minutes old
echo "[$(msg 555000000000000100 $((NOW-660)) sam false)]" > "$CHAN"
check "lower-ranked account stays quiet" "$(run schans2)" ""
check "the triagemaster stays quiet" "$(run tkneeland)" ""
check "next-ranked live account wakes" "$(run agage-JG)" "HIVE_TAKEOVER 555000000000000100"
check "the same message never wakes it twice" "$(run agage-JG)" ""
# 2. rank 2 has a stale heartbeat: it is skipped and rank 3 is next
reset; STALE="agage-JG"
check "rank 3 wakes in its place" "$(run schans2)" "HIVE_TAKEOVER 555000000000000100"
# 3. only 5 minutes old: not yet
reset; STALE=""
echo "[$(msg 555000000000000100 $((NOW-300)) sam false)]" > "$CHAN"
check "under 10 minutes waits" "$(run agage-JG)" ""
# 4. the triagemaster's bot answered
echo "[$(msg 555000000000000100 $((NOW-900)) sam false),$(msg 555000000000000101 $((NOW-800)) Pickfight true)]" > "$CHAN"
check "an answered message wakes nobody (rank 2)" "$(run agage-JG)" ""
check "an answered message wakes nobody (rank 3)" "$(run schans2)" ""
# 5. a later dev message after that answer is unanswered
echo "[$(msg 555000000000000102 $((NOW-700)) austin false),$(msg 555000000000000100 $((NOW-900)) sam false),$(msg 555000000000000101 $((NOW-800)) Pickfight true)]" > "$CHAN"
check "only the unanswered message wakes" "$(run agage-JG)" "HIVE_TAKEOVER 555000000000000102"
# 6. no pf-discord.conf: quiet exit, owner asked once
rm -f "$T/state-schans2/pf-discord.conf"
out=$(PF_NOW=$NOW PF_ACCOUNT=schans2 PF_STATE_DIR=$T/state-schans2 bash "$AG/pf-hive-failover.sh" 2>&1); check "no conf exits quietly" "$out" ""
check "no conf leaves the ask marker" "$([ -f "$T/state-schans2/.hive-noconf-asked" ] && echo yes)" yes
echo "hive-failover: $pass passed, $fail failed"; [ "$fail" = 0 ]
