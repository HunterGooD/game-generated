class_name WeaponDefinition
extends RefCounted

# Typed descriptor for ONE basic-attack "weapon kind" (melee / claw / dagger /
# bolt …). Data-driven counterpart of the old hardcoded `match basic_attack_kind`
# that lived in player.gd's _configure_basic_attack + _spawn_default_basic_attack.
# The catalog (WeaponCatalog.WEAPONS) is the authoring source; WeaponCatalog
# builds one cached WeaponDefinition per kind and player.gd reads the fields to
# tune the attack cadence + spawn the attack node, so swapping a weapon's scene /
# cadence / animation is a data change, not a code edit.
#
# `combo` is the growth hook (a future ordered list of {anim, window, scene/effect,
# dmg_mult} steps for chained attacks) — empty today, no runtime behaviour yet.

var id: String = ""
var interval: float = 0.55  # seconds between basic attacks (attack cadence)
var mana_cost: float = 0.0
var scene_path: String = ""  # the attack scene spawned per swing/throw/cast
var sfx_path: String = ""  # default on-attack sfx (callers may override by state)
var sfx_db: float = -8.0  # volume for the on-attack sfx
# Where the attack node spawns: "ahead" = caster.global_position + dir * offset
# (melee swings land in front); "at_origin" = the caster's cast_origin (ranged).
var spawn: String = "at_origin"
var offset: float = 0.0
# 3rd arg passed to the scene's setup() when non-empty — magic_bolt.setup takes a
# team/owner ("player"); melee/dagger setup(dir, dmg) take none.
var team: String = ""
var anim: String = "attack"  # AnimatedSprite2D animation to play while attacking
var combo: Array = []  # reserved — chained-attack steps (unused today)

var _scene_cache: PackedScene = null


# The attack scene, loaded once and cached (mirrors SkillDefinition.get_scene).
func get_scene() -> PackedScene:
	if _scene_cache == null and scene_path != "" and ResourceLoader.exists(scene_path):
		_scene_cache = load(scene_path) as PackedScene
	return _scene_cache


static func from_dict(weapon_id: String, d: Dictionary) -> WeaponDefinition:
	var w := WeaponDefinition.new()
	w.id = weapon_id
	w.interval = float(d.get("interval", 0.55))
	w.mana_cost = float(d.get("mana_cost", 0.0))
	w.scene_path = String(d.get("scene", ""))
	w.sfx_path = String(d.get("sfx", ""))
	w.sfx_db = float(d.get("sfx_db", -8.0))
	w.spawn = String(d.get("spawn", "at_origin"))
	w.offset = float(d.get("offset", 0.0))
	w.team = String(d.get("team", ""))
	w.anim = String(d.get("anim", "attack"))
	w.combo = (d.get("combo", []) as Array).duplicate()
	return w


# Index of the combo step for the next basic attack. `window_open` = the previous
# attack's chain window hasn't expired -> advance (wrapping at the end); otherwise
# the combo resets to step 0. Pure (no state) so it's unit-testable.
static func next_combo_step(size: int, cur: int, window_open: bool) -> int:
	if size <= 0:
		return 0
	return ((cur + 1) % size) if window_open else 0


static func unknown(weapon_id: String) -> WeaponDefinition:
	var w := WeaponDefinition.new()
	w.id = weapon_id
	return w
