# #428 verification
- The worker's commit is amended by the orchestrator. GodotSteam GDExtension 4.23.1 (Codeberg; GitHub repo archived) is no longer committed: `tools/fetch_godotsteam.sh` installs it into the git-ignored addons/godotsteam/, pinned to sha256 37d53ede…cc0a. release.yml runs it before export. This keeps ~31 MB of binaries out of public git history for good.
- `pf-atlas.sh run '428|steam'`: 2/2 pass, with the addon installed. The worker's full suite: 846 passed, 1 failed. The failure is the known local `axe_wins_clash_against_every_weapon`.
- The fresh clone (no addon) boots clean (no SCRIPT ERROR/GDExtension/dynamic library lines). With the addon installed, headless boot prints nothing about Steam.
- Not exercised: the live steamInitEx and callbacks path; that needs the Steam client and is an owner test with app 480 (steam-readiness 6.2/6.4).
