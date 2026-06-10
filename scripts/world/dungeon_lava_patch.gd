class_name DungeonLavaPatch
extends Node2D

## Infernal-biome floor hazard: a stationary pool of lava (rendered with the existing
## lava_pulse shader) that ticks damage to any player standing in it. The runner scatters a
## handful of these through an infernal dungeon. Damages via the canonical group-iteration +
## receive_damage_payload path (mirrors boss_telegraph.gd).

const FLOOR_TEX := "res://assets/textures/floors/ruins_floor.webp"
const LAVA_SHADER := "res://assets/shaders/lava_pulse.gdshader"
const RADIUS := 96.0
const TICK := 0.5
const BASE_TICK_DAMAGE := 6

var difficulty: int = 0
var _t := 0.0


func _ready() -> void:
	z_index = -8  # on the floor, under actors
	add_to_group("dungeon_hazard")
	_build_visual()
	set_process(true)


func _build_visual() -> void:
	if not ResourceLoader.exists(FLOOR_TEX):
		return
	var tex: Texture2D = load(FLOOR_TEX) as Texture2D
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	var ts: Vector2 = tex.get_size()
	if ts.x > 0 and ts.y > 0:
		s.scale = Vector2(RADIUS * 2.4 / ts.x, RADIUS * 2.4 / ts.y)
	s.modulate = Color(1.0, 0.55, 0.3)
	if ResourceLoader.exists(LAVA_SHADER):
		var mat := ShaderMaterial.new()
		mat.shader = load(LAVA_SHADER) as Shader
		mat.set_shader_parameter("warm_color", Color(1.0, 0.45, 0.18, 1.0))
		mat.set_shader_parameter("cool_color", Color(0.55, 0.12, 0.12, 1.0))
		mat.set_shader_parameter("pulse_speed", 0.7)
		mat.set_shader_parameter("scroll_speed", 0.25)
		mat.set_shader_parameter("intensity", 0.8)
		s.material = mat
	add_child(s)


func _process(delta: float) -> void:
	if GameManager and GameManager.game_over:
		return
	_t += delta
	if _t < TICK:
		return
	_t = 0.0
	var dmg: int = BASE_TICK_DAMAGE + 2 * difficulty
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if (p as Node2D).global_position.distance_to(global_position) > RADIUS:
			continue
		if p.has_method("receive_damage_payload"):
			p.call(
				"receive_damage_payload",
				DamageInstance.new(float(dmg), null, self, [&"environment", &"lava"], [])
			)
		elif p.has_method("take_damage"):
			p.call("take_damage", dmg)
