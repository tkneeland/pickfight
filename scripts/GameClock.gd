extends Node

## The game clock (issue #182): game time, in msec, that every gameplay timer
## reads instead of `Time.get_ticks_msec()`, which is wall clock.
##
## It is the physics delta summed up, so it moves only while the game does:
## - it stops while the tree is paused (the host's Pause, #149), because this
##   node is pausable;
## - it runs at `Engine.time_scale`, which scales the physics delta;
## - under `--fixed-fps 60` it moves exactly 1/60 s a physics tick, however
##   fast or slow the machine really runs those ticks.
##
## Registered as an autoload in project.godot, but nothing uses that name:
## read it through the script, loaded by path (never `class_name`), e.g.
##   const GameClockScript := preload("res://scripts/GameClock.gd")
##   var now: int = GameClockScript.now_msec()
## The time lives in a static var, so every reader shares it. The autoload
## is the one node that moves it, and nothing else should call `advance()`
## except a scenario checking a timer against a fake clock.
##
## Left on wall clock on purpose: ControllerServer's packet and liveness
## timers (a phone's connection lives in real time, pause or not), Sfx's and
## Music's release tails and the fullscreen sync grace (audio and the window
## run in real time), and the scenario runner's network poll timeouts.

static var _sec: float = 0.0

## Game time since start-up, in whole msec.
static func now_msec() -> int:
	return int(_sec * 1000.0)

## Game time since start-up, in seconds.
static func now_sec() -> float:
	return _sec

## Moves game time on by `sec`. The autoload calls it every physics tick.
static func advance(sec: float) -> void:
	if sec > 0.0:
		_sec += sec

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _physics_process(delta: float) -> void:
	advance(delta)
