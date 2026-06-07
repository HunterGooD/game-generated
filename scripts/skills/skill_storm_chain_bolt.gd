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


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)
	caster = mods.get("caster", null)
	# Forking Path modifier — each stack lets the bolt arc to one more target.
	jump_bonus = int(mods.get("jump_bonus", 0))


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
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = JUMP_RANGE
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e.get("dead") == true:
			continue
		if visited.has(e.get_instance_id()):
			continue
		var d: float = pos.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e as Node2D
	return best
