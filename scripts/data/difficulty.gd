class_name Difficulty
extends RefCounted

## Run difficulty tiers — selected before a run and applied across the whole encounter.
## Data-driven: one table holds every scaling knob so balance lives in a single place
## (later this can move to a `.tres` resource without touching call sites).
##
## Knobs:
##   enemy_hp_mult / enemy_dmg_mult  multiply the wave-scaled enemy stats
##   elite_chance                    absolute per-spawn chance to roll an elite
##   elite_affix_bonus               extra affixes granted on top of the random roll
##   spawn_rate_mult                 multiplies wave enemy counts (density)
##   loot_rarity_bonus               shifts LootRoller weights toward higher rarities
##   reward_mult                     multiplies XP / gold from kills
##   shards_miniboss / shards_boss   mirror shards (meta currency) a mini-boss / boss drops
##   gems_uber                       meta gems the uber-boss pays out (+1 per endless loop)
##
## Stateless — every method is static. The selected tier lives in GameManager.run_difficulty.

const TIERS: Array = [
	{
		"id": "normal",
		"name": "Обычный",
		"enemy_hp_mult": 1.0,
		"enemy_dmg_mult": 1.0,
		"elite_chance": 0.10,
		"elite_affix_bonus": 0,
		"spawn_rate_mult": 1.0,
		"loot_rarity_bonus": 0.0,
		"reward_mult": 1.0,
		"shards_miniboss": 1,
		"shards_boss": 4,
		"gems_uber": 1,
	},
	{
		"id": "hard",
		"name": "Тяжёлый",
		"enemy_hp_mult": 1.5,
		"enemy_dmg_mult": 1.3,
		"elite_chance": 0.18,
		"elite_affix_bonus": 0,
		"spawn_rate_mult": 1.15,
		"loot_rarity_bonus": 0.25,
		"reward_mult": 1.35,
		"shards_miniboss": 2,
		"shards_boss": 6,
		"gems_uber": 2,
	},
	{
		"id": "nightmare",
		"name": "Кошмар",
		"enemy_hp_mult": 2.2,
		"enemy_dmg_mult": 1.7,
		"elite_chance": 0.28,
		"elite_affix_bonus": 1,
		"spawn_rate_mult": 1.3,
		"loot_rarity_bonus": 0.6,
		"reward_mult": 1.8,
		"shards_miniboss": 3,
		"shards_boss": 9,
		"gems_uber": 3,
	},
	{
		"id": "hell",
		"name": "Ад",
		"enemy_hp_mult": 3.2,
		"enemy_dmg_mult": 2.3,
		"elite_chance": 0.40,
		"elite_affix_bonus": 1,
		"spawn_rate_mult": 1.5,
		"loot_rarity_bonus": 1.0,
		"reward_mult": 2.4,
		"shards_miniboss": 4,
		"shards_boss": 12,
		"gems_uber": 4,
	},
]


static func count() -> int:
	return TIERS.size()


static func clamp_tier(tier: int) -> int:
	return clampi(tier, 0, TIERS.size() - 1)


static func get_tier(tier: int) -> Dictionary:
	return TIERS[clamp_tier(tier)]


# A single scaling knob for `tier`, falling back to `default` for unknown keys.
static func value(tier: int, key: String, default: float = 0.0) -> float:
	return float(get_tier(tier).get(key, default))


static func name_of(tier: int) -> String:
	return String(get_tier(tier).get("name", "Обычный"))
