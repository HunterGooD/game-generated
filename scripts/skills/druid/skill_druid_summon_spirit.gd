extends Node2D

# Summon Spirit — calls ghostly wolf/bear pets that chase and damage enemies.
# Default max is 1 pet; Pack Caller upgrades raise the max.
# Pets live until they die. Re-casting despawns the caster's existing pets
# and spawns a fresh batch at full HP with current damage/buffs applied.

const SPIRIT_PET_SCENE: PackedScene = preload("res://scenes/entities/spirit_pet.tscn")
const BASE_COUNT: int = 1
const SPAWN_SPREAD: float = 60.0

var damage: int = 14
var visual_only: bool = false
var _pending_caster: Node = null
var _pending_pet_type: String = "wolf"
var _pending_count: int = 1


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	var caster = ctx.caster
	if visual_only or caster == null:
		return
	_pending_caster = caster
	# Max pets = 1 base + 1 per Pack Caller stack.
	var bonus_stacks: int = 0
	var ss = caster.get_node_or_null("SkillSystem")
	if ss and ss.has_method("get_modifier"):
		bonus_stacks = int(ss.call("get_modifier", 3, "spirit_pets"))
	_pending_count = BASE_COUNT + bonus_stacks
	# Pet flavour follows the druid's current shape — bear-form summons bears.
	_pending_pet_type = "wolf"
	if caster.get("druid_form") != null and String(caster.get("druid_form")) == "bear":
		_pending_pet_type = "bear"


func _ready() -> void:
	z_index = 70
	# Summon flash at spawn.
	var ring := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/cast_flash.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
	ring.modulate = Color(0.55, 0.95, 1.0, 0.8)
	ring.scale = Vector2(0.5, 0.5)
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(2.0, 2.0), 0.5)
	tw.tween_property(ring, "modulate:a", 0.0, 0.5)
	# Spawn the pets AFTER we're in the tree so they actually land in the scene.
	# Skip on visual-only replicas — only the caster's machine owns pets.
	_do_summon()
	var t := get_tree().create_timer(0.6)
	t.timeout.connect(queue_free)


# Solo: spawn locally. Multiplayer: host owns the pets (host spawns them; a
# client requests them via the host). Local scene only plays the cast flash on
# non-authoritative peers.
func _do_summon() -> void:
	if visual_only or _pending_caster == null or not is_instance_valid(_pending_caster):
		return
	if NetManager and NetManager.is_multiplayer:
		var ns := _find_net_sync()
		if ns == null:
			return
		if NetManager.is_host:
			ns.call(
				"host_spawn_summon",
				"spirit",
				_pending_pet_type,
				NetManager.local_player_id,
				global_position,
				_pending_count,
				damage,
				0
			)
		else:
			ns.call(
				"request_summon",
				"spirit",
				_pending_pet_type,
				global_position,
				_pending_count,
				damage,
				0
			)
		return
	_refresh_pets()


func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null("NetSync")


func _refresh_pets() -> void:
	# Despawn any existing pets that belong to this caster so re-cast acts as
	# a refresh: old ones vanish, new ones come in at full HP with current buffs.
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("spirit_pet"):
		if not is_instance_valid(n):
			continue
		if n.get("owner_caster") == _pending_caster:
			n.queue_free()
	# Spawn the new batch.
	for i in _pending_count:
		_spawn_pet(_pending_caster, _pending_pet_type, i)


func _spawn_pet(caster: Node, pet_type: String, _idx: int) -> void:
	if not is_inside_tree():
		return
	var pet: Node2D = SPIRIT_PET_SCENE.instantiate()
	get_tree().current_scene.add_child(pet)
	var ang: float = randf() * TAU
	pet.global_position = (
		(caster as Node2D).global_position + Vector2(cos(ang), sin(ang)) * SPAWN_SPREAD
	)
	if pet.has_method("configure"):
		pet.call("configure", pet_type, damage)
	# Stamp owner so future re-casts only despawn this druid's pets, not other
	# co-op druids' pets.
	pet.set("owner_caster", caster)
