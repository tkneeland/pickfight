#!/usr/bin/env bash
# Prints the scenario names from SCENARIO_NAMES in tools/scenario_runner.gd.
#
#   tools/list_scenarios.sh            one name per line, in suite order
#   tools/list_scenarios.sh <i> <k>    shard i of k (0-based) as a comma list:
#                                      a contiguous slice of the suite order,
#                                      ready for `-- --scenarios=<list>`
#
# Used by .github/workflows/scenarios.yml (#186).
set -euo pipefail
cd "$(dirname "$0")/.."

mapfile -t names < <(
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
