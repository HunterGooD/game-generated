extends Node2D

# Raise Skeleton — summon one (or more, with Risen Legion) skeleton soldier.
# Default cap is 1 active soldier; re-cast refreshes (despawn old, summon new
# at full HP). Pack count grows with the necro_skel_count modifier.

const MINION_SCENE: PackedScene = preload("res://scenes/entities/necro_minion.tscn")
const BASE_COUNT: int = 1
const SPAWN_SPREAD: float = 48.0

var damage: int = 14
var visual_only: bool = false
var _pending_caster: Node = null
var _pending_count: int = 1
var _spawn_pos: Vector2 = Vector2.ZERO


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
	var bonus_stacks: int = 0
	var ss = caster.get_node_or_null("SkillSystem")
	if ss and ss.has_method("get_modifier"):
		bonus_stacks = int(ss.call("get_modifier", 0, "necro_skel_count"))
	_pending_count = BASE_COUNT + bonus_stacks
	_spawn_pos = global_position


func _ready() -> void:
	z_index = 70
	# Summon flash.
	var ring := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/cast_flash.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
	ring.modulate = Color(0.7, 0.5, 1.0, 0.85)
	ring.scale = Vector2(0.5, 0.5)
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(1.8, 1.8), 0.5)
	tw.tween_property(ring, "modulate:a", 0.0, 0.5)
	_do_summon()
	var t := get_tree().create_timer(0.6)
	t.timeout.connect(queue_free)


# Solo: spawn locally. Multiplayer: the host owns all summons — host spawns
# authoritative units, a client asks the host via request_summon. The local
# scene only ever plays the cast flash on non-authoritative peers.
func _do_summon() -> void:
	if visual_only or not is_instance_valid(_pending_caster):
		return
	if NetManager and NetManager.is_multiplayer:
		var ns := _find_net_sync()
		if ns == null:
			return
		if NetManager.is_host:
			ns.call(
				"host_spawn_summon",
				"skeleton",
				"",
				NetManager.local_player_id,
				global_position,
				_pending_count,
				damage,
				0
			)
		else:
			ns.call("request_summon", "skeleton", "", global_position, _pending_count, damage, 0)
		return
	_refresh_minions()


func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null("NetSync")


func _refresh_minions() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Despawn this caster's existing soldiers (knights stay — different cap).
	for n in tree.get_nodes_in_group("necro_minion"):
		if not is_instance_valid(n):
			continue
		if n.get("owner_caster") == _pending_caster and String(n.get("minion_kind")) == "skeleton":
			n.queue_free()
	for i in _pending_count:
		_spawn_minion(i)


func _spawn_minion(idx: int) -> void:
	if not is_inside_tree():
		return
	var minion: Node2D = MINION_SCENE.instantiate()
	get_tree().current_scene.add_child(minion)
	var ang: float = (TAU / float(max(1, _pending_count))) * float(idx) + randf() * 0.3
	minion.global_position = _spawn_pos + Vector2(cos(ang), sin(ang)) * SPAWN_SPREAD
	if minion.has_method("configure"):
		minion.call("configure", "skeleton", damage)
	minion.set("owner_caster", _pending_caster)
