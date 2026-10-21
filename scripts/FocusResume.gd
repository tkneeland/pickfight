extends Node
## Resumes a round the window losing focus paused (#747): the first key, mouse button or
## gamepad button after the window is back. It keeps processing while the tree is paused.

signal resume_requested

var armed: bool = false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if not armed:
		return
	var pressed: bool = false
	if event is InputEventKey:
		pressed = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventJoypadButton:
		pressed = (event as InputEventJoypadButton).pressed
	if pressed:
		armed = false
		resume_requested.emit()
