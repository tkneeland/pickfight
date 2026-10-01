extends RefCounted

## The one palette every script reads (issue #255). Preloaded by path, never
## referenced by `class_name` (see CLAUDE.md).
##
## Players keep ONE colorblind-safe set everywhere. The stage rotates through
## three moods, Daylight, Dusk and Paper: each sets the sky gradient, the far
## and mid hill colours, the platform colour, the kill zone and the ink used
## for player outlines and eye pupils. The dress_* keys (#257) colour the flat
## parallax dressing behind the play area: sky shapes (clouds or stars), a far
## and a mid layer, each kept close to the sky so it never reads as a platform. The stages declare no family, so a
## stage's mood is simply its index in the rotation, round-robin.

const PLAYERS: Array[Color] = [
	Color("#E69F00"), Color("#3D8FD1"), Color("#009E73"), Color("#D55E00"),
	Color("#CC79A7"), Color("#56B4E9"), Color("#F5E24A"), Color("#E8E6F0"),
]

const DAYLIGHT: Dictionary = {
	"name": "daylight",
	"sky_top": Color("#bfe3f0"), "sky_bottom": Color("#e6f4f7"),
	"far": Color("#9fcbdc"), "mid": Color("#7fb6c9"),
	"dress_sky": Color("#f2fafc"), "dress_far": Color("#b9dce8"), "dress_mid": Color("#a8cfdd"),
	"platform": Color("#2a3440"), "kill": Color("#ff4d3d"), "ink": Color("#14181d"),
}
const DUSK: Dictionary = {
	"name": "dusk",
	"sky_top": Color("#241d3a"), "sky_bottom": Color("#5a3a5e"),
	"far": Color("#3a2c52"), "mid": Color("#4c3460"),
	"dress_sky": Color("#8a76a8"), "dress_far": Color("#33294d"), "dress_mid": Color("#3f2f58"),
	"platform": Color("#120f1d"), "kill": Color("#7cf2ff"), "ink": Color("#0b0912"),
}
const PAPER: Dictionary = {
	"name": "paper",
	"sky_top": Color("#eeeae2"), "sky_bottom": Color("#eeeae2"),
	"far": Color("#e2ddd2"), "mid": Color("#d6d0c3"),
	"dress_sky": Color("#f8f5ef"), "dress_far": Color("#e8e4da"), "dress_mid": Color("#ddd8cc"),
	"platform": Color("#26231f"), "kill": Color("#e0402a"), "ink": Color("#26231f"),
}

## Night variant (#332): the dusk look pushed darker, with stars. Not in the
## round-robin `MOODS`; a stage with `night` set uses it in place of its own.
const NIGHT: Dictionary = {
	"name": "night",
	"sky_top": Color("#0a0d1f"), "sky_bottom": Color("#1c2547"),
	"far": Color("#1a2140"), "mid": Color("#232b4f"),
	"dress_sky": Color("#c8d2ff"), "dress_far": Color("#161c38"), "dress_mid": Color("#1d2444"),
	"platform": Color("#2b3350"), "kill": Color("#ff6a4d"), "ink": Color("#0b0d18"),
}

const MOODS: Array[Dictionary] = [DAYLIGHT, DUSK, PAPER]

## The mood for the stage at `stage_index` in the rotation. A negative or
## unknown index (a stage loaded outside the rotation) gets Daylight.
static func mood_for_stage(stage_index: int) -> Dictionary:
	if stage_index < 0:
		return DAYLIGHT
	return MOODS[stage_index % MOODS.size()]
