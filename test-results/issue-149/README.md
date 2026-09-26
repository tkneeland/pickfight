# Issue #149 evidence

- `full-suite.txt`: every scenario in `SCENARIO_NAMES`, run on main `cfde4cc` plus this branch as 5 parallel `--scenarios=` shards. 162 passed, 0 failed, 162 total.
- New scenarios: `host_phone_controls_over_websocket`, `lobby_how_to_play_on_host_screen_only`, `controller_page_host_menu_is_guarded`.
- Fresh-clone boot: the only ERROR is qrencode "Could not create child process", which is an environment issue (qrencode is not installed here).
