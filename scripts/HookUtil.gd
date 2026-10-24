extends RefCounted

## Small statics shared by the nodes that hang off the game without being wired
## to it (Sfx's hooks, Juice, the announcer, Music, the HUD effects). Kept
## free of preloads on purpose: anything may preload it without pulling in a
## chain of other scripts. Reached by path, never by `class_name`.

## Call `on_node_added` for every node already under `tree`'s root, and again
## for each node that enters the tree from now on. The callback does its own
## filtering (an already-watched meta, a how-to-play demo node).
static func watch_tree(tree: SceneTree, on_node_added: Callable) -> void:
	tree.node_added.connect(on_node_added)
	_walk(tree.root, on_node_added)

static func _walk(node: Node, on_node_added: Callable) -> void:
	on_node_added.call(node)
	for child in node.get_children():
		_walk(child, on_node_added)

## The `Sfx` autoload's setting `setting`, read through `from`; `fallback`
## when there is no `Sfx` autoload to ask (a bare scenario fixture).
static func sfx_flag(from: Node, setting: StringName, fallback: bool) -> bool:
	var sfx: Node = from.get_node_or_null(^"/root/Sfx")
	if sfx == null:
		return fallback
	return bool(sfx.get(setting))
