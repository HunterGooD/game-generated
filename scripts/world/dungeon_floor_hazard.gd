class_name DungeonFloorHazard
extends Node2D

## A stationary floor pool that ticks damage to players standing in it. `kind` sets the
## biome flavor: lava (heavy, lava_pulse shader), ice (light frostbite), spore (moderate
## garden poison). The runner scatters these per biome. Damages via the canonical
## group-iteration + receive_damage_payload path (mirrors boss_telegraph.gd).

const FLOOR_TEX := "res://assets/textures/floors/ruins_floor.webp"
const LAVA_SHADER := "res://assets/shaders/lava_pulse.gdshader"
const TICK := 0.5

const CONFIG := {
	"lava":
	{
		"radius": 96.0, "dmg": 6, "tag": &"lava", "shader": true,
		"tint": Color(1.0, 0.55, 0.3), "warm": Color(1.0, 0.45, 0.18, 1.0), "cool": Color(0.55, 0.12, 0.12, 1.0),
	},
	"ice":
	{
		"radius": 88.0, "dmg": 3, "tag": &"frost", "shader": false,
		"ring": Color(0.7, 0.9, 1.0),
	},
	"spore":
	{
		"radius": 112.0, "dmg": 4, "tag": &"poison", "shader": false,
		"ring": Color(0.6, 0.95, 0.5),
	},
}

var kind: String = "lava"
var difficulty: int = 0

var _radius := 96.0
var _dmg := 6
var _tag := &"lava"
var _draw_ring := false
var _ring := Color(1, 1, 1)
var _t := 0.0
var _pulse := 0.0


func _ready() -> void:
	z_index = -8  # on the floor, under actors
	add_to_group("dungeon_hazard")
	var c: Dictionary = CONFIG.get(kind, CONFIG["lava"])
	_radius = float(c["radius"])
	_dmg = int(c["dmg"])
	_tag = c["tag"]
	if bool(c["shader"]):
		_build_lava(c)
	else:
		_draw_ring = true
		_ring = c["ring"]
		queue_redraw()
	set_process(true)


func _build_lava(c: Dictionary) -> void:
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
		s.scale = Vector2(_radius * 2.4 / ts.x, _radius * 2.4 / ts.y)
	s.modulate = c["tint"]
	if ResourceLoader.exists(LAVA_SHADER):
		var mat := ShaderMaterial.new()
		mat.shader = load(LAVA_SHADER) as Shader
		mat.set_shader_parameter("warm_color", c["warm"])
		mat.set_shader_parameter("cool_color", c["cool"])
		mat.set_shader_parameter("pulse_speed", 0.7)
		mat.set_shader_parameter("scroll_speed", 0.25)
		mat.set_shader_parameter("intensity", 0.8)
		s.material = mat
	add_child(s)


func _process(delta: float) -> void:
	if GameManager and GameManager.game_over:
		return
	if _draw_ring:
		_pulse = fmod(_pulse + delta, TAU)
		queue_redraw()
	_t += delta
	if _t < TICK:
		return
	_t = 0.0
	# Host-authoritative damage: clients render the pool (the pulse above keeps running)
	# but only the host applies its damage — to its local player and the puppets of
	# clients (→ player_hit to the owner) — so a client never double-applies the pool.
	if NetManager and NetManager.is_multiplayer and not NetManager.is_host:
		return
	var dmg: int = _dmg + 2 * difficulty
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if (p as Node2D).global_position.distance_to(global_position) > _radius:
			continue
		if p.has_method("receive_damage_payload"):
			p.call(
				"receive_damage_payload",
				DamageInstance.new(float(dmg), null, self, [&"environment", _tag], [])
			)
		elif p.has_method("take_damage"):
			p.call("take_damage", dmg)


func _draw() -> void:
	if not _draw_ring:
		return
	var a: float = 0.20 + 0.06 * sin(_pulse * 2.0)
	draw_circle(Vector2.ZERO, _radius, Color(_ring.r, _ring.g, _ring.b, a * 0.6))
	draw_circle(Vector2.ZERO, _radius * 0.6, Color(_ring.r, _ring.g, _ring.b, a * 0.35))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 44, Color(_ring.r, _ring.g, _ring.b, 0.7), 2.5, true)
