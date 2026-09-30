extends SceneTree
## Headless entry point: godot --headless --path . -s relay/relay_main.gd -- --port=9080
## Runs until killed.

func _initialize() -> void:
	var port: int = 9080
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	var relay: Node = preload("res://relay/Relay.gd").new()
	root.add_child(relay)
	var err: int = relay.start(port)
	if err != OK:
		push_error("relay: cannot listen on port %d (error %d)" % [port, err])
		quit(1)
		return
	print("relay listening on port %d" % port)
