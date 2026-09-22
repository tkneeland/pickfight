# Human gates -- operator verdicts

Four criteria in this work package cannot be proven headlessly: they are
judgements about feel and legibility on a real phone against the real host.
The operator drove each one. Each gate also carries a machine post-check
against the same target, because an operator completion report is not by
itself verification evidence.

## HG-1 -- aim tracks the finger closely enough to play

**Operator:** "def feels better overall"; "slightly lags behind finger, but
not by too much. leaves room for possibility of lighter and heavier weapons."

**Verdict: PASS.** Recorded in ADR-0006: the aim is *near*-1:1, not 1:1, and
the residual lag is kept deliberately as the axis light and heavy weapons
differ on.

**Post-check:** `aim_angle`, `extension_tracks_drag` -- see
`../scenario-suite/output.txt`.

## HG-2 -- the head does not pass through terrain under hard play

**Operator, first pass:** "when i try to swing the pickaxe hard straight down
to boost myself up, it clips thru the floor sometimes." -- FAIL, fixed in
40df5f3.

**Operator, re-test:** "no clipping, looks good". **Verdict: PASS.**

**Post-check:** `head_does_not_tunnel_thin_platform` -- see
`../scenario-suite/output.txt`.

## HG-3 -- the weapon reads as a weapon, not a floating square

**Operator, first pass:** "the pickaxe also looks nothing like a pickaxe, it's
just a floating square followed by the stretching arm." -- FAIL.

The operator's ruling on scope: "the art and game mechanics are intertwined-
weapon shape isnt just a matter of art." The head silhouette is therefore
drawn from the collision shape itself, so the drawing and the hitbox cannot
drift apart. Fixed in b325041. **Verdict: PASS.**

**Post-check:** `weapon_silhouette_matches_head_shape` -- see
`../scenario-suite/output.txt`.

## HG-4 -- a hurt player is still identifiable

Damage reddens the body fill, which is what the fill used to identify a player
by. **Operator: "outline is visible". Verdict: PASS.**

**Post-check:** `damage_reddens_fill_identity_persists`,
`identity_colours_match_controller_page`, plus the committed screenshots in
`../damage-display/` at 0%, 50% and 95% of lethal damage.
