extends RefCounted
## The lobby's centre column (#547): the "Players" heading with its count line and
## the 4x2 grid of player cards and dashed open seats, split out of
## `LobbyScreen.gd`. Cards persist from one redraw to the next (a new one pops in,
## a leaving one is freed), so a ready toggle or a ping does not replay the pop.
##
## `_screen` is the LobbyScreen (read dynamically: this script cannot name it
## without a preload cycle). Display only: clicks go back through the screen to
## the ControllerServer.

const LobbyPlayerCardScript := preload("res://scripts/LobbyPlayerCard.gd")
const LobbyEmptySeatScript := preload("res://scripts/LobbyEmptySeat.gd")
const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")
const TeamsScript := preload("res://scripts/Teams.gd")

const SEATS: int = 8
const COLUMNS: int = 4
const GRID_GAP_PX: int = 18

var _screen # the LobbyScreen
var _grid: GridContainer
var _count_label: Label
var _cards: Dictionary = {} # slot -> LobbyPlayerCard
var _empties: Array[Control] = []
var _hint: String = ""

func _init(screen) -> void:
	_screen = screen

## Builds the column into `parent`.
func build(parent: Control) -> void:
	var head := HBoxContainer.new()
	head.name = "PlayersHead"
	head.add_theme_constant_override("separation", 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(head)
	var title: Label = ScreenKitScript.themed_label(_screen.tr("LOBBY_PLAYERS"), 40, UiThemeScript.HEADING_LABEL)
	title.name = "PlayersTitle"
	head.add_child(title)
	_count_label = ScreenKitScript.themed_label("", 22, UiThemeScript.MUTED_LABEL)
	_count_label.name = "PlayerCount"
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_count_label)
	_grid = GridContainer.new()
	_grid.name = "PlayerCards"
	_grid.columns = COLUMNS
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", GRID_GAP_PX)
	_grid.add_theme_constant_override("v_separation", GRID_GAP_PX)
	parent.add_child(_grid)
	for _i in SEATS:
		var empty: Control = LobbyEmptySeatScript.new()
		_expand(empty)
		_empties.append(empty)

static func _expand(control: Control) -> void:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL

func grid() -> GridContainer:
	return _grid

func card(slot: int) -> Control:
	var found: Variant = _cards.get(slot)
	return found as Control if found != null and is_instance_valid(found) and not (found as Node).is_queued_for_deletion() else null

## The cards now, in grid order.
func cards() -> Array[Control]:
	var out: Array[Control] = []
	for node: Node in _grid.get_children():
		if node.get_script() == LobbyPlayerCardScript and not node.is_queued_for_deletion():
			out.append(node as Control)
	return out

## The dashed open seats showing now.
func open_seats() -> Array[Control]:
	var out: Array[Control] = []
	for node: Node in _grid.get_children():
		if node.get_script() == LobbyEmptySeatScript:
			out.append(node as Control)
	return out

## Redraws the column from the lobby state.
func refresh(state: Dictionary, join_source: Object) -> void:
	var server: Object = _screen._server
	var teams: bool = bool(state.get("teams", false))
	var entries: Array = state["players"].duplicate()
	if teams:
		entries = entries.filter(func(e: Dictionary) -> bool: return int(e.get("team", -1)) == 0) \
			+ entries.filter(func(e: Dictionary) -> bool: return int(e.get("team", -1)) != 0)
	var can_kick: bool = server != null and server.has_method("pc_runs_room") and server.pc_runs_room()
	var host_pc: int = server.host_pc_slot() if server != null and server.has_method("host_pc_slot") else -1
	var bots: int = 0
	var order: Array[Control] = []
	var seen: Dictionary = {}
	var fresh_cards: Array[Control] = []
	for entry: Dictionary in entries:
		if order.size() >= SEATS:
			break
		var slot: int = int(entry["slot"])
		seen[slot] = true
		var is_bot: bool = server != null and server.has_method("is_virtual") and server.is_virtual(slot)
		bots += 1 if is_bot else 0
		var fresh: bool = card(slot) == null
		var seat_card: Control = card(slot) if not fresh else _new_card(slot)
		var own: bool = slot == host_pc and server != null and server.has_method("match_kind") and ["online", "solo"].has(server.match_kind())
		var solo_host_ready: bool = own and server.has_method("room_closed") and server.room_closed()
		var info: Dictionary = {
			"name": entry["name"], "color": _screen._slot_color.call(slot) if _screen._slot_color.is_valid() else Color.WHITE,
			"hat": server.slot_hat(slot) if server != null and server.has_method("slot_hat") else "none",
			"eyes": server.slot_eyes(slot) if server != null and server.has_method("slot_eyes") else "round",
			"ready": bool(entry["ready"]), "bot": is_bot, "host": slot == int(state["host"]) and not own and not is_bot,
			"own": own, "ping": int(entry.get("ping", -1)), "tip": bool(entry.get("tip", false)),
			"clickable": own, "badge_clickable": solo_host_ready, "kickable": can_kick and slot != host_pc and not is_bot,
			"dim": not bool(entry["ready"]) and not is_bot,
		}
		if teams:
			var team: int = int(entry.get("team", -1))
			var text: String = _screen.tr("LOBBY_TEAM_TAG") % TeamsScript.team_name(team)
			info["team_text"] = text + (" " + _screen.tr("LOBBY_AUTO") if int(entry.get("pick", team)) == TeamsScript.NONE else "")
		seat_card.apply(info)
		if server != null and server.has_method("pad_claim") and server.pad_claim(slot):
			seat_card.add_picker(server)
		else:
			seat_card.remove_picker()
		order.append(seat_card)
		if fresh:
			fresh_cards.append(seat_card)
	for slot: int in _cards.keys():
		if not seen.has(slot):
			var gone: Variant = _cards[slot]
			_cards.erase(slot)
			if is_instance_valid(gone):
				if (gone as Node).get_parent() != null:
					(gone as Node).get_parent().remove_child(gone)
				(gone as Node).queue_free()
	var empty_count: int = SEATS - order.size()
	for i in empty_count:
		(_empties[i] as Control).call("set_hint", _hint)
		order.append(_empties[i])
	_set_order(order)
	for fresh_card: Control in fresh_cards:
		ScreenKitScript.pop_in(fresh_card)
	var humans: int = entries.size() - bots
	_count_label.text = (_screen.tr("LOBBY_COUNT_ONE_BOT") % humans) if bots == 1 else (_screen.tr("LOBBY_COUNT") % [humans, bots])

## The one-line hint on every open seat; it follows the match kind.
func set_hint(text: String) -> void:
	_hint = text
	for empty: Control in _empties:
		empty.call("set_hint", text)

func _new_card(slot: int) -> Control:
	var seat_card: Control = LobbyPlayerCardScript.new(slot)
	_expand(seat_card)
	_cards[slot] = seat_card
	seat_card.body_clicked.connect(_screen._on_card_clicked)
	seat_card.badge_pressed.connect(_screen._on_badge_pressed)
	seat_card.kick_pressed.connect(_screen._on_kick_pressed)
	return seat_card

func _set_order(order: Array[Control]) -> void:
	for child: Node in _grid.get_children():
		if not order.has(child):
			_grid.remove_child(child)
	for i in order.size():
		var want: Control = order[i]
		if want.get_parent() != _grid:
			_grid.add_child(want)
		_grid.move_child(want, i)
