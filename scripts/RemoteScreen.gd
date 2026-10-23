extends CanvasLayer

## The Online joiner's full-screen layer (issue #976), standing in for the
## host's `LobbyScreen` (layer 5) as the screen `RoundCards.gd` and
## `VictoryScreen.gd` build on, so the joiner's stage title card, PAUSED banner,
## podium, awards and end card are those scripts' own. Preloaded by path,
## never by `class_name` (CLAUDE.md).

## Whether a gamepad drives this machine (the PAUSED hint names its buttons).
var pad_check: Callable = Callable()

func _init() -> void:
	name = "RemoteScreen"
	layer = 5

func pad_active() -> bool:
	return pad_check.is_valid() and bool(pad_check.call())
