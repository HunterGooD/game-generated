extends Node2D

# Ally Arc — Conductor transform of Chain Bolt. The arc threads allies and enemies:
# allies get a small shield (and amplify the next jump), enemies take damage + static.

const MAX_LINKS: int = 6
const JUMP_RANGE: float = 260.0

var damage: int = 18
var visual_only: bool = false
var caster: Node2D = null


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	var origin: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	if not visual_only:
		var used: Dictionary = {}
		var prev: Vector2 = origin
		var amp: float = 1.0
		for _i in MAX_LINKS:
			var t: Node2D = _nearest(prev, used)
			if t == null:
				break
			used[t.get_instance_id()] = true
			_arc(prev, (t as Node2D).global_position)
			if t.is_in_group("enemy"):
				if t.has_method("take_damage"):
					t.call("take_damage", int(round(float(damage) * amp)), prev)
				if t.has_method("mark_element"):
					t.call("mark_element", "storm")
			else:
				if t.has_method("add_shield"):
					t.call("add_shield", float(damage) * 0.5, -1.0)
				amp += 0.25  # passing through an ally charges the next jump
			prev = (t as Node2D).global_position
	var tt := get_tree().create_timer(0.4)
	tt.timeout.connect(queue_free)


func _nearest(from: Vector2, used: Dictionary) -> Node2D:
	var best: Node2D = null
	var bd: float = JUMP_RANGE
	for grp in ["enemy", "remote_player"]:
		for n in get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(n) or not (n is Node2D) or used.has(n.get_instance_id()) or bool(n.get("dead")):
				continue
			var d: float = from.distance_to((n as Node2D).global_position)
			if d < bd:
				bd = d
				best = n
	return best


func _arc(a: Vector2, b: Vector2) -> void:
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.6, 0.85, 1.0, 0.9)
	line.add_point(to_local(a))
	line.add_point(to_local(b))
	add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.35)
