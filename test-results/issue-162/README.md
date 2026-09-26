# Issue #162 evidence

- `full-suite.txt` is every scenario in `SCENARIO_NAMES`, run on main `3c38982` as 5 parallel `--scenarios=` shards. **202 passed, 2 failed, 204 total.**
  - `controller_page_look_picker_after_name` is the known CRLF issue with this Windows checkout. It passes in an LF clone.
  - `round_modifier_double_damage_applies_and_undoes` fails because of a test leak already on main. Earlier scenarios leave `RoundManager.modifier_rolls_enabled = true`, so later rounds in the same shard roll random modifiers. It fails the same way on main's own code and passes on its own.
- The four new scenarios fail on main `3a6db34`'s source and pass with this change.
- Fresh-clone boot: the only ERROR is qrencode "Could not create child process", which is an environment issue.
