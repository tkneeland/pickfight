extends Node2D

## A stand-in for a host fighter on the Online joiner (issue #976), carrying
## just what the host's `OffscreenIndicators.gd` reads from a `Player`: where
## it is, whether it is alive and shown, and its team. `RemoteEffects.gd`
## keeps one per slot at that slot's puppet. Preloaded by path, never by
## `class_name` (CLAUDE.md).

var alive: bool = false
var team: int = -1
