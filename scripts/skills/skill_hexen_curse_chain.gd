extends Node2D

# Curse Chain — Curseweaver transform of Soul Tether. Links up to three enemies;
# damage to the chain is shared as curse damage to all linked.

const MAX_LINKS: int = 3
const LINK_RANGE: float = 280.0

var damage: int = 18
var visual_only: bool = false
var caster: Node2D = null


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	var origin: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	if not visual_only:
		var used: Dictionary = {}
		var prev: Vector2 = origin
		for _i in MAX_LINKS:
			var t: Node2D = _nearest(prev, used)
			if t == null:
				break
			used[t.get_instance_id()] = true
			_arc(prev, (t as Node2D).global_position)
			if t.has_method("take_damage"):
				t.call("take_damage", damage, prev)
			if t.has_method("add_curse_stack"):
				t.call("add_curse_stack")
			prev = (t as Node2D).global_position
	var tt := get_tree().create_timer(0.5)
	tt.timeout.connect(queue_free)


func _nearest(from: Vector2, used: Dictionary) -> Node2D:
	var best: Node2D = null
	var bd: float = LINK_RANGE
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
	line.default_color = Color(0.7, 0.1, 0.7, 0.9)
	line.add_point(to_local(a))
	line.add_point(to_local(b))
	add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.5)
