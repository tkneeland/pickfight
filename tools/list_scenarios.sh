#!/usr/bin/env bash
# Prints the scenario names from SCENARIO_NAMES in tools/scenario_runner.gd.
#
#   tools/list_scenarios.sh            one name per line, in suite order
#   tools/list_scenarios.sh <i> <k>    shard i of k (0-based) as a comma list:
#                                      a contiguous slice of the suite order,
#                                      ready for `-- --scenarios=<list>`
#   tools/list_scenarios.sh --check [<runner.gd>]
#                                      checks SCENARIO_NAMES against the
#                                      `_run_scenario` match (#1150): exits 1
#                                      naming each duplicate name, listed name
#                                      with no arm, arm with no listed name,
#                                      and list line this script cannot read
#                                      (CI would skip it). The file defaults to
#                                      tools/scenario_runner.gd.
#
# Used by .github/workflows/scenarios.yml (#186).
set -euo pipefail

# --check takes an optional file; resolve it before the cd below.
check_file=tools/scenario_runner.gd
if [ "${1:-}" = "--check" ] && [ $# -ge 2 ]; then
	case $2 in
		/* | [A-Za-z]:*) check_file=$2 ;;
		*) check_file=$PWD/$2 ;;
	esac
fi
cd "$(dirname "$0")/.."

if [ "${1:-}" = "--check" ]; then
	if [ ! -f "$check_file" ]; then
		echo "list_scenarios --check: no such file: $check_file" >&2
		exit 2
	fi
	# Exact string keys throughout, so a name that is a substring of another
	# never matches it. Arms are the two-tab `"name":` lines between
	# `func _run_scenario` and its `_:` arm; bodies (await, multi-line) sit
	# deeper and are ignored, as are comments and blank lines. A one-line arm
	# (`"name": return ...`) counts too.
	awk '
		function err(msg) { print "list_scenarios --check: " msg > "/dev/stderr"; bad++ }
		{ sub(/\r$/, "") }
		/^const SCENARIO_NAMES/ { inlist = 1; seenlist = 1; next }
		inlist && /^\]/ { inlist = 0; next }
		inlist {
			if ($0 ~ /^[ \t]*$/ || $0 ~ /^[ \t]*#/) next
			if ($0 !~ /^[ \t]*"[a-z0-9_]*",?[ \t]*$/) { err("line " NR " in SCENARIO_NAMES is not a plain \"name\", entry, so CI would skip it: " $0); next }
			name = $0; sub(/^[ \t]*"/, "", name); sub(/".*$/, "", name)
			if (name in listed) { err("duplicate name in SCENARIO_NAMES: " name " (lines " listed[name] " and " NR ")"); next }
			listed[name] = NR; lorder[++nl] = name
			next
		}
		/^func _run_scenario\(/ { indisp = 1; seendisp = 1; next }
		indisp && (/^\t\t_:/ || /^func /) { indisp = 0; next }
		indisp && /^\t\t"/ {
			# `"a":`, `"a", "b":` or a one-line arm `"a": return ...`.
			pats = $0; sub(/^\t\t/, "", pats)
			if (!match(pats, /^"[a-z0-9_]*"([ \t]*,[ \t]*"[a-z0-9_]*")*[ \t]*:/)) { err("line " NR " is not a plain \"name\": arm: " $0); next }
			pats = substr(pats, 1, RLENGTH - 1)
			n = split(pats, parts, /[ \t]*,[ \t]*/)
			for (j = 1; j <= n; j++) {
				p = parts[j]; sub(/[ \t]*$/, "", p)
				p = substr(p, 2, length(p) - 2)
				if (p in arm) { err("duplicate dispatcher arm: " p " (lines " arm[p] " and " NR ")"); continue }
				arm[p] = NR; aorder[++na] = p
			}
		}
		END {
			if (!seenlist) err("no const SCENARIO_NAMES found")
			if (!seendisp) err("no func _run_scenario found")
			for (j = 1; j <= nl; j++) if (!(lorder[j] in arm)) err("listed but no dispatcher arm: " lorder[j] " (line " listed[lorder[j]] ")")
			for (j = 1; j <= na; j++) if (!(aorder[j] in listed)) err("dispatcher arm but not listed in SCENARIO_NAMES: " aorder[j] " (line " arm[aorder[j]] ")")
			if (nl == 0) err("found no names in SCENARIO_NAMES")
			if (bad) exit 1
			print "list_scenarios --check: OK, " nl " names, each with one dispatcher arm"
		}
	' "$check_file"
	exit $?
fi

# A while-read loop, not mapfile: macOS ships bash 3.2, which has no mapfile
# (#195).
names=()
while IFS= read -r name; do
	names+=("$name")
done < <(
	awk '/^const SCENARIO_NAMES/{f=1;next} f&&/^\]/{exit} f' tools/scenario_runner.gd \
		| sed -n 's/^[[:space:]]*"\([a-z0-9_]*\)",\{0,1\}[[:space:]]*$/\1/p'
)
if [ "${#names[@]}" -eq 0 ]; then
	echo "list_scenarios: found no names in SCENARIO_NAMES" >&2
	exit 1
fi

if [ $# -eq 0 ]; then
	printf '%s\n' "${names[@]}"
	exit 0
fi

i=$1; k=$2
if [ "$k" -lt 1 ] || [ "$i" -lt 0 ] || [ "$i" -ge "$k" ]; then
	echo "list_scenarios: shard index must be 0..k-1" >&2
	exit 2
fi
n=${#names[@]}
start=$(( n * i / k ))
end=$(( n * (i + 1) / k ))
slice=("${names[@]:start:end-start}")
(IFS=,; echo "${slice[*]}")
