extends Node2D

# Elemental Orbit — Elementalist (Mage) ascension R. Fires every elemental orb the
# caster has banked (one per elemental skill cast, max 3) in the aim direction.
# Each orb deals ELEM_DMG_MULT of the ability damage and applies its element on
# hit. If all THREE elements are present it becomes a Prismatic Burst — every orb
# hits for PRISMATIC_MULT instead and detonates a fracturing nova.

const ELEM_DMG_MULT: float = 0.9
const PRISMATIC_MULT: float = 2.0
const ORB_SPEED: float = 520.0
const ORB_LIFETIME: float = 1.1
const ORB_HIT_RADIUS: float = 34.0

const ELEM_COLOR := {
	"fire": Color(1.0, 0.5, 0.2, 1),
	"frost": Color(0.6, 0.85, 1.0, 1),
	"storm": Color(0.8, 0.85, 1.0, 1),
}

var damage: int = 20
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var caster: Node2D = null
var prismatic: bool = false
var _orbs: Array = []  # [{el, spr, pos, vel, hit:{}, t}]
var _fan: Array = []  # [[element, direction], ...] launched in _ready


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)
	var elements: Array = []
	if caster and caster.has_method("consume_elem_orbs"):
		elements = caster.call("consume_elem_orbs")
	# A bare R with no orbs banked still fires one neutral fire orb so it isn't a
	# dead button.
	if elements.is_empty():
		elements = ["fire"]
	var distinct: Dictionary = {}
	for el in elements:
		distinct[el] = true
	prismatic = distinct.size() >= 3
	# Fan the orbs evenly around the aim direction.
	var n: int = elements.size()
	var spread: float = deg_to_rad(18.0)
	for i in n:
		var offset: float = 0.0 if n <= 1 else lerp(-spread, spread, float(i) / float(n - 1))
		_fan.append([String(elements[i]), direction.rotated(offset)])


func _ready() -> void:
	z_index = 55
	var origin: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	for entry in _fan:
		_spawn_orb(origin, entry[0], entry[1])
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_spell_chain_lightning.mp3", -6.0)
	var t := get_tree().create_timer(ORB_LIFETIME + 0.3)
	t.timeout.connect(queue_free)


func _spawn_orb(origin: Vector2, element: String, vdir: Vector2) -> void:
	var spr := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_flame.png"
	if ResourceLoader.exists(path):
		spr.texture = load(path) as Texture2D
	spr.modulate = ELEM_COLOR.get(element, Color(1, 1, 1, 1))
	spr.scale = Vector2(0.6, 0.6) * (1.3 if prismatic else 1.0)
	spr.global_position = origin
	add_child(spr)
	_orbs.append({"el": element, "spr": spr, "pos": origin, "vel": vdir * ORB_SPEED, "hit": {}, "t": 0.0})


func _process(delta: float) -> void:
	var tree := get_tree()
	for orb in _orbs:
		if not is_instance_valid(orb["spr"]):
			continue
		orb["t"] += delta
		orb["pos"] += orb["vel"] * delta
		(orb["spr"] as Sprite2D).global_position = orb["pos"]
		(orb["spr"] as Sprite2D).rotation += delta * 8.0
		if visual_only or tree == null:
			continue
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or bool(e.get("dead")):
				continue
			if orb["hit"].has(e.get_instance_id()):
				continue
			if orb["pos"].distance_to((e as Node2D).global_position) > ORB_HIT_RADIUS:
				continue
			orb["hit"][e.get_instance_id()] = true
			_hit_enemy(e, orb["el"])


func _hit_enemy(e: Node, element: String) -> void:
	var mult: float = PRISMATIC_MULT if prismatic else ELEM_DMG_MULT
	var dmg: int = int(round(float(damage) * mult))
	# Tri-Element Fracture payoff: a fractured target takes +10% from the orb.
	if e.has_method("is_fractured") and bool(e.call("is_fractured")):
		dmg = int(round(float(dmg) * 1.1))
		if e.has_method("consume_fracture"):
			e.call("consume_fracture")
	if e.has_method("take_damage"):
		e.call("take_damage", dmg, global_position)
	match element:
		"fire":
			if e.has_method("apply_burn"):
				e.call("apply_burn", 4.0, float(damage) * 0.3)
		"frost":
			if e.has_method("apply_chill"):
				e.call("apply_chill", 3.0, 1)
		"storm":
			if e.has_method("mark_element"):
				e.call("mark_element", "storm")
	if prismatic and e.has_method("mark_element"):
		# Prismatic orbs carry all three elements — instantly fracture-eligible.
		e.call("mark_element", "fire")
		e.call("mark_element", "frost")
		e.call("mark_element", "storm")
	if VfxManager:
		VfxManager.spawn_hit_sparks((e as Node2D).global_position, ELEM_COLOR.get(element, Color(1, 1, 1, 1)), 8)
