class_name DungeonVolatileOrb
extends Node2D

## "Volatile Spheres" affix hazard: an unstable orb spawns near a player, swells over a
## short fuse, then detonates — dealing heavy damage to players inside the blast. The
## counter-play is to move clear before it blows (it telegraphs the blast radius the whole
## time). The controller spawns these on a timer. Built in code.
##
## (Follow-up idea: make the orb a destructible the party can pop early — see docs §4.)

const FUSE: float = 2.6
const BLAST_RADIUS: float = 165.0
const BASE_DAMAGE: int = 26

var difficulty: int = 0
var _t: float = 0.0
var _detonated: bool = false


func _ready() -> void:
	z_index = 31
	add_to_group("dungeon_hazard")
	set_process(true)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/enemy/enemy_boss_telegraph_warn.mp3", -18.0)
	queue_redraw()


func _process(delta: float) -> void:
	if _detonated:
		return
	if GameManager and GameManager.game_over:
		queue_free()
		return
	_t += delta
	queue_redraw()
	if _t >= FUSE:
		_detonate()


func _detonate() -> void:
	_detonated = true
	var dmg: int = BASE_DAMAGE + 8 * difficulty
	var tree := get_tree()
	if tree:
		for p in tree.get_nodes_in_group("player"):
			if not is_instance_valid(p) or not (p is Node2D):
				continue
			if (p as Node2D).global_position.distance_to(global_position) > BLAST_RADIUS:
				continue
			if p.has_method("receive_damage_payload"):
				p.call(
					"receive_damage_payload",
					DamageInstance.new(float(dmg), null, self, [&"environment", &"volatile_orb"], [])
				)
			elif p.has_method("take_damage"):
				p.call("take_damage", dmg)
	if VfxManager and VfxManager.has_method("screen_flash"):
		VfxManager.screen_flash(Color(1.0, 0.55, 0.2, 0.25), 0.2)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/enemy/enemy_boss_telegraph_warn.mp3", -6.0)
	# Brief flash before freeing.
	queue_redraw()
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(queue_free)


func _draw() -> void:
	var f: float = clampf(_t / FUSE, 0.0, 1.0)
	if _detonated:
		draw_circle(Vector2.ZERO, BLAST_RADIUS, Color(1.0, 0.6, 0.25, 0.6))
		return
	# Telegraph: faint blast radius + a swelling, brightening core that "charges".
	draw_circle(Vector2.ZERO, BLAST_RADIUS, Color(1.0, 0.4, 0.15, 0.10 + 0.10 * f))
	draw_arc(Vector2.ZERO, BLAST_RADIUS, 0.0, TAU, 40, Color(1.0, 0.5, 0.2, 0.4 + 0.4 * f), 2.0, true)
	var core_r: float = 14.0 + 22.0 * f
	draw_circle(Vector2.ZERO, core_r, Color(1.0, 0.7 - 0.4 * f, 0.25, 0.9))
