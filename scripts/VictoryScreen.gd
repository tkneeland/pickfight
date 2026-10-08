extends RefCounted

## The victory screen and the demo build's end card (#543, split out of
## `LobbyScreen.gd`): the podium with its awards row (#138, #148) and stats
## table, and the "wishlist the full game" card (#361). Display only: the
## LobbyScreen builds it with the rest of the panels and RoundManager's numbers
## arrive through `refresh()`.

const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const KillFeedScript := preload("res://scripts/KillFeed.gd")
const TeamsScript := preload("res://scripts/Teams.gd")
const DemoBuildScript := preload("res://scripts/DemoBuild.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")

const PODIUM_INK: Color = UiThemeScript.INK
## Podium block heights by place, as a fraction of the tallest.
const PODIUM_HEIGHTS: Array[float] = [1.0, 0.72, 0.5, 0.34]
const PODIUM_TALLEST_PX: float = 260.0
## A podium column's width once more than four are on it (issue #138).
const PODIUM_CROWDED_COLUMN_PX: float = 180.0

var _screen: CanvasLayer
var _slot_name: Callable
var _slot_color: Callable

var _victory_panel: Control
var _victory_title: Label
var _podium: HBoxContainer
var _victory_logo: TextureRect
var _end_card_panel: Control
var _continue_prompt_label: Label

func _init(screen: CanvasLayer, slot_name: Callable, slot_color: Callable) -> void:
	_screen = screen
	_slot_name = slot_name
	_slot_color = slot_color

func victory_panel() -> Control:
	return _victory_panel

## The demo build's "wishlist the full game" card (#361), shown after the
## victory screen; hidden otherwise.
func end_card_panel() -> Control:
	return _end_card_panel

## The wordmark on the victory screen, or null before it was ever built.
func victory_logo() -> TextureRect:
	return _victory_logo

## The victory screen's title, or null before the panels are built.
func victory_title() -> Label:
	return _victory_title

## The victory screen's awards row, or null before any.
func awards_row() -> Control:
	return _podium.get_parent().get_node_or_null("Awards") as Control if _podium != null else null

## The victory screen's per-player stats table, or null before any.
func stats_table() -> Control:
	return _podium.get_parent().get_node_or_null("StatRows") as Control if _podium != null else null

## Builds the victory panel and the end card, both hidden.
func build() -> void:
	_victory_panel = ScreenKitScript.full_screen_panel(_screen, "VictoryPanel")
	(_victory_panel as ColorRect).color = UiThemeScript.INDIGO
	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 32)
	_victory_panel.add_child(stack)
	# A corner overlay, outside the stack so it never costs the podium height.
	_victory_logo = ScreenKitScript.logo_rect("Logo", ScreenKitScript.LOGO_VICTORY_SIZE)
	_victory_logo.position = Vector2(24, 16)
	_victory_logo.size = ScreenKitScript.LOGO_VICTORY_SIZE
	_victory_panel.add_child(_victory_logo)
	_victory_title = ScreenKitScript.ink_label("", 96, UiThemeScript.YELLOW, 14) # 110 before the Nunito metrics (#541); a 12-W name must still fit 1600
	stack.add_child(_victory_title)
	_podium = HBoxContainer.new()
	_podium.alignment = BoxContainer.ALIGNMENT_CENTER
	_podium.add_theme_constant_override("separation", 40)
	stack.add_child(_podium)
	_continue_prompt_label = _continue_prompt()
	stack.add_child(_continue_prompt_label)
	_build_end_card()

## "Tap Continue": ink Lilita text on a cream pill (the theme's cream panel).
func _continue_prompt() -> Label:
	var prompt: Label = ScreenKitScript.ink_label(_screen.tr("VICTORY_TAP_CONTINUE"), 40, UiThemeScript.INK, 1)
	prompt.name = "ContinuePrompt"
	prompt.theme_type_variation = UiThemeScript.INK_HEADING_LABEL
	prompt.add_theme_constant_override("outline_size", 0)
	prompt.add_theme_stylebox_override("normal", UiThemeScript.plate(UiThemeScript.CREAM, 28, 2, true, 22))
	prompt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return prompt

## Names the Continue inputs the room has (#639): `kinds` from
## `ControllerServer.continue_inputs()`. Phones alone (or nobody) keep the
## original line.
func set_continue_inputs(kinds: PackedStringArray) -> void:
	if _continue_prompt_label != null:
		_continue_prompt_label.text = continue_prompt_text(kinds)

## The prompt for `kinds` ("pc", "pad", "phone"): "Tap Continue on your phone"
## for phones alone, otherwise "Continue with Space, A on a gamepad or a tap on
## your phone" naming only the kinds present.
func continue_prompt_text(kinds: PackedStringArray) -> String:
	if kinds.is_empty() or (kinds.size() == 1 and kinds[0] == "phone"):
		return _screen.tr("VICTORY_TAP_CONTINUE")
	var names: PackedStringArray = PackedStringArray()
	for kind: String in kinds:
		match kind:
			"pc":
				names.append(_screen.tr("VICTORY_INPUT_SPACE"))
			"pad":
				names.append(_screen.tr("VICTORY_INPUT_PAD"))
			"phone":
				names.append(_screen.tr("VICTORY_INPUT_PHONE"))
	var list: String = names[0]
	for i in range(1, names.size()):
		list = _screen.tr("VICTORY_LIST_LAST") % [list, names[i]] if i == names.size() - 1 else "%s, %s" % [list, names[i]]
	return _screen.tr("VICTORY_CONTINUE_WITH") % list

## The demo build's end card (#361): logo over the thank-you and wishlist line.
func _build_end_card() -> void:
	_end_card_panel = ScreenKitScript.full_screen_panel(_screen, "EndCardPanel")
	(_end_card_panel as ColorRect).color = UiThemeScript.INDIGO
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 40)
	_end_card_panel.add_child(box)
	var logo: TextureRect = ScreenKitScript.logo_rect("Logo", ScreenKitScript.LOGO_LOBBY_SIZE)
	logo.custom_minimum_size = ScreenKitScript.LOGO_LOBBY_SIZE
	box.add_child(logo)
	var text: Label = ScreenKitScript.ink_label(DemoBuildScript.end_card_text(), 64, UiThemeScript.YELLOW, 12)
	text.name = "EndCardText"
	box.add_child(text)

## The podium: `slots` already in podium order (the match winner first, then
## by final score), each with its score from `scores`, then `awards` under it.
##
## Issue #236: a Teams match passes `winner_team`, each slot's team in `teams`
## and the team points in `team_scores`: the title names the winning team,
## and each column shows its player's team in place of a personal score.
func refresh(slots: Array[int], scores: PackedInt32Array, winner_slot: int, awards: Array[Dictionary],
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
		var name_label: Label = ScreenKitScript.ink_label("%s\n%d" % [_slot_name.call(slot), scores[slot]], 24 if crowded else 36, UiThemeScript.CREAM)
		if not teams.is_empty():
			var team: int = int(teams.get(slot, TeamsScript.NONE))
			name_label.text = "%s\n%s" % [_slot_name.call(slot), TeamsScript.team_name(team)]
			name_label.add_theme_color_override("font_color", TeamsScript.team_color(team))
		if crowded:
			# A fixed column that a long name wraps inside rather than widens.
			name_label.custom_minimum_size.x = PODIUM_CROWDED_COLUMN_PX
			name_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		column.add_child(name_label)
		var block := Panel.new()
		block.add_theme_stylebox_override("panel", _podium_block_style(_slot_color.call(slot)))
		var cap := ColorRect.new()
		cap.color = Color(1.0, 1.0, 1.0, 0.3)
		cap.set_anchors_preset(Control.PRESET_TOP_WIDE)
		cap.offset_left = 5.0
		cap.offset_right = -5.0
		cap.offset_top = 5.0
		cap.offset_bottom = 21.0
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(cap)
		block.custom_minimum_size = Vector2(120 if crowded else 160, PODIUM_TALLEST_PX * (0.55 if not stat_rows.is_empty() else 1.0) * PODIUM_HEIGHTS[mini(place, PODIUM_HEIGHTS.size() - 1)])
		column.add_child(block)
		column.add_child(ScreenKitScript.ink_label(str(place + 1), 28, UiThemeScript.CREAM))
		_podium.add_child(column)
	if winner_team != -1:
		_victory_title.text = _screen.tr("VICTORY_TEAM_WINS") % TeamsScript.team_name(winner_team)
		_victory_title.add_theme_color_override("font_color", TeamsScript.team_color(winner_team))
	elif winner_slot != -1:
		_victory_title.text = _screen.tr("VICTORY_WINS") % _slot_name.call(winner_slot)
		_victory_title.add_theme_color_override("font_color", _slot_color.call(winner_slot))
	else:
		_victory_title.text = _screen.tr("VICTORY_MATCH_OVER")
	_refresh_awards(awards)
	_refresh_stat_table(stat_rows)

## A podium block in the theme style: the player's colour, a thick ink outline,
## rounded corners and a hard offset shadow.
func _podium_block_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(UiThemeScript.OUTLINE_WIDTH + 2)
	style.border_color = PODIUM_INK
	style.set_corner_radius_all(UiThemeScript.CORNER_RADIUS)
	style.shadow_color = PODIUM_INK
	style.shadow_size = 0
	style.shadow_offset = Vector2(6, 6)
	return style

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
