extends Area2D

## Temporary "ring out" handling: teleport a fallen player back to the
## arena instead of properly eliminating/scoring them.

const RESPAWN_POSITION: Vector2 = Vector2(0, -200)

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		# Through the player's own move, not by writing its position: the
		# weapon is a separate jointed body and has to come with it.
		body.teleport_to(RESPAWN_POSITION)
