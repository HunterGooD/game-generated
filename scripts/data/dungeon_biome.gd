class_name DungeonBiome
extends RefCounted

## Per-biome theming + hazard for the explorable dungeon. The biome string comes from the
## Rust generator (`layer.biome()` → graph.rs Biome::as_str). Stateless, like Difficulty /
## DungeonAffixes. `hazard` drives an optional floor mechanic the runner spawns.

const DEFS := {
	"ruins":
	{
		"name": "Древние руины",
		"floor": Color(0.6, 0.6, 0.72),
		"wall": Color(0.5, 0.5, 0.72),
		"light": Color(0.62, 0.6, 0.78),
		"hazard": "",
		# `backdrop` fills the space beyond the map (see world_backdrop.gd). A soft, slightly
		# tinted dark — never pure black, which reads as a harsh hole in the world.
		"backdrop": Color(0.10, 0.10, 0.14),
		"backdrop_edge": Color(0.05, 0.05, 0.08),
	},
	"crypt":
	{
		"name": "Забытый склеп",
		"floor": Color(0.42, 0.44, 0.52),
		"wall": Color(0.34, 0.36, 0.5),
		"light": Color(0.34, 0.36, 0.46),  # darker → oppressive crypt gloom
		"hazard": "fog",  # screen-space vignette limiting vision
		"backdrop": Color(0.07, 0.08, 0.12),
		"backdrop_edge": Color(0.03, 0.04, 0.07),
	},
	"frost":
	{
		"name": "Морозное хранилище",
		"floor": Color(0.62, 0.72, 0.85),
		"wall": Color(0.5, 0.62, 0.82),
		"light": Color(0.66, 0.74, 0.9),
		"hazard": "ice",  # frostbite floor pools
		"backdrop": Color(0.09, 0.13, 0.18),
		"backdrop_edge": Color(0.04, 0.07, 0.11),
	},
	"garden":
	{
		"name": "Заросший сад",
		"floor": Color(0.5, 0.66, 0.5),
		"wall": Color(0.42, 0.58, 0.46),
		"light": Color(0.6, 0.74, 0.58),
		"hazard": "spore",  # poison spore pools
		"backdrop": Color(0.08, 0.13, 0.09),
		"backdrop_edge": Color(0.04, 0.07, 0.05),
	},
	"infernal":
	{
		"name": "Адские глубины",
		"floor": Color(0.8, 0.5, 0.45),
		"wall": Color(0.66, 0.4, 0.4),
		"light": Color(0.85, 0.55, 0.45),
		"hazard": "lava",  # damaging lava patches dot the rooms
		"backdrop": Color(0.15, 0.08, 0.07),
		"backdrop_edge": Color(0.08, 0.04, 0.04),
	},
}


static func backdrop_color(biome: String) -> Color:
	return get_def(biome).get("backdrop", Color(0.10, 0.10, 0.14))


static func backdrop_edge_color(biome: String) -> Color:
	return get_def(biome).get("backdrop_edge", Color(0.05, 0.05, 0.08))


static func get_def(biome: String) -> Dictionary:
	return DEFS.get(biome, DEFS["ruins"])


static func display_name(biome: String) -> String:
	return String(get_def(biome).get("name", "Подземелье"))


static func floor_tint(biome: String) -> Color:
	return get_def(biome).get("floor", Color(0.6, 0.6, 0.72))


static func wall_tint(biome: String) -> Color:
	return get_def(biome).get("wall", Color(0.5, 0.5, 0.72))


static func light_color(biome: String) -> Color:
	return get_def(biome).get("light", Color(0.62, 0.6, 0.78))


static func hazard(biome: String) -> String:
	return String(get_def(biome).get("hazard", ""))
