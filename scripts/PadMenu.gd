extends RefCounted

## Whether a host menu is being driven with a gamepad (#368, Steam Deck).
##
## A and B on a gamepad join and ready a seat (ControllerServer, #261). While
## a host menu is open, those same buttons must press and cancel the menu's
## controls instead, or "A" on a checkbox would also ready the player. Each
## menu registers under its own name; the seat code asks `is_open()`.

static var _open: Dictionary = {}

static func set_open(owner_name: String, on: bool) -> void:
	if on:
		ensure_accept_binding()
		_open[owner_name] = true
	else:
		_open.erase(owner_name)

static func is_open() -> bool:
	return not _open.is_empty()

static func reset() -> void:
	_open.clear()

## True when `event` is a pressed gamepad button `button`.
static func pressed(event: InputEvent, button: int) -> bool:
	var pad := event as InputEventJoypadButton
	return pad != null and pad.pressed and pad.button_index == button

## Godot 4.6's built-in `ui_accept` carries no gamepad button here (measured:
## Enter, Kp Enter and Space only), so a focused Button never answered A. Adds
## A (a Cross-style swap is the player's Steam Input layout, not ours).
static func ensure_accept_binding() -> void:
	if not InputMap.has_action("ui_accept"):
		return
	for existing: InputEvent in InputMap.action_get_events("ui_accept"):
		var pad := existing as InputEventJoypadButton
		if pad != null and pad.button_index == JOY_BUTTON_A:
			return
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	InputMap.action_add_event("ui_accept", event)
