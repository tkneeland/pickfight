# Technical plan: #1233 Hive: detect a dev whose watchers are alive but whose Claude session is idle, and alert them

- Work package: GitHub issue [#1233](https://github.com/tkneeland/pickfight/issues/1233) (stable contract; not
  duplicated here). `enhancement`, `p1`, `ready-for-agent`, assigned `tkneeland`, `[CLAIM]` by tkneeland.
- Plan status: **DRAFT, revision 2** (answers red-team cycle 1, section 9). Repository storage, drafts before
  approval permitted; the issue is already `ready-for-agent`, a later state than `atlas:plan-review`, so no label moves.
- Planned against: `origin/main` @ `0036dc6` (2026-11-11).
- Run surface: local bash tests under `tools/agents/tests/` (CI does not run them); no game code, no Godot change.
- Red-team review: required by autotriage.md rule 14 (p1). See section 9.

## 1. Intent

The USAGE heartbeat proves only that a machine's background scripts run. Add a second clock, `claude_at`, that moves
only when a Claude session on that account actually does something, publish it in the USAGE beacon, and let the
triagemaster's zero-token watcher wake (`DEV_IDLE <account> <minutes>`) when an account with live heartbeats has
work waiting, is not held back by its usage limits, and has a stale `claude_at`. The triagemaster then probes with
`pf-ask.sh`, alerts the dev in #hive, and at 2 hours offers to reassign. `pf-hive.sh status` shows the idle time.

## 2. Planning findings that shape the design

**F1. The snapshot's write time is not evidence of activity, so `claude_at` does not use it.** The contract says
`claude_at` is "the newest of the statusline snapshot's write time and the session's last tool call". On this
machine `~/.claude/settings.json` sets `statusLine.refreshInterval: 30`, so Claude Code re-runs
`statusline-usage.sh` every 30 s whether or not the session does anything, and the script rewrites
`usage-snapshot.json` each time. `pf-usage.sh` (launchd) and `windows/pf-supervise.sh beacon` (every 5 min) also
rewrite the snapshot with no Claude session at all. Taking the newest of the two would make `claude_at` as fresh
as `at=` on every machine with a refresh interval or a supervisor: exactly the false "alive" the contract says this
field exists to remove. **Resolution (planner, by the contract's stated purpose; red-team agreed):** `claude_at` =
the newest modification time of any Claude Code transcript (`*.jsonl`, sessions and their subagents) under the
account's Claude `projects/` directory, every project folder, not only the one the status line last named (with
`refreshInterval` every open session redraws the status line, so `transcript_path` flips between an idle and an
active session's folder). Claude Code appends to a transcript on every message and tool call and on nothing else,
so this is "the session's last tool call" made measurable with zero setup on macOS and Windows. Recorded here, not
silently amended into the issue; owner decision D1.

**F2. Where the directory comes from.** The status line's input JSON carries `transcript_path`;
`statusline-usage.sh` already saves that JSON verbatim as `usage-snapshot.json`, and `pf-usage.sh` preserves
non-`rate_limits` keys when it rewrites it, so the path survives. `projects/` is `dirname` twice of it. On Windows
the path has backslashes (`C:\Users\...`); normalise to `/` first (Git Bash accepts `C:/Users/...`). Paths may
contain spaces (`C:/Users/Sam Schantz/`): every loop over `find` output reads with `while IFS= read -r`. A snapshot
with no `transcript_path` (headless `claude -p` only) yields no `claude_at`; the beacon then omits the field.

**F3. Reading the field.** Every in-repo USAGE parser (`pf_beacon`'s ` at=` sed, its `read` field split,
`pf-hive.sh`'s `agents=` sed on #1225) reads the same values with a trailing ` claude_at=<ISO>` (red-team ran
them). `claude_at=` goes last in the message.

**F4. "Ready work" excludes work waiting on someone else**, or every dev waiting on a reviewer gets paged. Counted
for account `A` from the `issues` array the watcher already fetches each poll:
- open issues labelled `ready-for-agent`, assigned to `A`, not in `META_TICKETS`, with **no open PR** referring to
  them (`pf_pr_tickets` output; a branch alone does not exclude: a branch with no PR and a silent session is a
  stalled run), and not a `conflict-risk` ticket held by rule 6 (`cr_busy=1` and not in progress);
- open PRs authored by `A` labelled `review-blocked` where the PR's issue timeline shows no `committed` or
  `head_ref_force_pushed` event after the last `labeled review-blocked` event (no fix pushed since the block; once
  one is, it waits on the reviewer, rule 12). One `gh api` call per such PR, made only for an account that already
  passed every cheaper filter.
- At night (`pf_daynight` = night) only p1 counts: issues labelled `p1`, and review-blocked PRs labelled `p1` or
  referring (`pf_pr_tickets`) to an open `p1` issue. `pf_daynight` honours the triagemaster's `pf-day-until`
  override, so that override also widens DEV_IDLE to non-p1; accepted, it is the same "treat now as day".

**F4b. Throttled devs are not idle.** Rules 2 and 3 tell a session to sit idle at the 5-hour stop or the weekly stop,
and a session at its 5-hour limit cannot answer the `pf-ask.sh` probe. The check skips an account whose newest
USAGE beacon (`pf_beacon`) shows it cannot work: 5h at or above `FIVE_H_STOP_USED` with `b_r5` still ahead, or
weekly at or above `HANDOFF_WEEKLY_USED` with `b_reset` more than `RESET_GRACE_HOURS` away. Unknown numbers (empty)
do not exempt. A local helper `pf_dev_throttled` in the watcher's functions section does this; `pf-reserve.sh`'s
`able()` is not moved (its 5h test is 100%/1 h for a different purpose, and moving it widens the `pf-env.sh`
conflict with #1225).

**F5. "Live heartbeats"** uses the hive's existing definition (`pf-hive.sh` online, `pf-hive-failover.sh` live): a
HELLO or USAGE line from the account in `msg-inbox.log` under 1 h old. With none, the machine is off; that is the
reserve rules' job (rule 5), not this alert.

**F6. Accounts checked:** every handle from `pf_handles` except this account. `tkneeland` and `tommykneeland` may
share a Mac and one `projects/` dir, so each reports the other's activity; both are the owner's, and the only effect
is a missed alert between them. A reserve account that runs only headless `claude -p` has no status line, never
sends `claude_at`, and is never checked. Both accepted and noted in the README.

**F7. Addressing the dev in #hive.** `pf-discord.sh post` sends with `allowed_mentions: {parse: []}` (no pings), and
no handle-to-Discord-id map exists (the repo is public). Default: the post addresses the dev by name and handle
("Sam (schans2): ..."), names from `team-memory.md` "Per dev". A real ping is owner decision D2 (section 8).

## 3. Affected areas and interfaces

| File | Change |
|---|---|
| `tools/agents/pf-env.sh` | append `pf_claude_at` (epoch of this account's newest transcript write, empty if unknown) and `pf_peer_claude_at <handle>` (epoch from the handle's newest USAGE line if under 1 h old and carrying `claude_at=`, else empty); USAGE format comment at `pf_beacon` |
| `tools/agents/pf-beacon.sh` | append ` claude_at=<ISO>` when `pf_claude_at` is non-empty; header format comment |
| `tools/agents/pf-triage-watch.sh` | `pf_dev_throttled` and `pf_dev_idle_check "$issues" "$pr_tickets" "$cr_busy"` in the `--functions` section; called each 10-min poll, triagemaster only, after the PEER_BEACON block; header documents `DEV_IDLE <account> <minutes>` |
| `tools/agents/tests/dev-idle.sh` | new offline test (section 6) |
| `docs/agents/autotriage.md` | rule 21 gains the DEV_IDLE paragraph (step 5) |
| `tools/agents/README.md` | `pf-triage-watch.sh` wake list gains `DEV_IDLE`; `pf-beacon.sh` names `claude_at`; F6 notes; the new test |
| `tools/agents/pf-hive.sh` | **after #1225 merges**: `claude idle Nm` per account (step 6) |

Exclusions: no game code, no `docs/FEATURES.md` (not player-facing), no behaviour change to `pf-ask.sh`,
`pf-discord.sh`, `statusline-usage.sh` or `pf-reserve.sh`, no committed Discord id map, no state outside
`$PF_STATE`, no automatic reassignment.

Interface: wake line `DEV_IDLE <account> <minutes>` (whole minutes since `claude_at`); stamp
`$PF_STATE/.dev-idle-<account>` holding `<epoch of last wake> <stage 1|2>`.

## 4. Ordered steps

1. **`pf_claude_at` / `pf_peer_claude_at` (pf-env.sh, appended at the end).** `pf_claude_at`: read
   `.transcript_path` from `$PF_STATE/usage-snapshot.json`; `tr '\\' /`; projects dir = `dirname` twice; if it
   exists, newest `pf_mtime` over `find <projects> -maxdepth 4 -name '*.jsonl' -mmin -1440`, read with
   `while IFS= read -r` (bounded scan; nothing in 24 h falls back to the transcript file's own mtime); print the
   epoch or nothing. `pf_peer_claude_at <h>`: only the newest USAGE line of `<h>`; nothing if it is over 1 h old or
   has no ` claude_at=`; else sed out the ISO and `pf_iso_to_epoch` it.
2. **Beacon (pf-beacon.sh).** `ca=$(pf_claude_at)`; when non-empty append
   ` claude_at=$(TZ=UTC pf_epoch_fmt "$ca" +%Y-%m-%dT%H:%M:%SZ)`.
3. **Detection (pf-triage-watch.sh, functions section).** `pf_dev_idle_check issues pr_tickets cr_busy`: for each
   `h` in `pf_handles` except `$PF_ACCOUNT`, cheapest filter first:
   (a) heartbeat: skip unless a HELLO/USAGE line of `h` is under 3600 s old;
   (b) `ca=$(pf_peer_claude_at h)`: skip if empty or `now - ca < 2700`; `idle = now - ca`;
   (c) throttle from the stamp `<t> <stage>`: if `t >= ca` (a wake in this idle stretch) then allow only when
   `now - t >= 7200`, or stage is 1 and `idle >= 7200` (the one stage-2 wake at 2 h); a stamp older than `ca`
   is a previous stretch and allows a stage-1 wake;
   (d) `pf_beacon h`; skip if `pf_dev_throttled` (F4b);
   (e) work per F4; skip if zero;
   (f) write `now <stage>` (stage 2 when `idle >= 7200`, else 1), print `DEV_IDLE $h $((idle/60))`, return 0.
   Return 1 with no output when nobody qualifies. Uses `$PF_STATE/msg-inbox.log`, `$REPO`, `META_TICKETS`; the
   `META_TICKETS` default moves above the `--functions` return.
4. **Wire it.** In the main loop after the PEER_BEACON block: `if pf_is_triagemaster && [ -n "$issues" ]; then
   d=$(pf_dev_idle_check "$issues" "$pr_tickets" "$cr_busy") && { echo "$d"; exit 0; }; fi`. Header comment line
   for `DEV_IDLE`.
5. **Rule 21 (autotriage.md).** Append a paragraph with this meaning (wording is the worker's): "**Idle dev sessions
   (#1233).** Every USAGE beacon carries `claude_at=`, the last time a Claude session on that account wrote a
   transcript (a message or tool call; the status line and the supervisors do not move it). The triagemaster's
   watcher wakes `DEV_IDLE <account> <minutes>` when that account has a live heartbeat (HELLO/USAGE under 1 h),
   `claude_at` 45 min or more old, and work waiting on it: a ready-for-agent ticket assigned to it with no open PR,
   or a review-blocked PR of its own with no fix pushed since the block (by day; at night only p1). An account at
   its 5-hour or weekly stop (rules 2 and 3) is never woken for: idling is what it should do. At most once per
   account per 2 h, plus one wake when the idle time reaches 2 h. On the wake: `pf-ask.sh <account> "..."` first
   (its watcher wakes its session if one is alive); an answer ends it. No answer: post in #hive (`pf-discord.sh
   post <#hive id> "<Name> (<account>): ..."`) naming the idle minutes and the waiting tickets and PRs; an account
   without `pf-discord.conf` asks the owner on the private channel instead. When the wake says 120 minutes or more,
   the post also offers to reassign that account's unclaimed tickets (no branch, no PR, no CLAIM in 24 h, rule 16),
   and the triagemaster reassigns only on a dev's yes in #hive." If D2 is answered yes, the post pings the dev.
6. **`pf-hive.sh status` (gated on #1225).** When #1225 is on `main`: rebase, and in `row()` add `claude idle Nm`
   (the script's `ago`) for a peer from `pf_peer_claude_at`, for this machine from `pf_claude_at`, in both the full
   and `--short` forms; `claude ?` when unknown. Extend #1225's `tests/hive.sh` with a USAGE line carrying
   `claude_at` and assert the text. If #1225 is not merged when steps 1-5 are verified: record `[BLOCKED]` on #1233
   naming #1225, ASK schans2 on the private channel (rule 17), keep the PR open. **Deadline:** if #1225 is still
   open 24 h after that, ask the owner (private channel, and "needs Tommy" in #hive) to choose: deliver the
   `claude idle` row as a commit on #1225's branch (after an ASK to schans2), or merge #1233 without step 6 and move
   step 6 into #1225's scope. Nothing merges until the owner answers.
7. **README** lines (section 3).
8. **Evidence and verification** (section 6).

## 5. Acceptance coverage

| Contract item | Step | Check |
|---|---|---|
| USAGE gains `claude_at` from real session activity | 1, 2 | T1, T2, R1 |
| Watcher wakes `DEV_IDLE <account> <minutes>`: ready work or review-blocked PR + `claude_at` ≥ 45 min | 3, 4 | T3, T5, T6 |
| Day 9-8 ET; at night only p1 | 3 | T7 |
| At most once per account per 2 h | 3 | T4 |
| On DEV_IDLE: pf-ask first, then #hive, 2 h reassignment offer | 3, 5 | T4 (stage-2 wake at 120 min), V3 |
| `pf-hive.sh status` shows `claude idle Nm` | 6 | T9 |
| DoD: stubbed-inbox tests: one wake / none without work / throttle | 3 | T3, T5, T4 (named exactly) |
| DoD: rule 21 and README updated | 5, 7 | V3 |

## 6. Verification map

All tests offline. `dev-idle.sh` first sources `pf-env.sh` (scratch `PF_STATE_DIR`, `PF_ACCOUNT=tkneeland`, rank 1,
so triagemaster), then `pf-triage-watch.sh --functions`; `REPO_PATH` at a scratch git repo; stub `gh`/`curl` first
on `PATH`; modelled on `tests/beacon-channel.sh`. `pf_daynight` is redefined in the test for day/night cases.
Evidence: `test-results/1233/` (cleared first), each command's output captured to a `.txt` there and committed on
the feature branch.

`tools/agents/tests/dev-idle.sh` (new) cases:

| Id | Case | Expected |
|---|---|---|
| T1 | scratch `projects/` with folder `p1 dir` (space in the name) holding `a.jsonl` (2 h ago, the snapshot's `transcript_path`) and `p1 dir/s/subagents/b.jsonl` (20 min ago), and folder `p2` holding `c.jsonl` (10 min ago); `pf_claude_at` | epoch of `c.jsonl`; backslash form of the same path gives the same; no `transcript_path` → empty |
| T2 | `pf-beacon.sh` with stub curl logging its `-d` body | USAGE text ends ` claude_at=<c.jsonl ISO>`; `pf_beacon` on that line yields the same `b_at`/`b_used`/`b_p5` as without the field |
| T3 | inbox: agage-JG HELLO 2 min ago, USAGE (5h 10%, 7d 20%) 5 min ago with `claude_at` 50 min ago; one ready-for-agent p2 ticket assigned agage-JG, no PR; day | exactly one line `DEV_IDLE agage-JG 50` |
| T4 | T3 again at once; then stamp `now-7201 1` and call; then `claude_at` 125 min old with a stamp `now-80min 1`, then repeat at once | none (exit 1); one wake; one wake (stage 2); none |
| T5 | T3 but no ticket assigned; and T3 with the ticket in `pr_tickets` | no output each |
| T6 | no ticket; agage-JG authors a `review-blocked` PR; stub timeline with `labeled review-blocked` last → wake; with a `committed` (or `head_ref_force_pushed`) after it → none | as stated |
| T7 | night: p2 ticket → none; p1 ticket → wake | as stated |
| T8 | negatives: `claude_at` 30 min old; no `claude_at` field; newest USAGE lacks the field while an older one has an old value; newest USAGE over 1 h old with a fresh HELLO; heartbeat 2 h old; 5h 95% with reset ahead; weekly 90% with reset 3 days away; tkneeland itself with work | no output each; control: weekly 90% with reset 12 h away → wake |
| T9 | (step 6) `tests/hive.sh` with a USAGE line carrying `claude_at` 50 min old | row shows `claude idle 50m` |

Commands (each must end `N passed, 0 failed` / exit 0):

- `bash tools/agents/tests/dev-idle.sh` (new): after step 4; invalidated by any edit to pf-env.sh, pf-beacon.sh or pf-triage-watch.sh.
- Regression: `bash tools/agents/tests/triage-watch-in-progress.sh`, `bash tools/agents/tests/beacon-channel.sh`,
  `bash tools/agents/tests/hive-failover.sh`, `bash tools/agents/tests/ask.sh`, `bash tools/agents/tests/hive-join.sh`
  (and `tests/hive.sh` after step 6): after step 4 and again after any rebase.
- `bash -n` on every edited `.sh`: after each edit.
- V3: diff review of rule 21 and README against step 5 and section 3, before the PR.
- External parsers: grep `tkneeland/claude-autotriage` for USAGE parsers (` at=`, `agents=`) and confirm none breaks
  on a trailing ` claude_at=`; record the result in the PR.
- CI (`scenarios.yml`) stays green; no Godot files change.

Real-dependency check R1 (agent-run on this Mac, before the PR):
`PF_ACCOUNT=tkneeland bash -c '. tools/agents/pf-env.sh; e=$(pf_claude_at); echo $(( $(date +%s) - e ))'` prints a
value under 120 while this session works; captured to `test-results/1233/r1-claude-at.txt`. Post-merge peer check
(not a merge gate): Sam's Windows machine's next USAGE line in this Mac's `msg-inbox.log` carries `claude_at=`; ASK
schans2 with `pf-ask.sh` if it does not within 30 min (Windows path normalisation, F2).

Candidate evidence (planning, 2026-11-11, this Mac, tkneeland): the real `usage-snapshot.json` carries
`transcript_path` (`~/.claude/projects/-Users-...-pickfight/<session>.jsonl`); `find <folder> -maxdepth 3 -name
'*.jsonl' -mmin -5` returned the live session transcript and a running subagent's
`<session>/subagents/agent-*.jsonl` (668 transcripts in that folder), confirming F1/F2 and the scan depth (one more
level from `projects/`). Invalidated by a Claude Code change to the transcript layout or the status-line JSON.

Human-gated criteria: none for merge. Owner decisions D1 and D2 at approval; implementation may proceed on the
defaults.

## 7. Dependencies and coordination

- #1225 (Sam, #1208 `pf-hive.sh`) is open, `review-blocked`, with a failing check. It edits `pf-env.sh`,
  `autotriage.md` and `README.md` too: expect rebase conflicts there, resolved by keeping both sides. Step 6 depends
  on it, with the 24 h deadline in step 6.
- No `conflict-risk` files (rule 6) are touched.

## 8. Owner decisions

- D1: `claude_at` from transcript writes, not the snapshot write time (F1). Default: as planned.
- D2: should the #hive alert actually ping the idle dev? Recommended yes: look up the dev's Discord id at post time
  with `pf-discord.sh members` (no committed map) and post with that one mention allowed. Default if unanswered:
  name only, no ping.

## 9. Red-team review

Cycle 1 (fresh `atlas-red-team-reviewer`, 2026-11-11): **BLOCK** on B1 (rate-limited devs paged as idle). It
confirmed coverage of every contract item and Done-when, F1, and USAGE-parser compatibility. Revision 2 answers:
- B1 → F4b, step 3 (d), the rule 21 sentence, T8 cases.
- W1 (only the last session's folder scanned) → whole `projects/` dir; T1 with two folders.
- W2 (stale `claude_at` reused) → newest USAGE line only, 1 h cap; T8 cases.
- W3 (open-ended wait on #1225) → 24 h deadline and owner choice, step 6.
- W4 (un-pinged post) → owner decision D2 with a recommendation.
- M1 (offer at 165 min) → stage-2 wake at 120 min; M2 accepted (F4); M3 → issue-timeline events; M4 → space-safe
  loops and a T1 path with a space; M5 → test setup stated; M6 → F6 and README; M7 → external-parser check.

Cycle 2 not run: the one blocking finding has a direct, tested fix. The owner's approval is the final gate.
