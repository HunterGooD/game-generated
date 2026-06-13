extends CharacterBody2D

# Boss entity — phase-driven, telegraph-based ARPG boss.
# Configured via boss_database.gd. Spawned by enemy_spawner on milestone waves.

signal boss_defeated(boss_id: String, reward: String)
signal boss_hp_changed(hp: int, max_hp: int)
signal boss_phase_changed(phase_index: int)

const TELEGRAPH_SCENE: PackedScene = preload("res://scenes/combat/enemy/boss_telegraph.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/enemy/boss_projectile.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/entities/enemy.tscn")

const HIT_FLASH_SHADER: Shader = preload("res://assets/shaders/hit_flash.gdshader")
const DISSOLVE_SHADER: Shader = preload("res://assets/shaders/dissolve.gdshader")
const OUTLINE_SHADER: Shader = preload("res://assets/shaders/outline.gdshader")

@export var sprite: Sprite2D
@export var hurtbox: HurtBoxComponent
@export var stats_component: StatsComponent
@export var health_component: HealthComponent
@export var status_effect_receiver: StatusEffectReceiverComponent

var boss_id: String = ""
var boss_data: Dictionary = {}
var phases: Array = []
var current_phase_idx: int = 0
var attack_idx: int = 0
var attack_t: float = 1.6
var t_alive: float = 0.0
var max_hp: int = 1000
var hp: int = 1000
var damage_unit: int = 20
var move_speed: float = 60.0
# Phase modifiers (applied on phase enter). _base_move_speed is the unscaled speed;
# _phase_attack_speed_mult divides the attack interval (higher = faster attacks).
var _base_move_speed: float = 60.0
var _phase_attack_speed_mult: float = 1.0
# LimboAI phase HSM (host-only, lazily built when use_hsm_bosses is on).
var _hsm = null
var _phase_states: Array = []
var dead: bool = false
var spawn_wave: int = 1
var owner_player_id: int = 0  # For multiplayer per-player loot.
var transition_lockout: float = 0.0
var is_puppet: bool = false
var network_id: int = -1
var _puppet_target_pos: Vector2 = Vector2.ZERO
var _runtime_base_stats: ActorStatsResource = ActorStatsResource.new()


func configure(id: String, wave: int) -> void:
	boss_id = id
	spawn_wave = wave
	boss_data = BossDatabase.get_boss(id)
	if boss_data.is_empty():
		push_warning("Unknown boss id: " + id)
		queue_free()
		return
	phases = boss_data.get("phases", [])
	_ensure_phases()
	# Stats scaled vs wave.
	var hp_per_unit_wave: int = 36
	max_hp = int(
		round(float(hp_per_unit_wave) * float(wave) * float(boss_data.get("hp_mult_vs_wave", 6.0)))
	)
	hp = max_hp
	# Damage unit = enemy damage at this wave × multiplier.
	var dmg_per_wave: int = 8 + int(float(wave) * 0.4)
	damage_unit = int(round(float(dmg_per_wave) * float(boss_data.get("damage_mult_vs_wave", 1.4))))
	move_speed = float(boss_data.get("move_speed", 60.0))
	_base_move_speed = move_speed
	_sync_component_stats(true)
	# Apply visual + emit initial signals NOW. _ready already ran with an empty
	# boss_data before configure was called by the spawner, which is exactly
	# why bosses were rendering invisible.
	_apply_visual()
	current_phase_idx = 0
	_enter_phase(0)
	boss_hp_changed.emit(hp, max_hp)
	boss_phase_changed.emit(current_phase_idx)


func _apply_visual() -> void:
	if sprite == null:
		return
	var sp_path: String = String(boss_data.get("sprite", ""))
	var src_h: float = 0.0
	if sp_path != "" and ResourceLoader.exists(sp_path):
		var tex: Texture2D = load(sp_path) as Texture2D
		if tex:
			sprite.texture = tex
			src_h = float(tex.get_size().y)
	# Normalize visual size — bosses target ~260 px tall × the catalog's
	# sprite_scale (so smaller bosses stay smaller, bigger ones stay bigger),
	# regardless of how big the source PNG is.
	var target_h: float = 260.0 * float(boss_data.get("sprite_scale", 1.0))
	var s: float = 1.0
	if src_h > 1.0:
		s = clamp(target_h / src_h, 0.08, 1.6)
	sprite.scale = Vector2(s, s)
	sprite.modulate = boss_data.get("tint", Color(1, 1, 1, 1))
	# Big feet-line shadow scaled to the boss's normalised height (~260 px tall).
	var scl: float = float(boss_data.get("sprite_scale", 1.0))
	BlobShadow.attach_at_feet(self, sprite, 150.0 * scl, 48.0 * scl)
	# Install hit-flash shader material now that the sprite has its texture.
	var mat := ShaderMaterial.new()
	mat.shader = HIT_FLASH_SHADER
	mat.set_shader_parameter("flash_amount", 0.0)
	mat.set_shader_parameter("flash_color", Color(2.0, 0.45, 0.45, 1.0))
	sprite.material = mat
	# Intro fade-in.
	sprite.modulate.a = 0.0
	var tw := sprite.create_tween()
	tw.tween_property(sprite, "modulate:a", 1.0, 0.6)


func _ready() -> void:
	collision_layer = 4 | 8
	collision_mask = 1
	add_to_group("enemy")
	add_to_group("boss")
	z_index = 70
	_puppet_target_pos = global_position
	_setup_components()
	_sync_component_stats(true)
	# Hurtbox setup — runs regardless of configure() ordering.
	if hurtbox:
		hurtbox.collision_layer = 16  # enemy hurtbox
		hurtbox.collision_mask = 0
		hurtbox.add_to_group("enemy_hit")
	# Intro burst.
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(1.0, 0.3, 0.25, 1), 24)
		VfxManager.screen_shake(8.0, 0.4)
		VfxManager.screen_flash(Color(1.0, 0.2, 0.15, 0.35), 0.4)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/enemy/enemy_boss_appear.mp3", -4.0)
	# Camera punch on boss spawn — pushes the camera back briefly for an
	# "oh shit" reveal moment.
	var tree := get_tree()
	if tree:
		for p in tree.get_nodes_in_group("player"):
			if not p.is_in_group("remote_player") and p.has_method("camera_punch"):
				p.call("camera_punch", 0.12, 0.45)
				break
	# Safety: if configure() already ran (some paths do that pre-add), make
	# sure the visual got applied.
	if not boss_data.is_empty() and sprite and sprite.texture == null:
		_apply_visual()


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
	_runtime_base_stats.damage = float(damage_unit)
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


func _physics_process(delta: float) -> void:
	if dead:
		return
	# Puppet mode — lerp to host position; no AI / attacks.
	if is_puppet:
		var w: float = clamp(10.0 * delta, 0.0, 1.0)
		global_position = global_position.lerp(_puppet_target_pos, w)
		return
	t_alive += delta
	if transition_lockout > 0.0:
		transition_lockout -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# LimboAI HSM (phases-as-states) when the flag is on; else the legacy combat step.
	# Both run the SAME boss_combat_step — the HSM adds the per-phase state structure.
	if _hsm_enabled():
		_ensure_hsm()
		if _hsm != null:
			_hsm.update(delta)
			return
	boss_combat_step(delta)


# Chase/retreat the nearest player and fire the current phase's attack cycle on the
# attack timer. Shared by the legacy path and every HSM phase state's _update.
func boss_combat_step(delta: float) -> void:
	var target := _find_nearest_player()
	if is_instance_valid(target):
		var to_target: Vector2 = (target as Node2D).global_position - global_position
		var dist: float = to_target.length()
		if dist > 220.0:
			velocity = to_target.normalized() * move_speed
		elif dist < 140.0:
			velocity = -to_target.normalized() * (move_speed * 0.5)
		else:
			velocity = Vector2.ZERO
		if sprite and abs(to_target.x) > 1.0:
			sprite.flip_h = to_target.x < 0.0
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	attack_t -= delta
	if attack_t <= 0.0:
		_fire_next_attack()


func _hsm_enabled() -> bool:
	return GameManager != null and bool(GameManager.use_hsm_bosses)


# Lazily build the phase HSM: one BossPhaseState per phase (its _enter applies the
# phase mods, its _update runs boss_combat_step). Advancement is driven by HP via
# _maybe_advance_phase → change_active_state. The state objects are the extension
# point — a phase can later use a custom LimboState subclass for unique behaviour.
func _ensure_hsm() -> void:
	if _hsm != null or phases.is_empty():
		return
	_hsm = ClassDB.instantiate("LimboHSM")
	add_child(_hsm)
	_phase_states = []
	var state_script: Script = load("res://scripts/ai/boss/boss_phase_state.gd")
	for i in phases.size():
		var st = state_script.new()
		st.phase_idx = i
		st.name = "Phase%d" % i
		_hsm.add_child(st)
		_phase_states.append(st)
	_hsm.set_initial_state(_phase_states[mini(current_phase_idx, _phase_states.size() - 1)])
	_hsm.initialize(self)
	_hsm.set_active(true)


func _find_nearest_player() -> Node:
	# Returns the nearest valid target — local player OR an allied pet — so
	# pets pull boss aggro just like they do for regular enemies.
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node = null
	var best_d: float = INF
	for grp in ["player", "pet_ally"]:
		for p in tree.get_nodes_in_group(grp):
			if not is_instance_valid(p):
				continue
			if p.is_in_group("stealthed") or p.is_in_group("airborne"):
				continue
			if p.get("dead") == true:
				continue
			var d: float = global_position.distance_to((p as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = p
	return best


func _current_phase() -> Dictionary:
	if phases.is_empty():
		return {}
	if current_phase_idx >= phases.size():
		current_phase_idx = phases.size() - 1
	return phases[current_phase_idx]


# Bosses authored with a single phase still escalate: synthesize "enrage" phases that
# progressively speed up attacks as HP drops. Multi-phase bosses keep their authored
# data untouched (their phases default attack_speed_mult/move_speed_mult to 1.0, so
# behaviour is identical). This is also the growth point — a phase dict can later carry
# move_speed_mult, extra attacks, or per-phase skills, read in _enter_phase.
func _ensure_phases() -> void:
	if phases.size() >= 2:
		return
	var base: Dictionary = phases[0] if not phases.is_empty() else {}
	var cycle: Array = base.get("attack_cycle", [])
	var interval: float = float(base.get("attack_interval", 2.0))
	var base_tint: Color = base.get("tint", Color(1, 1, 1, 1))
	phases = [
		{
			"hp_threshold": 1.0, "attack_cycle": cycle, "attack_interval": interval,
			"attack_speed_mult": 1.0, "tint": base_tint,
		},
		{
			"hp_threshold": 0.66, "attack_cycle": cycle, "attack_interval": interval,
			"attack_speed_mult": 1.3, "move_speed_mult": 1.12, "tint": Color(1.2, 0.7, 0.6, 1),
		},
		{
			"hp_threshold": 0.33, "attack_cycle": cycle, "attack_interval": interval,
			"attack_speed_mult": 1.7, "move_speed_mult": 1.25, "tint": Color(1.35, 0.45, 0.4, 1),
		},
	]


# Apply a phase's modifiers. Extension point for future per-phase content (new
# attacks, granted skills, passives) — add fields to the phase dict and read here.
func _enter_phase(idx: int) -> void:
	if idx < 0 or idx >= phases.size():
		return
	var phase: Dictionary = phases[idx]
	_phase_attack_speed_mult = float(phase.get("attack_speed_mult", 1.0))
	move_speed = _base_move_speed * float(phase.get("move_speed_mult", 1.0))


func _fire_next_attack() -> void:
	var phase := _current_phase()
	var cycle: Array = phase.get("attack_cycle", [])
	if cycle.is_empty():
		attack_t = 1.5
		return
	var atk_id: String = String(cycle[attack_idx % cycle.size()])
	attack_idx += 1
	# Phase attack-speed mult shortens the interval (later phases attack faster).
	attack_t = float(phase.get("attack_interval", 2.0)) / maxf(0.1, _phase_attack_speed_mult)
	_dispatch_attack(atk_id)


func _dispatch_attack(atk_id: String) -> void:
	match atk_id:
		BossDatabase.ATK_HELLBOLT:
			_atk_hellbolt()
		BossDatabase.ATK_CHAIN_SWEEP:
			_atk_chain_sweep()
		BossDatabase.ATK_SUMMON_PACT:
			_atk_summon_pact()
		BossDatabase.ATK_INFERNAL_CROSS:
			_atk_infernal_cross()
		BossDatabase.ATK_WALL_OF_FIRE:
			_atk_wall_of_fire()
		BossDatabase.ATK_LAVA_HUNTER:
			_atk_lava_hunter()
		BossDatabase.ATK_SHADOW_STEP:
			_atk_shadow_step()
		BossDatabase.ATK_DARK_BEAM:
			_atk_dark_beam()
		BossDatabase.ATK_HEX_MARK:
			_atk_hex_mark()
		BossDatabase.ATK_NECRO_SUMMON:
			_atk_necro_summon()
		BossDatabase.ATK_TRIPLE_BOLT:
			_atk_triple_bolt()
		BossDatabase.ATK_BONE_SPIRE:
			_atk_bone_spire()
		BossDatabase.ATK_SOUL_DRAIN:
			_atk_soul_drain()


# ─────────────────────────────────────────────────────────────────────────────
# Attacks
func _atk_hellbolt() -> void:
	var target := _find_nearest_player()
	if not is_instance_valid(target):
		return
	var dir: Vector2 = ((target as Node2D).global_position - global_position).normalized()
	_spawn_projectile(dir, damage_unit, false, Color(1.0, 0.55, 0.25, 1))


func _atk_chain_sweep() -> void:
	var target := _find_nearest_player()
	if not is_instance_valid(target):
		return
	var dir: Vector2 = (target as Node2D).global_position - global_position
	var rot: float = rad_to_deg(dir.angle())
	_spawn_telegraph(
		"cone", global_position + dir.normalized() * 100.0, 180.0, 1.0, damage_unit * 2, rot
	)


func _atk_summon_pact() -> void:
	# Spawn 2-3 small skeletons around the boss.
	var n: int = 3 if current_phase_idx > 0 else 2
	for i in n:
		var angle: float = float(i) * (TAU / float(n))
		var pos: Vector2 = global_position + Vector2(cos(angle), sin(angle)) * 90.0
		_spawn_minion(pos, "skeleton")


func _atk_infernal_cross() -> void:
	# Four cross-arm telegraphs.
	for i in 4:
		var rot: float = float(i) * 90.0
		_spawn_telegraph("line", global_position, 220.0, 1.0, damage_unit * 2, rot)


func _atk_wall_of_fire() -> void:
	# Long horizontal wall through the arena's center, passing through boss.
	_spawn_telegraph("line", global_position, 400.0, 1.4, damage_unit * 3, 0.0)
	_spawn_telegraph("line", global_position, 400.0, 1.4, damage_unit * 3, 90.0)


func _atk_lava_hunter() -> void:
	# Launch 2 homing fireballs that track the nearest player.
	for i in 2:
		var angle: float = float(i) * PI - PI * 0.5
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var proj := _spawn_projectile(dir, damage_unit, true, Color(1.0, 0.4, 0.2, 1))
		if proj and proj.has_method("set_homing_target"):
			proj.call("set_homing_target", _find_nearest_player())


func _atk_shadow_step() -> void:
	# Teleport behind the nearest player with a small AoE.
	var target := _find_nearest_player()
	if not is_instance_valid(target):
		return
	var dst: Vector2 = (
		(target as Node2D).global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
	)
	# Flash out from current pos.
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.6, 0.35, 1, 1), 12)
	global_position = dst
	if VfxManager:
		VfxManager.spawn_hit_sparks(dst, Color(0.6, 0.35, 1, 1), 12)
	# Small AoE at landing.
	_spawn_telegraph("circle", dst, 90.0, 0.5, damage_unit * 2, 0.0)


func _atk_dark_beam() -> void:
	var target := _find_nearest_player()
	if not is_instance_valid(target):
		return
	var dir: Vector2 = (target as Node2D).global_position - global_position
	var rot: float = rad_to_deg(dir.angle())
	_spawn_telegraph(
		"line", global_position + dir.normalized() * 140.0, 320.0, 1.2, damage_unit * 2, rot
	)


func _atk_hex_mark() -> void:
	var target := _find_nearest_player()
	if not is_instance_valid(target):
		return
	_spawn_telegraph("circle", (target as Node2D).global_position, 100.0, 2.0, damage_unit * 2, 0.0)


func _atk_necro_summon() -> void:
	# Lich summons 5 minions in a pentagon around her.
	for i in 5:
		var angle: float = float(i) * (TAU / 5.0)
		var pos: Vector2 = global_position + Vector2(cos(angle), sin(angle)) * 110.0
		_spawn_minion(pos, "skeleton" if randf() < 0.6 else "wraith")


func _atk_triple_bolt() -> void:
	var target := _find_nearest_player()
	if not is_instance_valid(target):
		return
	var base_dir: Vector2 = ((target as Node2D).global_position - global_position).normalized()
	for i in 3:
		var spread: float = (float(i) - 1.0) * 0.25
		var dir: Vector2 = base_dir.rotated(spread)
		_spawn_projectile(
			dir,
			damage_unit,
			false,
			Color(0.8, 0.5, 1.0, 1),
			"res://assets/sprites/effects/dark_beam.png"
		)


func _atk_bone_spire() -> void:
	# Ring of 8 spires erupting from ground around boss.
	for i in 8:
		var angle: float = float(i) * (TAU / 8.0)
		var pos: Vector2 = global_position + Vector2(cos(angle), sin(angle)) * 130.0
		_spawn_telegraph("circle", pos, 70.0, 0.7, damage_unit * 2, 0.0)


func _atk_soul_drain() -> void:
	# Big AoE telegraph around boss, then damage all players in radius.
	_spawn_telegraph("circle", global_position, 320.0, 2.2, damage_unit * 3, 0.0)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
func _spawn_telegraph(
	shape: String, pos: Vector2, radius: float, duration: float, damage: int, rotation_deg: float
) -> Node2D:
	var t: Node2D = TELEGRAPH_SCENE.instantiate()
	get_tree().current_scene.add_child(t)
	t.call("setup", shape, pos, radius, duration, damage, rotation_deg, self)
	# Co-op: replicate the telegraph so clients can see + dodge the boss AoE.
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_fx"):
			ns.call(
				"broadcast_fx",
				TELEGRAPH_SCENE.resource_path,
				pos,
				Vector2.RIGHT,
				{"shape": shape, "radius": radius, "dur": duration, "rot": rotation_deg}
			)
	return t


func _spawn_projectile(
	dir: Vector2,
	damage: int,
	homing: bool,
	tint: Color,
	tex_path: String = "res://assets/sprites/effects/hellbolt_projectile.png"
) -> Node2D:
	var p: Node2D = PROJECTILE_SCENE.instantiate()
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.call("setup", dir, damage, homing, tex_path, tint)
	# Co-op: replicate the bolt to clients as a visual (host adjudicates the hit).
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_fx"):
			ns.call(
				"broadcast_fx",
				PROJECTILE_SCENE.resource_path,
				p.global_position,
				dir,
				{"homing": homing, "tex": tex_path, "tr": tint.r, "tg": tint.g, "tb": tint.b}
			)
	return p


func _spawn_minion(pos: Vector2, type_id: String) -> void:
	var e := ENEMY_SCENE.instantiate()
	get_tree().current_scene.add_child(e)
	e.global_position = pos
	# Reuse the spawner's enemy types via dictionary.
	var cfg: Dictionary = {}
	match type_id:
		"wraith":
			cfg = {
				"type": "wraith",
				"max_hp": 22 + spawn_wave,
				"move_speed": 150.0,
				"attack_damage": damage_unit / 2,
				"attack_range": 48.0,
				"attack_cooldown": 0.9,
				"detection_range": 460.0,
				"xp_value": 6,
				"gold_min": 0,
				"gold_max": 2,
				"sprite_idle": "res://assets/sprites/characters/ruin_wraith/ruin_wraith_idle.png",
				"sprite_walk": "res://assets/sprites/characters/ruin_wraith/ruin_wraith_walk.png",
				"sprite_attack":
				"res://assets/sprites/characters/ruin_wraith/ruin_wraith_attack.png",
				"sprite_scale": 0.36,
				"tint": Color(0.7, 0.85, 1.2, 0.85),
				"ranged": false,
			}
		_:
			cfg = {
				"type": "skeleton",
				"max_hp": 30 + spawn_wave * 2,
				"move_speed": 110.0,
				"attack_damage": damage_unit / 2,
				"attack_range": 56.0,
				"attack_cooldown": 1.0,
				"detection_range": 380.0,
				"xp_value": 8,
				"gold_min": 1,
				"gold_max": 2,
				"sprite_idle":
				"res://assets/sprites/characters/skeleton_warrior/skeleton_warrior_idle.png",
				"sprite_walk":
				"res://assets/sprites/characters/skeleton_warrior/skeleton_warrior_walk.png",
				"sprite_attack":
				"res://assets/sprites/characters/skeleton_warrior/skeleton_warrior_attack.png",
				"sprite_scale": 0.34,
				"tint": Color(1, 1, 1, 1),
				"ranged": false,
			}
	if e.has_method("configure"):
		e.call("configure", cfg)


# ─────────────────────────────────────────────────────────────────────────────
# Damage / phase transitions
func _on_health_component_changed(current_hp: float, current_max_hp: float) -> void:
	hp = int(round(current_hp))
	max_hp = int(round(current_max_hp))
	boss_hp_changed.emit(hp, max_hp)


func _on_health_component_dead(_damage_payload: DamageInstance) -> void:
	_die()


func receive_damage_payload(payload: DamageInstance) -> bool:
	if payload == null or dead:
		return false

	var amount: int = int(round(payload.amount))
	var tint: Color = boss_data.get("tint", Color(1, 1, 1, 1))

	# Puppet — forward to host.
	if is_puppet:
		if NetManager:
			NetManager.send("enemy_hit", {"id": network_id, "damage": amount})
		if sprite:
			var puppet_tw := create_tween()
			puppet_tw.tween_property(sprite, "modulate", Color(2.0, 0.4, 0.4, 1), 0.04)
			puppet_tw.tween_property(sprite, "modulate", tint, 0.18)
		return false

	var previous_hp: int = hp
	if health_component:
		health_component.apply_damage(payload)
		hp = int(round(health_component.current_hp))
	else:
		hp = max(0, hp - amount)

	var applied_amount: int = max(0, previous_hp - hp)
	if applied_amount <= 0:
		return false

	if health_component == null:
		boss_hp_changed.emit(hp, max_hp)
	# Host: broadcast HP delta immediately so co-op peers' boss bar tracks the
	# fight in real time (instead of waiting up to 100ms for the next enemy_state).
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_boss_state"):
			ns.call("broadcast_boss_state", network_id, hp, max_hp, global_position)
	if VfxManager:
		VfxManager.spawn_damage_number(
			global_position + Vector2(0, -100), applied_amount, Color(1.0, 0.85, 0.4, 1)
		)
		VfxManager.spawn_hit_sparks(global_position, Color(1.0, 0.5, 0.5, 1), 4)
	# Hit-flash shader instead of the modulate tween — keeps the boss's tint
	# stable while still reading as a satisfying hit.
	if sprite and sprite.material is ShaderMaterial:
		var mat: ShaderMaterial = sprite.material
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
				0.2
			)
			. set_trans(Tween.TRANS_QUAD)
		)
	_maybe_advance_phase()
	if health_component == null and hp <= 0:
		_die()
	return true


# `from_net` — кооп-хост применяет чужой удар: локальный вампиризм не считается.
func take_damage(
	amount: int, _source_pos: Vector2 = Vector2.ZERO, from_net: bool = false
) -> void:
	if dead:
		return
	# Контур крови / Кровавый обсидиан — вампиризм с ЛОКАЛЬНО нанесённого урона.
	if not from_net and GameManager:
		GameManager.on_player_dealt_damage(amount)
	receive_damage_payload(DamageInstance.new(float(amount), null, self, [&"player_hit"], []))


func _maybe_advance_phase() -> void:
	if phases.size() <= 1:
		return
	var pct: float = float(hp) / float(max_hp)
	var next_idx: int = current_phase_idx
	for i in range(current_phase_idx + 1, phases.size()):
		var thresh: float = float(phases[i].get("hp_threshold", 1.0))
		if pct <= thresh:
			next_idx = i
	if next_idx > current_phase_idx:
		if _hsm != null and _hsm.is_active():
			# HSM drives the phase: switching the active state runs the new phase
			# state's _enter (sets idx, applies mods, emits signal, plays transition).
			_hsm.change_active_state(_phase_states[next_idx])
		else:
			current_phase_idx = next_idx
			_enter_phase(current_phase_idx)
			boss_phase_changed.emit(current_phase_idx)
			_play_phase_transition()


func _play_phase_transition() -> void:
	# Brief invuln + knockback effect + roar.
	transition_lockout = 1.0
	if sprite:
		var phase := _current_phase()
		var tint: Color = phase.get("tint", Color(1, 1, 1, 1))
		var tw := sprite.create_tween()
		tw.tween_property(sprite, "modulate", Color(2.5, 1.5, 1.2, 1), 0.2)
		tw.tween_property(sprite, "modulate", tint, 0.4)
	if VfxManager:
		VfxManager.screen_shake(10.0, 0.5)
		VfxManager.screen_flash(Color(1.0, 0.25, 0.2, 0.4), 0.45)
	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/enemy/enemy_boss_phase_transition.mp3", -4.0
		)
	# Knock players back from boss.
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		var to_p: Vector2 = ((p as Node2D).global_position - global_position).normalized()
		# Node has no has(); knock back only true physics bodies that own a
		# `velocity` field. Remote-player puppets aren't CharacterBody2D.
		if p is CharacterBody2D:
			(p as CharacterBody2D).velocity = to_p * 600.0


func _die() -> void:
	if dead:
		return
	dead = true
	_die_disable_bodies()
	_die_play_fx()
	_die_announce()
	_die_dissolve_and_free()


# Stop the hurtbox and drop the body collision so the corpse doesn't block the player.
func _die_disable_bodies() -> void:
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	# Disable the body's own shape so corpse doesn't block player movement.
	var body_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if body_shape:
		body_shape.set_deferred("disabled", true)


# Heavy death burst (shake/flash/hit-stop) and the boss death SFX.
func _die_play_fx() -> void:
	if VfxManager:
		VfxManager.spawn_death_burst(global_position, "boss")
		VfxManager.screen_shake(15.0, 0.6)
		VfxManager.screen_flash(Color(1.0, 0.85, 0.4, 0.55), 0.5)
		VfxManager.hit_stop(0.2)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/enemy/enemy_boss_death.mp3", -3.0)


# Bump the kill counter, broadcast the death to puppets, and emit boss_defeated
# so the spawner/world can hand out the reward.
func _die_announce() -> void:
	if GameManager:
		GameManager.enemies_killed += 1
	# Multiplayer host: broadcast death so puppets also fade away.
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_enemy_death"):
			ns.call("broadcast_enemy_death", network_id, global_position, 0, 0, 0)
	# Emit defeat so spawner / world can hand out reward.
	boss_defeated.emit(boss_id, String(boss_data.get("reward", "legendary")))


# Dissolve-on-death — and ACTUALLY queue_free at the end. Boss corpses
# were sticking around because this branch never freed them. A safety Timer
# guarantees the free even if the tween is interrupted.
func _die_dissolve_and_free() -> void:
	if sprite and is_inside_tree():
		var dm := ShaderMaterial.new()
		dm.shader = DISSOLVE_SHADER
		dm.set_shader_parameter("dissolve_amount", 0.0)
		dm.set_shader_parameter("edge_color", Color(1.0, 0.5, 0.25, 1.0))
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
				1.2
			)
			. set_trans(Tween.TRANS_QUAD)
		)
		tw.tween_callback(queue_free)
	else:
		queue_free()
	# Safety net — guaranteed free in 1.8s via a child Timer.
	if is_inside_tree():
		var safety := Timer.new()
		safety.one_shot = true
		safety.wait_time = 1.8
		safety.autostart = true
		safety.timeout.connect(
			func():
				if is_instance_valid(self):
					queue_free()
		)
		add_child(safety)


func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("NetSync")


func apply_remote_state(state: Dictionary) -> void:
	_puppet_target_pos = Vector2(
		float(state.get("x", global_position.x)), float(state.get("y", global_position.y))
	)
	if state.has("max_hp"):
		var nm: int = int(state.get("max_hp", max_hp))
		if nm > 0:
			max_hp = nm
	var new_hp: int = int(state.get("hp", hp))
	if new_hp != hp:
		hp = new_hp
		if health_component:
			health_component.max_hp = max(1.0, float(max_hp))
			health_component.current_hp = clampf(float(new_hp), 0.0, health_component.max_hp)
			health_component.is_dead = new_hp <= 0
		boss_hp_changed.emit(hp, max_hp)
		if hp <= 0 and not dead:
			dead = true


func die_remote() -> void:
	if dead:
		return
	dead = true
	if health_component:
		health_component.is_dead = true
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	if VfxManager:
		VfxManager.spawn_death_burst(global_position, "boss")
		VfxManager.screen_shake(10.0, 0.4)
	if sprite and is_inside_tree():
		var dm := ShaderMaterial.new()
		dm.shader = DISSOLVE_SHADER
		dm.set_shader_parameter("dissolve_amount", 0.0)
		dm.set_shader_parameter("edge_color", Color(1.0, 0.45, 0.25, 1.0))
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
				0.9
			)
			. set_trans(Tween.TRANS_QUAD)
		)
		tw.tween_callback(queue_free)
	else:
		call_deferred("queue_free")
	# Fade out then free.
	if sprite:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(sprite, "modulate:a", 0.0, 1.0)
		tw.tween_property(sprite, "scale", sprite.scale * 0.5, 1.0)
		tw.chain().tween_callback(queue_free)
	else:
		queue_free()
