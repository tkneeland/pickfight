# Issue #18 — stage mechanics: moving platforms, crumbling ledges, hazard zones

Branch `feat/issue-18-stage-parts`, stacked on `feat/issue-17-more-stages`.

## Verification

| | check | command | verdict |
|---|---|---|---|
| V1 | the project boots with all three parts in the tree | `godot --headless --path . --quit` | PASS — `boot-check.txt` |
| V2 | a player resting on a moving platform is carried with it | `--scenario=moving_platform_carries_player` | PASS |
| V3 | a head plants on a moving platform rather than tunnelling it | `--scenario=head_plants_moving_platform` | PASS |
| V4 | a crumbling ledge runs solid → warning → away → solid | `--scenario=crumbling_ledge_three_phases` | PASS |
| V5 | a hazard zone kills a player at full health | `--scenario=hazard_zone_kills_at_full_health` | PASS |
| V6 | nothing already in the suite regressed | `-- --all` | 36 passed, 0 failed — `scenario-suite.txt` |
| V7 | no part ships unused | read the three stages | PASS — see below |
| V8 | fresh clone parses | `ls -d .godot` then boot | PASS — `boot-check.txt` |

On V8: the `mv .godot .godot.bak` dance CLAUDE.md documents cannot run here, because Godot 4.6.2 headless never creates that cache. This worktree has never had one, so the boot check above already ran under the fresh-clone condition the dance exists to simulate. Filed separately as #21.

## Where each part is used (V7)

The spec requires that no part ships unused, and each was placed where it sharpens a stage's existing thesis rather than replacing it.

**Hazard → Gauntlet, hung from the centre of the ceiling.** The low ceiling was already this stage's whole idea — it is what stops you crossing the two gaps in one wide arc — but it was a limit you bumped into rather than something that cost you. Now the highest, fastest line across the stage is the one that kills, so a crossing is either low and slow over a gap or wide around the middle. Hung rather than laid on GroundMid: GroundMid is 200 px wide and the hazard is 160, so laying it there would leave two 20 px slivers of safe ledge on the one platform you land on after a committed swing — a coin flip, not a decision.

**Moving platform → Islands, as the third island.** Islands was already the stage about spacing; one of the four moving is that idea with the answer changing while you decide. It stays at y=300, because a platform that rose and fell would hand back the height advantage the stage exists to withhold. Authored to dock at both ends: 10 px off IslandB at its near end, flush with IslandD at its far end, so it is a crossing that opens and closes rather than a moving obstacle.

**Crumbling ledge → Highrise, as the third rung.** A climb whose every rung is permanent rewards getting up first and holding the summit. A middle rung that goes away under the first player to use it means whoever climbs first spends the route. The third rung specifically: crumbling the first could strand a player off the ground with nothing to do but be hit, and the summit should not evaporate under the player who earned it.

## Two things found while doing this

**The hazard zone did not need its own script.** Built out, it was identical to `KillZone.gd` — same `body_entered` check, same `eliminate()` call, same disregard for health. `scenes/parts/Hazard.tscn` instances that script with a hazard's shape and colour, and `KillZone.gd`'s docstring now says not to add a `HazardZone.gd`.

**Integrating three parallel workers broke the runner, and the way it broke will recur.** All three appended to `tools/scenario_runner.gd`, so cherry-picking them conflicted in the three places the file's append-only convention puts new work. Resolving by keeping both sides is correct — except that every scenario function in that file ends with exactly the same two lines:

```gdscript
	await _teardown(stage)
	return failures
```

git therefore matched one function's ending against the next function's ending as shared context, left it outside the conflict region, and a resolver that keeps both sides kept one copy. Two functions silently lost their tails. GDScript caught it as a hard parse failure only because the return type is declared; the version of this to fear is the one that still parses.
