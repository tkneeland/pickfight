extends RefCounted
## The Stages & Rules screen (#647), a lobby popup on the host PC: per game
## mode, which stages are in the draw, which round modifiers (and night
## stages) may roll, and which pickup weapons spawn. It replaces the stage,
## weapon and Rules lists the Settings panel used to carry (#294, #378).
##
## Built into the card `LobbyPopups` gives it. Mode tabs along the top; per
## tab a Smash-style grid of that mode's stage tiles (preview image and name,
## yellow when on, dimmed when off) with a big preview of the hovered or
## focused one beside it; All on / All off; the mode's modifier switches and
## the global weapon switches. The footer says what a round draws from.
## All of it writes straight to `HostSettings` (per mode, saved at once).
##
## Host only: the lobby never opens it without host controls attached.
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const GameModesScript := preload("res://scripts/GameModes.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")
const RoundModifiersScript := preload("res://scripts/RoundModifiers.gd")
const StagePreviewsScript := preload("res://scripts/StagePreviews.gd")
const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")

## Night stages are a per-mode switch beside the round modifiers (#647).
const NIGHT_ID: String = "night"
const NIGHT_TITLE: String = "Night stages"
const CARD_WIDTH_PX: float = 1500.0
const CARD_HEIGHT_PX: float = 800.0
const TILE_SIZE: Vector2 = Vector2(152, 122)
const TILE_ICON_PX: int = 136
const TILE_COLUMNS: int = 6
const RIGHT_COLUMN_PX: float = 440.0
const PREVIEW_SIZE: Vector2 = Vector2(360, 203)
## Every text on the screen is at least this many design px (#368).
const TEXT_PX: int = 18
const DIM: Color = Color(1, 1, 1, 0.5)

var _screen # the LobbyScreen
var _tab_id: String = GameModesScript.CLASSIC
var _tab_ids: Array[String] = []
var _tabs: Dictionary = {}
var _tiles: Dictionary = {}
var _textures: Dictionary = {}
var _mod_buttons: Dictionary = {}
var _weapon_buttons: Dictionary = {}
var _built: bool = false
var _card: Control
var _grid: GridContainer
var _preview_rect: TextureRect
var _preview_name: Label
var _footer: Label
var _modifier_note: Label
var _mods_box: GridContainer
var _weapons_box: GridContainer
var _done: Button
var _all_on: Button
var _all_off: Button
var _first_tab: Button

func _init(screen) -> void:
	_screen = screen

static func settings() -> RefCounted:
	return HostSettingsScript.shared()

## "Battlefield", "SkyBridge" -> "Battlefield", "Sky Bridge".
static func pretty_name(stage_name: String) -> String:
	var out: String = ""
	for i in stage_name.length():
		var ch: String = stage_name[i]
		if i > 0 and ch != ch.to_lower() and stage_name[i - 1] == stage_name[i - 1].to_lower() and stage_name[i - 1] != " ":
			out += " "
		out += ch
	return out

## The tab ids in order: Classic, then every mode the lobby offers.
static func mode_ids() -> Array[String]:
	var out: Array[String] = [GameModesScript.CLASSIC]
	for row: Dictionary in GameModesScript.picker_rows():
		if not out.has(str(row["id"])): # the picker lists Classic itself
			out.append(str(row["id"]))
	return out

## How many of `mode_id`'s stages are switched on (can be zero).
static func stages_on(mode_id: String) -> int:
	var host: RefCounted = settings()
	var count: int = 0
	for stage_name: String in host.stages_for_mode(mode_id):
		if host.is_stage_enabled_for(mode_id, stage_name):
			count += 1
	return count

static func modifier_ids() -> PackedStringArray:
	var ids := PackedStringArray(RoundModifiersScript.IDS)
	ids.append(NIGHT_ID)
	return ids

static func modifier_title(id: String) -> String:
	return NIGHT_TITLE if id == NIGHT_ID else RoundModifiersScript.title_of(id)

static func _count(count: int, noun: String) -> String:
	return "%d %s%s" % [count, noun, "" if count == 1 else "s"]

## "39 stages" for the lobby's status line.
static func stage_count_text(mode_id: String) -> String:
	return _count(stages_on(mode_id), "stage")

## The one-line summary under the lobby's mode cards: "39 stages on · modifiers on".
static func summary(mode_id: String) -> String:
	var host: RefCounted = settings()
	var open: int = 0
	var on: int = 0
	for id: String in modifier_ids():
		if GameModesScript.bans_modifier(mode_id, id):
			continue
		open += 1
		if host.is_modifier_enabled(mode_id, id):
			on += 1
	var mods: String = "modifiers off"
	if open > 0 and on == open:
		mods = "modifiers on"
	elif on > 0:
		mods = "%d of %d modifiers on" % [on, open]
	return "%s on · %s" % [stage_count_text(mode_id), mods]

# --- Building ------------------------------------------------------------------

## Builds the screen into `card` (a PanelContainer) the first time it opens.
func build(card: Control) -> void:
	_card = card
	card.custom_minimum_size.y = CARD_HEIGHT_PX
	var box := VBoxContainer.new()
	box.name = "StagesRules"
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.name = "Head"
	box.add_child(head)
	var title: Label = ScreenKitScript.themed_label("Stages & Rules", 40, UiThemeScript.INK_HEADING_LABEL)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_done = _button("Done", UiThemeScript.YELLOW_BUTTON, 26)
	_done.name = "Done"
	_done.custom_minimum_size = Vector2(150, 52)
	head.add_child(_done)
	var frame := PanelContainer.new()
	frame.name = "Tabs"
	frame.theme_type_variation = UiThemeScript.SWITCH_FRAME
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(frame)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 0)
	frame.add_child(cells)
	_tab_ids = mode_ids()
	for i in _tab_ids.size():
		var id: String = _tab_ids[i]
		if i > 0:
			var rule := ColorRect.new()
			rule.color = UiThemeScript.INK
			rule.custom_minimum_size = Vector2(4, 0)
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cells.add_child(rule)
		var tab: Button = _button(GameModesScript.display_name(id), UiThemeScript.SEG_BUTTON, 22)
		tab.name = "Tab_" + (id if id != "" else "classic")
		tab.pressed.connect(select_tab.bind(id))
		cells.add_child(tab)
		_tabs[id] = tab
	_first_tab = _tabs[_tab_ids[0]]
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	box.add_child(body)
	body.add_child(_build_grid_column())
	body.add_child(_build_side_column())
	_footer = ScreenKitScript.themed_label("", 24, UiThemeScript.INK_HEADING_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_footer.name = "Footer"
	box.add_child(_footer)
	_done.pressed.connect(func() -> void: _screen.request_close_popup())
	_built = true

func _build_grid_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "StageColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	var label: Label = ScreenKitScript.themed_label("Stages", 26, UiThemeScript.INK_HEADING_LABEL)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_all_on = _button("All on", UiThemeScript.SKY_BUTTON, 20)
	_all_on.name = "AllOn"
	_all_on.pressed.connect(_set_all.bind(true))
	row.add_child(_all_on)
	_all_off = _button("All off", UiThemeScript.PINK_BUTTON, 20)
	_all_off.name = "AllOff"
	_all_off.pressed.connect(_set_all.bind(false))
	row.add_child(_all_off)
	var scroll := ScrollContainer.new()
	scroll.name = "StageScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "Stages"
	_grid.columns = TILE_COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)
	return column

func _build_side_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "SideColumn"
	column.custom_minimum_size.x = RIGHT_COLUMN_PX
	column.add_theme_constant_override("separation", 8)
	var shot := PanelContainer.new()
	shot.name = "PreviewPanel"
	shot.theme_type_variation = UiThemeScript.RULE_BOX
	column.add_child(shot)
	var shot_box := VBoxContainer.new()
	shot_box.add_theme_constant_override("separation", 4)
	shot.add_child(shot_box)
	_preview_rect = TextureRect.new()
	_preview_rect.name = "Preview"
	_preview_rect.custom_minimum_size = PREVIEW_SIZE
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot_box.add_child(_preview_rect)
	_preview_name = ScreenKitScript.themed_label("", 28, UiThemeScript.INK_HEADING_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_preview_name.name = "PreviewName"
	shot_box.add_child(_preview_name)
	var scroll := ScrollContainer.new()
	scroll.name = "RulesScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var rules := VBoxContainer.new()
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules.add_theme_constant_override("separation", 6)
	scroll.add_child(rules)
	rules.add_child(ScreenKitScript.themed_label("Round modifiers", 24, UiThemeScript.INK_HEADING_LABEL))
	_modifier_note = ScreenKitScript.themed_label("", TEXT_PX, UiThemeScript.INK_BOLD_LABEL)
	_modifier_note.name = "ModifierNote"
	_modifier_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_child(_modifier_note)
	_mods_box = _switch_grid("Modifiers")
	rules.add_child(_mods_box)
	for id: String in modifier_ids():
		var button: Button = _switch(modifier_title(id), id)
		button.pressed.connect(_on_modifier.bind(id))
		_mods_box.add_child(button)
		_mod_buttons[id] = button
	rules.add_child(ScreenKitScript.themed_label("Weapons (every mode)", 24, UiThemeScript.INK_HEADING_LABEL))
	_weapons_box = _switch_grid("Weapons")
	rules.add_child(_weapons_box)
	for weapon_name: String in HostSettingsScript.known_weapons():
		var button: Button = _switch(weapon_name.capitalize(), weapon_name)
		button.pressed.connect(_on_weapon.bind(weapon_name))
		_weapons_box.add_child(button)
		_weapon_buttons[weapon_name] = button
	return column

func _switch_grid(node_name: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = node_name
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	return grid

## A toggle for a modifier or weapon: cream when off, yellow when on.
func _switch(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.toggle_mode = true
	button.clip_text = true
	button.theme_type_variation = UiThemeScript.PICK_BUTTON
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", TEXT_PX)
	return button

func _button(text: String, variation: StringName, font_size: int) -> Button:
	var button: Button = ScreenKitScript.themed_button(text, variation)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", font_size)
	return button

# --- Opening, tabs, tiles ----------------------------------------------------------

## Called by the popup when it opens: the tab follows the lobby's picked mode
## (a mode with no tab, such as retired Hot Potato, opens on Classic).
func on_open(mode_id: String) -> void:
	_tab_id = "\u0001" # force a rebuild
	select_tab(mode_id if _tabs.has(mode_id) else GameModesScript.CLASSIC)

func is_built() -> bool:
	return _built

func current_tab() -> String:
	return _tab_id

func tab_ids() -> Array[String]:
	return _tab_ids

func tab_button(id: String) -> Button:
	return _tabs.get(id) as Button

func select_tab(id: String) -> void:
	if not _tabs.has(id) or id == _tab_id:
		return
	_tab_id = id
	for tab_id: String in _tabs:
		(_tabs[tab_id] as Button).theme_type_variation = UiThemeScript.SEG_BUTTON_ON if tab_id == id else UiThemeScript.SEG_BUTTON
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_tiles.clear()
	for stage_name: String in settings().stages_for_mode(id):
		var tile: Button = _make_tile(stage_name)
		_grid.add_child(tile)
		_tiles[stage_name] = tile
	var names: PackedStringArray = settings().stages_for_mode(id)
	_show_stage(names[0] if not names.is_empty() else "")
	_sync()

func _make_tile(stage_name: String) -> Button:
	var tile := Button.new()
	tile.name = stage_name
	tile.text = pretty_name(stage_name)
	tile.toggle_mode = true
	tile.clip_text = true
	tile.theme_type_variation = UiThemeScript.PICK_BUTTON
	tile.focus_mode = Control.FOCUS_ALL
	tile.custom_minimum_size = TILE_SIZE
	tile.icon = _texture(stage_name)
	tile.expand_icon = true
	tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	tile.add_theme_font_size_override("font_size", TEXT_PX - 2)
	tile.add_theme_constant_override("icon_max_width", TILE_ICON_PX)
	tile.add_theme_constant_override("h_separation", 0)
	tile.pressed.connect(_on_tile.bind(stage_name))
	tile.mouse_entered.connect(_show_stage.bind(stage_name))
	tile.focus_entered.connect(_show_stage.bind(stage_name))
	return tile

func _texture(stage_name: String) -> Texture2D:
	if not _textures.has(stage_name):
		_textures[stage_name] = StagePreviewsScript.load_preview(stage_name)
	return _textures[stage_name] as Texture2D

func _show_stage(stage_name: String) -> void:
	_preview_name.text = pretty_name(stage_name)
	_preview_rect.texture = _texture(stage_name) if stage_name != "" else null

## The stage tile for `stage_name` on the current tab, or null.
func tile(stage_name: String) -> Button:
	return _tiles.get(stage_name) as Button

func tile_names() -> PackedStringArray:
	return PackedStringArray(_tiles.keys())

func modifier_button(id: String) -> Button:
	return _mod_buttons.get(id) as Button

func weapon_button(weapon_name: String) -> Button:
	return _weapon_buttons.get(weapon_name) as Button

func done_button() -> Button:
	return _done

func all_on_button() -> Button:
	return _all_on

func all_off_button() -> Button:
	return _all_off

func footer_text() -> String:
	return _footer.text if _footer != null else ""

func preview_name() -> String:
	return _preview_name.text if _preview_name != null else ""

## The control a gamepad should start on: the first stage tile, else Done.
func focus_target() -> Control:
	for stage_name: String in _tiles:
		return _tiles[stage_name]
	return _done

func _on_tile(stage_name: String) -> void:
	settings().set_stage_enabled_for(_tab_id, stage_name, (_tiles[stage_name] as Button).button_pressed)
	_sync()

func _set_all(on: bool) -> void:
	settings().set_all_stages_for(_tab_id, on)
	_sync()

func _on_modifier(id: String) -> void:
	settings().set_modifier_enabled(_tab_id, id, (_mod_buttons[id] as Button).button_pressed)
	_sync()

func _on_weapon(weapon_name: String) -> void:
	settings().set_weapon_enabled(weapon_name, (_weapon_buttons[weapon_name] as Button).button_pressed)
	_sync()

## LB and RB step through the tabs on a gamepad. True when the event was used.
func handle_pad(event: InputEvent) -> bool:
	var pad := event as InputEventJoypadButton
	if pad == null or not pad.pressed:
		return false
	var step: int = 0
	if pad.button_index == JOY_BUTTON_LEFT_SHOULDER:
		step = -1
	elif pad.button_index == JOY_BUTTON_RIGHT_SHOULDER:
		step = 1
	if step == 0:
		return false
	select_tab(_tab_ids[posmod(_tab_ids.find(_tab_id) + step, _tab_ids.size())])
	return true

# --- Showing the settings ------------------------------------------------------------

## The tabs that have stages to choose from but none switched on.
func empty_tabs() -> Array[String]:
	var out: Array[String] = []
	for id: String in _tab_ids:
		if not settings().stages_for_mode(id).is_empty() and stages_on(id) == 0:
			out.append(id)
	return out

## Whether Done, Esc and B may close the screen: every mode has a stage on.
func can_close() -> bool:
	return empty_tabs().is_empty()

## Redraws every switch from the settings and the footer line.
func _sync() -> void:
	var host: RefCounted = settings()
	for stage_name: String in _tiles:
		var tile_button: Button = _tiles[stage_name]
		var on: bool = host.is_stage_enabled_for(_tab_id, stage_name)
		tile_button.set_pressed_no_signal(on)
		tile_button.modulate = Color.WHITE if on else DIM
	var locked: bool = true
	for id: String in modifier_ids():
		var button: Button = _mod_buttons[id]
		var banned: bool = GameModesScript.bans_modifier(_tab_id, id)
		locked = locked and banned
		button.set_pressed_no_signal(host.is_modifier_enabled(_tab_id, id))
		button.disabled = banned
		button.modulate = DIM if banned or not button.button_pressed else Color.WHITE
		button.tooltip_text = "Not allowed in %s" % GameModesScript.display_name(_tab_id) if banned else ""
	_modifier_note.visible = locked
	_modifier_note.text = "%s plays without modifiers." % GameModesScript.display_name(_tab_id) if locked else ""
	for weapon_name: String in _weapon_buttons:
		var weapon: Button = _weapon_buttons[weapon_name]
		weapon.set_pressed_no_signal(host.is_weapon_enabled(weapon_name))
		weapon.modulate = Color.WHITE if weapon.button_pressed else DIM
	_footer.text = _footer_line()
	_done.disabled = not can_close()
	_screen.refresh_stage_summary()

func _footer_line() -> String:
	var empty: Array[String] = empty_tabs()
	if not empty.is_empty():
		if empty.has(_tab_id):
			return "Switch on at least one stage"
		return "Switch on at least one stage in %s" % GameModesScript.display_name(empty[0])
	var pool: PackedStringArray = settings().stages_for_mode(_tab_id)
	var on_names := PackedStringArray()
	for stage_name: String in pool:
		if settings().is_stage_enabled_for(_tab_id, stage_name):
			on_names.append(stage_name)
	if _tab_id == GameModesScript.STOCK:
		if on_names.size() == 1:
			return "Stock plays on %s" % pretty_name(on_names[0])
		return "Stock picks one at random from %d stages" % on_names.size()
	return "Each round draws from %d of %d stages" % [on_names.size(), pool.size()]
