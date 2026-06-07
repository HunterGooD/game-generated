extends CharacterBody2D

# Spirit pet — small allied creature that chases nearest enemy and melees them.
# Has its own HP. Lives until killed in battle. Re-cast of Summon Spirit
# despawns the caster's existing pets and spawns a fresh batch.

const MOVE_SPEED: float = 220.0
const ATTACK_RANGE: float = 60.0
const ATTACK_COOLDOWN: float = 1.0
const DETECTION_RANGE: float = 480.0

var pet_type: String = "wolf"  # "wolf" or "bear"
var damage: int = 10
var max_hp: int = 80
var hp: int = 80
var attack_cd: float = 0.0
var dead: bool = false
var sprite: AnimatedSprite2D = null
# Set by the Summon Spirit cast so re-casts only despawn THIS druid's pets.
var owner_caster: Node = null


func configure(p_type: String, dmg: int) -> void:
	pet_type = p_type
	# Druid spirit pets are DISTRACTIONS — low damage, low HP. The whole point
	# is enemies attack the pet for a few seconds instead of the player. Bear
	# is the tankier exception.
	max_hp = 45
	damage = max(3, int(round(float(dmg) * 0.30)))
	if pet_type == "bear":
		max_hp = 110
		damage = max(6, int(round(float(dmg) * 0.55)))
	hp = max_hp


func _ready() -> void:
	add_to_group("spirit_pet")
	add_to_group("pet_ally")  # unified group enemies aggro on
	collision_layer = 2
	collision_mask = 1
	z_index = 11
	# Build AnimatedSprite2D from the spirit_* PNGs.
	sprite = AnimatedSprite2D.new()
	sprite.name = "Visual"
	add_child(sprite)
	_apply_sprite_frames()


func _apply_sprite_frames() -> void:
	if sprite == null:
		return
	var prefix: String = "spirit_wolf"
	if pet_type == "bear":
		prefix = "spirit_bear"
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
	# Normalize visual height to ~55 px regardless of source PNG resolution.
	var target_h: float = 55.0
	var s: float = 0.12
	if sample_tex:
		var src_h: float = float(sample_tex.get_size().y)
		if src_h > 1.0:
			s = clamp(target_h / src_h, 0.05, 0.5)
	sprite.scale = Vector2(s, s)
	sprite.modulate = Color(0.7, 0.95, 1.05, 0.9)


func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		return
	if attack_cd > 0.0:
		attack_cd -= delta
	var target: Node2D = _find_nearest_enemy()
	if target == null:
		_follow_owner(delta)
		return
	var to_t: Vector2 = target.global_position - global_position
	var dist: float = to_t.length()
	if sprite and abs(to_t.x) > 1.0:
		sprite.flip_h = to_t.x < 0.0
	if dist > ATTACK_RANGE - 10.0:
		velocity = to_t.normalized() * MOVE_SPEED
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
			if sprite.animation != "walk":
				sprite.play("walk")
	else:
		velocity = Vector2.ZERO
		if attack_cd <= 0.0:
			_attack(target)
	move_and_slide()


func _follow_owner(delta: float) -> void:
	# When no enemy is in range, follow the caster — stop near them.
	if owner_caster == null or not is_instance_valid(owner_caster):
		velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
		move_and_slide()
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
			if sprite.animation != "idle":
				sprite.play("idle")
		return
	var to_owner: Vector2 = (owner_caster as Node2D).global_position - global_position
	var dist: float = to_owner.length()
	if dist > 90.0:
		velocity = to_owner.normalized() * MOVE_SPEED
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


func _find_nearest_enemy() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = DETECTION_RANGE
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
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
	# Apply damage right away.
	if target.has_method("take_damage"):
		target.call("take_damage", damage, global_position)
	if VfxManager:
		VfxManager.spawn_hit_sparks(target.global_position, Color(0.55, 0.95, 1.0, 1), 5)


func take_damage(amount: int, _src: Vector2 = Vector2.ZERO) -> void:
	if dead:
		return
	hp -= amount
	if sprite:
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color(1.6, 0.6, 0.6, 1), 0.06)
		tw.tween_property(sprite, "modulate", Color(0.7, 0.95, 1.05, 0.9), 0.18)
	if hp <= 0:
		_die()


func _die() -> void:
	if dead:
		return
	dead = true
	if sprite:
		var tw := sprite.create_tween().set_parallel(true)
		tw.tween_property(sprite, "modulate:a", 0.0, 0.5)
		tw.tween_property(sprite, "scale", sprite.scale * 0.6, 0.5)
		tw.chain().tween_callback(queue_free)
	else:
		queue_free()
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.55, 0.95, 1.0, 1), 14)
	# Use a child Timer instead of get_tree().create_timer so when we're freed
	# the timer dies with us — no orphan callback hitting data.tree=null.
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
