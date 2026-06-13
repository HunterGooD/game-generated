class_name SkillCatalog
extends RefCounted

# Static registry of every castable skill as a typed SkillDefinition, plus the
# catalog-level lookup maps (transform overrides, druid form slots). Built once,
# lazily, from the raw data below. SkillSystem reads through this instead of the
# old inline SKILL_CATALOG dictionary. Authoring stays in code for now; each
# entry can be exported to a .tres SkillDefinition later without touching callers.

# Slot-swap / variant transform maps — DERIVED from the single SkillTrees table
# (every variant node), so adding a tree variant needs no edit here.
#   transform_overrides(): transform id → catalog skill id to cast instead of the
#     base. Only "slot-swap" variants (a separate catalog skill); ctx-variants
#     (ice_wall, hexen_bloodmoon, …) keep the base scene and branch on
#     ctx.transform inside the skill script, so they're NOT in overrides.
#   transform_base(): transform id → the BASE skill it belongs to. The guard in
#     SkillSystem.get_transform deactivates a variant while the slot holds a
#     different skill (druid forms reuse slots 0/1 per shape).
static var _xf_overrides: Dictionary = {}
static var _xf_base: Dictionary = {}
static var _xf_built: bool = false

# transform id → catalog skill id when they differ (else identity).
const _XF_ALIASES := {"druid_dire_wolf": "druid_dire_wolf_form"}

# Variants implemented as a ctx-flag on the BASE scene (no separate skill, no
# slot swap). The base skill's script branches on ctx.transform == this id.
const CTX_VARIANTS := {
	"ice_wall": true,
	"stone_armor_grinder": true,
	"hexen_bloodmoon": true,
	"hexen_eternal_mark": true,
	"hexen_tether_shock": true,
	"storm_capacitor_core": true,
	"storm_heavens_spear": true,
	"storm_stormveil": true,
}


static func _ensure_transform_maps() -> void:
	if _xf_built:
		return
	_xf_built = true
	for b in SkillTrees.all_variant_bindings():
		var t: String = String(b["transform"])
		_xf_base[t] = String(b["base_skill"])
		if CTX_VARIANTS.has(t):
			continue
		_xf_overrides[t] = String(_XF_ALIASES.get(t, t))


static func transform_overrides() -> Dictionary:
	_ensure_transform_maps()
	return _xf_overrides


static func transform_base() -> Dictionary:
	_ensure_transform_maps()
	return _xf_base

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
	# MAGE TALENT TRANSFORMS — slot swaps bought in the run talent tree.
	"frost_nova": {
		# TODO(art): dedicated icon; reuses Ice Bolt's for now.
		"name": "Frost Nova", "scene": "res://scenes/skills/skill_frost_nova.tscn",
		"icon": "res://assets/sprites/items/icon_skill_ice_bolt.png",
		"cooldown": 6.0, "mana_cost": 18.0, "damage_mult": 1.2,
		"sfx": "res://assets/audio/sfx/player/player_spell_ice_bolt.mp3",
		"spawn": "at_caster", "behavior": "aoe",
		"mod_wiring": {"slow_stacks": {"modifier": "ib_slow"}},
	},
	"death_beam": {
		# TODO(art): dedicated icon; reuses Chain Lightning's for now.
		"name": "Death Beam", "scene": "res://scenes/skills/skill_death_beam.tscn",
		"icon": "res://assets/sprites/items/icon_skill_chain_lightning.png",
		"cooldown": 9.0, "mana_cost": 28.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_spell_chain_lightning.mp3",
		"spawn": "at_caster", "behavior": "aoe",
		"mod_wiring": {"length_bonus": {"modifier": "cl_jumps", "mul": 120.0}},
	},
	"meteor_shower": {
		# Same scene as Meteor — the script branches on ctx.transform to rain
		# several smaller meteors instead of one big rock. TODO(art): own icon.
		"name": "Meteor Shower", "scene": "res://scenes/skills/skill_meteor.tscn",
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
	# BARBARIAN SKILL-BLOCK OPTIONS — alternates pickable in the skill blocks
	# (SkillBlocks.BLOCKS). Data-only where the composed runner suffices.
	"barb_cleave": {
		# TODO(art): dedicated icon; reuses Whirlwind's for now.
		"name": "Cleave", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_barb_whirlwind.png",
		"cooldown": 5.0, "mana_cost": 14.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_melee_swing.mp3",
		"spawn": "ahead_of_caster", "behavior": "melee_arc",
		"effects": [
			{
				"type": "vfx", "explosion_scale": 0.9,
				"explosion_color": Color(0.9, 0.6, 0.4, 1), "shake_strength": 2.0, "shake_time": 0.12
			},
			{"type": "area_damage", "radius": 110.0, "damage_mult": 1.0},
		],
	},
	"barb_sword_throw": {
		# TODO(art): dedicated icon + sword projectile; reuses the thrown dagger.
		"name": "Sword Throw", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_barb_whirlwind.png",
		"cooldown": 4.0, "mana_cost": 12.0, "damage_mult": 1.8,
		"sfx": "res://assets/audio/sfx/player/player_dagger_throw.mp3",
		"spawn": "at_caster", "behavior": "projectile",
		"effects": [
			{
				"type": "projectile", "scene_path": "res://scenes/combat/player/thrown_dagger.tscn",
				"count": 1, "aimed": true, "arc": 0.0, "spawn_offset": 28.0
			},
		],
	},
	"barb_charge": {
		# TODO(art): dedicated icon; reuses Leap Slam's for now.
		"name": "Crushing Charge", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_barb_leap.png",
		"cooldown": 7.0, "mana_cost": 18.0, "damage_mult": 1.5,
		"sfx": "res://assets/audio/sfx/player/player_spell_leap.mp3",
		"spawn": "with_caster", "behavior": "dash",
		"effects": [
			{
				"type": "dash", "max_distance": 340.0, "width": 70.0, "duration": 0.18,
				"path_damage": true,
				"sparks_color": Color(0.95, 0.6, 0.3, 1), "sparks_count": 10
			},
		],
	},
	"barb_chain_hook": {
		# TODO(art): dedicated icon; reuses Leap Slam's for now.
		"name": "Chain Hook", "scene": "res://scenes/skills/skill_barb_chain_hook.tscn",
		"icon": "res://assets/sprites/items/icon_barb_leap.png",
		"cooldown": 8.0, "mana_cost": 20.0, "damage_mult": 0.8,
		"sfx": "res://assets/audio/sfx/player/player_melee_swing.mp3",
		"spawn": "at_caster", "behavior": "melee_arc",
		"mod_wiring": {"angle_bonus": {"modifier": "barb_hook_angle", "mul": 12.0}},
	},
	# SKILL-BLOCK COPIES OF ASCENSION R ABILITIES — same scenes, retuned from
	# ult pacing (50–80s) to regular-slot pacing. Separate ids so a later
	# ascension's R never collides with the block pick.
	"barb_banner_block": {
		"name": "Victory Banner", "scene": "res://scenes/skills/skill_barb_banner.tscn",
		"icon": "res://assets/sprites/items/icon_barb_cry.png",
		"cooldown": 30.0, "mana_cost": 40.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_battlecry.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	"barb_blood_frenzy_block": {
		"name": "Berserk", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_barb_cry.png",
		"cooldown": 28.0, "mana_cost": 30.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_battlecry.mp3",
		"spawn": "at_caster", "behavior": "buff",
		"effects": [
			{"type": "caster_call", "method": "start_frenzy", "args": [15.0]},
			{
				"type": "vfx", "sparks_color": Color(0.9, 0.1, 0.12, 1), "sparks_count": 20,
				"flash_color": Color(0.7, 0.05, 0.08, 0.22), "flash_time": 0.25,
				"shake_strength": 4.0, "shake_time": 0.2
			},
		],
	},
	"barb_worldsplitter_block": {
		"name": "Titan Strike", "scene": "res://scenes/skills/skill_barb_worldsplitter.tscn",
		"icon": "res://assets/sprites/items/icon_barb_quake.png",
		"cooldown": 22.0, "mana_cost": 40.0, "damage_mult": 2.2,
		"sfx": "res://assets/audio/sfx/player/player_spell_earthquake.mp3",
		"spawn": "at_caster", "behavior": "telegraph_aoe",
	},
	"storm_eye_of_storm_block": {
		"name": "Eye of the Storm", "scene": "res://scenes/skills/skill_storm_eye_of_storm.tscn",
		"icon": "res://assets/sprites/items/icon_storm_sky_strike.png",
		"cooldown": 26.0, "mana_cost": 45.0, "damage_mult": 0.8,
		"sfx": "res://assets/audio/sfx/player/player_storm_sky_strike_warn.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	"necro_crown_of_dead_block": {
		"name": "Crown of the Dead", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_necro_blood_pact.png",
		"cooldown": 26.0, "mana_cost": 40.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_blood_pact.mp3",
		"spawn": "at_caster", "behavior": "buff",
		"effects": [
			{"type": "caster_call", "method": "apply_buff", "args": [10.0, 1.15, 1.05]},
			{
				"type": "group_call", "group": "necro_minion",
				"method": "apply_blood_pact", "args": [10.0, 1.2, 1.1]
			},
			{"type": "vfx", "sparks_color": Color(0.6, 0.4, 0.9, 1), "sparks_count": 14},
		],
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
		"name": "Fan of Knives", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_knives.png",
		"cooldown": 10.0, "mana_cost": 30.0, "damage_mult": 1.3,
		"sfx": "res://assets/audio/sfx/player/player_spell_fan_knives.mp3",
		"spawn": "at_caster", "behavior": "melee_arc",
		"mod_wiring": {"count_bonus": {"modifier": "rogue_knives_count", "mul": 2}},
		"effects": [
			{
				"type": "projectile", "scene_path": "res://scenes/combat/player/thrown_dagger.tscn",
				"count": 8, "count_modifier": "count_bonus", "spawn_offset": 28.0,
				"unique_meta": "venomweave"
			},
			{"type": "vfx", "sparks_color": Color(1.0, 0.8, 0.6, 1), "sparks_count": 8},
		],
	},
	# DRUID
	"druid_wolf_form": {
		"name": "Wolf Form", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_druid_wolf_form.png",
		"cooldown": 16.0, "mana_cost": 20.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_wolf.mp3",
		"spawn": "at_caster", "behavior": "transform",
		"effects": [
			{
				"type": "transform", "form": "wolf", "base_duration": 20.0,
				"per_stack": 4.0, "duration_modifier": "wolf_duration", "modifier_slot": 0
			},
			{"type": "vfx", "sparks_color": Color(1.0, 0.55, 0.4, 1), "sparks_count": 14},
		],
	},
	"druid_bear_form": {
		"name": "Bear Form", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_druid_bear_form.png",
		"cooldown": 16.0, "mana_cost": 20.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_bear.mp3",
		"spawn": "at_caster", "behavior": "transform",
		"effects": [
			{
				"type": "transform", "form": "bear", "base_duration": 20.0,
				"per_stack": 4.0, "duration_modifier": "bear_duration", "modifier_slot": 1
			},
			{"type": "vfx", "sparks_color": Color(0.85, 0.7, 0.4, 1), "sparks_count": 14},
		],
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
		"name": "Arcane Flameblade", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_skill_fire_wall.png",
		"cooldown": 70.0, "mana_cost": 60.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_fire_wall.mp3",
		"spawn": "at_caster", "behavior": "buff",
		"effects": [
			{"type": "caster_call", "method": "apply_buff", "args": [20.0, 1.35, 1.1]},
			{"type": "caster_call", "method": "start_flameblade", "args": [20.0]},
			{
				"type": "vfx", "sparks_color": Color(1.0, 0.5, 0.2, 1), "sparks_count": 16,
				"flash_color": Color(1.0, 0.55, 0.25, 0.18), "flash_time": 0.2
			},
		],
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
		"name": "Stasis Star", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_skill_meteor.png",
		"cooldown": 12.0, "mana_cost": 36.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_spell_meteor.mp3",
		"spawn": "at_target", "behavior": "telegraph_aoe",
		"effects": [
			{
				"type": "telegraph", "delay": 0.5, "radius": 150.0,
				"chill_duration": 0.7, "chill_stacks": 4,
				"ally_shield_frac": 0.5, "caster_shield_frac": 0.75,
				"cooldown_refund": 1.0, "notify_control": true,
				"telegraph_texture": "res://assets/sprites/effects/fire_flame.png",
				"telegraph_color": Color(0.55, 0.85, 1.0, 0.9), "telegraph_scale": 2.4,
				"explosion_scale": 1.5, "explosion_color": Color(0.5, 0.85, 1.0, 1),
				"shake_strength": 8.0, "shake_time": 0.3,
				"flash_color": Color(0.5, 0.8, 1.0, 0.25), "flash_time": 0.2
			},
		],
	},
	# ── BARBARIAN ASCENSIONS ──
	# Berserker R + slot swaps.
	"barb_blood_frenzy": {
		"name": "Blood Frenzy", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_barb_cry.png",
		"cooldown": 65.0, "mana_cost": 40.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_battlecry.mp3",
		"spawn": "at_caster", "behavior": "buff",
		"effects": [
			{"type": "caster_call", "method": "start_frenzy", "args": [15.0]},
			{
				"type": "vfx", "sparks_color": Color(0.9, 0.1, 0.12, 1), "sparks_count": 20,
				"flash_color": Color(0.7, 0.05, 0.08, 0.22), "flash_time": 0.25,
				"shake_strength": 4.0, "shake_time": 0.2
			},
		],
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
		"name": "Commanding Shout", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_barb_cry.png",
		"cooldown": 16.0, "mana_cost": 26.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_battlecry.mp3",
		"spawn": "at_caster", "behavior": "buff",
		"effects": [
			{
				"type": "vfx", "explosion_scale": 1.2,
				"explosion_color": Color(0.5, 0.8, 1.0, 1), "shake_strength": 3.0, "shake_time": 0.18
			},
			{
				"type": "group_shield", "groups": ["player", "remote_player"],
				"radius": 260.0, "shield_frac": 0.18
			},
		],
	},
	"barb_war_ground": {
		"name": "War Ground", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_barb_quake.png",
		"cooldown": 14.0, "mana_cost": 34.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_earthquake.mp3",
		"spawn": "at_caster", "behavior": "ground",
		"effects": [
			{
				"type": "aura", "radius": 200.0, "lifetime": 6.0, "tick_interval": 0.5,
				"tick_damage_mult": 1.0, "enemy_slow_dur": 0.3, "enemy_slow_mult": 0.6,
				"ally_aura_dr": 0.2, "ring_color": Color(0.75, 0.6, 0.35, 0.4),
				"ring_texture_path": "res://assets/sprites/effects/fire_ring.png"
			},
		],
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
	# ── ROGUE ASCENSIONS ──
	"rogue_deathmark_dash": {
		"name": "Deathmark Dash", "scene": "res://scenes/skills/skill_rogue_deathmark_dash.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_knives.png",
		"cooldown": 60.0, "mana_cost": 45.0, "damage_mult": 2.2,
		"sfx": "res://assets/audio/sfx/player/player_dagger_throw.mp3",
		"spawn": "with_caster", "behavior": "dash",
	},
	"rogue_vanish": {
		"name": "Vanish", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_smoke.png",
		"cooldown": 12.0, "mana_cost": 20.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_smoke_bomb.mp3",
		"spawn": "at_caster", "behavior": "buff",
		"params": {"lifetime": 0.5},
		"effects": [
			{"type": "vfx", "sparks_color": Color(0.5, 0.5, 0.6, 1), "sparks_count": 16},
			{"type": "caster_call", "method": "apply_stealth", "args": [1.5]},
			{"type": "caster_call", "method": "start_backstab", "args": [2.0]},
		],
	},
	"rogue_execution_fan": {
		"name": "Execution Fan", "scene": "res://scenes/skills/skill_rogue_execution_fan.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_knives.png",
		"cooldown": 10.0, "mana_cost": 30.0, "damage_mult": 1.3,
		"sfx": "res://assets/audio/sfx/player/player_spell_fan_knives.mp3",
		"spawn": "at_caster", "behavior": "melee_arc",
	},
	"rogue_razor_trap": {
		"name": "Razor Trap", "scene": "res://scenes/skills/skill_rogue_razor_trap.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_caltrops.png",
		"cooldown": 8.0, "mana_cost": 18.0, "damage_mult": 0.4,
		"sfx": "res://assets/audio/sfx/player/player_spell_caltrops.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	"rogue_decoy_mirage": {
		"name": "Decoy Mirage", "scene": "res://scenes/skills/skill_rogue_decoy_mirage.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_smoke.png",
		"cooldown": 70.0, "mana_cost": 50.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_smoke_bomb.mp3",
		"spawn": "at_caster", "behavior": "summon",
	},
	"rogue_safehouse": {
		"name": "Safehouse", "scene": "res://scenes/skills/skill_rogue_safehouse.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_smoke.png",
		"cooldown": 12.0, "mana_cost": 20.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_smoke_bomb.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	"rogue_trick_field": {
		"name": "Trick Field", "scene": "res://scenes/skills/skill_rogue_trick_field.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_caltrops.png",
		"cooldown": 8.0, "mana_cost": 18.0, "damage_mult": 0.3,
		"sfx": "res://assets/audio/sfx/player/player_spell_caltrops.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	"rogue_confusion_flask": {
		"name": "Confusion Flask", "scene": "res://scenes/skills/skill_rogue_confusion_flask.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_poison.png",
		"cooldown": 9.0, "mana_cost": 22.0, "damage_mult": 0.5,
		"sfx": "res://assets/audio/sfx/player/player_spell_poison.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	"rogue_plague_bloom": {
		"name": "Plague Bloom", "scene": "res://scenes/skills/skill_rogue_plague_bloom.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_poison.png",
		"cooldown": 55.0, "mana_cost": 60.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_poison.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	"rogue_triple_flask": {
		"name": "Triple Flask", "scene": "res://scenes/skills/skill_rogue_triple_flask.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_poison.png",
		"cooldown": 7.0, "mana_cost": 22.0, "damage_mult": 0.45,
		"sfx": "res://assets/audio/sfx/player/player_spell_poison.mp3",
		"spawn": "at_caster", "behavior": "projectile",
	},
	"rogue_venom_fan": {
		"name": "Venom Fan", "scene": "res://scenes/skills/skill_rogue_venom_fan.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_knives.png",
		"cooldown": 10.0, "mana_cost": 30.0, "damage_mult": 1.3,
		"sfx": "res://assets/audio/sfx/player/player_spell_fan_knives.mp3",
		"spawn": "at_caster", "behavior": "melee_arc",
	},
	"rogue_toxic_spikes": {
		"name": "Toxic Spikes", "scene": "res://scenes/skills/skill_rogue_toxic_spikes.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_caltrops.png",
		"cooldown": 8.0, "mana_cost": 18.0, "damage_mult": 0.4,
		"sfx": "res://assets/audio/sfx/player/player_spell_caltrops.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	# ── STORMCALLER ASCENSIONS ──
	"storm_lightning_overdrive": {
		"name": "Lightning Overdrive", "scene": "res://scenes/skills/skill_storm_lightning_overdrive.tscn",
		"icon": "res://assets/sprites/items/icon_storm_static_discharge.png",
		"cooldown": 70.0, "mana_cost": 65.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_storm_static_discharge.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"storm_thunder_lunge": {
		"name": "Thunder Lunge", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_storm_step.png",
		"cooldown": 5.0, "mana_cost": 14.0, "damage_mult": 1.4,
		"sfx": "res://assets/audio/sfx/player/player_storm_step_dash.mp3",
		"spawn": "with_caster", "behavior": "dash",
		"effects": [
			{
				"type": "dash", "max_distance": 320.0, "width": 64.0, "duration": 0.15,
				"path_damage": true, "mark_element": "storm",
				"sparks_color": Color(0.7, 0.85, 1.0, 1), "sparks_count": 10
			},
		],
	},
	"storm_body_discharge": {
		"name": "Body Discharge", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_storm_static_discharge.png",
		"cooldown": 16.0, "mana_cost": 22.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_storm_static_discharge.mp3",
		"spawn": "at_caster", "behavior": "aoe",
		"effects": [
			{
				"type": "vfx", "explosion_scale": 1.2,
				"explosion_color": Color(0.7, 0.85, 1.0, 1), "shake_strength": 5.0, "shake_time": 0.2
			},
			{"type": "area_damage", "radius": 130.0, "damage_mult": 1.25, "mark_element": "storm"},
		],
	},
	"storm_charged_slash": {
		"name": "Charged Slash", "scene": "res://scenes/skills/skill_storm_charged_slash.tscn",
		"icon": "res://assets/sprites/items/icon_storm_chain_bolt.png",
		"cooldown": 4.0, "mana_cost": 16.0, "damage_mult": 1.4,
		"sfx": "res://assets/audio/sfx/player/player_storm_chain_bolt.mp3",
		"spawn": "at_caster", "behavior": "melee_arc",
	},
	"storm_eye_of_storm": {
		"name": "Eye of the Storm", "scene": "res://scenes/skills/skill_storm_eye_of_storm.tscn",
		"icon": "res://assets/sprites/items/icon_storm_sky_strike.png",
		"cooldown": 65.0, "mana_cost": 80.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_storm_sky_strike_warn.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	"storm_forked_bolt": {
		"name": "Forked Bolt", "scene": "res://scenes/skills/skill_storm_forked_bolt.tscn",
		"icon": "res://assets/sprites/items/icon_storm_chain_bolt.png",
		"cooldown": 4.0, "mana_cost": 16.0, "damage_mult": 1.4,
		"sfx": "res://assets/audio/sfx/player/player_storm_chain_bolt.mp3",
		"spawn": "at_caster", "behavior": "chain",
	},
	"storm_controlled_discharge": {
		"name": "Controlled Discharge", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_storm_static_discharge.png",
		"cooldown": 16.0, "mana_cost": 22.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_storm_static_discharge.mp3",
		"spawn": "at_target", "behavior": "aoe",
		"effects": [
			{"type": "vfx", "explosion_scale": 1.1, "explosion_color": Color(0.6, 0.8, 1.0, 1)},
			{
				"type": "area_damage", "radius": 140.0, "mark_element": "storm",
				"slow_duration": 1.5, "slow_mult": 0.6
			},
		],
	},
	"storm_pillar": {
		"name": "Storm Pillar", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_storm_sky_strike.png",
		"cooldown": 14.0, "mana_cost": 30.0, "damage_mult": 0.8,
		"sfx": "res://assets/audio/sfx/player/player_storm_sky_strike_warn.mp3",
		"spawn": "at_target", "behavior": "telegraph_aoe",
		"effects": [
			{
				"type": "aura", "radius": 120.0, "lifetime": 4.0, "tick_interval": 0.5,
				"telegraph_delay": 0.5, "tick_damage_mult": 0.5, "mark_element": "storm",
				"strike_explosion_scale": 1.3, "strike_explosion_color": Color(0.7, 0.9, 1.0, 1),
				"strike_shake": 5.0, "ring_color": Color(0.6, 0.8, 1.0, 0.6),
				"ring_texture_path": "res://assets/sprites/effects/meteor_telegraph.png"
			},
		],
	},
	"storm_living_battery": {
		"name": "Living Battery", "scene": "res://scenes/skills/skill_storm_living_battery.tscn",
		"icon": "res://assets/sprites/items/icon_storm_chain_bolt.png",
		"cooldown": 50.0, "mana_cost": 70.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_storm_chain_bolt.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	"storm_rescue_step": {
		"name": "Rescue Step", "scene": "res://scenes/skills/skill_storm_rescue_step.tscn",
		"icon": "res://assets/sprites/items/icon_storm_step.png",
		"cooldown": 5.0, "mana_cost": 14.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_storm_step_dash.mp3",
		"spawn": "with_caster", "behavior": "dash",
	},
	"storm_energizing_discharge": {
		"name": "Energizing Discharge", "scene": "res://scenes/skills/skill_storm_energizing_discharge.tscn",
		"icon": "res://assets/sprites/items/icon_storm_static_discharge.png",
		"cooldown": 16.0, "mana_cost": 22.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_storm_static_discharge.mp3",
		"spawn": "at_caster", "behavior": "aoe",
	},
	"storm_ally_arc": {
		"name": "Ally Arc", "scene": "res://scenes/skills/skill_storm_ally_arc.tscn",
		"icon": "res://assets/sprites/items/icon_storm_chain_bolt.png",
		"cooldown": 4.0, "mana_cost": 16.0, "damage_mult": 1.4,
		"sfx": "res://assets/audio/sfx/player/player_storm_chain_bolt.mp3",
		"spawn": "at_caster", "behavior": "chain",
	},
	# ── HEXEN ASCENSIONS ──
	"hexen_scarlet_possession": {
		"name": "Scarlet Possession", "scene": "res://scenes/skills/skill_hexen_scarlet_possession.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_blood_whip.png",
		"cooldown": 65.0, "mana_cost": 40.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_hexen_blood_whip.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"hexen_blood_scythe": {
		"name": "Blood Scythe", "scene": "res://scenes/skills/skill_hexen_blood_scythe.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_blood_whip.png",
		"cooldown": 5.0, "mana_cost": 18.0, "damage_mult": 1.3,
		"sfx": "res://assets/audio/sfx/player/player_hexen_blood_whip.mp3",
		"spawn": "ahead_of_caster", "behavior": "melee_arc",
	},
	"hexen_open_wound": {
		"name": "Open Wound", "scene": "res://scenes/skills/skill_hexen_open_wound.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_hex_mark.png",
		"cooldown": 2.0, "mana_cost": 14.0, "damage_mult": 0.9,
		"sfx": "res://assets/audio/sfx/player/player_hexen_hex_mark_apply.mp3",
		"spawn": "at_target", "behavior": "mark",
	},
	"hexen_blood_arena": {
		"name": "Blood Arena", "scene": "res://scenes/skills/skill_hexen_blood_arena.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_crimson_ritual.png",
		"cooldown": 18.0, "mana_cost": 36.0, "damage_mult": 0.5,
		"sfx": "res://assets/audio/sfx/player/player_hexen_crimson_ritual.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	"hexen_grand_malediction": {
		"name": "Grand Malediction", "scene": "res://scenes/skills/skill_hexen_grand_malediction.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_hex_mark.png",
		"cooldown": 40.0, "mana_cost": 75.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_hexen_hex_mark_apply.mp3",
		"spawn": "at_caster", "behavior": "aoe",
	},
	"hexen_rotating_hex": {
		"name": "Rotating Hex", "scene": "res://scenes/skills/skill_hexen_rotating_hex.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_hex_mark.png",
		"cooldown": 2.0, "mana_cost": 14.0, "damage_mult": 0.9,
		"sfx": "res://assets/audio/sfx/player/player_hexen_hex_mark_apply.mp3",
		"spawn": "at_target", "behavior": "mark",
	},
	"hexen_curse_chain": {
		"name": "Curse Chain", "scene": "res://scenes/skills/skill_hexen_curse_chain.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_soul_tether.png",
		"cooldown": 12.0, "mana_cost": 32.0, "damage_mult": 0.6,
		"sfx": "res://assets/audio/sfx/player/player_hexen_soul_tether.mp3",
		"spawn": "at_caster", "behavior": "chain",
	},
	"hexen_ritual_of_doom": {
		"name": "Ritual of Doom", "scene": "res://scenes/skills/skill_hexen_ritual_of_doom.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_crimson_ritual.png",
		"cooldown": 18.0, "mana_cost": 36.0, "damage_mult": 0.4,
		"sfx": "res://assets/audio/sfx/player/player_hexen_crimson_ritual.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	"hexen_coven_pact": {
		"name": "Coven Pact", "scene": "res://scenes/skills/skill_hexen_coven_pact.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_soul_tether.png",
		"cooldown": 80.0, "mana_cost": 85.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_hexen_soul_tether.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"hexen_ally_tether": {
		"name": "Ally Tether", "scene": "res://scenes/skills/skill_hexen_ally_tether.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_soul_tether.png",
		"cooldown": 12.0, "mana_cost": 32.0, "damage_mult": 0.6,
		"sfx": "res://assets/audio/sfx/player/player_hexen_soul_tether.mp3",
		"spawn": "at_caster", "behavior": "mark",
	},
	"hexen_safe_ritual": {
		"name": "Safe Ritual", "scene": "res://scenes/skills/skill_hexen_safe_ritual.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_crimson_ritual.png",
		"cooldown": 18.0, "mana_cost": 36.0, "damage_mult": 0.4,
		"sfx": "res://assets/audio/sfx/player/player_hexen_crimson_ritual.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	"hexen_binding_whip": {
		"name": "Binding Whip", "scene": "res://scenes/skills/skill_hexen_binding_whip.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_blood_whip.png",
		"cooldown": 5.0, "mana_cost": 18.0, "damage_mult": 1.3,
		"sfx": "res://assets/audio/sfx/player/player_hexen_blood_whip.mp3",
		"spawn": "ahead_of_caster", "behavior": "melee_arc",
	},
	# ── NECROMANCER ASCENSIONS ──
	"necro_crown_of_dead": {
		"name": "Crown of the Dead", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_necro_blood_pact.png",
		"cooldown": 80.0, "mana_cost": 75.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_blood_pact.mp3",
		"spawn": "at_caster", "behavior": "buff",
		"effects": [
			{"type": "caster_call", "method": "apply_buff", "args": [18.0, 1.25, 1.1]},
			{
				"type": "group_call", "group": "necro_minion",
				"method": "apply_blood_pact", "args": [18.0, 1.35, 1.2]
			},
			{"type": "vfx", "sparks_color": Color(0.6, 0.4, 0.9, 1), "sparks_count": 18},
		],
	},
	"necro_skeletal_legion": {
		"name": "Skeletal Legion", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_necro_raise_skeleton.png",
		"cooldown": 8.0, "mana_cost": 22.0, "damage_mult": 0.8,
		"sfx": "res://assets/audio/sfx/player/player_necro_raise_skeleton.mp3",
		"spawn": "at_target", "behavior": "summon",
		"effects": [
			{"type": "vfx", "sparks_color": Color(0.7, 0.5, 1.0, 1), "sparks_count": 14},
			{
				"type": "summon", "kind": "skeleton", "count": 3,
				"scene_path": "res://scenes/entities/necro_minion.tscn"
			},
		],
	},
	"necro_grave_champion": {
		"name": "Grave Champion", "scene": "res://scenes/skills/skill_necro_grave_champion.tscn",
		"icon": "res://assets/sprites/items/icon_necro_raise_knight.png",
		"cooldown": 16.0, "mana_cost": 40.0, "damage_mult": 1.2,
		"sfx": "res://assets/audio/sfx/player/player_necro_raise_knight.mp3",
		"spawn": "at_target", "behavior": "summon",
	},
	"necro_rally_pulse": {
		"name": "Rally Pulse", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_necro_death_pulse.png",
		"cooldown": 10.0, "mana_cost": 28.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_necro_death_pulse.mp3",
		"spawn": "at_caster", "behavior": "aoe",
		"effects": [
			{"type": "vfx", "explosion_scale": 1.4, "explosion_color": Color(0.6, 0.4, 0.9, 1)},
			{"type": "area_damage", "radius": 200.0},
			{
				"type": "group_heal", "group": "necro_minion",
				"radius": 200.0, "heal_frac": 0.25
			},
		],
	},
	"necro_bone_citadel": {
		"name": "Bone Citadel", "scene": "res://scenes/skills/skill_necro_bone_citadel.tscn",
		"icon": "res://assets/sprites/items/icon_necro_raise_knight.png",
		"cooldown": 70.0, "mana_cost": 85.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_raise_knight.mp3",
		"spawn": "at_target", "behavior": "ground",
	},
	"necro_bone_turret": {
		"name": "Bone Turret", "scene": "res://scenes/skills/skill_necro_bone_turret.tscn",
		"icon": "res://assets/sprites/items/icon_necro_raise_skeleton.png",
		"cooldown": 8.0, "mana_cost": 22.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_raise_skeleton.mp3",
		"spawn": "at_target", "behavior": "summon",
	},
	"necro_bone_golem": {
		"name": "Bone Golem", "scene": "res://scenes/skills/skill_necro_bone_golem.tscn",
		"icon": "res://assets/sprites/items/icon_necro_raise_knight.png",
		"cooldown": 16.0, "mana_cost": 40.0, "damage_mult": 1.2,
		"sfx": "res://assets/audio/sfx/player/player_necro_raise_knight.mp3",
		"spawn": "at_target", "behavior": "summon",
	},
	"necro_bone_nova": {
		"name": "Bone Nova", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_necro_death_pulse.png",
		"cooldown": 10.0, "mana_cost": 28.0, "damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_necro_death_pulse.mp3",
		"spawn": "at_caster", "behavior": "aoe",
		"effects": [
			{
				"type": "vfx", "explosion_scale": 1.6,
				"explosion_color": Color(0.85, 0.8, 0.7, 1), "shake_strength": 5.0, "shake_time": 0.2
			},
			{"type": "area_damage", "radius": 230.0},
		],
	},
	"necro_second_funeral": {
		"name": "Second Funeral", "scene": "res://scenes/skills/skill_necro_second_funeral.tscn",
		"icon": "res://assets/sprites/items/icon_necro_blood_pact.png",
		"cooldown": 95.0, "mana_cost": 90.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_blood_pact.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"necro_blood_ward": {
		"name": "Blood Ward", "scene": "res://scenes/skills/skill_necro_blood_ward.tscn",
		"icon": "res://assets/sprites/items/icon_necro_blood_pact.png",
		"cooldown": 18.0, "mana_cost": 0.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_blood_pact.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"necro_mending_pulse": {
		"name": "Mending Pulse", "scene": "res://scenes/skills/skill_necro_mending_pulse.tscn",
		"icon": "res://assets/sprites/items/icon_necro_death_pulse.png",
		"cooldown": 10.0, "mana_cost": 28.0, "damage_mult": 1.4,
		"sfx": "res://assets/audio/sfx/player/player_necro_death_pulse.mp3",
		"spawn": "at_caster", "behavior": "aoe",
	},
	"necro_oathbound_knight": {
		"name": "Oathbound Knight", "scene": "res://scenes/skills/skill_necro_oathbound_knight.tscn",
		"icon": "res://assets/sprites/items/icon_necro_raise_knight.png",
		"cooldown": 16.0, "mana_cost": 40.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_raise_knight.mp3",
		"spawn": "at_target", "behavior": "summon",
	},
	# ── DRUID ASCENSIONS ──
	"druid_apex_form": {
		"name": "Apex Form", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_druid_eagle_form.png",
		"cooldown": 80.0, "mana_cost": 70.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_bear.mp3",
		"spawn": "at_caster", "behavior": "buff",
		"effects": [
			{"type": "caster_call", "method": "apply_buff", "args": [18.0, 1.4, 1.2]},
			{
				"type": "vfx", "sparks_color": Color(0.9, 0.7, 0.3, 1), "sparks_count": 20,
				"flash_color": Color(0.7, 0.5, 0.2, 0.18), "flash_time": 0.2
			},
		],
	},
	"druid_hide_of_beast": {
		"name": "Hide of the Beast", "scene": "res://scenes/skills/skill_druid_hide_of_beast.tscn",
		"icon": "res://assets/sprites/items/icon_druid_stone_armor.png",
		"cooldown": 14.0, "mana_cost": 32.0, "damage_mult": 0.6,
		"sfx": "res://assets/audio/sfx/player/player_druid_stone_armor_form.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"druid_pack_spirit": {
		"name": "Pack Spirit", "scene": "res://scenes/skills/skill_composed.tscn",
		"icon": "res://assets/sprites/items/icon_druid_summon_spirit.png",
		"cooldown": 22.0, "mana_cost": 38.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_summon_spirit.mp3",
		"spawn": "at_caster", "behavior": "summon",
		"effects": [
			{"type": "vfx", "sparks_color": Color(0.6, 1.0, 0.6, 1), "sparks_count": 12},
			{
				"type": "summon", "kind": "spirit", "subtype": "wolf", "count": 1,
				"scene_path": "res://scenes/entities/spirit_pet.tscn"
			},
		],
	},
	"druid_living_grove": {
		"name": "Living Grove", "scene": "res://scenes/skills/skill_druid_living_grove.tscn",
		"icon": "res://assets/sprites/items/icon_druid_summon_spirit.png",
		"cooldown": 90.0, "mana_cost": 75.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_summon_spirit.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	"druid_guardian_spirit": {
		"name": "Guardian Spirit", "scene": "res://scenes/skills/skill_druid_guardian_spirit.tscn",
		"icon": "res://assets/sprites/items/icon_druid_summon_spirit.png",
		"cooldown": 22.0, "mana_cost": 38.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_summon_spirit.mp3",
		"spawn": "at_caster", "behavior": "summon",
	},
	"druid_barkskin_aura": {
		"name": "Barkskin Aura", "scene": "res://scenes/skills/skill_druid_barkskin_aura.tscn",
		"icon": "res://assets/sprites/items/icon_druid_stone_armor.png",
		"cooldown": 14.0, "mana_cost": 32.0, "damage_mult": 0.6,
		"sfx": "res://assets/audio/sfx/player/player_druid_stone_armor_form.mp3",
		"spawn": "at_caster", "behavior": "buff",
	},
	"druid_tempest_communion": {
		"name": "Tempest Communion", "scene": "res://scenes/skills/skill_druid_tempest_communion.tscn",
		"icon": "res://assets/sprites/items/icon_druid_eagle_form.png",
		"cooldown": 65.0, "mana_cost": 65.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_eagle.mp3",
		"spawn": "at_caster", "behavior": "ground",
	},
	"druid_storm_totem": {
		"name": "Storm Totem", "scene": "res://scenes/skills/skill_druid_storm_totem.tscn",
		"icon": "res://assets/sprites/items/icon_druid_summon_spirit.png",
		"cooldown": 22.0, "mana_cost": 38.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_summon_spirit.mp3",
		"spawn": "at_caster", "behavior": "summon",
	},
	"druid_earthen_pulse": {
		"name": "Earthen Pulse", "scene": "res://scenes/skills/skill_druid_earthen_pulse.tscn",
		"icon": "res://assets/sprites/items/icon_druid_stone_armor.png",
		"cooldown": 14.0, "mana_cost": 32.0, "damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_stone_armor_form.mp3",
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
