class_name SkillCaster
extends RefCounted

# Stateless spawn logic for a resolved skill cast. Given a SkillDefinition, the
# caster, the aim point, the precomputed damage and the built mods, it positions
# the skill, instantiates it, runs its setup, parents it into the scene, reparents
# "attached" skills onto the caster, and broadcasts a visual-only copy in MP.
#
# Extracted verbatim from the old SkillSystem.try_cast body — casting behaviour is
# unchanged; SkillSystem keeps per-player state (cooldowns/mana/modifiers) and just
# delegates the spawn here.


static func spawn(
	def: SkillDefinition,
	caster: Node2D,
	mouse_world: Vector2,
	scaled_damage: int,
	mods: Dictionary
) -> bool:
	# Scene-based skills instantiate their .tscn; script-carrier skills (no .tscn)
	# build Node2D + set_script. instantiate_node() handles both.
	var node: Node = def.instantiate_node()
	if node == null:
		push_warning("Skill has neither scene nor script: %s" % def.id)
		return false

	# Aim direction (same rule as before: fall back to RIGHT when aiming on self).
	var dir: Vector2 = mouse_world - caster.global_position
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	# Spawn rules: position before add_child, setup before add_child.
	var spawn_pos: Vector2 = caster.global_position
	match def.spawn:
		"ahead_of_caster":
			spawn_pos = caster.global_position + dir * 80.0
		"projectile":
			spawn_pos = caster.global_position + dir * 24.0
		"at_target":
			spawn_pos = mouse_world
		"attached_to_caster", "with_caster", "at_caster":
			spawn_pos = caster.global_position
		_:
			spawn_pos = caster.global_position
	(node as Node2D).position = spawn_pos

	# Bundle the cast into a typed SkillContext and dispatch. The dispatcher
	# prefers setup_context() but falls back to the legacy setup_with_mods/
	# setup_meteor/setup for scenes not yet migrated, so behaviour is unchanged.
	var ctx := SkillContext.from_mods(dir, scaled_damage, mods, mouse_world)
	ctx.definition = def
	SkillContext.apply(node, ctx)

	var tree := caster.get_tree()
	if tree == null or tree.current_scene == null:
		node.queue_free()
		return false
	tree.current_scene.add_child(node)

	# Whirlwind/Stone Armor follow the caster — reparent so they track movement.
	if def.spawn == "attached_to_caster":
		var current_parent := node.get_parent()
		if current_parent:
			current_parent.remove_child(node)
		caster.add_child(node)
		(node as Node2D).position = Vector2.ZERO

	# Multiplayer: broadcast a visual-only copy so other peers see our cast.
	if NetManager and NetManager.is_multiplayer:
		var ns := tree.current_scene.get_node_or_null("NetSync")
		if ns and ns.has_method("broadcast_skill_cast"):
			ns.call("broadcast_skill_cast", def.id, def.scene_path, spawn_pos, dir, scaled_damage)

	return true
