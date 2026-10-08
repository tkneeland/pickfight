extends "res://tools/stub_lobby_roster.gd"

## `stub_lobby_roster.gd` plus the host phone's picked game mode, as the real
## `ControllerServer.game_mode()` reports it (#352): the round loop latches it
## as a match's countdown runs out. A scenario sets `picked_mode`, the way the
## lobby picker would.

var picked_mode: String = ""

func game_mode() -> String:
	return picked_mode
