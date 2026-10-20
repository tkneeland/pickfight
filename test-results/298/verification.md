# #298 verification — Steam friend invites

Commit c29b259 on feat/issue-298 (base 4030ab8).

| Check | Command | Result |
|---|---|---|
| Targeted | `pf-atlas.sh run '298\|538\|428\|online\|remote_client\|join' .` | 106 passed, 0 failed, 106 total |
| Full suite | `godot --headless --fixed-fps 60 --path . -s tools/scenario_runner.gd -- --all` | 899 passed, 1 failed, 900 total (only `axe_wins_clash_against_every_weapon`, known macOS-only) |
| Fresh-clone boot | clone + `godot --headless --quit` grep SCRIPT ERROR/Failed to load | no output (pass) |

Orchestrator review: rich presence is set only for an Online match with an open room and cleared otherwise (Couch/Local set nothing); invite button gated on `SteamPlatform.running()`; connect codes validated with RemoteClient's typed-code rules. GodotSteam names: `setRichPresence`, `clearRichPresence`, `activateGameOverlayInviteDialogConnectString`, signal `join_game_requested(user, connect)`.

Not verified: real Steam client. Owner two-account test on app 480 is in `docs/steam-invites.md`.
