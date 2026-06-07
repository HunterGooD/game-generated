extends Area2D

# Magic bolt projectile fired by the player.

const SPEED: float = 760.0
const LIFETIME: float = 1.6

@export var sprite: Sprite2D
@export var hit_box: HitBoxComponent

var direction: Vector2 = Vector2.RIGHT
var damage: int = 14
var owner_tag: String = "player"
var travelled: float = 0.0
var pierces: bool = false
var hit_ids: Dictionary = {}


func setup(dir: Vector2, dmg: int, owner_tag_in: String) -> void:
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	damage = dmg
	owner_tag = owner_tag_in
	rotation = direction.angle()
	if hit_box:
		hit_box.payload = _build_damage_payload()


func _ready() -> void:
	collision_layer = 4
	collision_mask = 17  # 1 (walls) | 16 (enemy hurtbox)
	# Voidstaff unique — bolt pierces through enemies.
	if owner_tag == "player" and InventorySystem and InventorySystem.has_unique("voidstaff"):
		pierces = true
		modulate = Color(0.7, 0.55, 1.0, 1.0)
		scale *= 1.15
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if hit_box:
		hit_box.collision_layer = 4
		hit_box.collision_mask = 16
		hit_box.hit.connect(_on_hit_hurtbox)
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
	if travelled > 1400.0:
		_die()


func _on_body_entered(body: Node) -> void:
	if body is StaticBody2D or body is TileMap:
		_impact()


func _on_area_entered(area: Area2D) -> void:
	if area is HurtBoxComponent:
		return
	if owner_tag == "player" and area.is_in_group("enemy_hit"):
		var enemy := area.get_parent()
		if enemy and enemy.has_method("take_damage"):
			var id: int = enemy.get_instance_id()
			if pierces and hit_ids.has(id):
				return
			hit_ids[id] = true
			enemy.take_damage(damage, global_position)
		if pierces:
			# Light spark without dying.
			if VfxManager:
				VfxManager.spawn_hit_sparks(global_position, Color(0.7, 0.5, 1.0, 1), 4)
			return
		_impact()


func _on_hit_hurtbox(area: Area2D) -> void:
	var enemy := area.get_parent()
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	if pierces and hit_ids.has(id):
		return
	hit_ids[id] = true
	if pierces:
		if VfxManager:
			VfxManager.spawn_hit_sparks(global_position, Color(0.7, 0.5, 1.0, 1), 4)
		return
	_impact()


func _impact() -> void:
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_magic_hit.mp3", -10.0)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.85, 0.5, 1.0, 1), 5)
	_die()


func _die() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	queue_free()


func _build_damage_payload() -> DamageInstance:
	return DamageInstance.new(
		float(damage),
		_resolve_local_player() if owner_tag == "player" else null,
		self,
		[&"player", &"projectile", &"magic_bolt"],
		[]
	)


func _resolve_local_player() -> Node:
	# Guard with is_inside_tree() first: calling get_tree() on a node that
	# hasn't been added to the SceneTree yet (e.g. during setup() before
	# add_child) emits "Parameter data.tree is null" before returning null.
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("player"):
		if node is Node and not node.is_in_group("remote_player"):
			return node
	return null
