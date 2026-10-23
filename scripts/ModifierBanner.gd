extends RefCounted

## The round modifier's banner (#69): the modifier's name big, outlined and
## centred across the upper part of the screen, on its own canvas layer above
## the HUD. Built by RoundManager on the host and by the Online joiner (#976)
## from the snapshot's `announcer_text`, so both screens draw the same label.
## Preloaded by path, never by `class_name`.

const UiThemeScript := preload("res://scripts/UiTheme.gd")

const LAYER: int = 10

## A hidden banner label on a new "ModifierLayer" under `parent`.
static func build(parent: Node) -> Label:
	var layer := CanvasLayer.new()
	layer.name = "ModifierLayer"
	layer.layer = LAYER
	parent.add_child(layer)
	var label := Label.new()
	label.name = "ModifierLabel"
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.12
	label.anchor_bottom = 0.32
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = UiThemeScript.HUD_HEADING_LABEL # Lilita One, ink outline (#548)
	label.add_theme_font_size_override("font_size", 96)
	label.add_theme_color_override("font_color", UiThemeScript.YELLOW)
	label.add_theme_constant_override("outline_size", 18)
	label.visible = false
	layer.add_child(label)
	return label
