extends Node2D

# Crimson Ritual — stationary 220-px sigil that drains enemies for HP and
# heals the Hexen. 6 s lifetime. Bloodmoon unique adds an end-burst and
# refunds cooldown on kill.

const LIFETIME: float = 6.0
const RADIUS: float = 220.0
const TICK_INTERVAL: float = 0.4
const TICK_DMG_FRAC: float = 0.18
const HEAL_PCT_PER_TICK: float = 0.04

var damage: int = 14
var visual_only: bool = false
var bloodmoon: bool = false
var caster: Node2D = null
var tick_t: float = 0.0
var life_t: float = LIFETIME
var sprite: Sprite2D = null
var killed_inside: bool = false


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	caster = ctx.caster
	if InventorySystem and InventorySystem.has_method("has_unique"):
		bloodmoon = bool(InventorySystem.call("has_unique", "hexen_bloodmoon"))


func _ready() -> void:
	z_index = 6
	sprite = Sprite2D.new()
	var path := "res://assets/sprites/effects/crimson_ritual_zone.png"
	if ResourceLoader.exists(path):
		sprite.texture = load(path) as Texture2D
	sprite.modulate = Color(1.0, 0.18, 0.28, 0.9)
	if sprite.texture:
		var src_w: float = float(sprite.texture.get_size().x)
		if src_w > 1.0:
			var sc: float = (RADIUS * 2.0) / src_w
			sprite.scale = Vector2(sc, sc)
	add_child(sprite)
	var rot := sprite.create_tween().set_loops()
	rot.tween_property(sprite, "rotation", sprite.rotation + TAU, 5.0)


func _physics_process(delta: float) -> void:
	if visual_only:
		life_t -= delta
		if life_t <= 0.0:
			queue_free()
		return
	life_t -= delta
	if life_t <= 0.0:
		_finish()
		return
	tick_t -= delta
	if tick_t > 0.0:
		return
	tick_t = TICK_INTERVAL
	var tree := get_tree()
	if tree == null:
		return
	var hits_this_tick: int = 0
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e.get("dead") == true:
			continue
		if global_position.distance_to((e as Node2D).global_position) <= RADIUS:
			if e.has_method("take_damage"):
				e.call("take_damage", int(round(float(damage) * TICK_DMG_FRAC)), global_position)
			hits_this_tick += 1
	# Heal the Hexen per tick based on enemies drained.
	if hits_this_tick > 0 and GameManager:
		var pct: float = clamp(
			HEAL_PCT_PER_TICK * float(hits_this_tick), 0.0, HEAL_PCT_PER_TICK * 4.0
		)
		var heal_amt: int = int(round(float(GameManager.player_max_hp) * pct))
		if heal_amt > 0:
			GameManager.heal_player(heal_amt)


# Called by enemy._die when a kill happens (Bloodmoon refund).
func notify_kill(pos: Vector2) -> void:
	if visual_only:
		return
	if global_position.distance_to(pos) <= RADIUS:
		killed_inside = true


func _finish() -> void:
	# Bloodmoon end-burst.
	if bloodmoon:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e):
					continue
				if global_position.distance_to((e as Node2D).global_position) <= RADIUS:
					if e.has_method("take_damage"):
						e.call("take_damage", int(round(float(damage) * 2.2)), global_position)
		if VfxManager:
			VfxManager.spawn_explosion(global_position, 1.4, Color(0.95, 0.15, 0.3, 1))
			VfxManager.screen_shake(4.0, 0.18)
		# Kill-inside refund — reset Crimson Ritual cooldown on the caster.
		if killed_inside and caster and is_instance_valid(caster):
			var ss = caster.get_node_or_null("SkillSystem")
			if ss and ss.cooldowns.size() > 3:
				ss.cooldowns[3] = 0.0
				ss.cooldown_finished.emit(3)
	queue_free()
