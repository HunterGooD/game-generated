extends Node

# Enemy spawner — escalating waves with per-wave stat scaling.

const BOSS_SCENE: PackedScene = preload("res://scenes/entities/boss.tscn")
const MERCHANT_SCENE: PackedScene = preload("res://scenes/pickups/merchant.tscn")
const PORTAL_SCENE: PackedScene = preload("res://scenes/pickups/wave_portal.tscn")

const ENEMY_TYPES := {
	"skeleton":
	{
		"type": "skeleton",
		"max_hp": 36,
		"move_speed": 95.0,
		"attack_damage": 8,
		"attack_range": 56.0,
		"attack_cooldown": 1.2,
		"detection_range": 380.0,
		"xp_value": 12,
		"gold_min": 1,
		"gold_max": 4,
		"sprite_idle": "res://assets/sprites/characters/skeleton_warrior/skeleton_warrior_idle.png",
		"sprite_walk": "res://assets/sprites/characters/skeleton_warrior/skeleton_warrior_walk.png",
		"sprite_attack":
		"res://assets/sprites/characters/skeleton_warrior/skeleton_warrior_attack.png",
		"sprite_scale": 0.36,
		"tint": Color(1, 1, 1, 1),
		"ranged": false,
	},
	"cultist":
	{
		"type": "cultist",
		"max_hp": 24,
		"move_speed": 80.0,
		"attack_damage": 7,
		"attack_range": 360.0,
		"attack_cooldown": 1.8,
		"detection_range": 440.0,
		"xp_value": 16,
		"gold_min": 2,
		"gold_max": 6,
		"sprite_idle": "res://assets/sprites/characters/dark_cultist/dark_cultist_idle.png",
		"sprite_walk": "res://assets/sprites/characters/dark_cultist/dark_cultist_walk.png",
		"sprite_attack": "res://assets/sprites/characters/dark_cultist/dark_cultist_attack.png",
		"sprite_scale": 0.36,
		"tint": Color(1, 0.9, 0.95, 1),
		"ranged": true,
		"kite_distance": 240.0,
	},
	"wraith":
	{
		"type": "wraith",
		"max_hp": 18,
		"move_speed": 150.0,
		"attack_damage": 6,
		"attack_range": 48.0,
		"attack_cooldown": 0.9,
		"detection_range": 460.0,
		"xp_value": 10,
		"gold_min": 0,
		"gold_max": 3,
		"sprite_idle": "res://assets/sprites/characters/ruin_wraith/ruin_wraith_idle.png",
		"sprite_walk": "res://assets/sprites/characters/ruin_wraith/ruin_wraith_walk.png",
		"sprite_attack": "res://assets/sprites/characters/ruin_wraith/ruin_wraith_attack.png",
		"sprite_scale": 0.38,
		"tint": Color(0.7, 0.85, 1.2, 0.85),
		"ranged": false,
	},
	"spider_brood":
	{
		"type": "spider_brood",
		"max_hp": 280,
		"move_speed": 70.0,
		"attack_damage": 14,
		"attack_range": 52.0,
		"attack_cooldown": 1.6,
		"detection_range": 480.0,
		"xp_value": 35,
		"gold_min": 5,
		"gold_max": 12,
		"sprite_idle": "res://assets/sprites/characters/spider_brood_idle.png",
		"sprite_walk": "res://assets/sprites/characters/spider_brood_walk.png",
		"sprite_attack": "res://assets/sprites/characters/spider_brood_attack.png",
		"sprite_scale": 0.55,
		"tint": Color(1, 1, 1, 1),
		"ranged": false,
		"brood_mother": true,
	},
	"spider_hatchling":
	{
		"type": "spider_hatchling",
		"max_hp": 22,
		"move_speed": 165.0,
		"attack_damage": 4,
		"attack_range": 38.0,
		"attack_cooldown": 0.8,
		"detection_range": 360.0,
		# Hit-and-run: dart in, bite, scuttle back, re-approach (LimboAI spider BT).
		"spider": true,
		"xp_value": 3,
		"gold_min": 0,
		"gold_max": 1,
		"sprite_idle": "res://assets/sprites/characters/spider_hatchling_idle.png",
		"sprite_walk": "res://assets/sprites/characters/spider_hatchling_walk.png",
		"sprite_attack": "res://assets/sprites/characters/spider_hatchling_attack.png",
		"sprite_scale": 0.32,
		"tint": Color(1, 1, 1, 1),
		"ranged": false,
	},
	"succubus":
	{
		"type": "succubus",
		"max_hp": 72,
		"move_speed": 110.0,
		"attack_damage": 11,
		"attack_range": 220.0,
		"attack_cooldown": 2.6,
		"detection_range": 520.0,
		"xp_value": 22,
		"gold_min": 3,
		"gold_max": 8,
		"sprite_idle": "res://assets/sprites/characters/succubus_idle.png",
		"sprite_walk": "res://assets/sprites/characters/succubus_walk.png",
		"sprite_attack": "res://assets/sprites/characters/succubus_attack.png",
		"sprite_scale": 0.40,
		"tint": Color(1.0, 0.85, 0.95, 1),
		"ranged": false,
		"aoe": true,
	},
}

const WAVE_TEMPLATES := [
	{"skeleton": 3, "wraith": 1},
	{"skeleton": 2, "cultist": 2},
	{"skeleton": 3, "cultist": 1, "wraith": 2},
	{"skeleton": 4, "cultist": 2, "wraith": 2, "succubus": 1, "spider_brood": 1},
]

const TYPE_ORDER := ["skeleton", "cultist", "wraith", "succubus", "spider_brood"]

@export var room_min: Vector2 = Vector2(192, 192)
@export var room_max: Vector2 = Vector2(2400, 1408)
@export var safe_radius_around_player: float = 220.0
@export var wave_break: float = 8.0

var current_wave: int = 0
var enemies_remaining: int = 0
var combat_active: bool = false
var combat_music_on: bool = false
var boss_active: bool = false
var current_boss: Node = null
var current_merchant: Node = null
var current_portal: Node = null
var portal_break_active: bool = false

# Arena / run-node mode. When the spawner is hosting a run-map combat node it runs a
# BOUNDED set of waves (arena_waves) then opens an exit portal back to the map, instead
# of the endless Play loop. Set from GameManager.run_node_active in _ready.
var arena_mode: bool = false
var arena_waves: int = 0  # waves before the finale boss (from RunMap.combat_plan)
var arena_elite_chance: float = -1.0  # -1 = use the difficulty default
var _arena_pillars: Array = []
var _arena_choosing: bool = false  # true while the pre-wave pillar choice is open
# Timed survival waves: each wave lasts ARENA_WAVE_DURATION and spawns a batch every
# ARENA_BATCH_INTERVAL (ARENA_BATCHES batches). Batch size grows per wave.
const ARENA_WAVE_DURATION: float = 30.0
const ARENA_BATCH_INTERVAL: float = 10.0
const ARENA_BATCHES: int = 3
const ARENA_BATCH_TYPES: Array = ["skeleton", "cultist", "wraith", "succubus"]
const ARENA_EVENT_CURRENCY: int = 40  # bonus for clearing a kill-counter event (mini-boss/tower)
const ARENA_PURPLE_CHANCE: float = 0.22  # chance a 5th rare purple pillar also appears
const ARENA_PURPLE_BOSS_CURRENCY: int = 35  # per purple-wave mini-boss
const ARENA_PILLAR_CURRENCY := {"green": 8, "red": 22, "purple": 55}
# Three effect sub-types each for green (player boons) and red (enemy escalation). A pillar
# of that colour rolls one. Effects ACCUMULATE across the whole arena (GameManager fields).
const GREEN_EFFECTS := {
	"might": "Might — +15% damage",
	"swift": "Swift — +12% move speed",
	"fortune": "Fortune — heal + bonus XP",
}
const RED_EFFECTS := {
	"brutality": "Brutality — enemies +40% power",
	"frenzy": "Frenzy — events fire faster",
	"horde": "Horde — +50% more enemies",
}
var _arena_batch_timer: Timer = null
var _arena_wave_timer: Timer = null
var _arena_tick_timer: Timer = null
var _arena_batches_left: int = 0
var _wave_end_msec: int = 0
var _wave_purple: bool = false  # current wave is a purple boss-swarm wave
var _wave_kills: int = 0
# Captured at the first arena wave = the player's spawn point (the middle of the arena).
var _arena_center: Vector2 = Vector2.ZERO
var _arena_center_set: bool = false


func _ready() -> void:
	add_to_group("enemy_spawner")  # so dev console / tools can find us
	if GameManager:
		GameManager.enemy_defeated.connect(_on_enemy_defeated)
	# Arena event mini-bosses pay bonus currency when they die (tagged via metadata).
	if GameEvents and not GameEvents.enemy_died.is_connected(_on_any_enemy_died):
		GameEvents.enemy_died.connect(_on_any_enemy_died)
	# Front-load enemy instancing into the pool (component setup is the costly part) so the
	# first wave doesn't hitch. Deferred: during _ready the parent is still building its
	# children, so add_child() is blocked — prewarm once the tree settles. Pool also feeds
	# client puppets (net_sync).
	if EnemyPool and get_parent():
		EnemyPool.call_deferred("prewarm", 12, get_parent())
	# Run-map combat node → bounded arena mode (vs the endless Play loop).
	if GameManager and not GameManager.run_node_active.is_empty():
		var node: Dictionary = GameManager.run_node_active
		if RunMap.is_combat_type(String(node.get("type", ""))):
			var plan: Dictionary = RunMap.combat_plan(node)
			arena_mode = true
			arena_waves = int(plan["waves"])
			arena_elite_chance = float(plan["elite_chance"])
			if GameManager:
				GameManager.arena_reset()
	# In multiplayer, only the host spawns enemies. Clients receive enemy_spawn
	# messages and instantiate puppet enemies via NetSync.
	if NetManager and NetManager.is_multiplayer and not NetManager.is_host:
		return
	# Start the first wave after a short grace period so the player can settle in.
	var t := get_tree().create_timer(2.5)
	t.timeout.connect(_start_next_wave)


func _start_next_wave() -> void:
	if not is_inside_tree():
		return
	if GameManager and GameManager.game_over:
		return
	# Arena nodes open with a mandatory pillar choice that starts the timed survival wave.
	if arena_mode:
		_arena_open_pillars()
		return
	# If a merchant is still on the field, send them away.
	if (
		current_merchant
		and is_instance_valid(current_merchant)
		and current_merchant.has_method("leave")
	):
		current_merchant.call("leave")
		current_merchant = null
	# In multiplayer, only the host runs enemy spawning. Other peers spawn
	# their own clientside copies of the same enemies — that's a known v1
	# limitation; perfect enemy sync is future work. For now everyone sees
	# THEIR local enemies (roughly the same waves since the wave template
	# is deterministic) but damage/HP are independent. Co-op still feels
	# alive because remote players visually share the room.
	current_wave += 1
	# Boss-wave gate: every 5 waves spawn a boss instead of a normal wave.
	var boss_id: String = BossDatabase.boss_for_wave(current_wave)
	if boss_id != "":
		_spawn_boss(boss_id)
		return
	var template_idx: int = (current_wave - 1) % WAVE_TEMPLATES.size()
	var counts: Dictionary = WAVE_TEMPLATES[template_idx].duplicate(true)

	# Per-wave scaling — counts grow linearly with the wave number.
	# +1 to ALL types every 3 waves.
	var every_three_bonus: int = int(floor(float(current_wave - 1) / 3.0))
	if every_three_bonus > 0:
		for t in counts.keys():
			counts[t] = int(counts[t]) + every_three_bonus

	# +1 extra to one random type per wave (after wave 1).
	if current_wave > 1:
		var pick: String = TYPE_ORDER[randi() % TYPE_ORDER.size()]
		counts[pick] = int(counts.get(pick, 0)) + (current_wave - 1)

	# Every 5 waves: 2 extra random-type minions.
	if current_wave % 5 == 0:
		for i in 2:
			var pick: String = TYPE_ORDER[randi() % TYPE_ORDER.size()]
			counts[pick] = int(counts.get(pick, 0)) + 1

	# Stat / xp scaling factors — wave growth × run difficulty.
	var diff: int = GameManager.run_difficulty if GameManager else 0
	var d_hp: float = Difficulty.value(diff, "enemy_hp_mult", 1.0)
	var d_dmg: float = Difficulty.value(diff, "enemy_dmg_mult", 1.0)
	var d_reward: float = Difficulty.value(diff, "reward_mult", 1.0)
	var d_spawn: float = Difficulty.value(diff, "spawn_rate_mult", 1.0)
	var hp_mult: float = (1.0 + 0.08 * float(current_wave - 1)) * d_hp
	var dmg_mult: float = (1.0 + 0.05 * float(int(floor(float(current_wave - 1) / 2.0)))) * d_dmg
	# Arena empowerment pillars escalate the remaining waves.
	if arena_mode and GameManager:
		hp_mult *= GameManager.arena_enemy_power
		dmg_mult *= GameManager.arena_enemy_power
	var xp_mult: float = (1.0 + 0.12 * float(current_wave - 1)) * d_reward
	var gold_mult: float = (1.0 + 0.10 * float(current_wave - 1)) * d_reward

	var spawned: int = 0
	for type_id in counts.keys():
		# Higher difficulty packs in more enemies per type (density).
		var n: int = int(round(float(int(counts[type_id])) * d_spawn))
		for i in n:
			_spawn_one(String(type_id), hp_mult, dmg_mult, xp_mult, gold_mult)
			spawned += 1
	enemies_remaining = spawned
	combat_active = true
	if GameManager:
		GameManager.wave_started.emit(current_wave)
	_broadcast_wave_started(current_wave)
	_switch_to_combat_music()


const ELITE_CHANCE: float = 0.10


func _spawn_one(
	type_id: String,
	hp_mult: float,
	dmg_mult: float,
	xp_mult: float,
	gold_mult: float,
	force_affixes: Array = [],
	pos_override = null
) -> Node:
	if not ENEMY_TYPES.has(type_id):
		return null
	var cfg: Dictionary = ENEMY_TYPES[type_id].duplicate(true)
	cfg["max_hp"] = int(round(float(cfg["max_hp"]) * hp_mult))
	cfg["attack_damage"] = int(round(float(cfg["attack_damage"]) * dmg_mult))
	cfg["xp_value"] = int(round(float(cfg["xp_value"]) * xp_mult))
	cfg["gold_min"] = int(round(float(cfg["gold_min"]) * gold_mult))
	cfg["gold_max"] = int(round(float(cfg["gold_max"]) * gold_mult))
	var host_auth: bool = NetManager == null or not NetManager.is_multiplayer or NetManager.is_host
	var diff: int = GameManager.run_difficulty if GameManager else 0
	if not force_affixes.is_empty():
		# Caller-supplied affixes (arena mini-bosses) — skip the random elite roll.
		cfg["affixes"] = (force_affixes as Array).duplicate()
		var fbump: float = 1.0 + 0.6 * float(force_affixes.size())
		cfg["xp_value"] = int(round(float(cfg["xp_value"]) * fbump))
		cfg["gold_max"] = int(round(float(cfg["gold_max"]) * fbump))
	else:
		# Elite roll (V6): host-side a chance to grant 1–3 affixes. Clients get the affix
		# list via the spawn message for the aura. Brood mothers stay vanilla.
		var elite_chance: float = Difficulty.value(diff, "elite_chance", ELITE_CHANCE)
		if arena_mode and arena_elite_chance >= 0.0:
			elite_chance = arena_elite_chance  # node-type override (e.g. elite packs)
		if host_auth and not bool(cfg.get("brood_mother", false)) and randf() < elite_chance:
			var affix_n: int = EnemyAffixes.roll_count() + int(Difficulty.value(diff, "elite_affix_bonus", 0.0))
			var affix_ids: Array = EnemyAffixes.roll(affix_n)
			cfg["affixes"] = affix_ids
			var bump: float = 1.0 + 0.6 * float(affix_ids.size())
			cfg["xp_value"] = int(round(float(cfg["xp_value"]) * bump))
			cfg["gold_max"] = int(round(float(cfg["gold_max"]) * bump))
	var pos: Vector2 = pos_override if pos_override != null else _pick_spawn_pos()
	var parent: Node = get_parent() if get_parent() else get_tree().current_scene
	var e := EnemyPool.acquire(parent, pos)
	if e == null:
		return null
	if e.has_method("configure"):
		e.call("configure", cfg)
	# Multiplayer host: assign network id + broadcast spawn so clients render
	# the same enemy.
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("register_enemy"):
			ns.call("register_enemy", e)
	return e


# ── Dev/console spawn helpers (host/solo) ─────────────────────────────────────
# Dev: instantly end the current arena and jump to the reward screen (to verify rewards +
# the exit-to-map). Stops the wave, clears pillars/enemies. Returns false if not in an arena.
func dev_finish_arena() -> bool:
	if not arena_mode:
		return false
	combat_active = false
	_arena_choosing = false
	for tmr in [_arena_batch_timer, _arena_wave_timer, _arena_tick_timer]:
		if tmr and is_instance_valid(tmr):
			tmr.queue_free()
	_arena_batch_timer = null
	_arena_wave_timer = null
	_arena_tick_timer = null
	for p in _arena_pillars:
		if is_instance_valid(p):
			p.queue_free()
	_arena_pillars.clear()
	_despawn_arena_survivors()
	if GameManager:
		GameManager.arena_timer.emit(-1)
	_finish_arena()
	return true


# Spawn one enemy of `type_id` at `pos` with the given affix ids (empty = no affixes).
# Reuses the real spawn path incl. co-op register_enemy. Returns false on bad type.
func dev_spawn(type_id: String, affix_ids: Array, pos: Vector2) -> bool:
	if not ENEMY_TYPES.has(type_id):
		return false
	var cfg: Dictionary = ENEMY_TYPES[type_id].duplicate(true)
	if not affix_ids.is_empty():
		cfg["affixes"] = affix_ids
	var parent: Node = get_parent() if get_parent() else get_tree().current_scene
	var e := EnemyPool.acquire(parent, pos)
	if e == null:
		return false
	if e.has_method("configure"):
		e.call("configure", cfg)
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("register_enemy"):
			ns.call("register_enemy", e)
	return true


func dev_spawn_boss(boss_id: String) -> bool:
	if String(boss_id) == "" or not BossDatabase.get_boss(boss_id):
		return false
	_spawn_boss(boss_id)
	return true


func enemy_type_ids() -> Array:
	return ENEMY_TYPES.keys()


func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("NetSync")


func _pick_spawn_pos() -> Vector2:
	var player := _find_player()
	for i in 24:
		var x: float = randf_range(room_min.x, room_max.x)
		var y: float = randf_range(room_min.y, room_max.y)
		var p := Vector2(x, y)
		if player == null:
			return p
		if player.global_position.distance_to(p) > safe_radius_around_player:
			return p
	return Vector2(randf_range(room_min.x, room_max.x), randf_range(room_min.y, room_max.y))


func _find_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var players := tree.get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D


func _on_enemy_defeated() -> void:
	if GameManager:
		GameManager.enemies_killed += 1
	# enemies_remaining is now advisory only (used for HUD/stats). The real
	# wave-end gate is the actual count of live enemies in the scene — the manual
	# counter only ever knew about a wave's INITIAL spawn, so dynamically-born
	# foes (brood-mother hatchlings, boss minions) decremented it without ever
	# being added, draining it to 0 while real enemies were still alive. That
	# cleared the wave early and let survivors keep fighting during the merchant
	# break ("волны продолжаются в магазине").
	enemies_remaining = max(0, enemies_remaining - 1)
	# Arena waves are timer-driven (survival); kills feed the hidden event counter instead
	# of ending the wave.
	if arena_mode:
		if combat_active and not boss_active:
			_wave_kills += 1
			var thresh: int = GameManager.arena_event_threshold if GameManager else 12
			if thresh > 0 and _wave_kills % thresh == 0:
				_trigger_arena_event()
		return
	if combat_active and _live_enemy_count() == 0:
		_end_wave()


# Count enemies still alive and dangerous. The just-killed enemy already set
# `dead = true` at the top of its _die() before emitting enemy_defeated, so it is
# correctly excluded here. Puppet copies (multiplayer clients) never drive wave
# state on the host, so they're skipped too.
func _live_enemy_count() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e.get("dead") == true:
			continue
		if e.get("is_puppet") == true:
			continue
		n += 1
	return n


func _end_wave() -> void:
	combat_active = false
	if GameManager:
		GameManager.wave_cleared.emit(current_wave)
	_broadcast_wave_cleared(current_wave)
	_switch_to_explore_music()
	_spawn_loot_chest()
	# Decide between merchant-break (portal-gated) and timed auto-advance.
	var is_merchant_wave: bool = (
		(BossDatabase.boss_for_wave(current_wave) == "") and (current_wave % 3 == 0)
	)
	if is_merchant_wave:
		_spawn_merchant_and_portal()
	else:
		var t := get_tree().create_timer(wave_break)
		t.timeout.connect(_start_next_wave)


func _spawn_merchant_and_portal() -> void:
	if not is_inside_tree():
		return
	portal_break_active = true
	# Merchant: center-left of arena.
	var center: Vector2 = (room_min + room_max) * 0.5
	var merchant_pos: Vector2 = center + Vector2(-180, 0)
	var portal_pos: Vector2 = center + Vector2(220, 0)
	var m: Node2D = MERCHANT_SCENE.instantiate()
	get_tree().current_scene.add_child(m)
	m.global_position = merchant_pos
	current_merchant = m
	# Portal: center-right of arena.
	var portal: Node2D = PORTAL_SCENE.instantiate()
	get_tree().current_scene.add_child(portal)
	portal.global_position = portal_pos
	current_portal = portal
	if portal.has_signal("activated"):
		portal.connect("activated", _on_portal_activated)
	# Multiplayer host — replicate the merchant + portal to clients.
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_merchant_spawn"):
			ns.call("broadcast_merchant_spawn", merchant_pos)
			ns.call("broadcast_portal_spawn", portal_pos)


func _on_portal_activated() -> void:
	if not portal_break_active:
		return
	portal_break_active = false
	# Despawn merchant immediately (portal handles its own fade).
	if (
		current_merchant
		and is_instance_valid(current_merchant)
		and current_merchant.has_method("leave")
	):
		current_merchant.call("leave")
	current_merchant = null
	current_portal = null
	# Tell clients to dispose of their merchant + portal copies before the
	# next wave_started message lands.
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_portal_consumed"):
			ns.call("broadcast_portal_consumed")
	# Tiny delay so the portal whoosh plays before the next wave kicks off.
	var t := get_tree().create_timer(0.7)
	t.timeout.connect(_start_next_wave)


# Called by NetSync on the host when a CLIENT portal triggers activation.
func portal_activate_from_client() -> void:
	_on_portal_activated()


# ── Arena cycle: pillar choice → 30s timed wave → … → finale boss → reward ─────
func _arena_batch_size(wave: int) -> int:
	return 10 + 5 * maxi(0, wave - 1)


func _make_arena_timer(wait: float, one_shot: bool, cb: Callable) -> Timer:
	var t := Timer.new()
	t.wait_time = wait
	t.one_shot = one_shot
	t.autostart = true
	add_child(t)
	t.timeout.connect(cb)
	return t


# Mandatory pre-wave pillar choice (1 of 3). After the last wave → the finale boss.
func _arena_open_pillars() -> void:
	if not _arena_center_set:
		var p := _find_player()
		_arena_center = p.global_position if p else (room_min + room_max) * 0.5
		_arena_center_set = true
	if current_wave >= arena_waves:
		_arena_start_boss()
		return
	_arena_choosing = true
	# 4 pillars: green + red guaranteed (never all one colour), 2 more random; + a rare 5th
	# purple. Each green/red rolls one of its three effects. Arranged in a circle.
	var kinds: Array = ["green", "red"]
	for i in 2:
		kinds.append("green" if randf() < 0.5 else "red")
	kinds.shuffle()
	if randf() < ARENA_PURPLE_CHANCE:
		kinds.append("purple")
	var count: int = kinds.size()
	for i in count:
		var k: String = String(kinds[i])
		var eff: String = ""
		var desc: String = ""
		if k == "green":
			eff = String((GREEN_EFFECTS.keys() as Array)[randi() % GREEN_EFFECTS.size()])
			desc = String(GREEN_EFFECTS[eff])
		elif k == "red":
			eff = String((RED_EFFECTS.keys() as Array)[randi() % RED_EFFECTS.size()])
			desc = String(RED_EFFECTS[eff])
		else:
			desc = "★ PURPLE — boss swarm, huge coin ★"
		var pillar := ArenaPillar.new()
		pillar.configure(k, eff, desc)
		pillar.chosen.connect(_arena_on_pillar_chosen)
		get_tree().current_scene.add_child(pillar)
		var ang: float = TAU * float(i) / float(count)
		var pos: Vector2 = _arena_center + Vector2(cos(ang), sin(ang)) * 240.0
		pos.x = clampf(pos.x, room_min.x + 80.0, room_max.x - 80.0)
		pos.y = clampf(pos.y, room_min.y + 120.0, room_max.y - 80.0)
		pillar.global_position = pos
		_arena_pillars.append(pillar)
	if GameManager:
		GameManager.notice.emit(
			"Choose a pillar to begin wave %d of %d" % [current_wave + 1, arena_waves],
			Color(0.95, 0.8, 0.4)
		)


# Apply a chosen pillar's effect. Effects ACCUMULATE for the whole arena (GameManager fields,
# wiped on exit unless arena_carryover) — picking more pillars stacks them.
func _arena_on_pillar_chosen(kind: String, effect: String) -> void:
	if not _arena_choosing:
		return  # only the first pick counts
	_arena_choosing = false
	for p in _arena_pillars:
		if is_instance_valid(p):
			p.queue_free()
	_arena_pillars.clear()
	_wave_purple = kind == "purple"
	if GameManager:
		match kind:
			"green":
				match effect:
					"might":
						GameManager.arena_buff_dmg += 0.15
					"swift":
						GameManager.arena_buff_spd += 0.12
					"fortune":
						GameManager.heal_player(40)
						GameManager.add_xp(30, false)
				_apply_arena_buffs()
			"red":
				match effect:
					"brutality":
						GameManager.arena_enemy_power += 0.4
					"frenzy":
						GameManager.arena_event_threshold = maxi(2, GameManager.arena_event_threshold - 3)
					"horde":
						GameManager.arena_spawn_bonus += 0.5
		GameManager.arena_award(int(ARENA_PILLAR_CURRENCY.get(kind, 8)))
	_start_arena_wave()


# Re-assert the accumulated green buffs on the current player (covers carryover into a new
# arena scene too). apply_buff keeps the strongest, so re-applying the running total is safe.
func _apply_arena_buffs() -> void:
	if GameManager == null:
		return
	if GameManager.arena_buff_dmg <= 1.0 and GameManager.arena_buff_spd <= 1.0:
		return
	var pl := _find_player()
	if pl and pl.has_method("apply_buff"):
		pl.call("apply_buff", 900.0, GameManager.arena_buff_dmg, GameManager.arena_buff_spd)


func _start_arena_wave() -> void:
	current_wave += 1
	combat_active = true
	_wave_kills = 0
	_apply_arena_buffs()  # keep accumulated green buffs active each wave
	if GameManager:
		GameManager.wave_started.emit(current_wave)
	_broadcast_wave_started(current_wave)
	_switch_to_combat_music()
	_arena_batches_left = ARENA_BATCHES
	_spawn_arena_batch()  # first batch immediately
	_arena_batch_timer = _make_arena_timer(ARENA_BATCH_INTERVAL, false, _spawn_arena_batch)
	_arena_wave_timer = _make_arena_timer(ARENA_WAVE_DURATION, true, _end_arena_wave)
	_wave_end_msec = Time.get_ticks_msec() + int(ARENA_WAVE_DURATION * 1000.0)
	_arena_tick_timer = _make_arena_timer(1.0, false, _arena_tick)
	_arena_tick()


func _arena_tick() -> void:
	if not combat_active or not arena_mode:
		return
	var left: int = int(ceil(float(_wave_end_msec - Time.get_ticks_msec()) / 1000.0))
	if GameManager:
		GameManager.arena_timer.emit(maxi(0, left))


func _spawn_arena_batch() -> void:
	if not combat_active or not arena_mode:
		return
	_arena_batches_left -= 1
	var host_auth: bool = NetManager == null or not NetManager.is_multiplayer or NetManager.is_host
	if host_auth:
		var m: Dictionary = _arena_wave_mults()
		if _wave_purple:
			# Purple wave: 3 mini-bosses (fully-affixed elites) per batch, each dropping a lot
			# of local currency when killed.
			var p := _find_player()
			var center: Vector2 = p.global_position if p else _arena_center
			for i in 3:
				var ang: float = TAU * float(i) / 3.0 + randf()
				var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * 240.0
				pos.x = clampf(pos.x, room_min.x + 80.0, room_max.x - 80.0)
				pos.y = clampf(pos.y, room_min.y + 120.0, room_max.y - 80.0)
				var e := _spawn_one("succubus", float(m["hp"]) * 3.0, float(m["dmg"]) * 1.4, float(m["xp"]) * 2.0, float(m["gold"]) * 2.0, EnemyAffixes.roll(3), pos)
				if e:
					e.set_meta("arena_event_reward", ARENA_PURPLE_BOSS_CURRENCY)
		else:
			# Horde (red) inflates the batch size.
			var n: int = int(round(float(_arena_batch_size(current_wave)) * (1.0 + GameManager.arena_spawn_bonus)))
			for i in n:
				var t: String = String(ARENA_BATCH_TYPES[randi() % ARENA_BATCH_TYPES.size()])
				_spawn_one(t, float(m["hp"]), float(m["dmg"]), float(m["xp"]), float(m["gold"]))
	if _arena_batches_left <= 0 and _arena_batch_timer and is_instance_valid(_arena_batch_timer):
		_arena_batch_timer.stop()


func _arena_wave_mults() -> Dictionary:
	var diff: int = GameManager.run_difficulty if GameManager else 0
	var d_hp: float = Difficulty.value(diff, "enemy_hp_mult", 1.0)
	var d_dmg: float = Difficulty.value(diff, "enemy_dmg_mult", 1.0)
	var d_reward: float = Difficulty.value(diff, "reward_mult", 1.0)
	var power: float = GameManager.arena_enemy_power if GameManager else 1.0
	return {
		"hp": (1.0 + 0.08 * float(current_wave - 1)) * d_hp * power,
		"dmg": (1.0 + 0.05 * float(int(floor(float(current_wave - 1) / 2.0)))) * d_dmg * power,
		"xp": (1.0 + 0.12 * float(current_wave - 1)) * d_reward,
		"gold": (1.0 + 0.10 * float(current_wave - 1)) * d_reward,
	}


# Hidden-kill-counter event: randomly a mini-boss, a destructible tower, or a clear-the-zone.
func _trigger_arena_event() -> void:
	var host_auth: bool = NetManager == null or not NetManager.is_multiplayer or NetManager.is_host
	if not host_auth:
		return
	var p := _find_player()
	var center: Vector2 = p.global_position if p else _arena_center
	match randi() % 3:
		0:
			_event_miniboss(center)
		1:
			_event_tower(center)
		_:
			_event_zone(center)


func _event_pos(center: Vector2, dist: float) -> Vector2:
	var ang: float = randf() * TAU
	var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * dist
	pos.x = clampf(pos.x, room_min.x + 80.0, room_max.x - 80.0)
	pos.y = clampf(pos.y, room_min.y + 120.0, room_max.y - 80.0)
	return pos


func _event_miniboss(center: Vector2) -> void:
	var m: Dictionary = _arena_wave_mults()
	var e := _spawn_one(
		"cultist", float(m["hp"]) * 2.2, float(m["dmg"]) * 1.3, float(m["xp"]) * 2.0, float(m["gold"]) * 2.0, EnemyAffixes.roll(3), _event_pos(center, 260.0)
	)
	if e:
		e.set_meta("arena_event_reward", ARENA_EVENT_CURRENCY)
	if GameManager:
		GameManager.notice.emit("⚠ EVENT — slay the mini-boss for %d coin!" % ARENA_EVENT_CURRENCY, Color(1.0, 0.5, 0.3))


# A destructible tower = a stationary, harmless, very-tough enemy that pays out when broken.
func _event_tower(center: Vector2) -> void:
	var m: Dictionary = _arena_wave_mults()
	var e := _spawn_one("skeleton", float(m["hp"]) * 6.0, 0.0, float(m["xp"]) * 2.0, float(m["gold"]) * 2.0, [], _event_pos(center, 300.0))
	if e:
		e.set("move_speed", 0.0)
		e.set("attack_damage", 0)
		e.set("detection_range", 0.0)
		e.set_meta("arena_event_reward", ARENA_EVENT_CURRENCY + 20)
		if e is CanvasItem:
			(e as CanvasItem).modulate = Color(0.55, 0.8, 1.1)
	if GameManager:
		GameManager.notice.emit("⚠ EVENT — destroy the tower for %d coin!" % (ARENA_EVENT_CURRENCY + 20), Color(0.5, 0.8, 1.0))


func _event_zone(center: Vector2) -> void:
	var zone := ArenaZone.new()
	get_tree().current_scene.add_child(zone)
	zone.global_position = _event_pos(center, 180.0)


# Bonus currency when a tagged event mini-boss is actually killed (not silently despawned).
func _on_any_enemy_died(ev) -> void:
	if not arena_mode or ev == null:
		return
	var actor = ev.actor
	if actor and is_instance_valid(actor) and actor.has_meta("arena_event_reward"):
		var reward: int = int(actor.get_meta("arena_event_reward", 0))
		actor.remove_meta("arena_event_reward")
		if GameManager:
			GameManager.arena_award(reward)
			GameManager.notice.emit("Event cleared!  +%d coin" % reward, Color(0.45, 0.9, 0.5))


func _end_arena_wave() -> void:
	if not arena_mode or not combat_active:
		return
	combat_active = false
	for tmr in [_arena_batch_timer, _arena_wave_timer, _arena_tick_timer]:
		if tmr and is_instance_valid(tmr):
			tmr.queue_free()
	_arena_batch_timer = null
	_arena_wave_timer = null
	_arena_tick_timer = null
	if GameManager:
		GameManager.wave_cleared.emit(current_wave)
		GameManager.arena_timer.emit(-1)  # hide the countdown
	# Enemy power / buffs PERSIST for the whole arena — not reset between waves.
	_broadcast_wave_cleared(current_wave)
	_despawn_arena_survivors()  # leftover enemies vanish and give nothing — kill them in time
	_switch_to_explore_music()
	if current_wave >= arena_waves:
		_arena_start_boss()
	else:
		_arena_open_pillars()


# Wipe any enemies still alive at the end of an arena wave (no XP/gold/drops). Skips
# puppets (clients mirror the host's despawns through normal death sync).
func _despawn_arena_survivors() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not bool(e.get("is_puppet")) and e.has_method("despawn_silent"):
			e.call("despawn_silent")


# Finale: a single buffed boss after the last wave. Its defeat shows the reward screen.
func _arena_start_boss() -> void:
	var boss_id: String = BossDatabase.boss_for_wave(10)
	if boss_id == "":
		boss_id = "crimson_matron"
	if GameManager:
		GameManager.notice.emit("The arena's champion arrives!", Color(1.0, 0.35, 0.3))
	# High effective wave + difficulty → a beefy finale boss.
	var eff: int = current_wave + 4 + (GameManager.run_difficulty if GameManager else 0) * 2
	_spawn_boss(boss_id, eff)


# Reward caches by rising cost → bigger scale, brighter colour, better loot.
const REWARD_CACHES := [
	{"label": "Small Cache", "cost": 30, "items": 1, "ilvl": 0, "scale": 1.0, "color": Color(0.40, 0.85, 0.50)},
	{"label": "Large Cache", "cost": 70, "items": 2, "ilvl": 3, "scale": 1.35, "color": Color(0.40, 0.62, 1.0)},
	{"label": "Grand Cache", "cost": 130, "items": 3, "ilvl": 6, "scale": 1.7, "color": Color(0.78, 0.42, 1.0)},
]


# Arena cleared: lay out the physical reward chests in a row (priced caches + a small dump
# coffer) and an exit portal ABOVE them (so it doesn't block them). The portal returns the
# party to the run map.
func _finish_arena() -> void:
	if not is_inside_tree():
		return
	var center: Vector2 = _arena_center if _arena_center_set else (room_min + room_max) * 0.5
	var n: int = REWARD_CACHES.size() + 1  # caches + dump
	var spacing: float = 165.0
	var start_x: float = center.x - spacing * float(n - 1) * 0.5
	var idx: int = 0
	for c in REWARD_CACHES:
		var chest := ArenaChest.new()
		var cfg: Dictionary = (c as Dictionary).duplicate()
		cfg["kind"] = "cache"
		cfg["wave_hint"] = current_wave
		chest.configure(cfg)
		get_tree().current_scene.add_child(chest)
		chest.global_position = _clamp_in_room(Vector2(start_x + spacing * float(idx), center.y))
		idx += 1
	var dump := ArenaChest.new()
	dump.configure({"kind": "dump", "label": "Coffer", "scale": 0.7, "color": Color(1.0, 0.84, 0.30)})
	get_tree().current_scene.add_child(dump)
	dump.global_position = _clamp_in_room(Vector2(start_x + spacing * float(idx), center.y))
	# Exit portal, placed well above the chest row so it never overlaps them.
	var portal: Node2D = PORTAL_SCENE.instantiate()
	get_tree().current_scene.add_child(portal)
	portal.global_position = _clamp_in_room(center + Vector2(0, -240.0))
	if portal.has_signal("activated"):
		portal.connect("activated", _on_arena_reward_portal)
	if GameManager:
		GameManager.notice.emit("Arena cleared! Open the chests, then take the portal to the map.", Color(1.0, 0.86, 0.5))


func _clamp_in_room(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, room_min.x + 80.0, room_max.x - 80.0),
		clampf(pos.y, room_min.y + 120.0, room_max.y - 80.0)
	)


func _on_arena_reward_portal() -> void:
	if GameManager:
		GameManager.clear_run_node()  # → run_node_cleared → RunFlow returns to the map


# ─────────────────────────────────────────────────────────────────────────────
# Host → client wave broadcasts. No-ops in solo / on clients.
func _broadcast_wave_started(wave: int) -> void:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return
	var ns := _find_net_sync()
	if ns and ns.has_method("broadcast_wave_started"):
		ns.call("broadcast_wave_started", wave)


func _broadcast_wave_cleared(wave: int) -> void:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return
	var ns := _find_net_sync()
	if ns and ns.has_method("broadcast_wave_cleared"):
		ns.call("broadcast_wave_cleared", wave)


func _spawn_loot_chest() -> void:
	# Drop a chest. In solo: one chest near the player.
	# In multiplayer (host): one chest PER player, anchored near each player.
	# Non-host in multiplayer: do nothing — host broadcasts via NetSync.
	if not is_inside_tree():
		return
	if NetManager and NetManager.is_multiplayer and not NetManager.is_host:
		return
	var chest_scene_path: String = "res://scenes/pickups/loot_chest.tscn"
	if not ResourceLoader.exists(chest_scene_path):
		return
	var chest_scene: PackedScene = load(chest_scene_path) as PackedScene
	if chest_scene == null:
		return
	# Multiplayer host: spawn one chest per player slot, broadcast to peers.
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var local_player := _find_player()
		var base_pos: Vector2 = (
			(local_player as Node2D).global_position
			if local_player
			else (room_min + room_max) * 0.5
		)
		for pid in NetManager.max_players:
			var angle: float = float(pid) / float(max(1, NetManager.max_players)) * TAU
			var pos: Vector2 = base_pos + Vector2(cos(angle), sin(angle)) * 160.0
			# Spawn local for pid == local_player_id; broadcast for others.
			if pid == NetManager.local_player_id:
				var chest: Node2D = chest_scene.instantiate()
				get_tree().current_scene.add_child(chest)
				chest.global_position = pos
				if chest.has_method("configure"):
					chest.call("configure", current_wave)
			(
				NetManager
				. send(
					"chest_spawn",
					{
						"owner": pid,
						"wave": current_wave,
						"x": pos.x,
						"y": pos.y,
					}
				)
			)
		return
	# Solo path.
	var chest: Node2D = chest_scene.instantiate()
	get_tree().current_scene.call_deferred("add_child", chest)
	var player := _find_player()
	if player:
		var offset: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * 140.0
		chest.global_position = (player as Node2D).global_position + offset
	else:
		chest.global_position = (room_min + room_max) * 0.5
	if chest.has_method("configure"):
		chest.call("configure", current_wave)


func _spawn_boss(boss_id: String, wave_override: int = -1) -> void:
	# Spawn the boss in the center of the room.
	var pos: Vector2 = (room_min + room_max) * 0.5
	var boss: Node2D = BOSS_SCENE.instantiate()
	if get_parent():
		get_parent().add_child(boss)
	else:
		get_tree().current_scene.add_child(boss)
	boss.global_position = pos
	if boss.has_method("configure"):
		boss.call("configure", boss_id, wave_override if wave_override > 0 else current_wave)
	# Host: broadcast boss spawn.
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("register_boss"):
			ns.call("register_boss", boss)
	current_boss = boss
	boss_active = true
	combat_active = true
	enemies_remaining = 1  # The boss counts as a single foe.
	if GameManager:
		GameManager.wave_started.emit(current_wave)
	_broadcast_wave_started(current_wave)
	_switch_to_boss_music()
	# Wire defeat signal so we know when the wave ends.
	if boss.has_signal("boss_defeated"):
		boss.connect("boss_defeated", _on_boss_defeated)
	# Notify HUD via game manager.
	var hud := _find_hud()
	if hud and hud.has_method("show_boss_bar"):
		var boss_data: Dictionary = BossDatabase.get_boss(boss_id)
		hud.call("show_boss_bar", String(boss_data.get("name", "BOSS")), boss)


func _on_boss_defeated(boss_id: String, reward: String) -> void:
	# End the boss wave like a normal wave but with guaranteed loot upgrade.
	boss_active = false
	combat_active = false
	current_boss = null
	if GameManager:
		GameManager.wave_cleared.emit(current_wave)
	_broadcast_wave_cleared(current_wave)
	_switch_to_explore_music()
	var hud := _find_hud()
	if hud and hud.has_method("hide_boss_bar"):
		hud.call("hide_boss_bar")
	# Avoid "unused" warning.
	var _ignore := boss_id
	# Arena finale boss → reward screen (spend local currency), then back to the map.
	if arena_mode:
		_finish_arena()
		return
	_spawn_boss_loot(reward)
	var t := get_tree().create_timer(wave_break)
	t.timeout.connect(_start_next_wave)


func _spawn_boss_loot(reward: String) -> void:
	if not is_inside_tree():
		return
	var chest_scene_path: String = "res://scenes/pickups/loot_chest.tscn"
	if not ResourceLoader.exists(chest_scene_path):
		return
	var chest_scene: PackedScene = load(chest_scene_path) as PackedScene
	if chest_scene == null:
		return
	var center: Vector2 = (room_min + room_max) * 0.5
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		for pid in NetManager.max_players:
			var angle: float = float(pid) / float(max(1, NetManager.max_players)) * TAU
			var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * 140.0
			var chest: Node2D = chest_scene.instantiate()
			get_tree().current_scene.add_child(chest)
			chest.global_position = pos
			if chest.has_method("configure"):
				chest.call("configure", current_wave)
			chest.set_meta("forced_rarity", reward)
			NetManager.send("chest_spawn", {
				"owner": pid,
				"wave": current_wave,
				"x": pos.x,
				"y": pos.y,
				"forced_rarity": reward,
			})
		return
	var chest: Node2D = chest_scene.instantiate()
	get_tree().current_scene.add_child(chest)
	chest.global_position = center
	if chest.has_method("configure"):
		chest.call("configure", current_wave)
	chest.set_meta("forced_rarity", reward)


func _find_hud() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.find_child("HUD", true, false)


func _switch_to_boss_music() -> void:
	combat_music_on = true
	if AudioManager:
		var music: AudioStream = (
			load("res://assets/audio/music/music_boss_music_boss.mp3") as AudioStream
		)
		if music:
			AudioManager.play_music(music, -8.0)


func _switch_to_combat_music() -> void:
	if combat_music_on:
		return
	combat_music_on = true
	if AudioManager:
		var music: AudioStream = (
			load("res://assets/audio/music/music_combat_dungeon_combat.mp3") as AudioStream
		)
		if music:
			AudioManager.play_music(music, -10.0)


func _switch_to_explore_music() -> void:
	if not combat_music_on:
		return
	combat_music_on = false
	if AudioManager:
		var music: AudioStream = (
			load("res://assets/audio/music/music_exploration_dungeon_explore.mp3") as AudioStream
		)
		if music:
			AudioManager.play_music(music, -12.0)
