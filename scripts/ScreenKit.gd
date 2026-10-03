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

## The chunky-party ground (#546, #507 decision 1): flat deep indigo with faint
## diagonal stripes, as a full-rect, input-transparent control.
static func striped_background(node_name: String = "Ground") -> Control:
	var ground := Control.new()
	ground.name = node_name
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground.draw.connect(func() -> void:
		var size: Vector2 = ground.size
		ground.draw_rect(Rect2(Vector2.ZERO, size), Color("232A4A"))
		# 135deg stripes, 28 px band every 56 px (measured along x), 3.5% white.
		var stripe := Color(1.0, 1.0, 1.0, 0.035)
		var step: float = 56.0
		var x: float = -size.y
		while x < size.x:
			ground.draw_colored_polygon(PackedVector2Array([
				Vector2(x, 0.0), Vector2(x + step * 0.5, 0.0),
				Vector2(x + step * 0.5 + size.y, size.y), Vector2(x + size.y, size.y)]), stripe)
			x += step
	)
	ground.resized.connect(ground.queue_redraw)
	return ground
