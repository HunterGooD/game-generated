extends Node2D

# Meteor — telegraph circle on the ground, falling rock, then big explosion.

const BASE_TELEGRAPH_TIME: float = 0.75
const BLAST_RADIUS: float = 160.0
var TELEGRAPH_TIME: float = BASE_TELEGRAPH_TIME

@export var telegraph: Sprite2D
@export var rock: Sprite2D

var damage: int = 30
var radius_mult: float = 1.0
var scale_mult: float = 1.0


func setup(dmg: int) -> void:
	setup_with_mods(Vector2.ZERO, dmg, {})


func setup_with_mods(dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	radius_mult = 1.0 + float(mods.get("radius_bonus", 0.0))
	scale_mult = float(mods.get("scale", 1.0))
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

	# Damage all enemies within blast.
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

	# Pyrocrown unique — leave a burning crater that ticks fire damage.
	if InventorySystem and InventorySystem.has_unique("pyrocrown"):
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
