extends RefCounted

## Quitting the game from a menu (#718): the title screen's Quit and Settings' Quit game. One place
## closes the room cleanly and then quits through Music's clean path, the one closing the window
## takes (it frees audio and lets a finished match send its record). A scenario swaps `quit_action`
## for a recorder, so the runner never really quits.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

## What runs instead of the real quit. Unset in the game; a scenario sets it and clears it again.
static var quit_action: Callable = Callable()

## Whether anyone but the host's own seat and bots is seated in `server`'s match: a phone, a gamepad
## or a remote player. Quitting from Settings then asks first.
static func others_seated(server: Object) -> bool:
	if server == null or not server.has_method("claimed_slots"):
		return false
	var own: Array[int] = []
	if server.has_method("host_pc_slot"):
		own.append(server.host_pc_slot())
	if server.has_method("virtual_slots"):
		own.append_array(server.virtual_slots())
	for slot: int in server.claimed_slots():
		if not own.has(slot):
			return true
	return false

## Closes the room (remote seats are told the host left), has a PC client hang up on the room it is
## in, then quits.
static func quit_game(tree: SceneTree, server: Object = null) -> void:
	if server != null:
		if server.has_method("online_requested") and server.online_requested():
			server.apply_host_command("online", false)
		if server.has_method("go_offline"):
			server.go_offline()
	var scene: Node = tree.current_scene
	if scene != null and scene.has_method("leave") and scene.has_method("rejoining"):
		scene.leave() # the PC client
	if quit_action.is_valid():
		quit_action.call()
		return
	if tree.get_script() != null:
		return # a -s script (the scenario runner) is the main loop: a menu press never quits it
	var music: Node = tree.root.get_node_or_null(^"Music")
	if music != null and music.has_method("quit_cleanly"):
		music.quit_cleanly()
	else:
		tree.quit()
