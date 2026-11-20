#!/bin/bash
# Runs every offline test in this folder (no network). Exit 0 only when all pass.   bash tools/agents/tests/all.sh
d=$(cd "$(dirname "$0")" && pwd); bad=""
for t in "$d"/*.sh; do
  case ${t##*/} in all.sh|lib.sh) continue;; esac
  if out=$(bash "$t" 2>&1); then echo "PASS ${t##*/}: $(printf '%s\n' "$out" | tail -n 1)"
  else echo "FAIL ${t##*/}"; printf '%s\n' "$out" | grep -E 'FAIL|failed' | sed 's/^/    /'; bad="$bad ${t##*/}"; fi
done
[ -z "$bad" ] && echo "all tests passed" || { echo "failed:$bad"; exit 1; }
