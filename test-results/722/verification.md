# #722 verification — SteamPipe upload readiness

Commits e658fc5 + demo preset metadata.

| Check | Result |
|---|---|
| release.yml YAML parse (ruby; python yaml missing) | ok |
| Full suite | 908 passed, 1 failed, 909 total (only known macOS-only axe) |
| Fresh-clone boot | no output (pass) |

Not exercised: the steam job itself, which skips until the owner adds STEAM_* secrets and variables (docs/steam-upload.md). Hand-rolled steamcmd (explicit depot IDs) rather than game-ci/steam-deploy; uploads to the beta branch only. Follow-up: pin the steamcmd image by digest.
