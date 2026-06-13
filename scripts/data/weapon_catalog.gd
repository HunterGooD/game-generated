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

static var _defs: Dictionary = {}


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
