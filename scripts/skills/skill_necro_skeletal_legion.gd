extends Node2D

# Skeletal Legion — Deathlord transform of Raise Skeleton. A bigger, weaker pack.

const MINION_SCENE: PackedScene = preload("res://scenes/entities/necro_minion.tscn")
const KIND: String = "skeleton"
const COUNT: int = 3
const SPREAD: float = 48.0

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
	var ring := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/cast_flash.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
	ring.modulate = Color(0.7, 0.5, 1.0, 0.85)
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(1.8, 1.8), 0.5)
	tw.tween_property(ring, "modulate:a", 0.0, 0.5)
	if not visual_only and caster:
		_summon()
	var t := get_tree().create_timer(0.6)
	t.timeout.connect(queue_free)


func _summon() -> void:
	var ns := _find_net_sync()
	if NetManager and NetManager.is_multiplayer:
		if ns == null:
			return
		if NetManager.is_host:
			ns.call("host_spawn_summon", KIND, "", NetManager.local_player_id, global_position, COUNT, damage, 0)
		else:
			ns.call("request_summon", KIND, "", global_position, COUNT, damage, 0)
		return
	for i in COUNT:
		var m: Node2D = MINION_SCENE.instantiate()
		get_tree().current_scene.add_child(m)
		var ang: float = (TAU / float(max(1, COUNT))) * float(i) + randf() * 0.3
		m.global_position = global_position + Vector2(cos(ang), sin(ang)) * SPREAD
		if m.has_method("configure"):
			m.call("configure", KIND, damage)
		m.set("owner_caster", caster)


func _find_net_sync() -> Node:
	var tr := get_tree()
	if tr == null or tr.current_scene == null:
		return null
	return tr.current_scene.get_node_or_null("NetSync")
