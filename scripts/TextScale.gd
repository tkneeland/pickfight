extends RefCounted
## The host's Text size setting (#751): scales every font size the UI uses, for
## reading the shared screen from across the room. Two kinds of size exist: the
## theme's (the default and each type variation) and the per-control
## `font_size` overrides screens set in code. Both are scaled from their
## original ("base") size, never from the last scaled one, so Normal always
## returns exactly to the design sizes. Load with preload() by path.
##
## Auto-fit: a "fit root" (a whole screen or popup, see `is_fit_root`) can run
## below the chosen size when its contents do not fit; `TextFit.gd` steps it
## down and back up. A fit root stores its own factor in `META_FIT`; its
## controls scale by that factor, and a smaller theme on the root restyles its
## theme-driven text. `overflows` is the "does it fit" measure.

const META_BASE: StringName = &"pf_base_font_sizes"
## Skip a control (world-space labels such as name tags have their own size option).
const META_SKIP: StringName = &"pf_no_text_scale"
const OVERRIDE_NAME: StringName = &"font_size"
const META_LAST: StringName = &"pf_scaled_font_size"
const META_ORIGIN: StringName = &"pf_origin_font_size"
## Marks a Control as a fit root (a popup inside a screen; whole screens are found by their parent).
const META_ROOT: StringName = &"pf_text_fit_root"
## The factor a fit root currently runs at (<= the chosen Text size).
const META_FIT: StringName = &"pf_fit_factor"
## Slack, in design px, before a rect counts as sticking out of its parent.
const TOLERANCE: float = 1.5

static var _fit_themes: Dictionary = {}


## Scales the project theme's font sizes to `factor` times their design sizes.
static func apply_to_theme(theme: Theme, factor: float) -> void:
	if theme == null:
		return
	var base: Dictionary = _base_sizes(theme)
	theme.default_font_size = scaled(int(base["#default"]), factor)
	for key: String in base:
		if key == "#default":
			continue
		var parts: PackedStringArray = key.split("/")
		theme.set_font_size(parts[1], parts[0], scaled(int(base[key]), factor))


## The design font sizes of `theme`, recorded the first time they are asked for.
static func _base_sizes(theme: Theme) -> Dictionary:
	var base: Dictionary = theme.get_meta(META_BASE, {})
	if base.is_empty():
		base["#default"] = theme.default_font_size
		for type_name: String in theme.get_font_size_type_list():
			for item: String in theme.get_font_size_list(type_name):
				base["%s/%s" % [type_name, item]] = theme.get_font_size(item, type_name)
		theme.set_meta(META_BASE, base)
	return base


## The design size of the default font, whatever Text size is chosen (0 when the theme sets none).
static func design_default_size() -> int:
	var project: Theme = ThemeDB.get_project_theme()
	return maxi(0, int(_base_sizes(project)["#default"])) if project != null else 0


## A theme holding only font sizes, `factor` times the design sizes, for one fit
## root: its descendants find these before the project theme's.
static func theme_for(project: Theme, factor: float) -> Theme:
	if project == null:
		return null
	var key: int = roundi(factor * 100.0)
	if _fit_themes.has(key) and is_instance_valid(_fit_themes[key]):
		return _fit_themes[key]
	var base: Dictionary = _base_sizes(project)
	var theme := Theme.new()
	if int(base["#default"]) > 0:
		theme.default_font_size = scaled(int(base["#default"]), factor)
	for item_key: String in base:
		if item_key == "#default":
			continue
		var parts: PackedStringArray = item_key.split("/")
		theme.set_font_size(parts[1], parts[0], scaled(int(base[item_key]), factor))
	_fit_themes[key] = theme
	return theme


static func scaled(size: int, factor: float) -> int:
	return maxi(1, roundi(float(size) * factor))


## The factor `node` is drawn at: its nearest fit root's, else `fallback` (the chosen Text size).
static func effective_factor(node: Node, fallback: float) -> float:
	var current: Node = node
	while current != null:
		if current.has_meta(META_FIT):
			return float(current.get_meta(META_FIT))
		current = current.get_parent()
	return fallback


## Scales the `font_size` override of `node` and of every descendant.
static func apply_to_tree(node: Node, factor: float) -> void:
	apply_to_node(node, factor)
	for child: Node in node.get_children():
		apply_to_tree(child, factor)


## Scales one control's `font_size` override. A size the screen set after our
## last scaling (a label that changes its own size) becomes the new base.
static func apply_to_node(node: Node, factor: float) -> void:
	if not node is Control or node.has_meta(META_SKIP):
		return
	var control := node as Control
	if not control.has_theme_font_size_override(OVERRIDE_NAME):
		return
	factor = effective_factor(node, factor)
	var current: int = control.get_theme_font_size(OVERRIDE_NAME)
	var origin: int = current
	if control.has_meta(META_LAST) and int(control.get_meta(META_LAST)) == current:
		origin = int(control.get_meta(META_ORIGIN))
	var target: int = scaled(origin, factor)
	control.set_meta(META_ORIGIN, origin)
	control.set_meta(META_LAST, target)
	if target != current:
		control.add_theme_font_size_override(OVERRIDE_NAME, target)


## True for a screen (a Control straight under a CanvasLayer or the window) and
## for a popup marked with `META_ROOT`: the units that auto-fit.
static func is_fit_root(node: Node) -> bool:
	if not node is Control or node.has_meta(META_SKIP):
		return false
	if node.has_meta(META_ROOT):
		return true
	var parent: Node = node.get_parent()
	return parent is CanvasLayer or parent is Window


## Records that `root` runs at `factor`. The root gets a smaller theme when `factor` is below
## the chosen size `target`, and always when it sits inside another fit root: that one's
## theme would otherwise be inherited.
static func assign_fit(root: Control, factor: float, target: float) -> void:
	root.set_meta(META_FIT, factor)
	if is_equal_approx(factor, target) and not _inside_fit_root(root):
		root.theme = null
	else:
		root.theme = theme_for(ThemeDB.get_project_theme(), factor)


## `assign_fit`, then scales the root's code-set font sizes to match.
static func set_fit(root: Control, factor: float, target: float) -> void:
	assign_fit(root, factor, target)
	apply_to_tree(root, factor)


static func _inside_fit_root(root: Control) -> bool:
	var current: Node = root.get_parent()
	while current != null:
		if current.has_meta(META_FIT):
			return true
		current = current.get_parent()
	return false


## Does anything in `root` stick out of where it is meant to sit, or get cut
## off? `viewport_size` bounds a screen that has no Control parent. Nested fit
## roots (popups) are measured by their own call. A control sticks out when its
## rect leaves its parent's: containers grow to their contents, so a screen
## that does not fit shows up as a child bigger than the parent that was meant
## to hold it. Scroll areas are allowed to hold more than they show.
static func overflows(root: Control, viewport_size: Vector2) -> bool:
	return not first_overflow(root, viewport_size).is_empty()


## The first thing that does not fit, by path and rect, or "" when everything does.
static func first_overflow(root: Control, viewport_size: Vector2) -> String:
	var parent := root.get_parent() as Control
	var bounds: Vector2 = parent.size if parent != null else viewport_size
	if _sticks_out(root, bounds):
		return "%s %s leaves %s" % [root.name, Rect2(root.position, root.size), bounds]
	return _children_overflow(root)


static func _sticks_out(control: Control, bounds: Vector2) -> bool:
	if control.size.x <= 0.0 or control.size.y <= 0.0:
		return false
	return control.position.x < -TOLERANCE or control.position.y < -TOLERANCE \
		or control.position.x + control.size.x > bounds.x + TOLERANCE \
		or control.position.y + control.size.y > bounds.y + TOLERANCE


static func _children_overflow(node: Control) -> String:
	var scrolls: bool = node is ScrollContainer
	for child: Node in node.get_children():
		var control := child as Control
		if control == null or not control.visible or control.has_meta(META_ROOT) or control.has_meta(META_SKIP):
			continue
		if control.top_level:
			continue
		if not scrolls and _sticks_out(control, node.size) and _has_text(control):
			return "%s %s leaves %s" % [control.get_path(), Rect2(control.position, control.size), node.size]
		if _text_cut_off(control):
			return "%s cuts its text off" % control.get_path()
		var inner: String = _children_overflow(control)
		if not inner.is_empty():
			return inner
	return ""


static func _has_text(node: Node) -> bool:
	if node is Label and not (node as Label).text.is_empty():
		return true
	if node is Button and not (node as Button).text.is_empty():
		return true
	for child: Node in node.get_children():
		var control := child as Control
		if control != null and control.visible and _has_text(control):
			return true
	return false


## A label or button set to clip its text (not with an ellipsis), whose text is wider than it is.
static func _text_cut_off(control: Control) -> bool:
	var text: String = ""
	var clips: bool = false
	var margins: float = 0.0
	if control is Label:
		var label := control as Label
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			return false
		text = label.text
		clips = (label.clip_text or label.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING) and not _ellipsis(label.text_overrun_behavior)
	elif control is Button:
		var button := control as Button
		if button.autowrap_mode != TextServer.AUTOWRAP_OFF:
			return false
		text = button.text
		clips = (button.clip_text or button.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING) and not _ellipsis(button.text_overrun_behavior)
		var box: StyleBox = button.get_theme_stylebox("normal")
		if box != null:
			margins = box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
	if not clips or text.is_empty() or control.size.x <= 0.0:
		return false
	var font: Font = control.get_theme_font("font")
	var needed: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, control.get_theme_font_size("font_size")).x
	return needed + margins > control.size.x + TOLERANCE



## A trim that ends in "..." is the design for text the player typed (a long name), not a clipped layout.
static func _ellipsis(behavior: int) -> bool:
	return behavior >= TextServer.OVERRUN_TRIM_ELLIPSIS


## How many controls are showing in `root` (a popup inside it has its own count):
## auto-fit looks for room again once there are fewer than when it last had none.
static func signature(root: Control) -> int:
	var total: int = 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var control := node as Control
		if control != null:
			if not control.visible or (control != root and control.has_meta(META_ROOT)):
				continue
			total += 1
		stack.append_array(node.get_children())
	return total
