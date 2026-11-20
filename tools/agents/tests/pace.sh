#!/bin/bash
# Offline test for pace and quiet hours in hive-env.sh: hive_pace, hive_worker_target, hive_quiet (this account and a peer's
# conf, including a pre-pace conf with NIGHT_START/NIGHT_END), the DAY_AGENTS fallback for WORKER_TARGET, and hive-at-mode.sh.
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
# snap <weekly %> <hours until the weekly reset> <5h %>
snap() { printf '{"rate_limits":{"seven_day":{"used_percentage":%s,"resets_at":%s},"five_hour":{"used_percentage":%s}}}\n' \
  "$1" "$(( now + $2 * 3600 ))" "$3" > "$T/state/usage-snapshot.json"; }
ev() { bash -c '. "$1/hive-env.sh" >/dev/null 2>&1 || exit 9; eval "$2"' _ "$AG" "$1"; }

# --- pace: halfway through the week the line is 42.5 + 10 slack
snap 50 84 0;  check "P1 halfway 50% on pace" "$(ev hive_pace)" "on pace"
snap 60 84 0;  check "P2 halfway 60% ahead" "$(ev hive_pace)" "ahead"
snap 5 167 0;  check "P3 first hour 5% on pace (slack)" "$(ev hive_pace)" "on pace"
rm -f "$T/state/usage-snapshot.json"; check "P4 no snapshot on pace" "$(ev hive_pace)" "on pace"

# --- worker target
snap 50 84 0;  check "W1 on pace" "$(ev hive_worker_target)" "3"
snap 60 84 0;  check "W2 ahead of pace" "$(ev hive_worker_target)" "1"
snap 50 84 75; check "W3 5h slow" "$(ev hive_worker_target)" "1"
snap 50 84 95; check "W4 5h stop" "$(ev hive_worker_target)" "0"
snap 90 84 0;  check "W5 weekly stop" "$(ev hive_worker_target)" "0"
snap 90 10 0;  check "W6 reset grace spends, not ahead" "$(ev hive_worker_target)" "3"
cp "$AG/accounts/_shared.conf" "$T/shared.bak"
sed -i.x '/^WORKER_TARGET=/d; /^PACE_SLACK=/d' "$AG/accounts/_shared.conf"; echo DAY_AGENTS=4 >> "$AG/accounts/_shared.conf"
snap 50 84 0;  check "W7 pre-pace DAY_AGENTS fallback" "$(ev hive_worker_target)" "4"
cp "$T/shared.bak" "$AG/accounts/_shared.conf"

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

# --- hive-at-mode.sh
snap 50 84 0;  check "M1 label on pace" "$(bash "$AG/hive-at-mode.sh")" "AT·on pace"
snap 60 84 0;  check "M2 label ahead" "$(bash "$AG/hive-at-mode.sh")" "AT·ahead"
echo $(( now + 3600 )) > "$T/state/day-until"; bash "$AG/hive-at-mode.sh" >/dev/null
check "M3 stale day-until removed" "$([ -e "$T/state/day-until" ] && echo kept || echo gone)" "gone"
bash "$AG/hive-at-mode.sh" MT >/dev/null; check "M4 MT" "$(bash "$AG/hive-at-mode.sh")" "MT"

echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
