extends Node

## Round/session loop (ADR-0004), built on top of `ControllerServer`'s roster
## (ADR-0007). The session itself is endless -- this node just keeps starting
## a new elimination round each time the current one is down to one player
## standing, for as long as enough of the roster is present to play.
##
## "The roster" means claimed slots (`ControllerServer.claimed_slots()`):
## someone whose controller drops mid-round keeps their slot for the rest of
## that round -- their `Player` just sits wherever the last input left it,
## drifting to rest, exactly as an unplugged controller always has -- and is
## only dropped from the roster between rounds, when
## `expire_disconnected_claims()` runs.

@export var player_paths: Array[NodePath] = []
## Stages to rotate through: `stage_scenes[0]` opens every match (#200), then
## shuffled bags cover the rest with no repeat back-to-back (ADR-0011).
## Swapped once per round, in `_swap_stage()`. Spawn points come from the
## active stage's `get_spawn_points()`, not from an export here. Dealt by
## `StageRotation.gd`, which shares this array.
@export var stage_scenes: Array[PackedScene] = []:
	set(value):
		stage_scenes = value
		_stage_rotation.scenes = value
## Issue #144: a large stage (`Stage.view_size` bigger than the normal view)
## is only offered to a round with at least this many players; normal stages
## are offered at any count. See `StageRotation.stage_allowed()`.
@export var large_stage_min_players: int = 5:
	set(value):
		large_stage_min_players = value
		_stage_rotation.large_stage_min_players = value
## Issue #144: the camera `_swap_stage()` zooms and centres on each new
## stage's view (`Stage.get_view_rect()`). Empty leaves every camera alone,
## which is what every scenario's RoundManager does unless it tests this.
@export var camera_path: NodePath
## Node the active stage instance is added to and removed from.
@export var arena_container_path: NodePath
@export var controller_server_path: NodePath
@export var score_label_path: NodePath
## Shown while waiting on roster size, since a WAITING round leaves every
## Player invisible (Player._ready()) -- without this the shared screen looks
## broken (blank arena, no players) instead of "needs one more phone".
@export var waiting_label_path: NodePath
## Shown for round_end_pause_sec once a round resolves. Without this, the
## winner is put through leave_round() the same tick the loser is put through
## eliminate() -- both go inert via the same _go_inert(), so every player
## vanishes at once and the shared screen shows nothing happened. Holds one
## icon+score entry per player slot (see scenes/Main.tscn), refreshed from
## each Player's identity_color and this node's own _scores.
@export var scoreboard_path: NodePath
## A round will not start with fewer roster entries than this -- one player
## cannot be "eliminated down to one survivor".
@export var min_players_to_start: int = 2
## Pause after a round resolves, so the shared screen has a moment where a
## win is visible before the next round's players pop back in.
@export var round_end_pause_sec: float = 2.0
## How long a round may run with no player still in it holding a connected
## controller before it ends with no winner (ADR-0007 amendment). Without
## this, a round everyone walked away from can never end -- nobody is left to
## ring anyone out -- so its claims never expire and every new phone is
## refused. Long enough that a Wi-Fi blip hitting the whole room at once
## costs nobody the round.
@export var abandoned_round_grace_sec: float = 10.0
## Determinism seam for stage rotation (ADR-0011): -1 (the default) leaves
## the rotation randomized every run; any other value seeds it so a scenario
## can assert an exact bag order.
@export var rotation_seed: int = -1
## Rising kill zone (issue #22, ADR-0012): how long the active stage's floor
## `KillZone` holds still at round start before it begins to climb.
@export var kill_zone_grace_sec: float = 50.0
## Seconds the rise then takes to reach the stage's highest spawn. A
## deadline, not a speed: stages range from under 500 px to over 900 px
## between floor and top spawn, and a fixed speed would give Cascade's
## holdouts twice as long as Flatlands'. The speed is derived per stage in
## `_start_kill_zone_rise()`, and the zone keeps climbing past that spawn.
@export var kill_zone_rise_sec: float = 80.0

## The pickup scene instanced per spawn (scenes/Pickup.tscn).
@export var pickup_scene: PackedScene = preload("res://scenes/Pickup.tscn")
## Seconds between pickup arrivals once a round is running (user story 20).
## 12 since #152 (was 10): a little rarer with few players, and
## `PickupDirector.interval_sec()` shortens it for a crowd.
@export var pickup_spawn_interval_sec: float = 12.0
## With this many players or more on the roster the stage is crowded (#152):
## pickups come every `crowded_interval_scale` of the interval, and the cap
## rises to one per player.
@export var crowded_roster: int = 5
@export var crowded_interval_scale: float = 0.6
## Fewest pickups the stage is allowed to hold at once (user stories 3 and
## 20). The live cap is `PickupDirector.cap()`: one fewer than the roster, never
## below this (#36, amending ADR-0009).
@export var max_pickups: int = 2
## Weapons a pickup may hold. Empty means the roster's own list
## (`PickupWeapons.available_weapons()`); scenarios fill it with test weapons.
## The pickaxe is filtered out either way.
@export var pickup_weapons: Array[Resource] = []

## Seconds of spawn protection at round start (#114). 0 turns it off.
@export var spawn_protection_sec: float = 1.0

## Chance, 0..1, that a round rolls a modifier. 0 switches them off.
@export_range(0.0, 1.0) var modifier_chance: float = 0.35
## How long a rolled modifier's name stays on screen at round start.
@export var modifier_announce_sec: float = 3.0
## A `RoundModifiers` id (e.g. "low_gravity") every round gets, whatever
## `modifier_chance` and `modifier_rolls_enabled` say: the determinism seam a
## scenario or a playtest uses to pick one. Empty (the default) rolls.
@export var forced_modifier: String = ""
## Determinism seam for the roll itself, like `rotation_seed`: -1 leaves it
## random every run. Its own RNG, never the rotation's, so a roll can never shift a
## seeded stage rotation.
@export var modifier_seed: int = -1
## The match seed (issue #187), the scenario seam: -1 (the default) takes
## `--seed=N` from the command line (after `--`), or failing that picks one
## with `randi()` at match start. Every gameplay RNG -- the stage deal, the
## pickups, the modifier roll with Weapon Roulette and Meteor Shower, the
## bots, `--random-weapons` and the hit-sound jitter -- is its own stream
## derived from it (`rng_for()`), so one logged seed replays a whole match.
## `rotation_seed` and `modifier_seed`, when set, still win for their own
## streams, so every scenario written against them deals exactly as before.
@export var match_seed: int = -1

## Open on the lobby and play matches ("first to N") instead of an endless
## round loop.
@export var lobby_enabled: bool = false
## Length of the 3-2-1 countdown once everyone is ready.
@export var lobby_countdown_sec: float = 3.0
## How long the victory screen waits for every phone's Continue (#337).
@export var victory_continue_sec: float = 30.0

## How long the stage name takes to sweep across. 0 turns it off.
@export var stage_title_sec: float = 1.1

## The HUD's KillFeed node (scenes/Main.tscn). Empty: KOs are still counted,
## just not shown.
@export var kill_feed_path: NodePath

## Sound hooks (issue #75, ADR-0016); nothing in the game reads them.
## `round_started` once every player is spawned, `round_won` where the
## winner scores, `modifier_announced` as a modifier's name goes up.
signal round_started
signal round_won(slot: int)
signal modifier_announced(title: String)
## Announcer hooks (#152): each whole second of the lobby countdown (3, 2,
## 1), and the round win that wins the match.
signal countdown_ticked(seconds_left: int)
signal match_won(slot: int)
## Teams mode (issue #236): a team took a round, and a team won the match.
## A Teams match emits these instead of `match_won` (`round_won` still goes
## out for the sound hooks, with a winning survivor's slot or -1).
signal team_round_won(team: int)
signal team_match_won(team: int)

enum State { WAITING, ROUND_ACTIVE, ROUND_END, LOBBY, COUNTDOWN, VICTORY }

## The pieces split out of this script (#175), loaded by path (never by
## class_name). This node still runs the round loop and owns every setting
## above; these do one job each and are driven from here:
## - StageRotation (RefCounted): which stage plays next.
## - PickupDirector (Node child): weapon pickups.
## - NameTags (Node2D child): the nicknames over players' heads.
## - LobbyScreen (CanvasLayer child): lobby, podium, title card, pause banner.
const StageRotationScript := preload("res://scripts/StageRotation.gd")
const StatsSenderScript := preload("res://scripts/StatsSender.gd")
const PickupDirectorScript := preload("res://scripts/PickupDirector.gd")
const NameTagsScript := preload("res://scripts/NameTags.gd")
const LobbyScreenScript := preload("res://scripts/LobbyScreen.gd")
## Teams mode's rules (issue #236, ADR-0018).
const TeamsScript := preload("res://scripts/Teams.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")
## Every deadline this node and its pieces keep (`*_msec`) is game time
## (#182), read from here: it stops while the tree is paused and runs at
## `Engine.time_scale`, so none of them needs pushing back after a pause.
const GameClockScript := preload("res://scripts/GameClock.gd")

var _state: int = State.WAITING
var _pause_until_msec: int = 0
var _players: Array = []
var _scores: PackedInt32Array = PackedInt32Array()
var _controller_server: Node
var _waiting_label: Label
var _scoreboard: Control
## Stage rotation (ADR-0011, #144, #163): which stage plays next. Built here,
## not in `_ready()`, so the export setters above can reach it and a
## RoundManager outside the tree can still deal.
var _stage_rotation: RefCounted = StageRotationScript.new()
var _current_stage: Node2D
var _stage_spawn_points: Array[Vector2] = []
## Weapon pickups (#14, #152): spawns, caps and clears them. A child built in
## `_init()`, so a RoundManager outside the tree has one too.
var _pickup_director: Node
## When the current round was first seen with no connected controller among
## its surviving players, or -1 while at least one is connected.
var _abandoned_since_msec: int = -1
## The previous round's winner slot, or -1 (no winner: a no-survivors round,
## or no round has ended yet). Consumed by the next `_try_start_round()` --
## which clears it back to -1, since it applies to one round only -- and
## dropped early if that slot's claim expires first (issue #6, D3): a claim
## only ever lapses at the round boundary (ADR-0007), and a newcomer who
## later takes the freed slot must not inherit the old winner's weapon.
var _last_winner_slot: int = -1

## Playtest option (issue #29): with `-- --random-weapons` on the host's
## command line, every player who did not win the last round starts the next
## one holding a random weapon from this list rather than the pickaxe, for
## trying weapons without chasing pickups (#14). The winner still keeps what
## they held (ADR-0005), and pickups still spawn. Off by default: a normal
## launch plays exactly as designed.
##
## The list is the pickaxe then `PickupWeapons.WEAPON_PATHS` (issue #200), so
## a weapon added to the roster there is offered here too.
static func playtest_weapon_paths() -> PackedStringArray:
	var paths := PackedStringArray([PickupWeaponsScript.PICKAXE_PATH])
	paths.append_array(PickupWeaponsScript.WEAPON_PATHS)
	return paths

const PickupWeaponsScript := preload("res://scripts/PickupWeapons.gd")
var _random_weapons: bool = false
## `--demo`: a short-slot showcase. Random weapons, a fixed opening run of
## the stages with the most parts on show, and a quicker lava that still
## leaves a real fight before it arrives. Tests never pass it.
var _demo: bool = false
const DEMO_STAGE_ORDER: PackedStringArray = [
	"Springboard", "Rockfall", "Gale", "Bulwark", "Carousel", "Sinkhole",
]
const DEMO_KILL_ZONE_GRACE_SEC: float = 20.0
const DEMO_KILL_ZONE_RISE_SEC: float = 40.0
const DEMO_PHYSICS_TICKS: int = 120

func _init() -> void:
	add_to_group("round_manager")
	_pickup_director = PickupDirectorScript.new(self)
	add_child(_pickup_director)

const ReplayBufferScript := preload("res://scripts/ReplayBuffer.gd")
var _replay: Node

## F9 saves the last ~10 s of play as a clip (#329, ADR-0020).
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F9 and _replay != null:
		_replay.save_and_toast()
		get_viewport().set_input_as_handled()

func _ready() -> void:
	_replay = ReplayBufferScript.new()
	_replay.name = "ReplayBuffer"
	add_child(_replay)
	# Either list: `-- --demo` from a terminal, or bare `--demo` from the
	# editor's Play button (project.godot `editor/run/main_run_args`).
	_demo = OS.get_cmdline_user_args().has("--demo") or OS.get_cmdline_args().has("--demo")
	_random_weapons = _demo or OS.get_cmdline_user_args().has("--random-weapons")
	if _demo:
		_apply_demo_mode()
	if _random_weapons:
		print("RoundManager: --random-weapons on; non-winners start each round with a random weapon")
	_stage_rotation.demo = _demo
	for path in player_paths:
		_players.append(get_node_or_null(path))
	_watch_for_buzzes()
	_watch_for_survivor()
	_scores.resize(_players.size())
	_controller_server = get_node_or_null(controller_server_path)
	if _controller_server != null and _controller_server.has_signal("host_command"):
		_controller_server.connect("host_command", _on_host_command)
	_watch_for_lobby_changes()
	if _controller_server != null and _controller_server.has_signal("steal_requested"):
		_controller_server.connect("steal_requested", _on_steal_requested)
	if _controller_server != null and _controller_server.has_signal("player_joined"):
		_controller_server.connect("player_joined", _on_slot_claimed_fresh)
	_waiting_label = get_node_or_null(waiting_label_path) as Label
	_scoreboard = get_node_or_null(scoreboard_path) as Control
	if _scoreboard != null:
		_scoreboard.visible = false
	_update_score_label()
	_set_waiting_text(0)
	# Without the lobby this whole session is the match. With it, a match
	# starts at each countdown's end, which seeds (and logs) afresh; this
	# only makes sure nothing ever draws from an unseeded stream before then.
	_seed_match(not lobby_enabled)
	if lobby_enabled:
		_enter_lobby()

func _process(_delta: float) -> void:
	_tick_final_ko()
	_tick_spawn_protection()
	_tick_ghosts()
	_tick_name_tags()
	_tick_damage_bars()
	match _state:
		State.LOBBY, State.COUNTDOWN, State.VICTORY:
			_tick_lobby()
		State.WAITING:
			if lobby_enabled and _roster_size() < min_players_to_start:
				_enter_lobby()
			else:
				_try_start_round()
		State.ROUND_ACTIVE:
			_check_round_end()
			if _state == State.ROUND_ACTIVE:
				_tick_airtime()
				_pickup_director.tick()
				if lobby_enabled and _lobby_publish_due():
					_publish_lobby_state()
		State.ROUND_END:
			if GameClockScript.now_msec() >= _pause_until_msec:
				# Expire first, then test: a winner whose claim lapsed must not
				# pass its weapon to whoever claims the freed slot (issue #6 D3).
				# `_try_start_round()` expires again on the way in; it is idempotent,
				# and the check below is only meaningful once expiry has run.
				if _controller_server != null:
					_controller_server.expire_disconnected_claims()
					if _last_winner_slot != -1 and not _controller_server.claimed_slots().has(_last_winner_slot):
						_last_winner_slot = -1
					var claimed: Array[int] = _controller_server.claimed_slots()
					_team_keep_weapon = _team_keep_weapon.filter(func(slot: int) -> bool: return claimed.has(slot))
				if _match_winner_slot != -1 or _match_winner_team != -1:
					_enter_victory()
					return
				_state = State.WAITING
				_try_start_round()

## Enough of the roster present and idle: bring every claimed player into
## the arena. Slots nobody has claimed stay exactly as `Player._ready()`
## (or the previous round's `leave_round()`) left them -- inert and hidden.
##
## Disconnected claims are expired first, on every attempt rather than only
## after a round ends: ADR-0007 holds an entry "until the end of the current
## round", and while waiting there is no round to hold it for. Otherwise a
## phone that joined and dropped before any round started keeps its slot
## forever, is counted as present, and gets spawned as a limp body.
func _try_start_round() -> void:
	if _controller_server == null:
		return
	_controller_server.expire_disconnected_claims()
	var roster: Array[int] = _controller_server.claimed_slots()
	if roster.size() < min_players_to_start:
		# Drop the last round's scoreboard too, so it can't sit over the
		# centred waiting text when a player left during the round.
		if _scoreboard != null:
			_scoreboard.visible = false
		_set_waiting_text(roster.size())
		return
	if _waiting_label != null:
		_waiting_label.visible = false
	if _scoreboard != null:
		_scoreboard.visible = false
	_stage_rotation.round_player_count = roster.size()
	_stage_rotation.mode_id = game_mode
	_swap_stage()
	_round_number += 1
	_in_round.clear()
	var entering: Array[int] = []
	for slot in roster:
		if slot >= 0 and slot < _players.size() and _players[slot] != null:
			entering.append(slot)
	_apply_teams(entering)
	var spawn_offset: int = spawn_rotation_offset(entering.size())
	var weapon_paths: PackedStringArray = playtest_weapon_paths()
	for i in entering.size():
		var slot: int = entering[i]
		# By place in the round, not slot number (#163): stages pair their spawns
		# left/right, so slots 0 and 2 alone would both start on the left. The
		# places are rotated a seeded amount each round (#200), so nobody starts
		# on the same spot every round of a stage.
		var spawn: Vector2 = _spawn_point((i + spawn_offset) % entering.size())
		var keeps_weapon: bool = slot == _last_winner_slot or _team_keep_weapon.has(slot)
		_players[slot].start_round(spawn, keeps_weapon)
		_in_round.append(slot)
		if _random_weapons and not keeps_weapon:
			_players[slot].set_weapon_stats(load(weapon_paths[_playtest_weapon_rng.randi() % weapon_paths.size()]))
	_ko_round_started()
	_abandoned_since_msec = -1
	# One round only: consumed here whether or not the winner is still rostered.
	_last_winner_slot = -1
	_team_keep_weapon.clear()
	_survivor_slot = -1
	_survivor_team = -1
	_state = State.ROUND_ACTIVE
	_start_round_modifier()
	_start_game_mode()
	_pickup_director.start()
	_start_kill_zone_rise()
	_start_spawn_protection()
	_show_stage_title()
	round_started.emit()

## Rotates to the next stage (ADR-0011): frees the outgoing instance, picks
## the next index into `stage_scenes` via `StageRotation.next_stage_index()`, and
## caches the new stage's spawn points so `_try_start_round()`'s loop above
## can hand them out in roster order. A no-op with an empty `stage_scenes`, leaving
## `_stage_spawn_points` as it was.
func _swap_stage() -> void:
	if stage_scenes.is_empty():
		return
	var container: Node = get_node_or_null(arena_container_path)
	if container == null:
		return
	if _current_stage != null:
		# Out of the tree first: a queued free leaves it there until frame end and
		# the same-named new stage would be auto-renamed (#594).
		if _current_stage.get_parent() != null:
			_current_stage.get_parent().remove_child(_current_stage)
		_current_stage.queue_free()
	_pin_stock_stage()
	_stage_rotation.stage_index = _stage_rotation.next_stage_index()
	_current_stage = stage_scenes[_stage_rotation.stage_index].instantiate()
	_current_stage.set("stage_index", _stage_rotation.stage_index)
	_match_stages.append(stage_scenes[_stage_rotation.stage_index].resource_path.get_file().get_basename())
	var night: bool = _roll_night()
	_current_stage.set("night", night)
	container.add_child(_current_stage)
	var ink: Color = PaletteScript.NIGHT["ink"] if night else PaletteScript.mood_for_stage(_stage_rotation.stage_index)["ink"]
	for player in _players:
		if player != null and player.has_method("set_ink"):
			player.set_ink(ink)
	_stage_spawn_points = _current_stage.get_spawn_points()
	_fit_camera_to_stage()

# --- Night stages (issue #332) -------------------------------------------------
#
# A stage can be played as a night variant: darkened, lit by lamps and glows,
# purely visual. It is applied by data (`Stage.night`, set before the stage
# enters the tree), so no stage scene is duplicated. Each round rolls it with
# `night_chance`, from its own RNG so the modifier stream is undisturbed. The
# roll honours `modifier_rolls_enabled` (the deterministic-run seam) and
# `forced_night` (-1 roll, 0 never, 1 always) overrides it.

## Chance, 0..1, that a round's stage is the night variant.
@export_range(0.0, 1.0) var night_chance: float = 0.2
## -1 roll as usual, 0 never night, 1 always night.
@export var forced_night: int = -1
var _night_rng: RandomNumberGenerator

func _roll_night() -> bool:
	if forced_night >= 0:
		return forced_night == 1
	if not modifier_rolls_enabled or night_chance <= 0.0:
		return false
	if _night_rng == null:
		_night_rng = RandomNumberGenerator.new()
		if modifier_seed >= 0:
			_night_rng.seed = modifier_seed + 332
		else:
			_night_rng.randomize()
	return _night_rng.randf() < night_chance

# --- Large stages (issue #144) ------------------------------------------------
#
# A stage may declare a view bigger than the 1600x900 screen (`Stage.view_size`).
# The Main camera zooms out, uniformly, until that view fits, and centres on it;
# a normal stage puts it back to zoom 1 at the origin, exactly as it always was.
# HUD, title card, lobby and podium live on CanvasLayers, which the camera never
# moves or scales; the name tags are world-space, so they are scaled back up by
# the zoom (see `_tick_name_tags()`).

const StageScript := preload("res://scripts/Stage.gd")
const PaletteScript := preload("res://scripts/Palette.gd")

func _fit_camera_to_stage() -> void:
	var camera: Camera2D = get_node_or_null(camera_path) as Camera2D if not camera_path.is_empty() else null
	if camera == null or _current_stage == null:
		return
	var view: Rect2
	if _current_stage.has_method("get_view_rect"):
		view = _current_stage.get_view_rect()
	else:
		view = Rect2(_current_stage.global_position - StageScript.DEFAULT_VIEW_SIZE * 0.5, StageScript.DEFAULT_VIEW_SIZE)
	var zoom: float = StageScript.zoom_for_view(view.size)
	camera.zoom = Vector2(zoom, zoom)
	camera.global_position = view.get_center()
	# A cut between rounds, not a pan: no smoothing or interpolation from the
	# last stage's framing.
	camera.reset_smoothing()
	camera.reset_physics_interpolation()
	camera.force_update_scroll()

func _set_waiting_text(connected: int) -> void:
	if _waiting_label == null:
		return
	_waiting_label.visible = true
	# Not "x / 2": two is the minimum to start, not the most who can play (#36).
	_waiting_label.text = tr("WAITING_FOR_PLAYERS") % [connected, min_players_to_start]

## Issue #193: set by a mid-round kick, consumed by the next
## `_check_round_end()`.
var _kicked_this_round_check: bool = false

## A round ends the instant one or zero players are still standing --
## whichever came from a ring-out or the last hit that crossed DEATH_DAMAGE.
## The lone survivor (if any) scores the round and is returned to the same
## inert state a loser ends up in, via `leave_round()` rather than
## `eliminate()`, since finishing a round alive is not a death.
##
## A round nobody can finish -- no survivor has a connected controller -- is
## ended with no winner once `abandoned_round_grace_sec` has passed; every
## survivor leaves the round the same way a winner does.
##
## Issue #193: the first check after the host kicks someone mid-round reads
## `_kicked_this_round_check`. If that kick left a lone survivor, the round
## ends with no winner: kicking the last opponent must not hand anyone a point.
func _check_round_end() -> void:
	var after_kick: bool = _kicked_this_round_check
	_kicked_this_round_check = false
	if _team_mode:
		_check_team_round_end(after_kick)
		return
	_flush_kos()
	var alive_slots: Array[int] = _alive_slots()
	# Nobody left, but someone was the last one standing on an earlier physics
	# tick of this frame: they won before they fell (#163).
	if alive_slots.is_empty() and _survivor_slot != -1:
		alive_slots.append(_survivor_slot)
	if alive_slots.size() > 1:
		if not _round_abandoned(alive_slots):
			return
		for slot in alive_slots:
			_players[slot].leave_round()
		alive_slots.clear()
	_survivor_slot = -1
	if after_kick and alive_slots.size() == 1:
		if _players[alive_slots[0]].alive:
			_players[alive_slots[0]].leave_round()
		alive_slots.clear()
	if alive_slots.size() == 1:
		var winner_slot: int = alive_slots[0]
		_scores[winner_slot] += 1
		_buzz(winner_slot, "win")
		round_won.emit(winner_slot)
		var winner_point: Vector2 = _players[winner_slot].global_position
		_players[winner_slot].leave_round()
		_update_score_label()
		_last_winner_slot = winner_slot
		if lobby_enabled and _scores[winner_slot] >= _match_target:
			_match_winner_slot = winner_slot
			_start_final_ko(winner_point)
			match_won.emit(winner_slot)
	else:
		_last_winner_slot = -1
	_pickup_director.clear()
	_stop_kill_zone_rise()
	_end_round_modifier()
	_ko_round_ended(_last_winner_slot)
	_show_scoreboard()
	_clear_all_shots()
	_state = State.ROUND_END
	_pause_until_msec = GameClockScript.now_msec() + int(round_end_pause_sec * 1000.0)
	if lobby_enabled:
		_publish_lobby_state()

## The round's last one standing, recorded the moment an elimination leaves a
## single player alive (#163), or -1. `_check_round_end()` runs once per
## rendered frame, but eliminations land on physics ticks and a slow frame
## can hold two: without this, a survivor who falls on the tick after the
## deciding KO ends the round with nobody standing, and nobody scores.
var _survivor_slot: int = -1
## The physics frame `_survivor_slot` was recorded on. A survivor eliminated
## on that same tick went down together with the last opponent: still a draw.
var _survivor_frame: int = -1

func _watch_for_survivor() -> void:
	for slot in _players.size():
		var player: Variant = _players[slot]
		if player != null and player.has_signal("eliminated"):
			player.connect("eliminated", _on_eliminated_check_survivor.bind(slot))

func _on_eliminated_check_survivor(slot: int) -> void:
	# Stock decides who is still standing (a life left) itself, then calls
	# `_record_survivor()`; here the lives would not be counted yet.
	if _game_mode_node != null and _game_mode_node.has_method("is_pending"):
		return
	_record_survivor(slot)

func _record_survivor(slot: int) -> void:
	if _state != State.ROUND_ACTIVE:
		return
	if _team_mode:
		_check_team_survivor()
		return
	var frame: int = Engine.get_physics_frames()
	if slot == _survivor_slot:
		if frame == _survivor_frame:
			_survivor_slot = -1
		return
	var alive: Array[int] = _alive_slots()
	if alive.size() == 1:
		_survivor_slot = alive[0]
		_survivor_frame = frame

## Phone buzzes (issue #34, ADR-0013): each slot's player is watched here, so
## `Player` never learns about phones and `ControllerServer` never learns
## about rounds. Every buzz goes only to the phone whose player it is about.
## - `eliminated` for the player just eliminated -- not for survivors put
##   through `leave_round()` at round end, which emits nothing.
## - `struck` for the victim of a strike that dealt damage, and `hit` for the
##   attacker who landed it. A 0-damage swing buzzes no one.
## - `win` is sent from `_check_round_end()` where the winner scores.
func _watch_for_buzzes() -> void:
	for slot in _players.size():
		var player: Variant = _players[slot]
		if player == null:
			continue
		if player.has_signal("eliminated"):
			player.connect("eliminated", _buzz.bind(slot, "eliminated"))
		if player.has_signal("strike_landed"):
			player.connect("strike_landed", _on_strike_landed.bind(slot))
		if player.has_signal("eliminated"):
			player.connect("eliminated", _on_ko_eliminated.bind(slot))
		if player.has_signal("weapon_picked_up"):
			player.connect("weapon_picked_up", _on_weapon_picked_up.bind(slot))

## `attacker_slot` comes last because that is where the signal's bind puts it.
func _on_strike_landed(victim: Node, amount: float, point: Vector2, lethal: bool, attacker_slot: int) -> void:
	if lethal:
		_last_lethal_point = point
		_has_lethal_point = true
	_ko_record_hit(victim, amount, attacker_slot)
	if amount <= 0.0:
		return
	var victim_slot: int = _players.find(victim)
	if victim_slot != -1:
		_buzz(victim_slot, "struck")
	# A rock reports on the victim's own signal (attacker == victim, #521).
	if attacker_slot != victim_slot:
		_buzz(attacker_slot, "hit")

## Phone damage bars (issue #331): every claimed slot's phone is told its
## player's damage fraction each tick; `send_damage` drops the unchanged and
## throttles the rest. A fresh round's 0 damage resets the bar the same way.
func _tick_damage_bars() -> void:
	if _controller_server == null or not _controller_server.has_method("send_damage"):
		return
	for slot in _players.size():
		var player: Variant = _players[slot]
		if player != null:
			_controller_server.send_damage(slot, player.damage / player.DEATH_DAMAGE)

## A roster that cannot buzz (a test stub without `send_buzz`) is skipped.
func _buzz(slot: int, kind: String) -> void:
	if _controller_server != null and _controller_server.has_method("send_buzz"):
		_controller_server.send_buzz(slot, kind)

## Whether the round has run for `abandoned_round_grace_sec` with none of
## `alive_slots` holding a connected controller. Any one reconnecting resets
## the countdown. A roster that cannot report liveness (a test stub without
## `slot_has_controller()`) never abandons a round.
func _round_abandoned(alive_slots: Array[int]) -> bool:
	if not _controller_server.has_method("slot_has_controller"):
		return false
	for slot in alive_slots:
		if _controller_server.slot_has_controller(slot):
			_abandoned_since_msec = -1
			return false
	var now: int = GameClockScript.now_msec()
	if _abandoned_since_msec < 0:
		_abandoned_since_msec = now
	return now - _abandoned_since_msec >= int(abandoned_round_grace_sec * 1000.0)

## How far round the spawn places are turned this round (issue #200): the
## `i`-th player entering, in roster order, takes place `(i + offset) % count`.
## Drawn from the match seed's "spawns" stream, so a replayed seed spawns
## everyone where they spawned before. One draw a round whatever the count,
## so the stream never depends on who was there.
func spawn_rotation_offset(count: int) -> int:
	var roll: int = _spawn_rng.randi()
	return roll % count if count > 0 else 0

## Where the `place`-th player of a round (0-based; the places go round the
## roster from `spawn_rotation_offset()`, #200) starts:
## spawn point `place`, so the first two players of any roster take a stage's
## first left/right pair whatever their slot numbers (#163). On a stage with
## fewer spawns than players (issue #138) a spawn is shared round-robin and
## nudged by `SPAWN_SHARE_OFFSET` per lap -- alternately left and right -- so
## two players never start inside each other.
func _spawn_point(place: int) -> Vector2:
	var count: int = _stage_spawn_points.size()
	if count == 0:
		push_warning("RoundManager: stage has no spawn points; player %d spawns at the origin" % place)
		return Vector2.ZERO
	var lap: int = place / count
	var spawn: Vector2 = _stage_spawn_points[place % count]
	if lap > 0:
		var side: float = 1.0 if place % 2 == 0 else -1.0
		spawn += Vector2(SPAWN_SHARE_OFFSET.x * side * lap, SPAWN_SHARE_OFFSET.y * lap)
	return spawn

## How far a player sharing a spawn point starts from the one it shares with:
## to the side by about a body width and a little higher, so it lands beside
## rather than on top, still on the same platform.
const SPAWN_SHARE_OFFSET: Vector2 = Vector2(48.0, -24.0)

## Refreshes and reveals the round-end scoreboard: one icon+score entry per
## player slot, read from that slot's Scoreboard/SlotN child (Icon then
## Score, per scenes/Main.tscn) and this node's own _players/_scores.
## Only slots in play get an entry (#45): an empty or disconnected slot's
## entry is hidden, so two players see two scores, not four.
func _show_scoreboard() -> void:
	if _scoreboard == null:
		return
	for slot in _players.size():
		if slot >= _scoreboard.get_child_count():
			continue
		var entry: Node = _scoreboard.get_child(slot)
		if entry is CanvasItem:
			entry.visible = _slot_in_play(slot)
		if entry.get_child_count() < 2:
			continue
		var icon: ColorRect = entry.get_child(0) as ColorRect
		var score_label: Label = entry.get_child(1) as Label
		var player: Variant = _players[slot]
		if icon != null and player != null:
			icon.color = player.identity_outline_color()
		if score_label != null:
			score_label.text = str(_scores[slot]) if slot < _scores.size() else "0"
		var name_label: Label = entry.get_child(2) as Label if entry.get_child_count() > 2 else null
		if name_label != null:
			name_label.text = _slot_name(slot)
		if _team_mode:
			_team_scoreboard_entry(slot, score_label, name_label)
		elif name_label != null and name_label.has_theme_color_override("font_color"):
			name_label.remove_theme_color_override("font_color")
		_scoreboard_ping(entry, slot)
	_scoreboard.visible = true

## Issue #446: the round trip to a remote seat in ms, -1 when `slot` has none.
func _slot_ping(slot: int) -> int:
	if _controller_server == null or not _controller_server.has_method("slot_ping_msec"):
		return -1
	return int(_controller_server.slot_ping_msec(slot))

## Issue #446: a "Ping" label at the end of `entry`, filled for a remote seat
## (warning colour past the limit) and hidden for everyone else.
func _scoreboard_ping(entry: Node, slot: int) -> void:
	var label: Label = entry.get_node_or_null("Ping") as Label
	if label == null:
		label = Label.new()
		label.name = "Ping"
		entry.add_child(label)
	var ping: int = _slot_ping(slot)
	label.visible = ping >= 0
	if ping >= 0:
		label.text = LobbyScreenScript.ping_text(ping)
		label.add_theme_color_override("font_color", LobbyScreenScript.ping_color(ping))

## Whether `slot` is claimed and, where the roster can say, has a phone
## connected right now (#45). Without a roster every slot counts, so a
## scenario with no ControllerServer still sees its whole scoreboard.
func _slot_in_play(slot: int) -> bool:
	if _controller_server == null:
		return true
	if not _controller_server.claimed_slots().has(slot):
		return false
	if _controller_server.has_method("slot_has_controller"):
		return _controller_server.slot_has_controller(slot)
	return true

func _update_score_label() -> void:
	var label: Label = get_node_or_null(score_label_path) as Label
	if label == null:
		return
	var parts: PackedStringArray = PackedStringArray()
	if _team_mode:
		for team in TeamsScript.COUNT:
			parts.append(tr("SCORE_TEAM") % [TeamsScript.team_name(team), _team_scores[team]])
		label.text = "  ".join(parts)
		return
	for slot in _scores.size():
		if _slot_in_play(slot):
			parts.append(tr("SCORE_PLAYER") % [slot + 1, _scores[slot]])
	label.text = "  ".join(parts)

# --- Weapon pickups (issue #14, ADR-0009) ------------------------------------
#
# One pickup lies on the stage when a round starts; another arrives every
# `pickup_spawn_interval_sec` while fewer than `max_pickups` are on it; any
# left when the round ends are cleared. Pickups are parented to the active
# stage instance, so a stage swap can never strand one either. All of it is
# `PickupDirector.gd` (#175), driven from `_try_start_round()`, `_process()`,
# `_check_round_end()` and the host controls; the settings are the exports up
# top.

# --- Spawn protection (issue #114) -------------------------------------------
#
# For `spawn_protection_sec` after a round places the players, none of them can
# take damage, and each blinks to show it. Knockback still applies (owner's
# call left to us in #114; a shove at spawn is harmless, and blocking it would
# mean reaching into Player's physics). The lava still eliminates. There is no
# mid-round spawn to protect: a phone that joins mid-round waits for the next
# round (ADR-0004), and that round's start protects it with everyone else.

## Blink rate and the dimmed alpha a protected player blinks down to.
const SPAWN_BLINK_HZ: float = 8.0
const SPAWN_BLINK_ALPHA: float = 0.35

var _protected: Array[Node2D] = []
var _protected_until_msec: int = 0

func _start_spawn_protection() -> void:
	_end_spawn_protection()
	if spawn_protection_sec <= 0.0:
		return
	for player: Variant in _players:
		if player is Node2D and is_instance_valid(player) and bool(player.get("alive")):
			player.set("spawn_protected", true)
			_protected.append(player)
	_protected_until_msec = GameClockScript.now_msec() + int(spawn_protection_sec * 1000.0)

func _tick_spawn_protection() -> void:
	if _protected.is_empty():
		return
	var now: int = GameClockScript.now_msec()
	if now >= _protected_until_msec or _state != State.ROUND_ACTIVE:
		_end_spawn_protection()
		return
	var lit: bool = int(float(now) / 1000.0 * SPAWN_BLINK_HZ * 2.0) % 2 == 0
	for player: Node2D in _protected:
		if is_instance_valid(player):
			player.modulate.a = 1.0 if lit else SPAWN_BLINK_ALPHA

func _end_spawn_protection() -> void:
	for player: Node2D in _protected:
		if is_instance_valid(player):
			player.set("spawn_protected", false)
			player.modulate.a = 1.0
	_protected.clear()

## Whether spawn protection is running, for the scenarios.
func spawn_protection_active() -> bool:
	return not _protected.is_empty()

# --- Rising kill zone (issue #22, ADR-0012) ----------------------------------
#
# Only the node named `KillZone` directly under the stage root rises. Hazard
# parts share KillZone.gd but sit elsewhere in the tree under other names, so
# they are never found here and never rise. Each round instances a fresh
# stage, so the zone resets to its authored height by construction.

## The active stage's floor kill zone, or null on a stage without one.
func _floor_kill_zone() -> Node2D:
	if _current_stage == null:
		return null
	var zone: Node2D = _current_stage.get_node_or_null("KillZone") as Node2D
	if zone == null or not zone.has_method("start_rising"):
		return null
	return zone

## Round start: arm the rise so it reaches the highest spawn
## `kill_zone_rise_sec` after the grace period ends.
func _start_kill_zone_rise() -> void:
	var zone: Node2D = _floor_kill_zone()
	if zone == null or _stage_spawn_points.is_empty() or not GameModesScript.has_rise(game_mode):
		return
	var highest_y: float = INF
	for spawn: Vector2 in _stage_spawn_points:
		highest_y = minf(highest_y, spawn.y)
	var distance: float = zone.global_position.y - highest_y
	if distance <= 0.0 or kill_zone_rise_sec <= 0.0:
		push_warning("RoundManager: floor kill zone is not below the highest spawn; not rising")
		return
	var timing: Dictionary = kill_zone_rise_timing(game_mode)
	zone.start_rising(float(timing["grace_sec"]), distance / float(timing["rise_sec"]))

## The rise under `mode_id` (issue #352): whether it runs, its grace period
## and the seconds it takes to reach the highest spawn, `kill_zone_grace_sec`
## and `kill_zone_rise_sec` scaled by the mode's factors in `GameModes.TABLE`.
func kill_zone_rise_timing(mode_id: String) -> Dictionary:
	return {
		"rises": GameModesScript.has_rise(mode_id),
		"grace_sec": kill_zone_grace_sec * GameModesScript.rise_grace_factor(mode_id),
		"rise_sec": kill_zone_rise_sec / GameModesScript.rise_speed_factor(mode_id),
	}

func _stop_kill_zone_rise() -> void:
	var zone: Node2D = _floor_kill_zone()
	if zone != null:
		zone.stop_rising()

# --- Round modifiers (issue #50, ADR-0015) -----------------------------------
#
# Some rounds get one random twist from `RoundModifiers.gd`, applied right
# after the round's players spawn and before the kill zone is armed, and
# undone the moment the round ends. Its name is shown big on screen for
# `modifier_announce_sec` by a label this node builds itself, so no scene
# needs editing.

const RoundModifiersScript := preload("res://scripts/RoundModifiers.gd")

## Master switch for random rolls, shared by every RoundManager. The game
## never touches it. The scenario runner turns it off at startup so every
## scenario written before #50 plays exactly as it did; a scenario that wants
## rolls turns it back on, and `forced_modifier` works either way.
static var modifier_rolls_enabled: bool = true

var _modifier: RefCounted = null
var _modifier_rng: RandomNumberGenerator
var _modifier_layer: CanvasLayer
var _modifier_label: Label
## Hides the label `modifier_announce_sec` after an announcement. A child
## node, so it goes when this node does; restarted by every announcement.
var _modifier_timer: Timer

## The id of the modifier on the current round, or "" for none.
func active_modifier_id() -> String:
	return _modifier.id if _modifier != null else ""

## The announcement label, or null before any modifier was ever announced.
func modifier_label() -> Label:
	return _modifier_label

## Round start: roll (or take the forced one), apply it to every player now
## in the round and the stage, and announce it.
func _start_round_modifier() -> void:
	_end_round_modifier()
	var id: String = _roll_modifier()
	if id == "":
		return
	_modifier = RoundModifiersScript.create(id)
	if _modifier == null:
		push_warning("RoundManager: unknown round modifier '%s'" % id)
		return
	var in_round: Array = []
	for player: Variant in _players:
		if player != null and player.alive:
			in_round.append(player)
	_modifier.apply(self, in_round, _current_stage)
	_announce_modifier(_modifier.title)

## Round end: put back everything the modifier changed and drop its name.
func _end_round_modifier() -> void:
	_end_game_mode()
	if _modifier != null:
		_modifier.undo()
		_modifier = null
	if _modifier_label != null:
		_modifier_label.visible = false

func _roll_modifier() -> String:
	if forced_modifier != "":
		return "" if GameModesScript.bans_modifier(game_mode, forced_modifier) else forced_modifier
	if not modifier_rolls_enabled or modifier_chance <= 0.0:
		return ""
	var draw: RandomNumberGenerator = modifier_rng()
	if draw.randf() >= modifier_chance:
		return ""
	# The mode's bans (#352) come off the pool; with none, the draw is the same
	# one it always was.
	var ids := PackedStringArray()
	for id: String in RoundModifiersScript.IDS:
		if not GameModesScript.bans_modifier(game_mode, id) \
				and HostSettingsScript.shared().is_modifier_enabled(game_mode, id):  # Rules tab (#378)
			ids.append(id)
	if ids.is_empty():
		return ""
	return ids[draw.randi() % ids.size()]

## The one stream the modifier roll and the modifiers' own draws (Weapon
## Roulette's picks, Meteor Shower's meteors) share (#162), made on first use:
## seeded from `modifier_seed` when that is set, otherwise the match seed's
## "modifiers" stream (#187). Setting `_modifier_rng` to null starts it afresh.
func modifier_rng() -> RandomNumberGenerator:
	if _modifier_rng == null:
		if modifier_seed == -1:
			_modifier_rng = rng_for("modifiers")
		else:
			_modifier_rng = RandomNumberGenerator.new()
			_modifier_rng.seed = modifier_seed
	return _modifier_rng

func _announce_modifier(title: String) -> void:
	if _modifier_label == null:
		_build_modifier_label()
	_modifier_label.text = tr("MODIFIER_" + title.to_upper().replace(" ", "_"))
	_modifier_label.visible = true
	_modifier_timer.start(maxf(modifier_announce_sec, 0.01))
	modifier_announced.emit(title)

## Big, outlined, centred across the upper part of the screen, on its own
## canvas layer above the HUD.
func _build_modifier_label() -> void:
	_modifier_layer = CanvasLayer.new()
	_modifier_layer.name = "ModifierLayer"
	_modifier_layer.layer = 10
	add_child(_modifier_layer)
	_modifier_label = Label.new()
	_modifier_label.name = "ModifierLabel"
	_modifier_label.anchor_left = 0.0
	_modifier_label.anchor_right = 1.0
	_modifier_label.anchor_top = 0.12
	_modifier_label.anchor_bottom = 0.32
	_modifier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modifier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_modifier_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modifier_label.theme_type_variation = UiThemeScript.HUD_HEADING_LABEL # Lilita One, ink outline (#548)
	_modifier_label.add_theme_font_size_override("font_size", 96)
	_modifier_label.add_theme_color_override("font_color", UiThemeScript.YELLOW)
	_modifier_label.add_theme_constant_override("outline_size", 18)
	_modifier_label.visible = false
	_modifier_layer.add_child(_modifier_label)
	_modifier_timer = Timer.new()
	_modifier_timer.name = "ModifierAnnounceTimer"
	_modifier_timer.one_shot = true
	_modifier_timer.timeout.connect(func() -> void: _modifier_label.visible = false)
	add_child(_modifier_timer)

## A RoundManager leaving the tree mid-round (a scenario tearing down) must
## not leave its modifier on players that outlive it.
func _exit_tree() -> void:
	_end_final_ko()
	_end_game_mode()
	if _paused:
		_set_tree_paused(false)
	if _modifier != null:
		_modifier.undo()
		_modifier = null

## Puts DEMO_STAGE_ORDER at the front of the rotation (the rest follow in
## their usual order, played straight through), and shortens the lava.
func _apply_demo_mode() -> void:
	var ordered: Array[PackedScene] = []
	for stage_name: String in DEMO_STAGE_ORDER:
		for scene: PackedScene in stage_scenes:
			if scene.resource_path.get_file().get_basename() == stage_name:
				ordered.append(scene)
	for scene: PackedScene in stage_scenes:
		if not ordered.has(scene):
			ordered.append(scene)
	stage_scenes = ordered
	kill_zone_grace_sec = DEMO_KILL_ZONE_GRACE_SEC
	kill_zone_rise_sec = DEMO_KILL_ZONE_RISE_SEC
	# Twice the physics rate halves how far a fast head or body moves per
	# step, so far less tunnels through platforms. Gameplay is timed in
	# seconds, not ticks; the scenarios never pass --demo, so they keep 60.
	Engine.physics_ticks_per_second = DEMO_PHYSICS_TICKS
	print("RoundManager: --demo on; random weapons, %d Hz physics, lava after %.0f s, stages from %s" % [
		Engine.physics_ticks_per_second, kill_zone_grace_sec, ", ".join(DEMO_STAGE_ORDER)])

# --- Lobby, ready-up and matches (issue #120) --------------------------------
#
# With `lobby_enabled` (scenes/Main.tscn turns it on) the session opens on a
# lobby screen: the game name, a big join QR, and each joined phone's colour,
# name and ready state. When every joined phone (2+) is ready a 3-2-1
# countdown runs; a join, a leave or an un-ready during it cancels it. Then a
# match: rounds as before, until someone reaches the host phone's "first to
# N". A victory screen with a podium follows, and every human phone tapping
# Continue (bots do not count), 30 seconds passing or the host pressing a key
# takes the room back to the lobby (#337), where everyone readies afresh. Off by default, so every scenario written before #120 keeps
# its endless round loop.
#
# ControllerServer only carries the phones' requests and this node's state
# back to them; everything here reaches it duck-typed, so a stub roster
# without the lobby methods simply never has anyone ready.

var _match_target: int = 5
var _match_winner_slot: int = -1
var _countdown_until_msec: int = 0
var _countdown_roster: Array[int] = []
## The lobby, podium, title card and pause banner (`LobbyScreen.gd`, #175),
## built the first time any of them is needed; see `_screen()`.
var _lobby_screen: CanvasLayer
var _last_lobby_state: Dictionary = {}

## "lobby", "countdown", "playing", "round_end" (the pause between rounds)
## or "victory": what the phones are told.
func lobby_phase() -> String:
	match _state:
		State.LOBBY:
			return "lobby"
		State.COUNTDOWN:
			return "countdown"
		State.VICTORY:
			return "victory"
		State.ROUND_END:
			return "round_end"
	return "playing"

## The current match's "first to N", fixed when its countdown finished.
func match_target() -> int:
	return _match_target

## The match winner the victory screen is showing, or -1.
func match_winner_slot() -> int:
	return _match_winner_slot

func lobby_panel() -> Control:
	return _lobby_screen.lobby_panel() if _lobby_screen != null else null

func victory_panel() -> Control:
	return _lobby_screen.victory_panel() if _lobby_screen != null else null

func score_of(slot: int) -> int:
	return _scores[slot] if slot >= 0 and slot < _scores.size() else 0

func _roster() -> Array[int]:
	if _controller_server == null:
		return []
	# Never mid-round: a claim outlives a disconnect until the round ends
	# (ADR-0007), and the phones' state is published every frame of one.
	if _state != State.ROUND_ACTIVE and _state != State.ROUND_END:
		_controller_server.expire_disconnected_claims()
	return _controller_server.claimed_slots()

func _roster_size() -> int:
	return _roster().size()

func _is_ready(slot: int) -> bool:
	return _controller_server != null and _controller_server.has_method("slot_ready") and _controller_server.slot_ready(slot)

func _everyone_ready(roster: Array[int]) -> bool:
	if roster.size() < min_players_to_start or _bots_waiting_for_a_human(roster):
		return false
	for slot: int in roster:
		if not _is_ready(slot):
			return false
	return true

func _host_slot() -> int:
	if _controller_server != null and _controller_server.has_method("host_slot"):
		return _controller_server.host_slot()
	return -1

## The Host panel's target row (#544): the mode's own value for Stock, Soccer
## and Capture the Flag, else the round target.
func _state_target(in_lobby: bool) -> int:
	var picked: int = GameModesScript.target_setting(_state_mode_id())
	if picked >= 0:
		return picked
	return _requested_target() if in_lobby else _match_target

func _state_target_kind() -> String:
	return GameModesScript.target_kind(_state_mode_id())

func _state_mode_id() -> String:
	if (_state == State.LOBBY or _state == State.COUNTDOWN or _state == State.VICTORY) \
			and _controller_server != null and _controller_server.has_method("game_mode"):
		return str(_controller_server.game_mode())
	return game_mode

## What the host phone has typed, or the current value with no host to ask.
func _requested_target() -> int:
	if _controller_server != null and _controller_server.has_method("match_target"):
		return maxi(1, int(_controller_server.match_target()))
	return _match_target

## A slot's display name: the phone's nickname where the roster has one.
func _slot_name(slot: int) -> String:
	if _controller_server != null and _controller_server.has_method("slot_name"):
		var nickname: String = str(_controller_server.slot_name(slot))
		if not nickname.is_empty():
			return nickname
	return "P%d" % (slot + 1)

func _slot_color(slot: int) -> Color:
	var player: Variant = _players[slot] if slot >= 0 and slot < _players.size() else null
	if player != null and player.has_method("identity_outline_color"):
		return player.identity_outline_color()
	return Color.WHITE

## The chill lobby track, from the Music autoload (#118) by path. Fight music
## is Music's own job: it follows `round_started`.
func _play_lobby_music() -> void:
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("play_lobby"):
		music.play_lobby()

func _enter_lobby() -> void:
	_end_final_ko()
	_play_lobby_music()
	_state = State.LOBBY
	_match_winner_slot = -1
	_match_winner_team = -1
	_clear_stage()
	# The last round's teams do not carry into the lobby sandbox (#521).
	for player: Variant in _players:
		if player != null and "team" in player:
			player.team = TeamsScript.NONE
	if _waiting_label != null:
		_waiting_label.visible = false
	if _scoreboard != null:
		_scoreboard.visible = false
	_build_lobby_ui()
	_lobby_screen.show_panel("lobby")
	_set_join_corner_visible(false)
	_last_lobby_state = {}
	_tick_lobby()

## The demo build's end card (#361): how long it waits for a Continue tap or
## a key, and whether it is up now.
@export var end_card_sec: float = 15.0
var _end_card_up: bool = false
var _end_card_until_msec: int = 0
## When the victory screen gives up waiting for Continue taps (#337).
var _victory_until_msec: int = 0

## On the victory screen a phone's Ready flag means "Continue" (#337). True when
## every human has tapped it; bots do not count, and with no human present only
## the timeout or the host's key moves on.
func _everyone_continued(roster: Array[int]) -> bool:
	var humans: int = 0
	for slot: int in roster:
		if _controller_server != null and _controller_server.has_method("is_virtual") and _controller_server.is_virtual(slot):
			continue
		humans += 1
		if not _is_ready(slot):
			return false
	return humans > 0

## Victory over: back to the lobby with nobody ready, so the Continue taps do
## not start the next match's countdown by themselves.
func _leave_victory() -> void:
	# The demo build (#361) follows the victory screen with its end card.
	if DemoBuildScript.is_active() and not _end_card_up and _lobby_screen != null:
		_end_card_up = true
		_end_card_until_msec = GameClockScript.now_msec() + int(end_card_sec * 1000.0)
		if _controller_server != null and _controller_server.has_method("clear_ready"):
			_controller_server.clear_ready()
		_lobby_screen.show_panel("end_card")
		return
	_end_card_up = false
	if _controller_server != null and _controller_server.has_method("clear_ready"):
		_controller_server.clear_ready()
	_enter_lobby()

## The host at the keyboard skips the wait (#337).
func _unhandled_key_input(event: InputEvent) -> void:
	if _state == State.VICTORY and event is InputEventKey and event.pressed and not event.echo:
		_leave_victory()

## Samples every living player's body contact for the Longest airtime award.
func _tick_airtime() -> void:
	var now: int = GameClockScript.now_msec()
	for slot: int in _in_round:
		var player: RigidBody2D = _players[slot] if slot < _players.size() else null
		if player == null or not player.alive:
			continue
		var head: Variant = player.get("_head")
		var touching: bool = player.get_contact_count() > 0 or (head != null and head.get_contact_count() > 0)
		_stats.note_air(slot, not touching, now)

func _enter_victory() -> void:
	_end_card_up = false
	_victory_until_msec = GameClockScript.now_msec() + int(victory_continue_sec * 1000.0)
	_end_final_ko()
	var victory_feed: Control = kill_feed()
	if victory_feed != null and victory_feed.has_method("clear_banners"):
		victory_feed.clear_banners() # nothing queued from the last round over victory (#613)
	_write_balance_log()
	send_telemetry()
	_play_lobby_music()
	_state = State.VICTORY
	_clear_stage()
	if _controller_server != null and _controller_server.has_method("clear_ready"):
		_controller_server.clear_ready()
	if _scoreboard != null:
		_scoreboard.visible = false
	_build_lobby_ui()
	_refresh_victory()
	_lobby_screen.show_panel("victory")
	_set_join_corner_visible(false)
	_last_lobby_state = {}
	_publish_lobby_state() # the phase first: Solo's host must Continue, and reads it (#522)
	_tick_lobby()

## Frees the last round's stage on the way into the lobby or the victory
## screen (#163), so its falling rocks and collapsing floors stop running --
## and making sounds -- behind them. The next round instances a fresh stage
## anyway. The rotation's `stage_index` is kept here, and only reset by
## `_begin_match()`.
func _clear_stage() -> void:
	if _current_stage != null:
		_current_stage.queue_free()
		_current_stage = null
	_stage_spawn_points = []

## The countdown ran out: fresh scores, everyone back to not-ready (so the
## victory screen's Continue needs tapping afresh), and the first round.
func _begin_match() -> void:
	_match_target = _requested_target()
	_match_stages.clear()
	_match_started_msec = GameClockScript.now_msec()
	_match_winner_slot = -1
	_last_winner_slot = -1
	_begin_team_match()
	for slot in _scores.size():
		_scores[slot] = 0
	# A fresh seed for a fresh match (#187), before anything draws from it.
	_seed_match(true)
	# A fresh bag for a fresh match (#163), dealt for its own player count,
	# from a rotation back at its start (#200): the bag it deals avoids the
	# stage just played, so a rematch that kept that would deal its seed a
	# different sequence than the same seed dealt at launch.
	_stage_rotation.new_bag()
	_stage_rotation.stage_index = -1
	_stage_rotation.pinned = -1
	_update_score_label()
	_ko_match_started()
	if _controller_server != null and _controller_server.has_method("clear_ready"):
		_controller_server.clear_ready()
	if _lobby_screen != null and _lobby_screen.panels_built():
		_lobby_screen.show_panel("")
	_set_join_corner_visible(false) # lobby only (#430)
	_state = State.WAITING
	_publish_lobby_state()
	_try_start_round()

func _tick_lobby() -> void:
	var roster: Array[int] = _roster()
	match _state:
		State.LOBBY:
			if _everyone_ready(roster) and _teams_can_start(roster):
				_state = State.COUNTDOWN
				_countdown_roster = roster.duplicate()
				_countdown_teams = _team_key(roster)
				_countdown_until_msec = GameClockScript.now_msec() + int(lobby_countdown_sec * 1000.0)
		State.COUNTDOWN:
			if roster != _countdown_roster or not _everyone_ready(roster) or _team_key(roster) != _countdown_teams:
				_state = State.LOBBY
			elif GameClockScript.now_msec() >= _countdown_until_msec:
				_begin_match()
				return
		State.VICTORY:
			var until_msec: int = _end_card_until_msec if _end_card_up else _victory_until_msec
			if _everyone_continued(roster) or roster.size() < min_players_to_start \
					or GameClockScript.now_msec() >= until_msec:
				_leave_victory()
				return
	var tick: int = _countdown_left() if _state == State.COUNTDOWN else 0
	if tick != _last_countdown_tick and tick > 0:
		countdown_ticked.emit(tick)
	_last_countdown_tick = tick
	_publish_lobby_state()

## The countdown second last announced by `countdown_ticked` (#152).
var _last_countdown_tick: int = 0

func _countdown_left() -> int:
	return maxi(1, ceili(float(_countdown_until_msec - GameClockScript.now_msec()) / 1000.0))

## Builds the state the phones and the lobby screen show, and pushes it out
## only when something in it changed.
func _publish_lobby_state() -> void:
	_lobby_published_msec = GameClockScript.now_msec()
	lobby_state_builds += 1
	var roster: Array[int] = _roster()
	var players: Array = []
	for slot: int in roster:
		# "color" (issue #151): a phone picking a colour changes the state, so
		# the lobby's swatches are redrawn in it.
		players.append({"slot": slot, "ready": _is_ready(slot), "name": _slot_name(slot),
			"color": _slot_color(slot).to_html(false)})
		var ping: int = _slot_ping(slot)
		if ping >= 0:
			players[-1]["ping"] = ping
	if _controller_server != null and _controller_server.has_method("pad_tip_pending"):
		for entry: Dictionary in players:
			entry["tip"] = _controller_server.pad_tip_pending(int(entry["slot"]))
	var in_lobby: bool = _state == State.LOBBY or _state == State.COUNTDOWN
	var state: Dictionary = {
		"phase": lobby_phase(),
		"host": _host_slot(),
		"target": _state_target(in_lobby),
		"players": players,
		"count": _countdown_left() if _state == State.COUNTDOWN else 0,
		"winner": _match_winner_slot,
		# Issue #121: what each phone needs to say where its player stands.
		"round": _round_number,
		"in_round": _in_round.duplicate(),
		"alive": _alive_slots(),
		"next": ceili(maxf(0.0, float(_pause_until_msec - GameClockScript.now_msec())) / 1000.0) if _state == State.ROUND_END else 0,
		# Issue #149: the host phone's menu offers Resume instead of Pause.
		"paused": _paused,
	}
	if _state_target_kind() != "first_to":  # only a mode with its own target adds the key (#544)
		state["target_kind"] = _state_target_kind()
	_add_team_state(state, roster, in_lobby)
	_add_game_mode_state(state, in_lobby)
	var picked_mode: String = game_mode
	if (in_lobby or _state == State.VICTORY) and _controller_server != null and _controller_server.has_method("game_mode"):
		picked_mode = str(_controller_server.game_mode())
	if picked_mode == GameModesScript.STOCK:  # the host phone's Stock controls (#354)
		var settings: RefCounted = HostSettingsScript.shared()
		state["stock"] = {
			"lives": settings.stock_lives, "time": settings.stock_time_limit,
			"stage": settings.stock_stage, "stages": _stage_rotation.picker_rows(),
		}
	if state == _last_lobby_state:
		return
	_last_lobby_state = state
	if _controller_server != null and _controller_server.has_method("set_lobby_state"):
		_controller_server.set_lobby_state(state)
	var panels: bool = _lobby_screen != null and _lobby_screen.panels_built()
	if panels and in_lobby:
		_lobby_screen.refresh_lobby(state, min_players_to_start, _controller_server)
	elif panels and _state == State.VICTORY:
		_refresh_victory()

## The podium: the match winner on the tallest block, then everyone else in
## the roster by final score, drawn by the lobby screen with the awards.
func _refresh_victory() -> void:
	var roster: Array[int] = _roster()
	var slots: Array[int] = []
	for slot in _players.size():
		if _players[slot] != null and (roster.has(slot) or slot == _match_winner_slot or (_team_mode and _teams.has(slot))):
			slots.append(slot)
	slots.sort_custom(podium_before)
	if _team_mode:
		_lobby_screen.refresh_victory(slots, _scores, -1, _all_awards(slots), _match_winner_team, _teams, _team_scores, _stats.stat_rows(slots))
		return
	_lobby_screen.refresh_victory(slots, _scores, _match_winner_slot, _all_awards(slots), -1, {}, PackedInt32Array(), _stats.stat_rows(slots))

## The core awards plus the extra superlatives (issue #325).
func _all_awards(slots: Array[int]) -> Array[Dictionary]:
	var out: Array[Dictionary] = _stats.awards(slots)
	out.append_array(_stats.extra_awards(slots))
	out.append_array(_stats.mode_awards(slots, game_mode))
	return out

## The podium's order: whether slot `a` stands before slot `b`. The match
## winner first, then by final score. Strict (#200): never true both ways,
## nor for a slot against itself, as `sort_custom()` needs.
func podium_before(a: int, b: int) -> bool:
	if _team_mode:
		return _team_podium_before(a, b)
	if a == _match_winner_slot or b == _match_winner_slot:
		return a == _match_winner_slot and b != _match_winner_slot
	return _scores[a] > _scores[b]

## The lobby screen, built (and added under this node) the first time
## anything on it is needed.
func _screen() -> CanvasLayer:
	if _lobby_screen == null:
		_lobby_screen = LobbyScreenScript.new(_slot_name, _slot_color)
		add_child(_lobby_screen)
	return _lobby_screen

func _build_lobby_ui() -> void:
	_screen().build_panels()
	_lobby_screen.attach_controls(_controller_server)

## The in-round join corner (issue #230) is hidden while the lobby, countdown
## or victory screen is up -- they show their own big QR and URL, and the
## small one bled through their backdrop -- and back for the rounds.
func _set_join_corner_visible(on: bool) -> void:
	if _controller_server != null and _controller_server.has_method("set_join_corner_visible"):
		_controller_server.set_join_corner_visible(on)

# --- Stage title card (issue #120) -------------------------------------------
#
# The stage's name sweeps across the screen for about a second at every round
# start, below the modifier banner so the two never overlap. Drawn by
# `LobbyScreen.gd` (#175).

## The title card label, or null before any round has started.
func stage_title_label() -> Label:
	return _lobby_screen.stage_title_label() if _lobby_screen != null else null

## The mode line under the stage title: the mode's name and its rule (#352).
func stage_title_rule_label() -> Label:
	return _lobby_screen.stage_title_rule_label() if _lobby_screen != null else null

## Name of the stage in play, or "" in the lobby (issue #262, feedback context).
func current_stage_name() -> String:
	return str(_current_stage.name) if _current_stage != null else ""

## The stage's on-screen name: its translated name, or its node name when no
## translation is catalogued (a stage added without a row).
func _stage_display_name(stage_name: String) -> String:
	var key: String = "STAGE_" + stage_name.to_upper()
	var shown: String = tr(key)
	return stage_name.to_upper() if shown == key else shown.to_upper()

func _show_stage_title() -> void:
	if _current_stage == null or stage_title_sec <= 0.0:
		return
	_screen().show_stage_title(_stage_display_name(str(_current_stage.name)), stage_title_sec,
		"%s: %s" % [GameModesScript.display_name(game_mode), GameModesScript.status_line(game_mode)])

# --- Nicknames in play (issue #121, always on since #151) --------------------
#
# Every living player carries its phone's nickname ("P3" without one) above
# its head, in its colour -- whatever the round loop is doing, lobby or not.
# The tags themselves are `NameTags.gd` (#175), a child this node builds on
# its first frame and lays out at the top of every `_process`.

var _round_number: int = 0
## The slots the current (or last) round spawned, in slot order.
var _in_round: Array[int] = []
var _name_tags: Node2D

## A slot's name tag, or null before the first frame has built them.
func name_tag(slot: int) -> Label:
	return _name_tags.name_tag(slot) if _name_tags != null else null

## Slots still standing: alive, or waiting to respawn in Stock (#354).
func _alive_slots() -> Array[int]:
	var alive: Array[int] = []
	var stock: bool = _game_mode_node != null and _game_mode_node.has_method("is_pending")
	for slot in _players.size():
		if _players[slot] != null and (_players[slot].alive or (stock and _game_mode_node.is_pending(slot))):
			alive.append(slot)
	return alive

func _tick_name_tags() -> void:
	if _name_tags == null:
		_name_tags = NameTagsScript.new(_players, _slot_name, _slot_color)
		_name_tags.lives_of = lives_of
		add_child(_name_tags)
		_name_tags.build()
	_name_tags.tick()

# --- Host phone controls and how to play (issue #149) --------------------------
#
# The host phone's hidden menu (controller/index.html) sends Pause/Resume, End
# match and Kick player; ControllerServer lets only the host's requests through
# as `host_command`, and they are acted on here. Pause freezes the whole scene
# tree except ControllerServer (which must keep hearing the phones) and this
# node's pause banner. Every deadline this node keeps is game time
# (`GameClock.gd`, #182), which stops with the tree, so nothing expires
# during a pause and nothing needs pushing back after it.
#
# The lobby screen -- the shared screen, not the phones -- carries a short
# how-to-play panel.

var _paused: bool = false

## The how-to-play panel's mode cards, one per game mode (#352).
func how_to_play_mode_cards() -> Array[Label]:
	return _lobby_screen.mode_cards() if _lobby_screen != null else []

## The lobby's how-to-play panel, or null before the lobby was ever shown.
func how_to_play_panel() -> Control:
	return _lobby_screen.how_to_play_panel() if _lobby_screen != null else null

## Whether the host phone has the match paused.
func is_paused() -> bool:
	return _paused

## The PAUSED banner, or null before the first pause.
func pause_label() -> Label:
	return _lobby_screen.pause_label() if _lobby_screen != null else null

## Whether a match is under way: what Pause and End match act on.
func _in_match() -> bool:
	return lobby_enabled and (_state == State.ROUND_ACTIVE or _state == State.ROUND_END or _state == State.WAITING)

func _on_host_command(cmd: String, slot: int) -> void:
	match cmd:
		"pause":
			if _in_match() and not _paused:
				_pause_match()
		"resume":
			if _paused:
				_resume_match()
		"end":
			if _in_match():
				_end_match()
		"kick":
			# Issue #193: a round a kick ends -- the last opponent kicked --
			# is won by nobody. The next `_check_round_end()` reads this.
			if _state == State.ROUND_ACTIVE:
				_kicked_this_round_check = true
			# Already out of the roster; out of the round too, without a death.
			if slot >= 0 and slot < _players.size() and _players[slot] != null and _players[slot].alive:
				_players[slot].leave_round()
			# Issue #570: a kicked player's shots in flight go with them.
			if slot >= 0 and slot < _players.size() and _players[slot] != null:
				_players[slot].clear_shots()
			# Issue #521: a kicked Stock player still waiting to respawn is out
			# now, not when the timer runs down, or the survivor scores.
			if _game_mode_node != null and _game_mode_node.has_method("cancel_respawn"):
				_game_mode_node.cancel_respawn(slot)
			if lobby_enabled:
				_publish_lobby_state()

func _pause_match() -> void:
	_paused = true
	_set_tree_paused(true)
	_show_pause_banner(true)
	_publish_lobby_state()

func _resume_match() -> void:
	_paused = false
	_set_tree_paused(false)
	_show_pause_banner(false)
	_publish_lobby_state()

## The host phone ended the match early: the round in progress is wound down
## with no winner and the room goes back to the lobby.
func _end_match() -> void:
	if _paused:
		_paused = false
		_set_tree_paused(false)
		_show_pause_banner(false)
	for player: Variant in _players:
		if player != null and player.alive:
			player.leave_round()
	_pickup_director.clear()
	_stop_kill_zone_rise()
	_end_round_modifier()
	_end_spawn_protection()
	_last_winner_slot = -1
	_team_keep_weapon.clear()
	if _controller_server != null and _controller_server.has_method("clear_ready"):
		_controller_server.clear_ready()
	_enter_lobby()

func _set_tree_paused(on: bool) -> void:
	if is_inside_tree():
		get_tree().paused = on

func _show_pause_banner(on: bool) -> void:
	if _lobby_screen == null and not on:
		return
	_screen().show_pause_banner(on)

# --- Host changes, solo bots, lobby publishing (issue #165) --------------------
#
# The host phone dropping hands its menu to the next phone at once, even while
# paused: ControllerServer's `host_changed` republishes the lobby state, which
# otherwise only goes out from `_process` and so stops with the tree. Solo
# practice bots never make a ready room on their own. Mid-round the full lobby
# state is built only when a cheap key of what changes in a round (the roster,
# who is alive, the host, the round) has changed, and otherwise at most every
# LOBBY_REFRESH_MSEC, not every frame.

## Mid-round, the longest the phones wait for a change outside the key (a
## nickname, a colour).
const LOBBY_REFRESH_MSEC: int = 250
var _lobby_published_msec: int = 0
var _lobby_key: Array = []
## How many times the lobby state has been built, for the scenarios.
var lobby_state_builds: int = 0

func _watch_for_lobby_changes() -> void:
	if _controller_server != null and _controller_server.has_signal("host_changed"):
		_controller_server.connect("host_changed", _on_host_changed)

func _lobby_publish_due() -> bool:
	var key: Array = [_roster(), _alive_slots(), _host_slot(), _round_number]
	if key != _lobby_key:
		_lobby_key = key
		return true
	return GameClockScript.now_msec() - _lobby_published_msec >= LOBBY_REFRESH_MSEC

func _on_host_changed(_slot: int) -> void:
	if lobby_enabled:
		_publish_lobby_state()

## Whether `roster` is only bots waiting for a human: no phone or host seat in
## it is connected, and the bots came from Solo practice or the host's bot
## counter (#505), not from `--bots=N`.
func _bots_waiting_for_a_human(roster: Array[int]) -> bool:
	var director: Variant = _controller_server.get("bot_director") if _controller_server != null else null
	if director == null or not director.has_method("needs_a_human"):
		return false
	if not director.needs_a_human() and not bool(director.get("counter_seated")):
		return false
	for slot: int in roster:
		if not _controller_server.is_virtual(slot) and _controller_server.slot_has_controller(slot):
			return false
	return true

# --- Teams mode (issue #236, ADR-0018) -------------------------------------------
#
# The host phone picks Free-for-all (the default) or Teams in the lobby; the
# mode is fixed for a whole match when its countdown runs out. In a Teams
# match every player is on Red or Blue: each phone's own pick, then everyone
# else balanced onto the smaller team, phones before bots (`Teams.assign()`).
# A countdown needs both teams manned, and a changed pick or mode cancels it.
# A round is won by the team with anyone left standing, and scores that team
# a point; the match is first to the host's "first to N" in team points. The
# winning team's survivors keep their weapons, as a lone winner does.
#
# Friendly fire is off where every weapon hit lands, `Player.is_teammate()`;
# this node only sets each player's `team` at round start (-1 in a
# free-for-all, so a free-for-all plays exactly as it always has). Hazards and
# the lava hurt everyone. The kill feed, KO credit and awards stay per player.

## The current match's mode, fixed at its start: true for a Teams match.
var _team_mode: bool = false
## slot -> team (0 red, 1 blue) for the current Teams match, kept across its
## rounds; a player new to the match is balanced in at the next round start.
var _teams: Dictionary = {}
## Team round wins this match, [red, blue].
var _team_scores: PackedInt32Array = PackedInt32Array([0, 0])
## The team that won the match, or -1.
var _match_winner_team: int = -1
## The team that took the last round, or -1.
var _last_winner_team: int = -1
## The last round's winning survivors: they keep their weapons into the next.
var _team_keep_weapon: Array[int] = []
## The #163 frame race for teams: the one team left standing, recorded the
## moment an elimination leaves only it, or -1.
var _survivor_team: int = -1
## The team picture a countdown started on: [mode, assignment].
var _countdown_teams: Array = []

## Whether the current match (or, between matches, the last one) is Teams.
func team_mode() -> bool:
	return _team_mode

## `slot`'s team in the current Teams match, or -1.
func team_of(slot: int) -> int:
	return int(_teams.get(slot, TeamsScript.NONE)) if _team_mode else TeamsScript.NONE

## `team`'s round wins this match.
func team_score(team: int) -> int:
	return _team_scores[team] if team >= 0 and team < TeamsScript.COUNT else 0

## The team that won the match the victory screen is showing, or -1.
func match_winner_team() -> int:
	return _match_winner_team

## Whether the host phone has chosen Teams for the next match.
func _requested_team_mode() -> bool:
	return _controller_server != null and _controller_server.has_method("team_mode") and bool(_controller_server.team_mode())

## Who would be on which team if the match started now: the phones' picks,
## the rest balanced (`Teams.assign()`).
func _lobby_teams(roster: Array[int]) -> Dictionary:
	var picks: Dictionary = {}
	var bots: Array[int] = []
	for slot: int in roster:
		if _controller_server.has_method("slot_team_pick"):
			var pick: int = int(_controller_server.slot_team_pick(slot))
			if pick != TeamsScript.NONE:
				picks[slot] = pick
		if _controller_server.has_method("is_virtual") and _controller_server.is_virtual(slot):
			bots.append(slot)
	return TeamsScript.assign(roster, picks, bots)

## A lobby may count down: always in a free-for-all, and in Teams only with
## somebody on each team.
func _teams_can_start(roster: Array[int]) -> bool:
	return not _requested_team_mode() or TeamsScript.both_manned(_lobby_teams(roster))

## What a countdown is cancelled by changing: the mode, and who is on which team.
func _team_key(roster: Array[int]) -> Array:
	var on: bool = _requested_team_mode()
	return [on, _lobby_teams(roster) if on else {}]

## The countdown ran out: fix the mode and the teams for the whole match.
func _begin_team_match() -> void:
	_team_mode = lobby_enabled and _requested_team_mode()
	_latch_game_mode()
	_teams = _lobby_teams(_roster()) if _team_mode else {}
	_team_scores = PackedInt32Array([0, 0])
	_match_winner_team = -1
	_last_winner_team = -1
	_team_keep_weapon.clear()
	_survivor_team = -1

## Every player's `team` for the round about to start: its team in a Teams
## match -- anyone not on one yet (a mid-match joiner) is balanced onto the
## smaller team first -- and -1 for everyone in a free-for-all.
func _apply_teams(entering: Array[int]) -> void:
	if _team_mode:
		var bots: Array[int] = []
		for slot: int in entering:
			if _controller_server.has_method("is_virtual") and _controller_server.is_virtual(slot):
				bots.append(slot)
		_teams = TeamsScript.assign(entering, {}, bots, _teams)
	for slot in _players.size():
		var player: Variant = _players[slot]
		if player != null and "team" in player:
			player.team = int(_teams.get(slot, TeamsScript.NONE)) if _team_mode else TeamsScript.NONE

## The distinct teams among `slots`, Red first.
func _teams_of(slots: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for team in TeamsScript.COUNT:
		for slot: int in slots:
			if int(_teams.get(slot, TeamsScript.NONE)) == team:
				out.append(team)
				break
	return out

## `_on_eliminated_check_survivor()` for a Teams round (#163): the moment an
## elimination leaves one team standing it is recorded, so that team still
## wins if its last survivors fall on a later tick of the same frame. If they
## fall on the very tick it was recorded, the teams went down together: a draw.
func _check_team_survivor() -> void:
	var frame: int = Engine.get_physics_frames()
	var standing: Array[int] = _teams_of(_alive_slots())
	if standing.size() == 1:
		if _survivor_team == -1:
			_survivor_team = standing[0]
			_survivor_frame = frame
	elif standing.is_empty() and _survivor_team != -1 and frame == _survivor_frame:
		_survivor_team = -1

## `_check_round_end()` for a Teams round: it ends once the players still
## standing are all on one team (or none are), and that team scores. An
## abandoned round and a round a kick decided (#193) are won by nobody, as in
## a free-for-all.
func _check_team_round_end(after_kick: bool) -> void:
	_flush_kos()
	var alive_slots: Array[int] = _alive_slots()
	var standing: Array[int] = _teams_of(alive_slots)
	var winner_team: int = -1
	if standing.size() > 1:
		if not _round_abandoned(alive_slots):
			return
	elif standing.size() == 1:
		winner_team = standing[0]
	elif _survivor_team != -1:
		winner_team = _survivor_team
	_survivor_team = -1
	if after_kick:
		winner_team = -1
	var winners: Array[int] = []
	for slot: int in alive_slots:
		if int(_teams.get(slot, TeamsScript.NONE)) == winner_team:
			winners.append(slot)
	if winner_team != -1:
		_team_scores[winner_team] += 1
		for slot: int in winners:
			_buzz(slot, "win")
		round_won.emit(winners[0] if not winners.is_empty() else -1)
		team_round_won.emit(winner_team)
	var team_point: Vector2 = _players[winners[0]].global_position if not winners.is_empty() else Vector2.ZERO
	for slot: int in alive_slots:
		if _players[slot].alive:
			_players[slot].leave_round()
	_update_score_label()
	_last_winner_slot = -1
	_last_winner_team = winner_team
	_team_keep_weapon = winners
	if winner_team != -1 and lobby_enabled and _team_scores[winner_team] >= _match_target:
		_match_winner_team = winner_team
		_start_final_ko(team_point)
		team_match_won.emit(winner_team)
	_pickup_director.clear()
	_stop_kill_zone_rise()
	_end_round_modifier()
	_ko_round_ended(-1)
	_show_scoreboard()
	_clear_all_shots()
	_state = State.ROUND_END
	_pause_until_msec = GameClockScript.now_msec() + int(round_end_pause_sec * 1000.0)
	if lobby_enabled:
		_publish_lobby_state()

## A Teams scoreboard entry: the player's team's points, and its name tagged
## with the team, in the team's colour.
func _team_scoreboard_entry(slot: int, score_label: Label, name_label: Label) -> void:
	var team: int = team_of(slot)
	if score_label != null:
		score_label.text = str(team_score(team))
	if name_label != null:
		name_label.text = "%s  %s" % [_slot_name(slot), TeamsScript.team_name(team)]
		name_label.add_theme_color_override("font_color", TeamsScript.team_color(team))

## The podium's order in a Teams match: the winning team first, then Red
## before Blue, then by slot. Strict, as `sort_custom()` needs.
func _team_podium_before(a: int, b: int) -> bool:
	var ta: int = team_of(a)
	var tb: int = team_of(b)
	var wa: bool = ta == _match_winner_team and _match_winner_team != -1
	var wb: bool = tb == _match_winner_team and _match_winner_team != -1
	if wa != wb:
		return wa
	if ta != tb:
		return ta >= 0 and (tb < 0 or ta < tb)
	return a < b

## The lobby state's Teams fields, only while Teams is chosen or being
## played, so a free-for-all's state is exactly what it always was: "mode"
## "teams" while the host has Teams chosen (for the host menu), "teams" while
## the rosters are shown as teams, each player entry's "team" (and in the
## lobby its phone's "pick"), the team points and the winning team.
func _add_team_state(state: Dictionary, roster: Array[int], in_lobby: bool) -> void:
	var requested: bool = _requested_team_mode()
	if requested:
		state["mode"] = "teams"
	# The lobby shows the mode chosen for the next match; a match, and the
	# victory screen after it, the mode it was played in.
	var showing: bool = requested if in_lobby else _team_mode
	if not showing:
		return
	var teams: Dictionary = _lobby_teams(roster) if in_lobby else _teams
	for entry: Dictionary in state["players"]:
		var slot: int = int(entry["slot"])
		entry["team"] = int(teams.get(slot, TeamsScript.NONE))
		if in_lobby and _controller_server.has_method("slot_team_pick"):
			entry["pick"] = int(_controller_server.slot_team_pick(slot))
	state["teams"] = true
	state["team_scores"] = [_team_scores[TeamsScript.RED], _team_scores[TeamsScript.BLUE]]
	state["winner_team"] = _match_winner_team

# --- Kill feed, KO credit and match awards (issue #148) ------------------------
#
# `MatchStats.gd` keeps the match's numbers and decides who gets each KO: the
# last player to hit the victim within 3 s, otherwise a self-KO. That holds for
# a hazard (spikes, saws, lava, kill zone) death too, since those report on the
# victim's own `strike_landed` and never overwrite the last hitter (#311). `KillFeed.gd`
# (the HUD node at `kill_feed_path`) shows each KO top right and a banner for
# the big moments. The victory screen gets up to three awards under the podium.

const MatchStatsScript := preload("res://scripts/MatchStats.gd")

var _stats: RefCounted = MatchStatsScript.new()
## Eliminations not yet credited, as [slot, msec]: `Player.eliminate()` emits
## `eliminated` before the lethal strike's `strike_landed`, so crediting waits
## for the end of the frame (or the next round-end check) to see that strike.
var _pending_kos: Array = []

func match_stats() -> RefCounted:
	return _stats

func kill_feed() -> Control:
	return get_node_or_null(kill_feed_path) as Control

## The victory screen's awards row, or null before any.
func awards_row() -> Control:
	return _lobby_screen.awards_row() if _lobby_screen != null else null

## Stages played this match and when it began (game clock), for the anonymous
## match record (issue #372).
var _match_stages: Array[String] = []
var _match_started_msec: int = 0
## Where the record goes; empty means the game's configured relay.
var telemetry_relay_url: String = ""

## Sends this match's anonymous record to the relay (issue #372), fire and
## forget. Returns whether a send started: false with sharing off, in a scripted
## or `--bots` run, or when no real player landed a damaging hit.
func send_telemetry() -> bool:
	var host: RefCounted = HostSettingsScript.shared()
	if not StatsSenderScript.should_send(host, StatsSenderScript.is_scripted(get_tree(), PackedStringArray()), OS.get_cmdline_user_args()):
		return false
	var winners: Array = []
	if _team_mode:
		for slot: int in _teams:
			if int(_teams[slot]) == _match_winner_team:
				winners.append(slot)
	elif _match_winner_slot != -1:
		winners.append(_match_winner_slot)
	var length_sec: int = maxi(0, GameClockScript.now_msec() - _match_started_msec) / 1000
	var record: Dictionary = StatsSenderScript.build_record(_stats, game_mode, _match_stages, "teams" if _team_mode else "ffa", length_sec, winners)
	if record.is_empty():
		return false
	var url: String = telemetry_relay_url
	if url.is_empty():
		url = preload("res://scripts/ControllerServer.gd").resolve_relay_url(OS.get_cmdline_user_args())
	var sender: Node = StatsSenderScript.new()
	sender.finished.connect(func(_status: int) -> void: sender.queue_free())
	add_child(sender)
	sender.send(record, url)
	return true

## Where the per-match balance tallies are appended (issue #316).
var balance_log_path: String = "user://balance_stats.jsonl"

## The local balance log, only with stats sharing on (#609).
func _write_balance_log() -> bool:
	if not HostSettingsScript.shared().share_stats:
		return false
	return _stats.append_line(balance_log_path, _stats.balance_log_line(int(Time.get_unix_time_from_system())))

func _ko_record_hit(victim: Node, amount: float, attacker_slot: int) -> void:
	var victim_slot: int = _players.find(victim)
	# Issue #311: a teammate never earns the KO for a teammate's death.
	if _team_mode and attacker_slot >= 0 and victim_slot >= 0 and attacker_slot != victim_slot and team_of(attacker_slot) == team_of(victim_slot):
		return
	var weapon: String = ""
	var real: bool = true
	if amount > 0.0 and attacker_slot >= 0 and attacker_slot < _players.size() and _players[attacker_slot] != null:
		var stats: Variant = _players[attacker_slot].get("weapon_stats")
		if stats != null and stats.resource_path != "":
			weapon = stats.resource_path.get_file().get_basename()
		# Issue #516: an in-flight shot is credited to the weapon that fired it.
		var fired_with: Variant = _players[attacker_slot].get("hit_weapon_id")
		if fired_with is String and fired_with != "":
			weapon = fired_with
		real = not (_controller_server != null and _controller_server.has_method("is_virtual") and _controller_server.is_virtual(attacker_slot))
	_stats.record_hit(attacker_slot, victim_slot, amount, GameClockScript.now_msec(), weapon, real)

func _on_weapon_picked_up(weapon_name: String, slot: int) -> void:
	_stats.record_pickup(slot, weapon_name)

func _on_ko_eliminated(slot: int) -> void:
	# A mode's scripted win eliminates the losers; that is a score, not a KO (#521).
	if mode_won():
		return
	if _pending_kos.is_empty():
		_flush_kos.call_deferred()
	_pending_kos.append([slot, GameClockScript.now_msec()])

func _flush_kos() -> void:
	var pending: Array = _pending_kos
	_pending_kos = []
	var feed: Control = kill_feed()
	for entry: Array in pending:
		var ko: Dictionary = _stats.record_elimination(entry[0], entry[1])
		if feed == null:
			continue
		var victim: int = ko["victim"]
		var killer: int = ko["killer"]
		if killer == -1:
			feed.push_ko("", Color.WHITE, _slot_name(victim), _slot_color(victim))
			continue
		feed.push_ko(_slot_name(killer), _slot_color(killer), _slot_name(victim), _slot_color(victim))
		var streak: int = ko["streak"]
		if streak >= 2:
			feed.show_banner([tr("BANNER_DOUBLE_KO"), tr("BANNER_TRIPLE_KO")][streak - 2] if streak <= 3 else tr("BANNER_MULTI_KO"), _slot_name(killer), _slot_color(killer))
		elif ko["first_blood"]:
			feed.show_banner(tr("BANNER_FIRST_BLOOD"), _slot_name(killer), _slot_color(killer))

func _ko_match_started() -> void:
	_stats.begin_match()
	_stats.tie_seed = match_seed_value() # full award ties break by the match seed (#613)
	_pending_kos.clear()
	var feed: Control = kill_feed()
	if feed != null:
		feed.clear()

## A fresh phone (or bot) claimed `slot` (issue #161). The slot may be one a
## drop-out's expired claim or a kick freed mid-match: the newcomer starts on
## no points and none of the old occupant's KOs, deaths or awards.
func _on_slot_claimed_fresh(slot: int) -> void:
	if slot < 0 or slot >= _scores.size():
		return
	_scores[slot] = 0
	# Issue #236: a newcomer in a freed slot is balanced onto a team afresh at
	# the next round start, and never keeps the old occupant's weapon.
	_teams.erase(slot)
	_team_keep_weapon.erase(slot)
	# Issue #510: nor the old occupant's round win (the weapon it keeps into the
	# next round) or match win.
	if _last_winner_slot == slot:
		_last_winner_slot = -1
	if _match_winner_slot == slot:
		_match_winner_slot = -1
	_stats.forget_slot(slot)
	_pending_kos = _pending_kos.filter(func(entry: Array) -> bool: return entry[0] != slot)
	_update_score_label()

## True once the round's mode has scored its win. That ends the round by
## eliminating the losers, which is a score, not a KO (#521, #613).
func mode_won() -> bool:
	return _game_mode_node != null and _game_mode_node.has_method("is_won") and _game_mode_node.is_won()

func _ko_round_started() -> void:
	_pending_kos.clear()
	var stale_feed: Control = kill_feed()
	if stale_feed != null and stale_feed.has_method("clear_banners"):
		stale_feed.clear_banners() # a late banner must not land in this round (#613)
	_stats.begin_round(_in_round, GameClockScript.now_msec())

## A round won by the last of three or more is a big moment; one of two
## winning speaks for itself on the scoreboard.
func _ko_round_ended(winner_slot: int) -> void:
	_stats.end_round(GameClockScript.now_msec())
	var feed: Control = kill_feed()
	if _team_mode:
		if feed != null and _last_winner_team != -1:
			feed.show_banner(tr("BANNER_TEAM_WINS") % TeamsScript.team_name(_last_winner_team),
				tr("BANNER_TEAM_SCORE") % [_team_scores[TeamsScript.RED], _team_scores[TeamsScript.BLUE]],
				TeamsScript.team_color(_last_winner_team))
		return
	if feed != null and winner_slot != -1 and _in_round.size() >= 3 and not mode_won():
		feed.show_banner(tr("BANNER_LAST_ONE_STANDING"), _slot_name(winner_slot), _slot_color(winner_slot))

# --- Match seed (issue #187) ---------------------------------------------------
#
# One seed per match; every gameplay RNG is a stream derived from it with
# `hash([seed, name])`, so a stream's draws never depend on how many times
# another one drew. Cosmetic-only randomness -- Juice's dust and sparks, the
# death burst's shards, the stage backdrops (already fixed-seeded) -- is left
# alone: none of it touches a body. The hit-sound jitter is cosmetic too but
# is seeded anyway, so a replay's sound log matches as well.

const SEED_FLAG: String = "--seed="

## The seed the current match runs on, or -1 before one is picked.
var _match_seed: int = -1
## `--random-weapons`' draw.
var _playtest_weapon_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Which way round the spawns are handed out each round (#200).
var _spawn_rng: RandomNumberGenerator = RandomNumberGenerator.new()

## The seed the current match runs on; picked now if none has been yet (a
## RoundManager driven by hand, outside the tree).
func match_seed_value() -> int:
	if _match_seed == -1:
		_seed_match(false)
	return _match_seed

## A fresh generator for the stream `stream_name` of the current match seed.
func rng_for(stream_name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([match_seed_value(), stream_name])
	return rng

## `rng_for(stream_name)` made once per match and handed out again after, so a
## node made afresh each round (a game mode) keeps drawing from one stream
## instead of repeating its first draw every round. `_seed_match` clears these.
var _match_rngs: Dictionary = {}
func match_rng(stream_name: String) -> RandomNumberGenerator:
	match_seed_value()
	if not _match_rngs.has(stream_name):
		_match_rngs[stream_name] = rng_for(stream_name)
	return _match_rngs[stream_name]

## The N in `--seed=N` among `args`, or -1 without it (or with junk).
static func seed_from_args(args: PackedStringArray) -> int:
	var found: int = -1
	for arg: String in args:
		if arg.begins_with(SEED_FLAG) and arg.trim_prefix(SEED_FLAG).is_valid_int():
			found = arg.trim_prefix(SEED_FLAG).to_int()
	return found

## Match start: settle the seed (`match_seed`, else `--seed=N`, else
## `randi()`), give every subsystem its stream, and, with `announce`, log it
## in one line so a playtest bug can be replayed.
func _seed_match(announce: bool) -> void:
	var seed_value: int = match_seed
	if seed_value == -1:
		seed_value = seed_from_args(OS.get_cmdline_user_args())
	if seed_value == -1:
		seed_value = randi()
	_match_seed = seed_value
	_match_rngs.clear()
	var stages: RandomNumberGenerator = rng_for("stages")
	if rotation_seed != -1:
		stages.seed = rotation_seed
	_stage_rotation.rng = stages
	_pickup_director.rng = rng_for("pickups")
	_playtest_weapon_rng = rng_for("playtest_weapons")
	_spawn_rng = rng_for("spawns")
	# Remade on first use, from `modifier_seed` or this seed (`modifier_rng()`).
	_modifier_rng = null
	var director: Variant = _controller_server.get("bot_director") if _controller_server != null else null
	if director != null and director.has_method("seed_bots"):
		director.seed_bots(hash([seed_value, "bots"]))
	var sfx: Node = get_node_or_null("/root/Sfx") if is_inside_tree() else null
	if sfx != null and sfx.has_method("reseed"):
		sfx.reseed(hash([seed_value, "sfx"]))
	if announce:
		print("RoundManager: match seed %d (replay with -- --seed=%d)" % [seed_value, seed_value])

# --- Game modes (issues #276-#278) -------------------------------------------------
# An optional rules layer over each round (`GameModes.gd`): King of the Hill,
# Sudden Death or Hot Potato. "" (the default) is the classic round. The mode
# node lives under this manager for one round and is torn down wherever the
# round's modifier is (`_end_round_modifier()`), so it never leaks into the next.

const GameModesScript := preload("res://scripts/GameModes.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")
const DemoBuildScript := preload("res://scripts/DemoBuild.gd")
## A `GameModes` id every round plays under, or "" for none. Host-set seam.
@export var game_mode: String = ""
var _game_mode_node: Node = null

## The id of the mode on the current round, or "" for none.
func active_game_mode_id() -> String:
	return game_mode if _game_mode_node != null else ""

## The current round's mode node, or null.
func game_mode_node() -> Node:
	return _game_mode_node

func _start_game_mode() -> void:
	_end_game_mode()
	_game_mode_node = GameModesScript.create(game_mode)
	if _game_mode_node == null:
		if game_mode != "":
			push_warning("RoundManager: unknown game mode '%s'" % game_mode)
		return
	add_child(_game_mode_node)
	_game_mode_node.setup(self)
	_game_mode_node.start_round(_in_round.duplicate())

## A Stock match plays one stage (#375): the host's pick, or a random enabled
## one, resolved on the match's first round and held for the rest. Any other
## mode keeps the rotation.
func _pin_stock_stage() -> void:
	if game_mode != GameModesScript.STOCK:
		_stage_rotation.pinned = -1
	elif _stage_rotation.pinned == -1:
		_stage_rotation.round_player_count = _roster().size()
		_stage_rotation.pinned = _stage_rotation.resolve_pin(HostSettingsScript.shared().stock_stage)

## The host phone's pick for the next match (issue #352), taken as the match's
## countdown runs out and held for all of it. Only a lobby match takes it, so a
## `game_mode` set directly (the scenario seam) is left alone.
func _latch_game_mode() -> void:
	if not lobby_enabled or _controller_server == null or not _controller_server.has_method("game_mode"):
		return
	var picked: String = str(_controller_server.game_mode())
	if not GameModesScript.fits_format(picked, _team_mode):
		picked = GameModesScript.CLASSIC
	game_mode = picked

## The lobby state's game-mode fields: the choice, and the picker's rows
## (from `GameModes.TABLE`) while the host can still change it.
func _add_game_mode_state(state: Dictionary, in_lobby: bool) -> void:
	if _controller_server == null or not _controller_server.has_method("game_mode"):
		return
	var shown: String = str(_controller_server.game_mode()) if in_lobby or _state == State.VICTORY else game_mode
	if shown != GameModesScript.CLASSIC:
		state["game_mode"] = shown
	if in_lobby or _state == State.VICTORY:
		state["game_modes"] = GameModesScript.picker_rows()
## A phone's "Steal a life" (Stock in Teams, #354).
func _on_steal_requested(slot: int) -> void:
	if _game_mode_node != null and _game_mode_node.has_method("steal_life"):
		_game_mode_node.steal_life(slot)

## `slot`'s lives for its name tag's pips, or -1 outside Stock.
func lives_of(slot: int) -> int:
	if _game_mode_node != null and _game_mode_node.has_method("lives_of"):
		return _game_mode_node.lives_of(slot)
	return -1

func _end_game_mode() -> void:
	if _game_mode_node != null:
		# The mode's per-round numbers go into the match's stats (#355).
		if _game_mode_node.has_method("report_stats"):
			_game_mode_node.report_stats(_stats)
		_game_mode_node.end_round()
		_game_mode_node.queue_free()
		_game_mode_node = null

# --- Final-KO slow motion (#328) ---
# The KO that wins the match plays a beat of slow motion with the camera
# punched in on the hit, while the announcer calls the winner (Announcer
# listens to match_won). It runs on game time (GameClock), which moves at
# Engine.time_scale, so it lasts FINAL_KO_GAME_MSEC / FINAL_KO_TIME_SCALE of
# real time (about 1 s) and ends before the victory panel (#325) is entered.
const FINAL_KO_TIME_SCALE: float = 0.3
const FINAL_KO_GAME_MSEC: int = 300
const FINAL_KO_ZOOM_FACTOR: float = 1.5
const FINAL_KO_FLASH_ALPHA: float = 0.45

var _last_lethal_point: Vector2 = Vector2.ZERO
var _has_lethal_point: bool = false
var _final_ko_active: bool = false
var _final_ko_end_msec: int = 0
var _final_ko_scale_was: float = 1.0
var _final_ko_camera: Camera2D = null
var _final_ko_zoom_was: Vector2 = Vector2.ONE
var _final_ko_pos_was: Vector2 = Vector2.ZERO
var _final_ko_flash: CanvasLayer = null

func _start_final_ko(fallback_point: Vector2) -> void:
	if _final_ko_active:
		return
	var point: Vector2 = _last_lethal_point if _has_lethal_point else fallback_point
	_has_lethal_point = false
	_final_ko_active = true
	_final_ko_end_msec = GameClockScript.now_msec() + FINAL_KO_GAME_MSEC
	_final_ko_scale_was = Engine.time_scale
	Engine.time_scale = FINAL_KO_TIME_SCALE
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx == null or bool(sfx.get("screen_shake")):
		var camera: Camera2D = get_node_or_null(camera_path) as Camera2D if not camera_path.is_empty() else null
		if camera != null:
			_final_ko_camera = camera
			_final_ko_zoom_was = camera.zoom
			_final_ko_pos_was = camera.global_position
			camera.zoom = camera.zoom * FINAL_KO_ZOOM_FACTOR
			camera.global_position = point
	if sfx == null or not bool(sfx.get("reduce_flash")):
		_final_ko_flash = CanvasLayer.new()
		_final_ko_flash.layer = 50
		var rect := ColorRect.new()
		rect.color = Color(1, 1, 1, FINAL_KO_FLASH_ALPHA)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_final_ko_flash.add_child(rect)
		add_child(_final_ko_flash)

func _tick_final_ko() -> void:
	if _final_ko_active and GameClockScript.now_msec() >= _final_ko_end_msec:
		_end_final_ko()

## Puts the time scale, the camera and the flash back. Safe to call any time.
func _end_final_ko() -> void:
	if not _final_ko_active:
		return
	_final_ko_active = false
	Engine.time_scale = _final_ko_scale_was
	if is_instance_valid(_final_ko_camera):
		_final_ko_camera.zoom = _final_ko_zoom_was
		_final_ko_camera.global_position = _final_ko_pos_was
		_final_ko_camera.reset_smoothing()
	_final_ko_camera = null
	if is_instance_valid(_final_ko_flash):
		_final_ko_flash.queue_free()
	_final_ko_flash = null

## Whether the final-KO slow motion is playing (for the scenario suite).
func final_ko_active() -> bool:
	return _final_ko_active

## The final-KO flash layer, or null (none, or reduce flashes is on).
func final_ko_flash() -> CanvasLayer:
	return _final_ko_flash
# --- Ghosts of KO'd players (issue #324) ---------------------------------------

const GhostScript := preload("res://scripts/Ghost.gd")
## slot -> its Ghost node, for human players knocked out this round.
var _ghosts: Dictionary = {}

## The ghost for `slot`, or null.
func ghost_of(slot: int) -> Node2D:
	return _ghosts.get(slot) as Node2D

## A knocked-out human gets a ghost the rest of the round; bots never do.
## Everything is gone the moment the round is no longer active.
func _tick_ghosts() -> void:
	if _state != State.ROUND_ACTIVE or _current_stage == null:
		if not _ghosts.is_empty():
			_clear_ghosts()
		return
	var claimed: Array[int] = _controller_server.claimed_slots() if _controller_server != null else []
	for slot in _in_round:
		var player: Variant = _players[slot]
		var stock: bool = _game_mode_node != null and _game_mode_node.has_method("is_pending")
		if stock and (player == null or player.alive or _game_mode_node.is_pending(slot)) and _ghosts.has(slot):
			if is_instance_valid(_ghosts[slot]):
				(_ghosts[slot] as Node).queue_free()
			_ghosts.erase(slot)
		if player == null or player.alive or not claimed.has(slot):
			continue
		if stock and _game_mode_node.is_pending(slot):
			continue  # a life left: coming back, no ghost yet (#354)
		if _controller_server.has_method("is_virtual") and _controller_server.is_virtual(slot):
			continue
		if _ghosts.has(slot) and is_instance_valid(_ghosts[slot]):
			continue
		var view: Rect2
		if _current_stage.has_method("get_view_rect"):
			view = _current_stage.get_view_rect()
		else:
			view = Rect2(_current_stage.global_position - StageScript.DEFAULT_VIEW_SIZE * 0.5, StageScript.DEFAULT_VIEW_SIZE)
		var ghost: Node2D = GhostScript.new()
		ghost.name = "Ghost%d" % slot
		_current_stage.add_child(ghost)
		ghost.setup(player, slot, player.global_position, view, player.identity_color)
		_ghosts[slot] = ghost

func _clear_ghosts() -> void:
	for ghost: Variant in _ghosts.values():
		if is_instance_valid(ghost):
			(ghost as Node).queue_free()
	_ghosts.clear()

## Issue #570: shots outlive an eliminated shooter, but never the round.
func _clear_all_shots() -> void:
	for player: Variant in _players:
		if player != null and is_instance_valid(player):
			player.clear_shots()
