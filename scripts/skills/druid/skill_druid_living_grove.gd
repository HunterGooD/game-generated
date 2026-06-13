extends Node2D

# Living Grove — Grovekeeper (Druid) R. A grove for 10s: allies inside are shielded
# (and the local druid healed), enemies inside are rooted (heavy slow).

const LIFETIME: float = 10.0
const RADIUS: float = 220.0
const TICK: float = 1.0

var visual_only: bool = false
var caster: Node2D = null
var _life: float = LIFETIME
var _t: float = 0.0


func setup_context(ctx: SkillContext) -> void:
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 4
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	var spr := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_ring.png"
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		spr.texture = load(path) as Texture2D
		var w: float = float(spr.texture.get_width())
		if w > 0.0:
			spr.scale = Vector2.ONE * (RADIUS * 2.0 / w)
	spr.modulate = Color(0.4, 0.9, 0.45, 0.4)
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
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= RADIUS and e.has_method("apply_slow"):
			e.call("apply_slow", 0.4, 0.3)
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	for grp in ["player", "remote_player"]:
		for a in tree.get_nodes_in_group(grp):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if global_position.distance_to((a as Node2D).global_position) <= RADIUS:
				if a.has_method("apply_aura"):
					a.call("apply_aura", 1.0, 0.15, 1.2)
				if a.has_method("add_shield"):
					a.call("add_shield", 8.0, -1.0)
	# Local druid heals while standing in their own grove.
	if caster is Node2D and global_position.distance_to((caster as Node2D).global_position) <= RADIUS:
		if GameManager and GameManager.has_method("heal_player"):
			GameManager.heal_player(int(round(float(GameManager.player_max_hp) * 0.02)))
