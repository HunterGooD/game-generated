class_name DungeonWrath
extends Node2D

## "Heaven's Wrath" affix hazard: on a cycle, lightning marks every player's CURRENT
## position; after a short warning the marks strike for heavy damage, then the sky goes
## quiet until the next cycle. Counter-play is to step off the mark during the warning.
##
## Self-contained: tracks active strikes as data and draws/fires them itself (no per-strike
## node). Damages via the canonical group + receive_damage_payload path. Kept at world
## origin so its _draw coords are world coords.

const CYCLE: float = 5.0  # seconds between volleys (the "cooldown")
const WARN: float = 1.1   # telegraph time before a mark strikes
const FLASH: float = 0.22 # how long the strike flash lingers
const STRIKE_RADIUS: float = 110.0
const BASE_DAMAGE: int = 20

var difficulty: int = 0
var _cycle_t: float = CYCLE  # fire the first volley almost immediately
var _strikes: Array = []  # each: {pos:Vector2, t:float, fired:bool}


func _ready() -> void:
	z_index = 39
	add_to_group("dungeon_hazard")
	global_position = Vector2.ZERO
	set_process(true)


func _process(delta: float) -> void:
	if GameManager and GameManager.game_over:
		return
	_cycle_t += delta
	if _cycle_t >= CYCLE:
		_cycle_t = 0.0
		_spawn_volley()
	for s in _strikes:
		s["t"] = float(s["t"]) + delta
		if not bool(s["fired"]) and float(s["t"]) >= WARN:
			s["fired"] = true
			_strike(s["pos"])
	# Drop finished strikes.
	var keep: Array = []
	for s in _strikes:
		if float(s["t"]) < WARN + FLASH:
			keep.append(s)
	_strikes = keep
	queue_redraw()


func _spawn_volley() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for p in tree.get_nodes_in_group("player"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		_strikes.append({"pos": (p as Node2D).global_position, "t": 0.0, "fired": false})
	if not _strikes.is_empty() and AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/enemy/enemy_boss_telegraph_warn.mp3", -16.0)


func _strike(center: Vector2) -> void:
	var dmg: int = BASE_DAMAGE + 7 * difficulty
	var tree := get_tree()
	if tree == null:
		return
	for p in tree.get_nodes_in_group("player"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if (p as Node2D).global_position.distance_to(center) > STRIKE_RADIUS:
			continue
		if p.has_method("receive_damage_payload"):
			p.call(
				"receive_damage_payload",
				DamageInstance.new(float(dmg), null, self, [&"environment", &"lightning"], [])
			)
		elif p.has_method("take_damage"):
			p.call("take_damage", dmg)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/enemy/enemy_boss_telegraph_warn.mp3", -8.0)


func _draw() -> void:
	for s in _strikes:
		var pos: Vector2 = s["pos"]
		var t: float = float(s["t"])
		if bool(s["fired"]):
			# Bright strike flash, fading over FLASH.
			var a: float = clampf(1.0 - (t - WARN) / FLASH, 0.0, 1.0)
			draw_circle(pos, STRIKE_RADIUS, Color(0.7, 0.9, 1.0, 0.6 * a))
			draw_line(pos + Vector2(0, -600), pos, Color(0.9, 0.95, 1.0, a), 5.0, true)
		else:
			# Telegraph: a tightening ring as the warning runs out.
			var f: float = clampf(t / WARN, 0.0, 1.0)
			draw_arc(pos, STRIKE_RADIUS, 0.0, TAU, 40, Color(0.55, 0.8, 1.0, 0.4 + 0.4 * f), 3.0, true)
			draw_arc(pos, STRIKE_RADIUS * (1.0 - 0.7 * f), 0.0, TAU, 32, Color(0.7, 0.9, 1.0, 0.7), 2.0, true)
