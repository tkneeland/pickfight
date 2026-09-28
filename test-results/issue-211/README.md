# Issue #211 evidence: new narrator voice (Piper `en_US-john-medium`)

On main `d8fef15` (includes `546f9b7`, PR #220: announce_* at -15 dB).

## Files
- `full-suite.txt`: the full scenario suite, 5 shards, `--fixed-fps 60`.
  **259 passed, 0 failed, 259 total.**
- `loudness.txt`: peak and active RMS of the old announcer clips (main
  `546f9b7`), the new john clips, and every other sfx at its `Sfx.gd` db.
- `render_announcer.py`: renders all 17 lines (Piper 1.8.0, length_scale 0.9,
  trim, peak 0.9, 8 ms / 40 ms fades, 22,050 Hz mono Ogg Vorbis).
- `loud211.py`: the loudness script.

## Targeted
`sfx_sound_files_exist`, `announcer_calls_the_match`,
`announcer_said_capped_and_lengths_from_decode`: 3 passed, 0 failed.

## Loudness (medians, dBFS)
| Set | Peak | Active RMS | Effective RMS (with db) |
|---|---|---|---|
| Old announcer, -15 dB | -0.9 | -17.4 | -32.4 |
| New john, -15 dB | -0.9 | -18.0 | -33.0 |
| Other sfx at their db | -1.0 | -17.4 | -18.0 |

The new lines peak at the same level and are 0.6 dB quieter in active RMS
than the clips they replace, so -15 dB is kept and `Sfx.gd` is unchanged.

## Boot notes
The only boot error is qrencode "Could not create child process" (environment-only).
