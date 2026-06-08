extends Node2D

# War Ground — Warchief transform of Earthquake (slot 3). A held zone of trampled
# earth: allies inside take less damage, enemies inside are slowed. Light damage
# over time keeps it relevant offensively.

const LIFETIME: float = 6.0
const RADIUS: float = 200.0
const AURA_DR: float = 0.2
const ENEMY_SLOW_MULT: float = 0.6
const TICK_INTERVAL: float = 0.5

var damage: int = 16
var visual_only: bool = false
var _life: float = LIFETIME
var _tick_t: float = 0.0


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)


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
			ring.scale = Vector2.ONE * (RADIUS * 2.0 / w)
	ring.modulate = Color(0.75, 0.6, 0.35, 0.4)
	add_child(ring)


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
	_tick_t -= delta
	var do_dmg: bool = _tick_t <= 0.0
	if do_dmg:
		_tick_t = TICK_INTERVAL
	for grp in ["player", "remote_player"]:
		for a in tree.get_nodes_in_group(grp):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if global_position.distance_to((a as Node2D).global_position) <= RADIUS and a.has_method("apply_aura"):
				a.call("apply_aura", 1.0, AURA_DR, 0.4)
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		if e.has_method("apply_slow"):
			e.call("apply_slow", 0.3, ENEMY_SLOW_MULT)
		if do_dmg and e.has_method("take_damage"):
			e.call("take_damage", damage, global_position)
