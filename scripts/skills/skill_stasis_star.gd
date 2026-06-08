extends Node2D

# Stasis Star — Chronomancer transform of Meteor (slot 3). A collapsing star at the
# target point: enemies take damage and are frozen in stasis briefly, allies inside
# gain a shield, and the caster gets a shield plus a flat cooldown refund.

const TELEGRAPH_TIME: float = 0.5
const BLAST_RADIUS: float = 150.0
const STASIS_DURATION: float = 0.7
const ALLY_SHIELD_FRAC: float = 0.5
const CASTER_CD_REFUND: float = 1.0

var damage: int = 28
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
	z_index = 50
	var star := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_flame.png"
	if ResourceLoader.exists(path):
		star.texture = load(path) as Texture2D
	star.modulate = Color(0.55, 0.85, 1.0, 0.9)
	star.scale = Vector2(2.4, 2.4)
	add_child(star)
	var tw := create_tween()
	tw.tween_property(star, "scale", Vector2(0.4, 0.4), TELEGRAPH_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(star, "rotation", TAU, TELEGRAPH_TIME)
	var t := get_tree().create_timer(TELEGRAPH_TIME)
	t.timeout.connect(_detonate)


func _detonate() -> void:
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.5, Color(0.5, 0.85, 1.0, 1))
		VfxManager.screen_shake(8.0, 0.3)
		VfxManager.screen_flash(Color(0.5, 0.8, 1.0, 0.25), 0.2)
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if global_position.distance_to((e as Node2D).global_position) > BLAST_RADIUS:
					continue
				if e.has_method("take_damage"):
					e.call("take_damage", damage, global_position)
				# Hard freeze (stasis) — apply_chill at the freeze cap.
				if e.has_method("apply_chill"):
					e.call("apply_chill", STASIS_DURATION, 4)
				elif e.has_method("apply_slow"):
					e.call("apply_slow", STASIS_DURATION, 0.05)
			for grp in ["player", "remote_player"]:
				for a in tree.get_nodes_in_group(grp):
					if not is_instance_valid(a) or not (a is Node2D):
						continue
					if global_position.distance_to((a as Node2D).global_position) > BLAST_RADIUS:
						continue
					if a.has_method("add_shield"):
						a.call("add_shield", float(damage) * ALLY_SHIELD_FRAC, -1.0)
		# Caster bonus: shield + flat cooldown refund on all skills.
		if caster:
			if caster.has_method("add_shield"):
				caster.call("add_shield", float(damage) * 0.75, -1.0)
			var ss = caster.get("skill_system")
			if ss and ss.has_method("reduce_all_cooldowns"):
				ss.call("reduce_all_cooldowns", CASTER_CD_REFUND)
			if caster.has_method("notify_control_applied"):
				caster.call("notify_control_applied")
	var t2 := get_tree().create_timer(0.5)
	t2.timeout.connect(queue_free)
