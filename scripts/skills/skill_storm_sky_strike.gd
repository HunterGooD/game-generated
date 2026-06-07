extends Node2D

# Sky Strike — for ~5 s, a lightning bolt strikes a random point in a 280-px
# radius around the caster every 0.4 s. Each strike has a 0.2 s telegraph,
# small AOE damage, and adds Static Charge per enemy hit.
# Heaven's Spear unique: each strike leaves a small charged patch for 1.2 s.

const DURATION: float = 5.0
const STRIKE_INTERVAL: float = 0.4
const TELEGRAPH_TIME: float = 0.22
const STRIKE_RADIUS: float = 70.0
const SCATTER_RADIUS: float = 280.0
const PATCH_DURATION: float = 1.2
const PATCH_TICK: float = 0.3

var damage: int = 14
var visual_only: bool = false
var caster: Node = null
var life_t: float = DURATION
var strike_t: float = 0.0
var heavens_spear: bool = false


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)
	caster = mods.get("caster", null)
	if InventorySystem and InventorySystem.has_method("has_unique"):
		heavens_spear = bool(InventorySystem.call("has_unique", "storm_heavens_spear"))


func _ready() -> void:
	z_index = 65
	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/player/player_storm_sky_strike_warn.mp3", -10.0
		)


func _physics_process(delta: float) -> void:
	life_t -= delta
	if life_t <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	if caster == null or not is_instance_valid(caster):
		queue_free()
		return
	strike_t -= delta
	if strike_t > 0.0:
		return
	strike_t = STRIKE_INTERVAL
	# Pick a random point in the scatter radius around the caster.
	var angle: float = randf() * TAU
	var r: float = sqrt(randf()) * SCATTER_RADIUS
	var target_pos: Vector2 = (
		(caster as Node2D).global_position + Vector2(cos(angle), sin(angle)) * r
	)
	# Telegraph.
	var tel := Sprite2D.new()
	var tel_path := "res://assets/sprites/effects/sky_strike_telegraph.png"
	if ResourceLoader.exists(tel_path):
		tel.texture = load(tel_path) as Texture2D
	tel.modulate = Color(1.0, 0.3, 0.3, 0.85)
	tel.global_position = target_pos
	tel.z_index = 50
	if tel.texture:
		var src_h: float = float(tel.texture.get_size().y)
		if src_h > 1.0:
			var s: float = clamp(140.0 / src_h, 0.05, 0.5)
			tel.scale = Vector2(s, s)
	get_tree().current_scene.add_child(tel)
	# Fire the strike after the telegraph window.
	var t := get_tree().create_timer(TELEGRAPH_TIME)
	t.timeout.connect(_resolve_strike.bind(target_pos, tel))


func _resolve_strike(pos: Vector2, tel: Sprite2D) -> void:
	if is_instance_valid(tel):
		tel.queue_free()
	# Bolt visual.
	var bolt := Sprite2D.new()
	var bolt_path := "res://assets/sprites/effects/sky_strike_bolt.png"
	if ResourceLoader.exists(bolt_path):
		bolt.texture = load(bolt_path) as Texture2D
	bolt.modulate = Color(0.7, 0.95, 1.5, 1)
	bolt.global_position = pos
	bolt.z_index = 70
	if bolt.texture:
		var src_h: float = float(bolt.texture.get_size().y)
		if src_h > 1.0:
			var s: float = clamp(220.0 / src_h, 0.1, 1.5)
			bolt.scale = Vector2(s, s)
	get_tree().current_scene.add_child(bolt)
	var tw := bolt.create_tween()
	tw.tween_property(bolt, "modulate:a", 0.0, 0.25)
	tw.tween_callback(bolt.queue_free)
	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/player/player_storm_sky_strike_hit.mp3", -12.0
		)
	if VfxManager:
		VfxManager.screen_shake(2.0, 0.08)
	# Damage in radius and charge gain.
	var tree := get_tree()
	if tree:
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e):
				continue
			if e.get("dead") == true:
				continue
			if pos.distance_to((e as Node2D).global_position) <= STRIKE_RADIUS:
				if e.has_method("take_damage"):
					e.call("take_damage", damage, pos)
				if caster and caster.has_method("add_static_charge"):
					caster.call("add_static_charge", 1)
	# Heaven's Spear charged patch.
	if heavens_spear:
		_spawn_patch(pos)


func _spawn_patch(pos: Vector2) -> void:
	var patch := Sprite2D.new()
	var p_path := "res://assets/sprites/effects/sky_strike_telegraph.png"
	if ResourceLoader.exists(p_path):
		patch.texture = load(p_path) as Texture2D
	patch.modulate = Color(0.55, 0.85, 1.5, 0.85)
	patch.global_position = pos
	patch.z_index = 30
	if patch.texture:
		var src_h: float = float(patch.texture.get_size().y)
		if src_h > 1.0:
			var s: float = clamp(120.0 / src_h, 0.05, 0.5)
			patch.scale = Vector2(s, s)
	get_tree().current_scene.add_child(patch)
	# Tick damage for PATCH_DURATION.
	var tree := get_tree()
	var ticks: int = int(PATCH_DURATION / PATCH_TICK)
	for i in ticks:
		var t := get_tree().create_timer(float(i) * PATCH_TICK)
		t.timeout.connect(_patch_tick.bind(pos))
	var fade := patch.create_tween()
	fade.tween_interval(PATCH_DURATION - 0.3)
	fade.tween_property(patch, "modulate:a", 0.0, 0.3)
	fade.tween_callback(patch.queue_free)
	# Avoid unused warning.
	var _ignore = tree


func _patch_tick(pos: Vector2) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e.get("dead") == true:
			continue
		if pos.distance_to((e as Node2D).global_position) <= 70.0:
			if e.has_method("take_damage"):
				e.call("take_damage", max(2, int(round(float(damage) * 0.25))), pos)
