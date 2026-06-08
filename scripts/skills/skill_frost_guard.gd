extends Node2D

# Frost Guard — Battlemage transform of Ice Bolt (slot 1). A defensive burst: the
# caster gains a one-hit ice ward (reusing the Stone Armor absorb) and a frost
# nova chills nearby enemies. Lets the melee Battlemage trade a ranged slot for
# survivability when wading into a pack.

const NOVA_RADIUS: float = 150.0
const CHILL_DURATION: float = 3.0

var damage: int = 14
var visual_only: bool = false
var caster: Node2D = null


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 40
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	_spawn_nova_visual()
	if not visual_only and caster:
		# One-hit ice ward — reuse the Stone Armor absorb path on the player.
		var cur: int = int(caster.get("stone_armor_charges")) if caster.has_method("get") else 0
		caster.set("stone_armor_charges", maxi(cur, 1))
		_chill_nearby()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_spell_ice_bolt.mp3", -8.0)
	var t := get_tree().create_timer(0.6)
	t.timeout.connect(queue_free)


func _spawn_nova_visual() -> void:
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.1, Color(0.6, 0.85, 1.0, 1))
		VfxManager.spawn_hit_sparks(global_position, Color(0.7, 0.9, 1.0, 1), 16)


func _chill_nearby() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > NOVA_RADIUS:
			continue
		if e.has_method("apply_chill"):
			e.call("apply_chill", CHILL_DURATION, 1)
		elif e.has_method("apply_slow"):
			e.call("apply_slow", CHILL_DURATION, 0.6)
