extends Node2D

# Venom Fan — Venomancer transform of Fan of Knives. Each knife adds a poison stack;
# already-poisoned targets get an extra stack (the "ricochet" lands as more venom).

const RANGE: float = 230.0

var damage: int = 22
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
	if VfxManager:
		for i in 8:
			var a: float = TAU * float(i) / 8.0
			VfxManager.spawn_hit_sparks(origin + Vector2(cos(a), sin(a)) * 110.0, Color(0.5, 0.9, 0.3, 1), 4)
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if origin.distance_to((e as Node2D).global_position) > RANGE:
					continue
				if e.has_method("take_damage"):
					e.call("take_damage", damage, origin)
				var stacks: int = 1
				if e.has_method("is_poisoned") and bool(e.call("is_poisoned")):
					stacks = 2
				if e.has_method("apply_poison"):
					e.call("apply_poison", stacks, 4.0, float(damage) * 0.2)
	var t := get_tree().create_timer(0.3)
	t.timeout.connect(queue_free)
