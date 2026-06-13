extends Node2D

# Eye of the Storm — Tempest Lord (Stormcaller) R. A storm centred on the aim point:
# every tick a lightning bolt strikes a random enemy inside (storm-marked foes are
# prioritised).

const LIFETIME: float = 10.0
const RADIUS: float = 200.0
const STRIKE_INTERVAL: float = 0.5

var damage: int = 24
var visual_only: bool = false
var _life: float = LIFETIME
var _t: float = 0.0


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 4
	var spr := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_ring.png"
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		spr.texture = load(path) as Texture2D
		var w: float = float(spr.texture.get_width())
		if w > 0.0:
			spr.scale = Vector2.ONE * (RADIUS * 2.0 / w)
	spr.modulate = Color(0.5, 0.7, 1.0, 0.4)
	add_child(spr)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = STRIKE_INTERVAL
	_strike()


func _strike() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var inside: Array = []
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		inside.append(e)
	if inside.is_empty():
		return
	var target = inside[randi() % inside.size()]
	if VfxManager:
		VfxManager.spawn_hit_sparks((target as Node2D).global_position, Color(0.7, 0.9, 1.0, 1), 10)
	if target.has_method("take_damage"):
		target.call("take_damage", damage, global_position)
	if target.has_method("mark_element"):
		target.call("mark_element", "storm")
