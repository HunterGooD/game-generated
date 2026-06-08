extends Node2D

# Crown of the Dead — Deathlord (Necromancer) R. For 18s the necromancer empowers
# the whole undead host (attack speed + move speed via the minion buff) and gains a
# personal melee buff to fight alongside them.

const DURATION: float = 18.0


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	var caster = mods.get("caster", null)
	if caster and caster.has_method("apply_buff"):
		caster.call("apply_buff", DURATION, 1.25, 1.1)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		for m in tree.get_nodes_in_group("necro_minion"):
			if is_instance_valid(m) and m.has_method("apply_blood_pact"):
				m.call("apply_blood_pact", DURATION, 1.35, 1.2)
	if VfxManager and caster is Node2D:
		VfxManager.spawn_hit_sparks((caster as Node2D).global_position, Color(0.6, 0.4, 0.9, 1), 18)
	queue_free()
