extends Node2D

# Plague Bloom — Venomancer (Rogue) R. Infects an area: enemies inside are poisoned
# every second; a poisoned enemy that dies bursts into a poison cloud and the zone
# lingers a little longer for each burst.

const BASE_LIFETIME: float = 8.0
const RADIUS: float = 170.0
const TICK: float = 1.0

var damage: int = 20
var visual_only: bool = false
var caster: Node2D = null
var _life: float = BASE_LIFETIME
var _t: float = 0.0
var _seen_hp: Dictionary = {}


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
	spr.modulate = Color(0.4, 0.8, 0.2, 0.4)
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
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var id: int = e.get_instance_id()
		if bool(e.get("dead")):
			# A poisoned death inside the zone extends it (cloud burst).
			if _seen_hp.has(id):
				_life += 0.3
				if VfxManager:
					VfxManager.spawn_explosion((e as Node2D).global_position, 0.8, Color(0.4, 0.8, 0.2, 1))
				_seen_hp.erase(id)
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		if e.has_method("apply_poison"):
			e.call("apply_poison", 1, 4.0, float(damage) * 0.25)
			_seen_hp[id] = true
