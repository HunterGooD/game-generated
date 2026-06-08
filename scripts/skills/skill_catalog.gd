class_name SkillCatalog
extends RefCounted

# Static registry of every castable skill as a typed SkillDefinition, plus the
# catalog-level lookup maps (transform overrides, druid form slots). Built once,
# lazily, from the raw data below. SkillSystem reads through this instead of the
# old inline SKILL_CATALOG dictionary. Authoring stays in code for now; each
# entry can be exported to a .tres SkillDefinition later without touching callers.

# Slot transform → alternate skill id (a unique OR a spec path replaces the base
# slot skill). Mage ascensions add their slot swaps here; keyed id == skill id.
const TRANSFORM_OVERRIDES: Dictionary = {
	"necro_bone_spear": "necro_bone_spear",
	"necro_curse_field": "necro_curse_field",
	"druid_hurricane": "druid_hurricane",
	"druid_dire_wolf": "druid_dire_wolf_form",
	# Battlemage (Mage) spec-path slot swaps.
	"flame_cleave": "flame_cleave",
	"frost_guard": "frost_guard",
	"falling_brand": "falling_brand",
	# Chronomancer (Mage) spec-path slot swaps.
	"time_wall": "time_wall",
	"time_link": "time_link",
	"stasis_star": "stasis_star",
	# Berserker (Barbarian) spec-path slot swaps.
	"barb_bloodstorm": "barb_bloodstorm",
	"barb_skullcrack_leap": "barb_skullcrack_leap",
	"barb_rage_howl": "barb_rage_howl",
	# Warchief (Barbarian) spec-path slot swaps.
	"barb_commanding_shout": "barb_commanding_shout",
	"barb_war_ground": "barb_war_ground",
	"barb_guardian_leap": "barb_guardian_leap",
	# Titanbreaker (Barbarian) spec-path slot swaps.
	"barb_stone_grinder": "barb_stone_grinder",
	"barb_fault_zone": "barb_fault_zone",
	"barb_tremor_roar": "barb_tremor_roar",
}

# Which slot each slot-swap transform replaces. Transforms can be granted by a
# level-up unique (apply_transform → transforms[slot]) OR an equipped unique item
# (sets only InventorySystem.has_unique); get_transform() reads both.
const ITEM_TRANSFORM_SLOT: Dictionary = {
	"druid_hurricane": 0,
	"druid_dire_wolf": 1,
	"necro_bone_spear": 0,
	"necro_curse_field": 1,
}

# Which BASE skill a slot-swap transform is meant to replace. The druid reuses
# slots 0/1 for different skills per form, so a transform keyed only by slot index
# would leak onto whatever in-form skill now occupies that slot. Gating on the
# slot's current skill_id fixes that. Transforms not listed always apply.
const TRANSFORM_BASE_SKILL: Dictionary = {
	"druid_hurricane": "druid_wolf_form",
	"druid_dire_wolf": "druid_bear_form",
}

# Druid form -> slot 0/1 swap. Slots 2 & 3 stay fixed; slot 4 is Eagle Form.
const DRUID_FORM_SLOTS: Dictionary = {
	"human": ["druid_wolf_form", "druid_bear_form"],
	"wolf": ["druid_bite", "druid_leap"],
	"bear": ["druid_sweep", "druid_charge"],
	"eagle": ["druid_talon_swoop", "druid_wind_gust"],
	"dire_wolf": ["druid_bite", "druid_leap"],
}

# Default fallback if class data has no skill_ids.
const DEFAULT_SKILL_IDS := ["fire_wall", "ice_bolt", "chain_lightning", "meteor"]

# Raw catalog data. `behavior` is a semantic category (documentation + future
# hook). `mod_wiring` is the data form of the old _build_mods_for switch.
const _RAW := {
	# MAGE
	"fire_wall": {
		"name": "Fire Wall", "scene": "res://scenes/combat/player/skill_fire_wall.tscn",
		"icon": "res://assets/sprites/items/icon_skill_fire_wall.png",
		"cooldown": 7.0, "mana_cost": 22.0, "damage_mult": 0.6,
		"sfx": "res://assets/audio/sfx/player/player_spell_fire_wall.mp3",
		"spawn": "ahead_of_caster", "behavior": "ground",
		"mod_wiring": {
			"duration_stacks": {"modifier": "fw_duration"},
			"radius_stacks": {"modifier": "fw_radius"},
		},
	},
	"ice_bolt": {
		"name": "Ice Bolt", "scene": "res://scenes/combat/player/skill_ice_bolt.tscn",
		"icon": "res://assets/sprites/items/icon_skill_ice_bolt.png",
		"cooldown": 4.0, "mana_cost": 14.0, "damage_mult": 1.4,
		"sfx": "res://assets/audio/sfx/player/player_spell_ice_bolt.mp3",
		"spawn": "projectile", "behavior": "projectile",
		"mod_wiring": {
			"pierce": {"modifier": "ib_pierce", "as_bool": true},
			"slow_stacks": {"modifier": "ib_slow"},
		},
	},
	"chain_lightning": {
		"name": "Chain Lightning", "scene": "res://scenes/skills/skill_chain_lightning.tscn",
		"icon": "res://assets/sprites/items/icon_skill_chain_lightning.png",
		"cooldown": 9.0, "mana_cost": 28.0, "damage_mult": 1.2,
		"sfx": "res://assets/audio/sfx/player/player_spell_chain_lightning.mp3",
		"spawn": "at_caster", "behavior": "chain",
		"mod_wiring": {"jumps_bonus": {"modifier": "cl_jumps", "mul": 2}},
	},
	"meteor": {
		"name": "Meteor", "scene": "res://scenes/skills/skill_meteor.tscn",
		"icon": "res://assets/sprites/items/icon_skill_meteor.png",
		"cooldown": 12.0, "mana_cost": 38.0, "damage_mult": 2.4,
		"sfx": "res://assets/audio/sfx/player/player_spell_meteor.mp3",
		"spawn": "at_target", "behavior": "telegraph_aoe",
		"mod_wiring": {"radius_bonus": {"modifier": "mt_radius", "mul": 0.5}},
	},
	# BARBARIAN
	"whirlwind": {
		"name": "Whirlwind", "scene": "res://scenes/combat/player/skill_whirlwind.tscn",
		"icon": "res://assets/sprites/items/icon_barb_whirlwind.png",
		"cooldown": 8.0, "mana_cost": 18.0, "damage_mult": 0.5,
		"sfx": "res://assets/audio/sfx/player/player_spell_whirlwind.mp3",
		"spawn": "attached_to_caster", "behavior": "melee_arc",
	},
	"leap_slam": {
		"name": "Leap Slam", "scene": "res://scenes/skills/skill_leap_slam.tscn",
		"icon": "res://assets/sprites/items/icon_barb_leap.png",
		"cooldown": 9.0, "mana_cost": 22.0, "damage_mult": 1.8,
		"sfx": "res://assets/audio/sfx/player/player_spell_leap.mp3",
		"spawn": "with_caster", "behavior": "dash",
	},
	"battle_cry": {
		"name": "Battle Cry", "scene": "res://scenes/skills/skill_battle_cry.tscn",
		"icon": "res://assets/sprites/items/icon_barb_cry.png",
		"cooldown": 18.0, "mana_cost": 28.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_battlecry.mp3",
		"spawn": "at_caster", "behavior": "buff",
		"mod_wiring": {
			"radius": {"const": 240.0},
			"duration": {"const": 5.0, "modifier": "barb_cry_power", "mul": 2.0},
			"dmg_mult": {"const": 1.6},
			"spd_mult": {"const": 1.3, "modifier": "barb_cry_power", "mul": 0.15},
		},
	},
	"earthquake": {
		"name": "Earthquake", "scene": "res://scenes/skills/skill_earthquake.tscn",
		"icon": "res://assets/sprites/items/icon_barb_quake.png",
		"cooldown": 14.0, "mana_cost": 36.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_spell_earthquake.mp3",
		"spawn": "at_caster", "behavior": "telegraph_aoe",
		"mod_wiring": {"wave_bonus": {"modifier": "barb_quake_waves"}},
	},
	# ROGUE
	"caltrops": {
		"name": "Caltrops", "scene": "res://scenes/skills/skill_caltrops.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_caltrops.png",
		"cooldown": 8.0, "mana_cost": 18.0, "damage_mult": 0.3,
		"sfx": "res://assets/audio/sfx/player/player_spell_caltrops.mp3",
		"spawn": "at_target", "behavior": "ground",
		"mod_wiring": {"duration_bonus": {"modifier": "rogue_caltrops_duration", "mul": 4.0}},
	},
	"smoke_bomb": {
		"name": "Smoke Bomb", "scene": "res://scenes/skills/skill_smoke_bomb.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_smoke.png",
		"cooldown": 12.0, "mana_cost": 20.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_smoke_bomb.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"poison_vial": {
		"name": "Poison Vial", "scene": "res://scenes/combat/player/skill_poison_vial.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_poison.png",
		"cooldown": 7.0, "mana_cost": 22.0, "damage_mult": 0.45,
		"sfx": "res://assets/audio/sfx/player/player_spell_poison.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	"fan_of_knives": {
		"name": "Fan of Knives", "scene": "res://scenes/skills/skill_fan_of_knives.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_knives.png",
		"cooldown": 10.0, "mana_cost": 30.0, "damage_mult": 1.3,
		"sfx": "res://assets/audio/sfx/player/player_spell_fan_knives.mp3",
		"spawn": "at_caster", "behavior": "melee_arc",
		"mod_wiring": {"count_bonus": {"modifier": "rogue_knives_count", "mul": 2}},
	},
	# DRUID
	"druid_wolf_form": {
		"name": "Wolf Form", "scene": "res://scenes/skills/skill_druid_wolf_form.tscn",
		"icon": "res://assets/sprites/items/icon_druid_wolf_form.png",
		"cooldown": 16.0, "mana_cost": 20.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_wolf.mp3",
		"spawn": "at_caster", "behavior": "transform",
	},
	"druid_bear_form": {
		"name": "Bear Form", "scene": "res://scenes/skills/skill_druid_bear_form.tscn",
		"icon": "res://assets/sprites/items/icon_druid_bear_form.png",
		"cooldown": 16.0, "mana_cost": 20.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_bear.mp3",
		"spawn": "at_caster", "behavior": "transform",
	},
	"druid_bite": {
		"name": "Savage Bite", "scene": "res://scenes/skills/skill_druid_bite.tscn",
		"icon": "res://assets/sprites/items/icon_druid_bite.png",
		"cooldown": 1.8, "mana_cost": 6.0, "damage_mult": 2.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_bite_hit.mp3",
		"spawn": "ahead_of_caster", "behavior": "melee_arc",
	},
	"druid_leap": {
		"name": "Hunting Leap", "scene": "res://scenes/skills/skill_druid_leap.tscn",
		"icon": "res://assets/sprites/items/icon_druid_leap.png",
		"cooldown": 5.0, "mana_cost": 14.0, "damage_mult": 1.5,
		"sfx": "res://assets/audio/sfx/player/player_druid_wolf_leap.mp3",
		"spawn": "with_caster", "behavior": "dash",
	},
	"druid_sweep": {
		"name": "Sweeping Maul", "scene": "res://scenes/skills/skill_druid_sweep.tscn",
		"icon": "res://assets/sprites/items/icon_druid_sweep.png",
		"cooldown": 3.2, "mana_cost": 10.0, "damage_mult": 2.6,
		"sfx": "res://assets/audio/sfx/player/player_druid_bear_sweep.mp3",
		"spawn": "ahead_of_caster", "behavior": "melee_arc",
	},
	"druid_charge": {
		"name": "Stone Charge", "scene": "res://scenes/skills/skill_druid_charge.tscn",
		"icon": "res://assets/sprites/items/icon_druid_charge.png",
		"cooldown": 7.0, "mana_cost": 18.0, "damage_mult": 1.8,
		"sfx": "res://assets/audio/sfx/player/player_druid_bear_charge.mp3",
		"spawn": "with_caster", "behavior": "dash",
	},
	"druid_stone_armor": {
		"name": "Stone Armor", "scene": "res://scenes/skills/skill_druid_stone_armor.tscn",
		"icon": "res://assets/sprites/items/icon_druid_stone_armor.png",
		"cooldown": 14.0, "mana_cost": 32.0, "damage_mult": 0.6,
		"sfx": "res://assets/audio/sfx/player/player_druid_stone_armor_form.mp3",
		"spawn": "attached_to_caster", "behavior": "buff",
	},
	"druid_summon_spirit": {
		"name": "Summon Spirit", "scene": "res://scenes/skills/skill_druid_summon_spirit.tscn",
		"icon": "res://assets/sprites/items/icon_druid_summon_spirit.png",
		"cooldown": 22.0, "mana_cost": 38.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_summon_spirit.mp3",
		"spawn": "at_caster", "behavior": "summon",
	},
	"druid_eagle_form": {
		"name": "Eagle Form", "scene": "res://scenes/skills/skill_druid_eagle_form.tscn",
		"icon": "res://assets/sprites/items/icon_druid_eagle_form.png",
		"cooldown": 24.0, "mana_cost": 30.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_eagle.mp3",
		"spawn": "at_caster", "behavior": "transform",
	},
	"druid_talon_swoop": {
		"name": "Talon Swoop", "scene": "res://scenes/skills/skill_druid_talon_swoop.tscn",
		"icon": "res://assets/sprites/items/icon_druid_talon_swoop.png",
		"cooldown": 3.5, "mana_cost": 10.0, "damage_mult": 2.2,
		"sfx": "res://assets/audio/sfx/player/player_druid_talon_swoop.mp3",
		"spawn": "with_caster", "behavior": "dash",
	},
	"druid_wind_gust": {
		"name": "Wind Gust", "scene": "res://scenes/skills/skill_druid_wind_gust.tscn",
		"icon": "res://assets/sprites/items/icon_druid_wind_gust.png",
		"cooldown": 5.0, "mana_cost": 14.0, "damage_mult": 1.4,
		"sfx": "res://assets/audio/sfx/player/player_druid_wind_gust.mp3",
		"spawn": "ahead_of_caster", "behavior": "aoe",
	},
	# NECROMANCER
	"necro_raise_skeleton": {
		"name": "Raise Skeleton", "scene": "res://scenes/skills/skill_necro_raise_skeleton.tscn",
		"icon": "res://assets/sprites/items/icon_necro_raise_skeleton.png",
		"cooldown": 6.0, "mana_cost": 18.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_raise_skeleton.mp3",
		"spawn": "at_target", "behavior": "summon",
	},
	"necro_raise_knight": {
		"name": "Raise Knight", "scene": "res://scenes/skills/skill_necro_raise_knight.tscn",
		"icon": "res://assets/sprites/items/icon_necro_raise_knight.png",
		"cooldown": 14.0, "mana_cost": 36.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_raise_knight.mp3",
		"spawn": "at_target", "behavior": "summon",
	},
	"necro_blood_pact": {
		"name": "Blood Pact", "scene": "res://scenes/skills/skill_necro_blood_pact.tscn",
		"icon": "res://assets/sprites/items/icon_necro_blood_pact.png",
		"cooldown": 18.0, "mana_cost": 0.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_blood_pact.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"necro_death_pulse": {
		"name": "Death Pulse", "scene": "res://scenes/skills/skill_necro_death_pulse.tscn",
		"icon": "res://assets/sprites/items/icon_necro_death_pulse.png",
		"cooldown": 10.0, "mana_cost": 28.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_necro_death_pulse.mp3",
		"spawn": "at_caster", "behavior": "aoe",
	},
	# UNIQUE TRANSFORM SCENES — selected at cast-time when slot has a transform.
	"necro_bone_spear": {
		"name": "Bone Spear", "scene": "res://scenes/skills/skill_necro_bone_spear.tscn",
		"icon": "res://assets/sprites/items/icon_necro_bone_spear.png",
		"cooldown": 1.6, "mana_cost": 12.0, "damage_mult": 2.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_bone_spear.mp3",
		"spawn": "ahead_of_caster", "behavior": "projectile",
	},
	"necro_curse_field": {
		"name": "Curse Field", "scene": "res://scenes/skills/skill_necro_curse_field.tscn",
		"icon": "res://assets/sprites/items/icon_necro_curse_field.png",
		"cooldown": 12.0, "mana_cost": 32.0, "damage_mult": 0.4,
		"sfx": "res://assets/audio/sfx/player/player_necro_curse_field.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	"druid_hurricane": {
		"name": "Hurricane", "scene": "res://scenes/skills/skill_druid_hurricane.tscn",
		"icon": "res://assets/sprites/items/icon_druid_hurricane.png",
		"cooldown": 10.0, "mana_cost": 24.0, "damage_mult": 0.8,
		"sfx": "res://assets/audio/sfx/player/player_druid_hurricane.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	"druid_dire_wolf_form": {
		"name": "Dire Wolf Form", "scene": "res://scenes/skills/skill_druid_dire_wolf_form.tscn",
		"icon": "res://assets/sprites/items/icon_druid_dire_wolf.png",
		"cooldown": 16.0, "mana_cost": 22.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_wolf.mp3",
		"spawn": "at_caster", "behavior": "transform",
	},
	# HEXEN
	"hexen_hex_mark": {
		"name": "Hex Mark", "scene": "res://scenes/skills/skill_hexen_hex_mark.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_hex_mark.png",
		"cooldown": 2.0, "mana_cost": 14.0, "damage_mult": 0.9,
		"sfx": "res://assets/audio/sfx/player/player_hexen_hex_mark_apply.mp3",
		"spawn": "at_target", "behavior": "mark",
		"mod_wiring": {"duration_bonus": {"modifier": "hexen_mark_duration", "mul": 1.5}},
	},
	"hexen_blood_whip": {
		"name": "Blood Whip", "scene": "res://scenes/skills/skill_hexen_blood_whip.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_blood_whip.png",
		"cooldown": 5.0, "mana_cost": 18.0, "damage_mult": 1.3,
		"sfx": "res://assets/audio/sfx/player/player_hexen_blood_whip.mp3",
		"spawn": "ahead_of_caster", "behavior": "melee_arc",
	},
	"hexen_soul_tether": {
		"name": "Soul Tether", "scene": "res://scenes/skills/skill_hexen_soul_tether.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_soul_tether.png",
		"cooldown": 12.0, "mana_cost": 32.0, "damage_mult": 0.6,
		"sfx": "res://assets/audio/sfx/player/player_hexen_soul_tether.mp3",
		"spawn": "at_caster", "behavior": "mark",
	},
	"hexen_crimson_ritual": {
		"name": "Crimson Ritual", "scene": "res://scenes/skills/skill_hexen_crimson_ritual.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_crimson_ritual.png",
		"cooldown": 18.0, "mana_cost": 36.0, "damage_mult": 0.4,
		"sfx": "res://assets/audio/sfx/player/player_hexen_crimson_ritual.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	# STORMCALLER
	"storm_chain_bolt": {
		"name": "Chain Bolt", "scene": "res://scenes/skills/skill_storm_chain_bolt.tscn",
		"icon": "res://assets/sprites/items/icon_storm_chain_bolt.png",
		"cooldown": 4.0, "mana_cost": 16.0, "damage_mult": 1.4,
		"sfx": "res://assets/audio/sfx/player/player_storm_chain_bolt.mp3",
		"spawn": "at_caster", "behavior": "chain",
		"mod_wiring": {"jump_bonus": {"modifier": "storm_bolt_jumps"}},
	},
	"storm_step": {
		"name": "Storm Step", "scene": "res://scenes/skills/skill_storm_step.tscn",
		"icon": "res://assets/sprites/items/icon_storm_step.png",
		"cooldown": 5.0, "mana_cost": 12.0, "damage_mult": 1.1,
		"sfx": "res://assets/audio/sfx/player/player_storm_step_dash.mp3",
		"spawn": "with_caster", "behavior": "dash",
	},
	"storm_sky_strike": {
		"name": "Sky Strike", "scene": "res://scenes/skills/skill_storm_sky_strike.tscn",
		"icon": "res://assets/sprites/items/icon_storm_sky_strike.png",
		"cooldown": 14.0, "mana_cost": 30.0, "damage_mult": 0.8,
		"sfx": "res://assets/audio/sfx/player/player_storm_sky_strike_warn.mp3",
		"spawn": "with_caster", "behavior": "telegraph_aoe",
	},
	"storm_static_discharge": {
		"name": "Static Discharge", "scene": "res://scenes/skills/skill_storm_static_discharge.tscn",
		"icon": "res://assets/sprites/items/icon_storm_static_discharge.png",
		"cooldown": 16.0, "mana_cost": 22.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_storm_static_discharge.mp3",
		"spawn": "at_caster", "behavior": "aoe",
	},
	# ── ASCENSION (Spec Path) R abilities ──
	# Battlemage (Mage). Icon/sfx reuse fire assets as placeholders for now.
	"arcane_flameblade": {
		"name": "Arcane Flameblade", "scene": "res://scenes/skills/skill_arcane_flameblade.tscn",
		"icon": "res://assets/sprites/items/icon_skill_fire_wall.png",
		"cooldown": 70.0, "mana_cost": 60.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_fire_wall.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	# Battlemage slot transforms (replace Fire Wall / Ice Bolt / Meteor).
	"flame_cleave": {
		"name": "Flame Cleave", "scene": "res://scenes/skills/skill_flame_cleave.tscn",
		"icon": "res://assets/sprites/items/icon_skill_fire_wall.png",
		"cooldown": 6.0, "mana_cost": 20.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_melee_swing.mp3",
		"spawn": "ahead_of_caster", "behavior": "melee_arc",
	},
	"frost_guard": {
		"name": "Frost Guard", "scene": "res://scenes/skills/skill_frost_guard.tscn",
		"icon": "res://assets/sprites/items/icon_skill_ice_bolt.png",
		"cooldown": 10.0, "mana_cost": 24.0, "damage_mult": 0.5,
		"sfx": "res://assets/audio/sfx/player/player_spell_ice_bolt.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"falling_brand": {
		"name": "Falling Brand", "scene": "res://scenes/skills/skill_falling_brand.tscn",
		"icon": "res://assets/sprites/items/icon_skill_meteor.png",
		"cooldown": 8.0, "mana_cost": 26.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_spell_meteor.mp3",
		"spawn": "ahead_of_caster", "behavior": "telegraph_aoe",
	},
	# Elementalist R (Mage).
	"elemental_orbit": {
		"name": "Elemental Orbit", "scene": "res://scenes/skills/skill_elemental_orbit.tscn",
		"icon": "res://assets/sprites/items/icon_skill_chain_lightning.png",
		"cooldown": 38.0, "mana_cost": 45.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_chain_lightning.mp3",
		"spawn": "at_caster", "behavior": "projectile",
	},
	# Chronomancer R (Mage).
	"temporal_dome": {
		"name": "Temporal Dome", "scene": "res://scenes/skills/skill_temporal_dome.tscn",
		"icon": "res://assets/sprites/items/icon_skill_ice_bolt.png",
		"cooldown": 55.0, "mana_cost": 70.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_ice_bolt.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	# Chronomancer slot transforms (replace Fire Wall / Chain Lightning / Meteor).
	"time_wall": {
		"name": "Time Wall", "scene": "res://scenes/skills/skill_time_wall.tscn",
		"icon": "res://assets/sprites/items/icon_skill_fire_wall.png",
		"cooldown": 8.0, "mana_cost": 22.0, "damage_mult": 0.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_ice_bolt.mp3",
		"spawn": "ahead_of_caster", "behavior": "ground",
	},
	"time_link": {
		"name": "Time Link", "scene": "res://scenes/skills/skill_time_link.tscn",
		"icon": "res://assets/sprites/items/icon_skill_chain_lightning.png",
		"cooldown": 9.0, "mana_cost": 26.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_chain_lightning.mp3",
		"spawn": "at_caster", "behavior": "chain",
	},
	"stasis_star": {
		"name": "Stasis Star", "scene": "res://scenes/skills/skill_stasis_star.tscn",
		"icon": "res://assets/sprites/items/icon_skill_meteor.png",
		"cooldown": 12.0, "mana_cost": 36.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_spell_meteor.mp3",
		"spawn": "at_target", "behavior": "telegraph_aoe",
	},
	# ── BARBARIAN ASCENSIONS ──
	# Berserker R + slot swaps.
	"barb_blood_frenzy": {
		"name": "Blood Frenzy", "scene": "res://scenes/skills/skill_barb_blood_frenzy.tscn",
		"icon": "res://assets/sprites/items/icon_barb_cry.png",
		"cooldown": 65.0, "mana_cost": 40.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_battlecry.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"barb_bloodstorm": {
		"name": "Bloodstorm", "scene": "res://scenes/skills/skill_barb_bloodstorm.tscn",
		"icon": "res://assets/sprites/items/icon_barb_whirlwind.png",
		"cooldown": 9.0, "mana_cost": 20.0, "damage_mult": 0.5,
		"sfx": "res://assets/audio/sfx/player/player_spell_whirlwind.mp3",
		"spawn": "attached_to_caster", "behavior": "melee_arc",
	},
	"barb_skullcrack_leap": {
		"name": "Skullcrack Leap", "scene": "res://scenes/skills/skill_barb_skullcrack_leap.tscn",
		"icon": "res://assets/sprites/items/icon_barb_leap.png",
		"cooldown": 9.0, "mana_cost": 22.0, "damage_mult": 1.8,
		"sfx": "res://assets/audio/sfx/player/player_spell_leap.mp3",
		"spawn": "with_caster", "behavior": "dash",
	},
	"barb_rage_howl": {
		"name": "Rage Howl", "scene": "res://scenes/skills/skill_barb_rage_howl.tscn",
		"icon": "res://assets/sprites/items/icon_barb_cry.png",
		"cooldown": 14.0, "mana_cost": 10.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_battlecry.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	# Warchief R + slot swaps.
	"barb_banner": {
		"name": "Banner of the Ancients", "scene": "res://scenes/skills/skill_barb_banner.tscn",
		"icon": "res://assets/sprites/items/icon_barb_cry.png",
		"cooldown": 75.0, "mana_cost": 60.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_battlecry.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	"barb_commanding_shout": {
		"name": "Commanding Shout", "scene": "res://scenes/skills/skill_barb_commanding_shout.tscn",
		"icon": "res://assets/sprites/items/icon_barb_cry.png",
		"cooldown": 16.0, "mana_cost": 26.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_battlecry.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"barb_war_ground": {
		"name": "War Ground", "scene": "res://scenes/skills/skill_barb_war_ground.tscn",
		"icon": "res://assets/sprites/items/icon_barb_quake.png",
		"cooldown": 14.0, "mana_cost": 34.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_earthquake.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	"barb_guardian_leap": {
		"name": "Guardian Leap", "scene": "res://scenes/skills/skill_barb_guardian_leap.tscn",
		"icon": "res://assets/sprites/items/icon_barb_leap.png",
		"cooldown": 10.0, "mana_cost": 24.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_spell_leap.mp3",
		"spawn": "with_caster", "behavior": "dash",
	},
	# Titanbreaker R + slot swaps.
	"barb_worldsplitter": {
		"name": "Worldsplitter", "scene": "res://scenes/skills/skill_barb_worldsplitter.tscn",
		"icon": "res://assets/sprites/items/icon_barb_quake.png",
		"cooldown": 50.0, "mana_cost": 55.0, "damage_mult": 2.8,
		"sfx": "res://assets/audio/sfx/player/player_spell_earthquake.mp3",
		"spawn": "at_caster", "behavior": "telegraph_aoe",
	},
	"barb_stone_grinder": {
		"name": "Stone Grinder", "scene": "res://scenes/skills/skill_barb_stone_grinder.tscn",
		"icon": "res://assets/sprites/items/icon_barb_whirlwind.png",
		"cooldown": 9.0, "mana_cost": 20.0, "damage_mult": 0.5,
		"sfx": "res://assets/audio/sfx/player/player_spell_whirlwind.mp3",
		"spawn": "attached_to_caster", "behavior": "melee_arc",
	},
	"barb_fault_zone": {
		"name": "Fault Zone", "scene": "res://scenes/skills/skill_barb_fault_zone.tscn",
		"icon": "res://assets/sprites/items/icon_barb_quake.png",
		"cooldown": 14.0, "mana_cost": 36.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_spell_earthquake.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	"barb_tremor_roar": {
		"name": "Tremor Roar", "scene": "res://scenes/skills/skill_barb_tremor_roar.tscn",
		"icon": "res://assets/sprites/items/icon_barb_cry.png",
		"cooldown": 14.0, "mana_cost": 28.0, "damage_mult": 1.2,
		"sfx": "res://assets/audio/sfx/player/player_spell_battlecry.mp3",
		"spawn": "at_caster", "behavior": "aoe",
	},
}

static var _defs: Dictionary = {}
static var _built: bool = false


static func _ensure_built() -> void:
	if _built:
		return
	for skill_id in _RAW:
		_defs[skill_id] = SkillDefinition.make(String(skill_id), _RAW[skill_id])
	_built = true


static func get_def(skill_id: String) -> SkillDefinition:
	_ensure_built()
	return _defs.get(skill_id, null)


static func has(skill_id: String) -> bool:
	_ensure_built()
	return _defs.has(skill_id)


static func all_ids() -> Array:
	_ensure_built()
	return _defs.keys()
