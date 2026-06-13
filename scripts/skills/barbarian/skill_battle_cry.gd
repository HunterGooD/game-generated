extends Node2D

# Battle Cry — AoE buff aura around the caster. Buffs every player in radius
# (current player + future coop allies) with damage and speed mults.

@export var sprite: Sprite2D

var radius: float = 240.0
var duration: float = 5.0
var dmg_mult: float = 1.6
var spd_mult: float = 1.3


func setup_context(ctx: SkillContext) -> void:
	radius = float(ctx.get_mod("radius", 240.0))
	duration = float(ctx.get_mod("duration", 5.0))
	dmg_mult = float(ctx.get_mod("dmg_mult", 1.6))
	spd_mult = float(ctx.get_mod("spd_mult", 1.3))


func _ready() -> void:
	# Visual aura that expands then fades.
	if sprite:
		sprite.scale = Vector2(0.6, 0.6)
		sprite.modulate = Color(1.0, 0.3, 0.3, 0.9)
		var tw := create_tween().set_parallel(true)
		(
			tw
			. tween_property(sprite, "scale", Vector2(2.6, 2.6), 0.7)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		tw.tween_property(sprite, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(
			Tween.EASE_IN
		)

	# Apply buff to all players in radius.
	var tree := get_tree()
	if tree:
		for p in tree.get_nodes_in_group("player"):
			if not is_instance_valid(p):
				continue
			if (p as Node2D).global_position.distance_to(global_position) <= radius:
				if p.has_method("apply_buff"):
					p.call("apply_buff", duration, dmg_mult, spd_mult)

	if VfxManager:
		VfxManager.screen_flash(Color(1, 0.2, 0.2, 0.18), 0.25)
		VfxManager.screen_shake(3.0, 0.2)

	# Crimson Aegis unique — burning aura that damages all enemies in radius.
	if InventorySystem and InventorySystem.has_unique("crimson_aegis"):
		_apply_crimson_aegis_burn()

	var t := get_tree().create_timer(0.8)
	t.timeout.connect(queue_free)


func _apply_crimson_aegis_burn() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var dmg: int = 30
	if GameManager:
		dmg = int(round(float(GameManager.get_effective_damage()) * 0.4))
	for e in SkillTargeting.in_radius(tree, global_position, radius):
		if e.has_method("take_damage"):
			e.take_damage(dmg, global_position)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(1, 0.5, 0.2, 1), 20)
