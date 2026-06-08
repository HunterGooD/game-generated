extends Node2D

# Falling Brand — Battlemage transform of Meteor (slot 3). Half the radius/range
# of Meteor and lower direct damage, but it lands almost instantly just ahead of
# the caster and sets the ground ablaze (burn). A melee-friendly burst the
# Battlemage can drop mid-fight without a long telegraph.

const TELEGRAPH_TIME: float = 0.22
const BLAST_RADIUS: float = 90.0
const BURN_DURATION: float = 5.0

var damage: int = 30
var visual_only: bool = false
var caster: Node2D = null


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 50
	var brand := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		brand.texture = load(path) as Texture2D
	brand.modulate = Color(1.0, 0.5, 0.15, 0.0)
	brand.position = Vector2(0, -260)
	brand.rotation = PI / 2.0
	add_child(brand)
	var t := create_tween()
	t.tween_property(brand, "position", Vector2.ZERO, TELEGRAPH_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(brand, "modulate:a", 1.0, TELEGRAPH_TIME * 0.6)
	var timer := get_tree().create_timer(TELEGRAPH_TIME)
	timer.timeout.connect(_explode)


func _explode() -> void:
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.0, Color(1.0, 0.5, 0.2, 1))
		VfxManager.screen_shake(5.0, 0.18)
		VfxManager.hit_stop(0.04)
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if global_position.distance_to((e as Node2D).global_position) > BLAST_RADIUS:
					continue
				if e.has_method("take_damage"):
					e.take_damage(damage, global_position)
				if e.has_method("apply_burn"):
					e.call("apply_burn", BURN_DURATION, float(damage) * 0.3)
	var t2 := get_tree().create_timer(0.5)
	t2.timeout.connect(queue_free)
