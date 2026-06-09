class_name EnemyAffixes
extends RefCounted

# Elite affixes. Each affix carries stat multipliers and/or behaviour flags applied to
# an enemy at spawn, plus an aura colour (outline shader) so players read the threat at
# a glance. An elite rolls 1–3 affixes; combos blend the aura colours and stack effects.
# Data-driven and extensible — add an entry here and (for new behaviour flags) one hook
# in enemy.gd.

const AFFIXES := {
	"vital":
	{"name": "Vital", "color": Color(0.35, 1.0, 0.45), "hp_mult": 2.4},
	"swift":
	{
		"name": "Swift",
		"color": Color(0.3, 0.9, 1.0),
		"speed_mult": 1.4,
		"attack_speed_mult": 1.5,
	},
	"brutal":
	{"name": "Brutal", "color": Color(1.0, 0.32, 0.22), "damage_mult": 1.7},
	"regenerating":
	{"name": "Regenerating", "color": Color(0.25, 1.0, 0.6), "regen_frac": 0.025},
	"explosive":
	{"name": "Explosive", "color": Color(1.0, 0.55, 0.12), "explode": true},
	"shielded":
	{"name": "Shielded", "color": Color(0.45, 0.62, 1.0), "shield": true},
}


# Number of affixes an elite gets (more = rarer / tougher).
static func roll_count() -> int:
	var r: float = randf()
	if r < 0.12:
		return 3
	if r < 0.42:
		return 2
	return 1


# `count` distinct affix ids at random.
static func roll(count: int) -> Array:
	var ids: Array = AFFIXES.keys()
	ids.shuffle()
	return ids.slice(0, clampi(count, 1, ids.size()))


# Blended aura colour (outline shader) for a set of affixes.
static func aura_color(ids: Array) -> Color:
	if ids.is_empty():
		return Color(1, 1, 1, 1)
	var c := Color(0, 0, 0, 1)
	for id in ids:
		c += (AFFIXES.get(id, {}) as Dictionary).get("color", Color(1, 1, 1, 1))
	var n: float = float(ids.size())
	return Color(c.r / n, c.g / n, c.b / n, 1.0)


static func display_name(ids: Array) -> String:
	var names: Array = []
	for id in ids:
		names.append(String((AFFIXES.get(id, {}) as Dictionary).get("name", id)))
	return " ".join(names)
