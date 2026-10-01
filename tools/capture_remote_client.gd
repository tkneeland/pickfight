extends SceneTree
## Windowed screenshots of the PC client mid-round (issue #241): a real host
## (Main with bots) goes online through an in-process relay, the client scene
## joins it from its own SubViewport (own 2D world, so its copy of the stage
## does not overlap the host's) and plays a round. Not part of the suite --
## headless Godot does not render, so run it windowed, by hand:
##
##   godot --path . -s tools/capture_remote_client.gd -- --bots=6 --out=/abs/dir
##
## Writes <out>/client-playing.png (what the remote player sees) and
## <out>/host-playing.png (the host's own screen), then quits.
const RelayScript := preload("res://relay/Relay.gd")
const ClientScene: PackedScene = preload("res://scenes/RemoteClient.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const PORT: int = 39555
var _out: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_run()

func _wait(msec: int) -> void:
	var end: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < end:
		await process_frame

func _fail(message: String) -> void:
	printerr("CAPTURE FAILED: " + message)
	quit(1)

func _run() -> void:
	var relay: Node = RelayScript.new()
	get_root().add_child(relay)
	if relay.start(PORT) != OK:
		_fail("relay could not listen on %d" % PORT)
		return
	var main: Node = MAIN_SCENE.instantiate()
	get_root().add_child(main)
	await _wait(500)
	var server: Node = main.get_node("ControllerServer")
	var rm: Node = main.get_node("RoundManager")
	server.go_online("ws://127.0.0.1:%d" % PORT)
	var waited: int = 0
	while not server.is_online() and waited < 100:
		await _wait(50)
		waited += 1
	if not server.is_online():
		_fail("host never came online")
		return
	var view := SubViewport.new()
	view.size = Vector2i(1280, 720)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(view)
	var client: Node = ClientScene.instantiate()
	client.settings_path = ""
	client.relay_url = "ws://127.0.0.1:%d" % PORT
	view.add_child(client)
	await _wait(300)
	client.join(server.online_room_code(), "Remote")
	waited = 0
	while client.state != 2 and waited < 100:
		await _wait(50)
		waited += 1
	if client.state != 2:
		_fail("client never joined: " + client.status_text)
		return
	client._ready_button.button_pressed = true
	waited = 0
	while int(rm.get("_state")) != 1 and waited < 600:
		await _wait(50)
		waited += 1
	if int(rm.get("_state")) != 1:
		_fail("the round never started")
		return
	client.mouse_motion(Vector2(300, -200))
	await _wait(6000)
	var shot: Image = view.get_texture().get_image()
	shot.save_png("%s/client-playing.png" % _out)
	get_root().get_texture().get_image().save_png("%s/host-playing.png" % _out)
	print("client: stage %d, %d players drawn, %d frames (%d full), slot %d" % [client.stage_id(), client.puppet_count(0), client.frames_applied, client.full_frames_applied, client.slot])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	server.go_offline()
	quit(0)
