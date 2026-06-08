extends Node2D

# Storm Totem — Stormshaper transform of Summon Spirit. Plants a totem that zaps the
# nearest enemy with mini-lightning over its lifetime.

const LIFETIME: float = 12.0
const FIRE_INTERVAL: float = 0.7
const RANGE: float = 340.0

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
	z_index = 40
	add_to_group("pet_ally")
	var spr := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_flame.png"
	if ResourceLoader.exists(path):
		spr.texture = load(path) as Texture2D
	spr.modulate = Color(0.5, 0.7, 1.0, 1)
	spr.scale = Vector2(0.7, 1.1)
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
	_t = FIRE_INTERVAL
	var best: Node2D = null
	var bd: float = RANGE
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d < bd:
			bd = d
			best = e
	if best:
		if VfxManager:
			VfxManager.spawn_hit_sparks(best.global_position, Color(0.6, 0.85, 1.0, 1), 6)
		if best.has_method("take_damage"):
			best.call("take_damage", damage, global_position)
