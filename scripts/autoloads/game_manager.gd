extends Node

# GameManager — global game state. Tracks player stats, class, score, and game flow.

signal player_stats_changed
signal player_died
# Co-op down/revive. `player_downed_changed` fires when the local player enters
# or leaves the downed (bleed-out) state; `player_revived` fires on a successful
# revive. Full death still goes through `player_died`.
signal player_downed_changed(is_downed: bool)
signal player_revived
signal player_levelled_up(new_level: int)
signal spec_path_offered
signal spec_path_chosen(path_id: String)
signal gold_changed(new_gold: int)
signal enemy_defeated
signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal class_selected(class_id: String)
signal xp_gained(amount: int)

# Class catalog — base stats and per-level growth.
const CLASSES := {
	"barbarian":
	{
		"display": "Barbarian",
		"primary": "strength",
		"primary_label": "Strength",
		"description": "Brutal close-quarters berserker. Hard to kill, hard to outhit.",
		"portrait": "res://assets/sprites/items/portrait_barbarian.png",
		"sprite_idle": "res://assets/sprites/characters/barbarian/barbarian_idle.png",
		"sprite_walk": "res://assets/sprites/characters/barbarian/barbarian_walk.png",
		"sprite_attack": "res://assets/sprites/characters/barbarian/barbarian_attack.png",
		"basic_attack": "melee",
		"skill_ids": ["whirlwind", "leap_slam", "battle_cry", "earthquake"],
		"dash_kind": "barbarian",
		"base":
		{
			"max_hp": 160,
			"max_mana": 50,
			"damage": 18,
			"move_speed": 200.0,
			"crit_chance": 0.05,
			"crit_damage": 1.5,
			"strength": 14,
			"dexterity": 6,
			"intelligence": 4,
		},
		"per_level":
		{
			"max_hp": 16,
			"max_mana": 4,
			"damage": 3,
			"move_speed": 0.0,
			"crit_chance": 0.002,
			"crit_damage": 0.02,
			"strength": 3,
			"dexterity": 1,
			"intelligence": 0,
		},
		"color": Color(0.85, 0.25, 0.2, 1),
	},
	"rogue":
	{
		"display": "Rogue",
		"primary": "dexterity",
		"primary_label": "Dexterity",
		"description": "Lightning-fast knife-thrower. Devastating crits, paper-thin defense.",
		"portrait": "res://assets/sprites/items/portrait_rogue.png",
		"sprite_idle": "res://assets/sprites/characters/rogue/rogue_idle.png",
		"sprite_walk": "res://assets/sprites/characters/rogue/rogue_walk.png",
		"sprite_attack": "res://assets/sprites/characters/rogue/rogue_attack.png",
		"basic_attack": "dagger",
		"skill_ids": ["caltrops", "smoke_bomb", "poison_vial", "fan_of_knives"],
		"dash_kind": "rogue",
		"base":
		{
			"max_hp": 80,
			"max_mana": 70,
			"damage": 14,
			"move_speed": 280.0,
			"crit_chance": 0.20,
			"crit_damage": 2.0,
			"strength": 6,
			"dexterity": 14,
			"intelligence": 6,
		},
		"per_level":
		{
			"max_hp": 6,
			"max_mana": 6,
			"damage": 2,
			"move_speed": 2.0,
			"crit_chance": 0.01,
			"crit_damage": 0.05,
			"strength": 1,
			"dexterity": 3,
			"intelligence": 0,
		},
		"color": Color(0.9, 0.5, 0.2, 1),
	},
	"mage":
	{
		"display": "Mage",
		"primary": "intelligence",
		"primary_label": "Intelligence",
		"description": "Spell-slinger from the ruin order. Fragile body, devastating mana pool.",
		"portrait": "res://assets/sprites/items/portrait_mage.png",
		"sprite_idle": "res://assets/sprites/characters/archmage/archmage_idle.png",
		"sprite_walk": "res://assets/sprites/characters/archmage/archmage_walk.png",
		"sprite_attack": "res://assets/sprites/characters/archmage/archmage_attack.png",
		"basic_attack": "bolt",
		"skill_ids": ["fire_wall", "ice_bolt", "chain_lightning", "meteor"],
		"dash_kind": "mage",
		"base":
		{
			"max_hp": 95,
			"max_mana": 140,
			"damage": 16,
			"move_speed": 220.0,
			"crit_chance": 0.07,
			"crit_damage": 1.6,
			"strength": 5,
			"dexterity": 6,
			"intelligence": 14,
		},
		"per_level":
		{
			"max_hp": 8,
			"max_mana": 12,
			"damage": 2,
			"move_speed": 0.0,
			"crit_chance": 0.004,
			"crit_damage": 0.03,
			"strength": 0,
			"dexterity": 1,
			"intelligence": 3,
		},
		"color": Color(0.7, 0.25, 0.85, 1),
	},
	"stormcaller":
	{
		"display": "Stormcaller",
		"primary": "dexterity",
		"primary_label": "Voltage",
		"description":
		"Lightning-fueled melee mage. Chains bolts between foes, dashes through storms, calls strikes from the sky.",
		"portrait": "res://assets/sprites/items/portrait_stormcaller.webp",
		"sprite_idle": "res://assets/sprites/characters/stormcaller_idle.png",
		"sprite_walk": "res://assets/sprites/characters/stormcaller_walk.png",
		"sprite_attack": "res://assets/sprites/characters/stormcaller_attack.png",
		"basic_attack": "bolt",
		"skill_ids":
		["storm_chain_bolt", "storm_step", "storm_sky_strike", "storm_static_discharge"],
		"dash_kind": "rogue",
		"base":
		{
			"max_hp": 105,
			"max_mana": 120,
			"damage": 15,
			"move_speed": 245.0,
			"crit_chance": 0.10,
			"crit_damage": 1.6,
			"strength": 7,
			"dexterity": 12,
			"intelligence": 11,
		},
		"per_level":
		{
			"max_hp": 9,
			"max_mana": 10,
			"damage": 2,
			"move_speed": 1.0,
			"crit_chance": 0.004,
			"crit_damage": 0.03,
			"strength": 1,
			"dexterity": 2,
			"intelligence": 2,
		},
		"color": Color(0.45, 0.75, 1.0, 1),
	},
	"hexen":
	{
		"display": "Crimson Hexen",
		"primary": "intelligence",
		"primary_label": "Hexcraft",
		"description":
		"Mistress of marks and chains. Marks foes, links them with crimson tethers, then detonates the whole pack.",
		"portrait": "res://assets/sprites/items/portrait_crimson_hexen.webp",
		"sprite_idle": "res://assets/sprites/characters/crimson_hexen_idle.png",
		"sprite_walk": "res://assets/sprites/characters/crimson_hexen_walk.png",
		"sprite_attack": "res://assets/sprites/characters/crimson_hexen_attack.png",
		"basic_attack": "bolt",
		"skill_ids":
		["hexen_hex_mark", "hexen_blood_whip", "hexen_soul_tether", "hexen_crimson_ritual"],
		"dash_kind": "rogue",
		"base":
		{
			"max_hp": 95,
			"max_mana": 130,
			"damage": 14,
			"move_speed": 240.0,
			"crit_chance": 0.12,
			"crit_damage": 1.7,
			"strength": 6,
			"dexterity": 10,
			"intelligence": 13,
		},
		"per_level":
		{
			"max_hp": 8,
			"max_mana": 11,
			"damage": 2,
			"move_speed": 1.0,
			"crit_chance": 0.005,
			"crit_damage": 0.035,
			"strength": 0,
			"dexterity": 2,
			"intelligence": 2,
		},
		"color": Color(0.92, 0.18, 0.28, 1),
	},
	"necromancer":
	{
		"display": "Necromancer",
		"primary": "intelligence",
		"primary_label": "Death",
		"description":
		"Master of bone and curse. Raises soldiers and tanks from the dust, then sacrifices his own blood to empower them.",
		"portrait": "res://assets/sprites/items/portrait_necromancer.webp",
		"sprite_idle": "res://assets/sprites/characters/necromancer_idle.png",
		"sprite_walk": "res://assets/sprites/characters/necromancer_walk.png",
		"sprite_attack": "res://assets/sprites/characters/necromancer_attack.png",
		"basic_attack": "bolt",
		"skill_ids":
		["necro_raise_skeleton", "necro_raise_knight", "necro_blood_pact", "necro_death_pulse"],
		"dash_kind": "mage",
		"base":
		{
			"max_hp": 110,
			"max_mana": 130,
			"damage": 14,
			"move_speed": 215.0,
			"crit_chance": 0.06,
			"crit_damage": 1.6,
			"strength": 6,
			"dexterity": 7,
			"intelligence": 13,
		},
		"per_level":
		{
			"max_hp": 10,
			"max_mana": 11,
			"damage": 2,
			"move_speed": 0.0,
			"crit_chance": 0.003,
			"crit_damage": 0.025,
			"strength": 0,
			"dexterity": 1,
			"intelligence": 3,
		},
		"color": Color(0.55, 0.25, 0.75, 1),
	},
	"druid":
	{
		"display": "Druid",
		"primary": "intelligence",
		"primary_label": "Wisdom",
		"description":
		"Wild-shaper. Wears wolf or bear flesh, calls down stone armor, summons spirit beasts.",
		"portrait": "res://assets/sprites/items/portrait_druid.webp",
		"sprite_idle": "res://assets/sprites/characters/druid_human_idle.png",
		"sprite_walk": "res://assets/sprites/characters/druid_human_walk.png",
		"sprite_attack": "res://assets/sprites/characters/druid_human_attack.png",
		"basic_attack": "claw",
		"skill_ids":
		["druid_wolf_form", "druid_bear_form", "druid_stone_armor", "druid_summon_spirit"],
		"dash_kind": "barbarian",
		"base":
		{
			"max_hp": 120,
			"max_mana": 90,
			"damage": 16,
			"move_speed": 230.0,
			"crit_chance": 0.08,
			"crit_damage": 1.6,
			"strength": 9,
			"dexterity": 8,
			"intelligence": 12,
		},
		"per_level":
		{
			"max_hp": 12,
			"max_mana": 7,
			"damage": 2,
			"move_speed": 1.0,
			"crit_chance": 0.003,
			"crit_damage": 0.03,
			"strength": 2,
			"dexterity": 1,
			"intelligence": 2,
		},
		"color": Color(0.4, 0.78, 0.32, 1),
	},
}

# Selected class — persists across deaths within a session.
var player_class: String = ""

# Player stats — populated when class is chosen.
var player_level: int = 1
var player_xp: int = 0
var player_xp_to_next: int = 50
# Spec path (V1): chosen once at SpecPaths.SPEC_PATH_LEVEL, reshapes role for the run.
var player_spec_path: String = ""
var _spec_path_offered: bool = false
var player_max_hp: int = 100
var player_hp: int = 100
var player_max_mana: int = 100
var player_mana: float = 100.0
var player_damage: int = 14
var player_move_speed: float = 220.0
var player_crit_chance: float = 0.05
var player_crit_damage: float = 1.5
var player_strength: int = 5
var player_dexterity: int = 5
var player_intelligence: int = 5
var gold: int = 0

# Run state.
var current_floor: int = 1
var is_paused: bool = false
var total_gold_earned: int = 0
var highest_wave: int = 0
var enemies_killed: int = 0
var game_over: bool = false

# Co-op down/revive state (local player). In multiplayer, hitting 0 HP puts the
# player in `player_downed` with a bleed-out countdown instead of an instant
# game over — a living teammate can revive them. Solo play keeps instant death.
const BLEED_OUT_TIME: float = 15.0
const REVIVE_HP_FRACTION: float = 0.5
var player_downed: bool = false
var downed_time_left: float = 0.0


func choose_class(class_id: String) -> void:
	if not CLASSES.has(class_id):
		push_warning("Unknown class: %s" % class_id)
		return
	player_class = class_id
	reset_run()
	class_selected.emit(class_id)


func get_class_data(class_id: String = "") -> Dictionary:
	var key: String = class_id if class_id != "" else player_class
	if CLASSES.has(key):
		return CLASSES[key]
	return CLASSES["mage"]


func reset_run() -> void:
	var data := get_class_data()
	var base: Dictionary = data.get("base", {})
	player_level = 1
	player_xp = 0
	player_xp_to_next = 50
	player_spec_path = ""
	_spec_path_offered = false
	player_max_hp = int(base.get("max_hp", 100))
	player_hp = player_max_hp
	player_max_mana = int(base.get("max_mana", 100))
	player_mana = float(player_max_mana)
	player_damage = int(base.get("damage", 14))
	player_move_speed = float(base.get("move_speed", 220.0))
	player_crit_chance = float(base.get("crit_chance", 0.05))
	player_crit_damage = float(base.get("crit_damage", 1.5))
	player_strength = int(base.get("strength", 5))
	player_dexterity = int(base.get("dexterity", 5))
	player_intelligence = int(base.get("intelligence", 5))
	gold = 0
	total_gold_earned = 0
	highest_wave = 0
	enemies_killed = 0
	game_over = false
	player_downed = false
	downed_time_left = 0.0
	current_floor = 1
	player_stats_changed.emit()
	gold_changed.emit(gold)


func add_gold(amount: int) -> void:
	# Equipment gold-gain multiplier applies to gameplay drops, but we keep
	# loot-chest salvage and direct grants 1:1. Callers can pass already
	# scaled amounts. Default here keeps the raw value.
	gold += amount
	total_gold_earned += amount
	gold_changed.emit(gold)


func add_gold_with_bonus(amount: int) -> void:
	# Used by enemy drops — applies equipment "+X% gold gain" affixes.
	var mult: float = 1.0
	if InventorySystem and InventorySystem.has_method("get_gold_gain_mult"):
		mult = float(InventorySystem.call("get_gold_gain_mult"))
	add_gold(int(round(float(amount) * mult)))


func add_xp(amount: int, apply_mult: bool = true) -> void:
	if amount <= 0:
		return
	# Equipment XP-gain bonus. Skipped for shared co-op party XP (apply_mult=false)
	# so every peer grants the SAME flat amount — otherwise different per-player
	# XP-gain gear would desync levels and break the synchronized level-up.
	if apply_mult and InventorySystem and InventorySystem.has_method("get_xp_gain_mult"):
		amount = int(round(float(amount) * float(InventorySystem.call("get_xp_gain_mult"))))
	player_xp += amount
	xp_gained.emit(amount)
	var data := get_class_data()
	var growth: Dictionary = data.get("per_level", {})
	while player_xp >= player_xp_to_next:
		player_xp -= player_xp_to_next
		player_level += 1
		player_xp_to_next = int(player_xp_to_next * 1.35)
		player_max_hp += int(growth.get("max_hp", 8))
		player_hp = player_max_hp
		player_max_mana += int(growth.get("max_mana", 8))
		player_mana = float(player_max_mana)
		player_damage += int(growth.get("damage", 2))
		player_move_speed += float(growth.get("move_speed", 0.0))
		player_crit_chance += float(growth.get("crit_chance", 0.002))
		player_crit_damage += float(growth.get("crit_damage", 0.02))
		player_strength += int(growth.get("strength", 0))
		player_dexterity += int(growth.get("dexterity", 0))
		player_intelligence += int(growth.get("intelligence", 0))
		player_levelled_up.emit(player_level)
	# Spec path offer — once, when the player reaches the milestone level and their
	# class actually has paths defined. game_world shows the choice overlay after
	# any level-up overlays clear.
	if (
		not _spec_path_offered
		and player_spec_path == ""
		and player_level >= SpecPaths.SPEC_PATH_LEVEL
		and SpecPaths.paths_for(player_class).size() > 0
	):
		_spec_path_offered = true
		spec_path_offered.emit()
	player_stats_changed.emit()


# Apply a chosen spec path's flat stat profile (V1). Per-player in co-op — each
# player picks their own role. Idempotent guard: only the first valid choice sticks.
func choose_spec_path(path_id: String) -> void:
	if player_spec_path != "":
		return
	var stats: Dictionary
	if path_id == SpecPaths.MORTAL_ID:
		# Decline ascension — no R/passive/transforms, just the base-stat bump.
		stats = SpecPaths.MORTAL_STATS
	else:
		var p: Dictionary = SpecPaths.find(player_class, path_id)
		if p.is_empty():
			return
		stats = p.get("stats", {})
	player_spec_path = path_id
	_apply_stat_dict(stats)
	player_stats_changed.emit()
	# The player listens for this to bind the path's R ability / basic / transforms.
	spec_path_chosen.emit(path_id)


func _apply_stat_dict(s: Dictionary) -> void:
	player_max_hp += int(s.get("max_hp", 0))
	player_hp = player_max_hp
	player_max_mana += int(s.get("max_mana", 0))
	player_mana = float(player_max_mana)
	player_damage += int(s.get("damage", 0))
	player_move_speed += float(s.get("move_speed", 0.0))
	player_crit_chance += float(s.get("crit_chance", 0.0))
	player_crit_damage += float(s.get("crit_damage", 0.0))


func damage_player(amount: int) -> void:
	if game_over or player_downed:
		return
	var mitigated: int = mitigate_damage(amount)
	player_hp -= mitigated
	if player_hp <= 0:
		player_hp = 0
		register_lethal_blow()
	player_stats_changed.emit()


# Called whenever the local player's HP reaches 0 (from any damage path). In
# co-op the player goes downed (revivable); solo it's an instant full death.
func register_lethal_blow() -> void:
	if game_over or player_downed:
		return
	player_hp = 0
	if NetManager and NetManager.is_multiplayer:
		go_downed()
	else:
		full_death()


func go_downed() -> void:
	if player_downed or game_over:
		return
	player_downed = true
	downed_time_left = BLEED_OUT_TIME
	player_hp = 0
	player_downed_changed.emit(true)
	player_stats_changed.emit()


func revive_player(health_fraction: float = REVIVE_HP_FRACTION) -> void:
	if not player_downed:
		return
	player_downed = false
	downed_time_left = 0.0
	player_hp = max(1, int(round(float(player_max_hp) * health_fraction)))
	player_downed_changed.emit(false)
	player_revived.emit()
	player_stats_changed.emit()


# Bleed-out expired with no rescue (or solo death) → permanent death + game over
# for this player. Teammates who are still alive keep playing.
func full_death() -> void:
	player_downed = false
	downed_time_left = 0.0
	player_hp = 0
	if not game_over:
		game_over = true
		player_downed_changed.emit(false)
		player_died.emit()


func _process(delta: float) -> void:
	if player_downed and not game_over:
		downed_time_left -= delta
		if downed_time_left <= 0.0:
			downed_time_left = 0.0
			full_death()


func heal_player(amount: int) -> void:
	player_hp = min(player_hp + amount, player_max_hp)
	player_stats_changed.emit()


func spend_mana(amount: float) -> bool:
	if player_mana < amount:
		return false
	player_mana -= amount
	player_stats_changed.emit()
	return true


func regen_mana(amount: float) -> void:
	player_mana = min(player_mana + amount, float(player_max_mana))
	player_stats_changed.emit()


func roll_crit() -> bool:
	return randf() < player_crit_chance


func compute_attack_damage(base_damage: int) -> Array:
	# Returns [final_damage, is_crit].
	var crit_bonus: float = 0.0
	var crit_dmg_bonus: float = 0.0
	if InventorySystem:
		if InventorySystem.has_method("get_crit_chance_bonus"):
			crit_bonus = float(InventorySystem.call("get_crit_chance_bonus"))
		if InventorySystem.has_method("get_crit_dmg_bonus"):
			crit_dmg_bonus = float(InventorySystem.call("get_crit_dmg_bonus"))
	var crit: bool = randf() < (player_crit_chance + crit_bonus)
	var dmg: int = base_damage
	if crit:
		dmg = int(round(float(base_damage) * (player_crit_damage + crit_dmg_bonus)))
	return [dmg, crit]


# Effective damage with equipment bonuses. Used by skills + basic attack.
func get_effective_damage() -> int:
	var base: float = float(player_damage)
	# Weapon damage multiplier — replaces 1.0 if a weapon is equipped.
	var wmult: float = 1.0
	var dmg_bonus: float = 0.0
	if InventorySystem:
		if InventorySystem.has_method("get_weapon_damage_mult"):
			wmult = float(InventorySystem.call("get_weapon_damage_mult"))
		if InventorySystem.has_method("get_damage_mult_bonus"):
			dmg_bonus = float(InventorySystem.call("get_damage_mult_bonus"))
	return int(round(base * wmult * (1.0 + dmg_bonus)))


# Effective max HP including +max_hp affixes.
func get_effective_max_hp() -> int:
	var bonus: int = 0
	if InventorySystem and InventorySystem.has_method("get_max_hp_bonus"):
		bonus = int(InventorySystem.call("get_max_hp_bonus"))
	return player_max_hp + bonus


func get_effective_max_mana() -> int:
	var bonus: int = 0
	if InventorySystem and InventorySystem.has_method("get_max_mana_bonus"):
		bonus = int(InventorySystem.call("get_max_mana_bonus"))
	return player_max_mana + bonus


func get_effective_move_speed() -> float:
	var bonus: float = 0.0
	if InventorySystem and InventorySystem.has_method("get_move_speed_mult_bonus"):
		bonus = float(InventorySystem.call("get_move_speed_mult_bonus"))
	return player_move_speed * (1.0 + bonus)


func get_effective_armor() -> int:
	if InventorySystem and InventorySystem.has_method("get_total_armor"):
		return int(InventorySystem.call("get_total_armor"))
	return 0


# Damage mitigation — convert armor to a flat percent reduction.
# Diminishing-returns curve: armor / (armor + 80) capped at 70%.
func mitigate_damage(amount: int) -> int:
	var ar: float = float(get_effective_armor())
	if ar <= 0.0:
		return amount
	var reduction: float = clamp(ar / (ar + 80.0), 0.0, 0.7)
	return int(max(1, round(float(amount) * (1.0 - reduction))))
