extends Node2D

# Guardian Spirit — Grovekeeper transform of Summon Spirit. A sturdy spirit that guards the party.

const SPIRIT_PET_SCENE: PackedScene = preload("res://scenes/entities/spirit_pet.tscn")
const PET: String = "bear"

var damage: int = 14
var visual_only: bool = false
var caster: Node = null


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 70
	if not visual_only and caster:
		_summon()
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.6, 1.0, 0.6, 1), 12)
	var t := get_tree().create_timer(0.6)
	t.timeout.connect(queue_free)


func _summon() -> void:
	var ns := _find_net_sync()
	if NetManager and NetManager.is_multiplayer:
		if ns == null:
			return
		if NetManager.is_host:
			ns.call("host_spawn_summon", "spirit", PET, NetManager.local_player_id, global_position, 1, damage, 0)
		else:
			ns.call("request_summon", "spirit", PET, global_position, 1, damage, 0)
		return
	var pet: Node2D = SPIRIT_PET_SCENE.instantiate()
	get_tree().current_scene.add_child(pet)
	pet.global_position = global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	if pet.has_method("configure"):
		pet.call("configure", PET, damage)
	pet.set("owner_caster", caster)


func _find_net_sync() -> Node:
	var tr := get_tree()
	if tr == null or tr.current_scene == null:
		return null
	return tr.current_scene.get_node_or_null("NetSync")
