extends Control

## A team's letter in ink on its colour (#752), for every team marker that would otherwise rest on
## colour alone: name tags, the lobby card, the podium, goals, bases and flags. A rounded square in the
## team's colour with an ink outline and the first character of the team's translated name. Hidden
## for no team, so a free-for-all draws nothing. No new shapes or patterns.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const TeamsScript := preload("res://scripts/Teams.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")
const DEFAULT_PX: float = 30.0
const BORDER_PX: int = 3
const CORNER_PX: int = 7

var _team: int = TeamsScript.NONE
## Player numbers (#809): a seat number (1 to 8) in ink on the player's colour, 0 for none. A team wins.
var _number: int = 0
var _number_color: Color = Color.WHITE
## The badge's box, made once and recoloured per draw.
var _box: StyleBoxFlat = null

func _init(team: int = TeamsScript.NONE, side_px: float = DEFAULT_PX) -> void:
	name = "TeamBadge"
	custom_minimum_size = Vector2(side_px, side_px)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_team(team)

## Shows the badge for `team` (0 or 1), or hides it for any other value.
func set_team(team: int) -> void:
	var was: int = _team
	_team = team if team >= 0 and team < TeamsScript.COUNT else TeamsScript.NONE
	visible = _team != TeamsScript.NONE or _number > 0
	if _team != was:
		queue_redraw() # callers set it every frame: redraw only on a change

## Player numbers (#809): shows seat `number` (1 to 8) on `color` when there is no team; 0 hides it.
func set_number(number: int, color: Color = Color.WHITE) -> void:
	var was_number: int = _number
	var was_color: Color = _number_color
	_number = number if number > 0 else 0
	_number_color = color
	visible = _team != TeamsScript.NONE or _number > 0
	if _number != was_number or _number_color != was_color:
		queue_redraw()

func _notification(what: int) -> void:
	# The letter is translated and drawn in the theme's font: redraw on either change.
	if what == NOTIFICATION_TRANSLATION_CHANGED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()

func number() -> int:
	return _number

func team() -> int:
	return _team

## The letter shown, "" for no team.
func letter() -> String:
	if _team == TeamsScript.NONE:
		return str(_number) if _number > 0 else ""
	return TeamsScript.team_letter(_team)

func _draw() -> void:
	if _team == TeamsScript.NONE and _number <= 0:
		return
	if _box == null:
		_box = StyleBoxFlat.new()
		_box.border_color = UiThemeScript.INK
		_box.set_border_width_all(BORDER_PX)
		_box.set_corner_radius_all(CORNER_PX)
	_box.bg_color = TeamsScript.team_color(_team) if _team != TeamsScript.NONE else _number_color
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	# The display font the name tags use, so a small letter stays bold and legible; the default if the theme lacks it.
	var font: Font = get_theme_font("font", UiThemeScript.HUD_HEADING_LABEL)
	if font == null:
		font = get_theme_default_font()
	var font_size: int = maxi(8, int(size.y * 0.62))
	var baseline: float = (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(0.0, baseline), letter(), HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, UiThemeScript.INK)
