extends Node2D

## Scenario stand-in for a StageGust (issue #313): the duck-typed surface Bot
## reads, so the gust reaction is checked before the real part exists.
var warning: bool = false
var direction: Vector2 = Vector2.RIGHT

func is_warning() -> bool:
	return warning

func gust_direction() -> Vector2:
	return direction
