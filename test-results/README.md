# Test results

Evidence for the latest work package only: issue #151 (hats, colour choice and always-on name tags).

- `issue-151/full-suite.txt`: fresh-clone boot check plus the full scenario list on `feat/issue-151-hats`, rebased on main 9102999, run as 4 parallel shards of `--scenarios=`. Boot is clean and the suite passes **172 of 172**. The four new scenarios are:
  - `phone_hat_choice_reaches_player`: every hat's geometry, a pick sent over the socket, and the hat staying on the head through a swing, an elimination and a respawn.
  - `phone_colour_first_come_first_served`: a colour another player holds is refused; a colour is released on claim expiry or kick but not on a plain disconnect; a newcomer falls back to the first free colour.
  - `name_tags_on_for_every_living_player_all_round`: Main.tscn with 8 phones. Checks every frame of a live round, 8 fighters bunched 56 px apart with no tags overlapping, tags hiding on elimination, and tags shown with no lobby.
  - `controller_page_look_picker_after_name`: static checks on the phone page.
- `buzz_reaches_only_its_phone` now ignores the new `looks` broadcast frame. It failed once, in the first full run, because of that frame.

Previous packages: issue #137 (wide stages), `issue-137/`, in `git show 631d961`; issue #148 (kill feed, awards), `issue-148/`, in `git show ce2b4e7`; issue #149 (host phone controls), `issue-149/`, in `git show 00deb72`.
