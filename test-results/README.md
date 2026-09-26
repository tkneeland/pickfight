# Test results

Evidence for the latest work package only: issue #148 (kill feed, KO credit and match awards).

- `issue-148/full-suite.txt`: the full scenario list on `feat/issue-148-kill-feed-awards`, based on main `cfde4cc`, run as 5 parallel shards of `--scenarios=`: **162 passed, 0 failed, 162 total**. It includes the three new scenarios `match_stats_ko_credit_and_awards`, `kill_feed_credits_hits_and_awards_at_match_end` and `kill_feed_and_awards_fit_eight_long_names`.
- Fresh-clone boot check (`godot --headless --quit` on a throwaway clone): the only ERROR is qrencode's "Could not create child process", which comes from the environment (qrencode is not installed on this machine) and not from the code.
