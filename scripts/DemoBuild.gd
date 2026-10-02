extends RefCounted

## The Steam Next Fest demo build (issue #361): one flag, and the game offers
## only a content slice. Preloaded by path, never by `class_name` (CLAUDE.md).
##
## On when the exported build carries the "demo" feature tag (the "Demo"
## export preset, `tools/export.sh demo`) or the command line has
## `--demo-build`. (Plain `--demo` is the older showcase mode in
## `RoundManager`, a different thing, and does not turn this on.)
##
## The slice is stages, pickup weapons and game modes. `HostSettings`' on/off
## lists can only switch things off inside it; the settings panel lists only
## its items. The picks and reasons are in docs/steam-readiness.md.

## Large-view stages are left out: they need five players, and a demo table
## often has two. Flatlands first, since `stage_scenes[0]` opens every match.
const STAGES: PackedStringArray = ["Flatlands", "Highrise", "Pillars", "Islands", "Bowl", "Springboard"]
## Pickup weapons by file stem; the pickaxe everyone starts with is extra.
const WEAPONS: PackedStringArray = ["sword", "boomstick", "grapple", "flail"]
## `GameModes` ids ("" is Classic). Literal here so this file needs no preload.
const MODES: PackedStringArray = ["", "king_of_the_hill"]

static func end_card_text() -> String:
	return TranslationServer.translate("DEMO_END_CARD")

## Scenario seam: -1 follows the real flag, 0 forces the full game, 1 the demo.
static var forced: int = -1

static func is_active() -> bool:
	if forced >= 0:
		return forced == 1
	return OS.has_feature("demo") \
			or OS.get_cmdline_user_args().has("--demo-build") \
			or OS.get_cmdline_args().has("--demo-build")

static func stage_in_slice(stage_name: String) -> bool:
	return not is_active() or STAGES.has(stage_name)

static func weapon_in_slice(weapon_name: String) -> bool:
	return not is_active() or WEAPONS.has(weapon_name)

static func mode_in_slice(id: String) -> bool:
	return not is_active() or MODES.has(id)
