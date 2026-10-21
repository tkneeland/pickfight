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

func _init(team: int = TeamsScript.NONE, side_px: float = DEFAULT_PX) -> void:
	name = "TeamBadge"
	custom_minimum_size = Vector2(side_px, side_px)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_team(team)

## Shows the badge for `team` (0 or 1), or hides it for any other value.
func set_team(team: int) -> void:
	_team = team if team >= 0 and team < TeamsScript.COUNT else TeamsScript.NONE
	visible = _team != TeamsScript.NONE
	queue_redraw()

func team() -> int:
	return _team

## The letter shown, "" for no team.
func letter() -> String:
	return TeamsScript.team_letter(_team)

func _draw() -> void:
	if _team == TeamsScript.NONE:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = TeamsScript.team_color(_team)
	box.border_color = UiThemeScript.INK
	box.set_border_width_all(BORDER_PX)
	box.set_corner_radius_all(CORNER_PX)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	# The display font the name tags use, so a small letter stays bold and legible; the default if the theme lacks it.
	var font: Font = get_theme_font("font", UiThemeScript.HUD_HEADING_LABEL)
	if font == null:
		font = get_theme_default_font()
	var font_size: int = maxi(8, int(size.y * 0.62))
	var baseline: float = (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(0.0, baseline), letter(), HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, UiThemeScript.INK)
