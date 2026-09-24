extends Area2D

## Ring-out: falling off the stage eliminates, whatever damage the player had
## taken. Stage geometry is meant to be the sharpest threat in the game, so it
## does not care how healthy anyone is.
##
## The elimination itself belongs to the player -- `Player.eliminate()` is
## the one path both routes out of a round take, the other being accumulated
## damage -- so this only decides that one happened.
##
## Issue #18 asked for a separate "hazard zone" placed inside the playable
## area rather than beneath it. Built out, it turned out identical to this
## script -- same body_entered check, same eliminate() call, same disregard
## for health -- so it is not a second script. `scenes/parts/Hazard.tscn`
## instances this same script with a hazard's visual and shape; do not add a
## `HazardZone.gd` that would just duplicate this file.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		body.eliminate()
