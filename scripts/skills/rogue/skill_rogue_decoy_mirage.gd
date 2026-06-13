extends Node2D

# Decoy Mirage — Trickster (Rogue) R. A standing mirage that taunts nearby enemies
# for 8s; when it expires it bursts into smoke that blinds (slows) enemies and
# grants allies evasion.

const LIFETIME: float = 8.0
const TAUNT_RADIUS: float = 240.0
const BURST_RADIUS: float = 220.0

var visual_only: bool = false
var caster: Node2D = null
var _life: float = LIFETIME


func setup_context(ctx: SkillContext) -> void:
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 20
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	add_to_group("pet_ally")  # so enemies treat the decoy as a target
	var spr := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_flame.png"
	if ResourceLoader.exists(path):
		spr.texture = load(path) as Texture2D
	spr.modulate = Color(0.6, 0.7, 1.0, 0.7)
	spr.scale = Vector2(1.2, 1.6)
	add_child(spr)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_burst()
		queue_free()
		return
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= TAUNT_RADIUS and e.has_method("apply_taunt"):
			e.call("apply_taunt", self, 0.6)


func _burst() -> void:
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.3, Color(0.6, 0.7, 1.0, 1))
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= BURST_RADIUS and e.has_method("apply_slow"):
			e.call("apply_slow", 3.0, 0.5)  # "blind" ~ disoriented slow
	for grp in ["player", "remote_player"]:
		for a in tree.get_nodes_in_group(grp):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if global_position.distance_to((a as Node2D).global_position) <= BURST_RADIUS and a.has_method("apply_evasion"):
				a.call("apply_evasion", 0.2, 4.0)
