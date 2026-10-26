# 26. Stage definition format

- Status: Accepted
- Date: 2026-10-25

## Context

Part of #350 (stage editor and Steam Workshop). Custom stages will arrive from
strangers, so the file that describes one must be data, never code. A `.tscn`
can embed scripts, which rules it out as the exchange format
([ADR-0008](0008-stage-authoring-format.md) keeps `.tscn` for the built-in
stages only).

## Decision

A **stage definition** is a versioned JSON document, parsed and checked by
`scripts/StageDef.gd` (preloaded by path, no `class_name`) before anything is
built from it. The validator returns ok, or exactly one human-readable reason.

Fields: `schema` (integer, currently 1), `name`, `parts` (each with `type`,
`pos`, and for sized parts `size` and optional `params`), `spawns` (list of
`[x, y]`), and optional `modes` (tags from `GameModes.IDS`). Unknown fields on
a part are rejected.

**Whitelisted part catalogue.** It starts with two entries, each backed by a
scene in `scenes/parts/` (the ADR-0008 amendment): `Platform` (size, param
`one_way`) and `KillFloor` (position only). Anything else is rejected as an
unknown type. Growing the catalogue is a later decision, one part at a time.

**Limits** (constants in `StageDef.gd`): at most 64 parts; 8 to 16 spawns
(one per possible player); exactly one `KillFloor`; every position within
+/-4000 x +/-3000 px, and a sized part's whole box inside that; part sides 8 px
to 2000 x 1000 px; name up to 40 characters.

Rejection reasons: malformed JSON, wrong schema version, unknown part type,
unknown param or field, out-of-bounds or oversize geometry, too many parts, too
few (or too many) spawns, missing (or duplicate) kill floor, unknown mode tag.

## Consequences

- Nothing here is player-facing yet; building a scene from a definition and
  loading one in a lobby are separate tickets (#1046 onward).
- A new schema version means a new validator branch; old versions are rejected
  until one is written.
- The numeric limits are first guesses (the ticket named none) and are cheap to
  change in one place.
