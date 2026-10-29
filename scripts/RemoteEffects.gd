extends Node2D

## The Online joiner's half of issue #976: everything the host shows that is
## not a persistent world object, drawn on the joiner by the host's OWN
## scripts. Lives under the joiner's `World` node, so world-space effects use
## the same coordinates as the puppets.
##
## - One-shot effects arrive as `EffectStream` events in each streamed frame's
##   trailer (`queue()`), and play `delay_msec` later, when the joiner's
##   interpolated world (drawn `RemoteClient.INTERP_MSEC` behind) reaches the
##   moment they happened: KO bursts (`DeathBurst`), hitmarkers and damage
##   numbers (`HitFeedback`), shakes, landing dust, clash sparks and catch
##   bursts (`Juice`), pickup callouts, shield sparks, round-win rings, the
##   kill feed and its banners, the stage title card and PAUSED banner
##   (`RoundCards`), MATCH POINT plates and dots, the final-KO zoom and flash
##   (`FinalKoView`), Play of the Round (`PlayOfRound` over this machine's own
##   `ReplayBuffer`) and the match-end clip save.
## - Head motion trails follow anchors at each player puppet's weapon head
##   (`track_heads()`), drawn by the same `Juice` trail code.
## - Screens come from the `hud` frame: the victory screen (`show_victory()`,
##   the host's `VictoryScreen` with every award) and the mode HUD
##   (`apply_mode_hud()`, the mode script's own `_build_hud()`).
##
## Every effect still asks THIS machine's display settings (Reduce flashes,
## Screen shake, Damage numbers, Kill feed, Pickup callouts, Stage title card,
## Match point plate, Play of the Round), as the host's copy asks the host's.
## Preloaded by path, never by `class_name` (CLAUDE.md).

const HitFeedbackScript: GDScript = preload("res://scripts/HitFeedback.gd")
const JuiceScript: GDScript = preload("res://scripts/Juice.gd")
const DeathBurstScript: GDScript = preload("res://scripts/DeathBurst.gd")
const PickupCalloutScript: GDScript = preload("res://scripts/PickupCallout.gd")
const ShieldSparkScript: GDScript = preload("res://scripts/ShieldSpark.gd")
const RoundWinRingScript: GDScript = preload("res://scripts/RoundWinRing.gd")
const BouncePadRingScript: GDScript = preload("res://scripts/BouncePadRing.gd")
const PartKitScript: GDScript = preload("res://scripts/PartKit.gd")
const MatchPointPlateScript: GDScript = preload("res://scripts/MatchPointPlate.gd")
const FinalKoViewScript: GDScript = preload("res://scripts/FinalKoView.gd")
const RoundCardsScript: GDScript = preload("res://scripts/RoundCards.gd")
const PlayOfRoundScript: GDScript = preload("res://scripts/PlayOfRound.gd")
const ReplayBufferScript: GDScript = preload("res://scripts/ReplayBuffer.gd")
const VictoryScreenScript: GDScript = preload("res://scripts/VictoryScreen.gd")
const RemoteScreenScript: GDScript = preload("res://scripts/RemoteScreen.gd")
const UiMirrorScript: GDScript = preload("res://scripts/UiMirror.gd")
const HostSettingsScript: GDScript = preload("res://scripts/HostSettings.gd")
const OffscreenIndicatorsScript: GDScript = preload("res://scripts/OffscreenIndicators.gd")
const RemoteFighterScript: GDScript = preload("res://scripts/RemoteFighter.gd")
const NameTagsScript: GDScript = preload("res://scripts/NameTags.gd")
const PickupSpawnRingScript: GDScript = preload("res://scripts/PickupSpawnRing.gd")
const MAX_SLOTS: int = 8

## How long after arrival an event plays: the joiner's interpolation delay.
var delay_msec: int = 100
## The joiner's camera (final-KO zoom); set by `RemoteClient`.
var camera: Camera2D = null
## The joiner's copy of the host's kill feed (inside its `HostHud.tscn`).
var kill_feed: Control = null
## Maps a slot to the joiner's name tag Label, or null (MATCH POINT dots);
## unset, the joiner's own `NameTags` copy answers.
var name_tag_of: Callable = Callable()
## Stock lives per slot (-1 none) for the name tags' pips; set by `RemoteClient`.
var lives_of: Callable = Callable()
## Called with a pickup's snapshot id when the host pops it in (#816), so the
## joiner's pickup puppet pops the same way; set by `RemoteClient`.
var pop_pickup: Callable = Callable()
## Whether the joiner's world shows a round in play (MATCH POINT dots last
## while it does).
var round_playing: Callable = Callable()
## Bumped each time a round starts on the joiner: a dot belongs to one round.
var _round_number: int = 0

var hit_feedback: Node2D
var juice: Node2D
var screen: CanvasLayer
var cards: RefCounted
var replay: Node
var play_of_round: CanvasLayer
var victory: RefCounted
var final_ko: RefCounted = FinalKoViewScript.new()
var mode_hud: CanvasLayer = null
var _mode_hud_script: String = ""
var _victory_names: Dictionary = {}
var _victory_key: String = ""

## Every event kind played so far, oldest first (the last 64; for scenarios).
var played: Array[String] = []
var _queue: Array = [] # [due msec, event]
var _anchors: Dictionary = {} # puppet instance id -> Node2D at its weapon head
## The host's edge arrows (#779), fed one `RemoteFighter` per slot.
var edge_arrows: CanvasLayer
var _fighters: Array = []
var _fighter_colors: Array[Color] = []
## The host's name tags (`NameTags.gd`, with its team badges, team rings,
## stock pips, idle hint #826 and boomstick ring #965), over the stand-ins.
var name_tags: Node2D

func _ready() -> void:
	name = "RemoteEffects"
	hit_feedback = HitFeedbackScript.new()
	hit_feedback.mirror = true
	hit_feedback.name = "HitFeedback"
	add_child(hit_feedback)
	juice = JuiceScript.new()
	juice.mirror = true
	juice.name = "Juice"
	add_child(juice)
	replay = ReplayBufferScript.new()
	replay.name = "ReplayBuffer"
	add_child(replay)
	screen = RemoteScreenScript.new()
	add_child(screen)
	cards = RoundCardsScript.new(screen)
	for slot in MAX_SLOTS:
		var fighter: Node2D = RemoteFighterScript.new()
		fighter.name = "Fighter%d" % slot
		fighter.visible = false
		add_child(fighter)
		_fighters.append(fighter)
		_fighter_colors.append(Color.WHITE)
	edge_arrows = OffscreenIndicatorsScript.new(_fighters, func(slot: int) -> Color: return _fighter_colors[slot])
	add_child(edge_arrows)
	edge_arrows.build()
	name_tags = NameTagsScript.new(_fighters,
		func(slot: int) -> String: return str(_fighters[slot].display_name),
		func(slot: int) -> Color: return _fighter_colors[slot])
	name_tags.lives_of = func(slot: int) -> int: return int(lives_of.call(slot)) if lives_of.is_valid() else -1
	add_child(name_tags)
	name_tags.build()
	name_tags.idle_hint().mirror = true
	name_tags.boomstick_ring().mirror = true

## Puts slot `slot`'s stand-in where its puppet is (`puppet` null: gone).
## `alive`, `team`, `display_name` and `weapon` (the head shape index) are the
## snapshot's; `colour` and the hat the puppet's.
func place_fighter(slot: int, puppet: Node2D, alive: bool, team: int, colour: Color, display_name: String = "", weapon: int = 0) -> void:
	if slot < 0 or slot >= _fighters.size():
		return
	var fighter: Node2D = _fighters[slot]
	var shown: bool = puppet != null and is_instance_valid(puppet) and puppet.visible
	fighter.visible = shown
	fighter.alive = shown and alive
	fighter.team = team
	_fighter_colors[slot] = colour
	if shown:
		fighter.global_position = puppet.global_position
		fighter.display_name = display_name if not display_name.is_empty() else "P%d" % (slot + 1)
		fighter.hat_id = str(puppet.call("hat_id")) if puppet.has_method("hat_id") else "none"
		fighter.set_weapon(weapon)

## Slot `slot`'s stand-in (scenarios).
func fighter_at(slot: int) -> Node2D:
	return _fighters[slot] if slot >= 0 and slot < _fighters.size() else null

## The host's "Player numbers" setting for the arrows' seat numbers.
func set_numbers(on: Variant) -> void:
	edge_arrows.numbers_override = on if on is bool else null
	name_tags.numbers_override = on if on is bool else null

## The MATCH POINT dot's round test (`MatchPointDot.gd`).
func lobby_phase() -> String:
	return "playing" if round_playing.is_valid() and bool(round_playing.call()) else "round_end"

## A round started on the joiner's screen.
func round_started() -> void:
	_round_number += 1

## Takes one frame's events; each plays `delay_msec` from now.
func queue(events: Array) -> void:
	var due: int = Time.get_ticks_msec() + delay_msec
	for ev: Variant in events:
		if ev is Dictionary and (ev as Dictionary).get("k") is String:
			_queue.append([due, ev])

## Events waiting to play.
func queued_count() -> int:
	return _queue.size()

func _process(_delta: float) -> void:
	name_tags.tick()
	if _queue.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	while not _queue.is_empty() and int(_queue[0][0]) <= now:
		var entry: Array = _queue.pop_front()
		play(entry[1])

## Plays every queued event now (scenarios; and a frame that skips the wait).
func flush() -> void:
	while not _queue.is_empty():
		play(_queue.pop_front()[1])

static func _v2(ev: Dictionary, key: String) -> Vector2:
	var v: Variant = ev.get(key)
	return v if v is Vector2 else Vector2.ZERO

static func _col(ev: Dictionary, key: String) -> Color:
	var v: Variant = ev.get(key)
	return v if v is Color else Color.WHITE

## Plays one recorded event with the host's own script.
func play(ev: Dictionary) -> void:
	var kind: String = str(ev.get("k", ""))
	played.append(kind)
	if played.size() > 64:
		played.pop_front()
	match kind:
		"ko":
			DeathBurstScript.spawn_at(self, _v2(ev, "p"), _col(ev, "c"))
		"hit":
			hit_feedback.show_strike(_v2(ev, "p"), float(ev.get("a", 0.0)), bool(ev.get("l", false)), _col(ev, "c"))
		"jolt":
			juice.strike_jolt(float(ev.get("a", 0.0)), false) # the stream already holds the hit-stop
		"ko_jolt":
			juice.elimination_jolt()
		"dust":
			juice.land_puff(_v2(ev, "p"), float(ev.get("s", 0.0)))
		"clash":
			juice.clash_sparks(_v2(ev, "p"), float(ev.get("s", 0.0)))
		"catch":
			juice.catch_burst(_v2(ev, "p"))
		"callout":
			PickupCalloutScript.show_at(self, _v2(ev, "p"), str(ev.get("w", "")), _col(ev, "c"), int(ev.get("o", 0)))
		"shield":
			ShieldSparkScript.spawn_at(self, _v2(ev, "p"), _col(ev, "c"))
		"win_ring":
			RoundWinRingScript.spawn_at(self, _v2(ev, "p"), _col(ev, "c"))
		"bounce_ring":
			if not PartKitScript.reduce_flash(self):
				BouncePadRingScript.spawn_at(self, _v2(ev, "p"))
		"feed_ko":
			if kill_feed != null:
				kill_feed.push_ko(str(ev.get("kn", "")), _col(ev, "kc"), str(ev.get("vn", "")), _col(ev, "vc"))
		"banner":
			if kill_feed != null:
				kill_feed.show_banner(str(ev.get("h", "")), str(ev.get("w", "")), _col(ev, "c"))
		"feed_clear":
			if kill_feed != null:
				kill_feed.clear()
		"banner_clear":
			if kill_feed != null:
				kill_feed.clear_banners()
		"title":
			cards.show_stage_title(str(ev.get("t", "")), float(ev.get("d", 1.0)), str(ev.get("r", "")))
		"pause":
			cards.show_pause_banner(bool(ev.get("on", false)))
		"match_point":
			var found: Array = []
			for line: Variant in ev.get("lines", []):
				if line is Dictionary:
					found.append(line)
			var tags: Callable = func(slot: int) -> Label:
				return name_tag_of.call(slot) if name_tag_of.is_valid() else name_tags.name_tag(slot)
			MatchPointPlateScript.present(self, found, tags, self, _round_number)
		"pickup_ring":
			PickupSpawnRingScript.spawn_at(self, _v2(ev, "p"))
			if pop_pickup.is_valid():
				pop_pickup.call(int(ev.get("id", -1)))
		"idle_hint":
			name_tags.idle_hint().show_hint(int(ev.get("s", -1)), bool(ev.get("pad", false)))
		"idle_hint_end":
			name_tags.idle_hint().hide_hint(int(ev.get("s", -1)))
		"fire_clock":
			var who: Node2D = fighter_at(int(ev.get("s", -1)))
			if who != null:
				who.sync_fire(float(ev.get("i", 0.0)), float(ev.get("r", 0.0)))
		"final_ko":
			final_ko.start(camera, self, _v2(ev, "p"))
		"final_ko_end":
			final_ko.end()
		"clip_save":
			replay.autosave_match_clip()
		"por":
			_play_of_round(ev)
		"por_end":
			end_play_of_round()

## Play of the Round: the same moment, cut from this machine's own replay
## buffer by the host's `select_frames()` (the KO `age` msec ago, `rem` msec
## of pause left), under this machine's Play of the Round and Screen shake.
func _play_of_round(ev: Dictionary) -> void:
	end_play_of_round()
	if not HostSettingsScript.shared().play_of_round or replay.hi_frame_count() == 0:
		return
	var now: int = Time.get_ticks_msec()
	var pick: Dictionary = PlayOfRoundScript.select_frames(replay.hi_frame_count(), now, now - int(ev.get("age", 0)), int(ev.get("rem", 0)))
	if int(pick["count"]) <= 0:
		return
	if play_of_round == null:
		play_of_round = PlayOfRoundScript.new()
		add_child(play_of_round)
	var sfx: Node = get_node_or_null("/root/Sfx")
	play_of_round.play(replay.hi_frames_slice(int(pick["start"]), int(pick["count"])), str(ev.get("cap", "")),
		sfx == null or bool(sfx.get("screen_shake")))

func end_play_of_round() -> void:
	if play_of_round != null:
		play_of_round.dismiss()

## Ends anything tied to a round when the joiner leaves it (a lost frame
## must never strand a zoom, a flash or a clip on screen).
func round_left() -> void:
	final_ko.end()
	end_play_of_round()

# --- Head trails ---------------------------------------------------------------

## Keeps one anchor at each visible player puppet's weapon head, which
## `Juice.track_trail()` follows like a host head. `puppets` are the player
## puppets (each with `head_offset`).
func track_heads(puppets: Array) -> void:
	var seen: Dictionary = {}
	for puppet: Variant in puppets:
		if not puppet is Node2D or not is_instance_valid(puppet) or not (puppet as Node2D).visible:
			continue
		var id: int = (puppet as Node2D).get_instance_id()
		seen[id] = true
		var anchor: Node2D = _anchors.get(id)
		var at: Vector2 = (puppet as Node2D).global_position + (puppet.get("head_offset") as Vector2 if puppet.get("head_offset") is Vector2 else Vector2.ZERO)
		if anchor == null or not is_instance_valid(anchor):
			anchor = Node2D.new()
			anchor.name = "HeadAnchor%d" % id
			add_child(anchor)
			anchor.global_position = at
			_anchors[id] = anchor
			juice.track_trail(anchor)
		else:
			anchor.global_position = at
	for id: int in _anchors.keys():
		if not seen.has(id):
			var gone: Node2D = _anchors[id]
			_anchors.erase(id)
			if is_instance_valid(gone):
				gone.queue_free()

func head_anchor_count() -> int:
	return _anchors.size()

# --- Screens from the hud frame ------------------------------------------------

## The host's victory screen from `RoundManager.victory_data()` (null hides
## it): the same `VictoryScreen` build and refresh, every award included.
func show_victory(data: Variant) -> void:
	if not data is Dictionary or (data as Dictionary).is_empty():
		if victory != null:
			victory.victory_panel().visible = false
			if victory.end_card_panel() != null:
				victory.end_card_panel().visible = false
		_victory_key = ""
		return
	var d: Dictionary = data
	if victory == null:
		victory = VictoryScreenScript.new(screen, _victory_name, _victory_color)
		victory.build()
	var key: String = var_to_str(d)
	if key != _victory_key:
		_victory_key = key
		_victory_names = d.get("names", {}) if d.get("names") is Dictionary else {}
		var slots: Array[int] = []
		for s: Variant in d.get("slots", []):
			slots.append(int(s))
		var awards: Array[Dictionary] = []
		for a: Variant in d.get("awards", []):
			if a is Dictionary:
				awards.append(a)
		var stats: Array[Dictionary] = []
		for r: Variant in d.get("stats", []):
			if r is Dictionary:
				stats.append(r)
		var scores: PackedInt32Array = PackedInt32Array(d.get("scores", PackedInt32Array()))
		var team_scores: PackedInt32Array = PackedInt32Array(d.get("team_scores", PackedInt32Array()))
		var teams: Dictionary = d.get("teams", {}) if d.get("teams") is Dictionary else {}
		victory.set_continue_inputs(PackedStringArray(d.get("inputs", PackedStringArray())))
		victory.refresh(slots, scores, int(d.get("winner", -1)), awards, int(d.get("winner_team", -1)), teams, team_scores, stats)
	var end_card: bool = bool(d.get("end_card", false)) and victory.end_card_panel() != null
	victory.victory_panel().visible = not end_card
	if victory.end_card_panel() != null:
		victory.end_card_panel().visible = end_card

func victory_visible() -> bool:
	return victory != null and victory.victory_panel().visible

func _victory_name(slot: int) -> String:
	var entry: Variant = _victory_names.get(slot)
	return str(entry[0]) if entry is Array and (entry as Array).size() > 0 else "P%d" % (slot + 1)

func _victory_color(slot: int) -> Color:
	var entry: Variant = _victory_names.get(slot)
	return entry[1] if entry is Array and (entry as Array).size() > 1 and entry[1] is Color else Color.WHITE

## The game mode's own HUD: built by the mode script's `_build_hud()` on an
## unattached instance (so nothing of the mode runs here), moved under this
## node, then given the host's label state. An empty `script_path` removes it.
func apply_mode_hud(script_path: String, state: Dictionary) -> void:
	if script_path != _mode_hud_script:
		if mode_hud != null and is_instance_valid(mode_hud):
			mode_hud.queue_free()
		mode_hud = null
		_mode_hud_script = script_path
		if script_path.begins_with("res://scripts/") and script_path.ends_with(".gd") and ResourceLoader.exists(script_path):
			var script: GDScript = load(script_path) as GDScript
			var mode: Object = script.new() if script != null and script.can_instantiate() else null
			if mode is Node and mode.has_method("_build_hud"):
				mode.call("_build_hud")
				var layer: Variant = mode.get("_hud")
				if layer is CanvasLayer:
					(layer as CanvasLayer).get_parent().remove_child(layer)
					mode_hud = layer
					add_child(mode_hud)
			if mode is Node:
				(mode as Node).free()
	if mode_hud != null:
		UiMirrorScript.apply(mode_hud, state)
