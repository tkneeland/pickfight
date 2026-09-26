extends CanvasLayer

## The shared screen's own UI, built in code and split out of RoundManager
## (#175): the lobby (#120: game name, join QR, each phone's colour, name and
## ready state, and the how-to-play panel from #149), the victory podium with
## its awards row (#138, #148), the stage title card that sweeps across at
## every round start (#120), and the PAUSED banner (#149).
##
## Display only. RoundManager decides everything and tells this what to
## show: the lobby from the same state dictionary `_publish_lobby_state()`
## sends the phones, the podium from the slots, scores and awards it has
## worked out. Names and colours come from RoundManager's `_slot_name` /
## `_slot_color`, passed in as callables.
##
## This node is the lobby's CanvasLayer (named LobbyLayer, layer 5). The
## title card and the pause banner keep their own CanvasLayers, at layers 10
## and 12, as children of it. Each part is built the first time it is needed,
## as it always was: the panels on entering the lobby or the victory screen,
## the title card at the first round start, the banner at the first pause.

const KillFeedScript := preload("res://scripts/KillFeed.gd")

const LOBBY_BACKGROUND: Color = Color(0.05, 0.06, 0.08, 0.96)
const LOBBY_ACCENT: Color = Color(1.0, 0.85, 0.2, 1.0)
const GAME_TITLE: String = "PICKFIGHT"
## Podium block heights by place, as a fraction of the tallest.
const PODIUM_HEIGHTS: Array[float] = [1.0, 0.72, 0.5, 0.34]
const PODIUM_TALLEST_PX: float = 260.0
## A podium column's width once more than four are on it (issue #138).
const PODIUM_CROWDED_COLUMN_PX: float = 180.0
## The lines of the lobby's how-to-play panel.
const HOW_TO_PLAY_LINES: PackedStringArray = [
	"Drag on your phone to swing your pick - flick it fast to hit hard",
	"Hook the pick on a ledge and pull yourself up to climb",
	"Touch a weapon pickup to grab a new weapon",
	"Knock the others off the stage or into the rising lava - last one standing wins the round",
]
const HOW_TO_PLAY_WIDTH_PX: float = 560.0

var _slot_name: Callable
var _slot_color: Callable

var _lobby_panel: Control
var _victory_panel: Control
var _lobby_rows: VBoxContainer
var _lobby_status: Label
var _lobby_target_label: Label
var _lobby_qr: TextureRect
var _lobby_url: Label
var _victory_title: Label
var _podium: HBoxContainer
var _how_to_play: Control

var _title_layer: CanvasLayer
var _title_label: Label
var _title_tween: Tween

var _pause_layer: CanvasLayer
var _pause_label: Label

func _init(slot_name: Callable = Callable(), slot_color: Callable = Callable()) -> void:
	name = "LobbyLayer"
	layer = 5
	_slot_name = slot_name
	_slot_color = slot_color

func lobby_panel() -> Control:
	return _lobby_panel

func victory_panel() -> Control:
	return _victory_panel

## The lobby's how-to-play panel, or null before the lobby was ever shown.
func how_to_play_panel() -> Control:
	return _how_to_play

## The title card label, or null before any round has started.
func stage_title_label() -> Label:
	return _title_label

## The PAUSED banner, or null before the first pause.
func pause_label() -> Label:
	return _pause_label

## The victory screen's awards row, or null before any.
func awards_row() -> Control:
	return _podium.get_parent().get_node_or_null("Awards") as Control if _podium != null else null

## Whether the lobby and victory panels exist yet.
func panels_built() -> bool:
	return _lobby_panel != null

## Which full-screen panel shows: "lobby", "victory" or neither ("").
func show_panel(which: String) -> void:
	_lobby_panel.visible = which == "lobby"
	_victory_panel.visible = which == "victory"

## Redraws the lobby from the state the phones are sent. `min_players` is
## how many it takes to start; `join_source` (the ControllerServer, or null)
## has the join QR and URL.
func refresh_lobby(state: Dictionary, min_players: int, join_source: Object) -> void:
	for child: Node in _lobby_rows.get_children():
		child.queue_free()
	for entry: Dictionary in state["players"]:
		var slot: int = entry["slot"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(40, 40)
		swatch.color = _slot_color.call(slot)
		row.add_child(swatch)
		var tag: String = "  (host)" if slot == state["host"] else ""
		var label := _big_label("%s%s  -  %s" % [entry["name"], tag, "READY" if entry["ready"] else "not ready"],
			36 if state["players"].size() <= 4 else 28, LOBBY_ACCENT if entry["ready"] else Color(0.8, 0.82, 0.88))
		row.add_child(label)
		_lobby_rows.add_child(row)
	_lobby_target_label.text = "First to %d" % state["target"]
	var joined: int = state["players"].size()
	if state["phase"] == "countdown":
		_lobby_status.text = str(state["count"])
	elif joined < min_players:
		_lobby_status.text = "Scan to join: %d joined (need %d)" % [joined, min_players]
	else:
		_lobby_status.text = "Press Ready on your phone"
	if join_source != null:
		var qr: Variant = join_source.get("join_qr_texture")
		_lobby_qr.texture = qr as Texture2D
		_lobby_qr.visible = qr != null
		var url: Variant = join_source.get("join_url")
		_lobby_url.text = str(url) if url != null else ""

## The podium: `slots` already in podium order (the match winner first, then
## by final score), each with its score from `scores`, then `awards` under it.
func refresh_victory(slots: Array[int], scores: PackedInt32Array, winner_slot: int, awards: Array[Dictionary]) -> void:
	for child: Node in _podium.get_children():
		child.queue_free()
	# Five to eight on the podium (issue #138) take narrower columns and smaller
	# names that wrap, so eight columns still fit across the 1600 px screen.
	var crowded: bool = slots.size() > 4
	_podium.add_theme_constant_override("separation", 16 if crowded else 40)
	for place in slots.size():
		var slot: int = slots[place]
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_END
		column.add_theme_constant_override("separation", 8)
		var name_label: Label = _big_label("%s\n%d" % [_slot_name.call(slot), scores[slot]], 24 if crowded else 36, Color.WHITE)
		if crowded:
			# A fixed column that a long name wraps inside rather than widens.
			name_label.custom_minimum_size.x = PODIUM_CROWDED_COLUMN_PX
			name_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		column.add_child(name_label)
		var block := ColorRect.new()
		block.color = _slot_color.call(slot)
		block.custom_minimum_size = Vector2(120 if crowded else 160, PODIUM_TALLEST_PX * PODIUM_HEIGHTS[mini(place, PODIUM_HEIGHTS.size() - 1)])
		column.add_child(block)
		column.add_child(_big_label(str(place + 1), 28, Color.WHITE))
		_podium.add_child(column)
	if winner_slot != -1:
		_victory_title.text = "%s WINS!" % _slot_name.call(winner_slot)
		_victory_title.add_theme_color_override("font_color", _slot_color.call(winner_slot))
	else:
		_victory_title.text = "MATCH OVER"
	_refresh_awards(awards)

func _refresh_awards(awards: Array[Dictionary]) -> void:
	var stack: Node = _podium.get_parent()
	var old: Node = stack.get_node_or_null("Awards")
	if old != null:
		stack.remove_child(old)
		old.queue_free()
	if awards.is_empty():
		return
	var row: HBoxContainer = KillFeedScript.award_cards(awards, _slot_name, _slot_color)
	stack.add_child(row)
	stack.move_child(row, _podium.get_index() + 1)

## Builds the lobby and victory panels, both hidden. A no-op once built.
func build_panels() -> void:
	if _lobby_panel != null:
		return
	_lobby_panel = _full_screen_panel("LobbyPanel")
	var columns := HBoxContainer.new()
	columns.set_anchors_preset(Control.PRESET_FULL_RECT)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 96)
	_lobby_panel.add_child(columns)
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 24)
	columns.add_child(left)
	left.add_child(_big_label(GAME_TITLE, 120, LOBBY_ACCENT))
	_lobby_target_label = _big_label("First to 5", 44, Color.WHITE)
	left.add_child(_lobby_target_label)
	_lobby_rows = VBoxContainer.new()
	_lobby_rows.add_theme_constant_override("separation", 12)
	left.add_child(_lobby_rows)
	_lobby_status = _big_label("", 56, LOBBY_ACCENT)
	left.add_child(_lobby_status)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 16)
	columns.add_child(right)
	_lobby_qr = TextureRect.new()
	_lobby_qr.custom_minimum_size = Vector2(420, 420)
	_lobby_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lobby_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lobby_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(_lobby_qr)
	_lobby_url = _big_label("", 28, Color(0.8, 0.82, 0.88))
	right.add_child(_lobby_url)
	_how_to_play = _build_how_to_play()
	right.add_child(_how_to_play)

	_victory_panel = _full_screen_panel("VictoryPanel")
	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 32)
	_victory_panel.add_child(stack)
	_victory_title = _big_label("", 110, LOBBY_ACCENT)
	stack.add_child(_victory_title)
	_podium = HBoxContainer.new()
	_podium.alignment = BoxContainer.ALIGNMENT_CENTER
	_podium.add_theme_constant_override("separation", 40)
	stack.add_child(_podium)
	stack.add_child(_big_label("Press Rematch on your phone", 40, Color.WHITE))

func _full_screen_panel(node_name: String) -> Control:
	var panel := ColorRect.new()
	panel.name = node_name
	panel.color = LOBBY_BACKGROUND
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	add_child(panel)
	return panel

func _build_how_to_play() -> Control:
	var box := VBoxContainer.new()
	box.name = "HowToPlay"
	box.add_theme_constant_override("separation", 8)
	box.add_child(_big_label("HOW TO PLAY", 34, LOBBY_ACCENT))
	for line: String in HOW_TO_PLAY_LINES:
		var label: Label = _big_label(line, 24, Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = HOW_TO_PLAY_WIDTH_PX
		box.add_child(label)
	return box

func _big_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	label.add_theme_constant_override("outline_size", maxi(4, font_size / 10))
	return label

# --- Stage title card (issue #120) -------------------------------------------
#
# The stage's name sweeps across the screen for about a second at every round
# start, below the modifier banner so the two never overlap.

## Sweeps `text` across the screen over `duration` seconds.
func show_stage_title(text: String, duration: float) -> void:
	if _title_label == null:
		_title_layer = CanvasLayer.new()
		_title_layer.name = "StageTitleLayer"
		_title_layer.layer = 10
		add_child(_title_layer)
		_title_label = Label.new()
		_title_label.name = "StageTitle"
		_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_label.add_theme_font_size_override("font_size", 80)
		_title_label.add_theme_color_override("font_color", Color.WHITE)
		_title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 1.0))
		_title_label.add_theme_constant_override("outline_size", 14)
		_title_layer.add_child(_title_label)
	_title_label.text = text
	_title_label.reset_size()
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var width: float = _title_label.get_minimum_size().x
	var middle: float = (screen.x - width) * 0.5
	_title_label.position = Vector2(screen.x, screen.y * 0.36)
	_title_label.visible = true
	if _title_tween != null:
		_title_tween.kill()
	_title_tween = create_tween()
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
		add_child(_pause_layer)
		var dim := ColorRect.new()
		dim.color = Color(0.0, 0.0, 0.0, 0.45)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pause_layer.add_child(dim)
		_pause_label = _big_label("PAUSED", 120, LOBBY_ACCENT)
		_pause_label.name = "PauseLabel"
		_pause_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_pause_layer.add_child(_pause_label)
	_pause_layer.visible = on
	_pause_label.visible = on
