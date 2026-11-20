#!/bin/bash
# msg-quota.sh part "beacon" (USAGE gate, HELLO, peer-silent and locks); a separate file so all.sh gives it its own watchdog (issue #338).   bash tools/agents/tests/msg-beacon.sh
exec bash "$(cd "$(dirname "$0")" && pwd)/msg-quota.sh" beacon
