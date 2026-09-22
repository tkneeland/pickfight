# 4. An endless session replaces the match

- Status: Accepted
- Date: 2026-09-22
- Supersedes: the "match" and "score target" definitions in `CONTEXT.md`

## Context

`CONTEXT.md` defined a **match** as a sequence of rounds ending when a player
reached a score target, and listed that target under deliberately-not-decided.

Stick Fight, the reference for this project's round structure, has no such
thing. A round is won by the last player alive, winning a level loads the next,
and the game runs until the players stop it. There is no target and no match
winner.

That difference matters more here than it looks. A match end is a gate: a phone
that connects mid-match either waits it out or invalidates the match it joined.
With no match, there is nothing to wait for.

## Decision

Sessions are endless. Rounds run back to back for as long as the game is open.

A running score tally is kept and displayed, but it ends nothing. It lives in
memory for the session and is forgotten when the process exits.

**Match** is struck from the glossary. **Session** takes its place: the endless
run of rounds from launch to quit, holding the roster and the tally.

## Consequences

- The "score target" open question is resolved by deletion rather than by
  picking a number.
- Nothing needs persisting to disk. No save format, no profile, no schema to
  migrate later.
- With no match boundary, the tally is the only record that anything is
  accumulating, so it has to stay legible: a persistent on-screen tally, a
  winner flash on the killing blow, and the full tally during the stage load.
- An open roster becomes coherent — a player joins at the next round boundary
  and there is no match they are interrupting.
- Anything that wants a defined end — tournaments, a "first to N" party mode —
  is a mode layered on top later, not a change to this.

## Alternatives considered

**Keep the match and pick a target.** Requires answering a question with no
evidence behind it, and reintroduces the join-timing problem the open roster
exists to avoid.

**Endless by default, optional host-set target.** Two lifecycles to build, tune
and debug for a prototype that needs one working well.
