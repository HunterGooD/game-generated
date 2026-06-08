extends Node2D

# Fault Zone — Titanbreaker transform of Earthquake (slot 3). A longer-lasting
# quake field that erupts random stone spikes inside it. Seismic Momentum (at cap)
# enlarges the zone by +30%.

const LIFETIME: float = 5.0
const BASE_RADIUS: float = 170.0
const SPIKE_INTERVAL: float = 0.35

var damage: int = 30
var radius: float = BASE_RADIUS
var visual_only: bool = false
var caster: Node2D = null
var _life: float = LIFETIME
var _spike_t: float = 0.0


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)
	# Seismic Momentum: a full stack bar enlarges the zone.
	var bonus: float = 1.0
	if caster and caster.has_method("consume_seismic_quake_bonus"):
		bonus = float(caster.call("consume_seismic_quake_bonus"))
	radius = BASE_RADIUS * bonus


func _ready() -> void:
	z_index = 4
	var ring := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_ring.png"
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
		var w: float = float(ring.texture.get_width())
		if w > 0.0:
			ring.scale = Vector2.ONE * (radius * 2.0 / w)
	ring.modulate = Color(0.65, 0.45, 0.25, 0.45)
	add_child(ring)
	if VfxManager:
		VfxManager.screen_shake(5.0, 0.3)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	_spike_t -= delta
	if _spike_t <= 0.0:
		_spike_t = SPIKE_INTERVAL
		_erupt_spike()


func _erupt_spike() -> void:
	var ang: float = randf() * TAU
	var dist: float = sqrt(randf()) * radius
	var spot: Vector2 = global_position + Vector2(cos(ang), sin(ang)) * dist
	if VfxManager:
		VfxManager.spawn_hit_sparks(spot, Color(0.7, 0.5, 0.3, 1), 8)
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if spot.distance_to((e as Node2D).global_position) > 60.0:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", damage, spot)
		if e.has_method("set"):
			(e as Node2D).set("velocity", (((e as Node2D).global_position - spot).normalized()) * 120.0)
