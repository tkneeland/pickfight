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

## Amendment: Online sync (#1049, 2026-11-12)

The definition is also the Online wire format. A built stage carries its
definition in JSON shape (`StageDef.to_json_data()`) as metadata, which survives
`StageBuilder.pack()` into the PackedScene the rotation holds. Custom stages take
stage ids after the built-in list. When a round moves to one, the host sends
`{"t": "stage_def", "id", "def"}` to every Online PC joiner before any snapshot
names the id, and again to a PC joiner who binds while it is in play. Phones
draw no stage and are never sent one; a built-in stage sends nothing.

The client validates the definition with the same `StageDef` limits before
keeping it, so a hostile host cannot push a bad stage, and builds it with the
host's own `StageBuilder`, so it sees exactly what the host sees. It keeps only
the latest definition, which bounds its memory. Only the stage in play is sent,
never the whole set, so a frame stays small: the largest definition the limits
allow is about 6.3 KB, well inside a client's 256 KB inbound buffer. The
relay's 4 KB cap applies only to client-to-host frames.
