extends Node2D

# Safehouse — Trickster transform of Smoke Bomb. A protective smoke zone: allies
# inside gain evasion, enemies inside briefly lose their target (short stop).

const LIFETIME: float = 5.0
const RADIUS: float = 190.0

var visual_only: bool = false
var _life: float = LIFETIME


func setup_context(ctx: SkillContext) -> void:
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
	spr.modulate = Color(0.6, 0.65, 0.75, 0.5)
	add_child(spr)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	for grp in ["player", "remote_player"]:
		for a in tree.get_nodes_in_group(grp):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if global_position.distance_to((a as Node2D).global_position) <= RADIUS and a.has_method("apply_evasion"):
				a.call("apply_evasion", 0.1, 0.4)
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= RADIUS and e.has_method("apply_slow"):
			e.call("apply_slow", 0.4, 0.6)
