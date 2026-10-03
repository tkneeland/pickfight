extends SceneTree
## Regenerates art/ui/pickfight_theme.tres from scripts/UiTheme.gd (#541):
##   godot --headless --path . -s tools/build_ui_theme.gd
## Run `godot --headless --import --path .` first on a fresh checkout so the
## fonts are imported.

const UiThemeScript := preload("res://scripts/UiTheme.gd")

func _init() -> void:
	var err: int = ResourceSaver.save(UiThemeScript.build(), UiThemeScript.THEME_PATH)
	print("saved %s (error %d)" % [UiThemeScript.THEME_PATH, err])
	quit(0 if err == OK else 1)
