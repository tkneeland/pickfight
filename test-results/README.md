# Test results

Evidence for the latest work package only: issue #91 (arm draws over the identity outline).

- `issue-91/full-suite.txt`: full scenario suite on `fix/issue-91-arm-over-outline`, rebased on origin/main `d4044c5`, 133/133, including the new `arm_draws_over_identity_outline`.
- The fresh-clone boot check printed no script errors.
- The new scenario fails with the fix reverted (the outline at child index 3, over the haft at 2) and passes with it.

The previous package (#76, stage part sounds) is in history at `d08600f`.
