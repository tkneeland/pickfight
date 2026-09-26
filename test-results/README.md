# Test results

Evidence for the latest work package only: issue #135 (the weapon head drawn trailing behind the haft tip).

- `issue-135/full-suite.txt`: boot check plus the full scenario suite in 4 parallel shards on `fix/issue-135-head-drift` rebased on main 46e6925: boot clean, 159/159. It includes the new `haft_tip_meets_drawn_head_every_frame`: every weapon, plain and with big heads, and phased, with a widest drawn gap of 0.00 px.
- `issue-135/new-scenario-red-on-main.txt`: the new scenario run with main 46e6925's `scripts/Player.gd`. It fails all 18 cases, with the drawn haft tip 13 to 57 px from the drawn head.
- Real-renderer check (windowed, Compatibility renderer, not committed): coloured dots on the head's anchor and on the haft tip, found in the rendered frames by pixel scan. Staff and pickaxe on main: median gap 47 px, worst 197 px and 110 px (retina pixels). With the fix: 0.1 px. This confirms the headless reconstruction matches what the renderer draws.

Previous packages: issue #139 (nickname prompt), `issue-139/`, in `git show a721c7d`; issue #138 (eight players), `issue-138/`, in `git show 00ee7eb`; issue #121 (nicknames, controller polish), `issue-121/`, in `git show c9a1e9b`.
