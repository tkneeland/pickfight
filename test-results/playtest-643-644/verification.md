# playtest-643-644 verification (2026-10-08)

Integrated HEAD: 97a8ad0. That is 2924ccd (merges of D643, D644, D645, D646, D648, D649) plus the review-fix commit.

## Deliverables (accepted)
| Issue | Commit | Summary |
|---|---|---|
| #643 | 31eb5e7 | Abandoned matches send an anonymous record (`completed:false`, `rounds_played`). The relay validates it. |
| #644 | cc3ac40 | Stock is one round, then the podium. |
| #645 | ab4a307 | Hot Potato is removed from every picker. A saved choice loads as Classic. |
| #646 | a0f0081 | The Soccer/CTF target ends the match. The stage changes after every non-winning score. |
| #648 | 3f1101a | Soccer and CTF KOs wait 4 s. Soccer spawns and kick-offs never land in a goal. |
| #649 | 524029b | The five Soccer/CTF stages are 1.4× wider (view 2240×1260). Ball mass 1.0 → 0.35, max speed 1800 → 2400. |
| review | 97a8ad0 | Fixes: the one-round target now uses the latched mode, modifiers are re-staged on a mid-round swap, the abandoned-match rule is 1 round or 60 s, the stats sender runs while paused, decided-but-unfinished matches are recorded as completed, the relay omits `winner_weapon` on abandoned records, and FEATURES is made consistent. |

## Checks
- Boot check (`--quit` grep for SCRIPT ERROR / Failed to load script): no output, in the worktree and in a fresh clone.
- Full suite on 2924ccd: `782 passed, 1 failed, 783 total`.
- Full suite on 97a8ad0: `786 passed, 1 failed, 787 total`.
  - The one failure in both runs is `axe_wins_clash_against_every_weapon`. It fails only on this Mac and also fails on main 92a1278 locally. CI passes it on main.
- Red-before-green was observed for each of the four review-fix scenarios.
- The worst case for #646 with 2 players (every Soccer/CTF stage now large) was run by temporarily lowering the lobby to 2 players: `4 passed, 0 failed`.
- Aggregate review was done on two axes, correctness and contract. All high, medium and low findings were fixed in 97a8ad0.

## Human follow-up
- #643: after merge, run `fly deploy` from `relay/` so the live relay accepts `completed` and `rounds_played`.
