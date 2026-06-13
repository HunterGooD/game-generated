extends Node2D

# Meteor — telegraph circle on the ground, falling rock, then big explosion.

const BASE_TELEGRAPH_TIME: float = 0.75
const BLAST_RADIUS: float = 160.0
const SHOWER_SCALE: float = 0.6
const SHOWER_DAMAGE_MULT: float = 0.5
const SHOWER_SPREAD: float = 150.0
var TELEGRAPH_TIME: float = BASE_TELEGRAPH_TIME

@export var telegraph: Sprite2D
@export var rock: Sprite2D

var damage: int = 30
var radius_mult: float = 1.0
var scale_mult: float = 1.0
# Meteor Shower talent transform — the lead meteor shrinks and spawns 2-3 staggered
# copies of itself; `shower_child` guards against recursive re-spawning.
var _is_shower: bool = false
var _is_shower_child: bool = false
var _visual_only: bool = false
var _ctx: SkillContext = null


func setup(dmg: int) -> void:
	setup_context(SkillContext.from_mods(Vector2.ZERO, dmg, {}))


func setup_context(ctx: SkillContext) -> void:
	_ctx = ctx
	var dmg := ctx.damage
	damage = dmg
	_visual_only = ctx.is_visual_only
	_is_shower = (
		ctx.transform == "meteor_shower"
		or (ctx.definition != null and ctx.definition.id == "meteor_shower")
	)
	_is_shower_child = bool(ctx.get_mod("shower_child", false))
	radius_mult = 1.0 + float(ctx.get_mod("radius_bonus", 0.0))
	scale_mult = float(ctx.get_mod("scale", 1.0))
	if _is_shower and not _is_shower_child:
		# Children receive the already-halved damage + shrunken scale via mods.
		damage = int(round(float(dmg) * SHOWER_DAMAGE_MULT))
		scale_mult *= SHOWER_SCALE
	scale = Vector2(scale_mult, scale_mult)


func _ready() -> void:
	# Pyrocrown unique — meteor lands faster.
	if InventorySystem and InventorySystem.has_unique("pyrocrown"):
		TELEGRAPH_TIME = 0.45
	# Telegraph pulses red.
	if telegraph:
		telegraph.modulate = Color(1, 0.4, 0.4, 0.85)
		var pulse := create_tween().set_loops(int(TELEGRAPH_TIME / 0.3) + 1)
		pulse.tween_property(telegraph, "scale", telegraph.scale * 1.1, 0.15).set_trans(
			Tween.TRANS_SINE
		)
		pulse.tween_property(telegraph, "scale", telegraph.scale * 0.95, 0.15).set_trans(
			Tween.TRANS_SINE
		)
	# Rock falls from above and onto telegraph point.
	if rock:
		rock.position = Vector2(220.0, -540.0)
		rock.modulate.a = 1.0
		rock.rotation = -PI / 4.0
		var t := create_tween()
		(
			t
			. tween_property(rock, "position", Vector2.ZERO, TELEGRAPH_TIME)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)

	# Wait for telegraph then explode.
	var timer := get_tree().create_timer(TELEGRAPH_TIME)
	timer.timeout.connect(_explode)

	# Meteor Shower: the lead meteor schedules its extra rocks.
	if _is_shower and not _is_shower_child:
		var count: int = 2 + (randi() % 2)
		# Cinder Cascade unique — the shower rains 2 additional meteors.
		if InventorySystem and InventorySystem.has_unique("shower_cascade"):
			count += 2
		for i in count:
			var t := get_tree().create_timer(0.25 * float(i + 1))
			t.timeout.connect(_spawn_shower_child)


func _spawn_shower_child() -> void:
	if not is_inside_tree():
		return
	var packed: PackedScene = load(scene_file_path) as PackedScene
	if packed == null:
		return
	var child: Node2D = packed.instantiate()
	child.position = (
		global_position
		+ Vector2(
			randf_range(-SHOWER_SPREAD, SHOWER_SPREAD), randf_range(-SHOWER_SPREAD, SHOWER_SPREAD)
		)
	)
	var mods: Dictionary = {
		"transform": "meteor_shower",
		"shower_child": true,
		"scale": scale_mult,
		"radius_bonus": radius_mult - 1.0,
		"visual_only": _visual_only,
	}
	var ctx := SkillContext.from_mods(Vector2.ZERO, damage, mods)
	SkillContext.apply(child, ctx)
	var parent := get_tree().current_scene
	if parent == null:
		child.queue_free()
		return
	parent.add_child(child)


func _explode() -> void:
	if telegraph:
		telegraph.visible = false
	if rock:
		rock.visible = false

	# Big VFX.
	if VfxManager:
		VfxManager.spawn_explosion(
			global_position, 1.6 * scale_mult * radius_mult, Color(1.0, 0.55, 0.25, 1)
		)
		VfxManager.screen_shake(14.0 * scale_mult, 0.45)
		VfxManager.screen_flash(Color(1.0, 0.6, 0.3, 0.35), 0.22)
		VfxManager.hit_stop(0.06)

	# Damage all enemies within blast. Skipped on multiplayer visual-only copies —
	# the caster's machine is authoritative (same rule as SkillEffectAreaDamage).
	if _visual_only:
		var t_vis := get_tree().create_timer(1.2)
		t_vis.timeout.connect(queue_free)
		return
	var blast: float = BLAST_RADIUS * radius_mult * scale_mult
	var tree := get_tree()
	if tree:
		var enemies := tree.get_nodes_in_group("enemy")
		for e in enemies:
			if not is_instance_valid(e):
				continue
			var pos: Vector2 = (e as Node2D).global_position
			var d: float = global_position.distance_to(pos)
			if d <= blast:
				var falloff: float = clamp(1.0 - (d / blast) * 0.5, 0.4, 1.0)
				var dmg: int = int(round(float(damage) * falloff))
				if e.has_method("take_damage"):
					e.take_damage(dmg, global_position)
				if e.has_method("mark_element"):
					e.call("mark_element", "fire")
				if _ctx != null:
					_ctx.apply_on_hit(e)

	# Pyrocrown unique / Cinderweave 5pc — leave a burning crater that ticks fire damage.
	if (
		InventorySystem
		and (
			InventorySystem.has_unique("pyrocrown")
			or InventorySystem.has_set_effect("mage_emberfall")
		)
	):
		_spawn_burning_crater()

	# Self-destruct after secondary effects play out.
	var t2 := get_tree().create_timer(1.2)
	t2.timeout.connect(queue_free)


func _spawn_burning_crater() -> void:
	var crater_scene_path: String = "res://scenes/combat/player/fire_ring.tscn"
	if not ResourceLoader.exists(crater_scene_path):
		return
	var packed: PackedScene = load(crater_scene_path) as PackedScene
	if packed == null:
		return
	var ring: Node2D = packed.instantiate()
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position
	if ring.has_method("setup"):
		ring.call("setup", damage)
