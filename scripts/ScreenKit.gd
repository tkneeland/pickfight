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

# --- Lobby look (#547): themed labels, the striped ground, light motion ----------

const UiThemeScript := preload("res://scripts/UiTheme.gd")
const UiGroundScript := preload("res://scripts/UiGround.gd")

## A label in a `UiTheme` variation (the theme gives font and colour), `font_size` px.
static func themed_label(text: String, font_size: int, variation: StringName = &"", align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	if variation != &"":
		label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## A button in a `UiTheme` variation. No focus until a gamepad menu asks for it.
static func themed_button(text: String, variation: StringName, node_name: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.focus_mode = Control.FOCUS_NONE
	button.pivot_offset_ratio = Vector2(0.5, 0.5)
	if not node_name.is_empty():
		button.name = node_name
	hover_pop(button)
	return button

## An opaque full-screen panel on the striped indigo ground, hidden. The lobby's.
static func striped_panel(parent: Node, node_name: String) -> Control:
	var panel := Control.new()
	panel.name = node_name
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	parent.add_child(panel)
	panel.add_child(UiGroundScript.new())
	return panel

## Light hover / focus motion: the control grows a little while the mouse or the
## gamepad focus is on it. Never delays input (it is only a scale).
static func hover_pop(control: Control, grow: float = 1.04) -> void:
	control.pivot_offset_ratio = Vector2(0.5, 0.5)
	var on: Callable = func() -> void: _scale_to(control, Vector2(grow, grow), 0.09)
	var off: Callable = func() -> void: _scale_to(control, Vector2.ONE, 0.09)
	control.mouse_entered.connect(on)
	control.mouse_exited.connect(off)
	control.focus_entered.connect(on)
	control.focus_exited.connect(off)

static func _scale_to(control: Control, target: Vector2, seconds: float) -> void:
	if not control.is_inside_tree():
		control.scale = target
		return
	if control.has_meta("pop_tween"):
		var old: Variant = control.get_meta("pop_tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tween: Tween = control.create_tween()
	control.set_meta("pop_tween", tween)
	tween.tween_property(control, "scale", target, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## A card or popup popping in: from 0.85 up past 1 and back (220 ms).
static func pop_in(control: Control) -> void:
	control.pivot_offset_ratio = Vector2(0.5, 0.5)
	control.scale = Vector2(0.85, 0.85)
	if not control.is_inside_tree():
		control.scale = Vector2.ONE
		return
	var tween: Tween = control.create_tween()
	control.set_meta("pop_tween", tween)
	tween.tween_property(control, "scale", Vector2(1.05, 1.05), 0.154).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.066).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

## A number "punching": it lands big and settles (the countdown).
static func punch(control: Control, from: float = 1.6) -> void:
	control.pivot_offset_ratio = Vector2(0.5, 0.5)
	control.scale = Vector2(from, from)
	if not control.is_inside_tree():
		control.scale = Vector2.ONE
		return
	var tween: Tween = control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
