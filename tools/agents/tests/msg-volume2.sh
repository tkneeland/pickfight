#!/bin/bash
# msg-quota.sh part "volume2" (hours 8-16 of the 24 h steady-state send volume); a separate file so all.sh gives it its own watchdog (issue #338).
exec bash "$(cd "$(dirname "$0")" && pwd)/msg-quota.sh" volume2
