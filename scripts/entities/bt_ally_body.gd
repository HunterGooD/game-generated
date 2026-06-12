class_name BtAllyBody
extends CharacterBody2D

# Shared chassis for summoned allies (necromancer minions, druid spirit pets). Holds
# the co-op networking / puppet / death plumbing, the LimboAI BT host-driver, and the
# AI movement primitives the behaviour trees call. Subclasses supply the differences
# through the small set of virtuals below (speed, ranges, BT path, per-entity timers,
# the attack impl, sprite frames, colours, group).
#
# Co-op invariant: authoritative allies live on the host; every other peer holds a
# visual puppet driven by host-broadcast state (no AI, no damage). The BT runs ONLY
# on the host.

var damage: int = 7
var max_hp: int = 50
var hp: int = 50
var attack_cd: float = 0.0
var dead: bool = false
var sprite: AnimatedSprite2D = null
var owner_caster: Node = null
# Networking.
var network_id: int = -1
var owner_player_id: int = -1
var is_puppet: bool = false
var _net_target_pos: Vector2 = Vector2.ZERO
# LimboAI behaviour tree (host-only, lazily created when use_bt_minions is on).
var _bt_player = null


# ── Virtuals (override in subclasses) ─────────────────────────────────────────
func _ai_group() -> String:
	return "pet_ally"


func _apply_sprite_frames() -> void:
	pass


func _chase_speed() -> float:
	return 200.0


func _detection_range() -> float:
	return 500.0


func _attack_range() -> float:
	return 60.0


func _follow_stop_dist() -> float:
	return 100.0


func _bt_path() -> String:
	return ""


# Decay subclass-specific timers (blood-pact buff, leap windows). attack_cd is ticked
# by the base.
func _tick_ai_timers(_delta: float) -> void:
	pass


# Deal this ally's hit. Subclass-specific (damage scaling, vfx colour, animation).
func _attack(_target: Node2D) -> void:
	pass


func _base_modulate() -> Color:
	return Color(1, 1, 1, 1)


func _death_spark_color() -> Color:
	return Color(1, 1, 1, 1)


# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("pet_ally")  # unified group enemies aggro on
	add_to_group(_ai_group())
	collision_layer = 2
	collision_mask = 1
	z_index = 11
	sprite = AnimatedSprite2D.new()
	sprite.name = "Visual"
	add_child(sprite)
	_apply_sprite_frames()
	BlobShadow.attach_at_feet(self, sprite, 38.0, 14.0)


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


func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		return
	if is_puppet:
		_puppet_process(delta)
		return
	if attack_cd > 0.0:
		attack_cd -= delta
	_tick_ai_timers(delta)
	# LimboAI BT when the feature flag is on (host-only, lazily created); otherwise the
	# legacy primitive sequence. Both drive the same bt_* primitives → parity.
	if _bt_enabled():
		if _bt_player == null:
			_setup_bt()
		if _bt_player != null:
			_bt_player.update(delta)
			return
	_run_host_ai(delta)


# Legacy host-AI sequence: acquire nearest enemy → in range attack, else chase; no
# enemy → follow owner. The LimboAI BT drives the SAME bt_* primitives, so behaviour
# is identical (proven by tests/unit/test_minion_ai + test_spirit_pet_ai).
func _run_host_ai(delta: float) -> void:
	var target := bt_acquire_target()
	if target == null:
		bt_follow_owner(delta)
		return
	if bt_in_attack_range(target.global_position):
		bt_attack(target)
	else:
		bt_move_toward(target.global_position)


# ── AI primitives (shared by the legacy sequence and the LimboAI BT) ───────────
func bt_acquire_target() -> Node2D:
	# Forced-target override (necromancer Commander's Mark; the hook future mark
	# mechanics plug into): if our owner has marked a target in range, focus it.
	# Otherwise behave normally — pick the nearest enemy.
	var marked := _owner_marked_target()
	if marked != null:
		return marked
	return _find_nearest_enemy()


# The owner's marked target, if any, valid, alive, and within reach. Co-op-safe: an
# owner without get_marked_target() (druid, remote puppet) just yields null → normal.
func _owner_marked_target() -> Node2D:
	if owner_caster == null or not is_instance_valid(owner_caster):
		return null
	if not owner_caster.has_method("get_marked_target"):
		return null
	var m = owner_caster.call("get_marked_target")
	if m == null or not is_instance_valid(m) or not (m is Node2D):
		return null
	if m.get("dead") == true:
		return null
	# Don't abandon position to chase a mark across the whole map.
	if global_position.distance_to((m as Node2D).global_position) > _detection_range() * 1.5:
		return null
	return m as Node2D


func bt_in_attack_range(target_pos: Vector2) -> bool:
	return global_position.distance_to(target_pos) <= _attack_range() - 10.0


func bt_move_toward(target_pos: Vector2) -> void:
	_face(target_pos)
	velocity = (target_pos - global_position).normalized() * _chase_speed()
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
		if sprite.animation != "walk":
			sprite.play("walk")
	move_and_slide()


func bt_attack(target: Node2D) -> void:
	_face(target.global_position)
	velocity = Vector2.ZERO
	if attack_cd <= 0.0:
		_attack(target)
	move_and_slide()


func bt_follow_owner(delta: float) -> void:
	_follow_owner(delta)


func _face(target_pos: Vector2) -> void:
	if sprite and absf(target_pos.x - global_position.x) > 1.0:
		sprite.flip_h = target_pos.x < global_position.x


func _follow_owner(delta: float) -> void:
	if owner_caster == null or not is_instance_valid(owner_caster):
		velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
		move_and_slide()
		_play_idle()
		return
	var to_owner: Vector2 = (owner_caster as Node2D).global_position - global_position
	if to_owner.length() > _follow_stop_dist():
		velocity = to_owner.normalized() * _chase_speed()
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
			if sprite.animation != "walk":
				sprite.play("walk")
		if sprite and absf(to_owner.x) > 1.0:
			sprite.flip_h = to_owner.x < 0.0
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
		_play_idle()
	move_and_slide()


func _play_idle() -> void:
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
		if sprite.animation != "idle":
			sprite.play("idle")


func _find_nearest_enemy() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = _detection_range()
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


# ── LimboAI BT host-driver ────────────────────────────────────────────────────
func _bt_enabled() -> bool:
	return GameManager != null and bool(GameManager.use_bt_minions)


# Lazily create the host BTPlayer driving this ally's tree. MANUAL update_mode — we
# tick it ourselves from _physics_process so it stays in lockstep with the legacy
# path's timers. Runtime-spawned allies have no scene owner, so hint the scene root
# (our tasks use get_agent(), no node paths, so self is a fine root).
func _setup_bt() -> void:
	var bt = load(_bt_path())
	if bt == null:
		return
	_bt_player = ClassDB.instantiate("BTPlayer")
	if _bt_player == null:
		return
	_bt_player.behavior_tree = bt
	_bt_player.update_mode = 2  # BTPlayer.UpdateMode.MANUAL
	_bt_player.set_scene_root_hint(self)
	add_child(_bt_player)


# ── Puppet (client visual) ────────────────────────────────────────────────────
func _puppet_process(delta: float) -> void:
	var to_t: Vector2 = _net_target_pos - global_position
	if to_t.length() > 2.0:
		global_position = global_position.lerp(_net_target_pos, clamp(12.0 * delta, 0.0, 1.0))
		if sprite and absf(to_t.x) > 1.0:
			sprite.flip_h = to_t.x < 0.0
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
			if sprite.animation != "walk":
				sprite.play("walk")
	else:
		_play_idle()


# ── Damage / death ────────────────────────────────────────────────────────────
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
		tw.tween_property(sprite, "modulate", _base_modulate(), 0.18)
	if hp <= 0:
		_die()


func _die() -> void:
	if dead:
		return
	dead = true
	# Host: tell peers to drop their puppet of this ally.
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
		VfxManager.spawn_hit_sparks(global_position, _death_spark_color(), 10)
	# Child Timer (not get_tree().create_timer) so it dies with us — no orphan callback.
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
