extends Node2D

# Bloodstorm — Berserker transform of Whirlwind (slot 0). A spinning melee storm
# that applies Bleed and hits already-bleeding foes for extra damage. Follows the
# caster (spawned attached_to_caster).

const LIFETIME: float = 1.8
const RADIUS: float = 160.0
const TICK_INTERVAL: float = 0.2
const BLEED_BONUS: float = 0.5  # +50% vs bleeding targets

var damage: int = 14
var visual_only: bool = false
var _life: float = LIFETIME
var _tick_t: float = 0.0
var _blade: Sprite2D = null


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 40
	var blade := Sprite2D.new()
	var path := "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		blade.texture = load(path) as Texture2D
	blade.modulate = Color(0.8, 0.1, 0.12, 0.85)
	blade.scale = Vector2(1.6, 1.6)
	add_child(blade)
	_blade = blade
	var tw := blade.create_tween().set_loops()
	tw.tween_property(blade, "rotation", blade.rotation + TAU, 0.3)
	if VfxManager:
		VfxManager.screen_shake(1.5, 0.15)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = TICK_INTERVAL
		_tick_damage()


func _tick_damage() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		var dmg: int = damage
		if e.has_method("is_bleeding") and bool(e.call("is_bleeding")):
			dmg = int(round(float(dmg) * (1.0 + BLEED_BONUS)))
		if e.has_method("take_damage"):
			e.call("take_damage", dmg, global_position)
		if e.has_method("apply_bleed"):
			e.call("apply_bleed", 4.0, float(damage) * 0.35)
		if VfxManager and randi() % 3 == 0:
			VfxManager.spawn_hit_sparks((e as Node2D).global_position, Color(0.8, 0.1, 0.12, 1), 4)
