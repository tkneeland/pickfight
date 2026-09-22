extends Area2D

## Ring-out: falling off the stage kills, whatever health the player had
## left. Stage geometry is meant to be the sharpest threat in the game, so it
## does not care how healthy anyone is.
##
## The death itself belongs to the player -- `Player.die()` is the one path
## both routes out of a life take, the other being accumulated damage -- so
## this only decides that one happened. That also keeps the weapon coming
## along: it is a separate jointed body and cannot be moved by writing a
## position.
##
## Still the interim model: dying is a respawn with health reset until the
## Round exists, at which point it becomes elimination.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		body.die()
