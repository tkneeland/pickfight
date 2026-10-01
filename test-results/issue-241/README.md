# Issue #241: PC client

- `client-playing.png`: what a remote PC player sees mid-round (the client scene in its own SubViewport, joined to a real host through an in-process relay; 6 bots plus the remote player, stage 0, 7 puppets, scores, kill feed, a pickup).
- `host-playing.png`: the host's own screen at the same moment, for comparison.

Captured with (windowed, by hand; headless Godot does not render):

    godot --path . -s tools/capture_remote_client.gd -- --bots=6 --out=<abs dir>

Printed: `client: stage 0, 7 players drawn, 275 frames (10 full), slot 6`.

Suite, on the committed tree, raw: `godot --headless --fixed-fps 60 --path . -s tools/scenario_runner.gd -- --all` gave `368 passed, 0 failed, 368 total`, exit 0.
Fresh-clone check (`git clone`, then `godot --headless --path <clone> --quit | grep -E "SCRIPT ERROR|Failed to load script"`) printed nothing; the 16 `remote_client_*` scenarios' loader scenario also passed in the clone.

Known noise, not from this branch: every round logs `Juice.gd::_on_strike_landed: Method expected 4 argument(s), but called with 5` (present on main).
