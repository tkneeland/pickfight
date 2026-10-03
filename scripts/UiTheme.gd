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
	return theme
