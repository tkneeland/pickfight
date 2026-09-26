# Test results

Evidence for the latest work package only: issue #152 (bots, pickup scaling with a crowd, and the announcer).

- `issue-152/full-suite.txt`: fresh-clone boot check plus the full scenario list on `feat/issue-152-bots`, rebased on main d00dba3, run as 4 parallel shards of `--scenarios=`. Boot is clean and the suite passes **176 of 176**.
- `issue-152/new-scenarios.txt`: the four new scenarios, plus `sfx_sound_files_exist` and `pickup_cap_scales_with_roster`. The four new ones are:
  - `bots_flag_fills_lobby_and_bots_fight`: `--bots=3` on Main.tscn (Flatlands). The bots take slots with controllers bound and are always ready, and none of them is host. The match starts by itself, and the lobby state marks the bots. Their vectors reach the slot's input smoothing, they move, and one lands a damaging strike within 40 s (typically 3 to 5 s). The host's kick sends a bot away, and removing the bots frees every slot.
  - `solo_practice_button_adds_and_removes_bots`: two real phones over the socket. A non-host's `solo` is ignored. The host's `solo` fills the lobby to four and readies the host, and the phones see the bots. "Remove bots" empties the lobby again. With every phone ready, Solo practice starts a four-player match.
  - `pickups_come_faster_and_more_with_a_crowd`: the shipped interval is 12 s (it was 10 s). The cap and interval are checked for 2 to 8 players: at 5+ players the cap is one per player and the interval is 60%. Then a live round runs with the crowd threshold lowered.
  - `announcer_calls_the_match`: a lobby round with a forced LOW GRAVITY modifier is called in order: 3, 2, 1, FIGHT!, LOW GRAVITY, KO!, Winner! Two eliminations 3 ticks apart make one Double KO!. Every modifier has a line.
- Bot benchmark (a throwaway harness, not committed). Four bots ran through the whole stage rotation headless at `--fixed-fps 60`, measured before the rebase onto the wide stages of #137. These stages gave real fights:

  | Stage | Damage per round |
  |---|---|
  | Flatlands | 54 to 124 |
  | Highrise | 54 to 124 |
  | Bulwark | 54 to 124 |
  | Slant | 54 to 124 |
  | Sinkhole | 54 to 124 |

  On the hazard stages (Furnace, Erosion, Ferry, Carousel and others), bots die to the stage within seconds. Players sending no input at all die there just as fast or faster, so the limit is how well a bot reads hazards, not its movement.

Previous packages: issue #151 (hats, colours, name tags), `issue-151/`, in `git show 656bd59`; issue #137 (wide stages), `issue-137/`, in `git show 631d961`; issue #148 (kill feed, awards), `issue-148/`, in `git show ce2b4e7`.
