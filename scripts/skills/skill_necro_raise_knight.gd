extends Node2D

# Raise Knight — summon one tank skeleton knight. Max 1; re-cast refreshes.
# Plated Bones modifier adds +40 HP per stack to the knight.

const MINION_SCENE: PackedScene = preload("res://scenes/entities/necro_minion.tscn")

var damage: int = 14
var visual_only: bool = false
var _pending_caster: Node = null
var _pending_armor_bonus: int = 0
var _spawn_pos: Vector2 = Vector2.ZERO


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)
	var caster = mods.get("caster", null)
	if visual_only or caster == null:
		return
	_pending_caster = caster
	var bonus_stacks: int = 0
	var ss = caster.get_node_or_null("SkillSystem")
	if ss and ss.has_method("get_modifier"):
		bonus_stacks = int(ss.call("get_modifier", 1, "necro_knight_armor"))
	_pending_armor_bonus = 40 * bonus_stacks
	_spawn_pos = global_position


func _ready() -> void:
	z_index = 70
	var ring := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/cast_flash.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
	ring.modulate = Color(0.55, 0.35, 0.9, 0.9)
	ring.scale = Vector2(0.7, 0.7)
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(2.4, 2.4), 0.6)
	tw.tween_property(ring, "modulate:a", 0.0, 0.6)
	if not visual_only and is_instance_valid(_pending_caster):
		_refresh_knight()
	var t := get_tree().create_timer(0.7)
	t.timeout.connect(queue_free)


func _refresh_knight() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("necro_minion"):
		if not is_instance_valid(n):
			continue
		if n.get("owner_caster") == _pending_caster and String(n.get("minion_kind")) == "knight":
			n.queue_free()
	var knight: Node2D = MINION_SCENE.instantiate()
	get_tree().current_scene.add_child(knight)
	knight.global_position = _spawn_pos + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	if knight.has_method("configure"):
		knight.call("configure", "knight", damage)
	if _pending_armor_bonus > 0 and knight.has_method("apply_knight_armor_bonus"):
		knight.call("apply_knight_armor_bonus", _pending_armor_bonus)
	knight.set("owner_caster", _pending_caster)
