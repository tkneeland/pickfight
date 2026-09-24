# Proof of work -- issue #13, weapon roster

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. Produced on
`feat/issue-13-weapon-roster` (rebased onto `main` at `8f52ebb`), local
headless Godot 4.6.2.

| Criterion | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| V1 The project boots | `godot --headless --path . --quit`, exit 0 | `issue-13/boot-check.txt` | PASS |
| V2 Each weapon reaches the reach it carries, and the five bucket into the roster's S/M/L tiers | `weapon_reach_matches_roster` | `issue-13/scenario-suite.txt` | PASS |
| V3 Each weapon deals the damage it carries at a full-speed strike | `weapon_damage_matches_roster` | `issue-13/scenario-suite.txt` | PASS |
| V4 No head circle reaches outside that weapon's own art outline, within the scenario's 0.5 px tolerance | `weapon_head_circles_within_art`, all five plus a deliberately misfitted control | `issue-13/scenario-suite.txt` | PASS |
| V5 The heavy head beats the light head in a clash, on either side | `heavy_weapon_wins_clash` (axe vs dagger, with a dagger-vs-dagger control) | `issue-13/scenario-suite.txt` | PASS |
| V6 The haft still passes through a player; only the head collides | `haft_is_non_colliding` | `issue-13/scenario-suite.txt` | PASS |
| V7 Full suite green, no regressions | `--all`, 31/31 | `issue-13/scenario-suite.txt` | PASS |
| V8 Fresh clone parses (CLAUDE.md `class_name` rule) | `.godot/` moved aside, then boot + full suite: 31/31 with no global class cache | `issue-13/fresh-clone.txt`, `issue-13/class-name-rule.txt` | PASS |
| V9 **HUMAN GATE** -- the five heads read as the owner's drawings | all five rendered from the shipped `.tres` values, against a 48 px player body | `issue-13/weapon-heads.png` | **PENDING the owner's look** |

V2 and V3 are named `weapon_reach_matches_roster` / `weapon_damage_matches_roster`
in the suite; the planning ledger called them `weapon_reach_per_weapon` /
`weapon_damage_per_weapon` before they were written.

A fourth roster scenario, `weapon_responsiveness_matches_roster`, went in
beyond the planned three. It measures the *reach* half of a newly commanded
drag rather than the angular half: timing a turn orders the roster backwards
(the staff, the lightest and quickest weapon, comes out the most sluggish at
17 ticks against the dagger's 13), because a turn is made against the weapon's
own lever arm and the head's inertia out on the end of it, so it mostly times
length rather than `drive_speed`. The docstring records the rejected variant.

V4's tolerance is worth stating plainly rather than reading as an absolute.
The scenario allows 0.5 px of slack, and two heads use a little of it: the
staff's single circle stands 0.003 px proud of its traced outline and the
axe's widest circle 0.011 px. Both are rounding -- the outline and the circles
are rounded to two decimals independently -- not geometry anyone can see at a
48 px player body. The pickaxe, sword and dagger are strictly inside, the
pickaxe's worst fit 0.043 px in.

## What V9 is asking of the owner

`issue-13/weapon-heads.png` draws each head exactly as its shipped `.tres`
defines it -- grey is the drawn art, red is what actually collides, the dashed
box is the 48 px player body and the grey line is the haft with the player off
to the left. The question is only whether each one reads as the thing on the
whiteboard. Two known departures to judge:

1. **The axe is still a symmetric crescent**, not the one-sided bit it was
   drawn as. That was deferred deliberately to #16, which is now blocked by
   this issue and carries the refitted one-sided geometry.
2. **The pickaxe is thinner than the first pass but not as thin as it could
   look.** How thin it can get is bounded by physics: an earlier cut thinned
   the belly to 4.7 px and filled it with eighteen circles of 1.0-2.3 px, and
   three scenarios went red (`head_plants_player`, `haft_is_non_colliding`,
   `heads_do_not_tunnel_head` -- 1 charge in 12 drove a head clean through
   another), because circles that small cross a contact inside one physics
   step. The shipped head instead shortens the horns, which slims the
   silhouette on both axes without taking any circle below 2.01 px.
