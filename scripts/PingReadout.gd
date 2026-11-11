extends RefCounted
## The in-match Online ping readout (issue #1195): one small label in the
## host's screen-space HUD, a line per remote seat ("<name>  <ping>  (delay N
## ms)") and a last line for the host's own leg to the relay, in the worst of
## its lines' ping colours.
##
## Both the host (`RoundManager`) and the Online joiner (`RemoteClient._build_hud`)
## build the label through `make()`, so it is placed, sized and styled the same
## on both screens; `UiMirror` then only carries its text, colour and
## visibility (it copies no position or font, and a label it has to create
## itself lands at (0,0) in the default font). Preload by path; never reference
## it by `class_name` (CLAUDE.md).

const LobbyScreenScript: GDScript = preload("res://scripts/LobbyScreen.gd")

## The label's node name, directly under the HUD root (`HostHud.tscn`'s "UI").
const NODE_NAME: String = "Ping"
const FONT_SIZE: int = 16
const WIDTH_PX: float = 420.0
const MARGIN_PX: float = 16.0
const HEIGHT_PX: float = 24.0

## The readout under `ui_root`, built and placed the first time. Bottom right:
## the kill feed owns the top right.
static func make(ui_root: Node) -> Label:
	var label := ui_root.get_node_or_null(NODE_NAME) as Label
	if label != null:
		return label
	label = Label.new()
	label.name = NODE_NAME
	label.theme_type_variation = &"HudLabel"
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left = -WIDTH_PX - MARGIN_PX
	label.offset_right = -MARGIN_PX
	label.offset_top = -HEIGHT_PX - MARGIN_PX
	label.offset_bottom = -MARGIN_PX
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	ui_root.add_child(label)
	return label

## One remote seat's line: its name, round trip (`PING_MS`) and, once the
## joiner has measured it, its felt input-to-screen delay (`FELT_MS`).
static func line(name: String, ping_msec: int, felt_msec: int) -> String:
	var text: String = name + "  " + (TranslationServer.translate("PING_MS") % ping_msec if ping_msec >= 0 else "…")
	if felt_msec >= 0:
		text += "  (" + TranslationServer.translate("FELT_MS") % felt_msec + ")"
	return text

## The host's own leg to the relay, the readout's last line.
static func host_leg_line(leg_msec: int) -> String:
	return TranslationServer.translate("HOST_LEG_MS") % leg_msec

## The colour of the whole label: the worst of `pings` (ms) by the lobby's rule.
static func color_of(pings: Array) -> Color:
	var worst: int = -1
	for ping: Variant in pings:
		worst = maxi(worst, int(ping))
	return LobbyScreenScript.ping_color(worst)
