class_name DungeonEnemies
extends RefCounted

## Enemy composition for the explorable dungeon. Driven by BIOME (thematic pools) + DEPTH
## (a nastier type joins deeper) + ROOM KIND (swarm sizes). Boss is themed per biome.
## Stateless, like Difficulty / DungeonBiome. Type ids must exist in EnemySpawner.ENEMY_TYPES.

# Per-biome type pools: `base` is the staple, `deep` joins at depth ≥ 2.
const POOLS := {
	"ruins": {"base": ["skeleton", "wraith"], "deep": ["cultist"], "miniboss": "cultist"},
	"crypt": {"base": ["skeleton", "cultist"], "deep": ["wraith"], "miniboss": "cultist"},
	"frost": {"base": ["wraith", "skeleton"], "deep": ["succubus"], "miniboss": "succubus"},
	"garden": {"base": ["spider_hatchling", "wraith"], "deep": ["spider_brood"], "miniboss": "spider_brood"},
	"infernal": {"base": ["succubus", "cultist"], "deep": ["skeleton"], "miniboss": "succubus"},
}

# Thematic dungeon boss per biome (ids from BossDatabase).
const BIOME_BOSS := {
	"ruins": "crimson_matron",
	"crypt": "lich_empress",
	"frost": "shadewitch",
	"garden": "crimson_matron",
	"infernal": "hellgate_sovereign",
}

# Chance an elite room spawns a single beefy mini-boss instead of a pack.
const MINIBOSS_CHANCE := 0.35


static func _pool(biome: String) -> Dictionary:
	return POOLS.get(biome, POOLS["ruins"])


# Type pool for a room: biome staples, plus the biome's nastier type once deep enough.
static func types_for(biome: String, depth: int) -> Array:
	var p: Dictionary = _pool(biome)
	var out: Array = (p["base"] as Array).duplicate()
	if depth >= 2:
		out.append_array(p["deep"])
	return out


# Swarm size by room kind — deliberately horde-y, growing with depth/difficulty.
static func count_for(kind: String, depth: int, difficulty: int) -> int:
	var d := depth
	var hard := 1 if difficulty >= 2 else 0
	match kind:
		"pocket":
			return 7 + d + hard       # fast swarm room
		"elite_pylon":
			return 4 + d              # affixed pack
		"pylon":
			return 5 + d + hard
		"merchant_guard":
			return 4 + d
	return 4 + d


# Affix count for an elite pack (more affixes deeper).
static func elite_affixes(depth: int) -> int:
	return 2 + (1 if depth >= 3 else 0)


static func miniboss_type(biome: String) -> String:
	return String(_pool(biome).get("miniboss", "cultist"))


static func boss_for(biome: String) -> String:
	return String(BIOME_BOSS.get(biome, "crimson_matron"))
