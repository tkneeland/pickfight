extends Node

## Re-applies the display settings when the window changes monitor (#1184). A
## window dragged to a second monitor froze on one machine, and a Godot vsync or
## frame-cap setting that keeps following the old monitor's refresh rate is the
## leading guess (godotengine/godot#95706). So on every screen change this
## re-applies `HostSettings.apply_display()` (vsync mode and `Engine.max_fps`) and
## logs the screen, its refresh rate and the vsync mode, so a frozen report can be
## read off the log. An autoload, reached by path, never by `class_name`.
##
## It uses `Window.screen_changed` where the window has it, and polls
## `get_window().current_screen` twice a second as well, since some platforms
## never emit the signal. Inactive in a headless run (no window to move).

const HostSettingsScript := preload("res://scripts/HostSettings.gd")

const POLL_SECONDS := 0.5

var _screen: int = -1
var _timer: float = 0.0
## How many screen changes have been handled; part of every log line.
var changes: int = 0

func _ready() -> void:
	# Keep polling while the tree is paused, so a focus-loss pause cannot hide a screen change.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var window := get_window()
	_screen = window.current_screen
	if window.has_signal("screen_changed"):
		window.connect("screen_changed", _check)
	_log("start")

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= POLL_SECONDS:
		_timer = 0.0
		_check()

func _check() -> void:
	var now := get_window().current_screen
	if now == _screen:
		return
	_screen = now
	changes += 1
	# Re-applying an unchanged vsync mode can be a no-op, so force a real reset:
	# switch vsync off, then re-apply the saved vsync mode and frame cap.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	HostSettingsScript.shared().apply_display()
	_log("screen changed")

func _log(why: String) -> void:
	print("ScreenWatch: %s (change %d): screen %d of %d, refresh %.1f Hz, vsync mode %d, max_fps %d" % [
			why, changes, _screen, DisplayServer.get_screen_count(),
			DisplayServer.screen_get_refresh_rate(_screen), DisplayServer.window_get_vsync_mode(),
			Engine.max_fps])
