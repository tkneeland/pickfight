extends RefCounted

## A screen-space HUD's state, copied from the host's nodes onto the Online
## joiner's identical nodes (issue #976). The joiner builds the SAME HUD the
## host does (`scenes/HostHud.tscn`, a game mode's own `_build_hud()`), so all
## that crosses the wire is what changed on it at run time: each Label's
## visibility, text, font colour override, scale, pivot and modulate, each
## ColorRect's colour, and every other CanvasItem's visibility and modulate.
## Generic: a label the host adds later (the scoreboard's Ping, #446) is made
## on the joiner the first time it shows up.
##
## `capture()` returns plain values only (the `hud` frame sends it through
## `var_to_bytes()`, never with objects). TextureRects are skipped: the only
## one, the join QR, is the Local room's phone link, which an Online room never
## shows. Preloaded by path, never by `class_name` (CLAUDE.md).

const KIND_ITEM: int = 0
const KIND_LABEL: int = 1
const KIND_RECT: int = 2

## `root`'s descendants by path, minus any subtree named in `skip`.
static func capture(root: Node, skip: PackedStringArray = PackedStringArray()) -> Dictionary:
	var out: Dictionary = {}
	if root != null and is_instance_valid(root):
		_walk(root, root, skip, out)
	return out

static func _walk(root: Node, node: Node, skip: PackedStringArray, out: Dictionary) -> void:
	for child: Node in node.get_children():
		if skip.has(String(child.name)) or not child is CanvasItem or child is TextureRect:
			continue
		var path: String = String(root.get_path_to(child))
		var item := child as CanvasItem
		if child is Label:
			var label := child as Label
			var colour: Variant = label.get_theme_color("font_color") if label.has_theme_color_override("font_color") else null
			out[path] = [KIND_LABEL, label.visible, label.text, colour, label.scale.snappedf(0.01), label.pivot_offset.round(), label.modulate]
		elif child is ColorRect:
			out[path] = [KIND_RECT, item.visible, (child as ColorRect).color, item.modulate]
		else:
			out[path] = [KIND_ITEM, item.visible, item.modulate]
		_walk(root, child, skip, out)

## Puts `state` (from `capture()`) onto `root`'s matching descendants. A path
## that leaves `root` or names the wrong kind of node is ignored.
static func apply(root: Node, state: Dictionary) -> void:
	if root == null:
		return
	for key: Variant in state:
		var path: String = str(key)
		var v: Variant = state[key]
		if path.is_empty() or path.begins_with("/") or path.contains("..") or not v is Array or (v as Array).size() < 3:
			continue
		var values: Array = v
		var kind: int = int(values[0])
		var node: Node = root.get_node_or_null(NodePath(path))
		if node == null:
			node = _make(root, path, kind)
		if node == null:
			continue
		var item := node as CanvasItem
		if item == null:
			continue
		item.visible = bool(values[1])
		match kind:
			KIND_LABEL:
				var label := node as Label
				if label == null or values.size() < 7:
					continue
				label.text = str(values[2])
				if values[3] is Color:
					if not label.has_theme_color_override("font_color") or label.get_theme_color("font_color") != values[3]:
						label.add_theme_color_override("font_color", values[3])
				elif label.has_theme_color_override("font_color"):
					label.remove_theme_color_override("font_color")
				if values[4] is Vector2:
					label.scale = values[4]
				if values[5] is Vector2:
					label.pivot_offset = values[5]
				if values[6] is Color:
					label.modulate = values[6]
			KIND_RECT:
				var rect := node as ColorRect
				if rect == null or values.size() < 4:
					continue
				if values[2] is Color:
					rect.color = values[2]
				if values[3] is Color:
					rect.modulate = values[3]
			_:
				if values[2] is Color:
					item.modulate = values[2]

## A node the host made at run time and the joiner's copy lacks.
static func _make(root: Node, path: String, kind: int) -> Node:
	var parent_path: String = path.get_base_dir()
	var parent: Node = root if parent_path.is_empty() else root.get_node_or_null(NodePath(parent_path))
	if parent == null:
		return null
	var node: Node
	match kind:
		KIND_LABEL:
			node = Label.new()
		KIND_RECT:
			node = ColorRect.new()
		_:
			return null
	node.name = path.get_file()
	parent.add_child(node)
	return node
