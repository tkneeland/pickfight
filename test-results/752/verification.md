# #752 Team letters for colour-blind players: verification

Windows 11, Godot 4.6.2. Branch `feat/issue-752-team-letters`, based on `origin/main` at `437931c` and merged up to `94c9aa0`.

## Behaviour

Every team marker also carries the team's letter, in ink on the team colour, so Red and Blue are told apart by more than colour. The letter is the first character of the translated team name (R and B in English, R and A in Spanish). No new shapes or patterns, and a free-for-all shows none.

| Marker | What it shows |
|---|---|
| Name tag | a small rounded badge beside the name (left of it, scaled with the tag) |
| Lobby card (Teams match) | a badge top right of the card, next to the existing "RED TEAM (auto)" text |
| Podium (Teams match) | a badge over each team player's name |
| Soccer goal | a large badge centred on each goal |
| Capture the Flag base | a large badge centred on each base |
| Capture the Flag flag | a small badge on the flag's cloth |
| In-round scoreboard row | the row text starts with the letter in brackets, e.g. `[R] P1  RED` (a text label cannot carry a chip) |

`scripts/TeamBadge.gd` (new) draws the badge in the name tags' display font so a small letter stays bold. The goals and bases are added by `Stage.gd` in code, so no `.tscn` changed.

## Evidence

| Check | Result |
|---|---|
| `team_letters_752`: letters in all nine languages (and never shared by the two teams); the badge control; the lobby chip; goal and base badges on every Soccer and CTF stage, centred; name tags (left of the tag) and scoreboard rows in a live Teams round; a free-for-all with no badge; the flag cloths | PASS |
| Mutation checks (each breaks one thing; the scenario must fail; the file is restored exactly and it passes again) | no letters: FAILS in every language. Name tags never set their badge: FAILS (3 tags). Lobby chip never set: FAILS. Stages never mark goals and bases: FAILS (every Soccer and CTF stage). Scoreboard row loses its letter: FAILS. Flag badge removed: FAILS |
| Runner parse check | no output (pass) |
| Fresh-clone boot check of the merged head (no `.godot/`) | no output (pass) |
| Full suite | **919 passed, 3 failed, 922 total** |

The 3 failures are the same ones that fail identically on untouched `origin/main` on this machine and pass on Linux CI; not from this change:

- `flail_ball_does_not_clip_head` (ball goes 6.9 px into a held sword)
- `online_bots_only_match_starts_offline_and_says_so` (link stays on "connecting")
- `career_phone_page_shows_compact_line_and_expands_503` (expected HTML snippet not found on Windows)

## Screenshots

Real Teams matches with 8 bots, captured windowed with a throwaway probe (not committed) based on `tools/capture_store_screenshots.gd`, at 1920x1080 and at the Steam Deck's 1280x800 (`1920x1080/` and `1280x800/`):

- `teams_lobby.png`: the Teams lobby, a badge on each of the 8 cards
- `teams_match.png`: name tags with their badges
- `soccer.png`: the goals
- `ctf.png`: the bases and the flags
- `teams_podium.png`: the podium

The podium badges are covered by the screenshot only; the scenario does not drive the victory screen.

## Translations

No new strings: the letters come from the existing `TEAM_RED` / `TEAM_BLUE` names in every language.
