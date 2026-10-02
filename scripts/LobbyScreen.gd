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
const HowToPlayDemoScript := preload("res://scripts/HowToPlayDemo.gd")
const GameModesScript := preload("res://scripts/GameModes.gd")
const TeamsScript := preload("res://scripts/Teams.gd")

const LOBBY_BACKGROUND: Color = Color(0.05, 0.06, 0.08, 0.96)
const LOBBY_ACCENT: Color = Color(1.0, 0.85, 0.2, 1.0)
const GAME_TITLE: String = "PICKFIGHT"
## Podium block heights by place, as a fraction of the tallest.
const PODIUM_HEIGHTS: Array[float] = [1.0, 0.72, 0.5, 0.34]
const PODIUM_TALLEST_PX: float = 260.0
## A podium column's width once more than four are on it (issue #138).
const PODIUM_CROWDED_COLUMN_PX: float = 180.0
## How wide the lobby's status line ("Scan to join: ...") runs before it
## wraps.
const LOBBY_STATUS_WIDTH_PX: float = 620.0
## The lessons of the lobby's how-to-play panel, in order, each shown by a
## looping demo (`HowToPlayDemo.gd`, #219) with its line as the caption.
const HOW_TO_PLAY_LINES: PackedStringArray = [
	"Drag on your phone to swing your pick. Flick fast to hit hard.",
	"Hook the pick on a ledge and pull to climb.",
	"Touch a weapon pickup to grab it.",
	"Hit them till they die, or knock them off. Last one standing wins.",
]
## Issue #230. How much of the screen's bottom the how-to-play column keeps
## clear: the host's Settings panel (`SfxSettings.gd`) opens upward from the
## bottom-right corner, over this column, and covered the last caption. The
## column centres itself in the height above this, so the open panel (its
## volume sliders, boxes and button, about 265 px of the 900 px screen)
## never reaches a caption.
const SETTINGS_CORNER_RESERVE_PX: int = 280
const HOW_TO_PLAY_KINDS: Array[int] = [
	HowToPlayDemoScript.Kind.SWING,
	HowToPlayDemoScript.Kind.CLIMB,
	HowToPlayDemoScript.Kind.PICKUP,
	HowToPlayDemoScript.Kind.WIN,
]

var _slot_name: Callable
var _slot_color: Callable

var _lobby_panel: Control
var _victory_panel: Control
var _lobby_rows: VBoxContainer
var _lobby_status: Label
var _lobby_target_label: Label
var _lobby_qr: TextureRect
var _lobby_url: Label
var _lobby_right: VBoxContainer
var _victory_title: Label
var _podium: HBoxContainer
var _how_to_play: Control

var _title_layer: CanvasLayer
var _title_label: Label
var _title_rule_label: Label
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

## The line under the stage title naming the game mode and its rule (#352).
func stage_title_rule_label() -> Label:
	return _title_rule_label

## The PAUSED banner, or null before the first pause.
func pause_label() -> Label:
	return _pause_label

## The victory screen's awards row, or null before any.
func awards_row() -> Control:
	return _podium.get_parent().get_node_or_null("Awards") as Control if _podium != null else null

## Whether the lobby and victory panels exist yet.
func panels_built() -> bool:
	return _lobby_panel != null

## The lobby's mode cards, its how-to-play explainer's game-mode lines (#352), one per `GameModes.TABLE` row.
func mode_cards() -> Array[Label]:
	var out: Array[Label] = []
	if _lobby_right != null and _lobby_right.has_node("ModeCards"):
		for child: Node in _lobby_right.get_node("ModeCards").get_children():
			if child.has_meta("mode_card"):
				out.append(child as Label)
	return out

## The how-to-play demos running now: four while the lobby shows, none
## otherwise.
func how_to_play_demos() -> Array[Node]:
	var out: Array[Node] = []
	if _how_to_play != null:
		for child: Node in _how_to_play.get_children():
			if child.get_script() == HowToPlayDemoScript:
				out.append(child)
	return out

## Which full-screen panel shows: "lobby", "victory" or neither ("").
## The how-to-play demos run only while the lobby shows: they are built
## when it appears and freed the moment it goes (#219), so no demo body is
## simulated behind a round or the podium.
func show_panel(which: String) -> void:
	_lobby_panel.visible = which == "lobby"
	_victory_panel.visible = which == "victory"
	if which == "lobby":
		_start_demos()
	else:
		_stop_demos()

func _start_demos() -> void:
	if _how_to_play == null or not how_to_play_demos().is_empty():
		return
	for i in HOW_TO_PLAY_LINES.size():
		_how_to_play.add_child(HowToPlayDemoScript.new(HOW_TO_PLAY_KINDS[i], HOW_TO_PLAY_LINES[i], i))

func _stop_demos() -> void:
	for demo: Node in how_to_play_demos():
		# Out of the tree at once, not at the end of the frame: its bodies
		# leave their worlds, and its players the "players" group, now.
		_how_to_play.remove_child(demo)
		demo.queue_free()

## Redraws the lobby from the state the phones are sent. `min_players` is
## how many it takes to start; `join_source` (the ControllerServer, or null)
## has the join QR and URL.
func refresh_lobby(state: Dictionary, min_players: int, join_source: Object) -> void:
	for child: Node in _lobby_rows.get_children():
		child.queue_free()
	var teams: bool = bool(state.get("teams", false))
	if teams:
		_team_rosters(state)
	else:
		for entry: Dictionary in state["players"]:
			_lobby_rows.add_child(_lobby_row(state, entry, 36 if state["players"].size() <= 4 else 28))
	_lobby_target_label.text = "First to %d" % state["target"]
	if teams:
		_lobby_target_label.text = "Teams  -  first to %d" % state["target"]
	var joined: int = state["players"].size()
	if state["phase"] == "countdown":
		_lobby_status.text = str(state["count"])
	elif joined < min_players:
		_lobby_status.text = "Scan to join: %d joined (need %d)" % [joined, min_players]
	elif teams and not both_teams_manned(state):
		_lobby_status.text = "Both teams need a player: pick a team on your phone"
	else:
		_lobby_status.text = "Press Ready on your phone"
	if join_source != null:
		var qr: Variant = join_source.get("join_qr_texture")
		_lobby_qr.texture = qr as Texture2D
		_lobby_qr.visible = qr != null
		var url: Variant = join_source.get("join_url")
		_lobby_url.text = str(url) if url != null else ""

## One lobby row: the player's swatch, name, host tag and ready state.
func _lobby_row(state: Dictionary, entry: Dictionary, font_size: int) -> HBoxContainer:
	var slot: int = entry["slot"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(40, 40)
	swatch.color = _slot_color.call(slot)
	row.add_child(swatch)
	var tag: String = "  (host)" if slot == state["host"] else ""
	var label := _big_label("%s%s  -  %s" % [entry["name"], tag, "READY" if entry["ready"] else "not ready"],
		font_size, LOBBY_ACCENT if entry["ready"] else Color(0.8, 0.82, 0.88))
	row.add_child(label)
	return row

## Issue #236: a Teams lobby's two rosters side by side, Red then Blue, each
## under its team's name in its colour; a player who has not picked a team is
## listed where auto-balance puts them, marked "(auto)".
func _team_rosters(state: Dictionary) -> void:
	var columns := HBoxContainer.new()
	columns.name = "TeamRosters"
	columns.set_meta("team_rosters", true)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 40)
	_lobby_rows.add_child(columns)
	for team in TeamsScript.COUNT:
		var column := VBoxContainer.new()
		column.name = "%sRoster" % TeamsScript.team_name(team).capitalize()
		column.add_theme_constant_override("separation", 8)
		var members: Array = state["players"].filter(func(e: Dictionary) -> bool: return int(e.get("team", -1)) == team)
		column.add_child(_big_label("%s TEAM (%d)" % [TeamsScript.team_name(team), members.size()], 40, TeamsScript.team_color(team)))
		for entry: Dictionary in members:
			var row: HBoxContainer = _lobby_row(state, entry, 28)
			if int(entry.get("pick", team)) == TeamsScript.NONE:
				row.add_child(_big_label("(auto)", 22, Color(0.8, 0.82, 0.88)))
			column.add_child(row)
		if members.is_empty():
			column.add_child(_big_label("nobody yet", 26, Color(0.6, 0.62, 0.68)))
		columns.add_child(column)

## Issue #236: the lobby's two team rosters, or null outside a Teams lobby.
## (A redraw frees the old rosters at the end of the frame, so the live one
## is the one not queued for deletion.)
func team_rosters() -> Control:
	if _lobby_rows == null:
		return null
	for child: Node in _lobby_rows.get_children():
		if child.has_meta("team_rosters") and not child.is_queued_for_deletion():
			return child as Control
	return null

## Issue #236: whether a Teams lobby state has somebody on each team.
static func both_teams_manned(state: Dictionary) -> bool:
	var counts: Array[int] = [0, 0]
	for entry: Dictionary in state["players"]:
		var team: int = int(entry.get("team", -1))
		if team >= 0 and team < TeamsScript.COUNT:
			counts[team] += 1
	return counts[0] > 0 and counts[1] > 0

## The victory screen's title, or null before the panels are built.
func victory_title() -> Label:
	return _victory_title

## The podium: `slots` already in podium order (the match winner first, then
## by final score), each with its score from `scores`, then `awards` under it.
##
## Issue #236: a Teams match passes `winner_team`, each slot's team in `teams`
## and the team points in `team_scores`: the title names the winning team,
## and each column shows its player's team in place of a personal score.
func refresh_victory(slots: Array[int], scores: PackedInt32Array, winner_slot: int, awards: Array[Dictionary],
		winner_team: int = -1, teams: Dictionary = {}, team_scores: PackedInt32Array = PackedInt32Array(),
		stat_rows: Array[Dictionary] = []) -> void:
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
		if not teams.is_empty():
			var team: int = int(teams.get(slot, TeamsScript.NONE))
			name_label.text = "%s\n%s" % [_slot_name.call(slot), TeamsScript.team_name(team)]
			name_label.add_theme_color_override("font_color", TeamsScript.team_color(team))
		if crowded:
			# A fixed column that a long name wraps inside rather than widens.
			name_label.custom_minimum_size.x = PODIUM_CROWDED_COLUMN_PX
			name_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		column.add_child(name_label)
		var block := ColorRect.new()
		block.color = _slot_color.call(slot)
		block.custom_minimum_size = Vector2(120 if crowded else 160, PODIUM_TALLEST_PX * (0.55 if not stat_rows.is_empty() else 1.0) * PODIUM_HEIGHTS[mini(place, PODIUM_HEIGHTS.size() - 1)])
		column.add_child(block)
		column.add_child(_big_label(str(place + 1), 28, Color.WHITE))
		_podium.add_child(column)
	if winner_team != -1:
		_victory_title.text = "%s TEAM WINS!" % TeamsScript.team_name(winner_team)
		_victory_title.add_theme_color_override("font_color", TeamsScript.team_color(winner_team))
	elif winner_slot != -1:
		_victory_title.text = "%s WINS!" % _slot_name.call(winner_slot)
		_victory_title.add_theme_color_override("font_color", _slot_color.call(winner_slot))
	else:
		_victory_title.text = "MATCH OVER"
	_refresh_awards(awards)
	_refresh_stat_table(stat_rows)

## The victory screen's per-player stats table, or null before any.
func stats_table() -> Control:
	return _podium.get_parent().get_node_or_null("StatRows") as Control if _podium != null else null

func _refresh_stat_table(stat_rows: Array[Dictionary]) -> void:
	var stack: Node = _podium.get_parent()
	var old: Node = stack.get_node_or_null("StatRows")
	if old != null:
		stack.remove_child(old)
		old.queue_free()
	if stat_rows.is_empty():
		return
	var table: Control = KillFeedScript.stat_table(stat_rows, _slot_name, _slot_color)
	stack.add_child(table)
	var prompt_at: int = stack.get_child_count() - 2
	stack.move_child(table, prompt_at)

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
	columns.add_theme_constant_override("separation", 48)
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
	# Wrapped rather than one long line, so the how-to-play column fits
	# beside the QR (#219).
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_status.custom_minimum_size.x = LOBBY_STATUS_WIDTH_PX
	left.add_child(_lobby_status)
	var right := VBoxContainer.new()
	_lobby_right = right
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 16)
	columns.add_child(right)
	_lobby_qr = TextureRect.new()
	_lobby_qr.custom_minimum_size = Vector2(380, 380)
	_lobby_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lobby_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lobby_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(_lobby_qr)
	_lobby_url = _big_label("", 28, Color(0.8, 0.82, 0.88))
	right.add_child(_lobby_url)
	# One card per game mode (#352), from `GameModes.TABLE`, under the QR:
	# the how-to-play column is already as tall as the screen allows.
	var cards := VBoxContainer.new()
	cards.name = "ModeCards"
	cards.add_theme_constant_override("separation", 0)
	right.add_child(cards)
	for row: Dictionary in GameModesScript.TABLE:
		var card: Label = _big_label("%s: %s" % [row["name"], row["rule"]], 12, Color(0.8, 0.82, 0.88))
		card.set_meta("mode_card", true)
		cards.add_child(card)
	# A column of its own, beside the QR and never over it (#219).
	# Clear of the Settings corner below it (#230).
	_how_to_play = _build_how_to_play()
	var how_to_play_slot := MarginContainer.new()
	how_to_play_slot.name = "HowToPlaySlot"
	how_to_play_slot.add_theme_constant_override("margin_bottom", SETTINGS_CORNER_RESERVE_PX)
	how_to_play_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	how_to_play_slot.add_child(_how_to_play)
	columns.add_child(how_to_play_slot)

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
	stack.add_child(_big_label("Tap Continue on your phone", 40, Color.WHITE))

func _full_screen_panel(node_name: String) -> Control:
	var panel := ColorRect.new()
	panel.name = node_name
	panel.color = LOBBY_BACKGROUND
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	add_child(panel)
	return panel

## The how-to-play column: its heading, and the demos while the lobby shows.
func _build_how_to_play() -> Control:
	var box := VBoxContainer.new()
	box.name = "HowToPlay"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	# Tighter than it was (14 px) to make room for SETTINGS_CORNER_RESERVE_PX.
	box.add_theme_constant_override("separation", 10)
	box.add_child(_big_label("HOW TO PLAY", 34, LOBBY_ACCENT))
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
func show_stage_title(text: String, duration: float, rule: String = "") -> void:
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
		# A child of the title, so the sweep carries it along.
		_title_rule_label = Label.new()
		_title_rule_label.name = "StageTitleRule"
		_title_rule_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_rule_label.add_theme_font_size_override("font_size", 32)
		_title_rule_label.add_theme_color_override("font_color", LOBBY_ACCENT)
		_title_rule_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 1.0))
		_title_rule_label.add_theme_constant_override("outline_size", 8)
		_title_label.add_child(_title_rule_label)
	_title_label.text = text
	_title_label.reset_size()
	_title_rule_label.text = rule
	_title_rule_label.visible = rule != ""
	_title_rule_label.reset_size()
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var width: float = _title_label.get_minimum_size().x
	var middle: float = (screen.x - width) * 0.5
	_title_rule_label.position = Vector2((width - _title_rule_label.get_minimum_size().x) * 0.5, 96.0)
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

# --- Host-screen lobby controls (issue #239) -------------------------------------
#
# For a PC-only match with no phone: clickable buttons and keys for Go online
# (O), Play on this PC (P), Mode (T), First to (- and =) and Start (Enter).
# Each calls ControllerServer.apply_host_command(), the same function the host
# phone's menu ends up in, so nothing is decided here.

const CONTROL_KEYS: Dictionary = {
	"online": KEY_O, "pc_seat": KEY_P, "mode": KEY_T, "target_down": KEY_MINUS,
	"target_up": KEY_EQUAL, "start": KEY_ENTER, "join": KEY_J,
}
const REMOTE_CLIENT_SCENE: String = "res://scenes/RemoteClient.tscn"

var _server: Object = null
var _controls: Dictionary = {}
var _room_label: Label
var _online_status: Label

## Builds the controls (once) under the QR and points them at `server`. A
## server without `apply_host_command` (a test stub) gets none.
func attach_controls(server: Object) -> void:
	if _lobby_right == null or _server != null or server == null or not server.has_method("apply_host_command"):
		return
	_server = server
	var box := VBoxContainer.new()
	box.name = "HostControls"
	box.add_theme_constant_override("separation", 8)
	_lobby_right.add_child(box)
	_room_label = _big_label("", 64, LOBBY_ACCENT)
	_room_label.name = "RoomCode"
	_room_label.visible = false
	_lobby_right.add_child(_room_label)
	_lobby_right.move_child(_room_label, _lobby_url.get_index() + 1)
	var online_row := HBoxContainer.new()
	online_row.add_theme_constant_override("separation", 12)
	box.add_child(online_row)
	online_row.add_child(_control_button("online", "Go online (O)"))
	_online_status = _big_label("", 24, Color(0.8, 0.82, 0.88))
	online_row.add_child(_online_status)
	box.add_child(_control_button("pc_seat", "Play on this PC (P)"))
	var pad_hint := _big_label("Press A on a gamepad to join", 24, Color(0.8, 0.82, 0.88))
	pad_hint.name = "GamepadHint"
	box.add_child(pad_hint)
	box.add_child(_control_button("mode", "Mode (T)"))
	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 12)
	box.add_child(target_row)
	target_row.add_child(_control_button("target_down", "First to  -"))
	target_row.add_child(_control_button("target_up", "+"))
	box.add_child(_control_button("start", "Start match (Enter)"))
	box.add_child(_control_button("join", "Join online game (J)"))
	refresh_controls()

func _control_button(id: String, text: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 26)
	button.pressed.connect(press_control.bind(id))
	_controls[id] = button
	return button

## The control button `id` ("online", "pc_seat", "mode", "target_down",
## "target_up", "start"), or null.
func control_button(id: String) -> Button:
	return _controls.get(id) as Button

## What a click or key on control `id` does.
func press_control(id: String) -> void:
	if _server == null:
		return
	match id:
		"online":
			_server.apply_host_command("online", not _server.online_requested())
		"pc_seat":
			_server.apply_host_command("pc_seat", _server.host_pc_slot() == -1)
		"mode":
			_server.apply_host_command("mode", "ffa" if _server.team_mode() else "teams")
		"target_down":
			_server.apply_host_command("target", _server.match_target() - 1)
		"target_up":
			_server.apply_host_command("target", _server.match_target() + 1)
		"start":
			_server.apply_host_command("start")
		"join":
			# Issue #241: leave this host's lobby for the PC client's join
			# screen. Only while nobody is seated, so a click cannot end a
			# match someone is in.
			if _can_join_online():
				get_tree().change_scene_to_file(REMOTE_CLIENT_SCENE)
				return
	refresh_controls()

func _can_join_online() -> bool:
	if _server == null or not _server.has_method("claimed_slots"):
		return false
	return _server.claimed_slots().is_empty() and _server.host_pc_slot() == -1 and not _server.online_requested()

## Redraws the controls' captions from the server: the link state beside the
## toggle, the room code large beside the QR.
func refresh_controls() -> void:
	if _server == null:
		return
	var status: String = _server.online_status()
	var code: String = _server.online_room_code()
	control_button("online").text = "Go online (O): %s" % ("on" if _server.online_requested() else "off")
	_online_status.text = {"connecting": "connecting…", "online": "online", "unreachable": "relay unreachable"}.get(status, "")
	_room_label.text = "Online: %s" % code
	_room_label.visible = code != ""
	control_button("pc_seat").text = "Play on this PC (P): %s" % ("on" if _server.host_pc_slot() != -1 else "off")
	control_button("mode").text = "Mode (T): %s" % ("Teams" if _server.team_mode() else "Free-for-all")
	control_button("join").disabled = not _can_join_online()

func _process(_delta: float) -> void:
	if _server != null and _lobby_panel != null and _lobby_panel.visible:
		refresh_controls()

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _server == null or key == null or not key.pressed or key.echo or _lobby_panel == null or not _lobby_panel.visible:
		return
	for id: String in CONTROL_KEYS:
		if key.physical_keycode == CONTROL_KEYS[id] or (id == "start" and key.physical_keycode == KEY_KP_ENTER):
			press_control(id)
			get_viewport().set_input_as_handled()
			return
