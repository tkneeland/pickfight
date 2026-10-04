extends Node2D

## Nicknames in play (issue #121, always on since #151), split out of
## RoundManager (#175).
##
## Every living player carries its phone's nickname ("P3" without one) above
## its head, in its colour -- whatever the round loop is doing, lobby or not.
## The tag clears the player's hat (issue #151), follows a colour change at
## once, and, when fighters bunch up, a tag that would cover another's is
## lifted clear of it so all eight stay readable. Tags are world-space, so
## they are scaled up by however far the camera is zoomed out (#144, #163).
##
## RoundManager builds this lazily on its first frame and calls `tick()` at
## the top of its `_process`, as it always laid the tags out; this node has no
## `_process` of its own. Names and colours come from RoundManager's
## `_slot_name` / `_slot_color`, passed in as callables.
##
## Teams mode (issue #236, ADR-0018): a player on a team (`Player.team` 0 or
## 1) keeps its own colour for the name, but the tag's outline turns the
## team's colour and a ring of it is drawn round the body, so the room can
## tell the sides apart at a glance. In a free-for-all (`team` -1) neither is
## drawn and the tags are exactly as they were.

## How far above the body's centre the name tag's bottom edge sits, at least.
const NAME_TAG_RISE: float = 40.0
## Gap between the top of a player's hat and its name tag's bottom edge.
const NAME_TAG_HAT_GAP: float = 6.0
## Gap kept between two tags stacked to clear each other.
const NAME_TAG_STACK_GAP: float = 2.0
## Issue #236: the team ring round a player's body (radius 24).
const TEAM_RING_RADIUS: float = 33.0
const TEAM_RING_WIDTH: float = 5.0
const TEAM_OUTLINE_SIZE: int = 8
const TeamsScript := preload("res://scripts/Teams.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")
## Issue #236: [centre, team] per team ring drawn this frame.
var _rings: Array = []

## RoundManager's `_players`, one entry (or null) per slot.
var _players: Array = []
var _slot_name: Callable
var _slot_color: Callable
var _name_tags: Array[Label] = []
## Stock (#354): a Callable slot -> lives (-1 for none) drawn as pips under the tag.
var lives_of: Callable = Callable()
const PIP_RADIUS: float = 4.0
const PIP_GAP: float = 4.0
## [slot, centre, count] per slot with pips this frame.
var _pips: Array = []

func _init(players: Array = [], slot_name: Callable = Callable(), slot_color: Callable = Callable()) -> void:
	name = "NameTags"
	z_index = 50
	_players = players
	_slot_name = slot_name
	_slot_color = slot_color

## A slot's name tag, or null before `build()`.
func name_tag(slot: int) -> Label:
	return _name_tags[slot] if slot >= 0 and slot < _name_tags.size() else null

## One hidden label per player slot. Called once, right after this node is
## added under RoundManager.
func build() -> void:
	for slot in _players.size():
		var tag := Label.new()
		tag.name = "NameTag%d" % slot
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.theme_type_variation = UiThemeScript.HUD_HEADING_LABEL
		tag.add_theme_font_size_override("font_size", 22)
		tag.add_theme_color_override("font_color", _slot_color.call(slot))
		tag.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0)) # black, not ink: the tags sit over any stage
		tag.add_theme_constant_override("outline_size", 6)
		tag.visible = false
		add_child(tag)
		_name_tags.append(tag)

## Shows, names, colours and places every living player's tag for this frame.
func tick() -> void:
	var placed: Array[Rect2] = []
	var shown_slots: Array[int] = []
	# Scaled up by however far the camera is zoomed out (issue #144), so a name
	# reads the same size on a large stage as on a normal one.
	var tag_scale: float = 1.0
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null and camera.zoom.x > 0.0:
		tag_scale = 1.0 / camera.zoom.x
	# Comfort option (#317): bigger tags for a far-off couch.
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null:
		tag_scale *= float(sfx.get("ui_scale"))
	var had_rings: bool = not _rings.is_empty() or not _pips.is_empty()
	_rings.clear()
	_pips.clear()
	for slot in _players.size():
		var player: Variant = _players[slot]
		var tag: Label = _name_tags[slot]
		var shown: bool = player != null and player.alive and player.visible
		tag.visible = shown
		if not shown:
			continue
		var text: String = _slot_name.call(slot)
		if tag.text != text:
			tag.text = text
			tag.reset_size()
		var colour: Color = _slot_color.call(slot)
		if tag.get_theme_color("font_color") != colour:
			tag.add_theme_color_override("font_color", colour)
		_mark_team(tag, player)
		var rise: float = NAME_TAG_RISE
		if player.has_method("hat_top"):
			rise = maxf(rise, player.hat_top() + NAME_TAG_HAT_GAP)
		tag.scale = Vector2(tag_scale, tag_scale)
		var size: Vector2 = tag.get_minimum_size() * tag_scale
		tag.position = player.global_position + Vector2(-size.x * 0.5, -rise - size.y)
		shown_slots.append(slot)
	# Lowest tag first; each one after it moves up past any tag it would cover.
	shown_slots.sort_custom(func(a: int, b: int) -> bool:
		return _name_tags[a].position.y > _name_tags[b].position.y)
	for slot: int in shown_slots:
		var tag: Label = _name_tags[slot]
		var rect := Rect2(tag.position, tag.get_minimum_size() * tag_scale)
		var moved: bool = true
		while moved:
			moved = false
			for other: Rect2 in placed:
				if rect.intersects(other):
					rect.position.y = other.position.y - rect.size.y - NAME_TAG_STACK_GAP * tag_scale
					moved = true
		tag.position = rect.position
		placed.append(rect)
		var count: int = int(lives_of.call(slot)) if lives_of.is_valid() else -1
		if count > 0:
			var below: float = rect.position.y + rect.size.y + (PIP_RADIUS + 2.0) * tag_scale
			_pips.append([slot, Vector2(rect.position.x + rect.size.x * 0.5, below), count, tag_scale])
	if had_rings or not _rings.is_empty() or not _pips.is_empty():
		queue_redraw()

## Issue #236: `player`'s team, 0 or 1, or -1 in a free-for-all.
static func team_of(player: Object) -> int:
	var team: Variant = player.get("team") if player != null else null
	return int(team) if team is int else TeamsScript.NONE

## Issue #236: the tag's outline in the player's team colour (black with no
## team), and a ring noted for `_draw()`.
func _mark_team(tag: Label, player: Node2D) -> void:
	var team: int = team_of(player)
	var outline: Color = TeamsScript.team_color(team) if team != TeamsScript.NONE else Color(0.0, 0.0, 0.0, 1.0)
	if tag.get_theme_color("font_outline_color") != outline:
		tag.add_theme_color_override("font_outline_color", outline)
		tag.add_theme_constant_override("outline_size", TEAM_OUTLINE_SIZE if team != TeamsScript.NONE else 6)
	if team != TeamsScript.NONE:
		_rings.append([player.global_position, team])

## Issue #236: the team rings noted this frame, for the scenarios.
func team_rings() -> Array:
	return _rings.duplicate()

## Stock (#354): [slot, lives] per player showing pips this frame.
func pip_counts() -> Array:
	var counts: Array = []
	for pip: Array in _pips:
		counts.append([pip[0], pip[2]])
	return counts

func _draw() -> void:
	for pip: Array in _pips:
		var step: float = (PIP_RADIUS * 2.0 + PIP_GAP) * float(pip[3])
		var left: float = (pip[1] as Vector2).x - step * (int(pip[2]) - 1) * 0.5
		for i in int(pip[2]):
			draw_circle(to_local(Vector2(left + step * i, (pip[1] as Vector2).y)), PIP_RADIUS * float(pip[3]), _slot_color.call(pip[0]))
	for ring: Array in _rings:
		draw_arc(to_local(ring[0]), TEAM_RING_RADIUS, 0.0, TAU, 48, TeamsScript.team_color(ring[1]), TEAM_RING_WIDTH, true)
