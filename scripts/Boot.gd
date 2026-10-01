extends CanvasLayer

const MainScene = preload("res://scenes/Main.tscn")
const RemoteClientScene = preload("res://scenes/RemoteClient.tscn")

func _on_local_pressed() -> void:
	get_tree().change_scene_to_packed(MainScene)

func _on_online_pressed() -> void:
	get_tree().change_scene_to_packed(RemoteClientScene)
