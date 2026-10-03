extends RefCounted

## The two cards laid over a round (#543, split out of `LobbyScreen.gd`): the
## stage title card (#120) and the PAUSED banner (#149). Each is built the first
## time it is needed, on its own CanvasLayer as a child of the LobbyScreen
## (layers 10 and 12). Display only.

const ScreenKitScript := preload("res://scripts/ScreenKit.gd")

var _screen: CanvasLayer

var _title_layer: CanvasLayer
var _title_label: Label
var _title_rule_label: Label
var _title_tween: Tween

var _pause_layer: CanvasLayer
var _pause_label: Label

func _init(screen: CanvasLayer) -> void:
	_screen = screen

## The title card label, or null before any round has started.
func stage_title_label() -> Label:
	return _title_label

## The line under the stage title naming the game mode and its rule (#352).
func stage_title_rule_label() -> Label:
	return _title_rule_label

## The PAUSED banner, or null before the first pause.
func pause_label() -> Label:
	return _pause_label

# --- Stage title card (issue #120) -------------------------------------------
#
# The stage's name sweeps across the screen for about a second at every round
# start, below the modifier banner so the two never overlap.

## Sweeps `text` across the screen over `duration` seconds.
func show_stage_title(text: String, duration: float, rule: String = "") -> void:
	if _title_label == null:
		_title_layer = CanvasLayer.new()
		_title_layer.name = "StageTitleLayer"
		_title_layer.layer = 10
		_screen.add_child(_title_layer)
		_title_label = Label.new()
		_title_label.name = "StageTitle"
		_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_label.add_theme_font_size_override("font_size", 80)
		_title_label.add_theme_color_override("font_color", Color.WHITE)
		_title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 1.0))
		_title_label.add_theme_constant_override("outline_size", 14)
		_title_layer.add_child(_title_label)
		# A child of the title, so the sweep carries it along.
		_title_rule_label = Label.new()
		_title_rule_label.name = "StageTitleRule"
		_title_rule_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_rule_label.add_theme_font_size_override("font_size", 32)
		_title_rule_label.add_theme_color_override("font_color", ScreenKitScript.LOBBY_ACCENT)
		_title_rule_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 1.0))
		_title_rule_label.add_theme_constant_override("outline_size", 8)
		_title_label.add_child(_title_rule_label)
	_title_label.text = text
	_title_label.reset_size()
	_title_rule_label.text = rule
	_title_rule_label.visible = rule != ""
	_title_rule_label.reset_size()
	var screen: Vector2 = _screen.get_viewport().get_visible_rect().size
	var width: float = _title_label.get_minimum_size().x
	var middle: float = (screen.x - width) * 0.5
	_title_rule_label.position = Vector2((width - _title_rule_label.get_minimum_size().x) * 0.5, 96.0)
	_title_label.position = Vector2(screen.x, screen.y * 0.36)
	_title_label.visible = true
	if _title_tween != null:
		_title_tween.kill()
	_title_tween = _screen.create_tween()
	# Fast in, a slow drift through the middle where it can be read, fast out.
	_title_tween.tween_property(_title_label, "position:x", middle + 40.0, duration * 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_title_tween.tween_property(_title_label, "position:x", middle - 40.0, duration * 0.4)
	_title_tween.tween_property(_title_label, "position:x", -width - 20.0, duration * 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_title_tween.tween_callback(func() -> void: _title_label.visible = false)

# --- Pause banner (issue #149) -----------------------------------------------

## Shows or hides the PAUSED banner, building it the first time it is shown.
## Its layer always processes, so it stays up while the tree is paused.
func show_pause_banner(on: bool) -> void:
	if _pause_label == null:
		if not on:
			return
		_pause_layer = CanvasLayer.new()
		_pause_layer.name = "PauseLayer"
		_pause_layer.layer = 12
		_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		_screen.add_child(_pause_layer)
		var dim := ColorRect.new()
		dim.color = Color(0.0, 0.0, 0.0, 0.45)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pause_layer.add_child(dim)
		_pause_label = ScreenKitScript.big_label(_screen.tr("PAUSED"), 120, ScreenKitScript.LOBBY_ACCENT)
		_pause_label.name = "PauseLabel"
		_pause_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_pause_layer.add_child(_pause_label)
	_pause_layer.visible = on
	_pause_label.visible = on
