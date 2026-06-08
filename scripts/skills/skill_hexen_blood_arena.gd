extends Node2D

# Blood Arena — Blood Witch transform of Crimson Ritual. A blood field: while the
# witch stands inside she is empowered; enemies inside bleed.

const LIFETIME: float = 6.0
const RADIUS: float = 190.0
const TICK: float = 0.6

var damage: int = 18
var visual_only: bool = false
var caster: Node2D = null
var _life: float = LIFETIME
var _t: float = 0.0


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	caster = ctx.caster
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
	spr.modulate = Color(0.6, 0.05, 0.1, 0.4)
	add_child(spr)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	if caster is Node2D and global_position.distance_to((caster as Node2D).global_position) <= RADIUS:
		if caster.has_method("apply_aura"):
			caster.call("apply_aura", 1.2, 0.0, 0.3)
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", int(round(float(damage) * 0.5)), global_position)
		if e.has_method("apply_bleed"):
			e.call("apply_bleed", 3.0, float(damage) * 0.25)
