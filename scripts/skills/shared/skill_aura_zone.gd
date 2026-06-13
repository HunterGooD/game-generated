extends Node2D

# Generic lingering skill zone, spawned + configured by SkillEffectAura. The composed
# skill runner frees itself immediately, so persistent zones live here instead: this
# node ticks on its own until `lifetime` elapses. Optionally it shows a telegraph for
# `telegraph_delay` seconds (with a strike explosion) before activating. While active
# it, each tick, damages enemies in `radius` (+ optional element mark), continuously
# slows enemies, and grants allies a damage-reduction aura. Gameplay is skipped when
# `visual_only` (the multiplayer remote copy) — visuals still play.

var radius: float = 150.0
var lifetime: float = 4.0
var tick_interval: float = 0.5
var telegraph_delay: float = 0.0
var damage: int = 0
var mark_element: String = ""
var enemy_slow_dur: float = 0.0
var enemy_slow_mult: float = 1.0
var ally_aura_dr: float = 0.0
var visual_only: bool = false
var strike_explosion_scale: float = 0.0
var strike_explosion_color: Color = Color(1, 1, 1, 1)
var strike_shake: float = 0.0
var ring_color: Color = Color(1, 1, 1, 0.4)
var ring_texture_path: String = ""

var _active: bool = false
var _life: float = 0.0
var _tick_t: float = 0.0
var _ring: Sprite2D = null


func configure(cfg: Dictionary) -> void:
	radius = float(cfg.get("radius", radius))
	lifetime = float(cfg.get("lifetime", lifetime))
	tick_interval = float(cfg.get("tick_interval", tick_interval))
	telegraph_delay = float(cfg.get("telegraph_delay", telegraph_delay))
	damage = int(cfg.get("damage", damage))
	mark_element = String(cfg.get("mark_element", mark_element))
	enemy_slow_dur = float(cfg.get("enemy_slow_dur", enemy_slow_dur))
	enemy_slow_mult = float(cfg.get("enemy_slow_mult", enemy_slow_mult))
	ally_aura_dr = float(cfg.get("ally_aura_dr", ally_aura_dr))
	visual_only = bool(cfg.get("visual_only", visual_only))
	strike_explosion_scale = float(cfg.get("strike_explosion_scale", strike_explosion_scale))
	strike_explosion_color = cfg.get("strike_explosion_color", strike_explosion_color)
	strike_shake = float(cfg.get("strike_shake", strike_shake))
	ring_color = cfg.get("ring_color", ring_color)
	ring_texture_path = String(cfg.get("ring_texture_path", ring_texture_path))


func _ready() -> void:
	z_index = 4
	_life = lifetime
	if telegraph_delay > 0.0:
		var tel := _make_ring(0.85)
		add_child(tel)
		var t := get_tree().create_timer(telegraph_delay)
		t.timeout.connect(func() -> void:
			if is_instance_valid(tel):
				tel.queue_free()
			_activate())
	else:
		_activate()


func _activate() -> void:
	_active = true
	if strike_explosion_scale > 0.0 and VfxManager:
		VfxManager.spawn_explosion(global_position, strike_explosion_scale, strike_explosion_color)
		if strike_shake > 0.0:
			VfxManager.screen_shake(strike_shake, 0.2)
	_ring = _make_ring(ring_color.a)
	add_child(_ring)


func _make_ring(alpha: float) -> Sprite2D:
	var s := Sprite2D.new()
	var path: String = ring_texture_path
	if path == "" or not ResourceLoader.exists(path):
		path = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		s.texture = load(path) as Texture2D
		var w: float = float(s.texture.get_width())
		if w > 0.0:
			s.scale = Vector2.ONE * (radius * 2.0 / w)
	var c: Color = ring_color
	c.a = alpha
	s.modulate = c
	return s


func _process(delta: float) -> void:
	if not _active:
		return
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	_tick_t -= delta
	var do_dmg: bool = _tick_t <= 0.0
	if do_dmg:
		_tick_t = tick_interval
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > radius:
			continue
		if enemy_slow_dur > 0.0 and e.has_method("apply_slow"):
			e.call("apply_slow", enemy_slow_dur, enemy_slow_mult)
		if do_dmg and damage > 0 and e.has_method("take_damage"):
			e.call("take_damage", damage, global_position)
		if do_dmg and mark_element != "" and e.has_method("mark_element"):
			e.call("mark_element", mark_element)
	if ally_aura_dr > 0.0:
		for grp in ["player", "remote_player"]:
			for a in tree.get_nodes_in_group(grp):
				if not is_instance_valid(a) or not (a is Node2D):
					continue
				if global_position.distance_to((a as Node2D).global_position) > radius:
					continue
				if a.has_method("apply_aura"):
					a.call("apply_aura", 1.0, ally_aura_dr, 0.4)
