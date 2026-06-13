extends Node2D

# Chain Bolt — fires a chain lightning bolt from the caster. Bounces between
# up to (3 + Static Charge stacks) enemies within 200 px of each previous
# target. Each enemy hit adds 1 Static Charge to the caster.

const BASE_JUMPS: int = 3
const JUMP_RANGE: float = 220.0
const SEGMENT_TEX: String = "res://assets/sprites/effects/lightning_bolt_segment.png"

var damage: int = 20
var visual_only: bool = false
var caster: Node = null
var jump_bonus: int = 0

var _ctx: SkillContext = null


func setup_context(ctx: SkillContext) -> void:
	_ctx = ctx
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	caster = ctx.caster
	# Forking Path modifier — each stack lets the bolt arc to one more target.
	jump_bonus = int(ctx.get_mod("jump_bonus", 0))


func _ready() -> void:
	z_index = 65
	if visual_only:
		var t := get_tree().create_timer(0.5)
		t.timeout.connect(queue_free)
		return
	# Bonus jumps from Static Charge plus the Forking Path modifier.
	var jumps: int = BASE_JUMPS + jump_bonus
	if caster and caster.get("static_charge") != null:
		jumps += int(caster.get("static_charge"))
	var origin: Vector2 = global_position
	var visited: Dictionary = {}
	var prev_pos: Vector2 = origin
	var current_dmg: int = damage
	for i in jumps:
		var next: Node2D = _nearest_unhit_enemy(prev_pos, visited)
		if next == null:
			break
		visited[next.get_instance_id()] = true
		_draw_segment(prev_pos, next.global_position)
		if next.has_method("take_damage"):
			next.call("take_damage", current_dmg, prev_pos)
			if _ctx != null:
				_ctx.apply_on_hit(next)
		# Add a static charge per hit.
		if caster and caster.has_method("add_static_charge"):
			caster.call("add_static_charge", 1)
		if VfxManager:
			VfxManager.spawn_hit_sparks(next.global_position, Color(0.7, 0.9, 1.0, 1), 5)
		current_dmg = int(round(float(current_dmg) * 0.78))
		prev_pos = next.global_position
	# Free after the visual fades.
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(queue_free)


func _draw_segment(a: Vector2, b: Vector2) -> void:
	if not is_inside_tree():
		return
	if not ResourceLoader.exists(SEGMENT_TEX):
		return
	var s := Sprite2D.new()
	s.texture = load(SEGMENT_TEX) as Texture2D
	s.modulate = Color(0.7, 0.9, 1.5, 1)
	s.z_index = 65
	var mid: Vector2 = (a + b) * 0.5
	var diff: Vector2 = b - a
	s.global_position = mid
	s.rotation = diff.angle()
	if s.texture:
		var tex_w: float = float(s.texture.get_size().x)
		if tex_w > 1.0:
			var sx: float = diff.length() / tex_w
			s.scale = Vector2(sx, clamp(60.0 / float(s.texture.get_size().y), 0.05, 0.3))
	get_tree().current_scene.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.32)
	tw.tween_callback(s.queue_free)


func _nearest_unhit_enemy(pos: Vector2, visited: Dictionary) -> Node2D:
	return SkillTargeting.nearest(get_tree(), pos, JUMP_RANGE, visited)
