extends CanvasLayer

## The shared screen's own UI, built in code and split out of RoundManager
## (#175): the lobby (#120: game name, join QR, each phone's colour, name and
## ready state, and the how-to-play panel from #149), and the coordinator of
## the other host-screen parts.
##
## Since #543 the other screens live in their own scripts, each preloaded by
## path and built by this node, which forwards their public API so callers
## (RoundManager, the scenarios) are unchanged:
##   - `TitleScreen.gd`: the Couch / Online / Solo title screen (#435).
##   - `VictoryScreen.gd`: the podium, awards row, stats table and end card.
##   - `RoundCards.gd`: the stage title card (#120) and the PAUSED banner (#149).
##   - `HostControls.gd`: the lobby's host buttons and keys (#239), the gamepad
##     host menu (#368) and the host PC's cosmetics picker (#441).
##   - `ScreenKit.gd`: the palette and label / panel builders they share.
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

const HowToPlayDemoScript := preload("res://scripts/HowToPlayDemo.gd")
const GameModesScript := preload("res://scripts/GameModes.gd")
const TeamsScript := preload("res://scripts/Teams.gd")
const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const TitleScreenScript := preload("res://scripts/TitleScreen.gd")
const VictoryScreenScript := preload("res://scripts/VictoryScreen.gd")
const RoundCardsScript := preload("res://scripts/RoundCards.gd")
const HostControlsScript := preload("res://scripts/HostControls.gd")

const LOBBY_BACKGROUND: Color = ScreenKitScript.LOBBY_BACKGROUND
const LOBBY_ACCENT: Color = ScreenKitScript.LOBBY_ACCENT
const DECK_MIN_FONT_SIZE: int = ScreenKitScript.DECK_MIN_FONT_SIZE
const GAME_TITLE: String = "PICKFIGHT"
const LOGO_PATH: String = ScreenKitScript.LOGO_PATH
const LOGO_LOBBY_SIZE: Vector2 = ScreenKitScript.LOGO_LOBBY_SIZE
const LOGO_VICTORY_SIZE: Vector2 = ScreenKitScript.LOGO_VICTORY_SIZE
const PODIUM_INK: Color = VictoryScreenScript.PODIUM_INK
const PODIUM_HEIGHTS: Array[float] = VictoryScreenScript.PODIUM_HEIGHTS
const PODIUM_TALLEST_PX: float = VictoryScreenScript.PODIUM_TALLEST_PX
const PODIUM_CROWDED_COLUMN_PX: float = VictoryScreenScript.PODIUM_CROWDED_COLUMN_PX
const CONTROL_KEYS: Dictionary = HostControlsScript.CONTROL_KEYS
const CONTROL_BUTTON_FONT_SIZE: int = HostControlsScript.CONTROL_BUTTON_FONT_SIZE
const ROOM_CODE_FONT_SIZE: int = HostControlsScript.ROOM_CODE_FONT_SIZE
const REMOTE_CLIENT_SCENE: String = HostControlsScript.REMOTE_CLIENT_SCENE
const START_NOTICE_MSEC: int = HostControlsScript.START_NOTICE_MSEC
const PAD_ORDER: Array[String] = HostControlsScript.PAD_ORDER
const TITLE_KINDS: Array[String] = TitleScreenScript.TITLE_KINDS
const TITLE_KEYS: Dictionary = TitleScreenScript.TITLE_KEYS
const TITLE_BUTTON_FONT_SIZE: int = TitleScreenScript.TITLE_BUTTON_FONT_SIZE
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
## The lobby's mode-card grid (#425): this many rows, this wide, each card this tall, so the QR above never shrinks for a new card.
const MODE_GRID_ROWS: int = 4
const MODE_GRID_WIDTH_PX: float = 436.0
const MODE_CARD_HEIGHT_PX: float = 49.0
const MODE_CARD_GAP_PX: int = 8
const HOW_TO_PLAY_KINDS: Array[int] = [
	HowToPlayDemoScript.Kind.SWING,
	HowToPlayDemoScript.Kind.CLIMB,
	HowToPlayDemoScript.Kind.PICKUP,
	HowToPlayDemoScript.Kind.WIN,
]

var _slot_name: Callable
var _slot_color: Callable

var _title_screen # TitleScreen.gd
var _victory # VictoryScreen.gd
var _cards # RoundCards.gd
var _host # HostControls.gd

var _lobby_panel: Control
var _lobby_rows: VBoxContainer
var _lobby_status: Label
var _lobby_target_label: Label
var _lobby_qr: TextureRect
var _lobby_url: Label
var _lobby_right: VBoxContainer
var _mode_grid: GridContainer
var _how_to_play: Control
var _lobby_logo: TextureRect

## The ControllerServer the host controls command, set by `attach_controls()`.
var _server: Object = null

# Widgets that live in the split-out scripts, kept readable here by name.
var _podium: HBoxContainer:
	get: return _victory._podium
var _room_label: Label:
	get: return _host._room_label
var _online_status: Label:
	get: return _host._online_status

func _init(slot_name: Callable = Callable(), slot_color: Callable = Callable()) -> void:
	name = "LobbyLayer"
	layer = 5
	_slot_name = slot_name
	_slot_color = slot_color
	_title_screen = TitleScreenScript.new(self)
	_victory = VictoryScreenScript.new(self, slot_name, slot_color)
	_cards = RoundCardsScript.new(self)
	_host = HostControlsScript.new(self)

func lobby_panel() -> Control:
	return _lobby_panel

func victory_panel() -> Control:
	return _victory.victory_panel()

## The demo build's "wishlist the full game" card (#361), shown after the
## victory screen; hidden otherwise.
func end_card_panel() -> Control:
	return _victory.end_card_panel()

## The lobby's how-to-play panel, or null before the lobby was ever shown.
func how_to_play_panel() -> Control:
	return _how_to_play

## The wordmark on the lobby, or null before the lobby was ever built.
func lobby_logo() -> TextureRect:
	return _lobby_logo

## The wordmark on the victory screen, or null before it was ever built.
func victory_logo() -> TextureRect:
	return _victory.victory_logo()

## The logo as a texture: the imported resource when there is one, else the
## SVG rasterised at 1600x400.
static func load_logo_texture() -> Texture2D:
	return ScreenKitScript.load_logo_texture()

## The title card label, or null before any round has started.
func stage_title_label() -> Label:
	return _cards.stage_title_label()

## The line under the stage title naming the game mode and its rule (#352).
func stage_title_rule_label() -> Label:
	return _cards.stage_title_rule_label()

## The PAUSED banner, or null before the first pause.
func pause_label() -> Label:
	return _cards.pause_label()

## The victory screen's awards row, or null before any.
func awards_row() -> Control:
	return _victory.awards_row()

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

## Adds one mode card to the lobby's grid (#425). The grid keeps `MODE_GRID_ROWS` rows and opens
## a column when the rows are full, so an added card never makes the column above it taller.
func append_mode_card(text: String) -> Label:
	var card: Label = ScreenKitScript.big_label(text, DECK_MIN_FONT_SIZE, Color(0.8, 0.82, 0.88))
	card.set_meta("mode_card", true)
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.max_lines_visible = 2
	card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mode_grid.add_child(card)
	var columns: int = maxi(1, ceili(float(_mode_grid.get_child_count()) / float(MODE_GRID_ROWS)))
	_mode_grid.columns = columns
	# The grid is as wide as it was for two columns, so a third column narrows the cards instead of the room around it.
	var width: float = floorf((MODE_GRID_WIDTH_PX - MODE_CARD_GAP_PX * (columns - 1)) / columns)
	for each: Node in _mode_grid.get_children():
		(each as Label).custom_minimum_size = Vector2(width, MODE_CARD_HEIGHT_PX)
	return card

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
	_victory.victory_panel().visible = which == "victory"
	if _victory.end_card_panel() != null:
		_victory.end_card_panel().visible = which == "end_card"
	if which != "lobby" and title_visible():
		show_title(false) # a match began under the title: let go of PadMenu (#545)
	if which == "lobby":
		_start_demos()
	else:
		_stop_demos()

func _start_demos() -> void:
	if _how_to_play == null or not how_to_play_demos().is_empty():
		return
	for i in HOW_TO_PLAY_LINES.size():
		_how_to_play.add_child(HowToPlayDemoScript.new(HOW_TO_PLAY_KINDS[i], tr("HOW_TO_PLAY_LINE_%d" % (i + 1)), i))

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
	_last_lobby_args = [state, min_players, join_source]
	_rows_have_kick = _server != null and _server.has_method("pc_runs_room") and _server.pc_runs_room()
	for child: Node in _lobby_rows.get_children():
		child.queue_free()
	var teams: bool = bool(state.get("teams", false))
	if teams:
		_team_rosters(state)
	else:
		for entry: Dictionary in state["players"]:
			_lobby_rows.add_child(_lobby_row(state, entry, 36 if state["players"].size() <= 4 else 28))
	var target_key: String = GameModesScript.target_label_key(str(state.get("target_kind", "first_to")))
	_lobby_target_label.text = tr(target_key) % state["target"]
	if teams and target_key == "LOBBY_FIRST_TO":
		_lobby_target_label.text = tr("LOBBY_TEAMS_FIRST_TO") % state["target"]
	var joined: int = state["players"].size()
	var online: bool = _online_kind(join_source)
	if state["phase"] == "countdown":
		_lobby_status.text = str(state["count"])
	elif joined < min_players:
		_lobby_status.text = (tr("LOBBY_ONLINE_WAITING") if online else tr("LOBBY_SCAN_TO_JOIN")) % [joined, min_players]
	elif teams and not both_teams_manned(state):
		_lobby_status.text = tr("LOBBY_BOTH_TEAMS_NEED_PLAYER")
	else:
		_lobby_status.text = tr("LOBBY_PRESS_READY_ONLINE") if online else tr("LOBBY_PRESS_READY")
	if state["phase"] != "countdown" and Time.get_ticks_msec() < _host.start_notice_until_msec:
		_lobby_status.text = _host.start_notice
	if join_source != null:
		var qr: Variant = join_source.get("join_qr_texture")
		_lobby_qr.texture = qr as Texture2D
		var url: Variant = join_source.get("join_url")
		_lobby_url.text = str(url) if url != null else ""
	_apply_streamer_mode(join_source)

## Streamer mode (#369): with "Hide room code" on, the join QR, URL and online
## room code give way to a notice; the host phone's menu still has the code.
func _apply_streamer_mode(join_source: Object) -> void:
	if join_source == null:
		return
	var hidden_text: String = tr("ROOM_CODE_HIDDEN")
	var hidden: bool = join_source.has_method("room_code_hidden") and join_source.room_code_hidden()
	_lobby_qr.visible = join_source.get("join_qr_texture") != null and not hidden
	if hidden:
		_lobby_url.text = hidden_text
	elif _lobby_url.text == hidden_text:
		_lobby_url.text = str(join_source.get("join_url"))
	if _room_label != null and hidden:
		_room_label.visible = false
	# #435: an Online match has no QR and no LAN join URL; a Couch one gets them back.
	var online: bool = _online_kind(join_source)
	_lobby_url.visible = not online
	if online:
		_lobby_qr.visible = false

## One lobby row: the player's swatch, name, host tag and ready state.
func _lobby_row(state: Dictionary, entry: Dictionary, font_size: int) -> HBoxContainer:
	var slot: int = entry["slot"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(40, 40)
	swatch.color = _slot_color.call(slot)
	row.add_child(swatch)
	var tag: String = tr("LOBBY_HOST_TAG") if slot == state["host"] else ""
	var label := ScreenKitScript.big_label("%s%s  -  %s" % [entry["name"], tag, tr("LOBBY_READY") if entry["ready"] else tr("LOBBY_NOT_READY")],
		font_size, LOBBY_ACCENT if entry["ready"] else Color(0.8, 0.82, 0.88))
	row.add_child(label)
	if entry.has("ping"):
		var ping_label := ScreenKitScript.big_label(ping_text(int(entry["ping"])), maxi(font_size - 8, 18), ping_color(int(entry["ping"])))
		ping_label.name = "Ping"
		row.add_child(ping_label)
	if bool(entry.get("tip", false)):
		row.add_child(ScreenKitScript.big_label(tr("LOBBY_PAD_TIP"), 22, Color(0.8, 0.82, 0.88)))
	# Issue #441: a gamepad claim's card carries its cosmetics picker (it hides itself while unplugged).
	if _server != null and _server.has_method("pad_claim") and _server.pad_claim(slot):
		row.add_child(preload("res://scripts/PadPickerCard.gd").new(_server, slot))
	_add_kick_button(row, slot)
	return row

## Issue #458: running the room (Online, ADR-0021), the host PC kicks from the
## lobby row itself: a Kick on every row but its own seat's.
func _add_kick_button(row: HBoxContainer, slot: int) -> void:
	if _server == null or not _server.has_method("pc_runs_room") or not _server.pc_runs_room() or slot == _server.host_pc_slot():
		return
	var kick: Button = Button.new()
	kick.name = "Kick"
	kick.text = tr("HOST_KICK")
	kick.focus_mode = Control.FOCUS_NONE
	kick.add_theme_font_size_override("font_size", CONTROL_BUTTON_FONT_SIZE)
	kick.pressed.connect(func() -> void: _server.host_pc_command("kick", slot))
	row.set_meta("kick_slot", slot)
	row.add_child(kick)

## Issue #458: the last `refresh_lobby()` arguments, and whether its rows had
## Kick buttons, so Go online turning them on or off redraws the rows.
var _last_lobby_args: Array = []
var _rows_have_kick: bool = false

## Issue #458: the Kick button on `slot`'s lobby row, or null.
func kick_button(slot: int) -> Button:
	if _lobby_rows == null:
		return null
	for node: Node in _lobby_rows.find_children("*", "HBoxContainer", true, false):
		if node.has_meta("kick_slot") and int(node.get_meta("kick_slot")) == slot and not _queued(node):
			return node.get_node_or_null("Kick") as Button
	return null

static func _queued(node: Node) -> bool:
	while node != null:
		if node.is_queued_for_deletion():
			return true
		node = node.get_parent()
	return false

## Issue #446: a remote seat's round trip as text, and the colour it is shown
## in: a warning colour above 150 ms.
const PING_WARN_MSEC: int = 150
const PING_OK_COLOR := Color(0.6, 0.85, 0.65)
const PING_WARN_COLOR := Color(1.0, 0.45, 0.25)
static func ping_text(ms: int) -> String:
	return TranslationServer.translate("PING_MS") % ms
static func ping_color(ms: int) -> Color:
	return PING_WARN_COLOR if ms > PING_WARN_MSEC else PING_OK_COLOR

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
		column.add_child(ScreenKitScript.big_label(tr("LOBBY_TEAM_HEADER") % [TeamsScript.team_name(team), members.size()], 40, TeamsScript.team_color(team)))
		for entry: Dictionary in members:
			var row: HBoxContainer = _lobby_row(state, entry, 28)
			if int(entry.get("pick", team)) == TeamsScript.NONE:
				row.add_child(ScreenKitScript.big_label(tr("LOBBY_AUTO"), 22, Color(0.8, 0.82, 0.88)))
			column.add_child(row)
		if members.is_empty():
			column.add_child(ScreenKitScript.big_label(tr("LOBBY_NOBODY_YET"), 26, Color(0.6, 0.62, 0.68)))
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
	return _victory.victory_title()

## The podium: `slots` already in podium order (the match winner first, then
## by final score), each with its score from `scores`, then `awards` under it.
## See `VictoryScreen.refresh()`.
func refresh_victory(slots: Array[int], scores: PackedInt32Array, winner_slot: int, awards: Array[Dictionary],
		winner_team: int = -1, teams: Dictionary = {}, team_scores: PackedInt32Array = PackedInt32Array(),
		stat_rows: Array[Dictionary] = []) -> void:
	_victory.refresh(slots, scores, winner_slot, awards, winner_team, teams, team_scores, stat_rows)

## The victory screen's per-player stats table, or null before any.
func stats_table() -> Control:
	return _victory.stats_table()

## Builds the lobby and victory panels, both hidden. A no-op once built.
func build_panels() -> void:
	if _lobby_panel != null:
		return
	_lobby_panel = ScreenKitScript.full_screen_panel(self, "LobbyPanel")
	var columns := HBoxContainer.new()
	columns.set_anchors_preset(Control.PRESET_FULL_RECT)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 48)
	_lobby_panel.add_child(columns)
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 24)
	columns.add_child(left)
	_lobby_logo = ScreenKitScript.logo_rect("Logo", LOGO_LOBBY_SIZE)
	left.add_child(_lobby_logo)
	_lobby_target_label = ScreenKitScript.big_label(tr("LOBBY_FIRST_TO") % 5, 44, Color.WHITE)
	left.add_child(_lobby_target_label)
	_lobby_rows = VBoxContainer.new()
	_lobby_rows.add_theme_constant_override("separation", 12)
	left.add_child(_lobby_rows)
	_lobby_status = ScreenKitScript.big_label("", 56, LOBBY_ACCENT)
	# Wrapped rather than one long line, so the how-to-play column fits
	# beside the QR (#219).
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_status.custom_minimum_size.x = LOBBY_STATUS_WIDTH_PX
	left.add_child(_lobby_status)
	var right := VBoxContainer.new()
	_lobby_right = right
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	# Tightened for the sixth and seventh mode cards (#402, #403): eight players still fit the screen.
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	_lobby_qr = TextureRect.new()
	_lobby_qr.name = "JoinQr"
	_lobby_qr.custom_minimum_size = Vector2(340, 340) # 372, then 320 for the 16 px mode cards (#368) and CTF (#403); the card grid (#425) frees the room
	_lobby_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lobby_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lobby_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(_lobby_qr)
	_lobby_url = ScreenKitScript.big_label("", 28, Color(0.8, 0.82, 0.88))
	right.add_child(_lobby_url)
	# One card per game mode (#352), from `GameModes.TABLE`, under the QR:
	# the how-to-play column is already as tall as the screen allows.
	_mode_grid = GridContainer.new()
	_mode_grid.name = "ModeCards"
	_mode_grid.add_theme_constant_override("h_separation", MODE_CARD_GAP_PX)
	_mode_grid.add_theme_constant_override("v_separation", 0)
	# Fixed height for the rows (#425): a new card fills a free cell or opens a new column, so it never pushes the QR.
	_mode_grid.custom_minimum_size.y = MODE_GRID_ROWS * MODE_CARD_HEIGHT_PX
	right.add_child(_mode_grid)
	for row: Dictionary in GameModesScript.TABLE:
		append_mode_card("%s: %s" % [GameModesScript.display_name(row["id"]), GameModesScript.rule_line(row["id"])])
	# A column of its own, beside the QR and never over it (#219).
	# Clear of the Settings corner below it (#230).
	_how_to_play = _build_how_to_play()
	var how_to_play_slot := MarginContainer.new()
	how_to_play_slot.name = "HowToPlaySlot"
	how_to_play_slot.add_theme_constant_override("margin_bottom", SETTINGS_CORNER_RESERVE_PX)
	how_to_play_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	how_to_play_slot.add_child(_how_to_play)
	columns.add_child(how_to_play_slot)

	_victory.build()

## The how-to-play column: its heading, and the demos while the lobby shows.
func _build_how_to_play() -> Control:
	var box := VBoxContainer.new()
	box.name = "HowToPlay"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	# Tighter than it was (14 px) to make room for SETTINGS_CORNER_RESERVE_PX.
	box.add_theme_constant_override("separation", 10)
	box.add_child(ScreenKitScript.big_label(tr("HOW_TO_PLAY_TITLE"), 30, LOBBY_ACCENT)) # 34 before the Nunito metrics (#541)
	return box

# --- Forwards to the split-out screens (#543) --------------------------------

func show_stage_title(text: String, duration: float, rule: String = "") -> void:
	_cards.show_stage_title(text, duration, rule)

func show_pause_banner(on: bool) -> void:
	_cards.show_pause_banner(on)

func attach_controls(server: Object) -> void:
	_host.attach(server)

func control_button(id: String) -> Button:
	return _host.control_button(id)

func press_control(id: String) -> void:
	_host.press_control(id)

func refresh_controls() -> void:
	_host.refresh()

func host_picker() -> Control:
	return _host.host_picker()

## Whether the last input was a gamepad's, which decides the captions' glyphs.
func pad_active() -> bool:
	return _host.pad_active()

func pad_menu_open() -> bool:
	return _host.pad_menu_open()

func set_pad_menu(on: bool) -> void:
	_host.set_pad_menu(on)

func _process(_delta: float) -> void:
	_host.process()

func _input(event: InputEvent) -> void:
	_host.input(event)

func _exit_tree() -> void:
	_host.exit_tree()

func _unhandled_key_input(event: InputEvent) -> void:
	_host.unhandled_key_input(event)

func title_panel() -> Control:
	return _title_screen.title_panel()

func title_visible() -> bool:
	return _title_screen.title_visible()

func title_button(kind: String) -> Button:
	return _title_screen.title_button(kind)

func show_title(on: bool) -> void:
	_title_screen.show_title(on)

func press_title(kind: String) -> void:
	_title_screen.press_title(kind)

static func _online_kind(source: Object) -> bool:
	return TitleScreenScript.online_kind(source)

## The match kind as the player reads it: Couch, Online or Solo.
static func match_kind_text(source: Object) -> String:
	return TitleScreenScript.match_kind_text(source)
