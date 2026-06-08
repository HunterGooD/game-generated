class_name Player
extends CharacterBody2D

# Top-down class-aware hero. Supports Barbarian, Rogue, Mage with their own
# basic attacks, hotbar skills, and a class-specific Space dash.

const MOVE_ACCEL: float = 1800.0
const MOVE_FRICTION: float = 1600.0
const DASH_COOLDOWN: float = 1.5

@export var sprite: AnimatedSprite2D
@export var cast_origin: Marker2D
@export var footstep_timer: Timer
@export var skill_system: SkillSystem
@export var hurtbox_component: HurtBoxComponent
@export var stats_component: StatsComponent
@export var health_component: HealthComponent
@export var status_effect_receiver: StatusEffectReceiverComponent

const BOLT_SCENE: PackedScene = preload("res://scenes/combat/player/magic_bolt.tscn")
const DAGGER_SCENE: PackedScene = preload("res://scenes/combat/player/thrown_dagger.tscn")
const MELEE_SCENE: PackedScene = preload("res://scenes/combat/player/melee_swing.tscn")
const DASH_TRAIL_TEX: String = "res://assets/sprites/effects/cast_flash.png"

var move_speed: float = 220.0
var basic_attack_cd: float = 0.0
var basic_attack_interval: float = 0.32
var basic_attack_mana_cost: float = 0.0
var basic_attack_kind: String = "bolt"
# Exposed so the enemy AI (enemy_ai_component._is_valid_target /
# gather_targets_in_radius) drops this player as a target once downed/dead —
# otherwise enemies keep swinging at the local player's corpse. remote_player
# already exposes these; the local player did not.
var is_downed: bool = false
var is_dead: bool = false

# Co-op revive — hold "interact" near a downed ally to bring them back.
const REVIVE_RANGE: float = 80.0
const REVIVE_TIME: float = 3.0
var revive_progress: float = 0.0
var revive_target_id: int = -1

# Stormcaller-only — Static Charge stacks built up by chain attacks.
var static_charge: int = 0
const STATIC_CHARGE_CAP_BASE: int = 5
const STATIC_CHARGE_CAP_BOOSTED: int = 9


func get_static_charge_cap() -> int:
	if InventorySystem and InventorySystem.has_method("has_unique"):
		if InventorySystem.call("has_unique", "storm_capacitor_core"):
			return STATIC_CHARGE_CAP_BOOSTED
	return STATIC_CHARGE_CAP_BASE


func add_static_charge(n: int) -> void:
	if GameManager == null or String(GameManager.player_class) != "stormcaller":
		return
	static_charge = clamp(static_charge + n, 0, get_static_charge_cap())


func consume_static_charge() -> int:
	var v: int = static_charge
	static_charge = 0
	return v


# Druid shapeshift state.
var druid_form: String = "human"
var druid_form_t: float = 0.0
const DRUID_FORM_BASE_DURATION: float = 20.0
# Stone Armor charge tracking — when > 0, Stone Armor absorbs incoming hits.
var stone_armor_charges: int = 0
var stone_armor_grinder: bool = false

var is_attacking: bool = false
var attack_anim_t: float = 0.0
var facing_right: bool = true
var invuln_t: float = 0.0

# Buff state.
var buff_damage_mult: float = 1.0
var buff_speed_mult: float = 1.0
var buff_t: float = 0.0

# ── Generic shield pool ───────────────────────────────────────────────────────
# Absorbs incoming damage before HP. Used by Battlemage (Flameblade burn-shield),
# Frost Guard reuses stone_armor_charges instead, Chronomancer Stasis Star, etc.
var shield_hp: float = 0.0

# ── Spec-path (ascension) runtime ─────────────────────────────────────────────
# Battlemage: Arcane Flameblade window + stacking melee passive.
var flameblade_t: float = 0.0
var battlemage_stacks: int = 0
const BATTLEMAGE_STACK_MAX: int = 5
# Elementalist: orbs banked by casting elemental skills, fired by Elemental Orbit.
var elem_orbs: Array[String] = []
const ELEM_ORB_MAX: int = 3
# Chronomancer: Borrowed Second — banked by applying shields/slows; at the cap the
# next skill is free (0 mana, half cooldown).
var borrowed_stacks: int = 0
const BORROWED_STACK_MAX: int = 6
# Refreshed each frame an ally stands inside a Temporal Dome — empowers casting
# (faster cooldowns), mana regen and move speed while > 0.
var dome_t: float = 0.0

# ── Barbarian ascension runtime ───────────────────────────────────────────────
# Ally aura (Warchief Banner / War Ground): outgoing-damage mult + damage
# reduction, refreshed each frame inside the zone.
var aura_dmg_mult: float = 1.0
var aura_dr: float = 0.0
var aura_t: float = 0.0
# Berserker Blood Frenzy window: faster attacks, lifesteal, +self damage taken.
var frenzy_t: float = 0.0
# Titanbreaker Seismic Momentum stacks (gained per enemy control).
var seismic_stacks: int = 0
const SEISMIC_STACK_MAX: int = 5

# ── Rogue / Necromancer ascension runtime ─────────────────────────────────────
# Evasion chance window (Trickster Decoy / Safehouse).
var evasion_chance: float = 0.0
var evasion_t: float = 0.0
# Cheat-death: survive a lethal hit at 1 HP. `funeral_t` is the Necro Second Funeral
# window (free while active); `dirty_escape_cd` gates the Trickster passive (90s).
var funeral_t: float = 0.0
var dirty_escape_cd: float = 0.0
# Assassin Backstab Window: brief window (after a dash/vanish) where attacks crit harder.
var backstab_t: float = 0.0

# Stealth state (Smoke Bomb).
var stealth_t: float = 0.0
var stealth_crit_charge: bool = false

# Dash state.
var dash_cd: float = 0.0
var dash_kind: String = "mage"
var is_dashing: bool = false
var _frostwalker_t: float = 0.0
var _runtime_base_stats: ActorStatsResource = ActorStatsResource.new()


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	_setup_components()
	_apply_class()
	if footstep_timer == null:
		var t := Timer.new()
		t.name = "FootstepTimer"
		t.wait_time = 0.32
		t.autostart = false
		t.timeout.connect(_on_footstep)
		add_child(t)
		footstep_timer = t
	var hurtbox: Area2D = get_node_or_null("Hurtbox")
	if hurtbox:
		hurtbox.collision_layer = 2
		hurtbox.collision_mask = 0
	if GameManager:
		GameManager.class_selected.connect(_on_class_selected)
		GameManager.player_stats_changed.connect(_on_player_stats_changed)
		GameManager.player_died.connect(_on_game_manager_player_died)
		GameManager.player_downed_changed.connect(_on_downed_changed)
		GameManager.player_revived.connect(_on_revived)
		GameManager.spec_path_chosen.connect(_on_spec_path_chosen)
		_on_player_stats_changed()
	# Berserker Blood Frenzy extends on kills near the player.
	if GameEvents:
		GameEvents.enemy_died.connect(_on_enemy_died_frenzy)


func _setup_components() -> void:
	if stats_component:
		stats_component.base_stats = _runtime_base_stats
	if health_component:
		health_component.main_stats = stats_component
	if status_effect_receiver:
		status_effect_receiver.main_stats = stats_component
		status_effect_receiver.health_component = health_component
	if hurtbox_component:
		hurtbox_component.health_component = health_component
		hurtbox_component.status_effect_receiver = status_effect_receiver
		hurtbox_component.damage_receiver = self


func _on_class_selected(_class_id: String) -> void:
	_apply_class()
	_sync_component_health_from_game_manager()


func _on_player_stats_changed() -> void:
	_sync_component_stats_from_game_manager()
	_sync_component_health_from_game_manager()


func _on_game_manager_player_died() -> void:
	is_dead = true
	if GameEvents == null:
		return
	var event := ActorDeathEvent.new()
	event.actor = self
	event.actor_kind = &"player"
	event.position = global_position
	GameEvents.player_died.emit(event)
	# Tell the party our puppet should show the dead pose.
	if NetManager and NetManager.is_multiplayer:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_player_dead"):
			ns.call("broadcast_player_dead")


# Downed / revived local feedback. `player_downed_changed(false)` also fires on
# full death, but the game-over screen takes over there so the reset is benign.
func _on_downed_changed(downed: bool) -> void:
	is_downed = downed
	if sprite:
		if downed:
			sprite.modulate = Color(0.55, 0.55, 0.65, 0.92)
			sprite.rotation = deg_to_rad(80.0)  # keel over
		else:
			sprite.modulate = Color(1, 1, 1, 1)
			sprite.rotation = 0.0
	# Tell the party our puppet should show the downed pose.
	if downed and NetManager and NetManager.is_multiplayer:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_player_downed"):
			ns.call("broadcast_player_downed")


func _on_spec_path_chosen(path_id: String) -> void:
	# Bind the chosen path's R ability to our SkillSystem (empty ability = stat-only
	# path; the cast just no-ops).
	if skill_system == null or GameManager == null:
		return
	var p: Dictionary = SpecPaths.find(String(GameManager.player_class), path_id)
	var ability: String = String(p.get("ability", ""))
	if ability != "" and skill_system.has_method("set_ascension"):
		skill_system.call("set_ascension", ability)
	# Path may replace the basic attack (Battlemage → melee fire blade) and swap
	# skill slots (transforms). Re-derive the basic attack, and apply any slot
	# transforms the path defines.
	_refresh_basic_attack()
	var transforms: Dictionary = p.get("transforms", {})
	for slot_key in transforms:
		if skill_system.has_method("apply_transform"):
			skill_system.call("apply_transform", int(slot_key), String(transforms[slot_key]))


func _on_revived() -> void:
	is_downed = false
	is_dead = false
	if sprite:
		sprite.modulate = Color(1, 1, 1, 1)
		sprite.rotation = 0.0
	invuln_t = 1.0  # brief grace window after getting back up
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.5, 1.0, 0.6, 1), 14)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_level_up.mp3", -8.0)
	# Sync our restored HP to the party so our puppet stands back up.
	if NetManager and NetManager.is_multiplayer:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_player_revived"):
			ns.call("broadcast_player_revived", int(GameManager.player_hp) if GameManager else 0)


# Hold "interact" near the nearest downed teammate puppet for REVIVE_TIME to
# send a revive request. The downed player is the authority that gets back up.
func _update_revive(delta: float) -> void:
	var tree := get_tree()
	if tree == null:
		revive_progress = 0.0
		revive_target_id = -1
		return
	var best: Node2D = null
	var best_d: float = REVIVE_RANGE
	for rp in tree.get_nodes_in_group("remote_player"):
		if not is_instance_valid(rp):
			continue
		if not bool(rp.get("is_downed")):
			continue
		var d: float = global_position.distance_to((rp as Node2D).global_position)
		if d <= best_d:
			best_d = d
			best = rp as Node2D
	if best == null or not Input.is_action_pressed("interact"):
		revive_progress = 0.0
		revive_target_id = -1
		return
	var target_id: int = int(best.get("player_id"))
	if target_id != revive_target_id:
		revive_target_id = target_id
		revive_progress = 0.0
	var prev: float = revive_progress
	revive_progress += delta
	# Tick green sparks on the ally roughly every 0.4 s of channel.
	if VfxManager and int(revive_progress / 0.4) != int(prev / 0.4):
		VfxManager.spawn_hit_sparks(best.global_position, Color(0.5, 1.0, 0.6, 1), 4)
	if revive_progress >= REVIVE_TIME:
		revive_progress = 0.0
		revive_target_id = -1
		var ns := _find_net_sync()
		if ns and ns.has_method("send_revive"):
			ns.call("send_revive", target_id)


func _apply_class() -> void:
	if GameManager == null:
		return
	var data: Dictionary = GameManager.get_class_data()
	move_speed = GameManager.player_move_speed
	dash_kind = String(data.get("dash_kind", "mage"))
	_refresh_basic_attack()
	_sync_component_stats_from_game_manager()
	_apply_sprite_frames(data)


# Resolve the effective basic-attack kind: a chosen spec path can override the
# class default (e.g. Battlemage → "melee"). Re-derived from the path each call so
# the override survives later stats refreshes.
func _refresh_basic_attack() -> void:
	if GameManager == null:
		return
	var kind: String = String(GameManager.get_class_data().get("basic_attack", "bolt"))
	if String(GameManager.player_spec_path) != "":
		var p: Dictionary = SpecPaths.find(
			String(GameManager.player_class), String(GameManager.player_spec_path)
		)
		var ov: String = String(p.get("basic_attack", ""))
		if ov != "":
			kind = ov
	_configure_basic_attack(kind)


func _configure_basic_attack(kind: String) -> void:
	basic_attack_kind = kind
	match kind:
		"melee", "claw":
			# Melee / druid human claw / Battlemage fire blade — short range.
			basic_attack_interval = 0.45 if kind == "melee" else 0.40
			basic_attack_mana_cost = 0.0
		"dagger":
			basic_attack_interval = 0.40
			basic_attack_mana_cost = 0.0
		_:
			# Ranged bolt-kind basics (mage, necromancer, hexen, stormcaller).
			basic_attack_interval = 0.55
			basic_attack_mana_cost = 4.0


func _sync_component_stats_from_game_manager() -> void:
	if stats_component == null or GameManager == null:
		return

	var changed := false
	var next_max_health := float(GameManager.get_effective_max_hp())
	var next_move_speed := float(GameManager.get_effective_move_speed())
	var next_armor := float(GameManager.get_effective_armor())
	var next_damage := float(GameManager.get_effective_damage())
	var next_max_mana := float(GameManager.get_effective_max_mana())
	var next_mana_regen := 8.0
	var next_attack_speed := 1.0
	var next_crit_chance := float(GameManager.player_crit_chance)
	var next_crit_damage := float(GameManager.player_crit_damage)

	if not is_equal_approx(_runtime_base_stats.max_health, next_max_health):
		_runtime_base_stats.max_health = next_max_health
		changed = true
	if not is_equal_approx(_runtime_base_stats.move_speed, next_move_speed):
		_runtime_base_stats.move_speed = next_move_speed
		changed = true
	if not is_equal_approx(_runtime_base_stats.armor, next_armor):
		_runtime_base_stats.armor = next_armor
		changed = true
	if not is_equal_approx(_runtime_base_stats.damage, next_damage):
		_runtime_base_stats.damage = next_damage
		changed = true
	if not is_equal_approx(_runtime_base_stats.max_mana, next_max_mana):
		_runtime_base_stats.max_mana = next_max_mana
		changed = true
	if not is_equal_approx(_runtime_base_stats.mana_regen, next_mana_regen):
		_runtime_base_stats.mana_regen = next_mana_regen
		changed = true
	if not is_equal_approx(_runtime_base_stats.attack_speed, next_attack_speed):
		_runtime_base_stats.attack_speed = next_attack_speed
		changed = true
	if not is_equal_approx(_runtime_base_stats.crit_chance, next_crit_chance):
		_runtime_base_stats.crit_chance = next_crit_chance
		changed = true
	if not is_equal_approx(_runtime_base_stats.crit_damage, next_crit_damage):
		_runtime_base_stats.crit_damage = next_crit_damage
		changed = true

	if changed:
		stats_component.stats_changed.emit()


func _sync_component_health_from_game_manager() -> void:
	if health_component == null or GameManager == null:
		return

	health_component.max_hp = max(1.0, float(GameManager.get_effective_max_hp()))
	health_component.current_hp = clampf(float(GameManager.player_hp), 0.0, health_component.max_hp)
	health_component.is_dead = GameManager.player_hp <= 0
	health_component.hp_change.emit(health_component.current_hp, health_component.max_hp)


func _apply_sprite_frames(data: Dictionary) -> void:
	if sprite == null:
		return
	var frames := SpriteFrames.new()
	var sample_tex: Texture2D = null
	for state_key in ["idle", "walk", "attack"]:
		var path: String = String(data.get("sprite_" + state_key, ""))
		if path != "" and ResourceLoader.exists(path):
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
	_normalize_player_sprite_scale(sample_tex)


# Keeps every class / form at the same on-screen height regardless of how big
# the source PNG is. Legacy classes were 256-px sources at scene-scale 0.32 ≈
# 82 px tall; new classes (druid) ship at 768-px sources, so without this they
# render 3× bigger than the others.
func _normalize_player_sprite_scale(sample_tex: Texture2D) -> void:
	if sprite == null or sample_tex == null:
		return
	var src_h: float = float(sample_tex.get_size().y)
	if src_h <= 1.0:
		return
	var target_h: float = 85.0
	var s: float = clamp(target_h / src_h, 0.08, 0.5)
	sprite.scale = Vector2(s, s)


func _physics_process(delta: float) -> void:
	if GameManager:
		move_speed = GameManager.get_effective_move_speed()
	# Temporal Dome benefit: +20% move speed and faster cooldown regen while the
	# dome keeps refreshing dome_t (see skill_temporal_dome._process).
	if dome_t > 0.0:
		dome_t -= delta
		move_speed *= 1.2
		if skill_system and skill_system.has_method("reduce_all_cooldowns"):
			skill_system.call("reduce_all_cooldowns", delta * 0.35)
	# Druid form timer — auto-revert to human when expired.
	if druid_form != "human":
		druid_form_t -= delta
		if druid_form_t <= 0.0:
			set_druid_form("human", 0.0)
	if invuln_t > 0.0:
		invuln_t -= delta
	if buff_t > 0.0:
		buff_t -= delta
		if buff_t <= 0.0:
			_remove_buff()
	if flameblade_t > 0.0:
		flameblade_t -= delta
	if aura_t > 0.0:
		aura_t -= delta
		if aura_t <= 0.0:
			aura_dmg_mult = 1.0
			aura_dr = 0.0
	if frenzy_t > 0.0:
		frenzy_t -= delta
		move_speed *= 1.25  # Blood Frenzy haste
	if evasion_t > 0.0:
		evasion_t -= delta
		if evasion_t <= 0.0:
			evasion_chance = 0.0
	if funeral_t > 0.0:
		funeral_t -= delta
	if dirty_escape_cd > 0.0:
		dirty_escape_cd -= delta
	if backstab_t > 0.0:
		backstab_t -= delta
	if stealth_t > 0.0:
		stealth_t -= delta
		if stealth_t <= 0.0:
			_remove_stealth()
	dash_cd = max(dash_cd - delta, 0.0)

	# Downed (co-op bleed-out): no movement, dash, attacks, or skills until a
	# teammate revives. Just decelerate to a stop and wait.
	if GameManager and GameManager.player_downed:
		velocity = velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
		move_and_slide()
		return

	# Co-op: hold "interact" near a downed ally to revive them.
	if NetManager and NetManager.is_multiplayer:
		_update_revive(delta)

	if not is_dashing:
		var input_vec := Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
		)
		if input_vec.length_squared() > 0.01:
			input_vec = input_vec.normalized()
			velocity = velocity.move_toward(
				input_vec * move_speed * buff_speed_mult, MOVE_ACCEL * delta
			)
			if footstep_timer and footstep_timer.is_stopped():
				footstep_timer.start()
		else:
			velocity = velocity.move_toward(Vector2.ZERO, MOVE_FRICTION * delta)
			if footstep_timer and not footstep_timer.is_stopped() and velocity.length() < 20.0:
				footstep_timer.stop()

	var mouse_pos := get_global_mouse_position()
	facing_right = mouse_pos.x >= global_position.x
	if sprite:
		sprite.flip_h = not facing_right

	move_and_slide()

	# Dash on space.
	if Input.is_action_just_pressed("dash") and dash_cd <= 0.0 and not is_dashing:
		_perform_dash()

	# Basic attack.
	basic_attack_cd = max(basic_attack_cd - delta, 0.0)
	if not is_dashing and Input.is_action_pressed("cast_attack") and basic_attack_cd <= 0.0:
		if (
			basic_attack_mana_cost <= 0.0
			or (GameManager and GameManager.spend_mana(basic_attack_mana_cost))
		):
			_perform_basic_attack()
			# Blood Frenzy: +35% attack speed → shorter interval.
			basic_attack_cd = basic_attack_interval / (1.35 if frenzy_t > 0.0 else 1.0)

	# Skills.
	if not is_dashing:
		if Input.is_action_just_pressed("skill_1"):
			skill_system.try_cast(0, self, get_global_mouse_position())
		if Input.is_action_just_pressed("skill_2"):
			skill_system.try_cast(1, self, get_global_mouse_position())
		if Input.is_action_just_pressed("skill_3"):
			skill_system.try_cast(2, self, get_global_mouse_position())
		if Input.is_action_just_pressed("skill_4"):
			skill_system.try_cast(3, self, get_global_mouse_position())
		# Ascension ability (R) — granted by the chosen spec path at level 7.
		if Input.is_action_just_pressed("skill_ascension"):
			skill_system.cast_ascension(self, get_global_mouse_position())
		# DEBUG/TEST: P grants one level instantly to speed up testing.
		if Input.is_action_just_pressed("debug_level_up") and GameManager:
			GameManager.debug_grant_level()
		# Druid ultimate (Q) — Eagle Form. Only meaningful for druid since
		# only their skill_ids array reaches length 5.
		if (
			Input.is_action_just_pressed("ultimate")
			and skill_system
			and skill_system.skill_ids.size() > 4
		):
			skill_system.try_cast(4, self, get_global_mouse_position())

	if GameManager:
		GameManager.regen_mana(8.0 * delta * (1.05 if dome_t > 0.0 else 1.0))

	# Frostwalker unique — drop a small slow patch behind the player.
	if velocity.length() > 30.0 and InventorySystem and InventorySystem.has_unique("frostwalker"):
		_frostwalker_t -= delta
		if _frostwalker_t <= 0.0:
			_frostwalker_t = 0.45
			_drop_frostwalker_patch()

	_update_animation()

	if is_attacking:
		attack_anim_t -= delta
		if attack_anim_t <= 0.0:
			is_attacking = false


func _update_animation() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var target: String
	if is_attacking and sprite.sprite_frames.has_animation("attack"):
		target = "attack"
	elif velocity.length() > 30.0 and sprite.sprite_frames.has_animation("walk"):
		target = "walk"
	else:
		target = "idle" if sprite.sprite_frames.has_animation("idle") else ""
	if target != "" and sprite.animation != target:
		sprite.play(target)


# ─────────────────────────────────────────────────────────────────────────────
# DASH
func _perform_dash() -> void:
	dash_cd = DASH_COOLDOWN
	var mouse_pos: Vector2 = get_global_mouse_position()
	var dir: Vector2 = mouse_pos - global_position
	if dir.length_squared() < 0.001:
		dir = (Vector2.RIGHT if facing_right else Vector2.LEFT)
	dir = dir.normalized()

	match dash_kind:
		"barbarian":
			_do_barbarian_dash(dir)
		"rogue":
			_do_rogue_dash(dir)
		_:
			_do_mage_dash(dir)

	# Phantom Soles unique — slash 60% off smoke bomb's remaining cooldown.
	if InventorySystem and InventorySystem.has_unique("phantom_soles"):
		if skill_system:
			# Smoke Bomb is slot 1 for rogue.
			var idx: int = 1
			if (
				skill_system.skill_ids.size() > idx
				and String(skill_system.skill_ids[idx]) == "smoke_bomb"
			):
				skill_system.cooldowns[idx] = max(0.0, skill_system.cooldowns[idx] * 0.4)
				skill_system.cooldown_started.emit(idx, skill_system.cooldowns[idx])


func _do_barbarian_dash(dir: Vector2) -> void:
	# Medium dash with damage along path.
	var dist: float = 180.0
	var dur: float = 0.18
	is_dashing = true
	invuln_t = max(invuln_t, dur + 0.05)
	var start: Vector2 = global_position
	var end: Vector2 = start + dir * dist

	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/player/player_spell_dash_short.mp3", -8.0
		)

	# Spawn a trailing damage area along the path.
	_spawn_dash_damage(start, end, 12)

	# Move via tween.
	var tw := create_tween()
	tw.tween_property(self, "global_position", end, dur).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_callback(_end_dash)
	_spawn_dash_trail(Color(1.0, 0.6, 0.4, 1))


func _do_rogue_dash(dir: Vector2) -> void:
	# Long fast dash, no damage, brief invuln + shadow trail.
	var dist: float = 320.0
	var dur: float = 0.22
	is_dashing = true
	invuln_t = max(invuln_t, dur + 0.1)
	var end: Vector2 = global_position + dir * dist

	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/player/player_spell_dash_short.mp3", -8.0
		)

	_spawn_dash_trail(Color(0.8, 0.4, 0.7, 1), 5)
	var tw := create_tween()
	tw.tween_property(self, "global_position", end, dur).set_trans(Tween.TRANS_QUART).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_callback(_end_dash)


func _do_mage_dash(dir: Vector2) -> void:
	# Short instant teleport with smoke puffs at both ends.
	var dist: float = 150.0
	var start: Vector2 = global_position
	var end: Vector2 = start + dir * dist
	is_dashing = true
	invuln_t = max(invuln_t, 0.15)

	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/player/player_spell_dash_teleport.mp3", -8.0
		)

	if VfxManager:
		VfxManager.spawn_hit_sparks(start, Color(0.85, 0.5, 1, 1), 8)
		VfxManager.spawn_hit_sparks(end, Color(0.85, 0.5, 1, 1), 8)
	global_position = end
	var t := get_tree().create_timer(0.12)
	t.timeout.connect(_end_dash)


func _end_dash() -> void:
	is_dashing = false


func _spawn_dash_trail(color: Color, count: int = 3) -> void:
	# Leave behind fading sprite ghosts at current position.
	if sprite == null or sprite.sprite_frames == null:
		return
	var current_anim: String = sprite.animation
	var frame_tex: Texture2D = null
	if current_anim != "" and sprite.sprite_frames.has_animation(current_anim):
		frame_tex = sprite.sprite_frames.get_frame_texture(current_anim, 0)
	if frame_tex == null:
		return
	for i in count:
		var delay: float = float(i) * 0.05
		var t := get_tree().create_timer(delay)
		t.timeout.connect(_spawn_one_trail_ghost.bind(frame_tex, color))


func _spawn_one_trail_ghost(tex: Texture2D, color: Color) -> void:
	if not is_inside_tree():
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.global_position = global_position + Vector2(0, -10)
	s.scale = (sprite.scale if sprite else Vector2(0.32, 0.32))
	s.modulate = Color(color.r, color.g, color.b, 0.6)
	s.flip_h = sprite.flip_h if sprite else false
	s.z_index = 90
	get_tree().current_scene.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.35)
	tw.tween_callback(s.queue_free)


func _spawn_dash_damage(start: Vector2, end: Vector2, damage: int) -> void:
	# Sample 5 points along path and damage nearby enemies once each.
	var hit_set: Dictionary = {}
	var tree := get_tree()
	if tree == null:
		return
	var steps: int = 6
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var p: Vector2 = start.lerp(end, t)
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e):
				continue
			var id: int = e.get_instance_id()
			if hit_set.has(id):
				continue
			if p.distance_to((e as Node2D).global_position) < 60.0:
				hit_set[id] = true
				if e.has_method("take_damage"):
					var final_dmg: int = int(
						round(
							(
								float(GameManager.player_damage if GameManager else damage)
								* 0.8
								* buff_damage_mult
							)
						)
					)
					e.take_damage(final_dmg, p)
				if VfxManager:
					VfxManager.spawn_hit_sparks(
						(e as Node2D).global_position, Color(1, 0.5, 0.3, 1), 5
					)


# ─────────────────────────────────────────────────────────────────────────────
# BUFFS
func apply_buff(duration: float, dmg_mult: float, spd_mult: float) -> void:
	buff_t = max(buff_t, duration)
	buff_damage_mult = max(buff_damage_mult, dmg_mult)
	buff_speed_mult = max(buff_speed_mult, spd_mult)
	# Tint sprite red briefly.
	if sprite:
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color(1.6, 0.7, 0.6, 1), 0.15)
		tw.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.25)


func _remove_buff() -> void:
	buff_damage_mult = 1.0
	buff_speed_mult = 1.0


func get_buff_damage_mult() -> float:
	# The single outgoing-damage chokepoint for skills (skill_system) and basics:
	# active buff × ally aura × spec-path passives (Berserker Pain Engine).
	return buff_damage_mult * aura_dmg_mult * _spec_outgoing_mult()


# Spec-path outgoing-damage multipliers that scale ALL damage (not just melee).
func _spec_outgoing_mult() -> float:
	var m: float = 1.0
	if GameManager == null:
		return m
	match String(GameManager.player_spec_path):
		"berserker":
			m *= _pain_engine_mult()
		"assassin":
			if backstab_t > 0.0:
				m *= 1.4  # Backstab Window
	return m


# Open the Assassin Backstab Window (after a dash / Vanish).
func start_backstab(duration: float) -> void:
	backstab_t = max(backstab_t, duration)


# Berserker Pain Engine: the lower the HP, the harder the hits.
func _pain_engine_mult() -> float:
	if GameManager == null:
		return 1.0
	var frac: float = float(GameManager.player_hp) / float(maxi(1, GameManager.player_max_hp))
	if frac < 0.20:
		return 1.45
	if frac < 0.40:
		return 1.25
	if frac < 0.70:
		return 1.10
	return 1.0


# ── Barbarian ascension API ───────────────────────────────────────────────────
func apply_aura(dmg_mult: float, dr: float, duration: float) -> void:
	aura_dmg_mult = max(aura_dmg_mult, dmg_mult)
	aura_dr = max(aura_dr, dr)
	aura_t = max(aura_t, duration)


func start_frenzy(duration: float) -> void:
	frenzy_t = max(frenzy_t, duration)


func is_frenzied() -> bool:
	return frenzy_t > 0.0


func extend_frenzy(amount: float) -> void:
	if frenzy_t > 0.0:
		frenzy_t += amount


func _on_enemy_died_frenzy(event) -> void:
	if frenzy_t <= 0.0:
		return
	# Only nearby kills extend the frenzy (keeps co-op kills across the map out).
	var actor = event.get("actor") if event else null
	if actor is Node2D and global_position.distance_to((actor as Node2D).global_position) > 360.0:
		return
	extend_frenzy(0.5)


func add_seismic_stack() -> void:
	if GameManager == null or String(GameManager.player_spec_path) != "titanbreaker":
		return
	seismic_stacks = mini(seismic_stacks + 1, SEISMIC_STACK_MAX)


# Returns the Earthquake/Fault-Zone size bonus from Seismic Momentum, consuming
# the stacks when the cap is reached (1.0 = no bonus, 1.3 = +30%).
func consume_seismic_quake_bonus() -> float:
	if seismic_stacks >= SEISMIC_STACK_MAX:
		seismic_stacks = 0
		return 1.3
	return 1.0


# Heal that honors Pain Engine's reduced healing below 20% HP. Used by lifesteal.
func heal_amount(amount: int) -> void:
	if GameManager == null or amount <= 0:
		return
	var a: int = amount
	if String(GameManager.player_spec_path) == "berserker":
		var frac: float = float(GameManager.player_hp) / float(maxi(1, GameManager.player_max_hp))
		if frac < 0.20:
			a = int(round(float(a) * 0.7))
	GameManager.heal_player(a)


# ─────────────────────────────────────────────────────────────────────────────
# SHIELD POOL
func add_shield(amount: float, cap: float = -1.0) -> void:
	if amount <= 0.0:
		return
	shield_hp += amount
	if cap >= 0.0:
		shield_hp = min(shield_hp, cap)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.6, 0.85, 1.0, 1), 5)


# ─────────────────────────────────────────────────────────────────────────────
# ASCENSION RUNTIME — fired by SkillSystem after a successful cast.
func on_skill_cast(skill_id: String, _behavior: String) -> void:
	if GameManager == null:
		return
	match String(GameManager.player_spec_path):
		"battlemage":
			add_battlemage_stack()
		"elementalist":
			add_elem_orb(_skill_element(skill_id))


func _skill_element(skill_id: String) -> String:
	var s := skill_id.to_lower()
	if s.contains("ice") or s.contains("frost"):
		return "frost"
	if s.contains("chain") or s.contains("lightning") or s.contains("storm"):
		return "storm"
	return "fire"  # fire_wall / meteor / flame_cleave / falling_brand default


# ── Battlemage ────────────────────────────────────────────────────────────────
func start_flameblade(duration: float) -> void:
	flameblade_t = max(flameblade_t, duration)


func is_flameblade_active() -> bool:
	return flameblade_t > 0.0


func add_battlemage_stack() -> void:
	battlemage_stacks = mini(battlemage_stacks + 1, BATTLEMAGE_STACK_MAX)


# +3% melee damage per stack (basic attack + melee-arc skills).
func get_battlemage_melee_mult() -> float:
	return 1.0 + 0.03 * float(battlemage_stacks)


# +4% incoming-damage reduction per stack (the "armor" half of the passive).
func get_battlemage_dr() -> float:
	return 0.04 * float(battlemage_stacks)


# The fire-blade: while Flameblade is active, a melee basic attack ignites foes in
# front and, for any that were already burning, grants a stacking shield (the
# "+2% max HP per hit, cap 30%" design — robust without cross-node hit hooks).
func _flameblade_melee_proc(dir: Vector2) -> void:
	if not is_flameblade_active() or GameManager == null:
		return
	var tree := get_tree()
	if tree == null:
		return
	var front: Vector2 = global_position + dir * 60.0
	var max_hp: float = float(GameManager.player_max_hp)
	var shield_cap: float = max_hp * 0.30
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D) or bool(e.get("dead")):
			continue
		if front.distance_to((e as Node2D).global_position) > 130.0:
			continue
		var was_burning: bool = e.has_method("is_burning") and bool(e.call("is_burning"))
		if e.has_method("apply_burn"):
			e.call("apply_burn", 4.0, float(GameManager.get_effective_damage()) * 0.4)
		if was_burning:
			add_shield(max_hp * 0.02, shield_cap)


# ── Elementalist ──────────────────────────────────────────────────────────────
func add_elem_orb(element: String) -> void:
	elem_orbs.append(element)
	while elem_orbs.size() > ELEM_ORB_MAX:
		elem_orbs.pop_front()


func consume_elem_orbs() -> Array[String]:
	var orbs: Array[String] = elem_orbs.duplicate()
	elem_orbs.clear()
	return orbs


# ── Chronomancer ──────────────────────────────────────────────────────────────
# Banked whenever a spec path controls the battlefield (Chronomancer shields/slows,
# Titanbreaker enemy control). Each path reads its own stack pool.
func notify_control_applied() -> void:
	if GameManager == null:
		return
	match String(GameManager.player_spec_path):
		"chronomancer":
			borrowed_stacks = mini(borrowed_stacks + 1, BORROWED_STACK_MAX)
		"titanbreaker":
			add_seismic_stack()


# SkillSystem asks this before charging a slot's mana/cooldown. At the cap the
# next skill is free and half-cooldown; returns the cooldown multiplier to apply.
func consume_borrowed_second() -> float:
	if borrowed_stacks >= BORROWED_STACK_MAX:
		borrowed_stacks = 0
		return 0.5
	return 1.0


# Refresh the Temporal Dome benefit window (called each frame the player is inside
# the dome zone).
func enter_dome(duration: float) -> void:
	dome_t = max(dome_t, duration)


# Warchief Hold the Line: when taking damage with an ally nearby, soak 20% of the
# hit (turned into mitigation) and grant that ally 5% damage reduction for 3s.
func _hold_the_line(amount: int) -> int:
	if GameManager == null or String(GameManager.player_spec_path) != "warchief":
		return amount
	var tree := get_tree()
	if tree == null:
		return amount
	var helped: bool = false
	for ally in tree.get_nodes_in_group("remote_player"):
		if not is_instance_valid(ally) or not (ally is Node2D):
			continue
		if global_position.distance_to((ally as Node2D).global_position) > 280.0:
			continue
		if ally.has_method("apply_aura"):
			ally.call("apply_aura", 1.0, 0.05, 3.0)
		helped = true
	if helped:
		return int(round(float(amount) * 0.8))
	return amount


# ── Rogue / Necromancer ascension API ─────────────────────────────────────────
func apply_evasion(chance: float, duration: float) -> void:
	evasion_chance = max(evasion_chance, chance)
	evasion_t = max(evasion_t, duration)


# Necromancer Second Funeral: mark this player so a lethal hit is survived at 1 HP
# for the next `duration` seconds.
func grant_funeral(duration: float) -> void:
	funeral_t = max(funeral_t, duration)


# Trickster Dirty Escape passive: arm a one-shot cheat-death on an 90s shared CD.
# Returns true if it fired (and started the cooldown).
func try_dirty_escape() -> bool:
	if GameManager == null or String(GameManager.player_spec_path) != "trickster":
		return false
	if dirty_escape_cd > 0.0:
		return false
	dirty_escape_cd = 90.0
	return true


# Called from receive_damage_payload when a hit would be lethal. Returns true if a
# cheat-death effect saves the player (sets them to 1 HP + brief invuln + smoke).
func _try_cheat_death() -> bool:
	var saved: bool = false
	if funeral_t > 0.0:
		saved = true
	elif try_dirty_escape():
		saved = true
		# Drop a smoke bomb on escape (Trickster flavour).
		apply_stealth(1.0)
	if not saved:
		return false
	if GameManager:
		GameManager.player_hp = 1
		if health_component:
			health_component.current_hp = 1.0
			health_component.is_dead = false
		GameManager.player_stats_changed.emit()
	invuln_t = 1.0
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.8, 0.9, 1.0, 1), 16)
		VfxManager.screen_flash(Color(0.6, 0.7, 1.0, 0.2), 0.2)
	return true


# ─────────────────────────────────────────────────────────────────────────────
# STEALTH
func apply_stealth(duration: float) -> void:
	stealth_t = max(stealth_t, duration)
	stealth_crit_charge = true
	if sprite:
		sprite.modulate = Color(1, 1, 1, 0.45)
	add_to_group("stealthed")


func _remove_stealth() -> void:
	stealth_crit_charge = false
	if sprite:
		sprite.modulate = Color(1, 1, 1, 1)
	if is_in_group("stealthed"):
		remove_from_group("stealthed")


# ─────────────────────────────────────────────────────────────────────────────
# BASIC ATTACK
func _perform_basic_attack() -> void:
	is_attacking = true
	attack_anim_t = 0.22
	var origin: Vector2 = cast_origin.global_position if cast_origin else global_position
	var dir: Vector2 = get_global_mouse_position() - origin
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var base_dmg: int = GameManager.get_effective_damage() if GameManager else 14
	# get_buff_damage_mult folds in active buff × ally aura × Pain Engine.
	var dmg: int = int(round(float(base_dmg) * get_buff_damage_mult()))
	# Battlemage stacks empower melee basics; Flameblade ignites foes in front.
	if basic_attack_kind == "melee" or basic_attack_kind == "claw":
		dmg = int(round(float(dmg) * get_battlemage_melee_mult()))
		_flameblade_melee_proc(dir)
	# Blood Frenzy: each basic attack leeches 2% of missing HP.
	if frenzy_t > 0.0 and GameManager:
		var missing: int = GameManager.player_max_hp - GameManager.player_hp
		if missing > 0:
			heal_amount(maxi(1, int(round(float(missing) * 0.02))))

	# Stealth burst: next attack auto-crits.
	if stealth_crit_charge:
		dmg = int(round(float(dmg) * 3.0))
		stealth_crit_charge = false
		_remove_stealth()
		# Whisper-Edge unique: stealth attack also blows up in a wide arc.
		_maybe_whisper_edge_burst(dmg, dir)

	var attack_scene_path: String = ""
	var attack_spawn_pos: Vector2 = origin
	# Check for basic-attack uniques — each class has one that swaps the default
	# basic-attack scene out for an alternate. Returns the dispatched path or
	# empty string if no unique was used.
	var unique_path: String = _try_basic_attack_unique(dir, dmg)
	if unique_path != "":
		# Multiplayer: broadcast and skip the default dispatch below.
		if NetManager and NetManager.is_multiplayer:
			var ns_u := _find_net_sync()
			if ns_u and ns_u.has_method("broadcast_skill_cast"):
				ns_u.call(
					"broadcast_skill_cast", "basic_unique", unique_path, global_position, dir, dmg
				)
		return
	match basic_attack_kind:
		"melee", "claw":
			var sw := MELEE_SCENE.instantiate()
			get_tree().current_scene.add_child(sw)
			attack_spawn_pos = global_position + dir * 30.0
			sw.global_position = attack_spawn_pos
			if sw.has_method("setup"):
				sw.call("setup", dir, dmg)
			if AudioManager:
				if basic_attack_kind == "claw" and druid_form != "human":
					AudioManager.play_sfx_path(
						"res://assets/audio/sfx/player/player_druid_bite_hit.mp3", -10.0
					)
				else:
					AudioManager.play_sfx_path(
						"res://assets/audio/sfx/player/player_melee_swing.mp3", -8.0
					)
			attack_scene_path = "res://scenes/combat/player/melee_swing.tscn"
		"dagger":
			var d := DAGGER_SCENE.instantiate()
			get_tree().current_scene.add_child(d)
			d.global_position = origin
			if d.has_method("setup"):
				d.call("setup", dir, dmg)
			if AudioManager:
				AudioManager.play_sfx_path(
					"res://assets/audio/sfx/player/player_dagger_throw.mp3", -8.0
				)
			attack_scene_path = "res://scenes/combat/player/thrown_dagger.tscn"
		_:
			var bolt := BOLT_SCENE.instantiate()
			get_tree().current_scene.add_child(bolt)
			bolt.global_position = origin
			if bolt.has_method("setup"):
				bolt.call("setup", dir, dmg, "player")
			if AudioManager:
				AudioManager.play_sfx_path(
					"res://assets/audio/sfx/player/player_magic_cast.mp3", -10.0
				)
			attack_scene_path = "res://scenes/combat/player/magic_bolt.tscn"

	# Multiplayer: broadcast a visual-only copy of the basic attack so peers
	# see our melee swing / dagger throw / magic bolt land.
	if NetManager and NetManager.is_multiplayer and attack_scene_path != "":
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_skill_cast"):
			ns.call(
				"broadcast_skill_cast",
				"basic_" + basic_attack_kind,
				attack_scene_path,
				attack_spawn_pos,
				dir,
				dmg
			)


func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("NetSync")


# Subtle camera-zoom punch for big-impact moments (boss spawn, big skills,
# level-up). amount = relative zoom-out delta (0.08 = 8% zoom-out then back).
func camera_punch(amount: float = 0.08, duration: float = 0.25) -> void:
	var cam: Camera2D = get_node_or_null("Camera2D")
	if cam == null:
		return
	var base: Vector2 = cam.zoom
	var out: Vector2 = base * (1.0 - clamp(amount, 0.0, 0.4))
	var tw := create_tween()
	tw.tween_property(cam, "zoom", out, duration * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_property(cam, "zoom", base, duration * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN
	)


# ─────────────────────────────────────────────────────────────────────────────
# Basic-attack uniques — one per class. Player owns the unique transform id
# (e.g. "basic_barb_shockwave"). When equipped, this dispatches the alt scene
# and returns the spawned scene path. Empty string means no unique matched.
func _try_basic_attack_unique(dir: Vector2, dmg: int) -> String:
	if InventorySystem == null or not InventorySystem.has_method("has_unique"):
		return ""
	if GameManager == null:
		return ""
	var cls: String = String(GameManager.player_class)
	# Resolve which unique id (if any) is in play for this class.
	var unique_id: String = ""
	match cls:
		"barbarian":
			unique_id = "basic_barb_shockwave"
		"rogue":
			unique_id = "basic_rogue_triple_throw"
		"mage":
			unique_id = "basic_mage_phantom_edge"
		"druid":
			unique_id = "basic_druid_thunder_sphere"
		"necromancer":
			unique_id = "basic_necro_bone_lance"
		"hexen":
			unique_id = "basic_hexen_whipcrack"
		"stormcaller":
			unique_id = "basic_storm_voltaic_tonfa"
	if unique_id == "" or not InventorySystem.call("has_unique", unique_id):
		return ""
	var origin: Vector2 = cast_origin.global_position if cast_origin else global_position
	match unique_id:
		"basic_barb_shockwave":
			var path := "res://scenes/combat/player/basic_shockwave.tscn"
			var sc: PackedScene = load(path) as PackedScene
			if sc == null:
				return ""
			var n: Node2D = sc.instantiate()
			get_tree().current_scene.add_child(n)
			n.global_position = origin + dir * 30.0
			if n.has_method("setup"):
				n.call("setup", dir, dmg)
			return path
		"basic_rogue_triple_throw":
			var d_path := "res://scenes/combat/player/thrown_dagger.tscn"
			var d_sc: PackedScene = load(d_path) as PackedScene
			if d_sc == null:
				return ""
			# 3 daggers with spread.
			var spreads: Array = [-0.25, 0.0, 0.25]
			for spread in spreads:
				var d: Node2D = d_sc.instantiate()
				get_tree().current_scene.add_child(d)
				d.global_position = origin
				var d_dir: Vector2 = dir.rotated(float(spread))
				if d.has_method("setup"):
					d.call("setup", d_dir, max(1, int(round(float(dmg) * 0.7))))
			if AudioManager:
				AudioManager.play_sfx_path(
					"res://assets/audio/sfx/player/player_dagger_throw.mp3", -8.0
				)
			return d_path
		"basic_mage_phantom_edge":
			var p_path := "res://scenes/combat/player/melee_swing.tscn"
			var p_sc: PackedScene = load(p_path) as PackedScene
			if p_sc == null:
				return ""
			var sw: Node2D = p_sc.instantiate()
			get_tree().current_scene.add_child(sw)
			sw.global_position = global_position + dir * 30.0
			if sw.has_method("setup"):
				sw.call("setup", dir, int(round(float(dmg) * 1.1)))
			# Phantom blue tint on the swing visual.
			var visual: Sprite2D = sw.get_node_or_null("Sprite")
			if visual:
				visual.modulate = Color(0.6, 0.85, 1.5, 1)
			if AudioManager:
				AudioManager.play_sfx_path(
					"res://assets/audio/sfx/player/player_basic_phantom_swing.mp3", -8.0
				)
			return p_path
		"basic_druid_thunder_sphere":
			var t_path := "res://scenes/combat/player/basic_thunder_sphere.tscn"
			var t_sc: PackedScene = load(t_path) as PackedScene
			if t_sc == null:
				return ""
			var b: Node2D = t_sc.instantiate()
			get_tree().current_scene.add_child(b)
			b.global_position = origin
			if b.has_method("setup"):
				b.call("setup", dir, dmg)
			return t_path
		"basic_necro_bone_lance":
			var l_path := "res://scenes/combat/player/melee_swing.tscn"
			var l_sc: PackedScene = load(l_path) as PackedScene
			if l_sc == null:
				return ""
			var lance: Node2D = l_sc.instantiate()
			get_tree().current_scene.add_child(lance)
			lance.global_position = global_position + dir * 36.0
			if lance.has_method("setup"):
				lance.call("setup", dir, int(round(float(dmg) * 1.15)))
			var vis: Sprite2D = lance.get_node_or_null("Sprite")
			if vis:
				vis.modulate = Color(0.85, 0.6, 1.4, 1)
			if AudioManager:
				AudioManager.play_sfx_path(
					"res://assets/audio/sfx/player/player_basic_bone_lance.mp3", -8.0
				)
			return l_path
		"basic_hexen_whipcrack":
			var w_path := "res://scenes/skills/skill_hexen_blood_whip.tscn"
			var w_sc: PackedScene = load(w_path) as PackedScene
			if w_sc == null:
				return ""
			var whip: Node2D = w_sc.instantiate()
			get_tree().current_scene.add_child(whip)
			whip.global_position = origin
			if whip.has_method("setup_with_mods"):
				whip.call("setup_with_mods", dir, int(round(float(dmg) * 0.6)), {"caster": self})
			return w_path
		"basic_storm_voltaic_tonfa":
			var v_path := "res://scenes/combat/player/melee_swing.tscn"
			var v_sc: PackedScene = load(v_path) as PackedScene
			if v_sc == null:
				return ""
			var tonfa: Node2D = v_sc.instantiate()
			get_tree().current_scene.add_child(tonfa)
			tonfa.global_position = global_position + dir * 34.0
			if tonfa.has_method("setup"):
				tonfa.call("setup", dir, int(round(float(dmg) * 1.05)))
			var t_vis: Sprite2D = tonfa.get_node_or_null("Sprite")
			if t_vis:
				t_vis.modulate = Color(0.55, 0.85, 1.6, 1)
			if AudioManager:
				AudioManager.play_sfx_path(
					"res://assets/audio/sfx/player/player_storm_chain_bolt.mp3", -12.0
				)
			return v_path
	return ""


func _on_footstep() -> void:
	if velocity.length() < 20.0:
		return
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_footstep_stone.mp3", -16.0)


# ─────────────────────────────────────────────────────────────────────────────
# DRUID SHAPESHIFT
func set_druid_form(new_form: String, duration: float = -1.0) -> void:
	if GameManager == null:
		return
	if String(GameManager.player_class) != "druid":
		return
	if new_form == druid_form:
		# Already in this form — just refresh duration (used by stack-extending uniques).
		if duration > 0.0:
			druid_form_t = max(druid_form_t, duration)
		return
	# Leaving airborne: drop the Visual back to ground level and remove
	# airborne tag so enemies can target this player again.
	if druid_form == "eagle":
		if sprite:
			sprite.position.y = sprite.position.y + 26.0
		if is_in_group("airborne"):
			remove_from_group("airborne")
	druid_form = new_form
	var dur: float = duration
	if dur < 0.0:
		dur = DRUID_FORM_BASE_DURATION
	druid_form_t = dur
	# Swap sprites + basic-attack kind based on form.
	_apply_druid_form_sprites()
	# Entering airborne: lift the Visual and tag for AI to ignore.
	if new_form == "eagle":
		if sprite:
			sprite.position.y = sprite.position.y - 26.0
		if not is_in_group("airborne"):
			add_to_group("airborne")
	# Sync skill_system slot 0/1.
	if skill_system and skill_system.has_method("set_druid_form"):
		skill_system.set_druid_form(new_form)
	# SFX.
	if AudioManager:
		match new_form:
			"wolf":
				AudioManager.play_sfx_path(
					"res://assets/audio/sfx/player/player_druid_transform_wolf.mp3", -8.0
				)
			"bear":
				AudioManager.play_sfx_path(
					"res://assets/audio/sfx/player/player_druid_transform_bear.mp3", -8.0
				)
			"eagle":
				AudioManager.play_sfx_path(
					"res://assets/audio/sfx/player/player_druid_transform_eagle.mp3", -8.0
				)
			"dire_wolf":
				AudioManager.play_sfx_path(
					"res://assets/audio/sfx/player/player_druid_transform_wolf.mp3", -8.0
				)
			_:
				AudioManager.play_sfx_path(
					"res://assets/audio/sfx/player/player_druid_transform_revert.mp3", -10.0
				)
	# Brief flash VFX.
	if VfxManager:
		var col: Color = Color(0.4, 0.85, 0.4, 1)
		if new_form == "wolf":
			col = Color(1.0, 0.5, 0.4, 1)
		elif new_form == "bear":
			col = Color(0.85, 0.7, 0.4, 1)
		elif new_form == "eagle":
			col = Color(0.85, 0.95, 1.0, 1)
		VfxManager.spawn_hit_sparks(global_position, col, 14)
		VfxManager.screen_flash(Color(col.r, col.g, col.b, 0.18), 0.25)
	# Multiplayer: broadcast so remote puppets show the right sprite.
	if NetManager and NetManager.is_multiplayer:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_druid_form"):
			ns.call("broadcast_druid_form", new_form, druid_form_t)


func _apply_druid_form_sprites() -> void:
	if sprite == null or GameManager == null:
		return
	var data: Dictionary = GameManager.get_class_data()
	# Pull form-specific sprite paths.
	var paths: Dictionary
	match druid_form:
		"wolf":
			paths = {
				"idle": "res://assets/sprites/characters/druid_wolf_idle.png",
				"walk": "res://assets/sprites/characters/druid_wolf_walk.png",
				"attack": "res://assets/sprites/characters/druid_wolf_attack.png",
			}
			basic_attack_kind = "claw"
			basic_attack_interval = 0.30
		"bear":
			paths = {
				"idle": "res://assets/sprites/characters/druid_bear_idle.png",
				"walk": "res://assets/sprites/characters/druid_bear_walk.png",
				"attack": "res://assets/sprites/characters/druid_bear_attack.png",
			}
			basic_attack_kind = "claw"
			basic_attack_interval = 0.50
		"eagle":
			paths = {
				"idle": "res://assets/sprites/characters/druid_eagle_idle.png",
				"walk": "res://assets/sprites/characters/druid_eagle_walk.png",
				"attack": "res://assets/sprites/characters/druid_eagle_attack.png",
			}
			basic_attack_kind = "claw"
			basic_attack_interval = 0.32
		"dire_wolf":
			# Reuses the wolf sprites but with a deep red rim tint applied below.
			paths = {
				"idle": "res://assets/sprites/characters/druid_wolf_idle.png",
				"walk": "res://assets/sprites/characters/druid_wolf_walk.png",
				"attack": "res://assets/sprites/characters/druid_wolf_attack.png",
			}
			basic_attack_kind = "claw"
			basic_attack_interval = 0.28
		_:
			# human — fall back to class data.
			paths = {
				"idle": String(data.get("sprite_idle", "")),
				"walk": String(data.get("sprite_walk", "")),
				"attack": String(data.get("sprite_attack", "")),
			}
			basic_attack_kind = "claw"
			basic_attack_interval = 0.40
	# Rebuild SpriteFrames so AnimatedSprite2D shows the new look.
	var frames := SpriteFrames.new()
	var sample_tex: Texture2D = null
	for state_key in ["idle", "walk", "attack"]:
		var p: String = String(paths.get(state_key, ""))
		if p != "" and ResourceLoader.exists(p):
			var tex: Texture2D = load(p) as Texture2D
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
	_normalize_player_sprite_scale(sample_tex)
	# Dire wolf is a tinted wolf — deeper red rim and slightly larger silhouette.
	if druid_form == "dire_wolf":
		sprite.modulate = Color(1.3, 0.65, 0.55, 1)
		sprite.scale = sprite.scale * 1.18
	else:
		sprite.modulate = Color(1, 1, 1, 1)


func _maybe_whisper_edge_burst(damage: int, _dir: Vector2) -> void:
	if InventorySystem == null or not InventorySystem.has_unique("whisper_edge"):
		return
	# Damage every enemy within 220px.
	var tree := get_tree()
	if tree == null:
		return
	var burst_dmg: int = int(round(float(damage) * 0.8))
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if (e as Node2D).global_position.distance_to(global_position) <= 240.0:
			if e.has_method("take_damage"):
				e.take_damage(burst_dmg, global_position)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.8, 0.6, 1, 1), 16)
		VfxManager.screen_shake(2.5, 0.18)


func _drop_frostwalker_patch() -> void:
	# Lightweight Area2D that slows any enemy it touches once, then fades.
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 16
	get_tree().current_scene.add_child(area)
	area.global_position = global_position + Vector2(0, 8)
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 36.0
	cs.shape = shape
	area.add_child(cs)
	var sprite_ice := Sprite2D.new()
	var ice_path: String = "res://assets/sprites/effects/meteor_telegraph.png"
	if ResourceLoader.exists(ice_path):
		sprite_ice.texture = load(ice_path) as Texture2D
	sprite_ice.modulate = Color(0.55, 0.85, 1.0, 0.6)
	sprite_ice.scale = Vector2(0.5, 0.5)
	area.add_child(sprite_ice)
	# Apply slow to any enemy currently inside, every 0.25s for 1.6s.
	var ticks: int = 5
	for i in ticks:
		var t := get_tree().create_timer(float(i) * 0.25)
		t.timeout.connect(_frostwalker_tick.bind(area))
	# Fade and free.
	var tw := area.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(sprite_ice, "modulate:a", 0.0, 0.3)
	tw.tween_callback(area.queue_free)


func _frostwalker_tick(area: Area2D) -> void:
	if not is_instance_valid(area):
		return
	for body_area in area.get_overlapping_areas():
		if not body_area.is_in_group("enemy_hit"):
			continue
		var enemy := body_area.get_parent()
		if enemy and enemy.has_method("apply_slow"):
			enemy.apply_slow(0.6, 0.55)


func receive_damage_payload(payload: DamageInstance) -> bool:
	if invuln_t > 0.0:
		return false
	# Downed players are already at 0 HP — no further damage until revived/dead.
	if GameManager and (GameManager.player_downed or GameManager.game_over):
		return false
	# Stealth ignores damage.
	if stealth_t > 0.0:
		return false
	# Evasion (Trickster auras): chance to dodge the hit outright.
	if evasion_chance > 0.0 and randf() < evasion_chance:
		invuln_t = 0.1
		if VfxManager:
			VfxManager.spawn_damage_number(global_position + Vector2(0, -22), 0, Color(0.7, 0.9, 1, 1))
		return false
	# Stone Armor: absorb one incoming hit per charge, then break a stone.
	if stone_armor_charges > 0:
		stone_armor_charges -= 1
		invuln_t = 0.35
		if AudioManager:
			AudioManager.play_sfx_path(
				"res://assets/audio/sfx/player/player_druid_stone_armor_break.mp3", -8.0
			)
		if VfxManager:
			VfxManager.spawn_hit_sparks(global_position, Color(0.85, 0.7, 0.5, 1), 8)
			VfxManager.screen_shake(2.5, 0.12)
		# Tell the visible Stone Armor instance to drop a stone.
		var sa: Node = get_node_or_null("StoneArmor")
		if sa and sa.has_method("on_charge_consumed"):
			sa.call("on_charge_consumed")
		return false
	invuln_t = 0.4
	var amount: int = int(round(payload.amount))
	# Blood Frenzy makes the Berserker take +15% damage.
	if frenzy_t > 0.0:
		amount = int(round(float(amount) * 1.15))
	# Warchief Hold the Line: near an ally, part of the hit is absorbed and that
	# ally gains brief damage reduction.
	amount = _hold_the_line(amount)
	# Battlemage armor stacks + ally aura reduce the hit before anything else.
	var dr: float = min(0.8, get_battlemage_dr() + aura_dr)
	if dr > 0.0:
		amount = int(round(float(amount) * (1.0 - dr)))
	# Generic shield pool soaks damage before HP (Flameblade burn-shield, etc.).
	if shield_hp > 0.0 and amount > 0:
		var soaked: int = int(min(shield_hp, float(amount)))
		shield_hp -= float(soaked)
		amount -= soaked
		if VfxManager:
			VfxManager.spawn_hit_sparks(global_position, Color(0.6, 0.85, 1.0, 1), 6)
		if amount <= 0:
			payload.amount = 0.0
			return false
		payload.amount = float(amount)
	var previous_hp: float = health_component.current_hp if health_component else float(GameManager.player_hp)
	if health_component:
		health_component.apply_damage(payload)
		var new_hp: int = int(round(health_component.current_hp))
		if GameManager:
			GameManager.player_hp = new_hp
			if new_hp <= 0:
				# Routes to downed (co-op) or full death (solo) per GameManager.
				# Cheat-death (Trickster Dirty Escape / Necro Second Funeral) saves us
				# at 1 HP before the downed/death routing kicks in.
				if _try_cheat_death():
					return true
				GameManager.register_lethal_blow()
			GameManager.player_stats_changed.emit()
	else:
		if GameManager:
			GameManager.damage_player(amount)
	_sync_component_health_from_game_manager()
	var applied_amount: int = max(0, int(round(previous_hp - health_component.current_hp)) if health_component else amount)
	if applied_amount <= 0:
		return false
	if VfxManager:
		VfxManager.spawn_damage_number(
			global_position + Vector2(0, -22), applied_amount, Color(1.0, 0.4, 0.4, 1)
		)
		VfxManager.spawn_hit_sparks(global_position, Color(1.0, 0.4, 0.4, 1), 5)
		VfxManager.screen_shake(4.0, 0.2)
		VfxManager.screen_flash(Color(1, 0.1, 0.1, 0.18), 0.18)
	if sprite:
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color(1.6, 0.3, 0.3), 0.05)
		tw.tween_property(sprite, "modulate", Color(1, 1, 1), 0.15)
	return true


func take_damage(amount: int) -> void:
	receive_damage_payload(DamageInstance.new(float(amount), null, self, [&"enemy_hit"], []))
