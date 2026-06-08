extends Node2D

# Living Battery — Conductor (Stormcaller) R. A 12s field that empowers allies (cast
# / move speed via the aura + dome hooks) and statics enemies near them; the caster
# regains mana while it runs.

const LIFETIME: float = 12.0
const RADIUS: float = 240.0
const MANA_TICK: float = 1.0

var visual_only: bool = false
var caster: Node2D = null
var _life: float = LIFETIME
var _mana_t: float = 0.0


func setup_context(ctx: SkillContext) -> void:
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 5
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
	spr.modulate = Color(0.5, 0.8, 1.0, 0.4)
	add_child(spr)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	var tree := get_tree()
	if tree == null:
		return
	for grp in ["player", "remote_player"]:
		for a in tree.get_nodes_in_group(grp):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if global_position.distance_to((a as Node2D).global_position) <= RADIUS:
				if a.has_method("apply_aura"):
					a.call("apply_aura", 1.15, 0.0, 0.4)
				if a.has_method("enter_dome"):
					a.call("enter_dome", 0.4)
	_mana_t -= delta
	if _mana_t <= 0.0:
		_mana_t = MANA_TICK
		if GameManager and GameManager.has_method("regen_mana"):
			GameManager.regen_mana(6.0)
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or bool(e.get("dead")):
				continue
			if global_position.distance_to((e as Node2D).global_position) <= RADIUS and e.has_method("mark_element"):
				e.call("mark_element", "storm")
