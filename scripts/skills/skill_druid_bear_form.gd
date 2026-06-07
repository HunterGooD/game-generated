extends Node2D

# Bear form — transforms the caster into an armored bear for ~20 seconds.

const FLASH_DURATION: float = 0.45
const BASE_DURATION: float = 20.0

var visual_only: bool = false


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)
	var caster = mods.get("caster", null)
	if visual_only or caster == null:
		return
	var bonus_stacks: int = 0
	var ss = caster.get_node_or_null("SkillSystem")
	if ss and ss.has_method("get_modifier"):
		bonus_stacks = int(ss.call("get_modifier", 1, "bear_duration"))
	var dur: float = BASE_DURATION + 4.0 * float(bonus_stacks)
	if caster.has_method("set_druid_form"):
		caster.call("set_druid_form", "bear", dur)


func _ready() -> void:
	z_index = 70
	var ring := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/cast_flash.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
	ring.modulate = Color(0.85, 0.7, 0.4, 0.85)
	ring.scale = Vector2(0.5, 0.5)
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	(
		tw
		. tween_property(ring, "scale", Vector2(1.8, 1.8), FLASH_DURATION)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(ring, "modulate:a", 0.0, FLASH_DURATION)
	var t := get_tree().create_timer(FLASH_DURATION + 0.05)
	t.timeout.connect(queue_free)
