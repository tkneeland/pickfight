extends RefCounted
## The host's Text size setting (#751): scales every font size the UI uses, for
## reading the shared screen from across the room. Two kinds of size exist: the
## theme's (the default and each type variation) and the per-control
## `font_size` overrides screens set in code. Both are scaled from their
## original ("base") size, never from the last scaled one, so Normal always
## returns exactly to the design sizes. Load with preload() by path.

const META_BASE: StringName = &"pf_base_font_sizes"
## Skip a control (world-space labels such as name tags have their own size option).
const META_SKIP: StringName = &"pf_no_text_scale"
const OVERRIDE_NAME: StringName = &"font_size"
const META_LAST: StringName = &"pf_scaled_font_size"
const META_ORIGIN: StringName = &"pf_origin_font_size"


## Scales the project theme's font sizes to `factor` times their design sizes.
static func apply_to_theme(theme: Theme, factor: float) -> void:
	if theme == null:
		return
	var base: Dictionary = theme.get_meta(META_BASE, {})
	if base.is_empty():
		base["#default"] = theme.default_font_size
		for type_name: String in theme.get_font_size_type_list():
			for item: String in theme.get_font_size_list(type_name):
				base["%s/%s" % [type_name, item]] = theme.get_font_size(item, type_name)
		theme.set_meta(META_BASE, base)
	theme.default_font_size = scaled(int(base["#default"]), factor)
	for key: String in base:
		if key == "#default":
			continue
		var parts: PackedStringArray = key.split("/")
		theme.set_font_size(parts[1], parts[0], scaled(int(base[key]), factor))


static func scaled(size: int, factor: float) -> int:
	return maxi(1, roundi(float(size) * factor))


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
	var current: int = control.get_theme_font_size(OVERRIDE_NAME)
	var origin: int = current
	if control.has_meta(META_LAST) and int(control.get_meta(META_LAST)) == current:
		origin = int(control.get_meta(META_ORIGIN))
	var target: int = scaled(origin, factor)
	control.set_meta(META_ORIGIN, origin)
	control.set_meta(META_LAST, target)
	if target != current:
		control.add_theme_font_size_override(OVERRIDE_NAME, target)
