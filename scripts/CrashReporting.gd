extends Node

## Opt-out crash reporting (#681) with the Sentry Godot SDK. An autoload beside
## `SteamPlatform`, reached by path, never by `class_name`. The SDK is a
## GDExtension installed by `tools/fetch_sentry.sh` into the git-ignored
## `addons/sentry/`; it is reached only through the engine's singleton registry,
## so a build without the addon runs unchanged and this node stays inactive.
##
## It starts only when every condition in `should_init` holds: the addon is
## there, `pickfight/sentry_dsn` is set, the run is a real one (not headless, not
## a scenario or `--bots` run, not the editor) and the player has not turned
## "Send crash reports" off. The SDK's own auto-init is off in project.godot, so
## this is the only way it starts.
##
## Privacy: no personal data leaves the machine. Default PII, the Godot logger,
## log and scene-tree attachments, screenshots and breadcrumbs are all off, so
## only the crash, its stack, the build version, the platform and the mode and
## stage tags are sent, and the user is cleared. docs/crash-reporting.md.

const DSN_SETTING := "pickfight/sentry_dsn"
const CRASH_TEST_FLAG := "--crash-test"
const TAG_POLL_SECONDS := 1.0

const StatsSenderScript := preload("res://scripts/StatsSender.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")
const DemoBuildScript := preload("res://scripts/DemoBuild.gd")

## True only once the SDK has been initialised by this node.
var active: bool = false

var _sdk: Object = null
var _tag_timer: float = 0.0
var _last_mode: String = ""
var _last_stage: String = ""

## The whole decision, pure so it can be tested without the addon.
static func should_init(addon_present: bool, dsn: String, scripted: bool,
		headless: bool, editor: bool, opted_out: bool) -> bool:
	return addon_present and not dsn.strip_edges().is_empty() and not scripted \
			and not headless and not editor and not opted_out

## "demo" for the Next Fest demo build, "release" for the full game.
static func environment_name(demo: bool) -> String:
	return "demo" if demo else "release"

## The tag for a game mode id ("" is Classic).
static func mode_tag(mode: String) -> String:
	return "classic" if mode.is_empty() else mode

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	var dsn: String = str(ProjectSettings.get_setting(DSN_SETTING, ""))
	var host: RefCounted = HostSettingsScript.shared()
	var present: bool = Engine.has_singleton("SentrySDK")
	var scripted: bool = StatsSenderScript.is_scripted(get_tree(), args)
	if not should_init(present, dsn, scripted, DisplayServer.get_name() == "headless",
			OS.has_feature("editor"), not host.send_crash_reports):
		set_process(false)
		return
	_sdk = Engine.get_singleton("SentrySDK")
	_sdk.call("init", Callable(self, "_configure").bind(dsn))
	if not bool(_sdk.call("is_enabled")):
		print("CrashReporting: Sentry did not start, crash reports off")
		_sdk = null
		set_process(false)
		return
	_sdk.call("remove_user")
	active = true
	print("CrashReporting: crash reports on")
	if args.has(CRASH_TEST_FLAG):
		_run_crash_test()

func _configure(options: Object, dsn: String) -> void:
	options.set("dsn", dsn)
	options.set("release", "pickfight@%s" % str(ProjectSettings.get_setting("application/config/version", "dev")))
	options.set("environment", environment_name(DemoBuildScript.is_active()))
	options.set("send_default_pii", false)
	options.set("attach_log", false)
	options.set("attach_scene_tree", false)
	options.set("attach_screenshot", false)
	options.set("max_breadcrumbs", 0)
	options.set("enable_logs", false)
	options.set("enable_metrics", false)
	var logger: Object = options.get("godot_logger")
	if logger != null:
		logger.set("enabled", false)

func _process(delta: float) -> void:
	_tag_timer += delta
	if _tag_timer < TAG_POLL_SECONDS:
		return
	_tag_timer = 0.0
	var mode: String = mode_tag(str(HostSettingsScript.shared().game_mode))
	if mode != _last_mode:
		_last_mode = mode
		_sdk.call("set_tag", "mode", mode)
	var stage: String = _current_stage()
	if stage != _last_stage:
		_last_stage = stage
		_sdk.call("set_tag", "stage", stage)

func _current_stage() -> String:
	var scene: Node = get_tree().current_scene
	var rounds: Node = scene.get_node_or_null(^"RoundManager") if scene != null else null
	if rounds != null and rounds.has_method("current_stage_name"):
		var stage: String = str(rounds.current_stage_name())
		if not stage.is_empty():
			return stage
	return "lobby"

## `--crash-test`: send one test message, give it a moment to leave, then crash.
func _run_crash_test() -> void:
	var info: int = ClassDB.class_get_integer_constant("SentrySDK", "LEVEL_INFO")
	_sdk.call("capture_message", "Pickfight crash test", info)
	await get_tree().create_timer(2.0).timeout
	OS.crash("Pickfight crash test (--crash-test)")
