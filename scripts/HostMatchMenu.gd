extends VBoxContainer

## The host PC's match controls in the Esc menu (issue #458). An Online host
## has no host phone (ADR-0021), so the settings panel (`SfxSettings.gd`) leads
## with what the host phone's menu gives mid-match: Pause/Resume, End match and
## a Kick on each player's row. It shows only while the host PC runs the room
## and a match is in play or paused (`ControllerServer.pc_runs_room()` and
## `host_pc_match_live()`); otherwise it is hidden and takes no room.
##
## Display and buttons only: each button calls
## `ControllerServer.host_pc_command()`, which sends the same `host_command`
## the host phone's requests do, so RoundManager decides everything.

## How often the open menu re-reads the roster and the pause, in msec.
const REFRESH_MSEC: int = 250

var _pause: Button
var _end: Button
var _players: VBoxContainer
## The roster the player rows were last built for: [slot, name] pairs.
var _rows_key: Array = []
var _refreshed_msec: int = -REFRESH_MSEC

func _ready() -> void:
	name = "HostMatchMenu"
	visible = false
	var buttons := HBoxContainer.new()
	buttons.name = "MatchButtons"
	add_child(buttons)
	_pause = _button("Pause", tr("JOIN_PAUSE_MATCH"))
	_pause.pressed.connect(_on_pause_pressed)
	buttons.add_child(_pause)
	_end = _button("End", tr("HOST_END_MATCH"))
	_end.pressed.connect(func() -> void: _command("end"))
	buttons.add_child(_end)
	_players = VBoxContainer.new()
	_players.name = "Players"
	add_child(_players)
	add_child(HSeparator.new())

func _button(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	return button

## The ControllerServer of the running game, or null (no game, or one without
## these controls).
func server() -> Node:
	var rounds: Node = get_tree().get_first_node_in_group("round_manager") if is_inside_tree() else null
	if rounds == null:
		return null
	var found: Node = rounds.get_node_or_null(rounds.get("controller_server_path"))
	return found if found != null and found.has_method("host_pc_command") else null

func pause_button() -> Button:
	return _pause

func end_button() -> Button:
	return _end

## The Kick button on `slot`'s row, or null.
func kick_button(slot: int) -> Button:
	for row: Node in _players.get_children():
		if not row.is_queued_for_deletion() and row.has_meta("slot") and int(row.get_meta("slot")) == slot:
			return row.get_node_or_null("Kick") as Button
	return null

func _process(_delta: float) -> void:
	var parent: Control = get_parent() as Control
	if parent == null or not parent.is_visible_in_tree():
		return
	var now: int = Time.get_ticks_msec()
	if now - _refreshed_msec >= REFRESH_MSEC:
		refresh()

## Shows or hides the controls and redraws the Pause caption and the rows.
func refresh() -> void:
	_refreshed_msec = Time.get_ticks_msec()
	var srv: Node = server()
	visible = srv != null and srv.pc_runs_room() and srv.host_pc_match_live()
	if not visible:
		return
	_pause.text = tr("JOIN_RESUME_MATCH") if srv.host_pc_paused() else tr("JOIN_PAUSE_MATCH")
	var key: Array = []
	for slot: int in srv.claimed_slots():
		if slot != srv.host_pc_slot():
			key.append([slot, srv.slot_name(slot)])
	if key == _rows_key:
		return
	_rows_key = key
	for row: Node in _players.get_children():
		row.queue_free()
	for pair: Array in key:
		_players.add_child(_row(pair[0], pair[1]))

func _row(slot: int, player_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Slot%d" % slot
	row.set_meta("slot", slot)
	var label := Label.new()
	label.text = player_name if not player_name.is_empty() else "P%d" % (slot + 1)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var kick: Button = _button("Kick", tr("HOST_KICK"))
	kick.pressed.connect(func() -> void: _command("kick", slot))
	row.add_child(kick)
	return row

func _on_pause_pressed() -> void:
	var srv: Node = server()
	if srv != null:
		_command("resume" if srv.host_pc_paused() else "pause")

func _command(cmd: String, slot: int = -1) -> void:
	var srv: Node = server()
	if srv != null:
		srv.host_pc_command(cmd, slot)
	refresh()
