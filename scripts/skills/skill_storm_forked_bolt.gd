extends Node2D

# Forked Bolt — Tempest Lord transform of Chain Bolt. More branches, lower damage
# each, staticking every enemy it touches.

const MAX_TARGETS: int = 7
const JUMP_RANGE: float = 240.0

var damage: int = 16
var visual_only: bool = false
var caster: Node2D = null


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = int(round(float(dmg) * 0.8))
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	var origin: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	if not visual_only:
		var tree := get_tree()
		if tree:
			var used: Dictionary = {}
			var prev: Vector2 = origin
			for _i in MAX_TARGETS:
				var t: Node2D = _nearest(prev, used)
				if t == null:
					break
				used[t.get_instance_id()] = true
				_arc(prev, t.global_position)
				if t.has_method("take_damage"):
					t.call("take_damage", damage, prev)
				if t.has_method("mark_element"):
					t.call("mark_element", "storm")
				prev = t.global_position
	var tt := get_tree().create_timer(0.4)
	tt.timeout.connect(queue_free)


func _nearest(from: Vector2, used: Dictionary) -> Node2D:
	var best: Node2D = null
	var bd: float = JUMP_RANGE
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")) or used.has(e.get_instance_id()):
			continue
		var d: float = from.distance_to((e as Node2D).global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _arc(a: Vector2, b: Vector2) -> void:
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.7, 0.9, 1.0, 0.9)
	line.add_point(to_local(a))
	line.add_point(to_local(b))
	add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.35)
