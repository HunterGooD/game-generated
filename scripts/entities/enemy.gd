class_name Enemy
extends CharacterBody2D

# Base enemy — chase player, deal damage, drop loot. Subclasses tune behavior
# via the EnemyConfig dictionary they pass through `configure()`.

const ENEMY_PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/enemy/enemy_projectile.tscn")

# Tunable defaults — overwritten by configure().
var max_hp: int = 30
var hp: int = 30
var move_speed: float = 90.0
var attack_damage: int = 8
var attack_range: float = 60.0
var attack_cooldown: float = 1.2
var detection_range: float = 380.0
var xp_value: int = 12
var gold_drop_min: int = 1
var gold_drop_max: int = 4
var enemy_type: String = "skeleton"
var sprite_path_idle: String = ""
var sprite_path_walk: String = ""
var sprite_path_attack: String = ""
var sprite_scale: float = 0.34
var hue_tint: Color = Color(1, 1, 1, 1)
var is_ranged: bool = false
var ranged_kite_distance: float = 220.0
var fly: bool = false
var is_aoe: bool = false
var is_brood_mother: bool = false
var hatchling_spawn_t: float = 4.0

@export var sprite: Sprite2D
@export var hp_bar: ProgressBar
@export var collision_shape: CollisionShape2D
@export var hitbox: HitBoxComponent
@export var hurtbox: HurtBoxComponent
@export var stats_component: StatsComponent
@export var health_component: HealthComponent
@export var status_effect_receiver: StatusEffectReceiverComponent
@export var ai_component: EnemyAIComponent
@export var reward_drop: RewardDropComponent

const HIT_FLASH_SHADER: Shader = preload("res://assets/shaders/hit_flash.gdshader")
const DISSOLVE_SHADER: Shader = preload("res://assets/shaders/dissolve.gdshader")

var player: Node2D = null
var attack_cd: float = 0.0
var attack_lockout: float = 0.0
var slow_t: float = 0.0
var slow_mult: float = 1.0
var dead: bool = false

# ── Elemental status (shared by the Mage ascensions) ──────────────────────────
# Burn: a damage-over-time that also tags the "fire" element for Fracture.
var burn_t: float = 0.0
var burn_dps: float = 0.0
var _burn_tick_t: float = 0.0
# Chill: stacking slow that hard-freezes at CHILL_FREEZE_STACKS; tags "frost".
var chill_stacks: int = 0
var chill_t: float = 0.0
var frozen_t: float = 0.0
# Tri-Element Fracture (Elementalist): time-remaining per element seen recently.
# When fire+frost+storm overlap the enemy is "fractured" for FRACTURE_WINDOW.
var _elem_seen: Dictionary = {}  # element -> seconds remaining
var fractured_t: float = 0.0
const CHILL_FREEZE_STACKS: int = 4
const ELEM_WINDOW: float = 5.0
const FRACTURE_WINDOW: float = 5.0

# ── Physical status (shared by the Barbarian / Rogue ascensions) ──────────────
# Bleed: a physical damage-over-time (no elemental tag).
var bleed_t: float = 0.0
var bleed_dps: float = 0.0
var _bleed_tick_t: float = 0.0
# Vulnerable / Armor Break: scales incoming damage up for a while.
var vuln_t: float = 0.0
var vuln_amp: float = 0.0
# Taunt: forces this enemy to chase a specific node while active.
var taunt_target: Node2D = null
var taunt_t: float = 0.0
# Floating debuff icons above the enemy (built lazily when first afflicted).
var _status_strip: StatusIcons = null
var _status_ui_t: float = 0.0
# Poison: stacking DoT (Venomancer). At POISON_MAX it mutates to Necrotic Poison
# (also armor-breaks). Each stack adds damage; refreshing extends the duration.
var poison_stacks: int = 0
var poison_t: float = 0.0
var _poison_tick_t: float = 0.0
const POISON_MAX: int = 10
# Curse stacks: generic distinct-debuff counter (Hexen Threefold Curse / Coven Sin).
var curse_stacks: int = 0
var curse_t: float = 0.0
var hp_bar_shown: bool = false
var retarget_t: float = 0.0

# Multiplayer puppet state.
var is_puppet: bool = false
var network_id: int = -1
var _puppet_target_pos: Vector2 = Vector2.ZERO

# State flags.
var _idle_jitter: Vector2 = Vector2.ZERO
var _idle_jitter_t: float = 0.0
var _runtime_base_stats: ActorStatsResource = ActorStatsResource.new()
var _melee_hitbox_active: bool = false


func _ready() -> void:
	collision_layer = 4 | 8  # bit 3 enemies, bit 4 hurtable
	collision_mask = 1
	add_to_group("enemy")
	_setup_components()
	_sync_component_stats(true)
	# Initialise puppet target to spawn position so it doesn't lerp to (0,0).
	_puppet_target_pos = global_position

	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = hp
		hp_bar.visible = false

	if hurtbox:
		hurtbox.collision_layer = 16  # bit 5 — enemy hurtbox
		hurtbox.collision_mask = 0
		hurtbox.add_to_group("enemy_hit")

	if hitbox:
		hitbox.collision_layer = 0
		hitbox.collision_mask = 2  # bit 2 — player hurtbox
		hitbox.hit.connect(_on_attack_hit_hurtbox)
		hitbox.disable_collision()

	_apply_sprite()
	_install_hit_flash_material()
	_find_player()


func _setup_components() -> void:
	if stats_component:
		stats_component.base_stats = _runtime_base_stats
	if health_component:
		health_component.main_stats = stats_component
		if not health_component.hp_change.is_connected(_on_health_component_changed):
			health_component.hp_change.connect(_on_health_component_changed)
		if not health_component.dead.is_connected(_on_health_component_dead):
			health_component.dead.connect(_on_health_component_dead)
	if status_effect_receiver:
		status_effect_receiver.main_stats = stats_component
		status_effect_receiver.health_component = health_component
	if hurtbox:
		hurtbox.health_component = health_component
		hurtbox.status_effect_receiver = status_effect_receiver
		hurtbox.damage_receiver = self


func _sync_component_stats(full_heal: bool = false) -> void:
	if stats_component == null:
		return

	_runtime_base_stats.max_health = float(max_hp)
	_runtime_base_stats.move_speed = move_speed
	_runtime_base_stats.armor = 0.0
	_runtime_base_stats.damage = float(attack_damage)
	_runtime_base_stats.max_mana = 0.0
	_runtime_base_stats.mana_regen = 0.0
	_runtime_base_stats.attack_speed = 1.0
	_runtime_base_stats.crit_chance = 0.0
	_runtime_base_stats.crit_damage = 1.5
	_runtime_base_stats.dash_charges = 0
	stats_component.stats_changed.emit()

	if health_component:
		health_component.max_hp = max(1.0, stats_component.get_max_health())
		if full_heal:
			health_component.current_hp = health_component.max_hp
		else:
			health_component.current_hp = clampf(float(hp), 0.0, health_component.max_hp)
		health_component.is_dead = dead or health_component.current_hp <= 0.0
		health_component.hp_change.emit(health_component.current_hp, health_component.max_hp)


func configure(cfg: Dictionary) -> void:
	enemy_type = String(cfg.get("type", enemy_type))
	max_hp = int(cfg.get("max_hp", max_hp))
	hp = max_hp
	move_speed = float(cfg.get("move_speed", move_speed))
	attack_damage = int(cfg.get("attack_damage", attack_damage))
	attack_range = float(cfg.get("attack_range", attack_range))
	attack_cooldown = float(cfg.get("attack_cooldown", attack_cooldown))
	detection_range = float(cfg.get("detection_range", detection_range))
	xp_value = int(cfg.get("xp_value", xp_value))
	gold_drop_min = int(cfg.get("gold_min", gold_drop_min))
	gold_drop_max = int(cfg.get("gold_max", gold_drop_max))
	sprite_path_idle = String(cfg.get("sprite_idle", ""))
	sprite_path_walk = String(cfg.get("sprite_walk", ""))
	sprite_path_attack = String(cfg.get("sprite_attack", ""))
	sprite_scale = float(cfg.get("sprite_scale", sprite_scale))
	hue_tint = cfg.get("tint", Color(1, 1, 1, 1))
	is_ranged = bool(cfg.get("ranged", false))
	ranged_kite_distance = float(cfg.get("kite_distance", ranged_kite_distance))
	fly = bool(cfg.get("fly", false))
	is_aoe = bool(cfg.get("aoe", false))
	is_brood_mother = bool(cfg.get("brood_mother", false))
	if reward_drop:
		reward_drop.xp_value = xp_value
		reward_drop.gold_min = gold_drop_min
		reward_drop.gold_max = gold_drop_max
	if is_inside_tree():
		_apply_sprite()
		_sync_component_stats(true)


func _apply_sprite() -> void:
	if sprite == null:
		return
	var src_h: float = 0.0
	if sprite_path_idle != "" and ResourceLoader.exists(sprite_path_idle):
		var tex: Texture2D = load(sprite_path_idle) as Texture2D
		if tex:
			sprite.texture = tex
			src_h = float(tex.get_size().y)
	# Target visible height ~95 px regardless of source PNG resolution. Legacy
	# enemies (256 source × 0.36 scale ≈ 92 px) land in the same ballpark, so
	# they don't visibly shift; oversized sources (768 px) are auto-shrunk.
	var s: float = sprite_scale
	if src_h > 1.0:
		s = clamp(95.0 / src_h, 0.08, 0.6)
	sprite.scale = Vector2(s, s)
	sprite.modulate = hue_tint


func _install_hit_flash_material() -> void:
	if sprite == null:
		return
	# We share the hit-flash and dissolve uniforms on one ShaderMaterial. The
	# dissolve uniform stays at 0 during life and is driven only by _die().
	var mat := ShaderMaterial.new()
	mat.shader = HIT_FLASH_SHADER
	mat.set_shader_parameter("flash_amount", 0.0)
	mat.set_shader_parameter("flash_color", Color(2.0, 0.45, 0.45, 1.0))
	sprite.material = mat


func _flash_hit() -> void:
	if sprite == null or sprite.material == null:
		return
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("flash_amount", 1.0)
	var tw := create_tween()
	(
		tw
		. tween_method(
			func(v: float):
				if mat:
					mat.set_shader_parameter("flash_amount", v),
			1.0,
			0.0,
			0.18
		)
		. set_trans(Tween.TRANS_QUAD)
	)


func _find_player() -> void:
	# Targets the nearest valid combatant — local player OR an allied pet.
	# Pets are in the "pet_ally" group, so a pet that stands in front of the
	# enemy automatically pulls aggro off the player (taunt-by-proximity).
	# Acquisition + co-op/visibility filtering lives in EnemyAIComponent.
	if ai_component == null:
		return
	# Drop a cached target that has gone downed/dead — find_nearest_target already
	# filters those out, but it only REPLACES `player` when it finds another valid
	# target. If the downed ally is the only one nearby it returns null and we'd
	# otherwise keep swinging at the corpse. Clearing here makes the enemy idle /
	# wander instead.
	if (
		player != null
		and is_instance_valid(player)
		and (player.get("is_downed") == true or player.get("is_dead") == true)
	):
		player = null
	# Taunt overrides target acquisition while it lasts.
	if taunt_t > 0.0 and is_instance_valid(taunt_target):
		player = taunt_target
		return
	var best: Node2D = ai_component.find_nearest_target(global_position)
	if best != null:
		player = best


func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		return
	# Puppet mode (multiplayer client) — lerp toward host-broadcast position,
	# no AI, no attacks.
	if is_puppet:
		var w: float = clamp(12.0 * delta, 0.0, 1.0)
		global_position = global_position.lerp(_puppet_target_pos, w)
		return
	if attack_lockout > 0.0:
		attack_lockout -= delta
	if slow_t > 0.0:
		slow_t -= delta
		if slow_t <= 0.0:
			slow_mult = 1.0
			modulate = Color(1, 1, 1, 1)
	_tick_status(delta)
	# Refresh the floating debuff icons a few times a second (host/solo only —
	# puppets carry no authoritative status to show).
	_status_ui_t -= delta
	if _status_ui_t <= 0.0:
		_status_ui_t = 0.2
		_update_status_ui()
	# Brood mother — periodically spawn 2 hatchlings while alive.
	if is_brood_mother and not is_puppet:
		hatchling_spawn_t -= delta
		if hatchling_spawn_t <= 0.0:
			hatchling_spawn_t = 4.0
			_spawn_hatchlings(2)
	if attack_cd > 0.0:
		attack_cd -= delta

	# Periodically reconsider target so aggro routes to whichever ally is now
	# closest (e.g. a fresh spirit pet pulls the enemy off a fleeing player).
	retarget_t -= delta
	if retarget_t <= 0.0:
		retarget_t = 0.4
		_find_player()
	if player == null or not is_instance_valid(player):
		_find_player()
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
		move_and_slide()
		return

	# Stealthed players are invisible to the AI. Airborne players (druid in
	# eagle form) are out of reach of ground enemies — same treatment.
	if player.is_in_group("stealthed") or player.is_in_group("airborne"):
		velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
		move_and_slide()
		return

	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()

	# Sprite facing.
	if sprite and abs(to_player.x) > 1.0:
		sprite.flip_h = to_player.x < 0.0

	if dist <= detection_range:
		if is_aoe:
			# Succubus: kite at medium range, charge up an AOE attack.
			var aoe_keep: float = max(180.0, attack_range - 40.0)
			if dist < aoe_keep - 30.0:
				velocity = -to_player.normalized() * move_speed * slow_mult
			elif dist > attack_range:
				velocity = to_player.normalized() * move_speed * slow_mult
			else:
				velocity = Vector2.ZERO
			if dist <= attack_range and attack_cd <= 0.0 and attack_lockout <= 0.0:
				_perform_aoe_attack()
		elif is_ranged:
			# Kite — keep at ranged_kite_distance.
			if dist < ranged_kite_distance - 30.0:
				velocity = -to_player.normalized() * move_speed * slow_mult
			elif dist > ranged_kite_distance + 30.0:
				velocity = to_player.normalized() * move_speed * slow_mult
			else:
				velocity = Vector2.ZERO
			if dist <= attack_range and attack_cd <= 0.0 and attack_lockout <= 0.0:
				_perform_ranged_attack()
		else:
			# Melee — chase to attack range.
			if dist > attack_range - 10.0:
				velocity = to_player.normalized() * move_speed * slow_mult
			else:
				velocity = Vector2.ZERO
				if attack_cd <= 0.0 and attack_lockout <= 0.0:
					_perform_melee_attack()
	else:
		# Idle wander.
		_idle_jitter_t -= delta
		if _idle_jitter_t <= 0.0:
			_idle_jitter_t = randf_range(1.0, 2.0)
			_idle_jitter = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * 30.0
		velocity = velocity.move_toward(_idle_jitter, 200.0 * delta)

	move_and_slide()


func _perform_melee_attack() -> void:
	attack_cd = attack_cooldown
	attack_lockout = 0.45
	if sprite_path_attack != "" and ResourceLoader.exists(sprite_path_attack) and sprite:
		var atk_tex: Texture2D = load(sprite_path_attack) as Texture2D
		if atk_tex:
			sprite.texture = atk_tex
		var t := get_tree().create_timer(0.3)
		t.timeout.connect(_restore_idle_sprite)

	# Wind-up tween — lunge forward.
	if player and is_instance_valid(player):
		var dir: Vector2 = (player.global_position - global_position).normalized()
		var orig: Vector2 = global_position
		var lunge: Vector2 = orig + dir * 22.0
		var tw := create_tween()
		(
			tw
			. tween_property(self, "global_position", lunge, 0.12)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		tw.tween_callback(_apply_melee_damage)
		tw.tween_property(self, "global_position", orig, 0.18).set_trans(Tween.TRANS_QUAD)


func _restore_idle_sprite() -> void:
	if dead or sprite == null:
		return
	if sprite_path_idle != "" and ResourceLoader.exists(sprite_path_idle):
		var t: Texture2D = load(sprite_path_idle) as Texture2D
		if t:
			sprite.texture = t


func _apply_melee_damage() -> void:
	# The swing tween can land this callback a frame or two after we've started
	# dying — bail so we don't poke a hitbox whose monitoring is being torn down.
	if dead or not is_instance_valid(player):
		return
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= attack_range + 20.0:
		if hitbox:
			_activate_melee_hitbox()
		else:
			if player.has_method("take_damage"):
				player.call("take_damage", attack_damage)


func _activate_melee_hitbox() -> void:
	if hitbox == null or _melee_hitbox_active or dead:
		return

	_melee_hitbox_active = true
	hitbox.payload = _build_melee_damage_payload()
	hitbox.enable_collision()

	# get_overlapping_areas() errors out if monitoring is off (the hitbox can be
	# mid-teardown when the enemy dies during the swing). Guard the instant-
	# overlap sweep; the area_entered signal still covers newly-entering targets.
	if hitbox.monitoring:
		for area in hitbox.get_overlapping_areas():
			if area is HurtBoxComponent:
				var hurt_box := area as HurtBoxComponent
				if hurt_box.receive_hit(hitbox):
					_end_melee_hitbox_window()
					return

	var t := get_tree().create_timer(0.08)
	t.timeout.connect(_end_melee_hitbox_window)


func _end_melee_hitbox_window() -> void:
	_melee_hitbox_active = false
	if hitbox:
		hitbox.payload = null
		hitbox.disable_collision()


func _on_attack_hit_hurtbox(area: Area2D) -> void:
	if not _melee_hitbox_active:
		return
	if area is HurtBoxComponent:
		_end_melee_hitbox_window()


func _build_melee_damage_payload() -> DamageInstance:
	return DamageInstance.new(
		float(attack_damage),
		self,
		hitbox,
		[&"enemy", &"melee"],
		[]
	)


func _perform_aoe_attack() -> void:
	# Succubus signature attack: telegraph for ~0.9s at the player's current
	# position, then blast a heart-shaped AOE there.
	attack_cd = attack_cooldown
	attack_lockout = 1.1
	if sprite_path_attack != "" and ResourceLoader.exists(sprite_path_attack) and sprite:
		var atk_tex: Texture2D = load(sprite_path_attack) as Texture2D
		if atk_tex:
			sprite.texture = atk_tex
		var t := get_tree().create_timer(0.95)
		t.timeout.connect(_restore_idle_sprite)
	if not is_instance_valid(player):
		return
	var target_pos: Vector2 = player.global_position
	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/enemy/enemy_succubus_attack_charge.mp3", -10.0
		)
	# Telegraph.
	var tel := Sprite2D.new()
	var tel_path := "res://assets/sprites/effects/succubus_aoe_telegraph.png"
	if ResourceLoader.exists(tel_path):
		tel.texture = load(tel_path) as Texture2D
	tel.modulate = Color(1.0, 0.4, 0.7, 0.85)
	tel.scale = Vector2(0.8, 0.8)
	tel.global_position = target_pos
	tel.z_index = 50
	get_tree().current_scene.add_child(tel)
	var pulse := tel.create_tween().set_loops(5)
	pulse.tween_property(tel, "scale", Vector2(1.0, 1.0), 0.09)
	pulse.tween_property(tel, "scale", Vector2(0.8, 0.8), 0.09)
	# Safety self-free owned by the telegraph itself. If we (the succubus) are
	# killed during the wind-up, the _aoe_blast callback below is bound to us and
	# is dropped when we're freed — without this the pink telegraph would linger
	# on the ground forever. The tween lives on `tel` (parented to the scene), so
	# it survives our death; if _aoe_blast does fire first it frees `tel` and this
	# tween dies with it, so there's no double-free.
	var tel_safety := tel.create_tween()
	tel_safety.tween_interval(1.1)
	tel_safety.tween_callback(tel.queue_free)
	# Detonate after the wind-up.
	var blast_timer := get_tree().create_timer(0.9)
	blast_timer.timeout.connect(_aoe_blast.bind(target_pos, tel))


func _aoe_blast(target_pos: Vector2, telegraph: Sprite2D) -> void:
	if is_instance_valid(telegraph):
		telegraph.queue_free()
	if is_puppet:
		# Puppet copies don't deal damage — host does. But still play the visual.
		_spawn_aoe_visual(target_pos)
		return
	_spawn_aoe_visual(target_pos)
	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/enemy/enemy_succubus_aoe_blast.mp3", -8.0
		)
	if VfxManager:
		VfxManager.screen_shake(3.0, 0.18)
		VfxManager.screen_flash(Color(1.0, 0.4, 0.7, 0.18), 0.2)
	# Damage anyone in radius.
	var tree := get_tree()
	if tree == null:
		return
	var radius: float = 130.0
	var dmg: int = int(round(float(attack_damage) * 1.4))
	if ai_component == null:
		return
	for p in ai_component.gather_targets_in_radius(target_pos, radius):
		if p.has_method("receive_damage_payload"):
			p.call("receive_damage_payload", DamageInstance.new(float(dmg), self, self, [&"enemy", &"aoe"], []))
		elif p.has_method("take_damage"):
			p.call("take_damage", dmg)


func _spawn_aoe_visual(target_pos: Vector2) -> void:
	var s := Sprite2D.new()
	var path := "res://assets/sprites/effects/succubus_kiss_blast.png"
	if ResourceLoader.exists(path):
		s.texture = load(path) as Texture2D
	s.modulate = Color(1.0, 0.45, 0.7, 1)
	s.scale = Vector2(0.6, 0.6)
	s.global_position = target_pos
	s.z_index = 60
	get_tree().current_scene.add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector2(1.4, 1.4), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_property(s, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(s.queue_free)


func _perform_ranged_attack() -> void:
	attack_cd = attack_cooldown
	attack_lockout = 0.35
	if sprite_path_attack != "" and ResourceLoader.exists(sprite_path_attack) and sprite:
		var atk_tex: Texture2D = load(sprite_path_attack) as Texture2D
		if atk_tex:
			sprite.texture = atk_tex
		var t := get_tree().create_timer(0.3)
		t.timeout.connect(_restore_idle_sprite)
	if not is_instance_valid(player):
		return
	var dir: Vector2 = (player.global_position - global_position).normalized()
	var proj := ENEMY_PROJECTILE_SCENE.instantiate()
	get_tree().current_scene.add_child(proj)
	proj.global_position = global_position + dir * 24.0
	if proj.has_method("setup"):
		proj.call("setup", dir, attack_damage)


func _on_attack_hit_body(_body: Node) -> void:
	# Unused — damage via tween callback above.
	pass


func _on_health_component_changed(current_hp: float, current_max_hp: float) -> void:
	hp = int(round(current_hp))
	max_hp = int(round(current_max_hp))
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = max(hp, 0)
		if not hp_bar_shown and hp < max_hp:
			hp_bar.visible = true
			hp_bar_shown = true


func _on_health_component_dead(_damage_payload: DamageInstance) -> void:
	_die()


func receive_damage_payload(payload: DamageInstance) -> bool:
	if payload == null or dead:
		return false

	var amount: int = int(round(payload.amount))
	if dead:
		return false
	# Curse Field amplification — if we're standing in a necromancer's curse
	# zone, scale up the incoming damage.
	if has_meta("curse_amp"):
		var amp: float = float(get_meta("curse_amp", 0.0))
		if amp > 0.0:
			amount = int(round(float(amount) * (1.0 + amp)))
	# Vulnerable / Armor Break amplifies all incoming damage.
	if vuln_t > 0.0 and vuln_amp > 0.0:
		amount = int(round(float(amount) * (1.0 + vuln_amp)))
	# Soul Tether mirror — broadcast a fraction of this hit to other linked
	# enemies. has_meta() guard avoids the get_meta-missing-key spam when no
	# Hexen tether is active.
	if has_meta("tether_node"):
		var tether_node = get_meta("tether_node")
		if (
			tether_node
			and is_instance_valid(tether_node)
			and tether_node.has_method("mirror_damage")
		):
			tether_node.call("mirror_damage", self, amount)
	# Puppet (client) — forward to host, do NOT modify HP locally. Show a
	# brief hit flash so the player gets feedback while the round-trip happens.
	if is_puppet:
		if NetManager:
			NetManager.send("enemy_hit", {"id": network_id, "damage": amount})
		if sprite:
			var tw := create_tween()
			tw.tween_property(sprite, "modulate", Color(2.0, 0.4, 0.4, 1), 0.04)
			tw.tween_property(sprite, "modulate", hue_tint, 0.18)
		if VfxManager:
			VfxManager.spawn_hit_sparks(global_position, Color(1, 0.7, 0.4, 1), 4)
		return false
	var previous_hp: int = hp
	var knockback: Vector2 = payload.knockback
	if knockback == Vector2.ZERO and payload.source is Node2D:
		var source_position: Vector2 = (payload.source as Node2D).global_position
		if source_position != Vector2.ZERO:
			knockback = (global_position - source_position).normalized() * 110.0
	if health_component:
		health_component.apply_damage(
			DamageInstance.new(
				float(amount),
				payload.attacker,
				payload.source,
				payload.tags,
				payload.status_effects,
				payload.crit,
				knockback,
				payload.is_stealth
			)
		)
		hp = int(round(health_component.current_hp))
	else:
		hp -= amount
	var applied_amount: int = max(0, previous_hp - hp)
	if applied_amount <= 0:
		return false
	# Damage number + hit sparks.
	if VfxManager:
		VfxManager.spawn_damage_number(
			global_position + Vector2(0, -20), applied_amount, Color(1, 0.85, 0.4, 1)
		)
		var spark_color: Color = hue_tint.lerp(Color(1, 0.5, 1, 1), 0.6)
		VfxManager.spawn_hit_sparks(global_position, spark_color, 6)
		VfxManager.hit_stop(0.04)
	# Flash via the hit-flash shader (cleaner than modulate-tween races).
	_flash_hit()
	# Show HP bar after first hit.
	if hp_bar and not hp_bar_shown:
		hp_bar.visible = true
		hp_bar_shown = true
	if hp_bar:
		hp_bar.value = max(hp, 0)
	# Knockback impulse.
	if knockback != Vector2.ZERO:
		velocity = knockback
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/enemy/enemy_enemy_hurt.mp3", -10.0)
	if health_component == null and hp <= 0:
		_die()
	return true


func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	var knockback: Vector2 = Vector2.ZERO
	if source_position != Vector2.ZERO:
		knockback = (global_position - source_position).normalized() * 110.0
	receive_damage_payload(
		DamageInstance.new(float(amount), null, self, [&"player_hit"], [], false, knockback)
	)


func apply_slow(duration: float, mult: float) -> void:
	if dead:
		return
	slow_t = max(slow_t, duration)
	slow_mult = min(slow_mult, mult)
	if sprite:
		sprite.modulate = Color(0.7, 0.85, 1.4, 1)


# ── Elemental status API ──────────────────────────────────────────────────────
# Burn: stacking-refresh DoT. Also tags the fire element (Fracture).
func apply_burn(duration: float, dps: float) -> void:
	if dead:
		return
	burn_t = max(burn_t, duration)
	burn_dps = max(burn_dps, dps)
	mark_element("fire")


# Chill: each application adds a slow stack; at CHILL_FREEZE_STACKS the enemy
# freezes solid briefly. Tags the frost element (Fracture).
func apply_chill(duration: float, stacks: int = 1) -> void:
	if dead:
		return
	chill_t = max(chill_t, duration)
	chill_stacks = mini(chill_stacks + stacks, CHILL_FREEZE_STACKS)
	var mult: float = max(0.35, 1.0 - 0.16 * float(chill_stacks))
	apply_slow(duration, mult)
	if chill_stacks >= CHILL_FREEZE_STACKS:
		frozen_t = max(frozen_t, 1.0)
	mark_element("frost")


# Record that `element` ("fire"/"frost"/"storm") just hit this enemy. Once all
# three are present within ELEM_WINDOW the enemy becomes Fractured.
func mark_element(element: String) -> void:
	if dead:
		return
	_elem_seen[element] = ELEM_WINDOW
	if _elem_seen.size() >= 3:
		fractured_t = FRACTURE_WINDOW
		_elem_seen.clear()
		if VfxManager:
			VfxManager.spawn_hit_sparks(global_position, Color(0.9, 0.7, 1.0, 1), 12)


func is_burning() -> bool:
	return burn_t > 0.0


func is_chilled() -> bool:
	return chill_t > 0.0 or frozen_t > 0.0


func is_frozen() -> bool:
	return frozen_t > 0.0


func is_fractured() -> bool:
	return fractured_t > 0.0


# Consume the Fracture (Elementalist): returns true once, granting the +damage /
# death-explosion payoff, then clears the state so it isn't double-spent.
func consume_fracture() -> bool:
	if fractured_t <= 0.0:
		return false
	fractured_t = 0.0
	return true


# Bleed: physical DoT (Barbarian Bleed / Rogue Razor Trap).
func apply_bleed(duration: float, dps: float) -> void:
	if dead:
		return
	bleed_t = max(bleed_t, duration)
	bleed_dps = max(bleed_dps, dps)


func is_bleeding() -> bool:
	return bleed_t > 0.0


# Vulnerable / Armor Break: incoming damage scaled by (1 + amp) while active.
func apply_vulnerable(duration: float, amp: float) -> void:
	if dead:
		return
	vuln_t = max(vuln_t, duration)
	vuln_amp = max(vuln_amp, amp)


func is_vulnerable() -> bool:
	return vuln_t > 0.0


# Taunt: chase `node` until the timer runs out (Warchief Banner / Trickster Decoy).
func apply_taunt(node: Node2D, duration: float) -> void:
	if dead or node == null:
		return
	taunt_target = node
	taunt_t = max(taunt_t, duration)


# Poison: each application adds `stacks` (cap POISON_MAX) and refreshes duration.
# `dps_each` is the per-stack damage. At the cap it becomes Necrotic (armor break).
func apply_poison(stacks: int, duration: float, dps_each: float) -> void:
	if dead:
		return
	poison_stacks = mini(poison_stacks + stacks, POISON_MAX)
	poison_t = max(poison_t, duration)
	set_meta("poison_dps_each", dps_each)
	if poison_stacks >= POISON_MAX:
		apply_vulnerable(duration, 0.2)  # Necrotic Poison strips armor


func is_poisoned() -> bool:
	return poison_t > 0.0


func get_poison_stacks() -> int:
	return poison_stacks


# Curse: track distinct debuffs over a window; returns the running stack count so
# callers (Hexen) can trigger bursts on every Nth unique curse.
func add_curse_stack() -> int:
	if dead:
		return 0
	curse_stacks += 1
	curse_t = 6.0
	return curse_stacks


# Active debuffs for the floating status row above the enemy. Each entry:
# {id, label, color, progress(0..1 remaining)}. Reference durations approximate the
# dial; small squares, no labels by default.
# Lazily build / refresh the floating debuff strip above the enemy.
func _update_status_ui() -> void:
	var list: Array = get_active_statuses()
	if _status_strip == null:
		if list.is_empty():
			return
		_status_strip = StatusIcons.new()
		_status_strip.icon_size = 16.0
		_status_strip.gap = 2.0
		_status_strip.show_labels = true
		_status_strip.centered = true
		_status_strip.z_index = 80
		_status_strip.position = Vector2(0, -58)
		add_child(_status_strip)
	_status_strip.visible = not list.is_empty()
	if not list.is_empty():
		_status_strip.update_statuses(list)


func get_active_statuses() -> Array:
	var out: Array = []
	if burn_t > 0.0:
		out.append({"id": "burn", "label": "B", "color": Color(1.0, 0.5, 0.15), "progress": clampf(burn_t / 4.0, 0.0, 1.0)})
	if frozen_t > 0.0:
		out.append({"id": "frozen", "label": "F", "color": Color(0.5, 0.8, 1.0), "progress": clampf(frozen_t / 1.0, 0.0, 1.0)})
	elif chill_t > 0.0:
		out.append({"id": "chill", "label": "C", "color": Color(0.6, 0.85, 1.0), "progress": clampf(chill_t / 3.0, 0.0, 1.0)})
	elif slow_t > 0.0:
		out.append({"id": "slow", "label": "S", "color": Color(0.5, 0.65, 1.0), "progress": clampf(slow_t / 3.0, 0.0, 1.0)})
	if bleed_t > 0.0:
		out.append({"id": "bleed", "label": "L", "color": Color(0.75, 0.05, 0.08), "progress": clampf(bleed_t / 4.0, 0.0, 1.0)})
	if poison_t > 0.0:
		out.append({"id": "poison", "label": "P", "color": Color(0.4, 0.8, 0.2), "progress": clampf(poison_t / 5.0, 0.0, 1.0)})
	if vuln_t > 0.0:
		out.append({"id": "vuln", "label": "V", "color": Color(0.75, 0.4, 0.9), "progress": clampf(vuln_t / 8.0, 0.0, 1.0)})
	if fractured_t > 0.0:
		out.append({"id": "fracture", "label": "X", "color": Color(0.9, 0.6, 1.0), "progress": clampf(fractured_t / 5.0, 0.0, 1.0)})
	if curse_t > 0.0:
		out.append({"id": "curse", "label": "K", "color": Color(0.55, 0.2, 0.6), "progress": clampf(curse_t / 6.0, 0.0, 1.0)})
	if taunt_t > 0.0:
		out.append({"id": "taunt", "label": "T", "color": Color(0.95, 0.85, 0.3), "progress": clampf(taunt_t / 1.0, 0.0, 1.0)})
	return out


func _tick_status(delta: float) -> void:
	if frozen_t > 0.0:
		frozen_t -= delta
		slow_mult = min(slow_mult, 0.05)
	if chill_t > 0.0:
		chill_t -= delta
		if chill_t <= 0.0:
			chill_stacks = 0
	if fractured_t > 0.0:
		fractured_t -= delta
	for el in _elem_seen.keys():
		var left: float = float(_elem_seen[el]) - delta
		if left <= 0.0:
			_elem_seen.erase(el)
		else:
			_elem_seen[el] = left
	if burn_t > 0.0:
		burn_t -= delta
		_burn_tick_t -= delta
		if _burn_tick_t <= 0.0:
			_burn_tick_t = 0.5
			_apply_burn_tick()
	if bleed_t > 0.0:
		bleed_t -= delta
		_bleed_tick_t -= delta
		if _bleed_tick_t <= 0.0:
			_bleed_tick_t = 0.5
			_apply_bleed_tick()
	if vuln_t > 0.0:
		vuln_t -= delta
		if vuln_t <= 0.0:
			vuln_amp = 0.0
	if taunt_t > 0.0:
		taunt_t -= delta
		if taunt_t <= 0.0 or not is_instance_valid(taunt_target):
			taunt_target = null
	if poison_t > 0.0:
		poison_t -= delta
		_poison_tick_t -= delta
		if _poison_tick_t <= 0.0:
			_poison_tick_t = 0.5
			_apply_poison_tick()
		if poison_t <= 0.0:
			poison_stacks = 0
	if curse_t > 0.0:
		curse_t -= delta
		if curse_t <= 0.0:
			curse_stacks = 0


# Burn DoT damage. Host-authoritative (puppets never reach here). Routes through
# the normal damage path so HP/HUD/death all behave; tagged as a DoT so it can't
# crit or knock back.
func _apply_burn_tick() -> void:
	if dead or burn_dps <= 0.0:
		return
	var tick: int = max(1, int(round(burn_dps * 0.5)))
	receive_damage_payload(
		DamageInstance.new(float(tick), null, self, [&"burn"], [], false, Vector2.ZERO)
	)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(1.0, 0.5, 0.15, 1), 3)


func _apply_bleed_tick() -> void:
	if dead or bleed_dps <= 0.0:
		return
	var tick: int = max(1, int(round(bleed_dps * 0.5)))
	receive_damage_payload(
		DamageInstance.new(float(tick), null, self, [&"bleed"], [], false, Vector2.ZERO)
	)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.7, 0.05, 0.08, 1), 3)


func _apply_poison_tick() -> void:
	if dead or poison_stacks <= 0:
		return
	var dps_each: float = float(get_meta("poison_dps_each", 2.0))
	var tick: int = max(1, int(round(dps_each * float(poison_stacks) * 0.5)))
	receive_damage_payload(
		DamageInstance.new(float(tick), null, self, [&"poison"], [], false, Vector2.ZERO)
	)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.4, 0.85, 0.2, 1), 3)


# Small elemental detonation when a Fractured enemy dies — splashes foes within
# FRACTURE_BURST_RADIUS for a fraction of this enemy's max HP.
func _fracture_explosion() -> void:
	const FRACTURE_BURST_RADIUS: float = 120.0
	var splash: int = max(4, int(round(float(max_hp) * 0.25)))
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.85, 0.6, 1.0, 1), 18)
		VfxManager.screen_shake(2.0, 0.1)
	var tree := get_tree()
	if tree == null:
		return
	for other in tree.get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		if not (other is Node2D) or bool(other.get("dead")):
			continue
		if global_position.distance_to((other as Node2D).global_position) > FRACTURE_BURST_RADIUS:
			continue
		if other.has_method("take_damage"):
			other.call("take_damage", splash, global_position)


func apply_remote_state(state: Dictionary) -> void:
	# Called on puppet clients when host broadcasts an enemy_state batch entry.
	_puppet_target_pos = Vector2(
		float(state.get("x", global_position.x)), float(state.get("y", global_position.y))
	)
	var new_hp: int = int(state.get("hp", hp))
	if new_hp != hp:
		hp = new_hp
		if health_component:
			health_component.current_hp = clampf(float(new_hp), 0.0, health_component.max_hp)
			health_component.is_dead = new_hp <= 0
		if hp_bar:
			if not hp_bar_shown and hp < max_hp:
				hp_bar.visible = true
				hp_bar_shown = true
			hp_bar.value = max(hp, 0)


func die_remote() -> void:
	# Called on puppet clients when host broadcasts an enemy_death.
	if dead:
		return
	dead = true
	if health_component:
		health_component.is_dead = true
	# Fire the death event on clients too, so death-hook ascension passives
	# (Frenzy / Bones from Death / Predator Rhythm / Static Cascade) trigger for
	# CLIENT players, not just the host. Only player passives listen to this signal
	# and they are all local-state, so emitting on the puppet can't double-count
	# waves or XP (those flow through the authoritative enemy_death message).
	if GameEvents:
		var de := ActorDeathEvent.new()
		de.actor = self
		de.actor_kind = &"enemy"
		de.position = global_position
		GameEvents.enemy_died.emit(de)
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	if hitbox:
		hitbox.set_deferred("monitoring", false)
		hitbox.set_deferred("monitorable", false)
	if hp_bar:
		hp_bar.visible = false
	if VfxManager:
		VfxManager.spawn_death_burst(global_position, enemy_type)
	# Dissolve on death (puppet variant).
	if sprite and is_inside_tree():
		var dm := ShaderMaterial.new()
		dm.shader = DISSOLVE_SHADER
		dm.set_shader_parameter("dissolve_amount", 0.0)
		var edge: Color = hue_tint
		edge.a = 1.0
		dm.set_shader_parameter("edge_color", edge)
		sprite.material = dm
		var tw := create_tween()
		(
			tw
			. tween_method(
				func(v: float):
					if dm:
						dm.set_shader_parameter("dissolve_amount", v),
				0.0,
				1.0,
				0.5
			)
			. set_trans(Tween.TRANS_QUAD)
		)
		tw.tween_callback(queue_free)
	# Safety fallback — child Timer so we can't leak.
	if is_inside_tree():
		var safety := Timer.new()
		safety.one_shot = true
		safety.wait_time = 1.2
		safety.autostart = true
		safety.timeout.connect(_safety_free)
		add_child(safety)


func _safety_free() -> void:
	if is_instance_valid(self):
		queue_free()


func _spawn_hatchlings(count: int) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var enemy_scene: PackedScene = load("res://scenes/entities/enemy.tscn") as PackedScene
	if enemy_scene == null:
		return
	# Hatchling config matches enemy_spawner.gd's "spider_hatchling".
	var cfg: Dictionary = {
		"type": "spider_hatchling",
		"max_hp": 22,
		"move_speed": 165.0,
		"attack_damage": 4,
		"attack_range": 38.0,
		"attack_cooldown": 0.8,
		"detection_range": 360.0,
		"xp_value": 3,
		"gold_min": 0,
		"gold_max": 1,
		"sprite_idle": "res://assets/sprites/characters/spider_hatchling_idle.png",
		"sprite_walk": "res://assets/sprites/characters/spider_hatchling_walk.png",
		"sprite_attack": "res://assets/sprites/characters/spider_hatchling_attack.png",
		"sprite_scale": 0.32,
		"tint": Color(1, 1, 1, 1),
		"ranged": false,
	}
	for i in count:
		var h: Node2D = enemy_scene.instantiate()
		tree.current_scene.add_child(h)
		var ang: float = randf() * TAU
		h.global_position = global_position + Vector2(cos(ang), sin(ang)) * 48.0
		if h.has_method("configure"):
			h.call("configure", cfg)
		# Multiplayer host: broadcast so clients see the hatchlings too.
		if NetManager and NetManager.is_multiplayer and NetManager.is_host:
			var ns := _find_net_sync()
			if ns and ns.has_method("register_enemy"):
				ns.call("register_enemy", h)
	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/enemy/enemy_spider_hatchling_spawn.mp3", -10.0
		)


func _die() -> void:
	if dead:
		return
	dead = true
	# Elementalist Fracture payoff: a fractured enemy detonates in a small
	# elemental burst, splashing nearby foes (host-side / solo only).
	if fractured_t > 0.0 and not is_puppet:
		_fracture_explosion()
	# Brood Mother bursts into a small swarm on death.
	if is_brood_mother:
		_spawn_hatchlings(6)
	# Disable collision so player/bolts pass through corpse.
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	if hitbox:
		hitbox.set_deferred("monitoring", false)
		hitbox.set_deferred("monitorable", false)
	if hp_bar:
		hp_bar.visible = false
	if _status_strip:
		_status_strip.visible = false

	# Big death VFX.
	if VfxManager:
		VfxManager.spawn_death_burst(global_position, enemy_type)
		VfxManager.hit_stop(0.08)
		VfxManager.screen_shake(3.0, 0.15)

	# Type-specific death SFX.
	if AudioManager:
		var death_path := "res://assets/audio/sfx/enemy/enemy_enemy_death_%s.mp3" % enemy_type
		if ResourceLoader.exists(death_path):
			AudioManager.play_sfx_path(death_path, -6.0)

	# Multiplayer host: broadcast death so all clients spawn local drops + VFX.
	# Skip local drop_loot (the death message triggers identical drops on host too).
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_enemy_death"):
			ns.call(
				"broadcast_enemy_death",
				network_id,
				global_position,
				gold_drop_min,
				gold_drop_max,
				xp_value
			)
		# Shared party XP: the host grants this kill's XP authoritatively; clients
		# grant the SAME amount when they receive enemy_death (net_sync). XP drops
		# are cosmetic in co-op (see xp_drop.gd), so this is the single source —
		# everyone ends on the same level and levels up in sync.
		if GameManager:
			GameManager.add_xp(xp_value, false)  # flat: same amount on every peer
		# Also drop locally (host is also a player) — gold + cosmetic XP visual.
		_drop_loot()
	else:
		# Solo or weird state — local drops as usual (xp_drop grants XP in solo).
		_drop_loot()

	# Notify GameManager (so spawner can track waves).
	if GameEvents:
		var death_event := ActorDeathEvent.new()
		death_event.actor = self
		death_event.actor_kind = &"enemy"
		death_event.position = global_position
		death_event.xp = xp_value
		death_event.gold = gold_drop_max
		if health_component and not health_component.history_damage_taken.is_empty():
			death_event.damage = health_component.history_damage_taken.back()
			death_event.killer = death_event.damage.attacker
		GameEvents.enemy_died.emit(death_event)
	if GameManager and GameManager.has_signal("enemy_defeated"):
		GameManager.enemy_defeated.emit()

	# Dissolve-on-death — swap to the dissolve shader and animate dissolve_amount
	# 0 → 1. Edge color uses the enemy's hue tint so the burn frontier reads
	# thematically (skeletons burn white, wraiths blue, succubi pink).
	if sprite and is_inside_tree():
		var dm := ShaderMaterial.new()
		dm.shader = DISSOLVE_SHADER
		dm.set_shader_parameter("dissolve_amount", 0.0)
		var edge: Color = hue_tint
		edge.a = 1.0
		# Brighten the edge so it reads as a burn rather than just a tint.
		edge.r = clamp(edge.r * 1.4 + 0.4, 0.0, 2.0)
		edge.g = clamp(edge.g * 1.0 + 0.2, 0.0, 2.0)
		edge.b = clamp(edge.b * 0.9 + 0.1, 0.0, 2.0)
		dm.set_shader_parameter("edge_color", edge)
		dm.set_shader_parameter("edge_width", 0.08)
		sprite.material = dm
		var tw := create_tween()
		(
			tw
			. tween_method(
				func(v: float):
					if dm:
						dm.set_shader_parameter("dissolve_amount", v),
				0.0,
				1.0,
				0.55
			)
			. set_trans(Tween.TRANS_QUAD)
		)
		tw.tween_callback(queue_free)
	else:
		queue_free()
	# Safety net — child Timer so when we're freed the timer dies too.
	if is_inside_tree():
		var safety := Timer.new()
		safety.one_shot = true
		safety.wait_time = 1.2
		safety.autostart = true
		safety.timeout.connect(_safety_free)
		add_child(safety)


func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("NetSync")


func _drop_loot() -> void:
	if reward_drop:
		reward_drop.drop_at(global_position)
