# #538 verification: Steam persona name as the Online name default

- `pf-atlas.sh run '538|460|online_name|remote_client'`: 38 passed, 0 failed (the 4 new `_538` scenarios included).
- Full suite: 891 passed, 1 failed of 892. The failure is the known macOS-only `axe_wins_clash_against_every_weapon`.
- Fresh-clone boot check: clean.
- How the default is chosen: a saved name always wins. With no saved name, the field uses the persona name, cleaned and capped. With no Steam, behaviour is unchanged.
- Not checked: real Steam (`getPersonaName`). Tests use the `fake_persona_for_test` seam in SteamPlatform. The owner checks on a Steam build.
