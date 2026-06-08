extends Node2D

# Temporal Dome — Chronomancer (Mage) ascension R. An 8-second field centred on the
# cast point. Inside it: enemy projectiles crawl (-80% speed), enemies are slowed
# (-35%), and allies are empowered (faster cooldowns / mana / move, via
# player.enter_dome). Slowing foes feeds the caster's Borrowed Second passive.

const LIFETIME: float = 8.0
const RADIUS: float = 240.0
const ENEMY_SLOW_MULT: float = 0.65  # -35% move speed
const PROJ_SLOW_MULT: float = 0.2  # -80% projectile speed
const BORROW_TICK: float = 0.5

var visual_only: bool = false
var caster: Node2D = null
var _life: float = LIFETIME
var _borrow_t: float = 0.0
var _ring: Node2D = null


func setup_context(ctx: SkillContext) -> void:
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 5
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	_build_ring()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_spell_chain_lightning.mp3", -8.0)
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.4, Color(0.4, 0.9, 0.95, 1))


func _build_ring() -> void:
	var ring := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_ring.png"
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
		var tex_w: float = float(ring.texture.get_width())
		if tex_w > 0.0:
			ring.scale = Vector2.ONE * (RADIUS * 2.0 / tex_w)
	ring.modulate = Color(0.4, 0.9, 1.0, 0.4)
	add_child(ring)
	_ring = ring
	var tw := ring.create_tween().set_loops()
	tw.tween_property(ring, "rotation", TAU, 6.0).from(0.0)


func _process(delta: float) -> void:
	_life -= delta
	if _ring and is_instance_valid(_ring):
		_ring.modulate.a = 0.4 * clamp(_life / 1.0, 0.0, 1.0) if _life < 1.0 else 0.4
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	_borrow_t -= delta
	var grant_borrow: bool = _borrow_t <= 0.0
	if grant_borrow:
		_borrow_t = BORROW_TICK
	# Slow enemies inside.
	var slowed_any: bool = false
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		if e.has_method("apply_slow"):
			e.call("apply_slow", 0.3, ENEMY_SLOW_MULT)
			slowed_any = true
	# Crawl enemy projectiles inside.
	for p in tree.get_nodes_in_group("enemy_projectile"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if global_position.distance_to((p as Node2D).global_position) <= RADIUS:
			p.set("speed_mult", PROJ_SLOW_MULT)
	# Empower allies inside (local player + co-op puppets).
	for grp in ["player", "remote_player"]:
		for a in tree.get_nodes_in_group(grp):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if global_position.distance_to((a as Node2D).global_position) > RADIUS:
				continue
			if a.has_method("enter_dome"):
				a.call("enter_dome", 0.4)
	# Borrowed Second: banked while the dome keeps controlling the battlefield.
	if grant_borrow and slowed_any and caster and caster.has_method("notify_control_applied"):
		caster.call("notify_control_applied")
