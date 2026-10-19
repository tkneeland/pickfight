# #693 verification (6e111e8)
- `pf-atlas.sh run '688|693'`: 7/7 pass. Full suite: 844 passed, 1 failed. The failure is the known local `axe_wins_clash_against_every_weapon`.
- Fresh-clone boot check: clean. Running `--import` regenerates nothing beyond what is committed.
- 36 keys were moved into all 9 languages. Bot and pad names are translated at display time only (stored names stay identifiers). The Stages & Rules screen now uses the existing STAGE_*/MODIFIER_* keys.
- The new scenario walks the title, lobby, How to play, Look, Join help, the Stages & Rules tabs and a round in ja against an English denylist.
- Known gap: the Russian count plural uses one form ("%d арен"); proper plural forms are a later polish.
- Screenshots: ja.png and ru.png.
