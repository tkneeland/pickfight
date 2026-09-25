extends CanvasLayer

## The host screen's sound control (issue #75, ADR-0016): a small "Sound"
## button in the bottom-right corner that opens a master volume slider and a
## mute box. `M` toggles mute from the keyboard. There is no settings or pause
## screen in the game yet, so this is the whole of it; it drives `Sfx`'s
## `set_master_volume()` / `set_muted()`, which remember the choice.
##
## Built by `Sfx` once the game's own scene is running, so no scene file has
## to carry it. The bottom-right corner is free: the join text and scores sit
## top-left, the QR code top-right.

const MARGIN: float = 12.0
const SLIDER_WIDTH: float = 160.0

var sfx: Node

var _toggle: Button
var _panel: PanelContainer
var _slider: HSlider
var _mute: CheckBox

func _ready() -> void:
	layer = 20
	var corner := VBoxContainer.new()
	corner.name = "Corner"
	corner.anchor_left = 1.0
	corner.anchor_top = 1.0
	corner.anchor_right = 1.0
	corner.anchor_bottom = 1.0
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.offset_left = -MARGIN
	corner.offset_top = -MARGIN
	corner.offset_right = -MARGIN
	corner.offset_bottom = -MARGIN
	corner.alignment = BoxContainer.ALIGNMENT_END
	add_child(corner)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.visible = false
	corner.add_child(_panel)
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	var title := Label.new()
	title.text = "Master volume"
	rows.add_child(title)
	_slider = HSlider.new()
	_slider.name = "Volume"
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.05
	_slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 0.0)
	_slider.focus_mode = Control.FOCUS_NONE
	rows.add_child(_slider)
	_mute = CheckBox.new()
	_mute.name = "Mute"
	_mute.text = "Mute (M)"
	_mute.focus_mode = Control.FOCUS_NONE
	rows.add_child(_mute)

	_toggle = Button.new()
	_toggle.name = "Toggle"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	corner.add_child(_toggle)

	refresh()
	_slider.value_changed.connect(_on_volume_changed)
	_mute.toggled.connect(_on_mute_toggled)
	_toggle.pressed.connect(_on_toggle_pressed)

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_M:
		sfx.toggle_muted()
		refresh()
		get_viewport().set_input_as_handled()

## Show `Sfx`'s current volume and mute, without echoing them back to it.
func refresh() -> void:
	_slider.set_value_no_signal(sfx.master_volume)
	_mute.set_pressed_no_signal(sfx.muted)
	_toggle.text = "Sound: off" if sfx.muted else "Sound"

func volume_slider() -> HSlider:
	return _slider

func mute_box() -> CheckBox:
	return _mute

func _on_volume_changed(value: float) -> void:
	sfx.set_master_volume(value)
	refresh()

func _on_mute_toggled(pressed: bool) -> void:
	sfx.set_muted(pressed)
	refresh()

func _on_toggle_pressed() -> void:
	_panel.visible = not _panel.visible
