class_name LeafSpirit
extends Node2D

# Rootbound Spirits (Grovekeeper passive): a small leaf wisp conjured whenever
# the druid heals or shields. It darts at the nearest enemy and bursts for a
# fraction of the druid's damage. Solo behavior per the spec; the co-op
# "fly to a wounded ally" variant is future work.

const SPEED: float = 420.0
const LIFETIME: float = 3.0
const DAMAGE_FRAC: float = 0.35
const HIT_RADIUS: float = 26.0
const SEEK_RADIUS: float = 620.0

var _target: Node2D = null
var _life: float = LIFETIME
var _spin: float = 0.0


func _ready() -> void:
	z_index = 55


func _process(delta: float) -> void:
	_life -= delta
	_spin += delta * 9.0
	queue_redraw()
	if _life <= 0.0:
		queue_free()
		return
	if _target == null or not is_instance_valid(_target) or bool(_target.get("dead")):
		_target = _nearest_enemy()
		if _target == null:
			return
	var to: Vector2 = _target.global_position - global_position
	if to.length() <= HIT_RADIUS:
		_burst()
		return
	global_position += to.normalized() * SPEED * delta


func _burst() -> void:
	var dmg: int = 14
	if GameManager:
		dmg = maxi(1, int(round(float(GameManager.get_effective_damage()) * DAMAGE_FRAC)))
	if _target and is_instance_valid(_target) and _target.has_method("take_damage"):
		_target.call("take_damage", dmg, global_position)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.4, 0.9, 0.45, 1), 8)
	queue_free()


func _nearest_enemy() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = SEEK_RADIUS
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")) or not (e is Node2D):
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _draw() -> void:
	# A glowing seed with three spinning leaf blades.
	draw_circle(Vector2.ZERO, 8.0, Color(0.2, 0.7, 0.3, 0.8))
	draw_circle(Vector2.ZERO, 4.0, Color(0.7, 1.0, 0.7, 0.95))
	for i in 3:
		var ang: float = _spin + TAU * float(i) / 3.0
		var tip: Vector2 = Vector2(cos(ang), sin(ang)) * 14.0
		draw_line(Vector2.ZERO, tip, Color(0.45, 0.95, 0.5, 0.7), 2.5, true)
