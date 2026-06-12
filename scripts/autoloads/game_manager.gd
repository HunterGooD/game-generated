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
# In-run talent tree: fired when talent points are gained, spent, or respecced.
signal talents_changed
signal spec_path_offered
signal spec_path_chosen(path_id: String)
signal gold_changed(new_gold: int)
signal materials_changed
signal enemy_defeated
signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal class_selected(class_id: String)
signal xp_gained(amount: int)
# Run-map flow. `run_started` fires when a new map is generated; `run_node_entered` when
# the party travels onto a node; `run_completed` when the boss node is reached.
signal run_started
signal run_node_entered(node: Dictionary)
# Fired when the gameplay for the active node is finished (e.g. arena waves cleared) —
# RunFlow listens and returns the party to the run map.
signal run_node_cleared(node: Dictionary)
signal run_completed
# Arena local currency changed (the shared pool earned from empowerment pillars).
signal arena_currency_changed(amount: int)
# Transient on-screen notice (the HUD shows it as a banner) — wave/pillar/event callouts.
signal notice(text: String, color: Color)
# Arena wave countdown (seconds left); -1 = hide. The HUD shows it.
signal arena_timer(seconds_left: int)

# Class catalog — base stats and per-level growth.
const CLASSES := {
	"barbarian":
	{
		"display": "Варвар",
		"primary": "strength",
		"primary_label": "Сила",
		"description": "Свирепый берсерк ближнего боя. Трудно убить, трудно перебить.",
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
		"display": "Разбойник",
		"primary": "dexterity",
		"primary_label": "Ловкость",
		"description": "Молниеносный метатель ножей. Сокрушительные криты, бумажная защита.",
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
		"display": "Маг",
		"primary": "intelligence",
		"primary_label": "Интеллект",
		"description": "Заклинатель из ордена руин. Хрупкое тело, сокрушительный запас маны.",
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
		"display": "Буревестница",
		"primary": "dexterity",
		"primary_label": "Напряжение",
		"description":
		"Боевой маг молний. Пускает разряды между врагами, проносится сквозь бури и призывает удары с небес.",
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
		"display": "Багровая ведьма",
		"primary": "intelligence",
		"primary_label": "Ведовство",
		"description":
		"Госпожа меток и цепей. Метит врагов, связывает их багровыми узами и подрывает всю стаю разом.",
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
		"display": "Некромант",
		"primary": "intelligence",
		"primary_label": "Смерть",
		"description":
		"Повелитель костей и проклятий. Поднимает из праха бойцов и щитоносцев, а затем жертвует собственную кровь, чтобы усилить их.",
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
		"display": "Друид",
		"primary": "intelligence",
		"primary_label": "Мудрость",
		"description":
		"Оборотень дикой природы. Носит плоть волка или медведя, призывает каменную броню и духов-зверей.",
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

# Эссенция за прохождение ноды карты — топливо для сверления гнёзд (см.
# InventorySystem.drill_cost). Магазин/костёр платят на ВХОДЕ (begin_run_node),
# боевые ноды (данж/арена/элитка) — по победе (clear_run_node / run_return).
const NODE_ESSENCE_REWARD: int = 5
# Контуры самоцветов (SocketGems.LOOPS) — боевые константы крючков
# (см. on_player_dealt_damage / damage_player / spend_mana).
const SOCKET_RED_LOOP_LIFESTEAL: float = 0.03
const SOCKET_OBSIDIAN_LIFESTEAL: float = 0.02
const SOCKET_DODGE_COOLDOWN_MS: int = 10000
const SOCKET_FREE_CAST_EVERY: int = 4
# Шанс уникального самоцвета по победе над босс-нодой (роллится локально у каждого).
const BOSS_UNIQUE_GEM_CHANCE: float = 0.35

# Feature flag — drive minion host-AI with the LimboAI behaviour tree instead of
# the legacy state machine. ON now that the BT proves parity (tests/unit/test_minion_ai
# runs every behaviour with the flag both off and on). Host-only; puppets unaffected
# (no AI). Flip to false to fall back to the legacy state machine instantly.
var use_bt_minions: bool = true
# Feature flag — drive ENEMY host-AI (in-detection mode behaviour) with LimboAI
# behaviour trees per archetype (melee / ranged-kite / spider hit-and-run). OFF until
# parity proven per archetype, then flipped on. Host-only; puppets/idle/no-target and
# AOE stay on the legacy path. Flip to false to fall back to the legacy state machine.
var use_bt_enemies: bool = true
# Feature flag — drive boss combat with the LimboAI phase HSM (each phase is a state)
# instead of the inline phase loop. OFF until parity proven, then flipped on. Host-only;
# puppets/transition-lockout stay on the legacy path. Flip to false to fall back.
var use_hsm_bosses: bool = true

# Selected class — persists across deaths within a session.
var player_class: String = ""

# Контуры самоцветов — состояние боевых крючков. Carry копит дробный остаток
# вампиризма между ударами (3% от 20 урона не должны теряться).
var _socket_lifesteal_carry: float = 0.0
var _socket_dodge_ready_at_ms: int = 0
var _socket_cast_counter: int = 0

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
# In-run talent tree (V2 level-ups). When the flag is on, a level-up grants a
# talent point spent in the TalentTrees UI instead of opening the 3-card overlay
# (legacy path kept intact behind the flag for future modes). `talents` maps
# node_id → ranks bought (set-bonus free ranks are NOT stored here — they're
# read live from equipment via TalentTrees.set_grant_ranks).
var use_talent_tree: bool = true
var talent_points: int = 0
var talents: Dictionary = {}
# Meta-progression grain: meta XP per character level-up (+3 per difficulty
# tier), plus a flat bonus for finishing the run (+50 per tier). Deliberately
# NOT proportional to run XP — that curve is exponential.
const META_XP_PER_CHAR_LEVEL: int = 12
const META_XP_RUN_COMPLETE_BONUS: int = 150
var gold: int = 0
# Run-scoped crafting wallet (resets with gold in reset_run). Keys are
# ItemDatabase.MATERIAL_IDS: "scrap" / "cloth" / "essence". Like gold, materials
# are purely local in co-op — each peer salvages and spends their own.
var materials: Dictionary = {"scrap": 0, "cloth": 0, "essence": 0}
# Set stones: set_id → count. Salvaging a set item yields one stone of its set;
# two stones + an item craft that set (see InventorySystem.craft_set_item).
var set_stones: Dictionary = {}
# Bastion Vow 5pc shield state (absorbs damage before HP; 30s internal cooldown).
var bastion_shield_hp: int = 0
var _bastion_ready_at_ms: int = 0

# Run state.
var current_floor: int = 1
# Run difficulty tier (index into Difficulty.TIERS), chosen before a run starts. Scales
# enemy HP/damage, elite chance/affixes, spawn density, loot rarity and rewards. Host
# owns this in co-op (broadcast with the run so every peer scales identically).
var run_difficulty: int = 0
# Endless-run loop counter ("Greater Rift" style): each post-uber-boss Continue
# increments it and rolls a fresh map. Loops stack multiplicative pressure on
# enemies AND extra loot luck on top of the difficulty tier (numbers below are
# core-mechanic placeholders — balance pass later). 0 = first map of the run.
const LOOP_ENEMY_HP_PER: float = 0.20
const LOOP_ENEMY_DMG_PER: float = 0.15
const LOOP_REWARD_PER: float = 0.10
const LOOP_LOOT_LUCK_PER: float = 0.05
var run_loop: int = 0
# Active run-map traversal (null until a run is started). Host-authoritative in co-op:
# only the host advances it; clients rebuild the same map from the broadcast seed and
# follow the host's chosen node (replication is a Phase-1 relay addition — see run_travel_to).
var run_state: RunState = null
var run_seed: int = 0
# The map node currently being played (set by RunFlow on entry, cleared on completion).
# Empty {} means "not inside a run node" — e.g. the standalone endless Play mode, which
# lets game_world reset the run normally instead of preserving mid-run state.
var run_node_active: Dictionary = {}
# Dungeon positive-affix effects, local to the current dungeon node (set by
# DungeonAffixController, reset whenever a node begins/clears). `dungeon_loot_luck` is an
# additive bonus LootRoller._roll_rarity folds into its rarity weights (Fortune's Favor);
# `dungeon_extra_reel` tells the boss chest to spin a 4th reel.
var dungeon_loot_luck: float = 0.0
var dungeon_extra_reel: bool = false
# How many Descent portals deep the party is in the CURRENT dungeon node (0 = surface
# layer). Reset when a node begins; bumped by the dungeon's descent portal, which reloads
# the dungeon scene one layer deeper. Drives loot ×1.5 / enemies +1 / +1 negative affix.
var dungeon_depth: int = 0
# Last hero the player chose (persisted locally) — the hub spawns you as this on entry.
# Defaults to barbarian (first available hero). This is a UI preference, not meta-
# progression, so a small user:// config is fine (meta lives on the backend — see V7).
var last_class: String = "barbarian"
const _PREFS_PATH: String = "user://prefs.cfg"
# Arena economy (local to an arena node). `arena_currency` is a SHARED pool earned from
# empowerment pillars; `arena_enemy_power` is the escalation multiplier "empower enemies"
# pillars stack onto subsequent waves. Both reset when an arena node begins. (Co-op: the
# pool is shared, but each player spends it on themselves — that split is a later nuance;
# solo spends the whole pool.)
var arena_currency: int = 0
# Bonuses ACCUMULATE across the whole arena (every pillar you pick stacks) and are wiped on
# exit — unless arena_carryover (a future upgrade) keeps them across all arena nodes.
var arena_enemy_power: float = 1.0  # red "brutality" — enemy hp/dmg
var arena_event_threshold: int = 12  # red "frenzy" lowers it → events fire sooner
var arena_spawn_bonus: float = 0.0  # red "horde" — bigger batches
var arena_buff_dmg: float = 1.0  # green "might" — player damage
var arena_buff_spd: float = 1.0  # green "swift" — player speed
const ARENA_BASE_THRESHOLD: int = 12
# When true (a future meta upgrade / unique can flip it), arena effects + currency are NOT
# wiped between arena nodes — they stack across the run. Default off = effects are local to
# the current arena and vanish when you move to the next node on the map.
var arena_carryover: bool = false
const ARENA_GOLD_RATE: int = 2  # dump chest: 1 local coin → 2 gold
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
	talent_points = 0
	talents = {}
	# Meta-mirror passives — fold the player's persistent tree bonuses on top of the base
	# stat line so every run starts already empowered. Per-player & local in co-op (each
	# peer applies its own save to its own player). Empty {} when the class has no tree.
	if player_class != "" and MetaProgress != null:
		_apply_stat_dict(MetaProgress.meta_bonus(player_class))
		# Repeatable-notable ranks + socketed gems add PERCENT bumps on top.
		var mpct: Dictionary = MetaProgress.meta_percent(player_class)
		var dmg_pct: float = float(mpct.get("damage", 0.0))
		var hp_pct: float = float(mpct.get("max_hp", 0.0))
		var spd_pct: float = float(mpct.get("move_speed", 0.0))
		if dmg_pct != 0.0:
			player_damage = int(round(float(player_damage) * (1.0 + dmg_pct)))
		if hp_pct != 0.0:
			player_max_hp = int(round(float(player_max_hp) * (1.0 + hp_pct)))
			player_hp = player_max_hp
		if spd_pct != 0.0:
			player_move_speed *= 1.0 + spd_pct
	gold = 0
	materials = {"scrap": 0, "cloth": 0, "essence": 0}
	set_stones = {}
	# Fortune-arm meta grants: starting gold + materials (starting GEMS land in
	# InventorySystem._on_class_changed — it wipes the bag AFTER this runs).
	if player_class != "" and MetaProgress != null:
		var grants: Dictionary = MetaProgress.run_grants(player_class)
		gold += int(grants.get("gold", 0))
		var grant_mats: Dictionary = grants.get("materials", {})
		for k in grant_mats:
			materials[k] = int(materials.get(k, 0)) + int(grant_mats[k])
	bastion_shield_hp = 0
	_bastion_ready_at_ms = 0
	total_gold_earned = 0
	highest_wave = 0
	enemies_killed = 0
	game_over = false
	player_downed = false
	downed_time_left = 0.0
	current_floor = 1
	run_state = null
	run_node_active = {}
	run_loop = 0
	player_stats_changed.emit()
	gold_changed.emit(gold)
	materials_changed.emit()


# ── Run-map flow ──────────────────────────────────────────────────────────────
# Generate a fresh run map for `difficulty` and put the party at the entry gate. `seed`
# < 0 picks a random one. In co-op the host calls this and broadcasts (seed, difficulty)
# so every peer rebuilds the identical map.
func start_run(difficulty: int, seed_value: int = -1) -> void:
	run_difficulty = Difficulty.clamp_tier(difficulty)
	run_seed = seed_value if seed_value >= 0 else int(randi())
	run_state = RunState.new(RunMap.generate(run_seed, run_difficulty))
	run_started.emit()


# ── Endless-loop scaling (multiplies ON TOP of the difficulty tier) ───────────
func loop_enemy_hp_mult() -> float:
	return 1.0 + LOOP_ENEMY_HP_PER * float(run_loop)


func loop_enemy_dmg_mult() -> float:
	return 1.0 + LOOP_ENEMY_DMG_PER * float(run_loop)


func loop_reward_mult() -> float:
	return 1.0 + LOOP_REWARD_PER * float(run_loop)


# Additive rarity-luck bonus folded into LootRoller._roll_rarity.
func loop_loot_luck() -> float:
	return LOOP_LOOT_LUCK_PER * float(run_loop)


# Travel onto node `id` if it's a legal next step. Host-authoritative: a co-op client
# can't move the party itself (that needs a `run_nav` relay message — Phase 1). Returns
# whether the move happened. Emits run_node_entered, and run_completed at the boss.
func run_travel_to(id: int) -> bool:
	if run_state == null:
		return false
	var is_client: bool = NetManager != null and NetManager.is_multiplayer and not NetManager.is_host
	if is_client:
		return false  # TODO(Phase 1): send run_nav request to host once the relay allows it
	if not run_state.travel(id):
		return false
	run_node_entered.emit(run_state.current_node())
	if run_state.is_complete():
		run_completed.emit()
	return true


# Host-sanctioned travel for co-op clients. The host resolves the party vote and
# broadcasts `run_travel`; every peer (clients included) applies it here, bypassing
# the client gate in run_travel_to. Same effects: enters the node, completes at boss.
func coop_apply_travel(id: int) -> bool:
	if run_state == null:
		return false
	if not run_state.travel(id):
		return false
	run_node_entered.emit(run_state.current_node())
	if run_state.is_complete():
		run_completed.emit()
	return true


# ── Hero preference (persisted) ───────────────────────────────────────────────
func _ready() -> void:
	_load_prefs()
	# Finishing a run pays a meta-XP bonus on top of the per-level grain.
	run_completed.connect(_award_meta_completion_bonus)


func _award_meta_completion_bonus() -> void:
	if player_class != "" and MetaProgress != null:
		MetaProgress.award_xp(player_class, META_XP_RUN_COMPLETE_BONUS + 50 * run_difficulty)


# Record the chosen hero so the hub spawns you as it next time.
func set_last_class(class_id: String) -> void:
	if not CLASSES.has(class_id):
		return
	last_class = class_id
	_save_prefs()


func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_PREFS_PATH) != OK:
		return
	var lc: String = String(cfg.get_value("hero", "last_class", "barbarian"))
	if CLASSES.has(lc):
		last_class = lc


func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_PREFS_PATH)  # keep any other stored keys
	cfg.set_value("hero", "last_class", last_class)
	cfg.save(_PREFS_PATH)


# ── Arena economy ─────────────────────────────────────────────────────────────
func arena_reset() -> void:
	# Carryover (a future upgrade) keeps the empowerment + currency stacking across arenas.
	if arena_carryover:
		return
	arena_currency = 0
	arena_enemy_power = 1.0
	arena_event_threshold = ARENA_BASE_THRESHOLD
	arena_spawn_bonus = 0.0
	arena_buff_dmg = 1.0
	arena_buff_spd = 1.0
	arena_currency_changed.emit(arena_currency)


# Grant local currency into the shared pool (from pillar picks and cleared events).
func arena_award(amount: int) -> void:
	if amount <= 0:
		return
	arena_currency += amount
	arena_currency_changed.emit(arena_currency)


# Dump chest — convert ALL remaining local currency to gold at ARENA_GOLD_RATE. Returns the
# gold granted.
func arena_dump_to_gold() -> int:
	var gold_gained: int = arena_currency * ARENA_GOLD_RATE
	arena_currency = 0
	arena_currency_changed.emit(0)
	add_gold(gold_gained)
	return gold_gained


# Spend from the shared pool if affordable. Returns whether the purchase went through.
func arena_spend(cost: int) -> bool:
	if cost <= 0 or arena_currency < cost:
		return false
	arena_currency -= cost
	arena_currency_changed.emit(arena_currency)
	return true


# Mark that the party is now playing `node` (its gameplay scene is loading).
func begin_run_node(node: Dictionary) -> void:
	run_node_active = node
	_reset_dungeon_affix_state()  # each node starts with no carried-over dungeon luck
	var t: String = String(node.get("type", ""))
	if t == RunMap.TYPE_MERCHANT or t == RunMap.TYPE_CAMPFIRE:
		add_materials({"essence": NODE_ESSENCE_REWARD})


# The active node's gameplay finished — clear it and notify (RunFlow → back to map).
func clear_run_node() -> void:
	var node: Dictionary = run_node_active
	run_node_active = {}
	_reset_dungeon_affix_state()
	award_node_essence(String(node.get("type", "")))
	run_node_cleared.emit(node)


# Победная эссенция боевых нод. Отдельная точка входа: в кооперативе клиент не
# вызывает clear_run_node (его возвращает run_return) — RunFlow зовёт это сам.
func award_node_essence(node_type: String) -> void:
	if node_type in [RunMap.TYPE_DUNGEON, RunMap.TYPE_ARENA, RunMap.TYPE_ELITE]:
		add_materials({"essence": NODE_ESSENCE_REWARD})
	# Босс-нода: шанс уникального самоцвета (Призма / Замковый камень / …).
	if node_type == RunMap.TYPE_BOSS and InventorySystem and randf() < BOSS_UNIQUE_GEM_CHANCE:
		var gem := ItemInstance.new()
		gem.gem_id = SocketGems.roll_unique()
		gem.rarity = SocketGems.rarity_of(gem.gem_id)
		InventorySystem.add_item(gem)


# ── Контуры самоцветов и камни-эффекты — боевые крючки (см. SocketGems) ───────
func socket_lifesteal_pct() -> float:
	var pct: float = 0.0
	if InventorySystem:
		if InventorySystem.has_socket_loop("red"):
			pct += SOCKET_RED_LOOP_LIFESTEAL
		if InventorySystem.has_socket_effect("blood_obsidian"):
			pct += SOCKET_OBSIDIAN_LIFESTEAL
	return pct


# Вызывается из enemy/boss.take_damage ЛОКАЛЬНЫМИ ударами (from_net не считается:
# в коопе хост не должен лечиться от чужого урона).
func on_player_dealt_damage(amount: int) -> void:
	if amount <= 0 or game_over or player_downed:
		return
	var pct: float = socket_lifesteal_pct()
	if pct <= 0.0:
		return
	_socket_lifesteal_carry += float(amount) * pct
	var heal: int = int(floor(_socket_lifesteal_carry))
	if heal > 0:
		_socket_lifesteal_carry -= float(heal)
		heal_player(heal)


# Контур ветра: раз в SOCKET_DODGE_COOLDOWN_MS полностью игнорирует удар.
func _try_socket_dodge() -> bool:
	if InventorySystem == null or not InventorySystem.has_socket_loop("green"):
		return false
	var now: int = int(Time.get_ticks_msec())
	if now < _socket_dodge_ready_at_ms:
		return false
	_socket_dodge_ready_at_ms = now + SOCKET_DODGE_COOLDOWN_MS
	if VfxManager:
		VfxManager.screen_flash(Color(0.4, 0.95, 0.5, 0.18), 0.2)
	return true


func _reset_dungeon_affix_state() -> void:
	dungeon_loot_luck = 0.0
	dungeon_extra_reel = false
	dungeon_depth = 0


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


# ── Crafting materials (run-scoped wallet, same lifecycle as gold) ────────────
func add_materials(mats: Dictionary) -> void:
	for id in mats:
		var key := String(id)
		materials[key] = max(0, int(materials.get(key, 0)) + int(mats[id]))
	materials_changed.emit()


func get_material(id: String) -> int:
	return int(materials.get(id, 0))


func add_set_stone(set_id: String, n: int = 1) -> void:
	if set_id == "":
		return
	set_stones[set_id] = max(0, int(set_stones.get(set_id, 0)) + n)
	materials_changed.emit()


func get_set_stones(set_id: String) -> int:
	return int(set_stones.get(set_id, 0))


# Cost dicts may contain any of: "gold", "scrap", "cloth", "essence",
# "stones": {set_id: count}. Missing keys mean zero. An EMPTY dict means
# "operation unavailable" by convention — never affordable.
func can_afford_cost(cost: Dictionary) -> bool:
	if cost.is_empty():
		return false
	if gold < int(cost.get("gold", 0)):
		return false
	for id in ["scrap", "cloth", "essence"]:
		if get_material(id) < int(cost.get(id, 0)):
			return false
	var stones: Dictionary = cost.get("stones", {})
	for set_id in stones:
		if get_set_stones(String(set_id)) < int(stones[set_id]):
			return false
	return true


# Atomic: checks the FULL cost first, then deducts everything and emits both
# wallet signals. Returns false (and changes nothing) when unaffordable.
func spend_cost(cost: Dictionary) -> bool:
	if not can_afford_cost(cost):
		return false
	var g: int = int(cost.get("gold", 0))
	if g > 0:
		gold -= g
		gold_changed.emit(gold)
	for id in ["scrap", "cloth", "essence"]:
		var n: int = int(cost.get(id, 0))
		if n > 0:
			materials[id] = int(materials.get(id, 0)) - n
	var stones: Dictionary = cost.get("stones", {})
	for set_id in stones:
		var key := String(set_id)
		set_stones[key] = int(set_stones.get(key, 0)) - int(stones[set_id])
		if set_stones[key] <= 0:
			set_stones.erase(key)
	materials_changed.emit()
	return true


# DEBUG/TEST: instantly grant enough XP to gain one level (bound to P in-game).
# Solo testing aid — in co-op this only levels the local player, so it can desync.
func debug_grant_level() -> void:
	add_xp(maxi(1, player_xp_to_next - player_xp), false)


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
		if use_talent_tree:
			talent_points += 1
			talents_changed.emit()
		# Meta progression: a fixed grain per CHARACTER level (not per raw XP —
		# run XP grows ×1.35 per level, so mirroring it gave thousands of meta
		# levels on a deep run). A run to ~char 50 ≈ 600-900 meta XP ≈ 3-4 meta
		# levels at the start of the linear meta curve.
		if player_class != "" and MetaProgress != null:
			MetaProgress.award_xp(player_class, META_XP_PER_CHAR_LEVEL + 3 * run_difficulty)
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
	# (Meta XP is granted per character LEVEL inside the loop above, plus a
	# completion bonus on run_completed — never per raw run XP.)
	player_stats_changed.emit()


# Apply a chosen spec path's flat stat profile (V1). Per-player in co-op — each
# player picks their own role. Idempotent guard: only the first valid choice sticks.
# True while the level-7 ascension has been OFFERED but not yet chosen. Lives on the autoload
# (not the per-node game_world) so a pending awakening survives the scene change after a boss —
# the next game_world re-arms its HUD button from this instead of losing the choice.
func has_pending_spec_path() -> bool:
	return _spec_path_offered and player_spec_path == ""


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
	player_strength += int(s.get("strength", 0))
	player_dexterity += int(s.get("dexterity", 0))
	player_intelligence += int(s.get("intelligence", 0))


# ── In-run talent tree ────────────────────────────────────────────────────────
# Total rank of a node: bought ranks + free ranks from equipped unique items.
func get_talent_rank(node_id: String) -> int:
	return int(talents.get(node_id, 0)) + TalentTrees.set_grant_ranks(node_id)


# Why a node can't be bought right now ("" = it can). The panel uses this both
# to disable buttons and to explain the gate in the tooltip.
func talent_block_reason(node_id: String) -> String:
	var info: Dictionary = TalentTrees.node_info(player_class, node_id)
	if info.is_empty():
		return "Неизвестный талант"
	var node: Dictionary = info["node"]
	var kind: String = String(node["kind"])
	var max_r: int = TalentTrees.max_ranks(node)
	# Ult nodes ignore tier gates — they're gated on the ascension instead.
	var tier_ok: bool = (
		kind == "ult"
		or TalentTrees.tier_unlocked(
			player_class, int(info["branch_index"]), int(info["tier_index"]), talents
		)
	)
	var reason: String = ""
	if talent_points <= 0:
		reason = "Нет очков талантов"
	elif max_r >= 0 and int(talents.get(node_id, 0)) >= max_r:
		reason = "Уже максимальный ранг"
	elif kind == "ult" and (player_spec_path == "" or player_spec_path == SpecPaths.MORTAL_ID):
		reason = "Требуется вознесение"
	elif not tier_ok:
		reason = (
			"Нужно %d очков в этой ветви"
			% (TalentTrees.POINTS_PER_TIER * int(info["tier_index"]))
		)
	elif kind == "transform":
		# One transform per slot — an ascension (or another node) may already
		# hold this slot, and apply_transform would silently overwrite it.
		var ss := _find_skill_system()
		if ss != null and ss.has_method("get_transform"):
			var current: String = String(ss.call("get_transform", TalentTrees.node_slot(node)))
			if current != "" and current != String(node["transform"]):
				reason = "Этот слот навыка уже преобразован"
	return reason


func spend_talent_point(node_id: String) -> bool:
	if talent_block_reason(node_id) != "":
		return false
	var info: Dictionary = TalentTrees.node_info(player_class, node_id)
	var node: Dictionary = info["node"]
	talents[node_id] = int(talents.get(node_id, 0)) + 1
	talent_points -= 1
	_apply_talent_rank(node)
	talents_changed.emit()
	return true


func _apply_talent_rank(node: Dictionary) -> void:
	match String(node["kind"]):
		"stat":
			_apply_stat_dict({String(node["stat"]): int(node["amount"])})
			player_stats_changed.emit()
		"modifier":
			var ss := _find_skill_system()
			if ss != null:
				ss.call("add_modifier", TalentTrees.node_slot(node), String(node["modifier"]))
		"transform":
			var ss := _find_skill_system()
			if ss != null:
				ss.call("apply_transform", TalentTrees.node_slot(node), String(node["transform"]))
		"perk":
			if String(node["id"]) == "berserker_grip" and InventorySystem:
				InventorySystem.grant_berserker_grip()
		"ult":
			pass  # Read live by SkillSystem.cast_ascension via get_talent_rank.


# Points spent that a respec would refund (perks are kept — Berserker's Grip
# can't be un-granted once two 2H weapons may be equipped).
func talent_respec_refund() -> int:
	var refund: int = 0
	for node_id in talents:
		var info: Dictionary = TalentTrees.node_info(player_class, String(node_id))
		if info.is_empty() or String(info["node"]["kind"]) == "perk":
			continue
		refund += int(talents[node_id])
	return refund


# Refund all non-perk talents: revert stat ranks, wipe run modifiers/transforms,
# then re-apply the ascension's own transforms (those are not talents).
func respec_talents() -> void:
	var refund: int = talent_respec_refund()
	if refund <= 0:
		return
	var kept: Dictionary = {}
	for node_id in talents:
		var info: Dictionary = TalentTrees.node_info(player_class, String(node_id))
		if info.is_empty():
			continue
		var node: Dictionary = info["node"]
		if String(node["kind"]) == "perk":
			kept[node_id] = talents[node_id]
		elif String(node["kind"]) == "stat":
			_apply_stat_dict({String(node["stat"]): -int(node["amount"]) * int(talents[node_id])})
	talents = kept
	talent_points += refund
	var ss := _find_skill_system()
	if ss != null and ss.has_method("clear_run_upgrades"):
		ss.call("clear_run_upgrades")
		if player_spec_path != "" and player_spec_path != SpecPaths.MORTAL_ID:
			var p: Dictionary = SpecPaths.find(player_class, player_spec_path)
			var transforms: Dictionary = p.get("transforms", {})
			for slot in transforms:
				ss.call("apply_transform", int(slot), String(transforms[slot]))
	player_stats_changed.emit()
	talents_changed.emit()


# Re-apply bought talent skill effects to a FRESH SkillSystem (the player node —
# and its SkillSystem child — is recreated on every scene change, dropping all
# run-acquired modifiers/transforms). Called from player._restore_run_upgrades.
# Stat ranks live on this autoload and perks on InventorySystem, so only the
# skill-side effects need replaying.
func reapply_talent_effects(ss: Node) -> void:
	if ss == null or not use_talent_tree:
		return
	for node_id in talents:
		var info: Dictionary = TalentTrees.node_info(player_class, String(node_id))
		if info.is_empty():
			continue
		var node: Dictionary = info["node"]
		match String(node["kind"]):
			"modifier":
				for _i in int(talents[node_id]):
					ss.call("add_modifier", TalentTrees.node_slot(node), String(node["modifier"]))
			"transform":
				ss.call("apply_transform", TalentTrees.node_slot(node), String(node["transform"]))


func _find_skill_system() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var ps := tree.get_nodes_in_group("player")
	if ps.is_empty():
		return null
	return ps[0].get_node_or_null("SkillSystem")


# ── Universal stat effects (Str/Dex/Int) ─────────────────────────────────────
# Identical formulas for every class so off-profile builds work (fast mages,
# clever barbarians). Flat HP/mana/move-speed pieces live in the get_effective_*
# getters below; these are the multipliers combat code reads. Equipment can roll
# attribute affixes, so every consumer goes through get_effective_* attributes.
func get_effective_strength() -> int:
	var bonus: int = 0
	if InventorySystem and InventorySystem.has_method("get_total"):
		bonus = int(round(float(InventorySystem.call("get_total", "strength"))))
	return player_strength + bonus


func get_effective_dexterity() -> int:
	var bonus: int = 0
	if InventorySystem and InventorySystem.has_method("get_total"):
		bonus = int(round(float(InventorySystem.call("get_total", "dexterity"))))
	return player_dexterity + bonus


func get_effective_intelligence() -> int:
	var bonus: int = 0
	if InventorySystem and InventorySystem.has_method("get_total"):
		bonus = int(round(float(InventorySystem.call("get_total", "intelligence"))))
	return player_intelligence + bonus


func get_stat_basic_damage_mult() -> float:
	return 1.0 + 0.01 * float(get_effective_strength())


func get_stat_skill_damage_mult() -> float:
	return 1.0 + 0.01 * float(get_effective_intelligence())


func get_stat_attack_speed_mult() -> float:
	return 1.0 + 0.01 * float(get_effective_dexterity())


# Cooldowns tick this much faster per point of Intelligence.
func get_stat_cooldown_rate() -> float:
	return 1.0 + 0.003 * float(get_effective_intelligence())


func get_effective_crit_chance() -> float:
	return player_crit_chance + 0.003 * float(get_effective_dexterity())


func damage_player(amount: int) -> void:
	if game_over or player_downed:
		return
	# Контур ветра — удар полностью уклонён (перезарядка внутри).
	if amount > 0 and _try_socket_dodge():
		return
	var mitigated: int = mitigate_damage(amount)
	# Bastion Vow 5pc shield absorbs before HP.
	if bastion_shield_hp > 0:
		var absorbed: int = mini(bastion_shield_hp, mitigated)
		bastion_shield_hp -= absorbed
		mitigated -= absorbed
	# Wildheart Totems 5pc — shapeshifted druids reflect 15% to the nearest enemy.
	if mitigated > 0:
		_druid_thorns_reflect(mitigated)
	player_hp -= mitigated
	# Bastion Vow 5pc — dropping below 30% HP grants a shield (30s cooldown).
	if (
		player_hp > 0
		and player_hp < int(0.3 * float(get_effective_max_hp()))
		and Time.get_ticks_msec() >= _bastion_ready_at_ms
		and InventorySystem
		and InventorySystem.has_method("has_set_effect")
		and InventorySystem.has_set_effect("bastion_shield")
	):
		bastion_shield_hp = int(0.25 * float(get_effective_max_hp()))
		_bastion_ready_at_ms = Time.get_ticks_msec() + 30000
		if VfxManager:
			VfxManager.screen_flash(Color(0.4, 0.9, 0.5, 0.25), 0.3)
	if player_hp <= 0:
		player_hp = 0
		register_lethal_blow()
	player_stats_changed.emit()


func _druid_thorns_reflect(taken: int) -> void:
	if InventorySystem == null or not InventorySystem.has_method("has_set_effect"):
		return
	if not InventorySystem.has_set_effect("druid_thorns"):
		return
	var ss := _find_skill_system()
	if ss == null or String(ss.get("druid_form")) in ["", "human"]:
		return
	var ps := get_tree().get_nodes_in_group("player")
	if ps.is_empty():
		return
	var ppos: Vector2 = (ps[0] as Node2D).global_position
	var reflect: int = max(1, int(round(float(taken) * 0.15)))
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.get("dead") == true:
			continue
		if ppos.distance_to((e as Node2D).global_position) <= 160.0:
			if e.has_method("take_damage"):
				e.call("take_damage", reflect, ppos)
			return


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
	# Контур разума: каждый SOCKET_FREE_CAST_EVERY-й каст не тратит ману.
	if amount > 0.0 and InventorySystem and InventorySystem.has_socket_loop("blue"):
		_socket_cast_counter += 1
		if _socket_cast_counter >= SOCKET_FREE_CAST_EVERY:
			_socket_cast_counter = 0
			player_stats_changed.emit()
			return true
	player_mana -= amount
	player_stats_changed.emit()
	return true


func regen_mana(amount: float) -> void:
	player_mana = min(player_mana + amount, float(player_max_mana))
	player_stats_changed.emit()


func roll_crit() -> bool:
	return randf() < get_effective_crit_chance()


func compute_attack_damage(base_damage: int) -> Array:
	# Returns [final_damage, is_crit].
	var crit_bonus: float = 0.0
	var crit_dmg_bonus: float = 0.0
	if InventorySystem:
		if InventorySystem.has_method("get_crit_chance_bonus"):
			crit_bonus = float(InventorySystem.call("get_crit_chance_bonus"))
		if InventorySystem.has_method("get_crit_dmg_bonus"):
			crit_dmg_bonus = float(InventorySystem.call("get_crit_dmg_bonus"))
	var crit: bool = randf() < (get_effective_crit_chance() + crit_bonus)
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


# Effective max HP including +max_hp affixes and Strength (+5 HP per point).
func get_effective_max_hp() -> int:
	var bonus: int = 0
	if InventorySystem and InventorySystem.has_method("get_max_hp_bonus"):
		bonus = int(InventorySystem.call("get_max_hp_bonus"))
	return player_max_hp + bonus + 5 * get_effective_strength()


# Effective max mana including affixes and Intelligence (+3 mana per point).
func get_effective_max_mana() -> int:
	var bonus: int = 0
	if InventorySystem and InventorySystem.has_method("get_max_mana_bonus"):
		bonus = int(InventorySystem.call("get_max_mana_bonus"))
	return player_max_mana + bonus + 3 * get_effective_intelligence()


# Effective move speed: Dexterity adds +2 flat per point, then item multipliers.
func get_effective_move_speed() -> float:
	var bonus: float = 0.0
	if InventorySystem and InventorySystem.has_method("get_move_speed_mult_bonus"):
		bonus = float(InventorySystem.call("get_move_speed_mult_bonus"))
	return (player_move_speed + 2.0 * float(get_effective_dexterity())) * (1.0 + bonus)


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
