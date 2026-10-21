# #747 verification
- Fresh-clone boot check of the committed branch: no output.
- Runner parse check: no output.
- `pause_on_focus_loss_747`: fails with the pause logic disabled, passes with it.
- Full suite: 914 passed, 3 failed, 917 total. The three are the known Windows-only failures (flail_ball_does_not_clip_head, online_bots_only_match_starts_offline_and_says_so, career_phone_page_shows_compact_line_and_expands_503).
