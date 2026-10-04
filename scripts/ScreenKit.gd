extends RefCounted

## What the host screen's per-screen scripts share (#543, split out of
## `LobbyScreen.gd`): the palette, the wordmark and the label / panel builders.
## `LobbyScreen.gd` re-exports the constants other code reads. Preloaded by
## path, never by `class_name`.

const LOBBY_BACKGROUND: Color = Color(0.05, 0.06, 0.08, 0.96)
const LOBBY_ACCENT: Color = Color(1.0, 0.85, 0.2, 1.0)
## The smallest text size the host screen uses (#368): 16 design px is 12.8 px on a
## Steam Deck (1280x800 scales the 1600x900 canvas by 0.8), about 9 px cap height.
const DECK_MIN_FONT_SIZE: int = 16
## The wordmark (#359). Loaded as the imported texture where an import exists;
## a fresh clone has no import cache, so it falls back to rasterising the SVG.
const LOGO_PATH: String = "res://art/logo/logo.svg"
const LOGO_LOBBY_SIZE: Vector2 = Vector2(560, 140)
const LOGO_VICTORY_SIZE: Vector2 = Vector2(320, 80)

## The logo as a texture: the imported resource when there is one, else the
## SVG rasterised at 1600x400.
static func load_logo_texture() -> Texture2D:
	if ResourceLoader.exists(LOGO_PATH):
		var imported: Texture2D = load(LOGO_PATH) as Texture2D
		if imported != null:
			return imported
	var image := Image.new()
	if image.load_svg_from_string(FileAccess.get_file_as_string(LOGO_PATH), 1.0) != OK:
		return null
	return ImageTexture.create_from_image(image)

static func logo_rect(node_name: String, size: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = load_logo_texture()
	rect.custom_minimum_size = size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## A hidden full-screen panel added to `parent`.
static func full_screen_panel(parent: Node, node_name: String) -> Control:
	var panel := ColorRect.new()
	panel.name = node_name
	panel.color = LOBBY_BACKGROUND
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	parent.add_child(panel)
	return panel

static func big_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	label.add_theme_constant_override("outline_size", maxi(4, font_size / 10))
	return label

const UiThemeScript := preload("res://scripts/UiTheme.gd")

## A Lilita One label with the thick ink outline the in-match screens use
## (#548), for text drawn over the stage or the dark ground.
static func ink_label(text: String, font_size: int, color: Color, outline: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = UiThemeScript.HUD_HEADING_LABEL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", outline if outline > 0 else maxi(UiThemeScript.HUD_OUTLINE_SIZE, font_size / 8))
	return label

## A light "punch" on appearance (#548): `node` pops from 1.3x to 1x about its
## centre over a fifth of a second. Display only; nothing waits on it.
static func punch(node: Control, tree_owner: Node) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(1.3, 1.3)
	var tween: Tween = tree_owner.create_tween()
	tween.tween_property(node, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A mode HUD's top-centre readout (#548): Lilita One ink text on a cream pill
## with an ink outline and hard shadow. It keeps the label's size and anchors;
## only the look changes.
static func style_hud_pill(label: Label, font_size: int = 44) -> void:
	label.theme_type_variation = UiThemeScript.INK_HEADING_LABEL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_stylebox_override("normal", UiThemeScript.plate(UiThemeScript.CREAM, 22, 0, true, 18))
