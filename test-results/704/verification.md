# #704 verification: Play of the round

- `pf-atlas.sh run '704'`: 8 passed, 0 failed. Includes `play_of_round_leaves_the_pause_length_alone_704`, which runs a 3 s pause with the feature off and on: the clip must play and the pauses must differ by at most 50 ms.
- `pf-atlas.sh run 'replay|round_end|settings'`: 38 passed, 0 failed.
- Full suite: 887 passed, 1 failed of 888. The failure is the known macOS-only `axe_wins_clash_against_every_weapon`.
- Fresh-clone boot check: clean.
- The pause guarantee: the feature only reads `_pause_until_msec`. The clip is trimmed to fit the time left at half speed (250 ms margin) and is skipped when under 1.5 s. The panel closes the tick the pause ends.
- Not checked: the overlay's look, since no GUI window was opened. The owner sees it in the installed build.
