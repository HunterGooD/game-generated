class_name WeaponCatalog
extends RefCounted

# Catalog of basic-attack "weapon kinds". The class's `basic_attack` field
# (ClassDefinition.basic_attack, optionally overridden by a spec path) selects a
# kind; player.gd reads the WeaponDefinition to set attack cadence/mana and to
# spawn the attack node. Values here are a 1:1 lift of the old hardcoded
# `match basic_attack_kind` in player.gd (behaviour-preserving).
#
# Unknown kinds fall back to "bolt" — matching the old `match`'s `_:` branch
# (any non-melee/claw/dagger basic was a ranged bolt).
#
# To add/retune a weapon: edit WEAPONS. To add a NEW attack scene, drop it in
# scenes/combat/player/ and point "scene" at it.
#
# COMBO (machine is live but every weapon ships combo[]=empty = no combo). To
# ACTIVATE a chained attack later — once the hero has the extra attack frames —
# add a "combo" array to a weapon. Each step: {anim, dmg_mult, window}. `window`
# = seconds after this hit during which the next click chains to the next step
# (lapse -> restart at step 0). `anim` is an AnimatedSprite2D animation on the
# class (falls back to "attack" if missing), `dmg_mult` scales that hit's damage.
# Example (melee 3-hit finisher; needs attack2/attack3 frames on the class):
#   "combo": [
#       {"anim": "attack",  "dmg_mult": 0.85, "window": 0.55},
#       {"anim": "attack2", "dmg_mult": 0.95, "window": 0.55},
#       {"anim": "attack3", "dmg_mult": 1.35, "window": 0.0},
#   ],
# v1 combo affects ANIM + DAMAGE only; per-step scene/sfx is a later extension.

const WEAPONS := {
	"melee":
	{
		"interval": 0.45,
		"mana_cost": 0.0,
		"scene": "res://scenes/combat/player/melee_swing.tscn",
		"sfx": "res://assets/audio/sfx/player/player_melee_swing.mp3",
		"sfx_db": -8.0,
		"spawn": "ahead",
		"offset": 30.0,
		"team": "",
		"anim": "attack",
	},
	"claw":
	{
		"interval": 0.40,
		"mana_cost": 0.0,
		"scene": "res://scenes/combat/player/melee_swing.tscn",
		"sfx": "res://assets/audio/sfx/player/player_melee_swing.mp3",
		"sfx_db": -8.0,
		"spawn": "ahead",
		"offset": 30.0,
		"team": "",
		"anim": "attack",
	},
	"dagger":
	{
		"interval": 0.40,
		"mana_cost": 0.0,
		"scene": "res://scenes/combat/player/thrown_dagger.tscn",
		"sfx": "res://assets/audio/sfx/player/player_dagger_throw.mp3",
		"sfx_db": -8.0,
		"spawn": "at_origin",
		"offset": 0.0,
		"team": "",
		"anim": "attack",
	},
	"bolt":
	{
		"interval": 0.55,
		"mana_cost": 4.0,
		"scene": "res://scenes/combat/player/magic_bolt.tscn",
		"sfx": "res://assets/audio/sfx/player/player_magic_cast.mp3",
		"sfx_db": -10.0,
		"spawn": "at_origin",
		"offset": 0.0,
		"team": "player",
		"anim": "attack",
	},
}

const FALLBACK_KIND := "bolt"

# Basic-attack UNIQUES — one per class; equipping the unique (InventorySystem.
# has_unique) swaps the class's default basic attack for this. Selected via
# ClassDefinition.basic_unique; spawned by player._spawn_basic_unique. A 1:1 lift
# of the old hardcoded `match unique_id` in player.gd.
#   anchor: "global" = player pos, "origin" = cast origin (+ offset along aim).
#   dmg_mult: damage scale. melee_theme/melee_core: extra setup() args for the
#   melee_swing skin variants. via "context": resolve by skill_id from the skill
#   catalog (script-carrier-safe) + SkillContext.apply. spread: one shot per angle.
const BASIC_UNIQUES := {
	"basic_barb_shockwave":
	{
		"scene": "res://scenes/combat/player/basic_shockwave.tscn",
		"anchor": "origin",
		"offset": 30.0,
	},
	"basic_rogue_triple_throw":
	{
		"scene": "res://scenes/combat/player/thrown_dagger.tscn",
		"anchor": "origin",
		"dmg_mult": 0.7,
		"spread": [-0.25, 0.0, 0.25],
		"sfx": "res://assets/audio/sfx/player/player_dagger_throw.mp3",
		"sfx_db": -8.0,
	},
	"basic_mage_phantom_edge":
	{
		"scene": "res://scenes/combat/player/melee_swing.tscn",
		"anchor": "global",
		"offset": 30.0,
		"dmg_mult": 1.1,
		"melee_theme": "white",
		"melee_core": Color(0.6, 0.85, 1.5),
		"sfx": "res://assets/audio/sfx/player/player_basic_phantom_swing.mp3",
		"sfx_db": -8.0,
	},
	"basic_druid_thunder_sphere":
	{
		"scene": "res://scenes/combat/player/basic_thunder_sphere.tscn",
		"anchor": "origin",
	},
	"basic_necro_bone_lance":
	{
		"scene": "res://scenes/combat/player/melee_swing.tscn",
		"anchor": "global",
		"offset": 36.0,
		"dmg_mult": 1.15,
		"melee_theme": "white",
		"melee_core": Color(0.85, 0.6, 1.4),
		"sfx": "res://assets/audio/sfx/player/player_basic_bone_lance.mp3",
		"sfx_db": -8.0,
	},
	"basic_hexen_whipcrack":
	{
		"skill_id": "hexen_blood_whip",
		"anchor": "origin",
		"dmg_mult": 0.6,
		"via": "context",
	},
	"basic_storm_voltaic_tonfa":
	{
		"scene": "res://scenes/combat/player/melee_swing.tscn",
		"anchor": "global",
		"offset": 34.0,
		"dmg_mult": 1.05,
		"melee_theme": "storm",
		"melee_core": Color(0.55, 0.85, 1.6),
		"sfx": "res://assets/audio/sfx/player/player_storm_chain_bolt.mp3",
		"sfx_db": -12.0,
	},
}

static var _defs: Dictionary = {}
static var _unique_defs: Dictionary = {}


static func _ensure_built() -> void:
	if not _defs.is_empty():
		return
	for kind in WEAPONS:
		_defs[kind] = WeaponDefinition.from_dict(String(kind), WEAPONS[kind])


# Typed weapon for a kind. Unknown kind -> the "bolt" fallback (old `match` _:).
static func get_def(kind: String) -> WeaponDefinition:
	_ensure_built()
	if _defs.has(kind):
		return _defs[kind]
	return _defs[FALLBACK_KIND]


static func has_kind(kind: String) -> bool:
	_ensure_built()
	return _defs.has(kind)


static func all_kinds() -> Array:
	return WEAPONS.keys()


# Typed basic-attack unique by id, or null if the id isn't a known unique.
static func get_unique(unique_id: String) -> WeaponDefinition:
	if _unique_defs.is_empty():
		for uid in BASIC_UNIQUES:
			_unique_defs[uid] = WeaponDefinition.from_dict(String(uid), BASIC_UNIQUES[uid])
	return _unique_defs.get(unique_id, null)
