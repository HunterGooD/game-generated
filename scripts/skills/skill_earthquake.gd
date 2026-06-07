extends Node2D

# Earthquake — three expanding shockwave rings outward from the caster.

const BASE_WAVES: int = 3
const BASE_RING_GAP: float = 0.28
const MAX_RADIUS: float = 280.0
const RING_DURATION: float = 0.55

var damage: int = 24
var hit_per_wave: Array = []
var num_waves: int = BASE_WAVES
var ring_gap: float = BASE_RING_GAP


func setup_with_mods(_dir: Vector2, dmg: int, _mods: Dictionary) -> void:
	damage = dmg


func _ready() -> void:
	# Quakegrasp Gauntlets unique — 5 waves, 25% faster.
	if InventorySystem and InventorySystem.has_unique("quakegrasp_gauntlets"):
		num_waves = 5
		ring_gap = BASE_RING_GAP * 0.75
	for i in num_waves:
		hit_per_wave.append({})
		var t := get_tree().create_timer(float(i) * ring_gap)
		t.timeout.connect(_spawn_ring.bind(i))
	# Auto-destroy after final ring fades.
	var done := get_tree().create_timer(float(num_waves) * ring_gap + RING_DURATION + 0.2)
	done.timeout.connect(queue_free)
	if VfxManager:
		VfxManager.screen_shake(8.0, 0.6)


func _spawn_ring(idx: int) -> void:
	if not is_inside_tree():
		return
	# Visual ring expanding.
	var ring := Sprite2D.new()
	var path := "res://assets/sprites/effects/meteor_telegraph.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
	ring.modulate = Color(1.0, 0.5, 0.25, 0.85)
	ring.scale = Vector2(0.3, 0.3)
	ring.global_position = global_position
	ring.z_index = 50
	get_tree().current_scene.add_child(ring)
	var target_scale: float = 0.3 + (float(idx + 1) / float(num_waves)) * 2.0
	var tw := ring.create_tween().set_parallel(true)
	(
		tw
		. tween_property(ring, "scale", Vector2(target_scale, target_scale), RING_DURATION)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(ring, "modulate:a", 0.0, RING_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN
	)
	tw.chain().tween_callback(ring.queue_free)

	# Damage tick — sweep enemies in expanding radius. Apply damage as enemies enter.
	var max_r: float = (float(idx + 1) / float(num_waves)) * MAX_RADIUS
	_damage_ring(idx, max_r)

	if VfxManager:
		VfxManager.spawn_explosion(global_position, 0.7 + float(idx) * 0.4, Color(1, 0.55, 0.25, 1))


func _damage_ring(idx: int, max_r: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hits: Dictionary = hit_per_wave[idx]
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var id: int = e.get_instance_id()
		if hits.has(id):
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d <= max_r:
			hits[id] = true
			if e.has_method("take_damage"):
				e.take_damage(damage, global_position)
