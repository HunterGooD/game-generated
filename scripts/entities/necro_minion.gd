extends CharacterBody2D

# Necromancer minion — skeletal soldier or armored knight.
# Same chassis as spirit_pet but with skeleton sprites and a "taunt aggro"
# property knights use to pull enemy attention.

const MOVE_SPEED_SOLDIER: float = 240.0
const MOVE_SPEED_KNIGHT: float = 150.0
const ATTACK_RANGE: float = 60.0
const ATTACK_COOLDOWN: float = 1.0
const DETECTION_RANGE: float = 520.0

var minion_kind: String = "skeleton"  # "skeleton" or "knight"
var damage: int = 7
var max_hp: int = 50
var hp: int = 50
var attack_cd: float = 0.0
var dead: bool = false
var sprite: AnimatedSprite2D = null
var owner_caster: Node = null
# Blood Pact buff state.
var buff_t: float = 0.0
var dmg_mult: float = 1.0
var spd_mult: float = 1.0
# Co-op networking. Authoritative minions live on the host; every other peer
# holds a visual puppet driven by host-broadcast state (no AI, no damage).
var network_id: int = -1
var owner_player_id: int = -1
var is_puppet: bool = false
var _net_target_pos: Vector2 = Vector2.ZERO


func set_puppet() -> void:
	is_puppet = true
	_net_target_pos = global_position
	# A puppet shouldn't block movement or be hit — the host owns its life.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)


func apply_remote_state(d: Dictionary) -> void:
	_net_target_pos = Vector2(float(d.get("x", global_position.x)), float(d.get("y", global_position.y)))
	if d.has("hp"):
		hp = int(d.get("hp"))


func configure(kind: String, caster_dmg: int) -> void:
	minion_kind = kind
	if minion_kind == "knight":
		# Tank: high HP, modest damage, slow.
		max_hp = 200
		damage = max(10, int(round(float(caster_dmg) * 0.65)))
	else:
		# Soldier: low HP, fast.
		max_hp = 55
		damage = max(6, int(round(float(caster_dmg) * 0.45)))
	hp = max_hp


func apply_knight_armor_bonus(extra_hp: int) -> void:
	if minion_kind != "knight":
		return
	max_hp += extra_hp
	hp = max_hp


func _ready() -> void:
	add_to_group("necro_minion")
	add_to_group("pet_ally")  # so enemies aggro on us via the unified group
	collision_layer = 2
	collision_mask = 1
	z_index = 11
	sprite = AnimatedSprite2D.new()
	sprite.name = "Visual"
	add_child(sprite)
	_apply_sprite_frames()


func _apply_sprite_frames() -> void:
	if sprite == null:
		return
	var prefix: String = "necro_skeleton"
	if minion_kind == "knight":
		prefix = "necro_skeleton_knight"
	var frames := SpriteFrames.new()
	var sample_tex: Texture2D = null
	for state_key in ["idle", "walk", "attack"]:
		var path: String = "res://assets/sprites/characters/%s_%s.png" % [prefix, state_key]
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path) as Texture2D
			if tex:
				if sample_tex == null:
					sample_tex = tex
				frames.add_animation(state_key)
				frames.set_animation_loop(state_key, true)
				frames.set_animation_speed(state_key, 5.0)
				frames.add_frame(state_key, tex, 1.0)
	sprite.sprite_frames = frames
	if frames.has_animation("idle"):
		sprite.play("idle")
	# Knight is bigger; soldier is smaller.
	var target_h: float = 60.0 if minion_kind == "skeleton" else 85.0
	var s: float = 0.12
	if sample_tex:
		var src_h: float = float(sample_tex.get_size().y)
		if src_h > 1.0:
			s = clamp(target_h / src_h, 0.05, 0.5)
	sprite.scale = Vector2(s, s)
	# Subtle violet tint for the undead.
	sprite.modulate = Color(0.85, 0.78, 1.0, 0.95)


func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		return
	if is_puppet:
		_puppet_process(delta)
		return
	if attack_cd > 0.0:
		attack_cd -= delta
	if buff_t > 0.0:
		buff_t -= delta
		if buff_t <= 0.0:
			dmg_mult = 1.0
			spd_mult = 1.0
			if sprite:
				sprite.modulate = Color(0.85, 0.78, 1.0, 0.95)
	var target: Node2D = _find_nearest_enemy()
	if target == null:
		_follow_owner(delta)
		return
	var to_t: Vector2 = target.global_position - global_position
	var dist: float = to_t.length()
	if sprite and abs(to_t.x) > 1.0:
		sprite.flip_h = to_t.x < 0.0
	var base_speed: float = MOVE_SPEED_KNIGHT if minion_kind == "knight" else MOVE_SPEED_SOLDIER
	if dist > ATTACK_RANGE - 10.0:
		velocity = to_t.normalized() * base_speed * spd_mult
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
			if sprite.animation != "walk":
				sprite.play("walk")
	else:
		velocity = Vector2.ZERO
		if attack_cd <= 0.0:
			_attack(target)
	move_and_slide()


func _follow_owner(delta: float) -> void:
	if owner_caster == null or not is_instance_valid(owner_caster):
		velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
		move_and_slide()
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
			if sprite.animation != "idle":
				sprite.play("idle")
		return
	var to_owner: Vector2 = (owner_caster as Node2D).global_position - global_position
	var dist: float = to_owner.length()
	var base_speed: float = MOVE_SPEED_KNIGHT if minion_kind == "knight" else MOVE_SPEED_SOLDIER
	if dist > 110.0:
		velocity = to_owner.normalized() * base_speed * spd_mult
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
			if sprite.animation != "walk":
				sprite.play("walk")
		if sprite and abs(to_owner.x) > 1.0:
			sprite.flip_h = to_owner.x < 0.0
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
			if sprite.animation != "idle":
				sprite.play("idle")
	move_and_slide()


# Puppet: smoothly chase the host-provided position and animate.
func _puppet_process(delta: float) -> void:
	var to_t: Vector2 = _net_target_pos - global_position
	if to_t.length() > 2.0:
		global_position = global_position.lerp(_net_target_pos, clamp(12.0 * delta, 0.0, 1.0))
		if sprite and abs(to_t.x) > 1.0:
			sprite.flip_h = to_t.x < 0.0
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
			if sprite.animation != "walk":
				sprite.play("walk")
	elif sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
		if sprite.animation != "idle":
			sprite.play("idle")


func _find_nearest_enemy() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = DETECTION_RANGE
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e.get("dead") == true:
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e as Node2D
	return best


func _attack(target: Node2D) -> void:
	attack_cd = ATTACK_COOLDOWN
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")
	var dmg: int = int(round(float(damage) * dmg_mult))
	if target.has_method("take_damage"):
		target.call("take_damage", dmg, global_position)
	if VfxManager:
		VfxManager.spawn_hit_sparks(target.global_position, Color(0.8, 0.55, 1.0, 1), 5)


# Called by Blood Pact — empower this minion temporarily and full-heal.
func apply_blood_pact(duration: float, dmg_multiplier: float, speed_multiplier: float) -> void:
	if dead:
		return
	buff_t = max(buff_t, duration)
	dmg_mult = max(dmg_mult, dmg_multiplier)
	spd_mult = max(spd_mult, speed_multiplier)
	hp = max_hp
	if sprite:
		sprite.modulate = Color(1.4, 0.55, 0.9, 1)


func take_damage(amount: int, _src: Vector2 = Vector2.ZERO) -> void:
	if dead:
		return
	# Puppets never take authoritative damage — the host drives hp/death.
	if is_puppet:
		return
	hp -= amount
	if sprite:
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color(1.6, 0.5, 0.5, 1), 0.06)
		tw.tween_property(sprite, "modulate", Color(0.85, 0.78, 1.0, 0.95), 0.18)
	if hp <= 0:
		_die()


func _die() -> void:
	if dead:
		return
	dead = true
	# Host: tell peers to drop their puppet of this minion.
	if not is_puppet and network_id >= 0:
		var ns := _net_sync()
		if ns and ns.has_method("broadcast_minion_death"):
			ns.call("broadcast_minion_death", network_id)
	if sprite:
		var tw := sprite.create_tween().set_parallel(true)
		tw.tween_property(sprite, "modulate:a", 0.0, 0.5)
		tw.tween_property(sprite, "scale", sprite.scale * 0.6, 0.5)
		tw.chain().tween_callback(queue_free)
	else:
		queue_free()
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.8, 0.55, 1.0, 1), 10)
	if is_inside_tree():
		var safety := Timer.new()
		safety.one_shot = true
		safety.wait_time = 1.0
		safety.autostart = true
		safety.timeout.connect(_safety_free)
		add_child(safety)


func _safety_free() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(self):
		queue_free()


func _net_sync() -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null("NetSync")
