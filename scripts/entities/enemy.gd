class_name Enemy
extends CombatEntity

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
# Spider hit-and-run archetype (bite → retreat → re-approach fast).
var is_spider: bool = false
const SPIDER_RETREAT_TIME: float = 0.7
const SPIDER_RETREAT_SPEED_MULT: float = 1.6
var _spider_retreat_t: float = 0.0
# LimboAI behaviour tree (host-only, lazily created when use_bt_enemies is on).
var _bt_player = null
# Object pooling — when set, death returns the node to the pool instead of freeing.
# _release_done guards the two death exits (dissolve tween callback + safety timer)
# from both firing pool.release on the same corpse (which would double-pool it).
var _pool = null
var _release_done: bool = false
# Elite affixes (V6) — applied at configure; aura shown via a child silhouette sprite.
const ELITE_AURA_SHADER: Shader = preload("res://assets/shaders/elite_aura.gdshader")
var affixes: Array = []
var _regen_frac: float = 0.0
var _explosive: bool = false
var _shielded: bool = false
var _shield_ready: bool = false
var _shield_t: float = 0.0
var _aura: Sprite2D = null
const SHIELD_COOLDOWN: float = 4.0
const ELITE_EXPLODE_RADIUS: float = 130.0

# sprite, hurtbox, stats_component, health_component, status_effect_receiver
# are inherited @export refs from CombatEntity.
@export var hp_bar: ProgressBar
@export var collision_shape: CollisionShape2D
@export var hitbox: HitBoxComponent
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

# Hunter's Oath 5pc — player hits stack a hunt mark: +4% damage taken per stack.
var hunt_stacks: int = 0
var hunt_t: float = 0.0

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
# Named Hexen curses: id → seconds left. "hex" is the generic stack the base kit
# applies; Grand Malediction rolls the four flavored ones. Effects:
#   frailty    — takes +15% damage (receive_damage_payload)
#   misfortune — 25% chance any attack whiffs (_misfortune_whiff)
#   agony      — DoT (ticks in _tick_status)
#   doom       — corpse-burst that damages OTHER enemies on death
# Threefold Curse (local player is Curseweaver): every 3rd unique curse applied
# to this enemy triggers a Hex Burst and spreads one curse to a neighbour.
var curses: Dictionary = {}
var agony_dps: float = 0.0
var _agony_tick_t: float = 0.0
var _doom_damage: int = 0
var _unique_curses_seen: int = 0
# Shared Sin (Coven Mother) / Conductive Teamwork (Conductor) — per-enemy
# internal cooldowns + the Sin counter (5 stacks → curse burst).
var sin_stacks: int = 0
var _sin_icd: float = 0.0
var _conductive_icd: float = 0.0
const CURSE_TIME: float = 6.0
const FRAILTY_AMP: float = 0.15
const MISFORTUNE_MISS_CHANCE: float = 0.25
const DOOM_RADIUS: float = 160.0
const THREEFOLD_EVERY: int = 3
const THREEFOLD_MULT: float = 1.2
const CURSE_SPREAD_RADIUS: float = 200.0
var hp_bar_shown: bool = false
var retarget_t: float = 0.0

# Multiplayer puppet state.
var is_puppet: bool = false
var network_id: int = -1
var _puppet_target_pos: Vector2 = Vector2.ZERO

# State flags.
var _idle_jitter: Vector2 = Vector2.ZERO
var _idle_jitter_t: float = 0.0
# _runtime_base_stats is inherited from CombatEntity.
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


# _setup_components() is inherited from CombatEntity.


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
	is_spider = bool(cfg.get("spider", false))
	_apply_affix_stats(cfg.get("affixes", []))
	if reward_drop:
		reward_drop.xp_value = xp_value
		reward_drop.gold_min = gold_drop_min
		reward_drop.gold_max = gold_drop_max
	if is_inside_tree():
		_apply_sprite()
		_sync_component_stats(true)
		_apply_affix_aura()


# Wipe all per-life runtime state so this node can be handed back out by the pool as a
# fresh enemy. configure() afterwards re-applies stats/affixes/sprite/aura. The GUT
# test (test_enemy_pool) asserts a reused enemy carries no stale affix/HP/status/aura.
func reset_for_reuse() -> void:
	# Death state. (_release_done is intentionally NOT cleared here — it stays true from
	# the death exit until acquire() hands the node back out, so a late safety timer
	# can't re-release an already-pooled corpse. The pool clears it on acquire.)
	dead = false
	if health_component:
		health_component.is_dead = false
	# Drop any leftover death-safety timers (a pooled corpse can still hold one).
	for c in get_children():
		if c is Timer and c.name == "DeathSafety":
			c.queue_free()
	# Free the behaviour tree so it rebuilds with a clean blackboard / latch state.
	if _bt_player != null and is_instance_valid(_bt_player):
		_bt_player.queue_free()
	_bt_player = null
	_reset_affix_state()
	_reset_status_state()
	# Combat / AI timers.
	attack_cd = 0.0
	attack_lockout = 0.0
	retarget_t = 0.0
	_spider_retreat_t = 0.0
	_idle_jitter = Vector2.ZERO
	_idle_jitter_t = 0.0
	_status_ui_t = 0.0
	# Physics / networking.
	velocity = Vector2.ZERO
	is_puppet = false
	network_id = -1
	_puppet_target_pos = global_position
	_reset_bodies_and_visuals()


# Elite affixes — clear flags and tear down the aura silhouette.
func _reset_affix_state() -> void:
	affixes = []
	_regen_frac = 0.0
	_explosive = false
	_shielded = false
	_shield_ready = false
	_shield_t = 0.0
	if _aura != null and is_instance_valid(_aura):
		_aura.queue_free()
	_aura = null


# All status-effect / DoT / curse / slow / taunt timers back to baseline.
func _reset_status_state() -> void:
	burn_t = 0.0
	burn_dps = 0.0
	chill_stacks = 0
	chill_t = 0.0
	frozen_t = 0.0
	_elem_seen = {}
	fractured_t = 0.0
	bleed_t = 0.0
	bleed_dps = 0.0
	vuln_t = 0.0
	vuln_amp = 0.0
	poison_stacks = 0
	poison_t = 0.0
	curse_stacks = 0
	curse_t = 0.0
	curses = {}
	agony_dps = 0.0
	_doom_damage = 0
	_unique_curses_seen = 0
	sin_stacks = 0
	_sin_icd = 0.0
	_conductive_icd = 0.0
	slow_t = 0.0
	slow_mult = 1.0
	taunt_target = null
	taunt_t = 0.0


# Re-enable collision/hurt/hit boxes, reset the status strip + HP bar, and undo
# the death dissolve material so the recycled corpse looks alive again.
func _reset_bodies_and_visuals() -> void:
	# Collision back on (corpse disables it).
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if hurtbox:
		hurtbox.set_deferred("monitoring", true)
		hurtbox.set_deferred("monitorable", true)
	if hitbox:
		_melee_hitbox_active = false
		hitbox.payload = null
		hitbox.disable_collision()
	# Status strip / HP bar UI.
	if _status_strip and is_instance_valid(_status_strip):
		_status_strip.visible = false
		if _status_strip.has_method("update_statuses"):
			_status_strip.update_statuses([])
	hp_bar_shown = false
	if hp_bar:
		hp_bar.visible = false
	# Visuals — undo the dissolve material, restore tint / visibility.
	visible = true
	modulate = Color(1, 1, 1, 1)
	if sprite:
		sprite.modulate = Color(1, 1, 1, 1)
	_install_hit_flash_material()


# ── Elite affixes (V6) ────────────────────────────────────────────────────────
func is_elite() -> bool:
	return not affixes.is_empty()


# Apply each affix's stat multipliers / behaviour flags. Stats must be modified before
# _sync_component_stats so the components pick up the elite values.
func _apply_affix_stats(ids) -> void:
	if not (ids is Array) or (ids as Array).is_empty():
		return
	affixes = (ids as Array).duplicate()
	for id in affixes:
		var a: Dictionary = EnemyAffixes.AFFIXES.get(String(id), {})
		max_hp = int(round(float(max_hp) * float(a.get("hp_mult", 1.0))))
		move_speed *= float(a.get("speed_mult", 1.0))
		attack_damage = int(round(float(attack_damage) * float(a.get("damage_mult", 1.0))))
		attack_cooldown /= maxf(0.1, float(a.get("attack_speed_mult", 1.0)))
		if a.has("regen_frac"):
			_regen_frac = float(a["regen_frac"])
		if bool(a.get("explode", false)):
			_explosive = true
		if bool(a.get("shield", false)):
			_shielded = true
			_shield_ready = true
	hp = max_hp


# Child outline sprite shows the elite aura (blended affix colour). Kept separate from
# the main sprite so it doesn't clobber the hit-flash material; its texture is synced to
# the main sprite each frame. Used on the host and on client puppets (visual only).
func _apply_affix_aura(ids = null) -> void:
	if ids != null and ids is Array:
		affixes = (ids as Array).duplicate()
	if affixes.is_empty() or sprite == null or _aura != null:
		return
	_aura = Sprite2D.new()
	_aura.name = "EliteAura"
	_aura.show_behind_parent = true
	_aura.centered = sprite.centered  # align with the main sprite
	_aura.offset = sprite.offset
	# Enlarge so the silhouette peeks beyond the main sprite as a coloured halo. More
	# affixes → a slightly bigger, more obvious aura.
	var s: float = 1.18 + 0.04 * float(affixes.size())
	_aura.scale = Vector2(s, s)
	var mat := ShaderMaterial.new()
	mat.shader = ELITE_AURA_SHADER
	mat.set_shader_parameter("tint", EnemyAffixes.aura_color(affixes))
	_aura.material = mat
	sprite.add_child(_aura)
	_sync_aura()


func _sync_aura() -> void:
	if _aura == null or sprite == null:
		return
	_aura.texture = sprite.texture
	_aura.flip_h = sprite.flip_h


# Explosive affix — burst that damages players/pets in radius on death (host/solo only).
func _affix_explode() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var dmg: int = int(round(float(attack_damage) * 1.5))
	for grp in ["player", "remote_player", "pet_ally"]:
		for t in tree.get_nodes_in_group(grp):
			if not is_instance_valid(t) or not (t is Node2D):
				continue
			if global_position.distance_to((t as Node2D).global_position) <= ELITE_EXPLODE_RADIUS:
				if t.has_method("take_damage"):
					t.call("take_damage", dmg)
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.5, Color(1.0, 0.55, 0.12, 1))
		VfxManager.screen_shake(6.0, 0.25)


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
	# Feet-line blob shadow, placed once the sprite has its real texture/scale.
	# Idempotent, so pooled enemies re-position their shadow on each reconfigure.
	BlobShadow.attach_at_feet(self, sprite, 44.0, 16.0)


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
	if _aura != null:
		_sync_aura()  # elite aura tracks the main sprite (host + puppet)
	# Puppet mode (multiplayer client) — lerp toward host-broadcast position,
	# no AI, no attacks.
	if is_puppet:
		var w: float = clamp(12.0 * delta, 0.0, 1.0)
		global_position = global_position.lerp(_puppet_target_pos, w)
		return
	# Elite affixes: regenerating heals over time; shielded recharges its absorb.
	if _regen_frac > 0.0 and health_component != null:
		health_component.current_hp = minf(
			health_component.max_hp, health_component.current_hp + float(max_hp) * _regen_frac * delta
		)
		hp = int(round(health_component.current_hp))
	if _shielded and not _shield_ready:
		_shield_t -= delta
		if _shield_t <= 0.0:
			_shield_ready = true
	if attack_lockout > 0.0:
		attack_lockout -= delta
	if slow_t > 0.0:
		slow_t -= delta
		if slow_t <= 0.0:
			slow_mult = 1.0
			modulate = Color(1, 1, 1, 1)
	if hunt_t > 0.0:
		hunt_t -= delta
		if hunt_t <= 0.0:
			hunt_stacks = 0
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
	if _spider_retreat_t > 0.0:
		_spider_retreat_t -= delta

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
		# LimboAI BT drives the in-detection mode for piloted archetypes (melee /
		# ranged-kite / spider) when the flag is on; AOE and everything else stay on
		# the legacy path below. The preamble/idle/no-target handling is unchanged.
		if _bt_enabled() and _ensure_bt():
			_bt_player.update(delta)
		elif is_aoe:
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


# ── LimboAI BT support (host-only; replaces the in-detection mode decision) ────
func _bt_enabled() -> bool:
	return GameManager != null and bool(GameManager.use_bt_enemies)


# Behaviour tree path for this enemy's archetype, or "" if not piloted (AOE → legacy).
func _bt_path() -> String:
	if is_aoe:
		return ""
	if is_spider:
		return "res://scenes/ai/enemy_spider_bt.tres"
	if is_ranged:
		return "res://scenes/ai/enemy_ranged_bt.tres"
	return "res://scenes/ai/enemy_melee_bt.tres"


# Lazily create the BTPlayer; false (→ legacy) when not piloted or the tree is absent.
func _ensure_bt() -> bool:
	if _bt_player != null:
		return true
	var path: String = _bt_path()
	if path == "" or not ResourceLoader.exists(path):
		return false
	var bt = load(path)
	if bt == null:
		return false
	_bt_player = ClassDB.instantiate("BTPlayer")
	if _bt_player == null:
		return false
	_bt_player.behavior_tree = bt
	_bt_player.update_mode = 2  # BTPlayer.UpdateMode.MANUAL
	_bt_player.set_scene_root_hint(self)
	add_child(_bt_player)
	return true


# ── AI primitives (shared by legacy modes and BT tasks). They set velocity / fire
# attacks; _physics_process calls move_and_slide() once after the BT/legacy decision.
func bt_target() -> Node2D:
	return player if (player != null and is_instance_valid(player)) else null


func _to_target() -> Vector2:
	var t := bt_target()
	return ((t as Node2D).global_position - global_position) if t else Vector2.ZERO


func bt_dist() -> float:
	return _to_target().length()


func bt_move_toward_target(speed_mult: float = 1.0) -> void:
	velocity = _to_target().normalized() * move_speed * slow_mult * speed_mult


func bt_retreat(speed_mult: float = 1.0) -> void:
	velocity = -_to_target().normalized() * move_speed * slow_mult * speed_mult


func bt_hold() -> void:
	velocity = Vector2.ZERO


func bt_in_melee_range() -> bool:
	return bt_dist() <= attack_range - 10.0


func bt_in_attack_range() -> bool:
	return bt_dist() <= attack_range


func bt_can_attack() -> bool:
	return attack_cd <= 0.0 and attack_lockout <= 0.0


func bt_melee_attack() -> void:
	_perform_melee_attack()


func bt_ranged_attack() -> void:
	_perform_ranged_attack()


func bt_kite_distance() -> float:
	return ranged_kite_distance


func bt_spider_is_retreating() -> bool:
	return _spider_retreat_t > 0.0


func bt_spider_start_retreat() -> void:
	_spider_retreat_t = SPIDER_RETREAT_TIME


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
		if _misfortune_whiff():
			return
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
	if _misfortune_whiff():
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
	if _misfortune_whiff():
		return
	var dir: Vector2 = (player.global_position - global_position).normalized()
	var proj := ENEMY_PROJECTILE_SCENE.instantiate()
	get_tree().current_scene.add_child(proj)
	proj.global_position = global_position + dir * 24.0
	if proj.has_method("setup"):
		proj.call("setup", dir, attack_damage)
	# Co-op: replicate the bolt to clients as a visual-only copy so they can see and
	# dodge it. The host still adjudicates the actual hit (→ player_hit).
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_fx"):
			ns.call("broadcast_fx", ENEMY_PROJECTILE_SCENE.resource_path, proj.global_position, dir)


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


# _on_health_component_dead() is inherited from CombatEntity (calls _die()).


func receive_damage_payload(payload: DamageInstance) -> bool:
	if payload == null or dead:
		return false

	var amount: int = _amplify_incoming_damage(int(round(payload.amount)))
	if dead:
		return false
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
	# Shielded affix — a recharged shield absorbs one hit, then goes on cooldown.
	if _shielded and _shield_ready:
		_shield_ready = false
		_shield_t = SHIELD_COOLDOWN
		payload.amount = 0.0
		if VfxManager:
			VfxManager.spawn_hit_sparks(global_position, Color(0.45, 0.62, 1.0, 1), 8)
		return false
	# Ascension passives reacting to this hit (Shared Sin / Conductive Teamwork).
	# After the puppet fork so they run host/solo-side only; DoT ticks excluded.
	_ally_passive_hooks(payload)
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
	_play_hit_feedback(applied_amount, knockback)
	if health_component == null and hp <= 0:
		_die()
	return true


# Pre-mitigation damage amplifiers stacked on this hit: necromancer Curse Field
# zone, Vulnerable/Armor Break, and the Frailty curse.
func _amplify_incoming_damage(amount: int) -> int:
	# Curse Field amplification — standing in a necromancer's curse zone.
	if has_meta("curse_amp"):
		var amp: float = float(get_meta("curse_amp", 0.0))
		if amp > 0.0:
			amount = int(round(float(amount) * (1.0 + amp)))
	# Vulnerable / Armor Break amplifies all incoming damage.
	if vuln_t > 0.0 and vuln_amp > 0.0:
		amount = int(round(float(amount) * (1.0 + vuln_amp)))
	# Frailty curse — cursed flesh takes more from everything.
	if curses.has("frailty"):
		amount = int(round(float(amount) * (1.0 + FRAILTY_AMP)))
	return amount


# Visual/audio feedback for a hit that landed: damage number + sparks + hit-stop,
# hit-flash shader, HP-bar reveal/update, knockback impulse and the hurt SFX.
func _play_hit_feedback(applied_amount: int, knockback: Vector2) -> void:
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


# `from_net` — урон пришёл от другого игрока через relay (кооп-хост применяет
# чужие удары): локальные он-хит эффекты (вампиризм контуров) не срабатывают.
func take_damage(
	amount: int, source_position: Vector2 = Vector2.ZERO, from_net: bool = false
) -> void:
	var dmg: int = amount
	# Hunter's Oath 5pc: amplify by existing hunt stacks, then add a stack.
	if (
		InventorySystem
		and InventorySystem.has_method("has_set_effect")
		and InventorySystem.has_set_effect("hunt_mark")
	):
		dmg = int(round(float(dmg) * (1.0 + 0.04 * float(hunt_stacks))))
		hunt_stacks = mini(hunt_stacks + 1, 5)
		hunt_t = 4.0
	# Контур крови / Кровавый обсидиан — вампиризм с ЛОКАЛЬНО нанесённого урона.
	if not from_net and GameManager:
		GameManager.on_player_dealt_damage(dmg)
	var knockback: Vector2 = Vector2.ZERO
	if source_position != Vector2.ZERO:
		knockback = (global_position - source_position).normalized() * 110.0
	receive_damage_payload(
		DamageInstance.new(float(dmg), null, self, [&"player_hit"], [], false, knockback)
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
# callers (Hexen) can trigger bursts on every Nth unique curse. Routes through
# the named-curse system as the generic "hex" so the base kit and the flavored
# Malediction curses share one model (and one Threefold counter).
func add_curse_stack() -> int:
	if dead:
		return 0
	apply_curse("hex")
	return curse_stacks


# Apply a named Hexen curse. `power` is curse-specific: agony = DPS,
# doom = burst damage. Every application bumps the visible stack counter;
# a curse id NEW to this enemy also advances the Threefold counter.
func apply_curse(id: String, duration: float = CURSE_TIME, power: float = 0.0) -> void:
	if dead:
		return
	var is_new: bool = not curses.has(id)
	curses[id] = duration
	match id:
		"agony":
			agony_dps = maxf(agony_dps, power)
		"doom":
			_doom_damage = maxi(_doom_damage, int(power))
	curse_stacks += 1
	curse_t = maxf(curse_t, duration)
	if is_new:
		_unique_curses_seen += 1
		_maybe_threefold_burst()


# Threefold Curse (Curseweaver passive): every 3rd unique curse on this enemy
# detonates a Hex Burst and spreads one curse to the nearest uncursed neighbour.
# Keyed off the LOCAL player's spec (host-side sim, same limitation as the other
# ascension passives).
func _maybe_threefold_burst() -> void:
	if GameManager == null or String(GameManager.player_spec_path) != "curseweaver":
		return
	if _unique_curses_seen <= 0 or _unique_curses_seen % THREEFOLD_EVERY != 0:
		return
	var dmg: int = maxi(1, int(round(float(GameManager.get_effective_damage()) * THREEFOLD_MULT)))
	take_damage(dmg, global_position)
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 0.9, Color(0.7, 0.2, 0.8, 1))
	_spread_one_curse()


func _spread_one_curse() -> void:
	if curses.is_empty():
		return
	var tree := get_tree()
	if tree == null:
		return
	var best: Node = null
	var best_d: float = CURSE_SPREAD_RADIUS
	for e in tree.get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if not e.has_method("apply_curse"):
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	var ids: Array = curses.keys()
	var pick: String = String(ids[randi() % ids.size()])
	var power: float = agony_dps if pick == "agony" else float(_doom_damage)
	best.call("apply_curse", pick, float(curses[pick]), power)
	if VfxManager:
		VfxManager.spawn_hit_sparks((best as Node2D).global_position, Color(0.7, 0.2, 0.8, 1), 6)


# Misfortune curse: the attack whiffs entirely. Checked at every outgoing-damage
# site (melee, AoE, ranged); grey sparks sell the fumble.
func _misfortune_whiff() -> bool:
	if not curses.has("misfortune"):
		return false
	if randf() >= MISFORTUNE_MISS_CHANCE:
		return false
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.6, 0.6, 0.65, 0.9), 5)
	return true


func _apply_agony_tick() -> void:
	if dead or agony_dps <= 0.0:
		return
	var tick: int = max(1, int(round(agony_dps * 0.5)))
	receive_damage_payload(
		DamageInstance.new(float(tick), null, self, [&"curse"], [], false, Vector2.ZERO)
	)


# DoT ticks must not feed on-hit passives (burn/agony would farm Sin stacks).
func _is_dot_payload(payload: DamageInstance) -> bool:
	for tag in payload.tags:
		if tag in [&"burn", &"bleed", &"poison", &"curse", &"environment"]:
			return true
	return false


# Passives of the LOCAL player's ascension that react to this enemy being hit.
# Host-side sim like every other ascension passive (client allies' procs are a
# relay follow-up).
func _ally_passive_hooks(payload: DamageInstance) -> void:
	if dead or GameManager == null or _is_dot_payload(payload):
		return
	match String(GameManager.player_spec_path):
		"coven_mother":
			# Shared Sin: hits on a cursed/hex-marked foe pay the coven — mana
			# to the witch, a sliver of shield to the attacker, and a Sin stack;
			# the 5th stack detonates as a curse burst.
			if _sin_icd > 0.0:
				return
			if not (has_meta("hex_marked") or curse_stacks > 0):
				return
			_sin_icd = 0.4
			GameManager.regen_mana(2.0)
			var attacker := _payload_player(payload)
			if attacker and attacker.has_method("add_shield"):
				attacker.call("add_shield", 4.0, float(GameManager.get_effective_max_hp()) * 0.15)
			sin_stacks += 1
			if sin_stacks >= 5:
				sin_stacks = 0
				_sin_burst()
		"conductor":
			# Conductive Teamwork: hits on a static-marked foe arc to neighbours
			# (≤1 proc / 0.8s per enemy).
			if _conductive_icd > 0.0 or not _elem_seen.has("storm"):
				return
			_conductive_icd = 0.8
			_conductive_zap()


# The player behind this hit, falling back to the local player (solo, or when
# the source is a skill node without a caster backref).
func _payload_player(payload: DamageInstance) -> Node:
	if payload.attacker and is_instance_valid(payload.attacker) and payload.attacker.is_in_group("player"):
		return payload.attacker
	var tree := get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p) and not p.is_in_group("remote_player"):
			return p
	return null


func _sin_burst() -> void:
	if GameManager == null:
		return
	var dmg: int = maxi(1, int(round(float(GameManager.get_effective_damage()))))
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.0, Color(0.65, 0.15, 0.7, 1))
	take_damage(dmg, global_position)
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > 140.0:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", dmg, global_position)


func _conductive_zap() -> void:
	if GameManager == null:
		return
	var tree := get_tree()
	if tree == null:
		return
	var dmg: int = maxi(1, int(round(float(GameManager.get_effective_damage()) * 0.4)))
	var zapped: int = 0
	for e in tree.get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > 220.0:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", dmg, global_position)
		if e.has_method("mark_element"):
			e.call("mark_element", "storm")
		if VfxManager:
			VfxManager.spawn_hit_sparks((e as Node2D).global_position, Color(0.6, 0.8, 1.0, 1), 6)
		zapped += 1
		if zapped >= 2:
			break


# Doom curse payoff: the corpse bursts, damaging OTHER enemies around it.
func _doom_burst() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.2, Color(0.5, 0.1, 0.6, 1))
	for e in tree.get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > DOOM_RADIUS:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", maxi(1, _doom_damage), global_position)


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
		# Show the stack count so curse builds can read their ramp at a glance.
		var k_label: String = "K" if curse_stacks <= 1 else "K%d" % curse_stacks
		out.append({"id": "curse", "label": k_label, "color": Color(0.55, 0.2, 0.6), "progress": clampf(curse_t / 6.0, 0.0, 1.0)})
	var named_curses := {
		"frailty": {"label": "W", "color": Color(0.7, 0.5, 0.75)},
		"misfortune": {"label": "M", "color": Color(0.45, 0.45, 0.6)},
		"agony": {"label": "A", "color": Color(0.85, 0.25, 0.5)},
		"doom": {"label": "D", "color": Color(0.35, 0.05, 0.45)},
	}
	for cid in named_curses:
		if curses.has(cid):
			var meta: Dictionary = named_curses[cid]
			out.append({
				"id": cid,
				"label": meta["label"],
				"color": meta["color"],
				"progress": clampf(float(curses[cid]) / CURSE_TIME, 0.0, 1.0),
			})
	if taunt_t > 0.0:
		out.append({"id": "taunt", "label": "T", "color": Color(0.95, 0.85, 0.3), "progress": clampf(taunt_t / 1.0, 0.0, 1.0)})
	return out


func _tick_status(delta: float) -> void:
	_tick_elemental_status(delta)
	_tick_curses_and_control(delta)


# Elemental / physical effects: freeze + chill, fracture, recently-seen element
# decay, and the burn/bleed/poison damage-over-time ticks.
func _tick_elemental_status(delta: float) -> void:
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
	if poison_t > 0.0:
		poison_t -= delta
		_poison_tick_t -= delta
		if _poison_tick_t <= 0.0:
			_poison_tick_t = 0.5
			_apply_poison_tick()
		if poison_t <= 0.0:
			poison_stacks = 0


# Control + hex effects: Vulnerable, Taunt, the named curse timers (with the
# Agony DoT and Doom payoff teardown) and the ally-passive internal cooldowns.
func _tick_curses_and_control(delta: float) -> void:
	if vuln_t > 0.0:
		vuln_t -= delta
		if vuln_t <= 0.0:
			vuln_amp = 0.0
	if taunt_t > 0.0:
		taunt_t -= delta
		if taunt_t <= 0.0 or not is_instance_valid(taunt_target):
			taunt_target = null
	if curse_t > 0.0:
		curse_t -= delta
		if curse_t <= 0.0:
			curse_stacks = 0
	if not curses.is_empty():
		for cid in curses.keys():
			curses[cid] = float(curses[cid]) - delta
			if float(curses[cid]) <= 0.0:
				curses.erase(cid)
				if cid == "agony":
					agony_dps = 0.0
				elif cid == "doom":
					_doom_damage = 0
		if curses.has("agony") and agony_dps > 0.0:
			_agony_tick_t -= delta
			if _agony_tick_t <= 0.0:
				_agony_tick_t = 0.5
				_apply_agony_tick()
	if _sin_icd > 0.0:
		_sin_icd -= delta
	if _conductive_icd > 0.0:
		_conductive_icd -= delta


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
		tw.tween_callback(_release_or_free)
	else:
		_release_or_free()
	# Safety fallback — child Timer so we can't leak.
	if is_inside_tree():
		var safety := Timer.new()
		safety.name = "DeathSafety"
		safety.one_shot = true
		safety.wait_time = 1.2
		safety.autostart = true
		safety.timeout.connect(_safety_free)
		add_child(safety)


func _safety_free() -> void:
	if is_instance_valid(self):
		_release_or_free()


# Remove this enemy with NO rewards/drops/death event (used when an arena wave ends and
# survivors are wiped — the incentive is to kill them during the wave). Pools the node.
func despawn_silent() -> void:
	if dead:
		return
	dead = true
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	_release_or_free()


# Final death exit — return to the pool if pool-managed, else free. Guarded so the
# dissolve tween and the safety timer can't both act on the same corpse.
func _release_or_free() -> void:
	if _release_done:
		return
	_release_done = true
	if _pool != null and is_instance_valid(_pool) and _pool.has_method("release"):
		_pool.release(self)
	elif is_instance_valid(self):
		queue_free()


func _spawn_hatchlings(count: int) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
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
		"spider": true,  # hit-and-run BT
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
		var ang: float = randf() * TAU
		var pos: Vector2 = global_position + Vector2(cos(ang), sin(ang)) * 48.0
		var h: Node2D = EnemyPool.acquire(tree.current_scene, pos)
		if h == null:
			continue
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
	_die_trigger_affixes()
	_die_disable_bodies()
	_die_play_fx()
	_die_grant_rewards()
	_die_emit_event()
	_die_dissolve_and_free()


# On-death affix/curse payoffs (host/solo only): explosive burst, Fracture
# detonation, Doom corpse-burst, Brood Mother hatchling swarm.
func _die_trigger_affixes() -> void:
	# Explosive affix — burst that damages nearby players/pets (host/solo only).
	if _explosive and not is_puppet:
		_affix_explode()
	# Elementalist Fracture payoff: a fractured enemy detonates in a small
	# elemental burst, splashing nearby foes (host-side / solo only).
	if fractured_t > 0.0 and not is_puppet:
		_fracture_explosion()
	# Doom curse payoff — the cursed corpse bursts against its own kind.
	if curses.has("doom") and _doom_damage > 0 and not is_puppet:
		_doom_burst()
	# Brood Mother bursts into a small swarm on death.
	if is_brood_mother:
		_spawn_hatchlings(6)


# Turn the corpse non-interactive: drop collision so player/bolts pass through,
# stop hurt/hit boxes, hide HP bar + status strip.
func _die_disable_bodies() -> void:
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


# Death burst VFX (with hit-stop + shake) and type-specific death SFX.
func _die_play_fx() -> void:
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


# Grant XP + gold. Host broadcasts the death (clients spawn matching drops/VFX)
# and grants flat XP so every peer levels in sync; solo grants XP with gear mult.
func _die_grant_rewards() -> void:
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
		# grant the SAME amount when they receive enemy_death (net_sync). XP is a
		# number now (orbs removed), so the kill is the single grant point —
		# everyone ends on the same level and levels up in sync.
		if GameManager:
			GameManager.add_xp(xp_value, false)  # flat: same amount on every peer
		# Also drop locally (host is also a player) — gold only.
		_drop_loot()
	else:
		# Solo: grant XP on the kill (XP orbs were removed — XP is a number now),
		# then drop gold.
		if GameManager:
			GameManager.add_xp(xp_value)  # apply_mult=true: solo keeps XP-gain gear bonus
		_drop_loot()


# Fire the ActorDeathEvent on GameEvents (carrying killer/damage) and the legacy
# enemy_defeated signal so the spawner can track wave progress.
func _die_emit_event() -> void:
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
# thematically (skeletons burn white, wraiths blue, succubi pink). A safety
# Timer guarantees the node is released even if the tween never fires.
func _die_dissolve_and_free() -> void:
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
		tw.tween_callback(_release_or_free)
	else:
		_release_or_free()
	# Safety net — child Timer so when we're freed the timer dies too.
	if is_inside_tree():
		var safety := Timer.new()
		safety.name = "DeathSafety"
		safety.one_shot = true
		safety.wait_time = 1.2
		safety.autostart = true
		safety.timeout.connect(_safety_free)
		add_child(safety)


# _find_net_sync() is inherited from CombatEntity.


func _drop_loot() -> void:
	if reward_drop:
		reward_drop.drop_at(global_position)
