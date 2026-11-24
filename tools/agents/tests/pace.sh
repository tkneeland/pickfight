#!/bin/bash
# Offline test for hive-env.sh's budget, worker target and quiet hours: hive_budget_ok (the own weekly stop, its reset grace
# window, 100% as a hard stop), hive_worker_target (5h stop, pace governor AHEAD, the max workers and its tuned value),
# hive_quiet (this account and a peer's conf, including a pre-pace conf with NIGHT_START/NIGHT_END), and hive-at-mode.sh.
# Scratch HIVE_STATE_DIR with a written usage snapshot. No network. macOS, Linux and Git Bash.   bash tools/agents/tests/pace.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-pace-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
mkdir -p "$T/state"
git init -q "$T/repo"; git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export HIVE_STATE_DIR=$T/state REPO_PATH=$T/repo HIVE_ACCOUNT=alice
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
now=$(date +%s)
# snap <weekly %> <hours until the weekly reset> <5h %> [seconds until the 5h reset; none = no 5h window]
snap() { local r5=0; [ -n "${4:-}" ] && r5=$(( now + $4 ))
  printf '{"rate_limits":{"seven_day":{"used_percentage":%s,"resets_at":%s},"five_hour":{"used_percentage":%s,"resets_at":%s}}}\n' \
  "$1" "$(( now + $2 * 3600 ))" "$3" "$r5" > "$T/state/usage-snapshot.json"; }
ev() { bash -c '. "$1/hive-env.sh" >/dev/null 2>&1 || exit 9; eval "$2"' _ "$AG" "$1"; }
ok() { ev 'hive_budget_ok && echo ok || echo stop'; }

# --- budget: the own weekly stop (80% used here), ignored in the last RESET_GRACE_HOURS (24), except at 100%
rm -f "$T/state/usage-snapshot.json"; check "B1 no snapshot: ok" "$(ok)" ok
printf '\nMIN_WEEKLY_REMAINING_FOR_TICKETS=20\n' >> "$AG/accounts/alice.conf"
snap 79 84 0;  check "B2 under the stop" "$(ok)" ok
snap 80 84 0;  check "B3 at the stop" "$(ok)" stop
snap 95 10 0;  check "B4 over the stop in the grace window" "$(ok)" ok
snap 100 10 0; check "B5 100% in the grace window" "$(ok)" stop
sed -i.x '/^MIN_WEEKLY_REMAINING_FOR_TICKETS=/d' "$AG/accounts/alice.conf"
snap 99 84 0;  check "B6 no stop set: 99% ok" "$(ok)" ok
snap 100 84 0; check "B7 no stop set: 100% stops" "$(ok)" stop

# --- worker target: 0 at the weekly stop, at the 5h stop (window open), or AHEAD; else the max workers
snap 50 84 0;  check "W1 behind: the max" "$(ev hive_worker_target)" "3"
snap 50 84 50 9000; check "W2 on pace: the max" "$(ev hive_worker_target)" "3"
snap 60 84 0;  check "W3 weekly ahead of pace: 0" "$(ev hive_worker_target)" "0"
snap 50 84 80 9000; check "W4 5h ahead of pace: 0" "$(ev hive_worker_target)" "0"
snap 10 84 95 3600; check "W5 5h stop, window open: 0" "$(ev hive_worker_target)" "0"
snap 10 84 95; check "W6 5h stop, reset unknown: 0" "$(ev hive_worker_target)" "0"
snap 100 84 0; check "W7 weekly 100%: 0" "$(ev hive_worker_target)" "0"
snap 99 10 0;  check "W8 reset grace spends, not ahead" "$(ev hive_worker_target)" "3"
printf '\nMAX_WORKERS=5\nFIVE_H_STOP_USED=60\n' >> "$AG/accounts/alice.conf"
snap 10 84 0;  check "W9 the conf's max workers" "$(ev hive_worker_target)" "5"
snap 10 84 65 3600; check "W10 its own 5h stop" "$(ev hive_worker_target)" "0"
printf 'MAX_WORKERS=2\n' > "$T/state/pace-tuning.conf"
snap 10 84 0;  check "W11 the tuned max" "$(ev hive_worker_target)" "2"
rm -f "$T/state/pace-tuning.conf"; sed -i.x '/^MAX_WORKERS=/d; /^FIVE_H_STOP_USED=/d' "$AG/accounts/alice.conf"

# --- quiet hours, from the current hour in each conf's TZ
hr() { h=$(TZ=$1 date +%H); echo $((10#$h)); }
a=$(hr America/New_York)
setq() { sed -i.x "/^QUIET_START=/d; /^QUIET_END=/d; /^NIGHT_START=/d; /^NIGHT_END=/d" "$AG/accounts/$1.conf"; printf '%s=%s\n%s=%s\n' "$2" "$3" "$4" "$5" >> "$AG/accounts/$1.conf"; }
setq alice QUIET_START "$a" QUIET_END $(( (a + 1) % 24 ))
check "Q1 own quiet" "$(ev 'hive_quiet && echo y || echo n')" "y"
setq alice QUIET_START $(( (a + 1) % 24 )) QUIET_END $(( (a + 2) % 24 ))
check "Q2 own not quiet" "$(ev 'hive_quiet && echo y || echo n')" "n"
setq alice QUIET_START $(( (a + 1) % 24 )) QUIET_END "$a"
check "Q3 wrapping window, hour outside" "$(ev 'hive_quiet && echo y || echo n')" "n"
setq alice QUIET_START $(( (a + 23) % 24 )) QUIET_END $(( (a + 1) % 24 ))
check "Q4 wrapping window, hour inside" "$(ev 'hive_quiet && echo y || echo n')" "y"
sed -i.x 's#^TZ=.*#TZ=Asia/Tokyo#' "$AG/accounts/bob.conf"; b=$(hr Asia/Tokyo)
setq bob QUIET_START "$b" QUIET_END $(( (b + 1) % 24 ))
check "Q5 peer's own TZ and hours" "$(ev 'hive_quiet bob && echo y || echo n')" "y"
setq bob NIGHT_START "$b" NIGHT_END $(( (b + 1) % 24 ))
check "Q6 peer pre-pace NIGHT_* conf" "$(ev 'hive_quiet bob && echo y || echo n')" "y"
setq bob QUIET_START $(( (b + 1) % 24 )) QUIET_END $(( (b + 2) % 24 ))
check "Q7 peer not quiet" "$(ev 'hive_quiet bob && echo y || echo n')" "n"

# --- hive-at-mode.sh: the pace governor's state
snap 20 84 50 9000; check "M1 label on pace" "$(bash "$AG/hive-at-mode.sh")" "AT·on pace"
snap 60 84 0;  check "M2 label ahead" "$(bash "$AG/hive-at-mode.sh")" "AT·ahead"
snap 20 84 0;  check "M2b label behind" "$(bash "$AG/hive-at-mode.sh")" "AT·behind"
echo $(( now + 3600 )) > "$T/state/day-until"; bash "$AG/hive-at-mode.sh" >/dev/null
check "M3 stale day-until removed" "$([ -e "$T/state/day-until" ] && echo kept || echo gone)" "gone"
bash "$AG/hive-at-mode.sh" MT >/dev/null; check "M4 MT" "$(bash "$AG/hive-at-mode.sh")" "MT"

echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
