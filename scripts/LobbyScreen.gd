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
##   - `HostControls.gd`: the lobby's top-bar kind switch, Host panel, buttons and
##     keys (#239), the gamepad host menu (#368) and the host PC's picker (#441).
##   - `LobbyCards.gd`, `LobbyPlayerCard.gd`, `LobbyEmptySeat.gd`: the 4x2 grid of
##     player cards and open seats (#547).
##   - `LobbyPopups.gd`: the How to play and Your look popups (#547).
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
const LobbyCardsScript := preload("res://scripts/LobbyCards.gd")
const LobbyPopupsScript := preload("res://scripts/LobbyPopups.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")

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
## The lessons of the How to play popup, in order, each shown by a looping demo
## (`HowToPlayDemo.gd`, #219) with its line as the caption.
const HOW_TO_PLAY_LINES: PackedStringArray = [
	"Drag on your phone to swing your pick. Flick fast to hit hard.",
	"Hook the pick on a ledge and pull to climb.",
	"Touch a weapon pickup to grab it.",
	"Hit them till they die, or knock them off. Last one standing wins.",
]
const HOW_TO_PLAY_KINDS: Array[int] = [
	HowToPlayDemoScript.Kind.SWING,
	HowToPlayDemoScript.Kind.CLIMB,
	HowToPlayDemoScript.Kind.PICKUP,
	HowToPlayDemoScript.Kind.WIN,
]
## The layout, in design px at 1600x900 (the mockup's): page margins, the three
## columns' widths and the gaps (#547).
const PAGE_MARGIN_SIDE_PX: int = 36
const PAGE_MARGIN_TOP_PX: int = 16
const PAGE_MARGIN_BOTTOM_PX: int = 34
const LEFT_COLUMN_PX: float = 360.0
const RIGHT_COLUMN_PX: float = 320.0
const COLUMN_GAP_PX: int = 28
const QR_MIN_PX: float = 150.0
const QR_PX: float = 176.0
const MODE_GRID_COLUMNS: int = 2
const MODE_GRID_ROWS: int = 4
const MODE_GRID_GAP_PX: int = 12
## The wordmark's visible height on the top bar; its image has air above and below.
const LOGO_BAR_SIZE: Vector2 = Vector2(560, 84)
const LOGO_DRAW_SIZE: Vector2 = Vector2(560, 140)
const LOGO_DRAW_OFFSET: Vector2 = Vector2(0, -16)

var _slot_name: Callable
var _slot_color: Callable

var _title_screen # TitleScreen.gd
var _victory # VictoryScreen.gd
var _cards # RoundCards.gd
var _host # HostControls.gd
var _players # LobbyCards.gd
var _popups # LobbyPopups.gd

var _lobby_panel: Control
## The hint under START ("N players not ready yet", why Start did nothing).
var _lobby_status: Label
## The mode summary at the top right: "Classic - Teams - first to 5".
var _lobby_target_label: Label
var _lobby_qr: TextureRect
var _lobby_url: Label
var _lobby_right: VBoxContainer
var _join_box: VBoxContainer
var _join_title: Label
var _join_note: Label
var _mode_grid: GridContainer
var _top_left: HBoxContainer
var _lobby_logo: TextureRect
var _countdown_label: Label
var _countdown_shown: int = 0
var _mode_cards_by_id: Dictionary = {}

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
	_players = LobbyCardsScript.new(self)
	_popups = LobbyPopupsScript.new(self)

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
	return _popups.help_panel() if _popups != null else null

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

## The lobby's mode cards: the name Label of each, one per mode (#352).
func mode_cards() -> Array[Label]:
	var out: Array[Label] = []
	if _mode_grid != null:
		for card: Node in _mode_grid.get_children():
			var title: Variant = card.get_meta("name_label", null)
			if title is Label:
				out.append(title)
	return out

## The rule line under each mode card's name: wrapped, never cut off, no numbers.
func mode_rules() -> Array[Label]:
	var out: Array[Label] = []
	if _mode_grid != null:
		for card: Node in _mode_grid.get_children():
			var rule: Variant = card.get_meta("rule_label", null)
			if rule is Label:
				out.append(rule)
	return out

## The mode card for game mode `id` ("" is Classic), or null.
func mode_card(id: String) -> Control:
	return _mode_cards_by_id.get(id) as Control

## Adds one mode card to the lobby's grid (#425). `text` is "Name: rule"; the grid keeps its
## two columns and grows downwards.
func append_mode_card(text: String, id: String = "\u0001") -> Label:
	var split: int = text.find(": ")
	var card_name: String = text.substr(0, split) if split >= 0 else text
	var rule: String = text.substr(split + 2) if split >= 0 else ""
	return _add_mode_card(id, card_name, rule)

func _add_mode_card(id: String, card_name: String, rule: String) -> Label:
	var card := PanelContainer.new()
	card.name = "Mode_" + (id if id != "" else "classic")
	card.theme_type_variation = UiThemeScript.MODE_CARD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 0)
	card.pivot_offset_ratio = Vector2(0.5, 0.5)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)
	var title: Label = ScreenKitScript.themed_label(card_name, 22, UiThemeScript.INK_HEADING_LABEL)
	title.name = "Name"
	title.clip_text = true
	box.add_child(title)
	var rule_label: Label = ScreenKitScript.themed_label(rule, DECK_MIN_FONT_SIZE, UiThemeScript.INK_BOLD_LABEL)
	rule_label.name = "Rule"
	rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(rule_label)
	var click := Button.new()
	click.name = "Pick"
	click.flat = true
	click.focus_mode = Control.FOCUS_NONE
	click.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	var ring := UiThemeScript.box(Color.TRANSPARENT, 14, 4)
	ring.border_color = UiThemeScript.SKY
	for state: String in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		click.add_theme_stylebox_override(state, empty)
	click.add_theme_stylebox_override("focus", ring)
	click.pressed.connect(_on_mode_card_pressed.bind(id))
	for grow_signal: Signal in [click.mouse_entered, click.focus_entered]:
		grow_signal.connect(_scale_card.bind(1.04, card))
	for shrink_signal: Signal in [click.mouse_exited, click.focus_exited]:
		shrink_signal.connect(_scale_card.bind(1.0, card))
	card.add_child(click)
	card.set_meta("rule_label", rule_label)
	card.set_meta("name_label", title)
	card.set_meta("mode_id", id)
	_mode_grid.add_child(card)
	# The grid keeps MODE_GRID_ROWS rows and opens a column when they are full, so a
	# ninth mode never pushes the left column off the screen (#425).
	_mode_grid.columns = maxi(MODE_GRID_COLUMNS, ceili(float(_mode_grid.get_child_count()) / float(MODE_GRID_ROWS)))
	if id != "\u0001":
		_mode_cards_by_id[id] = card
	_host.register_mode_button(id, click)
	return rule_label

func _scale_card(target: float, card: Control) -> void:
	if not card.is_inside_tree():
		return
	var tween: Tween = card.create_tween()
	tween.tween_property(card, "scale", Vector2(target, target), 0.09)

func _on_mode_card_pressed(id: String) -> void:
	_host.press_game_mode(id)

## Highlights the picked mode card: yellow, a lift and a slight tilt.
func _select_mode_card(id: String) -> void:
	for card: Node in _mode_grid.get_children():
		var on: bool = str(card.get_meta("mode_id", "\u0001")) == id
		var wanted: StringName = UiThemeScript.MODE_CARD_ON if on else UiThemeScript.MODE_CARD
		if (card as Control).theme_type_variation != wanted:
			(card as Control).theme_type_variation = wanted
			var tween: Tween = card.create_tween() if card.is_inside_tree() else null
			var angle: float = deg_to_rad(-1.5) if on else 0.0
			if tween != null:
				tween.tween_property(card, "rotation", angle, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				(card as Control).rotation = angle

## The how-to-play demos running now: four while the How to play popup is open,
## none otherwise.
func how_to_play_demos() -> Array[Node]:
	return _popups.demos() if _popups != null else []

## The How to play popup, or null before the lobby was ever built.
func how_to_play_popup() -> Control:
	return _popups.help_panel() if _popups != null else null

## The Your look popup, or null before the lobby was ever built.
func look_popup() -> Control:
	return _popups.look_overlay() if _popups != null else null

## Opens the popup `which` ("help" or "look"), or closes any with "".
func set_popup(which: String) -> void:
	_popups.open(which)

func popup_open() -> String:
	return _popups.current() if _popups != null else ""

## Which full-screen panel shows: "lobby", "victory" or neither ("").
## The how-to-play demos run only while their popup is open: they are built
## when it opens and freed the moment it closes or the lobby goes (#219), so no
## demo body is simulated behind a round or the podium.
func show_panel(which: String) -> void:
	_lobby_panel.visible = which == "lobby"
	_victory.victory_panel().visible = which == "victory"
	if _victory.end_card_panel() != null:
		_victory.end_card_panel().visible = which == "end_card"
	if which != "lobby" and title_visible():
		show_title(false) # a match began under the title: let go of PadMenu (#545)
	if which != "lobby":
		_popups.open("")

## Redraws the lobby from the state the phones are sent. `min_players` is
## how many it takes to start; `join_source` (the ControllerServer, or null)
## has the join QR and URL.
func refresh_lobby(state: Dictionary, min_players: int, join_source: Object) -> void:
	_last_lobby_args = [state, min_players, join_source]
	_rows_have_kick = _server != null and _server.has_method("pc_runs_room") and _server.pc_runs_room()
	var teams: bool = bool(state.get("teams", false))
	var online: bool = _online_kind(join_source)
	var solo: bool = online and join_source.has_method("room_closed") and join_source.room_closed()
	_players.set_hint(tr("LOBBY_SEAT_HINT_SOLO") if solo else (tr("LOBBY_SEAT_HINT_ONLINE") if online else tr("LOBBY_SEAT_HINT_COUCH")))
	_players.refresh(state, join_source)
	# The mode summary: "Classic - Teams - first to 5", and the Host panel's row.
	var mode_id: String = str(state.get("game_mode", GameModesScript.CLASSIC))
	var target_kind: String = str(state.get("target_kind", "first_to"))
	var target_text: String = tr(GameModesScript.target_status_key(target_kind)) % state["target"]
	_lobby_target_label.text = "%s%s - %s" % [GameModesScript.display_name(mode_id), " - " + tr("MODE_TEAMS") if teams else "", target_text]
	_host.set_target(target_kind, int(state["target"]))
	_select_mode_card(mode_id)
	_popups.set_mode(mode_id, target_kind, int(state["target"]))
	# The hint under START, and whether START is lit.
	var humans_waiting: int = 0
	for entry: Dictionary in state["players"]:
		var is_bot: bool = _server != null and _server.has_method("is_virtual") and _server.is_virtual(int(entry["slot"]))
		if not is_bot and not bool(entry["ready"]):
			humans_waiting += 1
	var joined: int = state["players"].size()
	var can_start: bool = state["phase"] != "countdown" and joined >= min_players and humans_waiting == 0 and (not teams or both_teams_manned(state))
	if state["phase"] == "countdown":
		_lobby_status.text = tr("LOBBY_STARTING")
	elif joined < min_players:
		_lobby_status.text = (tr("LOBBY_ONLINE_WAITING") if online else tr("LOBBY_SCAN_TO_JOIN")) % [joined, min_players]
	elif teams and not both_teams_manned(state):
		_lobby_status.text = tr("LOBBY_BOTH_TEAMS_NEED_PLAYER")
	elif humans_waiting > 0:
		_lobby_status.text = tr("LOBBY_NOT_READY_ONE") if humans_waiting == 1 else tr("LOBBY_NOT_READY_N") % humans_waiting
	else:
		_lobby_status.text = tr("LOBBY_ENTER_OR_START")
	if state["phase"] != "countdown" and Time.get_ticks_msec() < _host.start_notice_until_msec:
		_lobby_status.text = _host.start_notice
	_host.set_start_ready(can_start or state["phase"] == "countdown") # lit while the countdown runs
	_show_countdown(int(state["count"]) if state["phase"] == "countdown" else 0)
	if join_source != null:
		var qr: Variant = join_source.get("join_qr_texture")
		_lobby_qr.texture = qr as Texture2D
		var url: Variant = join_source.get("join_url")
		_lobby_url.text = str(url) if url != null else ""
	_apply_streamer_mode(join_source)

## The big countdown number over the lobby, punching in on each tick.
func _show_countdown(count: int) -> void:
	if _countdown_label == null:
		return
	_countdown_label.visible = count > 0
	if count > 0 and count != _countdown_shown:
		_countdown_label.text = str(count)
		ScreenKitScript.punch(_countdown_label, self)
	_countdown_shown = count

## Streamer mode (#369): with "Hide room code" on, the join QR, URL and online
## room code give way to a notice; the host phone's menu still has the code.
## Also what the join card shows per match kind (#435): a Couch match its QR and
## URL, an Online one the big room code, Solo (#522) neither.
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
	var online: bool = _online_kind(join_source)
	var solo: bool = online and join_source.has_method("room_closed") and join_source.room_closed()
	_lobby_url.visible = not online
	if online:
		_lobby_qr.visible = false
	if online and hidden:
		_lobby_url.visible = true # the notice stands where the code was
	_join_title.text = tr("LOBBY_SOLO_TITLE") if solo else (tr("LOBBY_ROOM_CODE_TITLE") if online else tr("LOBBY_SCAN_TITLE"))
	_join_note.text = tr("LOBBY_SOLO_NOTE") if solo else tr("LOBBY_ROOM_CODE_NOTE")
	_join_note.visible = online and not (hidden and not solo)
	if solo:
		_join_note.add_theme_font_size_override("font_size", 22)
	else:
		_join_note.add_theme_font_size_override("font_size", 20)

func _on_card_clicked(slot: int) -> void:
	if _server != null and _server.has_method("host_pc_slot") and slot == _server.host_pc_slot() and _server.host_picker_shown():
		set_popup("look")

func _on_badge_pressed(slot: int) -> void:
	if _server != null and _server.has_method("room_closed") and _server.room_closed() and slot == _server.host_pc_slot():
		_server.set_slot_ready(slot, not _server.slot_ready(slot))
		if not _last_lobby_args.is_empty():
			refresh_lobby.callv(_last_lobby_args)

func _on_kick_pressed(slot: int) -> void:
	if _server != null:
		_server.host_pc_command("kick", slot)

## Issue #458: the last `refresh_lobby()` arguments, and whether the cards had
## Kick buttons, so Go online turning them on or off redraws the cards.
var _last_lobby_args: Array = []
var _rows_have_kick: bool = false

## Issue #458: the Kick button on `slot`'s player card, or null.
func kick_button(slot: int) -> Button:
	if _players == null:
		return null
	var card: Control = _players.card(slot)
	return card.kick_button() if card != null else null

## The player card for `slot`, or null.
func player_card(slot: int) -> Control:
	return _players.card(slot) if _players != null else null

## The player cards now, in grid order.
func player_cards() -> Array[Control]:
	return _players.cards() if _players != null else []

## The dashed open seats now.
func open_seats() -> Array[Control]:
	return _players.open_seats() if _players != null else []

## Issue #446: a remote seat's round trip as text, and the colour it is shown
## in: a warning colour above 150 ms.
const PING_WARN_MSEC: int = 150
const PING_OK_COLOR := Color(0.6, 0.85, 0.65)
const PING_WARN_COLOR := Color(1.0, 0.45, 0.25)
static func ping_text(ms: int) -> String:
	return TranslationServer.translate("PING_MS") % ms
static func ping_color(ms: int) -> Color:
	return PING_WARN_COLOR if ms > PING_WARN_MSEC else PING_OK_COLOR

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
	_lobby_panel = ScreenKitScript.striped_panel(self, "LobbyPanel")
	var page := MarginContainer.new()
	page.name = "Page"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("margin_left", PAGE_MARGIN_SIDE_PX)
	page.add_theme_constant_override("margin_right", PAGE_MARGIN_SIDE_PX)
	page.add_theme_constant_override("margin_top", PAGE_MARGIN_TOP_PX)
	page.add_theme_constant_override("margin_bottom", PAGE_MARGIN_BOTTOM_PX)
	_lobby_panel.add_child(page)
	var page_box := VBoxContainer.new()
	page_box.name = "PageBox"
	page_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_box.add_theme_constant_override("separation", 14)
	page.add_child(page_box)
	page_box.add_child(_build_top_bar())
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override("separation", COLUMN_GAP_PX)
	page_box.add_child(columns)
	columns.add_child(_build_left_column())
	var centre := VBoxContainer.new()
	centre.name = "CentreColumn"
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_theme_constant_override("separation", 16)
	columns.add_child(centre)
	_players.build(centre)
	_lobby_right = VBoxContainer.new()
	_lobby_right.name = "RightColumn"
	_lobby_right.custom_minimum_size.x = RIGHT_COLUMN_PX
	_lobby_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_right.add_theme_constant_override("separation", 14)
	columns.add_child(_lobby_right)
	_lobby_status = ScreenKitScript.themed_label("", DECK_MIN_FONT_SIZE + 2, UiThemeScript.MUTED_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_lobby_status.name = "StartHint"
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_right.add_child(_lobby_status)
	_countdown_label = ScreenKitScript.themed_label("", 220, UiThemeScript.HEADING_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_countdown_label.name = "Countdown"
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_countdown_label.add_theme_color_override("font_color", UiThemeScript.YELLOW)
	_countdown_label.add_theme_color_override("font_outline_color", UiThemeScript.INK)
	_countdown_label.add_theme_constant_override("outline_size", 24)
	_countdown_label.visible = false
	_lobby_panel.add_child(_countdown_label)
	_popups.build(_lobby_panel)
	_victory.build()

## The top bar: the Couch / Online / Solo switch at the left (HostControls fills
## it), the wordmark in the middle and the mode summary at the right (#547).
func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 24)
	_top_left = HBoxContainer.new()
	_top_left.name = "TopLeft"
	_top_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_left.alignment = BoxContainer.ALIGNMENT_BEGIN
	_top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_top_left)
	var logo_holder := Control.new()
	logo_holder.name = "LogoHolder"
	logo_holder.custom_minimum_size = LOGO_BAR_SIZE
	logo_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(logo_holder)
	_lobby_logo = ScreenKitScript.logo_rect("Logo", LOGO_DRAW_SIZE)
	_lobby_logo.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_lobby_logo.position = LOGO_DRAW_OFFSET
	_lobby_logo.size = LOGO_DRAW_SIZE
	logo_holder.add_child(_lobby_logo)
	_lobby_target_label = ScreenKitScript.themed_label("", 28, UiThemeScript.HEADING_LABEL, HORIZONTAL_ALIGNMENT_RIGHT)
	_lobby_target_label.name = "StatusLine"
	_lobby_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_target_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lobby_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_lobby_target_label)
	return bar

## The left column: the join card (QR and URL, the room code or Solo practice)
## over the 2-column grid of mode cards.
func _build_left_column() -> Control:
	var left := VBoxContainer.new()
	left.name = "LeftColumn"
	left.custom_minimum_size.x = LEFT_COLUMN_PX
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 14)
	var card := PanelContainer.new()
	card.name = "JoinCard"
	card.theme_type_variation = UiThemeScript.CARD_PANEL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(card)
	_join_box = VBoxContainer.new()
	_join_box.name = "JoinBox"
	_join_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_join_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_join_box.add_theme_constant_override("separation", 8)
	card.add_child(_join_box)
	_join_title = ScreenKitScript.themed_label(tr("LOBBY_SCAN_TITLE"), 30, UiThemeScript.INK_HEADING_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_join_title.name = "JoinTitle"
	_join_box.add_child(_join_title)
	_lobby_qr = TextureRect.new()
	_lobby_qr.name = "JoinQr"
	_lobby_qr.custom_minimum_size = Vector2(QR_MIN_PX, QR_MIN_PX)
	_lobby_qr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lobby_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lobby_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lobby_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_join_box.add_child(_lobby_qr)
	_lobby_url = ScreenKitScript.themed_label("", 22, UiThemeScript.INK_BOLD_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_lobby_url.name = "JoinUrl"
	_lobby_url.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_join_box.add_child(_lobby_url)
	_join_note = ScreenKitScript.themed_label("", 20, UiThemeScript.INK_BOLD_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_join_note.name = "JoinNote"
	_join_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_note.visible = false
	_join_box.add_child(_join_note)
	var mode_title: Label = ScreenKitScript.themed_label(tr("LOBBY_MODE_TITLE"), 26, UiThemeScript.HEADING_LABEL)
	mode_title.name = "ModeTitle"
	left.add_child(mode_title)
	# One card per game mode (#352), from `GameModes.picker_rows()`.
	_mode_grid = GridContainer.new()
	_mode_grid.name = "ModeCards"
	_mode_grid.columns = MODE_GRID_COLUMNS
	_mode_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_grid.add_theme_constant_override("h_separation", MODE_GRID_GAP_PX)
	_mode_grid.add_theme_constant_override("v_separation", MODE_GRID_GAP_PX)
	left.add_child(_mode_grid)
	for row: Dictionary in GameModesScript.picker_rows():
		_add_mode_card(str(row["id"]), GameModesScript.display_name(row["id"]), GameModesScript.blurb(row["id"]))
	return left

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
