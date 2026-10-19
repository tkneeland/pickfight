extends Node

## The one place the game talks to Steam (docs/steam-readiness.md item 6.1).
## An autoload beside `Sfx` and `Music`, reached by path, never by
## `class_name`; GodotSteam itself is reached only through the engine's
## singleton registry, so a build without the addon, without the Steam client
## or running headless still starts and plays. Every failure logs one line and
## leaves `available` false.
##
## Later tickets build on this: achievements (#689) call `set_achievement` and
## `store_stats`; persona names (#538) read `persona_name()`.
##
## Dev checkouts test against Spacewar (app ID 480) through a git-ignored
## `steam_appid.txt` at the repo root; see docs/steam-readiness.md.

const APP_ID_SETTING := "pickfight/steam_app_id"
const DEFAULT_APP_ID := 480

## True only once Steam answered the init call.
var available: bool = false
var app_id: int = 0

var _steam: Object = null

func _ready() -> void:
	app_id = int(ProjectSettings.get_setting(APP_ID_SETTING, DEFAULT_APP_ID))
	if not Engine.has_singleton("Steam"):
		print("SteamPlatform: GodotSteam not present, Steam off")
		return
	var tree := get_tree()
	if (tree != null and tree.get_script() != null) or DisplayServer.get_name() == "headless":
		return
	var steam: Object = Engine.get_singleton("Steam")
	var result: Variant = steam.call("steamInitEx", app_id)
	# steamInitEx returns {"status": int, "verbal": String}; 0 (OK) means ready.
	if typeof(result) != TYPE_DICTIONARY or int(result.get("status", 1)) != 0:
		var why: String = str(result.get("verbal", "unknown")) if typeof(result) == TYPE_DICTIONARY else "unknown"
		print("SteamPlatform: Steam init failed (%s), Steam off" % why)
		return
	_steam = steam
	available = true
	print("SteamPlatform: Steam ready (app %d)" % app_id)

func _process(_delta: float) -> void:
	if available:
		_steam.call("run_callbacks")

## The player's Steam name, or "" when Steam is not running.
func persona_name() -> String:
	if not available:
		return ""
	return str(_steam.call("getPersonaName"))

## The player's 64-bit Steam ID, or 0 when Steam is not running.
func steam_id() -> int:
	if not available:
		return 0
	return int(_steam.call("getSteamID"))

## Unlock an achievement by its Steamworks API name. False when Steam is not
## running or refused it.
func set_achievement(api_name: String) -> bool:
	if not available:
		return false
	return bool(_steam.call("setAchievement", api_name))

## Push pending stat and achievement changes to Steam. False when unavailable.
func store_stats() -> bool:
	if not available:
		return false
	return bool(_steam.call("storeStats"))
