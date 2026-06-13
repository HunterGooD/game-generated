extends Node2D

# Caltrops — scatter spikes in a 3x3 grid at target. Each spike is an Area2D
# that DoT-damages and slows enemies on contact, lasts 10 seconds.

const LIFETIME: float = 10.0
const SPACING: float = 38.0
const TICK_INTERVAL: float = 0.6

var damage: int = 6
var slow_t: float = 1.0
var slow_mult: float = 0.55
var extra_lifetime: float = 0.0

@onready var grid_root: Node2D = self

var _ctx: SkillContext = null


func setup_context(ctx: SkillContext) -> void:
	_ctx = ctx
	var dmg := ctx.damage
	damage = dmg
	# Lasting Barbs modifier — each stack keeps the spikes on the ground longer.
	extra_lifetime = float(ctx.get_mod("duration_bonus", 0.0))


func _ready() -> void:
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_spell_caltrops.mp3", -10.0)
	var tex: Texture2D = null
	var path := "res://assets/sprites/effects/caltrop_spike.png"
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	# 3x3 grid.
	for yi in 3:
		for xi in 3:
			var local_pos := Vector2(float(xi - 1) * SPACING, float(yi - 1) * SPACING)
			local_pos += Vector2(randf_range(-6, 6), randf_range(-6, 6))
			_spawn_spike(local_pos, tex)
	var t := get_tree().create_timer(LIFETIME + extra_lifetime)
	t.timeout.connect(queue_free)
	# Mark of the Coil unique — detonate after 4 seconds for burst damage.
	if InventorySystem and InventorySystem.has_unique("mark_of_coil"):
		var detonate := get_tree().create_timer(4.0)
		detonate.timeout.connect(_detonate)


func _detonate() -> void:
	if not is_inside_tree():
		return
	var burst: float = SPACING * 3.0
	var burst_dmg: int = int(round(float(damage) * 6.0))
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if (e as Node2D).global_position.distance_to(global_position) <= burst:
			if e.has_method("take_damage"):
				e.take_damage(burst_dmg, global_position)
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.2, Color(0.6, 1.0, 0.4, 1))
		VfxManager.screen_shake(5.0, 0.2)


func _spawn_spike(local_pos: Vector2, tex: Texture2D) -> void:
	var spike := Area2D.new()
	spike.collision_layer = 0
	spike.collision_mask = 16
	spike.position = local_pos
	add_child(spike)
	spike.set_meta("damage_t", 0.0)

	var col := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 18.0
	col.shape = cs
	spike.add_child(col)

	var s := Sprite2D.new()
	if tex:
		s.texture = tex
	s.scale = Vector2(0.6, 0.6)
	s.modulate = Color(0.85, 0.85, 0.9, 1)
	s.rotation = randf() * TAU
	spike.add_child(s)


func _physics_process(delta: float) -> void:
	for spike in get_children():
		if not (spike is Area2D):
			continue
		var d_t: float = float(spike.get_meta("damage_t", 0.0)) - delta
		if d_t > 0.0:
			spike.set_meta("damage_t", d_t)
			continue
		spike.set_meta("damage_t", TICK_INTERVAL)
		for area in (spike as Area2D).get_overlapping_areas():
			if not area.is_in_group("enemy_hit"):
				continue
			var enemy = area.get_parent()
			if enemy and enemy.has_method("take_damage"):
				enemy.take_damage(damage, spike.global_position)
				if _ctx != null:
					_ctx.apply_on_hit(enemy)
			if enemy and enemy.has_method("apply_slow"):
				enemy.apply_slow(slow_t, slow_mult)
