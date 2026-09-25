# Proof of work: issue #86, the charge sweep's dependence on suite history

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. Earlier evidence is
in git history:

- #54: `bfb9897:test-results/issue-54/`
- #82: `9ff2640:test-results/issue-82/`
- #77 (with #71's integration run): `72669aa:test-results/issue-77/`
- #75: `5f163a0:test-results/issue-75/`
- #52: `cb30530:test-results/`
- #59: `d2fa0a7:test-results/`
- #47, #61 and damage-display: `8f32c86:test-results/`

Branch `fix/issue-86-sweep-ambient-state`, from `origin/main` at `fe9744b`
(#84 and #85 merged). macOS, local Godot 4.6.2, headless.

## What #86 turned out to be

Not a coverage threshold sitting on its edge. Instrumented on the failing
history (the old #84 stack, `faeee6b` plus the #84 commits), the sword sweep
in `roster_heads_do_not_tunnel_head_reversed` went like this:

1. The 0 deg charge at 1200 px/s eliminated a player (101.3 damage), and the
   45 deg charge at 1800 px/s eliminated the other (41.5 + 17.6 + 17.2 + 32.9
   = 109.1). Clearing `damage` before each charge cannot stop that: a sword
   lands several strikes inside one 45-tick charge. Which charges do it is
   sub-pixel timing, so suite history.
2. After the second, the revive put both players on `centre` with both
   weapons still pushed out at each other. The survivor took 2.8, 9.1, 24.8,
   31.3, 29.9 and 24.2 in seventeen ticks and was eliminated **during the
   settle**, where no charge was watching (the death baseline was taken after
   the next charge's settle).
3. From then on that player had no rig. Its head cluster was empty, every
   later charge read `inf`, and each was counted as a completed charge that
   missed: 6 of them. The 4 that "met" were every charge that ran with both
   players in play.

The fix is in `tools/scenario_runner.gd` only:

- `_sweep_stats`: the sweep's pair holds the weapon with `damage` and
  `projectile_damage` at 0 and every other stored property untouched. Damage
  moves nothing (scored after the step, not read by the body shove or the
  bullet knockback), so the head-against-head physics is unchanged and no
  charge can end in an elimination any more.
- `_revive_sweep_pair`: if a charge is ever cut short anyway, inputs are
  released and each player comes back on its own side of the line, farther
  apart than two reaches, one frame after the deferred freeze has landed.
- `_charge_sweep` fails out loud if a player is not in play at the start of a
  charge, and takes the death baseline before the settle, not after it.

The coverage threshold (`met < measured / 2`) and the breach check are
unchanged.

| Criterion | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| The #86 failure reproduces on the #84 stack | suite prefix up to and including `roster_heads_do_not_tunnel_head_reversed`, on `faeee6b` + #84 (integ-54, `6e7b983`) | `issue-86/red-84-stack-suite-prefix.txt`: sword 2 of 12 void, then 6 charges at `inf`, "only 4 of 10 completed charges brought the heads together" | FAIL, as reported |
| ...and is gone with the fix | full suite on the same #84 stack with this fix applied | `issue-86/green-84-stack-full-suite.txt`: 128/128; sword 0 of 12 void, 9 of 12 met, no breach | PASS |
| A deterministic standalone reproduction goes red before the fix | `charge_sweep_pair_stays_in_play` run against the old `_sweep_stats`/revive behaviour | `issue-86/red-new-scenario.txt`: every weapon still does damage; the survivor of the old revive dies during the settle and has no head | FAIL before fix |
| ...and green after | same scenario on this branch | `issue-86/green-new-scenario.txt` | PASS |
| Full suite on this branch | `--all` | `issue-86/scenario-suite.txt`: 130/130, no charge voided in either roster sweep | PASS |
| Boots on a fresh clone | `godot --headless --path <fresh clone> --quit`, grep `^ERROR` / `SCRIPT ERROR` / `Failed to load script` | `issue-86/boot-check.txt` (no matches) | PASS |

With #84 on top of #85 (`8653519`) the same prefix passes without the fix,
the sword voiding 1 of 12 charges instead of 2 -- which is the history
dependence itself: the same sweep, a different count of eliminations, and
only the second one's revive killed anybody. The fix removes the
eliminations, so the count is 0 after any history.

`red-new-scenario.txt` was captured on this branch's tree with `_sweep_stats`
returning the weapon unchanged and `_revive_sweep_pair` reduced to the old
`start_round(centre, true)` for both players.
