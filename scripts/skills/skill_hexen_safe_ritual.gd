extends Node2D

# Safe Ritual — Coven Mother transform of Crimson Ritual. A warded circle: allies
# inside are shielded, enemies inside are cursed and damaged.

const LIFETIME: float = 6.0
const RADIUS: float = 200.0
const TICK: float = 0.8

var damage: int = 16
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
	spr.modulate = Color(0.4, 0.2, 0.6, 0.4)
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
	_t = TICK
	var tree := get_tree()
	if tree == null:
		return
	for grp in ["player", "remote_player"]:
		for a in tree.get_nodes_in_group(grp):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if global_position.distance_to((a as Node2D).global_position) <= RADIUS and a.has_method("add_shield"):
				a.call("add_shield", 8.0, -1.0)
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", int(round(float(damage) * 0.5)), global_position)
		if e.has_method("add_curse_stack"):
			e.call("add_curse_stack")
