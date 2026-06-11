class_name DungeonGloom
extends Node2D

## "Suffocating Gloom" affix hazard: a dark cloud that drifts slowly after the nearest
## player and ticks damage to anyone standing inside it. Slower than a player so it is
## always kiteable — the punishment is for standing still. Built in code, like ArenaZone.
##
## Damages players via the canonical group-iteration + receive_damage_payload path
## (mirrors boss_telegraph.gd). Host/solo-gated by the controller that spawns it.

const RADIUS: float = 150.0
const MOVE_SPEED: float = 62.0  # well below player base speed → kiteable
const TICK: float = 0.6
const BASE_TICK_DAMAGE: int = 5

var difficulty: int = 0
var _t: float = 0.0
var _pulse: float = 0.0


func _ready() -> void:
	z_index = 30
	add_to_group("dungeon_hazard")
	# Start off-screen-ish from the player so it has to drift in.
	var p := _nearest_player()
	if p:
		global_position = p.global_position + Vector2(0, -1).rotated(randf() * TAU) * 520.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if GameManager and GameManager.game_over:
		return
	# Drift toward the nearest player.
	var target := _nearest_player()
	if target:
		var to: Vector2 = target.global_position - global_position
		if to.length() > 4.0:
			global_position += to.normalized() * MOVE_SPEED * delta
	_pulse = fmod(_pulse + delta, TAU)
	queue_redraw()
	# Periodic DoT to anyone inside the cloud.
	_t += delta
	if _t >= TICK:
		_t = 0.0
		_tick_damage()


func _tick_damage() -> void:
	# Host-authoritative: the client's visual cloud drifts + ticks visually but deals no
	# damage (the host adjudicates → player_hit). Solo always applies.
	if NetManager and NetManager.is_multiplayer and not NetManager.is_host:
		return
	var dmg: int = BASE_TICK_DAMAGE + 2 * difficulty
	var tree := get_tree()
	if tree == null:
		return
	for p in tree.get_nodes_in_group("player"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if (p as Node2D).global_position.distance_to(global_position) > RADIUS:
			continue
		if p.has_method("receive_damage_payload"):
			p.call(
				"receive_damage_payload",
				DamageInstance.new(float(dmg), null, self, [&"environment", &"gloom"], [])
			)
		elif p.has_method("take_damage"):
			p.call("take_damage", dmg)


func _draw() -> void:
	var a: float = 0.22 + 0.05 * sin(_pulse * 2.0)
	draw_circle(Vector2.ZERO, RADIUS, Color(0.18, 0.12, 0.24, a))
	draw_circle(Vector2.ZERO, RADIUS * 0.66, Color(0.10, 0.06, 0.16, a + 0.08))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(0.5, 0.4, 0.6, 0.5), 3.0, true)


func _nearest_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = INF
	for p in tree.get_nodes_in_group("player"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		var d: float = (p as Node2D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
