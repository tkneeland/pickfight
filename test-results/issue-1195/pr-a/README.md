# #1195 PR A evidence (measure: ping readout, felt delay, match statistics)

Godot 4.6.2-stable, Windows 11, headless, `--fixed-fps 60`, local in-process relay.
Commands are in `docs/plans/1195-online-latency.md` section 5.

| # | Criterion | Evidence | Verdict |
|---|---|---|---|
| V1 | Per-seat avg / p95 / max; hostile `felt` clamped; departed seats kept | `scenario-S1.txt` | PASS |
| V2 | In-match readout identical on host and joiner (text, colour, visibility, position, size, anchors, font size); hidden in Local | `scenario-S2.txt` | PASS |
| V3 | Felt delay measured on the drawn pose (>= INTERP_MSEC - 1000/SNAPSHOT_HZ - 5) and reported on the pong | `scenario-S3.txt` | PASS |
| V4 | Match-end log and telemetry carry the ping list; D8 filter; cap 8; relay validator | `scenario-S4.txt` | PASS |
| V7 | Real-network before number | `real-network.md` (human-gated, not yet run) | BLOCKED (human) |
| V9 | Full suite | `scenario-all.txt`: 1248 passed, 4 failed of 1252. Three are the known Windows-local failures that also fail on unmodified `main` on this machine (`flail_ball_does_not_clip_head`, `online_bots_only_match_starts_offline_and_says_so`, `career_phone_page_shows_compact_line_and_expands_503`; `soccer_stuck_ball_returns_to_centre`, the fourth known one, passed this run). The fourth, `cjk_subsets_cover_every_translated_character_849`, was this branch's: the new zh/ja/ko text used glyphs outside the bundled font subsets. Rephrased within the subsets; `scenario-rerun-after-cjk-fix.txt` re-runs it plus S2 and the failures (CJK PASS, the three known ones still fail) | PASS (no new failure) |
| V10 | Boot check, runner parse check | `boot-check.txt`, `runner-parse.txt` | PASS |
| V11 | Fresh-clone parse | `fresh-clone.txt` | PASS |
| V12 | Online parity: one drawing path | `parity-grep.txt` + S2 | PASS |
| V13 | Lobby ping, host and joiner | `scenario-lobby.txt` | PASS |
| V14 | FEATURES, privacy draft, notice | PR diff | PASS |
| V15 | Nagle | `nagle.md` (off on both ends already) | PASS |

LAN addresses in the captured output are replaced with `<lan-ip>`.
