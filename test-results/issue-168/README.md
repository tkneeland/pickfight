# Issue #168 evidence

- `full-suite.txt` holds every scenario in `SCENARIO_NAMES`, run on `107effd` (rebased on main `4d616d8`) as 4 contiguous shards through `psuite.sh`. The result was **208 passed, 0 failed, 208 total.** The fresh-clone boot was clean, and no shard printed `ObjectDB instances leaked at exit`.
- Wall time per shard, measured from the psuite start to each shard's output file, including the clone and `--import`:

  | shard | main `3c38982` (200 scenarios) | this branch (208 scenarios) |
  |---|---|---|
  | 0 | 920 s | 410 s |
  | 1 | 344 s | 258 s |
  | 2 | 329 s | 171 s |
  | 3 | 157 s | 211 s |
  | whole run | 920 s | 410 s |

- Single-scenario times, before and after:
  - `stage_spawns_are_safe`: about 205 s before, 13 s after.
  - `every_stage_can_ring_out`: about 309 s before, under 55 s after.
  - Each tunnel sweep: about 163 s before, 58 s after.
  - `roster_heads_do_not_clip_platform_in_play` was about 122 s as one scenario. It is now three scenarios of about 25 s each.
- The new scenarios `juice_overflow_head_claims_trail_later` and `hit_feedback_pools_markers_and_numbers` fail on main's `Juice.gd` and `HitFeedback.gd` and pass with this change. On main, the Juice one reports "after 8 players swapped weapons in one frame, 0 new heads hold trail slots, expected all 8".
- The leak at exit on main was an `AudioStreamOggVorbis` playback on the SFX bus. The announcer played a still-queued line during `Sfx.release()`'s wait. Five scenarios reproduced it on their own, including `round_modifier_tiny_weapons_applies_and_undoes` and `lobby_ready_up_counts_down_and_starts_match`.
