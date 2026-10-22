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

## The base game's Steam app ID (#793, #540). Fill it in once the app exists:
## 0 means "not created yet", and then no Wishlist on Steam button shows at all.
const STORE_APP_ID: int = 0
const STORE_URL_FORMAT := "https://store.steampowered.com/app/%d"

## Scenario seam: -1 follows `STORE_APP_ID`, anything else stands in for it.
static var store_app_id_for_test: int = -1

static func store_app_id() -> int:
	return STORE_APP_ID if store_app_id_for_test < 0 else store_app_id_for_test

## The base game's store page, or "" while the app ID is unset.
static func store_url() -> String:
	var id: int = store_app_id()
	return STORE_URL_FORMAT % id if id > 0 else ""

## Whether the Wishlist on Steam buttons show: the demo build with a store page
## to send people to. Never in the full game (#793).
static func wishlist_available() -> bool:
	return is_active() and store_app_id() > 0

## Opens the base game's store page (Steam overlay when Steam runs, else the
## browser) through the SteamPlatform autoload. Nothing when the button is off.
static func open_wishlist(tree: SceneTree) -> void:
	if not wishlist_available() or tree == null:
		return
	var steam: Node = tree.root.get_node_or_null(^"SteamPlatform")
	if steam != null:
		steam.call("open_store_page", store_app_id(), store_url())

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
