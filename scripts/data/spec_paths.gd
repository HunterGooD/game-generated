class_name SpecPaths
extends RefCounted

# V1 Spec Paths — at SPEC_PATH_LEVEL the player picks one of their class's paths,
# which reshapes their role (caster / warrior / support) for the rest of the run.
#
# Adding a class's paths is a SINGLE entry here (mirrors how skills live in
# SkillCatalog and items in ItemDatabase — one place to extend). A class with no
# entry simply isn't offered a path yet. Mage is the first vertical slice; the
# other six classes get their trios the same way later.
#
# `stats` = flat additive bonuses applied to GameManager on choice (keys match
# GameManager fields). `role`/`tag` are markers future skill/HUD logic can read
# via GameManager.player_spec_path / its path's role.

const SPEC_PATH_LEVEL: int = 7

# 4th card at level 7: decline ascension. No R / passive / transforms, but a solid
# all-round base-stat bump — a safe, simple option.
const MORTAL_ID: String = "mortal"
const MORTAL_STATS := {
	"max_hp": 80,
	"max_mana": 40,
	"damage": 8,
	"move_speed": 20.0,
	"crit_chance": 0.03,
	"crit_damage": 0.15,
}

# `ability`     — SkillCatalog id cast on R (own cooldown + mana). "" = stat-only.
# `basic_attack`— overrides the class basic-attack kind ("" = keep class default).
# `transforms`  — {slot:int -> transform_id} applied on choosing the path (the
#                 transform_id must exist in SkillCatalog.TRANSFORM_OVERRIDES).
# `passive`     — tag a future passive-handler reads (logic added incrementally).
# Full per-ability design lives in ASCENSIONS.md. Battlemage is the first built
# ascension; its transforms/passive land in a follow-up increment (data left empty
# until the transform skills exist so slot icons/casts don't break).
const PATHS := {
	"mage":
	[
		{
			"id": "battlemage",
			"name": "Battlemage",
			"role": "warrior",
			"desc": "Mana-blade melee. Basic attack becomes a fire sword; R: Arcane Flameblade empowers your melee for 20s.",
			"ability": "arcane_flameblade",
			"basic_attack": "melee",
			"transforms": {0: "flame_cleave", 1: "frost_guard", 3: "falling_brand"},
			"passive": "battlemage_stacks",
			"stats": {"max_hp": 60, "move_speed": 30.0, "damage": 4},
		},
		{
			"id": "elementalist",
			"name": "Elementalist",
			"role": "caster",
			"desc": "Combo artillery. Skills spawn elemental orbs; R: Elemental Orbit fires them (3 elements = Prismatic Burst).",
			"ability": "elemental_orbit",
			"transforms": {},
			"passive": "tri_element_fracture",
			"stats": {"damage": 10, "max_mana": 40, "crit_chance": 0.04},
		},
		{
			"id": "chronomancer",
			"name": "Chronomancer",
			"role": "support",
			"desc": "Time control. R: Temporal Dome — slows enemies, empowers allies inside an 8s field.",
			"ability": "temporal_dome",
			"transforms": {0: "time_wall", 2: "time_link", 3: "stasis_star"},
			"passive": "borrowed_second",
			"stats": {"max_mana": 60, "max_hp": 30, "crit_damage": 0.2},
		},
	],
	"barbarian":
	[
		{
			"id": "berserker",
			"name": "Berserker",
			"role": "warrior",
			"desc": "Glass-cannon rage. R: Blood Frenzy — faster, lifesteal, but fragile. Pain Engine: the lower your HP, the harder you hit.",
			"ability": "barb_blood_frenzy",
			"transforms": {0: "barb_bloodstorm", 1: "barb_skullcrack_leap", 2: "barb_rage_howl"},
			"passive": "pain_engine",
			"stats": {"damage": 8, "move_speed": 20.0, "crit_damage": 0.3},
		},
		{
			"id": "warchief",
			"name": "Warchief",
			"role": "support",
			"desc": "Frontline commander. R: Banner of the Ancients — buffs allies, taunts foes. Hold the Line: guard nearby allies.",
			"ability": "barb_banner",
			"transforms": {1: "barb_guardian_leap", 2: "barb_commanding_shout", 3: "barb_war_ground"},
			"passive": "hold_the_line",
			"stats": {"max_hp": 80, "max_mana": 30},
		},
		{
			"id": "titanbreaker",
			"name": "Titanbreaker",
			"role": "caster",
			"desc": "Earth-shaper. R: Worldsplitter — a fissure that erupts twice. Seismic Momentum: control builds toward bigger quakes.",
			"ability": "barb_worldsplitter",
			"transforms": {0: "barb_stone_grinder", 2: "barb_tremor_roar", 3: "barb_fault_zone"},
			"passive": "seismic_momentum",
			"stats": {"max_hp": 40, "damage": 6, "max_mana": 30},
		},
	],
}


static func paths_for(cls: String) -> Array:
	return PATHS.get(cls, [])


static func find(cls: String, path_id: String) -> Dictionary:
	for p in paths_for(cls):
		if String(p.get("id", "")) == path_id:
			return p
	return {}
