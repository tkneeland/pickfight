#!/bin/bash
# Usage: hive-notify.sh <FIRE|DIGEST|DONE|FILED> "<one line>"
# Appends a tagged line to the outbox the main terminal watches (hive-outbox-wait.sh). Zero tokens.
. "$(dirname "$0")/hive-env.sh" || exit 1
[ $# -ge 2 ] || { sed -n '2,3p' "$0"; exit 2; }
tag=$1; shift
hive_outbox "$tag" "$*"
