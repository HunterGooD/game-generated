extends Node

# Enemy spawner — escalating waves with per-wave stat scaling.

const ENEMY_SCENE: PackedScene = preload("res://scenes/entities/enemy.tscn")
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


func _ready() -> void:
	if GameManager:
		GameManager.enemy_defeated.connect(_on_enemy_defeated)
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

	# Stat / xp scaling factors.
	var hp_mult: float = 1.0 + 0.08 * float(current_wave - 1)
	var dmg_mult: float = 1.0 + 0.05 * float(int(floor(float(current_wave - 1) / 2.0)))
	var xp_mult: float = 1.0 + 0.12 * float(current_wave - 1)
	var gold_mult: float = 1.0 + 0.10 * float(current_wave - 1)

	var spawned: int = 0
	for type_id in counts.keys():
		var n: int = int(counts[type_id])
		for i in n:
			_spawn_one(String(type_id), hp_mult, dmg_mult, xp_mult, gold_mult)
			spawned += 1
	enemies_remaining = spawned
	combat_active = true
	if GameManager:
		GameManager.wave_started.emit(current_wave)
	_broadcast_wave_started(current_wave)
	_switch_to_combat_music()


func _spawn_one(
	type_id: String, hp_mult: float, dmg_mult: float, xp_mult: float, gold_mult: float
) -> void:
	if not ENEMY_TYPES.has(type_id):
		return
	var cfg: Dictionary = ENEMY_TYPES[type_id].duplicate(true)
	cfg["max_hp"] = int(round(float(cfg["max_hp"]) * hp_mult))
	cfg["attack_damage"] = int(round(float(cfg["attack_damage"]) * dmg_mult))
	cfg["xp_value"] = int(round(float(cfg["xp_value"]) * xp_mult))
	cfg["gold_min"] = int(round(float(cfg["gold_min"]) * gold_mult))
	cfg["gold_max"] = int(round(float(cfg["gold_max"]) * gold_mult))
	var pos: Vector2 = _pick_spawn_pos()
	var e := ENEMY_SCENE.instantiate()
	if get_parent():
		get_parent().add_child(e)
	else:
		get_tree().current_scene.add_child(e)
	e.global_position = pos
	if e.has_method("configure"):
		e.call("configure", cfg)
	# Multiplayer host: assign network id + broadcast spawn so clients render
	# the same enemy.
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("register_enemy"):
			ns.call("register_enemy", e)


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


func _spawn_boss(boss_id: String) -> void:
	# Spawn the boss in the center of the room.
	var pos: Vector2 = (room_min + room_max) * 0.5
	var boss: Node2D = BOSS_SCENE.instantiate()
	if get_parent():
		get_parent().add_child(boss)
	else:
		get_tree().current_scene.add_child(boss)
	boss.global_position = pos
	if boss.has_method("configure"):
		boss.call("configure", boss_id, current_wave)
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
	_spawn_boss_loot(reward)
	var t := get_tree().create_timer(wave_break)
	t.timeout.connect(_start_next_wave)
	# Avoid "unused" warning.
	var _ignore := boss_id


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
