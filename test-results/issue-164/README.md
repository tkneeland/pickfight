# Issue #164 evidence: phone and server hardening

**What was run:** the full scenario list (195 scenarios), on branch
`fix/issue-164-phone-server-hardening` rebased on main `1e97a2a` (branched
from `3a6db34`). It ran as 5 parallel shards of
`godot --headless --path . -s tools/scenario_runner.gd -- --scenarios=...`,
then a fresh-clone boot check. The full log is `full-suite.txt`.

**Result:** 194 passed, 1 failed, 195 total.

The one failure is `controller_page_look_picker_after_name`. It is the known
line-ending problem. That scenario looks for `"</div>\n<div id=\"name-prompt\">"`,
but this Windows checkout has CRLF endings (`core.autocrlf=true`), so the text
never matches. In an LF clone (`git clone -c core.autocrlf=false`), that scenario
passes, and so do `controller_page_no_traps_in_play` and
`controller_page_stale_confirms_close`.

**Fail before the fix:** the source files were put back to main's versions with
`git checkout origin/main -- scripts/ControllerServer.gd controller/index.html`.
Then the six new scenarios and the updated `controller_page_host_menu_is_guarded`
were run: 0 passed, 7 failed. The files were then restored with
`git checkout HEAD -- ...`. `git stash` was not used.

**Fresh-clone boot:** the only line printed is
`ERROR: Could not create child process: qrencode ...`. That comes from the
missing `qrencode` binary on this machine and is expected. There were no
SCRIPT ERROR or "Failed to load script" lines.
