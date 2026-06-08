extends Node2D

# Bone Citadel — Bone Architect (Necromancer) R. A bone fortress for 10s: it fires
# spikes at nearby enemies and shelters allies inside (damage reduction).

const LIFETIME: float = 10.0
const RADIUS: float = 220.0
const FIRE_INTERVAL: float = 0.5

var damage: int = 22
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
	z_index = 5
	var spr := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_ring.png"
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		spr.texture = load(path) as Texture2D
		var w: float = float(spr.texture.get_width())
		if w > 0.0:
			spr.scale = Vector2.ONE * (RADIUS * 2.0 / w)
	spr.modulate = Color(0.8, 0.78, 0.7, 0.4)
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
			if global_position.distance_to((a as Node2D).global_position) <= RADIUS and a.has_method("apply_aura"):
				a.call("apply_aura", 1.0, 0.2, 0.4)
	_t -= delta
	if _t > 0.0:
		return
	_t = FIRE_INTERVAL
	var target: Node2D = null
	var bd: float = RADIUS + 80.0
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d < bd:
			bd = d
			target = e
	if target:
		if VfxManager:
			VfxManager.spawn_hit_sparks(target.global_position, Color(0.9, 0.85, 0.7, 1), 6)
		if target.has_method("take_damage"):
			target.call("take_damage", damage, global_position)
