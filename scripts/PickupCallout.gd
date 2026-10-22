extends Node2D

## The weapon's name floating over a fighter who just grabbed a pickup
## (issue #818). World-space text in the fighter's colour on an ink plate (the
## #548 HUD look) that rises RISE_PX and fades over LIFETIME_SEC, drawn above
## the name tags. At most one per fighter: a new grab replaces the old label.
## Self-contained: `Pickup._on_body_entered` is the only caller.

const UiThemeScript := preload("res://scripts/UiTheme.gd")
const ScreenKitScript := preload("res://scripts/ScreenKit.gd")

const GROUP: StringName = &"pickup_callouts"
const FONT_SIZE: int = 20 # at least the 16 px Deck floor (D7/D10)
const START_RISE: float = 64.0 # plate centre above the body's centre
const RISE_PX: float = 40.0
const LIFETIME_SEC: float = 1.2
## Above NameTags (z 50).
const CALLOUT_Z: int = 60
## The round's spawn weapon: respawning with it is not a pickup.
const SPAWN_WEAPON: String = "pickaxe"

var fighter: Node = null
var text: String = ""

## Shows `weapon_id` (a resource basename such as "fishing_rod") over `fighter`.
## Returns the callout, or null when none is due (a ghost, the spawn weapon).
static func show_for(fighter_body: Node2D, weapon_id: String, parent: Node) -> Node2D:
	if weapon_id == SPAWN_WEAPON or not fighter_body.get("alive") or parent == null:
		return null
	for old: Node in fighter_body.get_tree().get_nodes_in_group(GROUP):
		if old.get("fighter") == fighter_body:
			old.remove_from_group(GROUP)
			old.queue_free()
	var callout: Node2D = (load("res://scripts/PickupCallout.gd") as GDScript).new() as Node2D
	callout.fighter = fighter_body
	var key: String = "WEAPON_" + weapon_id.to_upper()
	var shown: String = TranslationServer.translate(key)
	callout.text = weapon_id.replace("_", " ").capitalize() if shown == key else shown
	parent.add_child(callout)
	callout.global_position = fighter_body.global_position + Vector2(0.0, -START_RISE)
	return callout

func _ready() -> void:
	add_to_group(GROUP)
	name = "PickupCallout"
	z_index = CALLOUT_Z
	z_as_relative = false
	var identity: Variant = fighter.get("identity_color") if fighter != null else null
	var colour: Color = identity if identity is Color else Color.WHITE
	var label: Label = ScreenKitScript.ink_label(text, FONT_SIZE, colour)
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", UiThemeScript.plate(UiThemeScript.INK, 10, 2, false, 10))
	plate.add_child(label)
	add_child(plate)
	var size: Vector2 = plate.get_combined_minimum_size()
	plate.size = size
	plate.position = -size * 0.5
	# Same on-screen size however far the camera is zoomed out (#144, #163).
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null and camera.zoom.x > 0.0:
		scale = Vector2.ONE / camera.zoom.x
	var tween: Tween = create_tween().set_parallel(true).set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, "position:y", position.y - RISE_PX * scale.y, LIFETIME_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME_SEC * 0.6).set_delay(LIFETIME_SEC * 0.4)
	tween.chain().tween_callback(queue_free)
