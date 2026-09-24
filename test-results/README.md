# Proof of work -- issue #34, phone buzz feedback

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #36's evidence is in
history at `276e27b:test-results/issue-36/`.

Branch `feat/issue-34-phone-buzz`, macOS, local Godot 4.6.2.

| Criterion (issue #34) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| A round win sends `win` only to the winner's phone; losers get `eliminated`, the winner (put through `leave_round()`) does not | `round_win_buzzes_only_winner` (3 players, winner in the middle slot) | `issue-34/scenario-suite.txt` | PASS |
| A damaging strike sends `struck` to the victim and `hit` to the attacker, nothing to a bystander | `damaging_strike_buzzes_victim_and_attacker` | `issue-34/scenario-suite.txt` | PASS |
| A 0-damage strike sends nothing | `zero_damage_strike_buzzes_no_one` (the 0 strike is confirmed reported, so the check is not vacuous) | `issue-34/scenario-suite.txt` | PASS |
| An elimination sends `eliminated` to that player's phone alone, by a direct elimination and by damage | `elimination_buzzes_eliminated_player` | `issue-34/scenario-suite.txt` | PASS |
| Wire format `{"t":"buzz","kind":...}` reaches only the bound phone; a slot with no phone is a no-op | `buzz_reaches_only_its_phone` (real ControllerServer, WebSocket clients) | `issue-34/scenario-suite.txt` | PASS |
| The page vibrates where `navigator.vibrate` exists and always flashes the slot colour, scaled by kind | `controller/index.html` extracted and passed through `node --check`; no scenario drives a browser | none | PARTIAL: syntax only |
| Nothing else regressed | full suite, 74 of 75; the one failure is the known flaky `roster_heads_do_not_tunnel_head_reversed` (#38) | `issue-34/scenario-suite.txt` | PASS (known #38 flake excepted) |
| Boots on a fresh clone | `git clone` of the branch, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-34/boot-check.txt` | PASS |
| Vibration and flash on real Android and iOS phones | not yet run | none | BLOCKED: needs phones on the LAN |
