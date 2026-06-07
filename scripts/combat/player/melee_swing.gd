extends Node2D

# Melee swing — short-lived cone attack in front of the player.

const LIFETIME: float = 0.22
const ARC_DEGREES: float = 130.0
const RADIUS: float = 110.0

@export var hurt_area: HitBoxComponent
@export var sprite: Sprite2D

var damage: int = 18
var direction: Vector2 = Vector2.RIGHT
var hit_set: Dictionary = {}
var is_crit: bool = false


func setup(dir: Vector2, dmg: int) -> void:
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	if GameManager:
		var res: Array = GameManager.compute_attack_damage(dmg)
		damage = int(res[0])
		is_crit = bool(res[1])
	else:
		damage = dmg
	rotation = direction.angle()
	if hurt_area:
		hurt_area.payload = _build_damage_payload()


func _ready() -> void:
	if hurt_area:
		hurt_area.collision_layer = 0
		hurt_area.collision_mask = 16
		hurt_area.area_entered.connect(_on_area_entered)
		hurt_area.hit.connect(_on_hit_hurtbox)
	# Quick swing tween.
	if sprite:
		sprite.modulate = Color(1, 1, 1, 0.95)
		var tw := create_tween().set_parallel(true)
		(
			tw
			. tween_property(sprite, "scale", sprite.scale * 1.25, LIFETIME)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		tw.tween_property(sprite, "modulate:a", 0.0, LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(
			Tween.EASE_IN
		)
	# Auto-destroy.
	var t := get_tree().create_timer(LIFETIME + 0.05)
	t.timeout.connect(_finish)


func _on_area_entered(area: Area2D) -> void:
	if area is HurtBoxComponent:
		return
	if not area.is_in_group("enemy_hit"):
		return
	var enemy := area.get_parent()
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	if hit_set.has(id):
		return
	hit_set[id] = true
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, global_position)
	_play_hit_feedback(enemy)


func _on_hit_hurtbox(area: Area2D) -> void:
	var enemy := area.get_parent()
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	if hit_set.has(id):
		return
	hit_set[id] = true
	_play_hit_feedback(enemy)


func _play_hit_feedback(enemy: Node) -> void:
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_melee_hit.mp3", -8.0)
	if VfxManager:
		var col: Color = Color(1.0, 0.4, 0.2, 1) if is_crit else Color(1, 0.85, 0.5, 1)
		VfxManager.spawn_hit_sparks(enemy.global_position, col, 7)
		if is_crit:
			VfxManager.screen_shake(2.5, 0.12)


func _build_damage_payload() -> DamageInstance:
	return DamageInstance.new(
		float(damage),
		_resolve_local_player(),
		self,
		[&"player", &"melee"],
		[],
		is_crit
	)


func _resolve_local_player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("player"):
		if node is Node and not node.is_in_group("remote_player"):
			return node
	return null


func _finish() -> void:
	if hurt_area:
		hurt_area.set_deferred("monitoring", false)
		hurt_area.set_deferred("monitorable", false)
	queue_free()
