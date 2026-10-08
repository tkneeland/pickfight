extends RefCounted
## Baked stage preview images (#647): art/stage_previews/<StageName>.png, made
## by tools/capture_stage_previews.gd. Consumers preload this script by path.
const DIR: String = "res://art/stage_previews"
static func preview_path(stage_name: String) -> String:
	return "%s/%s.png" % [DIR, stage_name]
## The preview texture, or null when none has been baked for that stage.
static func load_preview(stage_name: String) -> Texture2D:
	var path: String = preview_path(stage_name)
	if not ResourceLoader.exists(path): return null
	return load(path) as Texture2D
