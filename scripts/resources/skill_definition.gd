class_name SkillDefinition
extends Resource

# Typed descriptor for one castable skill. Replaces the old inline SKILL_CATALOG
# dictionary entries (untyped magic-string fields). Behaviour itself still lives
# in the per-skill scene script (setup_context); this resource carries the
# metadata plus the data-driven modifier wiring, so adding/tuning a skill is now
# a single-place change in SkillCatalog instead of edits across a dict + a switch.

@export var id: String = ""
@export var display_name: String = "?"
# Paths (not preloaded PackedScene/Texture) because NetSync replicates a cast by
# sending scene_path over the wire, and several call sites still pass strings.
@export var scene_path: String = ""
@export var icon_path: String = ""
@export var sfx_path: String = ""
@export var cooldown: float = 1.0
@export var mana_cost: float = 0.0
@export var damage_mult: float = 1.0
# Positioning rule consumed by SkillCaster:
# ahead_of_caster / projectile / at_target / at_caster / with_caster / attached_to_caster
@export var spawn: String = "at_caster"
# Semantic category — the "type" a skill is: projectile / telegraph_aoe / buff /
# summon / transform / dash / ground / melee_arc / chain / mark / aoe. Documents
# intent today and is the hook for future SkillEffect-based behaviour composition;
# it does NOT drive runtime yet.
@export var behavior: String = ""
# Data-driven modifier wiring (replaces the per-skill cases of _build_mods_for).
# Each entry maps a mods[key] the scene reads via ctx.mods in setup_context to a value:
#   value = const + mul * get_modifier(slot, modifier)
# Optional flag `as_bool` yields (get_modifier(slot, modifier) > 0). int-ness is
# preserved when both const and mul are ints. See SkillSystem._build_mods.
@export var mod_wiring: Dictionary = {}
# Reserved growth point: per-skill tuning numbers the scene could read instead of
# hardcoded consts. Empty today.
@export var params: Dictionary = {}
# Composable behaviour blocks (SkillEffect). When non-empty the skill can use the
# generic `skill_composed.tscn` runner instead of a bespoke scene script — the
# data-driven authoring path for new/simple skills. Empty for bespoke skills.
@export var effects: Array[SkillEffect] = []

var _scene_cache: PackedScene = null


# Build a SkillDefinition from a raw catalog dictionary (the key becomes the id).
static func make(skill_id: String, data: Dictionary) -> SkillDefinition:
	var d := SkillDefinition.new()
	d.id = skill_id
	d.display_name = String(data.get("name", "?"))
	d.scene_path = String(data.get("scene", ""))
	d.icon_path = String(data.get("icon", ""))
	d.sfx_path = String(data.get("sfx", ""))
	d.cooldown = float(data.get("cooldown", 1.0))
	d.mana_cost = float(data.get("mana_cost", 0.0))
	d.damage_mult = float(data.get("damage_mult", 1.0))
	d.spawn = String(data.get("spawn", "at_caster"))
	d.behavior = String(data.get("behavior", ""))
	d.mod_wiring = data.get("mod_wiring", {})
	d.params = data.get("params", {})
	d.effects = SkillEffect.list_from(data.get("effects", []))
	return d


func get_scene() -> PackedScene:
	if _scene_cache == null and scene_path != "" and ResourceLoader.exists(scene_path):
		_scene_cache = load(scene_path) as PackedScene
	return _scene_cache


func get_icon() -> Texture2D:
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		return null
	return load(icon_path) as Texture2D
