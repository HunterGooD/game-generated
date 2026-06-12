class_name BossDatabase
extends RefCounted

# Static catalog of all bosses. Used by enemy_spawner to pick the right boss
# template for a given wave and by boss.gd to configure itself.

# Attack ids — boss.gd dispatches by string.
const ATK_HELLBOLT: String = "hellbolt"
const ATK_CHAIN_SWEEP: String = "chain_sweep"
const ATK_SUMMON_PACT: String = "summon_pact"
const ATK_INFERNAL_CROSS: String = "infernal_cross"
const ATK_WALL_OF_FIRE: String = "wall_of_fire"
const ATK_LAVA_HUNTER: String = "lava_hunter"
const ATK_SHADOW_STEP: String = "shadow_step"
const ATK_DARK_BEAM: String = "dark_beam"
const ATK_HEX_MARK: String = "hex_mark"
const ATK_NECRO_SUMMON: String = "necro_summon"
const ATK_TRIPLE_BOLT: String = "triple_bolt"
const ATK_BONE_SPIRE: String = "bone_spire"
const ATK_SOUL_DRAIN: String = "soul_drain"

# Boss catalog. Each entry has full data the boss controller needs.
const BOSSES: Dictionary = {
	"crimson_matron":
	{
		"name": "Багровая матрона",
		"intro": "БАГРОВАЯ МАТРОНА ПРОБУЖДАЕТСЯ",
		"sprite": "res://assets/sprites/characters/boss_crimson_matron_idle.png",
		"sprite_scale": 0.95,
		"tint": Color(1, 1, 1, 1),
		"hp_mult_vs_wave": 6.5,
		"damage_mult_vs_wave": 1.5,
		"move_speed": 75.0,
		"phases":
		[
			{
				"hp_threshold": 0.0,
				"attack_cycle": [ATK_HELLBOLT, ATK_CHAIN_SWEEP, ATK_HELLBOLT, ATK_SUMMON_PACT],
				"attack_interval": 2.4,
				"tint": Color(1, 1, 1, 1),
			},
		],
		"reward": "legendary",
	},
	"hellgate_sovereign":
	{
		"name": "Владыка адских врат",
		"intro": "ВЛАДЫКА АДСКИХ ВРАТ ПРОБУЖДАЕТСЯ",
		"sprite": "res://assets/sprites/characters/boss_hellgate_sovereign_idle.png",
		"sprite_scale": 1.15,
		"tint": Color(1, 1, 1, 1),
		"hp_mult_vs_wave": 16.0,
		"damage_mult_vs_wave": 1.7,
		"move_speed": 60.0,
		"phases":
		[
			{
				"hp_threshold": 1.0,
				"attack_cycle": [ATK_HELLBOLT, ATK_CHAIN_SWEEP, ATK_HELLBOLT],
				"attack_interval": 2.6,
				"tint": Color(1, 1, 1, 1),
			},
			{
				"hp_threshold": 0.66,
				"attack_cycle":
				[ATK_HELLBOLT, ATK_INFERNAL_CROSS, ATK_CHAIN_SWEEP, ATK_SUMMON_PACT],
				"attack_interval": 2.1,
				"tint": Color(1.15, 0.6, 0.5, 1),
			},
			{
				"hp_threshold": 0.33,
				"attack_cycle":
				[
					ATK_WALL_OF_FIRE,
					ATK_LAVA_HUNTER,
					ATK_INFERNAL_CROSS,
					ATK_LAVA_HUNTER,
					ATK_SUMMON_PACT
				],
				"attack_interval": 1.6,
				"tint": Color(1.3, 0.4, 0.3, 1),
			},
		],
		"reward": "unique",
	},
	"shadewitch":
	{
		"name": "Ведьма теней",
		"intro": "ВЕДЬМА ТЕНЕЙ ВЫХОДИТ ИЗ-ЗА ЗАВЕСЫ",
		"sprite": "res://assets/sprites/characters/boss_shadewitch_idle.png",
		"sprite_scale": 0.85,
		"tint": Color(0.95, 0.85, 1.1, 1),
		"hp_mult_vs_wave": 8.0,
		"damage_mult_vs_wave": 1.4,
		"move_speed": 110.0,
		"phases":
		[
			{
				"hp_threshold": 0.0,
				"attack_cycle": [ATK_SHADOW_STEP, ATK_DARK_BEAM, ATK_HEX_MARK, ATK_DARK_BEAM],
				"attack_interval": 2.0,
				"tint": Color(0.95, 0.85, 1.1, 1),
			},
		],
		"reward": "legendary",
	},
	"lich_empress":
	{
		"name": "Лич-императрица эха",
		"intro": "ЛИЧ-ИМПЕРАТРИЦА ВОСХОДИТ НА ТРОН",
		"sprite": "res://assets/sprites/characters/boss_lich_empress_idle.png",
		"sprite_scale": 1.0,
		"tint": Color(0.9, 0.95, 1.15, 1),
		"hp_mult_vs_wave": 26.0,
		"damage_mult_vs_wave": 1.8,
		"move_speed": 55.0,
		"phases":
		[
			{
				"hp_threshold": 1.0,
				"attack_cycle": [ATK_NECRO_SUMMON, ATK_TRIPLE_BOLT, ATK_TRIPLE_BOLT],
				"attack_interval": 2.3,
				"tint": Color(0.9, 0.95, 1.15, 1),
			},
			{
				"hp_threshold": 0.66,
				"attack_cycle": [ATK_BONE_SPIRE, ATK_NECRO_SUMMON, ATK_TRIPLE_BOLT, ATK_BONE_SPIRE],
				"attack_interval": 1.9,
				"tint": Color(0.85, 0.85, 1.3, 1),
			},
			{
				"hp_threshold": 0.33,
				"attack_cycle":
				[ATK_SOUL_DRAIN, ATK_BONE_SPIRE, ATK_TRIPLE_BOLT, ATK_BONE_SPIRE, ATK_NECRO_SUMMON],
				"attack_interval": 1.5,
				"tint": Color(1.0, 0.7, 1.3, 1),
			},
		],
		"reward": "unique",
	},
}


# Map: wave number → boss id, or "" if no boss this wave.
static func boss_for_wave(wave: int) -> String:
	if wave <= 0:
		return ""
	# Major bosses on multiples of 10, mini on multiples of 5 (not 10).
	# We cycle through the major bosses by (wave / 10) parity.
	if wave % 10 == 0:
		var idx_major: int = ((wave / 10) - 1) % 2
		return "hellgate_sovereign" if idx_major == 0 else "lich_empress"
	if wave % 5 == 0:
		var idx_mini: int = ((wave / 5) - 1) % 2
		return "crimson_matron" if idx_mini == 0 else "shadewitch"
	return ""


static func get_boss(id: String) -> Dictionary:
	return BOSSES.get(id, {})
