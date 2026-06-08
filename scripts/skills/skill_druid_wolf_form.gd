extends Node2D

# Wolf form — transforms the caster into a dire wolf for ~20 seconds.
# Pure caster-state change; the visible scene is just a spawn flash.

const FLASH_DURATION: float = 0.45
const BASE_DURATION: float = 20.0

var visual_only: bool = false


func setup_context(ctx: SkillContext) -> void:
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	var caster = ctx.caster
	if visual_only or caster == null:
		return
	# Form duration: base 20 s plus +4 s per wolf_duration stack (from upgrades).
	var bonus_stacks: int = 0
	var ss = caster.get_node_or_null("SkillSystem")
	if ss and ss.has_method("get_modifier"):
		bonus_stacks = int(ss.call("get_modifier", 0, "wolf_duration"))
	var dur: float = BASE_DURATION + 4.0 * float(bonus_stacks)
	if caster.has_method("set_druid_form"):
		caster.call("set_druid_form", "wolf", dur)


func _ready() -> void:
	z_index = 70
	var ring := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/cast_flash.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
	ring.modulate = Color(1.0, 0.55, 0.4, 0.85)
	ring.scale = Vector2(0.4, 0.4)
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	(
		tw
		. tween_property(ring, "scale", Vector2(1.6, 1.6), FLASH_DURATION)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(ring, "modulate:a", 0.0, FLASH_DURATION)
	var t := get_tree().create_timer(FLASH_DURATION + 0.05)
	t.timeout.connect(queue_free)
