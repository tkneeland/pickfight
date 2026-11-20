#!/bin/bash
# Offline test for hive-control.sh (the hub's buttons), the beacon's tmaker field (and no mode=), and hive-join.sh recording the
# checkout the voice runner runs controls in. Scratch state, no network.   bash tools/agents/tests/control.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-control-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
mkdir -p "$T/state"
export HIVE_STATE_DIR=$T/state HIVE_ACCOUNT=alice HIVE_CONTROL_NOBEACON=1 HIVE_DRY_RUN=1
fails=0
ok() { if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
ctl() { bash "$AG/hive-control.sh" "$@"; }

[ "$(ctl state)" = '{"ticketmaker":"on"}' ]; ok "state: defaults" $?
[ "$(ctl ticketmaker off)" = '{"ticketmaker":"off"}' ]; ok "ticketmaker off" $?
[ "$(cat "$T/state/ticketmaker")" = off ]; ok "...through hive-ticketmaker.sh's file" $?
ctl ticketmaker on >/dev/null
for bad in "mode MT" "mode AT" "ticketmaker maybe" "shell ls" "mode" "" "state extra"; do
  # shellcheck disable=SC2086
  ctl $bad >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ]; ok "refused: '$bad'" $?
done
[ "$(ctl state)" = '{"ticketmaker":"on"}' ]; ok "refusals changed nothing" $?
[ ! -e "$T/state/at-mode" ]; ok "...and never touched at-mode" $?

# hive-join.sh records where this project's scripts are
bash "$AG/hive-join.sh" >/dev/null
[ "$(cat "$T/state/checkout")" = "$(cd "$AG" && pwd)" ]; ok "join: checkout recorded" $?
[ -f "$(cat "$T/state/checkout")/hive-control.sh" ]; ok "join: it holds hive-control.sh" $?

# the beacon carries tmaker; mode= is retired (issue #58), even with the local at-mode file at MT
mkdir -p "$T/bin"; printf '#!/bin/bash\n[ "$1" = send ] && echo "$3" >> "%s/sent"\nexit 0\n' "$T" > "$T/bin/msg"; chmod +x "$T/bin/msg"
cp "$T/bin/msg" "$AG/hive-msg.sh"
echo '{"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1800000000},"seven_day":{"used_percentage":34,"resets_at":1800000000}}}' > "$T/state/usage-snapshot.json"
echo HIVE_MSG_TOPIC=x > "$T/state/msg.conf"
ctl ticketmaker off >/dev/null; bash "$AG/hive-at-mode.sh" MT >/dev/null
bash "$AG/hive-beacon.sh" 2>/dev/null
grep -q " tmaker=off$" "$T/sent"; ok "beacon: tmaker=off" $?
! grep -q " mode=" "$T/sent"; ok "beacon: the retired mode= field is gone" $?
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
