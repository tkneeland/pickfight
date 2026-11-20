#!/bin/bash
# Offline test for REPO_PATHS in hive-env.sh (#217): drive-letter (C:/ and C:\), POSIX (/x, /cygdrive/...) and relative
# entries. Relative entries resolve under HIVE_ROOT; absolute ones pass through unchanged. No network.
# macOS, Linux and Git Bash.   bash tools/agents/tests/repo-paths.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-repopaths-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
unset REPO_PATH

# env_of <var> <REPO_PATHS value>: the value hive-env.sh leaves in <var>, read from a fresh shell that sources it
env_of() {
  REPO_PATHS=$2 HIVE_ACCOUNT=alice HIVE_STATE_DIR=$T/state bash -c ". '$AG/hive-env.sh' >/dev/null 2>&1 && printf '%s' \"\$$1\""
}

pass=0; fail=0
check() { # check <label> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', want '$3'"; fi
}

root=$(env_of HIVE_ROOT "$AG")
[ -n "$root" ] || { echo "FAIL could not read HIVE_ROOT from hive-env.sh"; exit 1; }

check "drive-letter forward slash" "$(env_of REPO_PATHS 'C:/x/y')" "C:/x/y"
check "drive-letter backslash"     "$(env_of REPO_PATHS 'C:\x\y')"  'C:\x\y'
check "drive-letter lowercase"     "$(env_of REPO_PATHS 'd:/x/y')"  "d:/x/y"
check "POSIX absolute"            "$(env_of REPO_PATHS '/x/y')"    "/x/y"
check "cygdrive absolute"         "$(env_of REPO_PATHS '/cygdrive/c/x/y')" "/cygdrive/c/x/y"
check "relative"                  "$(env_of REPO_PATHS 'x/y')"     "$root/x/y"
check "mixed list"                "$(env_of REPO_PATHS 'C:/a /x/y rel')" "C:/a /x/y $root/rel"

# TRACKER_DIR (TRACKER=local) uses the same absolute-path test; the dir must exist, so use real ones.
trk_of() {
  TRACKER=local TRACKER_DIR=$1 HIVE_ACCOUNT=alice HIVE_STATE_DIR=$T/state bash -c ". '$AG/hive-env.sh' >/dev/null 2>&1 && printf '%s' \"\$TRACKER_DIR\""
}
mkdir -p "$T/trk" "$root/trk-rel"
check "TRACKER_DIR POSIX absolute" "$(trk_of "$T/trk")" "$T/trk"
check "TRACKER_DIR relative"       "$(trk_of trk-rel)"   "$root/trk-rel"
if command -v cygpath >/dev/null 2>&1; then # Git Bash: the same dir as a drive-letter path must pass through unchanged
  win=$(cygpath -m "$T/trk")
  check "TRACKER_DIR drive-letter" "$(trk_of "$win")" "$win"
fi
rm -rf "$root/trk-rel"

echo "repo-paths: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
