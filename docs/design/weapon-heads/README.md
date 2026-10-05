# Weapon head redesign (#621)

The owner signed this design off on 2026-10-05. Six heads are redrawn: staff, umbrella, magnet, grapple, fishing rod and pogo. The other nine stay as they are. The flail is already spiky, and the boomerang was judged fine.

- `Main.dc.html` + `canvas.json` are the design canvas source. The page shows every head as it is now next to its proposal, at the same scale, plus a strip of the proposals at 2× game size.
- `outlines.json` holds the approved points for each redrawn head, in `WeaponStats` head-local space: +X out along the haft, origin at the groove anchor. Paste `art_outline` (and `loaded_art` for the grapple and fishing rod) into `resources/<weapon>.tres` as `PackedVector2Array`. The `pickup_art` of the grapple and fishing rod should follow the new loaded art.
- Refit `head_circle_offsets` / `head_circle_radii` where the new outline no longer contains the old circles. `weapon_head_circles_within_art` in `tools/scenario_runner.gd` enforces this.
