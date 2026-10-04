extends RefCounted
## The shared UI look (#541, child of the #507 overhaul): cream panels, ink
## outlines, hard offset shadows, Lilita One headings and Nunito body text.
##
## The project's custom theme is the saved resource at THEME_PATH, which
## `tools/build_ui_theme.gd` writes from build(). Edit build() and re-run that
## tool; do not hand-edit the .tres. Load this script with preload() by path,
## never by class_name.

const THEME_PATH: String = "res://art/ui/pickfight_theme.tres"
const HEADING_FONT_PATH: String = "res://art/fonts/LilitaOne-Regular.ttf"
const BODY_FONT_PATH: String = "res://art/fonts/Nunito-Variable.ttf"

## The smallest text the UI uses, in design px (#368: 16 design px is 12.8 px
## on the Steam Deck). The theme's default size, so nothing inherits less.
const MIN_FONT_SIZE: int = 16

# Palette (#507 decision 1).
const CREAM: Color = Color("FBF6EA")
const INK: Color = Color("14181D")
const INDIGO: Color = Color("232A4A")
## A step lighter than the ground, for dark panels that hold light text.
const INDIGO_PANEL: Color = Color("2F3760")
## Okabe-Ito accents, the same set as the player palette.
const ORANGE: Color = Color("E69F00")
const SKY: Color = Color("56B4E9")
const GREEN: Color = Color("009E73")
const YELLOW: Color = Color("F5E24A")
const PINK: Color = Color("CC79A7")
const VERMILION: Color = Color("D55E00")
const BLUE: Color = Color("3D8FD1")
const ACCENTS: Array[Color] = [ORANGE, SKY, GREEN, YELLOW, PINK, VERMILION, BLUE]

const OUTLINE_WIDTH: int = 3
const SHADOW_OFFSET: Vector2 = Vector2(0, 4)
const CORNER_RADIUS: int = 10

## Theme type variations (use with `theme_type_variation`).
const HEADING_LABEL: StringName = &"HeadingLabel" # Lilita One, light text
const INK_LABEL: StringName = &"InkLabel" # Nunito, ink text, for cream panels
const CREAM_PANEL: StringName = &"CreamPanel" # cream fill; pair with InkLabel
const INK_HEADING_LABEL: StringName = &"InkHeadingLabel" # Lilita One, ink text, for cream panels
## Title screen (#546): the three match-kind cards, a key badge, and its text.
const TITLE_CARD_ORANGE: StringName = &"TitleCardOrange"
const TITLE_CARD_SKY: StringName = &"TitleCardSky"
const TITLE_CARD_GREEN: StringName = &"TitleCardGreen"
const KEY_BADGE: StringName = &"KeyBadge" # a small cream key cap
const KEY_BADGE_LABEL: StringName = &"KeyBadgeLabel" # Lilita One 26, ink
const CARD_NAME_LABEL: StringName = &"CardNameLabel" # Lilita One 56, ink
const CARD_DESC_LABEL: StringName = &"CardDescLabel" # Nunito ExtraBold 24, ink
const TITLE_HEADING_LABEL: StringName = &"TitleHeadingLabel" # Lilita One 40, cream
const MUTED_HINT_LABEL: StringName = &"MutedHintLabel" # Nunito ExtraBold 20, muted
const MUTED: Color = Color("C9CCE0")


static func _box(fill: Color, shadow: bool = true, shadow_offset: Vector2 = SHADOW_OFFSET) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_border_width_all(OUTLINE_WIDTH)
	box.border_color = INK
	box.set_corner_radius_all(CORNER_RADIUS)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	if shadow:
		box.shadow_color = INK
		box.shadow_size = 0 # a hard shadow: offset only, no blur
		box.shadow_offset = shadow_offset
	return box


## A big chunky card (#546): thick outline, large radius, hard offset shadow.
static func _card_box(fill: Color, shadow_offset: Vector2, border: Color = INK) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_border_width_all(5)
	box.border_color = border
	box.set_corner_radius_all(22)
	box.content_margin_left = 32
	box.content_margin_right = 32
	box.content_margin_top = 28
	box.content_margin_bottom = 28
	box.shadow_color = INK
	box.shadow_size = 1 # 0 draws no shadow at all; 1 is the smallest, still hard
	box.shadow_offset = shadow_offset
	return box


static func _card_variation(theme: Theme, variation: StringName, fill: Color) -> void:
	theme.set_type_variation(variation, "Button")
	theme.set_stylebox("normal", variation, _card_box(fill, Vector2(7, 7)))
	theme.set_stylebox("hover", variation, _card_box(fill, Vector2(10, 12)))
	theme.set_stylebox("focus", variation, _card_box(fill, Vector2(10, 12), CREAM))
	theme.set_stylebox("pressed", variation, _card_box(fill, Vector2(2, 2)))
	theme.set_stylebox("disabled", variation, _card_box(fill, Vector2(7, 7)))


## Builds the theme in memory. tools/build_ui_theme.gd saves it to THEME_PATH.
static func build() -> Theme:
	var theme := Theme.new()
	var body: Font = load(BODY_FONT_PATH)
	var heading: Font = load(HEADING_FONT_PATH)
	theme.default_font = body
	theme.default_font_size = MIN_FONT_SIZE

	# Label: light text on the indigo ground by default, so the existing screens
	# (white text on dark) stay legible. Ink text is the InkLabel variation.
	theme.set_color("font_color", "Label", CREAM)
	theme.set_type_variation(HEADING_LABEL, "Label")
	theme.set_font("font", HEADING_LABEL, heading)
	theme.set_color("font_color", HEADING_LABEL, CREAM)
	theme.set_type_variation(INK_LABEL, "Label")
	theme.set_color("font_color", INK_LABEL, INK)
	theme.set_type_variation(INK_HEADING_LABEL, "Label")
	theme.set_font("font", INK_HEADING_LABEL, heading)
	theme.set_color("font_color", INK_HEADING_LABEL, INK)

	# Panels: bare Panel/PanelContainer are indigo with an ink outline (existing
	# screens put light text on them); CreamPanel is the cream one.
	var dark := _box(INDIGO_PANEL)
	theme.set_stylebox("panel", "Panel", dark)
	theme.set_stylebox("panel", "PanelContainer", dark)
	theme.set_type_variation(CREAM_PANEL, "PanelContainer")
	theme.set_stylebox("panel", CREAM_PANEL, _box(CREAM))

	# Buttons: cream with ink text. Hover and focus "pop" (lift and a longer
	# shadow); pressed sinks onto its shadow.
	var normal := _box(CREAM)
	var hover := _box(Color("FFFFFF"), true, Vector2(0, 6))
	var focus := _box(Color("FFFFFF"), true, Vector2(0, 6))
	focus.border_color = YELLOW
	var pressed := _box(Color("E8DFC8"), true, Vector2(0, 1))
	var disabled := _box(Color("B9B3A3"), false)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color("5A5E66"))

	# LineEdit: cream field, ink text.
	var field := _box(CREAM, false)
	var field_focus := _box(Color("FFFFFF"), false)
	field_focus.border_color = YELLOW
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_stylebox("read_only", "LineEdit", _box(Color("E8DFC8"), false))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_selected_color", "LineEdit", INK)
	theme.set_color("font_uneditable_color", "LineEdit", Color("5A5E66"))
	theme.set_color("caret_color", "LineEdit", INK)
	theme.set_color("selection_color", "LineEdit", Color(SKY, 0.6))
	theme.set_color("font_placeholder_color", "LineEdit", Color("5A5E66"))
	_add_lobby_variations(theme)

	# Title screen (#546).
	_card_variation(theme, TITLE_CARD_ORANGE, ORANGE)
	_card_variation(theme, TITLE_CARD_SKY, SKY)
	_card_variation(theme, TITLE_CARD_GREEN, GREEN)
	var extra_bold := FontVariation.new()
	extra_bold.base_font = body
	extra_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 800}
	theme.set_type_variation(KEY_BADGE, "PanelContainer")
	var badge := _box(CREAM, false)
	badge.set_border_width_all(4)
	badge.set_corner_radius_all(12)
	theme.set_stylebox("panel", KEY_BADGE, badge)
	theme.set_type_variation(KEY_BADGE_LABEL, "Label")
	theme.set_font("font", KEY_BADGE_LABEL, heading)
	theme.set_color("font_color", KEY_BADGE_LABEL, INK)
	theme.set_font_size("font_size", KEY_BADGE_LABEL, 26)
	theme.set_type_variation(CARD_NAME_LABEL, "Label")
	theme.set_font("font", CARD_NAME_LABEL, heading)
	theme.set_color("font_color", CARD_NAME_LABEL, INK)
	theme.set_font_size("font_size", CARD_NAME_LABEL, 56)
	theme.set_type_variation(CARD_DESC_LABEL, "Label")
	theme.set_color("font_color", CARD_DESC_LABEL, INK)
	theme.set_font("font", CARD_DESC_LABEL, extra_bold)
	theme.set_font_size("font_size", CARD_DESC_LABEL, 24)
	theme.set_type_variation(TITLE_HEADING_LABEL, "Label")
	theme.set_font("font", TITLE_HEADING_LABEL, heading)
	theme.set_color("font_color", TITLE_HEADING_LABEL, CREAM)
	theme.set_font_size("font_size", TITLE_HEADING_LABEL, 40)
	theme.set_type_variation(MUTED_HINT_LABEL, "Label")
	theme.set_font("font", MUTED_HINT_LABEL, extra_bold)
	theme.set_font_size("font_size", MUTED_HINT_LABEL, 20)
	theme.set_color("font_color", MUTED_HINT_LABEL, MUTED)
	return theme


# --- Lobby variations (#547) ----------------------------------------------------
# Chunky cream cards and buttons for the lobby, its popups and the Host panel.
# Colours that change per player (a card's strip, a swatch) are set in code.

const CARD_PANEL: StringName = &"CardPanel" # cream card: thick outline, big hard shadow
const DIALOG_CARD: StringName = &"DialogCard" # the same, bigger, for popups
const SWITCH_FRAME: StringName = &"SwitchFrame" # the frame round the Couch / Online / Solo cells
const DEMO_STAGE_FRAME: StringName = &"DemoStageFrame" # the ink frame round a How to play demo's stage
const PREVIEW_STAGE: StringName = &"PreviewStage" # the dark stage a live character preview stands on
const DEMO_CARD_COLORS: Array[Color] = [ORANGE, SKY, GREEN, PINK] # the four How to play cards
const RULE_BOX: StringName = &"RuleBox" # the yellow strip under the How to play demos
const PICK_ROW: StringName = &"PickRow" # a pad picker row on a player card
const PICK_ROW_ON: StringName = &"PickRowOn" # the row the cursor is on
const SEG_BUTTON: StringName = &"SegButton" # one cell of the Couch / Online / Solo switch
const SEG_BUTTON_ON: StringName = &"SegButtonOn"
const SWITCH_BUTTON: StringName = &"SwitchButton" # Teams Off / On
const SWITCH_BUTTON_ON: StringName = &"SwitchButtonOn"
const STEP_BUTTON: StringName = &"StepButton" # the - and + of a stepper
const VALUE_BUTTON: StringName = &"ValueButton" # a stepper's number, flat
const ACTION_BUTTON: StringName = &"ActionButton" # a big cream button
const SKY_BUTTON: StringName = &"SkyButton"
const PINK_BUTTON: StringName = &"PinkButton"
const YELLOW_BUTTON: StringName = &"YellowButton" # Done, close, a primary pick
const START_BUTTON: StringName = &"StartButton"
const START_BUTTON_OFF: StringName = &"StartButtonOff"
const PICK_BUTTON: StringName = &"PickButton" # a toggle in a picker grid: yellow when picked
const PILL_ON: StringName = &"PillOn" # READY
const PILL_OFF: StringName = &"PillOff" # not ready
const PILL_BOT: StringName = &"PillBot"
const MODE_CARD: StringName = &"ModeCard" # a game mode card (a panel)
const MODE_CARD_ON: StringName = &"ModeCardOn"
const BOLD_LABEL: StringName = &"BoldLabel" # Nunito 800, light text, for the ground
const INK_BOLD_LABEL: StringName = &"InkBoldLabel" # Nunito 800, ink text, for cream panels
const MUTED_LABEL: StringName = &"MutedLabel" # light grey-blue body text on the ground
const HINT_LABEL: StringName = &"HintLabel" # muted ink text on cream

const MUTED_INK: Color = Color("5A628C")
const DASH: Color = Color("5A628C")
const STRIP_GREY: Color = Color("9CA0B8")


## A cream-style box with `radius`, `border` and a hard shadow `shadow` px down-right.
static func box(fill: Color, radius: int, border: int, shadow: Vector2 = Vector2.ZERO, margin: Vector4 = Vector4(10, 4, 10, 4)) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.set_border_width_all(border)
	b.border_color = INK
	b.set_corner_radius_all(radius)
	b.content_margin_left = margin.x
	b.content_margin_top = margin.y
	b.content_margin_right = margin.z
	b.content_margin_bottom = margin.w
	if shadow != Vector2.ZERO:
		b.shadow_color = INK
		b.shadow_size = 0
		b.shadow_offset = shadow
	return b


## Sets a button variation: `normal`, with hover / focus lifting its shadow, pressed sinking.
static func _button_variation(theme: Theme, variation: StringName, font: Font, font_size: int, fill: Color, radius: int, border: int,
		shadow: Vector2, margin: Vector4, hover_fill: Color = Color.TRANSPARENT) -> void:
	theme.set_type_variation(variation, "Button")
	var hover_color: Color = hover_fill if hover_fill.a > 0.0 else fill.lightened(0.25)
	var lift: Vector2 = shadow + Vector2(0, 3) if shadow != Vector2.ZERO else Vector2.ZERO
	var normal := box(fill, radius, border, shadow, margin)
	var hover := box(hover_color, radius, border, lift, margin)
	var focus := box(hover_color, radius, border, lift, margin)
	focus.border_color = YELLOW if fill != YELLOW else CREAM
	var pressed := box(fill.darkened(0.1), radius, border, Vector2(shadow.x * 0.25, 1) if shadow != Vector2.ZERO else Vector2.ZERO, margin)
	var disabled := box(Color("B9B3A3"), radius, border, Vector2.ZERO, margin)
	theme.set_stylebox("normal", variation, normal)
	theme.set_stylebox("hover", variation, hover)
	theme.set_stylebox("focus", variation, focus)
	theme.set_stylebox("pressed", variation, pressed)
	theme.set_stylebox("hover_pressed", variation, pressed)
	theme.set_stylebox("disabled", variation, disabled)
	theme.set_font("font", variation, font)
	theme.set_font_size("font_size", variation, font_size)
	for color_name: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(color_name, variation, INK)
	theme.set_color("font_disabled_color", variation, Color("5A5E66"))


static func _add_lobby_variations(theme: Theme) -> void:
	var heading: Font = load(HEADING_FONT_PATH)
	var body: Font = load(BODY_FONT_PATH)
	# Panels.
	theme.set_type_variation(CARD_PANEL, "PanelContainer")
	theme.set_stylebox("panel", CARD_PANEL, box(CREAM, 20, 5, Vector2(6, 6), Vector4(16, 14, 16, 14)))
	theme.set_type_variation(DIALOG_CARD, "PanelContainer")
	theme.set_stylebox("panel", DIALOG_CARD, box(CREAM, 26, 6, Vector2(10, 10), Vector4(40, 26, 40, 26)))
	theme.set_type_variation(SWITCH_FRAME, "PanelContainer")
	theme.set_stylebox("panel", SWITCH_FRAME, box(CREAM, 14, 4, Vector2(4, 4), Vector4(4, 4, 4, 4)))
	theme.set_type_variation(DEMO_STAGE_FRAME, "PanelContainer")
	theme.set_stylebox("panel", DEMO_STAGE_FRAME, box(Color("212642"), 12, 4, Vector2.ZERO, Vector4(4, 4, 4, 4)))
	theme.set_type_variation(PREVIEW_STAGE, "PanelContainer")
	theme.set_stylebox("panel", PREVIEW_STAGE, box(INDIGO, 20, 5, Vector2.ZERO, Vector4(8, 8, 8, 8)))
	for i in DEMO_CARD_COLORS.size():
		theme.set_type_variation(StringName("DemoCard%d" % i), "PanelContainer")
		theme.set_stylebox("panel", StringName("DemoCard%d" % i), box(DEMO_CARD_COLORS[i], 18, 4, Vector2.ZERO, Vector4(12, 12, 12, 12)))
	theme.set_type_variation(RULE_BOX, "PanelContainer")
	theme.set_stylebox("panel", RULE_BOX, box(YELLOW, 14, 4, Vector2.ZERO, Vector4(18, 12, 18, 12)))
	theme.set_type_variation(PICK_ROW, "PanelContainer")
	theme.set_stylebox("panel", PICK_ROW, box(CREAM, 10, 3, Vector2.ZERO, Vector4(2, 0, 2, 0)))
	theme.set_type_variation(PICK_ROW_ON, "PanelContainer")
	theme.set_stylebox("panel", PICK_ROW_ON, box(YELLOW, 10, 3, Vector2.ZERO, Vector4(2, 0, 2, 0)))
	theme.set_type_variation(MODE_CARD, "PanelContainer")
	theme.set_stylebox("panel", MODE_CARD, box(CREAM, 14, 4, Vector2(3, 3), Vector4(10, 6, 10, 6)))
	theme.set_type_variation(MODE_CARD_ON, "PanelContainer")
	theme.set_stylebox("panel", MODE_CARD_ON, box(YELLOW, 14, 4, Vector2(5, 5), Vector4(10, 6, 10, 6)))
	# Labels. The mockup's body text is Nunito 800.
	var bold := FontVariation.new()
	bold.base_font = body
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	theme.set_type_variation(BOLD_LABEL, "Label")
	theme.set_font("font", BOLD_LABEL, bold)
	theme.set_type_variation(INK_BOLD_LABEL, "Label")
	theme.set_font("font", INK_BOLD_LABEL, bold)
	theme.set_color("font_color", INK_BOLD_LABEL, INK)
	theme.set_type_variation(MUTED_LABEL, "Label")
	theme.set_font("font", MUTED_LABEL, bold)
	theme.set_color("font_color", MUTED_LABEL, MUTED)
	theme.set_type_variation(HINT_LABEL, "Label")
	theme.set_font("font", HINT_LABEL, bold)
	theme.set_color("font_color", HINT_LABEL, MUTED_INK)
	# Buttons.
	_button_variation(theme, SEG_BUTTON, heading, 24, CREAM, 0, 0, Vector2.ZERO, Vector4(22, 10, 22, 10), Color("FFFFFF"))
	_button_variation(theme, SEG_BUTTON_ON, heading, 24, YELLOW, 0, 0, Vector2.ZERO, Vector4(22, 10, 22, 10), Color("FFF07A"))
	_button_variation(theme, SWITCH_BUTTON, heading, 22, CREAM, 12, 4, Vector2(3, 3), Vector4(14, 6, 14, 6))
	_button_variation(theme, SWITCH_BUTTON_ON, heading, 22, SKY, 12, 4, Vector2(3, 3), Vector4(14, 6, 14, 6))
	_button_variation(theme, STEP_BUTTON, heading, 24, CREAM, 12, 4, Vector2(3, 3), Vector4(0, 0, 0, 0))
	_button_variation(theme, ACTION_BUTTON, heading, 22, CREAM, 16, 4, Vector2(4, 4), Vector4(14, 10, 14, 10))
	_button_variation(theme, SKY_BUTTON, heading, 24, SKY, 16, 4, Vector2(4, 4), Vector4(14, 10, 14, 10))
	_button_variation(theme, PINK_BUTTON, heading, 24, PINK, 16, 4, Vector2(4, 4), Vector4(14, 10, 14, 10))
	_button_variation(theme, YELLOW_BUTTON, heading, 28, YELLOW, 14, 4, Vector2(4, 4), Vector4(14, 8, 14, 8))
	_button_variation(theme, START_BUTTON, heading, 44, YELLOW, 20, 5, Vector2(6, 6), Vector4(16, 16, 16, 16))
	_button_variation(theme, START_BUTTON_OFF, heading, 44, STRIP_GREY, 20, 5, Vector2(6, 6), Vector4(16, 16, 16, 16))
	_button_variation(theme, PICK_BUTTON, bold, 18, CREAM, 10, 3, Vector2(2, 2), Vector4(8, 4, 8, 4))
	var picked := box(YELLOW, 10, 3, Vector2(2, 2), Vector4(8, 4, 8, 4))
	theme.set_stylebox("pressed", PICK_BUTTON, picked)
	theme.set_stylebox("hover_pressed", PICK_BUTTON, picked)
	_button_variation(theme, PILL_ON, heading, 19, CREAM, 999, 4, Vector2.ZERO, Vector4(14, 1, 14, 1))
	_button_variation(theme, PILL_OFF, heading, 19, Color(CREAM, 0.0), 999, 4, Vector2.ZERO, Vector4(14, 1, 14, 1), Color(CREAM, 0.5))
	_button_variation(theme, PILL_BOT, heading, 19, INK, 999, 4, Vector2.ZERO, Vector4(14, 1, 14, 1), INK)
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, PILL_BOT, CREAM)
	_button_variation(theme, VALUE_BUTTON, heading, 34, Color(CREAM, 0.0), 8, 0, Vector2.ZERO, Vector4(0, 0, 0, 0), Color(CREAM, 0.0))
	theme.set_stylebox("focus", VALUE_BUTTON, box(Color(YELLOW, 0.0), 8, 3, Vector2.ZERO, Vector4(0, 0, 0, 0)))
