extends Node2D

# Banner of the Ancients — Warchief (Barbarian) ascension R. Plants a banner for
# 12s. Allies in range gain an aura (+20% damage, +15% damage reduction); enemies
# are taunted to the banner on first entry. In solo it also shields the Barbarian.

const LIFETIME: float = 12.0
const RADIUS: float = 240.0
const AURA_DMG_MULT: float = 1.2
const AURA_DR: float = 0.15
const TAUNT_TIME: float = 1.0

var visual_only: bool = false
var caster: Node2D = null
var _life: float = LIFETIME
var _taunted: Dictionary = {}  # enemy id -> true (first-entry taunt)


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 6
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	_build_visual()
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.2, Color(0.9, 0.7, 0.2, 1))
	# Solo: the banner also shields the Barbarian on the spot.
	if not visual_only and caster and caster.has_method("add_shield"):
		if not (NetManager and NetManager.is_multiplayer):
			var max_hp: float = float(GameManager.player_max_hp) if GameManager else 100.0
			caster.call("add_shield", max_hp * 0.2, -1.0)


func _build_visual() -> void:
	var pole := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_flame.png"
	if ResourceLoader.exists(path):
		pole.texture = load(path) as Texture2D
	pole.modulate = Color(1.0, 0.8, 0.25, 1)
	pole.position = Vector2(0, -28)
	pole.scale = Vector2(0.8, 1.4)
	add_child(pole)
	var tw := pole.create_tween().set_loops()
	tw.tween_property(pole, "modulate", Color(1.0, 0.9, 0.4, 1), 0.6)
	tw.tween_property(pole, "modulate", Color(0.9, 0.6, 0.2, 1), 0.6)


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
	for grp in ["player", "remote_player"]:
		for a in tree.get_nodes_in_group(grp):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if global_position.distance_to((a as Node2D).global_position) > RADIUS:
				continue
			if a.has_method("apply_aura"):
				a.call("apply_aura", AURA_DMG_MULT, AURA_DR, 0.4)
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		var id: int = e.get_instance_id()
		if not _taunted.has(id):
			_taunted[id] = true
			if e.has_method("apply_taunt"):
				e.call("apply_taunt", self, TAUNT_TIME)
