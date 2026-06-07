extends Node2D

# Eagle form — transforms the caster into a swift airborne raptor for ~20
# seconds. While airborne, ground enemies can't reach the druid. Press Q
# again to revert early.

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
	# If already in eagle form, revert (Q acts as a toggle).
	if String(caster.get("druid_form")) == "eagle":
		if caster.has_method("set_druid_form"):
			caster.call("set_druid_form", "human", 0.0)
		return
	# Duration: base 20 s + 4 s per eagle_duration stack.
	var bonus_stacks: int = 0
	var ss = caster.get_node_or_null("SkillSystem")
	if ss and ss.has_method("get_modifier"):
		bonus_stacks = int(ss.call("get_modifier", 4, "eagle_duration"))
	var dur: float = BASE_DURATION + 4.0 * float(bonus_stacks)
	if caster.has_method("set_druid_form"):
		caster.call("set_druid_form", "eagle", dur)


func _ready() -> void:
	z_index = 70
	var ring := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/cast_flash.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
	ring.modulate = Color(0.85, 0.95, 1.0, 0.85)
	ring.scale = Vector2(0.4, 0.4)
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	(
		tw
		. tween_property(ring, "scale", Vector2(2.0, 2.0), FLASH_DURATION)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(ring, "modulate:a", 0.0, FLASH_DURATION)
	var t := get_tree().create_timer(FLASH_DURATION + 0.05)
	t.timeout.connect(queue_free)
