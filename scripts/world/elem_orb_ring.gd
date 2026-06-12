class_name ElemOrbRing
extends Node2D

# Elementalist banked-orb display: one shader orb per entry in the player's
# `elem_orbs` bank, orbiting the character so the player can SEE the combo
# building toward Prismatic Burst (3 distinct elements). Purely visual — the
# bank itself lives on player.gd; Elemental Orbit (R) consumes it.
#
# Also the factory for the shader-orb visual (make_orb) so the R projectiles in
# skill_elemental_orbit.gd look identical to the orbiting ones.

const SHADER_PATH := "res://assets/shaders/elemental_orb.gdshader"
const ORB_SIZE: float = 26.0
const RADIUS: float = 46.0
const SPIN_SPEED: float = 1.6
const ELEMENT_INDEX := {"fire": 0, "storm": 1, "frost": 2}
# Orbiting orbs STING: an enemy grazed by an orb takes a small fraction of the
# player's damage and gets that orb's element mark — melee positioning feeds
# Tri-Element Fracture even before the R is pressed. Per-enemy cooldown keeps
# it a graze, not a blender.
const STING_RADIUS: float = 28.0
const STING_DAMAGE_FRAC: float = 0.25
const STING_COOLDOWN: float = 0.8
const STING_CHECK_INTERVAL: float = 0.12

var _orb_nodes: Array = []
var _shown: Array = []
var _spin: float = 0.0
var _sting_cd: Dictionary = {}  # enemy instance id -> cooldown left
var _check_t: float = 0.0


# A self-contained shader orb (Node2D wrapping a centered ColorRect).
static func make_orb(element: String, size: float = ORB_SIZE) -> Node2D:
	var holder := Node2D.new()
	var rect := ColorRect.new()
	rect.size = Vector2(size, size)
	rect.position = -Vector2(size, size) * 0.5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(SHADER_PATH):
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER_PATH) as Shader
		mat.set_shader_parameter("element", int(ELEMENT_INDEX.get(element, 0)))
		mat.set_shader_parameter("seed_offset", randf() * 20.0)
		rect.material = mat
	holder.add_child(rect)
	return holder


func _ready() -> void:
	z_index = 30


func _process(delta: float) -> void:
	_spin += delta * SPIN_SPEED
	var bank: Array = []
	var p := get_parent()
	if p and p.get("elem_orbs") != null:
		for el in p.get("elem_orbs"):
			bank.append(String(el))
	if bank != _shown:
		_rebuild(bank)
	# Even spacing with a light vertical bob so the ring feels alive.
	var n: int = _orb_nodes.size()
	for i in n:
		var orb: Node2D = _orb_nodes[i]
		if not is_instance_valid(orb):
			continue
		var ang: float = _spin + TAU * float(i) / float(n)
		orb.position = (
			Vector2(cos(ang), sin(ang)) * RADIUS + Vector2(0.0, sin(_spin * 2.0 + float(i)) * 4.0)
		)
	_update_sting(delta)


func _update_sting(delta: float) -> void:
	for key in _sting_cd.keys():
		_sting_cd[key] = float(_sting_cd[key]) - delta
		if float(_sting_cd[key]) <= 0.0:
			_sting_cd.erase(key)
	_check_t -= delta
	if _check_t > 0.0 or _orb_nodes.is_empty():
		return
	_check_t = STING_CHECK_INTERVAL
	var tree := get_tree()
	if tree == null:
		return
	var dmg: int = 14
	if GameManager:
		dmg = maxi(1, int(round(float(GameManager.get_effective_damage()) * STING_DAMAGE_FRAC)))
	for i in _orb_nodes.size():
		var orb: Node2D = _orb_nodes[i]
		if not is_instance_valid(orb) or i >= _shown.size():
			continue
		var element: String = String(_shown[i])
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or bool(e.get("dead")):
				continue
			var eid: int = e.get_instance_id()
			if _sting_cd.has(eid):
				continue
			if orb.global_position.distance_to((e as Node2D).global_position) > STING_RADIUS:
				continue
			_sting_cd[eid] = STING_COOLDOWN
			if e.has_method("take_damage"):
				e.call("take_damage", dmg, orb.global_position)
			if e.has_method("mark_element"):
				e.call("mark_element", element)
			if VfxManager:
				VfxManager.spawn_hit_sparks(
					(e as Node2D).global_position, Color(0.8, 0.85, 1.0, 1.0), 5
				)


func _rebuild(bank: Array) -> void:
	_shown = bank.duplicate()
	for orb in _orb_nodes:
		if is_instance_valid(orb):
			orb.queue_free()
	_orb_nodes.clear()
	for el in bank:
		var orb := make_orb(String(el))
		add_child(orb)
		_orb_nodes.append(orb)
