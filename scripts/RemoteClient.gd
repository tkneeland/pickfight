extends Node2D

## PC client for remote play over a relay. Joins a host's match by room code,
## sends relative mouse input, and renders the match from world snapshots.

const SnapshotScript = preload("res://scripts/Snapshot.gd")
const StageScript = preload("res://scripts/Stage.gd")

enum State { JOINING, PLAYING, PAUSED, CLOSED }

var relay_url: String = "ws://localhost:8080"
var room_code: String = ""
var player_name: String = ""
var player_id: int = -1
var team: int = 0

var websocket: WebSocketPeer
var state: State = State.JOINING
var current_snapshot: Dictionary = {}
var interpolation_buffer: Array[Dictionary] = []

var camera: Camera2D
var canvas: CanvasLayer
var ui_root: Control
var stage_container: Node2D
var player_container: Node2D

var mouse_captured: bool = false
var input_vector: Vector2 = Vector2.ZERO
var last_input_send_time: float = 0.0
var input_send_interval: float = 1.0 / 30.0

var stage_scene_cache: Dictionary = {}
var puppet_nodes: Array[Node2D] = []
var current_round_snapshot: Dictionary = {}

func _ready() -> void:
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()

	canvas = CanvasLayer.new()
	add_child(canvas)

	stage_container = Node2D.new()
	add_child(stage_container)

	player_container = Node2D.new()
	add_child(player_container)

	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(ui_root)

	_build_join_ui()

func _process(delta: float) -> void:
	if websocket == null:
		return

	websocket.poll()

	while websocket.get_available_packet_count() > 0:
		var data = websocket.get_packet()
		if data == null:
			continue

		var message_type = data[0]
		if message_type == 1:
			var text = data.slice(1).get_string_from_utf8()
			_on_relay_message(JSON.parse_string(text))
		else:
			var snapshot_bytes = data.slice(1)
			_on_snapshot(snapshot_bytes)

	if state == State.PLAYING:
		if Input.is_action_just_pressed("ui_cancel"):
			_release_mouse()

		var mouse_motion = Input.get_last_mouse_velocity()
		if mouse_captured:
			input_vector = mouse_motion.normalized()
			if input_vector.length() > 1.0:
				input_vector = input_vector.normalized()

		if Time.get_ticks_msec() - int(last_input_send_time * 1000) >= int(input_send_interval * 1000):
			_send_input()
			last_input_send_time = Time.get_ticks_msec() / 1000.0

func _physics_process(delta: float) -> void:
	if state == State.PLAYING:
		_update_render(delta)

func _on_relay_message(msg: Dictionary) -> void:
	var msg_type = msg.get("t", "")

	match msg_type:
		"hello":
			player_id = msg.get("id", -1)
		"error":
			var reason = msg.get("reason", "unknown")
			_show_error("Error: %s" % reason)
			_return_to_join()
		"closed":
			var reason = msg.get("reason", "unknown")
			_show_message("Host left: %s" % reason)
			_return_to_join()
		"menu":
			_show_menu(msg)

func _on_snapshot(data: PackedByteArray) -> void:
	if data.is_empty():
		return

	var snapshot = SnapshotScript.decode(data)
	if snapshot.is_empty():
		return

	current_snapshot = snapshot
	if snapshot.get("is_full_snapshot", false):
		interpolation_buffer.clear()

func _build_join_ui() -> void:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = Vector2(400, 300)
	ui_root.add_child(panel)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Join Online Game"
	vbox.add_child(title)

	var room_label = Label.new()
	room_label.text = "Room Code:"
	vbox.add_child(room_label)

	var room_input = LineEdit.new()
	room_input.placeholder_text = "ABCD"
	room_input.max_length = 4
	vbox.add_child(room_input)

	var name_label = Label.new()
	name_label.text = "Player Name:"
	vbox.add_child(name_label)

	var name_input = LineEdit.new()
	name_input.placeholder_text = "Your Name"
	vbox.add_child(name_input)

	var join_button = Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(func() -> void:
		room_code = room_input.text.to_upper()
		player_name = name_input.text if name_input.text else "Player"
		if room_code.length() == 4:
			_connect_to_relay()
	)
	vbox.add_child(join_button)

func _connect_to_relay() -> void:
	if websocket != null:
		websocket.close()

	websocket = WebSocketPeer.new()
	websocket.connect_to_url(relay_url)

	state = State.JOINING
	_show_message("Connecting to relay...")

	await get_tree().create_timer(0.5).timeout

	if websocket.get_state() == WebSocketPeer.STATE_OPEN:
		var join_msg = {"t": "join", "room": room_code}
		websocket.send_text(JSON.stringify(join_msg))

		await get_tree().create_timer(0.5).timeout
		if websocket.get_state() == WebSocketPeer.STATE_OPEN:
			var hello_msg = {"id": player_id, "proto": 1}
			websocket.send_text(JSON.stringify(hello_msg))
			state = State.PLAYING
			_on_join_success()
		else:
			_show_error("Failed to connect to relay")
			_return_to_join()
	else:
		_show_error("Could not reach relay at %s" % relay_url)
		_return_to_join()

func _send_input() -> void:
	if websocket == null or websocket.get_state() != WebSocketPeer.STATE_OPEN:
		return

	var input_bytes = PackedByteArray()
	input_bytes.append(0)

	var x = int(clamp(input_vector.x * 32767, -32768, 32767))
	var y = int(clamp(input_vector.y * 32767, -32768, 32767))
	input_bytes.append((x >> 8) & 0xFF)
	input_bytes.append(x & 0xFF)
	input_bytes.append((y >> 8) & 0xFF)
	input_bytes.append(y & 0xFF)

	websocket.send(input_bytes)

func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true

func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_captured = false
	input_vector = Vector2.ZERO

func _update_render(delta: float) -> void:
	if current_snapshot.is_empty():
		return

	var stage_id = current_snapshot.get("stage_id", 0)
	_load_stage(stage_id)

	var players = current_snapshot.get("players", [])
	_render_players(players)

	var projectiles = current_snapshot.get("projectiles", [])
	_render_projectiles(projectiles)

	var pickups = current_snapshot.get("pickups", [])
	_render_pickups(pickups)

func _load_stage(stage_id: int) -> void:
	if stage_container.get_child_count() > 0:
		return

	var stage_scenes = [
		preload("res://scenes/stages/Flatlands.tscn"),
		preload("res://scenes/stages/Highrise.tscn"),
		preload("res://scenes/stages/Gauntlet.tscn"),
		preload("res://scenes/stages/Pillars.tscn"),
		preload("res://scenes/stages/Islands.tscn"),
		preload("res://scenes/stages/Slant.tscn"),
		preload("res://scenes/stages/Bowl.tscn"),
		preload("res://scenes/stages/Ferry.tscn"),
		preload("res://scenes/stages/Erosion.tscn"),
		preload("res://scenes/stages/Furnace.tscn"),
		preload("res://scenes/stages/Cascade.tscn"),
		preload("res://scenes/stages/Springboard.tscn"),
		preload("res://scenes/stages/Gale.tscn"),
		preload("res://scenes/stages/Carousel.tscn"),
		preload("res://scenes/stages/Rockfall.tscn"),
		preload("res://scenes/stages/Sinkhole.tscn"),
		preload("res://scenes/stages/Bulwark.tscn"),
		preload("res://scenes/stages/Pistons.tscn"),
		preload("res://scenes/stages/Overpass.tscn"),
		preload("res://scenes/stages/Ziggurat.tscn"),
		preload("res://scenes/stages/Updraft.tscn"),
		preload("res://scenes/stages/Quarry.tscn"),
		preload("res://scenes/stages/Mill.tscn"),
		preload("res://scenes/stages/Reactor.tscn"),
	]

	if stage_id < stage_scenes.size():
		var stage = stage_scenes[stage_id].instantiate()
		stage_container.add_child(stage)

func _render_players(players: Array) -> void:
	while player_container.get_child_count() < players.size():
		var puppet = Node2D.new()
		player_container.add_child(puppet)

	for i in range(players.size()):
		var player_data = players[i]
		var puppet = player_container.get_child(i)

		var pos = player_data.get("body", {}).get("position", Vector2.ZERO)
		var rot = player_data.get("body", {}).get("rotation", 0.0)

		puppet.position = pos
		puppet.rotation = rot

func _render_projectiles(projectiles: Array) -> void:
	pass

func _render_pickups(pickups: Array) -> void:
	pass

func _on_join_success() -> void:
	ui_root.queue_free()
	_capture_mouse()

func _show_message(text: String) -> void:
	var label = Label.new()
	label.text = text
	label.set_anchors_preset(Control.PRESET_CENTER)
	ui_root.add_child(label)

func _show_error(text: String) -> void:
	_show_message("[color=ff0000]%s[/color]" % text)

func _show_menu(menu_data: Dictionary) -> void:
	state = State.PAUSED

func _return_to_join() -> void:
	state = State.JOINING
	player_container.queue_free()
	stage_container.queue_free()
	ui_root.queue_free()
	_build_join_ui()
	_release_mouse()

func close_game() -> void:
	state = State.CLOSED
	if websocket != null:
		websocket.close()
	get_tree().quit()
