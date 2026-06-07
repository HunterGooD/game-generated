extends Area2D

# Thrown dagger — fast projectile, often crits.

const SPEED: float = 900.0
const LIFETIME: float = 1.0

@export var sprite: Sprite2D
@export var hit_box: HitBoxComponent

var direction: Vector2 = Vector2.RIGHT
var damage: int = 14
var travelled: float = 0.0
var is_crit: bool = false
var _caster: Node = null


func setup(dir: Vector2, dmg: int) -> void:
	setup_with_mods(dir, dmg, {})


func setup_with_mods(dir: Vector2, dmg: int, mods: Dictionary) -> void:
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	_caster = mods.get("caster", null) if mods != null else null
	if GameManager:
		var res: Array = GameManager.compute_attack_damage(dmg)
		damage = int(res[0])
		is_crit = bool(res[1])
	else:
		damage = dmg
	rotation = direction.angle()
	if hit_box:
		hit_box.payload = _build_damage_payload()


func _ready() -> void:
	collision_layer = 4
	collision_mask = 17  # walls + enemy hurtbox
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if hit_box:
		hit_box.collision_layer = 4
		hit_box.collision_mask = 16
		hit_box.hit.connect(_on_hit_hurtbox)
	# Spin while flying.
	if sprite:
		var tw := create_tween().set_loops()
		tw.tween_property(sprite, "rotation", sprite.rotation + TAU, 0.25)
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = LIFETIME
	t.timeout.connect(_die)
	add_child(t)
	t.start()


func _physics_process(delta: float) -> void:
	var step: Vector2 = direction * SPEED * delta
	position += step
	travelled += step.length()
	if travelled > 1200.0:
		_die()


func _on_area_entered(area: Area2D) -> void:
	if area is HurtBoxComponent:
		return
	if not area.is_in_group("enemy_hit"):
		return
	var enemy := area.get_parent()
	if enemy and enemy.has_method("take_damage"):
		enemy.take_damage(damage, global_position)
		_play_hit_feedback()
	_impact()


func _on_hit_hurtbox(_area: Area2D) -> void:
	_play_hit_feedback()
	_impact()


func _on_body_entered(body: Node) -> void:
	if body is StaticBody2D or body is TileMap:
		_impact()


func _impact() -> void:
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_dagger_hit.mp3", -10.0)
	# Venomweave unique — leave a poison puddle at the impact point.
	if has_meta("venomweave"):
		_spawn_poison_puddle()
	_die()


func _spawn_poison_puddle() -> void:
	# Light DoT puddle that lasts 2 seconds, reusing the fire_ring scene
	# tinted green for poison.
	var path: String = "res://scenes/combat/player/fire_ring.tscn"
	if not ResourceLoader.exists(path):
		return
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return
	var puddle: Node2D = packed.instantiate()
	get_tree().current_scene.add_child(puddle)
	puddle.global_position = global_position
	if puddle.has_method("setup"):
		puddle.call("setup", damage)
	puddle.modulate = Color(0.5, 1.0, 0.4, 1)


func _die() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	queue_free()


func _play_hit_feedback() -> void:
	if VfxManager:
		var col: Color = Color(1.0, 0.3, 0.3, 1) if is_crit else Color(1.0, 0.7, 0.5, 1)
		VfxManager.spawn_hit_sparks(global_position, col, 6)
		if is_crit:
			VfxManager.screen_shake(2.0, 0.1)


func _build_damage_payload() -> DamageInstance:
	var attacker: Node = _caster
	if attacker == null and is_inside_tree():
		attacker = _resolve_local_player()
	return DamageInstance.new(
		float(damage),
		attacker,
		self,
		[&"player", &"projectile", &"dagger"],
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
