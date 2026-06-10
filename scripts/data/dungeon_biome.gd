class_name DungeonBiome
extends RefCounted

## Per-biome theming + hazard for the explorable dungeon. The biome string comes from the
## Rust generator (`layer.biome()` → graph.rs Biome::as_str). Stateless, like Difficulty /
## DungeonAffixes. `hazard` drives an optional floor mechanic the runner spawns.

const DEFS := {
	"ruins":
	{
		"name": "Ancient Ruins",
		"floor": Color(0.6, 0.6, 0.72),
		"wall": Color(0.5, 0.5, 0.72),
		"light": Color(0.62, 0.6, 0.78),
		"hazard": "",
	},
	"crypt":
	{
		"name": "Forgotten Crypt",
		"floor": Color(0.42, 0.44, 0.52),
		"wall": Color(0.34, 0.36, 0.5),
		"light": Color(0.34, 0.36, 0.46),  # darker → oppressive crypt gloom
		"hazard": "",
	},
	"frost":
	{
		"name": "Frostbound Vault",
		"floor": Color(0.62, 0.72, 0.85),
		"wall": Color(0.5, 0.62, 0.82),
		"light": Color(0.66, 0.74, 0.9),
		"hazard": "",
	},
	"garden":
	{
		"name": "Overgrown Garden",
		"floor": Color(0.5, 0.66, 0.5),
		"wall": Color(0.42, 0.58, 0.46),
		"light": Color(0.6, 0.74, 0.58),
		"hazard": "",
	},
	"infernal":
	{
		"name": "Infernal Depths",
		"floor": Color(0.8, 0.5, 0.45),
		"wall": Color(0.66, 0.4, 0.4),
		"light": Color(0.85, 0.55, 0.45),
		"hazard": "lava",  # damaging lava patches dot the rooms
	},
}


static func get_def(biome: String) -> Dictionary:
	return DEFS.get(biome, DEFS["ruins"])


static func display_name(biome: String) -> String:
	return String(get_def(biome).get("name", "Dungeon"))


static func floor_tint(biome: String) -> Color:
	return get_def(biome).get("floor", Color(0.6, 0.6, 0.72))


static func wall_tint(biome: String) -> Color:
	return get_def(biome).get("wall", Color(0.5, 0.5, 0.72))


static func light_color(biome: String) -> Color:
	return get_def(biome).get("light", Color(0.62, 0.6, 0.78))


static func hazard(biome: String) -> String:
	return String(get_def(biome).get("hazard", ""))
