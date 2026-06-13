extends Node2D

# Dire Wolf Form — replaces Bear Form when the Alpha Predator unique is equipped.
# Transforms the druid into an enhanced wolf shape (wolf moveset, deeper red
# tint, ~20 s duration). Slot 0/1 still become Bite + Leap via the form map.

const FLASH_DURATION: float = 0.5
const BASE_DURATION: float = 20.0

var visual_only: bool = false


func setup_context(ctx: SkillContext) -> void:
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	var caster = ctx.caster
	if visual_only or caster == null:
		return
	# Duration scales with bear_duration stacks (same upgrade slot 1).
	var bonus_stacks: int = 0
	var ss = caster.get_node_or_null("SkillSystem")
	if ss and ss.has_method("get_modifier"):
		bonus_stacks = int(ss.call("get_modifier", 1, "bear_duration"))
	var dur: float = BASE_DURATION + 4.0 * float(bonus_stacks)
	if caster.has_method("set_druid_form"):
		caster.call("set_druid_form", "dire_wolf", dur)


func _ready() -> void:
	z_index = 70
	var ring := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/cast_flash.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
	ring.modulate = Color(1.0, 0.35, 0.35, 0.9)
	ring.scale = Vector2(0.55, 0.55)
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	(
		tw
		. tween_property(ring, "scale", Vector2(2.2, 2.2), FLASH_DURATION)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(ring, "modulate:a", 0.0, FLASH_DURATION)
	var t := get_tree().create_timer(FLASH_DURATION + 0.05)
	t.timeout.connect(queue_free)
