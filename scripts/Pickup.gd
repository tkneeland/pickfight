extends Area2D

var weapon_stats: Resource

func set_weapon(stats: Resource) -> void:
	weapon_stats = stats

func art_polygon() -> PackedVector2Array:
	return PackedVector2Array()

func art_is_fallback() -> bool:
	return false

func trigger_radius() -> float:
	return 0.0
