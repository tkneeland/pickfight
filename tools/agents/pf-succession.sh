#!/bin/bash
# Works out who holds the triagemaster role and writes it to $PF_STATE/pf-triagemaster. Prints the holder.
# Rank-1 holder keeps the role until its weekly used >= HANDOFF_WEEKLY_USED with more than RESET_GRACE_HOURS
# until its reset, or >= HANDOFF_HARD_WEEKLY_USED (95%) at any time; then the next SUCCESSION_RANK with a beacon under 6h old and under HANDOFF_WEEKLY_USED holds it.
# The role returns on its own once the original holder's weekly resets. Beacons are the #432 comments.
# With --post, the stand-in itself posts "[TRIAGEMASTER] <handle> until <reset ISO>" on #432 when it takes over.
. "$(dirname "$0")/pf-env.sh" || exit 1
now=$(date +%s)
iso2e() { pf_iso_to_epoch "$1" || echo 0; }
comments=$(gh api "repos/$REPO/issues/432/comments?per_page=100" 2>/dev/null) || { pf_triagemaster; exit 0; }
beacon() { pf_beacon "$1" "$comments"; }  # sets b_age b_used b_reset for handle $1 (pf-env.sh)
order=$(for h in $(pf_handles); do r=$(sed -n 's/^SUCCESSION_RANK=\([0-9]*\).*/\1/p' "$PF_DIR/accounts/$h.conf"); echo "$r $h"; done | sort -n | awk '{print $2}')
first=$(echo "$order" | head -1)
beacon "$first"; holder=$first; reset0=$b_reset
if [ "$b_age" -lt 21600 ] && [ -n "$b_used" ] && { [ "$b_used" -ge "${HANDOFF_HARD_WEEKLY_USED:-95}" ] || { [ "$b_used" -ge "$HANDOFF_WEEKLY_USED" ] && [ $(( $(iso2e "$b_reset") - now )) -gt $(( RESET_GRACE_HOURS * 3600 )) ]; }; }; then
  for h in $(echo "$order" | tail -n +2); do
    beacon "$h"
    if [ "$b_age" -lt 21600 ] && [ -n "$b_used" ] && [ "$b_used" -lt "$HANDOFF_WEEKLY_USED" ]; then holder=$h; break; fi
  done
fi
prev=$(cat "$PF_STATE/pf-triagemaster" 2>/dev/null)
echo "$holder" > "$PF_STATE/pf-triagemaster"
if [ "$holder" != "$prev" ] && [ "$holder" != "$first" ] && [ "$holder" = "$PF_ACCOUNT" ] && [ "${1:-}" = "--post" ] && [ -z "${PF_DRY_RUN:-}" ]; then
  gh issue comment 432 -R "$REPO" --body "[TRIAGEMASTER] $holder until $reset0" >/dev/null 2>&1
fi
echo "$holder"
