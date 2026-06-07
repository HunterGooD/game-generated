class_name SkillSystem
extends Node

# Class-aware skill system. Picks skills based on GameManager.player_class.

signal cooldown_started(slot: int, duration: float)
signal cooldown_finished(slot: int)
signal skill_failed(slot: int, reason: String)
signal modifier_applied(slot: int, modifier_id: String)
signal transform_applied(slot: int, transform_id: String)
signal skill_ids_changed

# Master catalog of all available skills, keyed by id.
# Each entry: scene path, icon, cooldown, mana cost, damage multiplier, sfx, name.
const SKILL_CATALOG := {
	# MAGE
	"fire_wall":
	{
		"name": "Fire Wall",
		"scene": "res://scenes/combat/player/skill_fire_wall.tscn",
		"icon": "res://assets/sprites/items/icon_skill_fire_wall.png",
		"cooldown": 7.0,
		"mana_cost": 22.0,
		"damage_mult": 0.6,
		"sfx": "res://assets/audio/sfx/player/player_spell_fire_wall.mp3",
		"spawn": "ahead_of_caster",
	},
	"ice_bolt":
	{
		"name": "Ice Bolt",
		"scene": "res://scenes/combat/player/skill_ice_bolt.tscn",
		"icon": "res://assets/sprites/items/icon_skill_ice_bolt.png",
		"cooldown": 4.0,
		"mana_cost": 14.0,
		"damage_mult": 1.4,
		"sfx": "res://assets/audio/sfx/player/player_spell_ice_bolt.mp3",
		"spawn": "projectile",
	},
	"chain_lightning":
	{
		"name": "Chain Lightning",
		"scene": "res://scenes/skills/skill_chain_lightning.tscn",
		"icon": "res://assets/sprites/items/icon_skill_chain_lightning.png",
		"cooldown": 9.0,
		"mana_cost": 28.0,
		"damage_mult": 1.2,
		"sfx": "res://assets/audio/sfx/player/player_spell_chain_lightning.mp3",
		"spawn": "at_caster",
	},
	"meteor":
	{
		"name": "Meteor",
		"scene": "res://scenes/skills/skill_meteor.tscn",
		"icon": "res://assets/sprites/items/icon_skill_meteor.png",
		"cooldown": 12.0,
		"mana_cost": 38.0,
		"damage_mult": 2.4,
		"sfx": "res://assets/audio/sfx/player/player_spell_meteor.mp3",
		"spawn": "at_target",
	},
	# BARBARIAN
	"whirlwind":
	{
		"name": "Whirlwind",
		"scene": "res://scenes/combat/player/skill_whirlwind.tscn",
		"icon": "res://assets/sprites/items/icon_barb_whirlwind.png",
		"cooldown": 8.0,
		"mana_cost": 18.0,
		"damage_mult": 0.5,
		"sfx": "res://assets/audio/sfx/player/player_spell_whirlwind.mp3",
		"spawn": "attached_to_caster",
	},
	"leap_slam":
	{
		"name": "Leap Slam",
		"scene": "res://scenes/skills/skill_leap_slam.tscn",
		"icon": "res://assets/sprites/items/icon_barb_leap.png",
		"cooldown": 9.0,
		"mana_cost": 22.0,
		"damage_mult": 1.8,
		"sfx": "res://assets/audio/sfx/player/player_spell_leap.mp3",
		"spawn": "with_caster",
	},
	"battle_cry":
	{
		"name": "Battle Cry",
		"scene": "res://scenes/skills/skill_battle_cry.tscn",
		"icon": "res://assets/sprites/items/icon_barb_cry.png",
		"cooldown": 18.0,
		"mana_cost": 28.0,
		"damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_battlecry.mp3",
		"spawn": "at_caster",
	},
	"earthquake":
	{
		"name": "Earthquake",
		"scene": "res://scenes/skills/skill_earthquake.tscn",
		"icon": "res://assets/sprites/items/icon_barb_quake.png",
		"cooldown": 14.0,
		"mana_cost": 36.0,
		"damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_spell_earthquake.mp3",
		"spawn": "at_caster",
	},
	# ROGUE
	"caltrops":
	{
		"name": "Caltrops",
		"scene": "res://scenes/skills/skill_caltrops.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_caltrops.png",
		"cooldown": 8.0,
		"mana_cost": 18.0,
		"damage_mult": 0.3,
		"sfx": "res://assets/audio/sfx/player/player_spell_caltrops.mp3",
		"spawn": "at_target",
	},
	"smoke_bomb":
	{
		"name": "Smoke Bomb",
		"scene": "res://scenes/skills/skill_smoke_bomb.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_smoke.png",
		"cooldown": 12.0,
		"mana_cost": 20.0,
		"damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_spell_smoke_bomb.mp3",
		"spawn": "at_caster",
	},
	"poison_vial":
	{
		"name": "Poison Vial",
		"scene": "res://scenes/combat/player/skill_poison_vial.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_poison.png",
		"cooldown": 7.0,
		"mana_cost": 22.0,
		"damage_mult": 0.45,
		"sfx": "res://assets/audio/sfx/player/player_spell_poison.mp3",
		"spawn": "at_target",
	},
	"fan_of_knives":
	{
		"name": "Fan of Knives",
		"scene": "res://scenes/skills/skill_fan_of_knives.tscn",
		"icon": "res://assets/sprites/items/icon_rogue_knives.png",
		"cooldown": 10.0,
		"mana_cost": 30.0,
		"damage_mult": 1.3,
		"sfx": "res://assets/audio/sfx/player/player_spell_fan_knives.mp3",
		"spawn": "at_caster",
	},
	# DRUID
	"druid_wolf_form":
	{
		"name": "Wolf Form",
		"scene": "res://scenes/skills/skill_druid_wolf_form.tscn",
		"icon": "res://assets/sprites/items/icon_druid_wolf_form.png",
		"cooldown": 16.0,
		"mana_cost": 20.0,
		"damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_wolf.mp3",
		"spawn": "at_caster",
	},
	"druid_bear_form":
	{
		"name": "Bear Form",
		"scene": "res://scenes/skills/skill_druid_bear_form.tscn",
		"icon": "res://assets/sprites/items/icon_druid_bear_form.png",
		"cooldown": 16.0,
		"mana_cost": 20.0,
		"damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_bear.mp3",
		"spawn": "at_caster",
	},
	"druid_bite":
	{
		"name": "Savage Bite",
		"scene": "res://scenes/skills/skill_druid_bite.tscn",
		"icon": "res://assets/sprites/items/icon_druid_bite.png",
		"cooldown": 1.8,
		"mana_cost": 6.0,
		"damage_mult": 2.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_bite_hit.mp3",
		"spawn": "ahead_of_caster",
	},
	"druid_leap":
	{
		"name": "Hunting Leap",
		"scene": "res://scenes/skills/skill_druid_leap.tscn",
		"icon": "res://assets/sprites/items/icon_druid_leap.png",
		"cooldown": 5.0,
		"mana_cost": 14.0,
		"damage_mult": 1.5,
		"sfx": "res://assets/audio/sfx/player/player_druid_wolf_leap.mp3",
		"spawn": "with_caster",
	},
	"druid_sweep":
	{
		"name": "Sweeping Maul",
		"scene": "res://scenes/skills/skill_druid_sweep.tscn",
		"icon": "res://assets/sprites/items/icon_druid_sweep.png",
		"cooldown": 3.2,
		"mana_cost": 10.0,
		"damage_mult": 2.6,
		"sfx": "res://assets/audio/sfx/player/player_druid_bear_sweep.mp3",
		"spawn": "ahead_of_caster",
	},
	"druid_charge":
	{
		"name": "Stone Charge",
		"scene": "res://scenes/skills/skill_druid_charge.tscn",
		"icon": "res://assets/sprites/items/icon_druid_charge.png",
		"cooldown": 7.0,
		"mana_cost": 18.0,
		"damage_mult": 1.8,
		"sfx": "res://assets/audio/sfx/player/player_druid_bear_charge.mp3",
		"spawn": "with_caster",
	},
	"druid_stone_armor":
	{
		"name": "Stone Armor",
		"scene": "res://scenes/skills/skill_druid_stone_armor.tscn",
		"icon": "res://assets/sprites/items/icon_druid_stone_armor.png",
		"cooldown": 14.0,
		"mana_cost": 32.0,
		"damage_mult": 0.6,
		"sfx": "res://assets/audio/sfx/player/player_druid_stone_armor_form.mp3",
		"spawn": "attached_to_caster",
	},
	"druid_summon_spirit":
	{
		"name": "Summon Spirit",
		"scene": "res://scenes/skills/skill_druid_summon_spirit.tscn",
		"icon": "res://assets/sprites/items/icon_druid_summon_spirit.png",
		"cooldown": 22.0,
		"mana_cost": 38.0,
		"damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_summon_spirit.mp3",
		"spawn": "at_caster",
	},
	"druid_eagle_form":
	{
		"name": "Eagle Form",
		"scene": "res://scenes/skills/skill_druid_eagle_form.tscn",
		"icon": "res://assets/sprites/items/icon_druid_eagle_form.png",
		"cooldown": 24.0,
		"mana_cost": 30.0,
		"damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_eagle.mp3",
		"spawn": "at_caster",
	},
	"druid_talon_swoop":
	{
		"name": "Talon Swoop",
		"scene": "res://scenes/skills/skill_druid_talon_swoop.tscn",
		"icon": "res://assets/sprites/items/icon_druid_talon_swoop.png",
		"cooldown": 3.5,
		"mana_cost": 10.0,
		"damage_mult": 2.2,
		"sfx": "res://assets/audio/sfx/player/player_druid_talon_swoop.mp3",
		"spawn": "with_caster",
	},
	"druid_wind_gust":
	{
		"name": "Wind Gust",
		"scene": "res://scenes/skills/skill_druid_wind_gust.tscn",
		"icon": "res://assets/sprites/items/icon_druid_wind_gust.png",
		"cooldown": 5.0,
		"mana_cost": 14.0,
		"damage_mult": 1.4,
		"sfx": "res://assets/audio/sfx/player/player_druid_wind_gust.mp3",
		"spawn": "ahead_of_caster",
	},
	# NECROMANCER
	"necro_raise_skeleton":
	{
		"name": "Raise Skeleton",
		"scene": "res://scenes/skills/skill_necro_raise_skeleton.tscn",
		"icon": "res://assets/sprites/items/icon_necro_raise_skeleton.png",
		"cooldown": 6.0,
		"mana_cost": 18.0,
		"damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_raise_skeleton.mp3",
		"spawn": "at_target",
	},
	"necro_raise_knight":
	{
		"name": "Raise Knight",
		"scene": "res://scenes/skills/skill_necro_raise_knight.tscn",
		"icon": "res://assets/sprites/items/icon_necro_raise_knight.png",
		"cooldown": 14.0,
		"mana_cost": 36.0,
		"damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_raise_knight.mp3",
		"spawn": "at_target",
	},
	"necro_blood_pact":
	{
		"name": "Blood Pact",
		"scene": "res://scenes/skills/skill_necro_blood_pact.tscn",
		"icon": "res://assets/sprites/items/icon_necro_blood_pact.png",
		"cooldown": 18.0,
		"mana_cost": 0.0,
		"damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_blood_pact.mp3",
		"spawn": "at_caster",
	},
	"necro_death_pulse":
	{
		"name": "Death Pulse",
		"scene": "res://scenes/skills/skill_necro_death_pulse.tscn",
		"icon": "res://assets/sprites/items/icon_necro_death_pulse.png",
		"cooldown": 10.0,
		"mana_cost": 28.0,
		"damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_necro_death_pulse.mp3",
		"spawn": "at_caster",
	},
	# UNIQUE TRANSFORM SCENES — selected at cast-time when slot has a transform.
	"necro_bone_spear":
	{
		"name": "Bone Spear",
		"scene": "res://scenes/skills/skill_necro_bone_spear.tscn",
		"icon": "res://assets/sprites/items/icon_necro_bone_spear.png",
		"cooldown": 1.6,
		"mana_cost": 12.0,
		"damage_mult": 2.0,
		"sfx": "res://assets/audio/sfx/player/player_necro_bone_spear.mp3",
		"spawn": "ahead_of_caster",
	},
	"necro_curse_field":
	{
		"name": "Curse Field",
		"scene": "res://scenes/skills/skill_necro_curse_field.tscn",
		"icon": "res://assets/sprites/items/icon_necro_curse_field.png",
		"cooldown": 12.0,
		"mana_cost": 32.0,
		"damage_mult": 0.4,
		"sfx": "res://assets/audio/sfx/player/player_necro_curse_field.mp3",
		"spawn": "at_target",
	},
	"druid_hurricane":
	{
		"name": "Hurricane",
		"scene": "res://scenes/skills/skill_druid_hurricane.tscn",
		"icon": "res://assets/sprites/items/icon_druid_hurricane.png",
		"cooldown": 10.0,
		"mana_cost": 24.0,
		"damage_mult": 0.8,
		"sfx": "res://assets/audio/sfx/player/player_druid_hurricane.mp3",
		"spawn": "at_caster",
	},
	"druid_dire_wolf_form":
	{
		"name": "Dire Wolf Form",
		"scene": "res://scenes/skills/skill_druid_dire_wolf_form.tscn",
		"icon": "res://assets/sprites/items/icon_druid_dire_wolf.png",
		"cooldown": 16.0,
		"mana_cost": 22.0,
		"damage_mult": 1.0,
		"sfx": "res://assets/audio/sfx/player/player_druid_transform_wolf.mp3",
		"spawn": "at_caster",
	},
	# HEXEN
	"hexen_hex_mark":
	{
		"name": "Hex Mark",
		"scene": "res://scenes/skills/skill_hexen_hex_mark.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_hex_mark.png",
		"cooldown": 2.0,
		"mana_cost": 14.0,
		"damage_mult": 0.9,
		"sfx": "res://assets/audio/sfx/player/player_hexen_hex_mark_apply.mp3",
		"spawn": "at_target",
	},
	"hexen_blood_whip":
	{
		"name": "Blood Whip",
		"scene": "res://scenes/skills/skill_hexen_blood_whip.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_blood_whip.png",
		"cooldown": 5.0,
		"mana_cost": 18.0,
		"damage_mult": 1.3,
		"sfx": "res://assets/audio/sfx/player/player_hexen_blood_whip.mp3",
		"spawn": "ahead_of_caster",
	},
	"hexen_soul_tether":
	{
		"name": "Soul Tether",
		"scene": "res://scenes/skills/skill_hexen_soul_tether.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_soul_tether.png",
		"cooldown": 12.0,
		"mana_cost": 32.0,
		"damage_mult": 0.6,
		"sfx": "res://assets/audio/sfx/player/player_hexen_soul_tether.mp3",
		"spawn": "at_caster",
	},
	"hexen_crimson_ritual":
	{
		"name": "Crimson Ritual",
		"scene": "res://scenes/skills/skill_hexen_crimson_ritual.tscn",
		"icon": "res://assets/sprites/items/icon_hexen_crimson_ritual.png",
		"cooldown": 18.0,
		"mana_cost": 36.0,
		"damage_mult": 0.4,
		"sfx": "res://assets/audio/sfx/player/player_hexen_crimson_ritual.mp3",
		"spawn": "at_target",
	},
	# STORMCALLER
	"storm_chain_bolt":
	{
		"name": "Chain Bolt",
		"scene": "res://scenes/skills/skill_storm_chain_bolt.tscn",
		"icon": "res://assets/sprites/items/icon_storm_chain_bolt.png",
		"cooldown": 4.0,
		"mana_cost": 16.0,
		"damage_mult": 1.4,
		"sfx": "res://assets/audio/sfx/player/player_storm_chain_bolt.mp3",
		"spawn": "at_caster",
	},
	"storm_step":
	{
		"name": "Storm Step",
		"scene": "res://scenes/skills/skill_storm_step.tscn",
		"icon": "res://assets/sprites/items/icon_storm_step.png",
		"cooldown": 5.0,
		"mana_cost": 12.0,
		"damage_mult": 1.1,
		"sfx": "res://assets/audio/sfx/player/player_storm_step_dash.mp3",
		"spawn": "with_caster",
	},
	"storm_sky_strike":
	{
		"name": "Sky Strike",
		"scene": "res://scenes/skills/skill_storm_sky_strike.tscn",
		"icon": "res://assets/sprites/items/icon_storm_sky_strike.png",
		"cooldown": 14.0,
		"mana_cost": 30.0,
		"damage_mult": 0.8,
		"sfx": "res://assets/audio/sfx/player/player_storm_sky_strike_warn.mp3",
		"spawn": "with_caster",
	},
	"storm_static_discharge":
	{
		"name": "Static Discharge",
		"scene": "res://scenes/skills/skill_storm_static_discharge.tscn",
		"icon": "res://assets/sprites/items/icon_storm_static_discharge.png",
		"cooldown": 16.0,
		"mana_cost": 22.0,
		"damage_mult": 1.6,
		"sfx": "res://assets/audio/sfx/player/player_storm_static_discharge.mp3",
		"spawn": "at_caster",
	},
}

# Slot transform → alternate skill id (used when a unique is equipped).
const TRANSFORM_OVERRIDES: Dictionary = {
	"necro_bone_spear": "necro_bone_spear",
	"necro_curse_field": "necro_curse_field",
	"druid_hurricane": "druid_hurricane",
	"druid_dire_wolf": "druid_dire_wolf_form",
}

# Druid form -> slot 0/1 swap. Slots 2 & 3 (stone armor, summon) stay fixed.
# Slot 4 (eagle form) is reserved separately as the druid's ultimate.
const DRUID_FORM_SLOTS: Dictionary = {
	"human": ["druid_wolf_form", "druid_bear_form"],
	"wolf": ["druid_bite", "druid_leap"],
	"bear": ["druid_sweep", "druid_charge"],
	"eagle": ["druid_talon_swoop", "druid_wind_gust"],
	"dire_wolf": ["druid_bite", "druid_leap"],
}

# Default fallback if class data has no skill_ids.
const DEFAULT_SKILL_IDS := ["fire_wall", "ice_bolt", "chain_lightning", "meteor"]

var skill_ids: Array = DEFAULT_SKILL_IDS.duplicate()
var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var modifiers: Array = [{}, {}, {}, {}]
var transforms: Array = ["", "", "", ""]
var active_transforms: Array = []

# Druid-only: current shape ("human", "wolf", "bear", "eagle").
var druid_form: String = "human"


func _ready() -> void:
	_refresh_skill_ids()
	if GameManager:
		GameManager.class_selected.connect(_on_class_selected)


func _on_class_selected(_class_id: String) -> void:
	_refresh_skill_ids()
	# Reset cooldowns and modifiers on class change.
	for i in 4:
		cooldowns[i] = 0.0
		modifiers[i] = {}
		transforms[i] = ""
	active_transforms.clear()


func _refresh_skill_ids() -> void:
	if GameManager == null:
		return
	var data: Dictionary = GameManager.get_class_data()
	var ids: Array = data.get("skill_ids", DEFAULT_SKILL_IDS)
	if ids.size() < 4:
		ids = DEFAULT_SKILL_IDS
	skill_ids = ids.duplicate()
	# Druid: respect the current form for slots 0 & 1, and add Eagle Form as
	# the 5th "ultimate" slot bound to Q.
	if String(GameManager.player_class) == "druid":
		# Grow arrays to length 5 so slot 4 is addressable.
		if skill_ids.size() < 5:
			skill_ids.append("druid_eagle_form")
		else:
			skill_ids[4] = "druid_eagle_form"
		while cooldowns.size() < 5:
			cooldowns.append(0.0)
		while modifiers.size() < 5:
			modifiers.append({})
		while transforms.size() < 5:
			transforms.append("")
		_apply_druid_form_to_skill_ids()
	else:
		# Trim back to 4 for non-druid classes.
		if skill_ids.size() > 4:
			skill_ids.resize(4)
		if cooldowns.size() > 4:
			cooldowns.resize(4)
		if modifiers.size() > 4:
			modifiers.resize(4)
		if transforms.size() > 4:
			transforms.resize(4)
	skill_ids_changed.emit()


func _apply_druid_form_to_skill_ids() -> void:
	var pair: Array = DRUID_FORM_SLOTS.get(druid_form, DRUID_FORM_SLOTS["human"])
	if skill_ids.size() < 5:
		skill_ids = [
			"druid_wolf_form",
			"druid_bear_form",
			"druid_stone_armor",
			"druid_summon_spirit",
			"druid_eagle_form"
		]
	skill_ids[0] = pair[0]
	skill_ids[1] = pair[1]
	# Slot 4 always shows Eagle Form. The script itself toggles between cast
	# (when human) and revert (when in any beast form) — see skill_druid_eagle_form.gd.
	skill_ids[4] = "druid_eagle_form"


# Called by the player when shapeshift starts/ends.
func set_druid_form(new_form: String) -> void:
	if not DRUID_FORM_SLOTS.has(new_form):
		new_form = "human"
	if new_form == druid_form:
		return
	druid_form = new_form
	# Reset cooldowns on the two slots that just swapped so the new form's
	# attacks are immediately usable.
	cooldowns[0] = 0.0
	cooldowns[1] = 0.0
	_apply_druid_form_to_skill_ids()
	skill_ids_changed.emit()


func get_druid_form() -> String:
	return druid_form


func _process(delta: float) -> void:
	for i in cooldowns.size():
		if cooldowns[i] > 0.0:
			var prev: float = cooldowns[i]
			cooldowns[i] = max(0.0, cooldowns[i] - delta)
			if prev > 0.0 and cooldowns[i] == 0.0:
				cooldown_finished.emit(i)


func get_slot_data(slot: int) -> Dictionary:
	if slot < 0 or slot >= skill_ids.size():
		return {}
	var id: String = String(skill_ids[slot])
	return SKILL_CATALOG.get(id, {})


func get_cooldown_remaining(slot: int) -> float:
	if slot < 0 or slot >= cooldowns.size():
		return 0.0
	return cooldowns[slot]


func get_cooldown_total(slot: int) -> float:
	var d: Dictionary = get_slot_data(slot)
	return float(d.get("cooldown", 1.0))


func get_skill_icon(slot: int) -> Texture2D:
	# Honor unique transforms — show the bone-spear / curse-field / hurricane
	# / dire-wolf icon when the corresponding unique is equipped.
	var d: Dictionary = get_slot_data(slot)
	var transform_id: String = get_transform(slot)
	if transform_id != "" and TRANSFORM_OVERRIDES.has(transform_id):
		d = SKILL_CATALOG.get(String(TRANSFORM_OVERRIDES[transform_id]), d)
	var path: String = String(d.get("icon", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func get_skill_name(slot: int) -> String:
	var d: Dictionary = get_slot_data(slot)
	var transform_id: String = get_transform(slot)
	if transform_id != "" and TRANSFORM_OVERRIDES.has(transform_id):
		d = SKILL_CATALOG.get(String(TRANSFORM_OVERRIDES[transform_id]), d)
	return String(d.get("name", "?"))


func add_modifier(slot: int, modifier_id: String) -> void:
	if slot < 0 or slot >= modifiers.size():
		return
	var m: Dictionary = modifiers[slot]
	m[modifier_id] = int(m.get(modifier_id, 0)) + 1
	modifiers[slot] = m
	modifier_applied.emit(slot, modifier_id)


func apply_transform(slot: int, transform_id: String) -> void:
	if slot < 0 or slot >= transforms.size():
		return
	transforms[slot] = transform_id
	if not active_transforms.has(transform_id):
		active_transforms.append(transform_id)
	transform_applied.emit(slot, transform_id)
	# Tell the HUD to repaint slot icon (so e.g. Bone Spear's icon replaces
	# Raise Skeleton's the moment the unique is equipped).
	skill_ids_changed.emit()


func get_modifier(slot: int, modifier_id: String) -> int:
	if slot < 0 or slot >= modifiers.size():
		return 0
	return int(modifiers[slot].get(modifier_id, 0))


func get_transform(slot: int) -> String:
	if slot < 0 or slot >= transforms.size():
		return ""
	return transforms[slot]


func try_cast(slot: int, caster: Node2D, mouse_world: Vector2) -> bool:
	if slot < 0 or slot >= skill_ids.size():
		return false
	if cooldowns[slot] > 0.0:
		skill_failed.emit(slot, "cooldown")
		return false
	# Slot transform → alternate skill (uniques replace the base slot).
	var skill_id_local: String = String(skill_ids[slot])
	var transform_id: String = get_transform(slot)
	if transform_id != "" and TRANSFORM_OVERRIDES.has(transform_id):
		skill_id_local = String(TRANSFORM_OVERRIDES[transform_id])
	var data: Dictionary = SKILL_CATALOG.get(skill_id_local, {})
	if data.is_empty():
		return false
	var cost: float = float(data.get("mana_cost", 0.0))
	if cost > 0.0 and (GameManager == null or not GameManager.spend_mana(cost)):
		skill_failed.emit(slot, "mana")
		return false

	cooldowns[slot] = float(data.get("cooldown", 1.0))
	cooldown_started.emit(slot, float(data.get("cooldown", 1.0)))

	if AudioManager:
		AudioManager.play_sfx_path(String(data.get("sfx", "")), -6.0)

	# Compute damage with stat scaling + modifier damage bonus + player buff.
	var base_damage: int = GameManager.player_damage if GameManager else 14
	var dmg_mult: float = float(data.get("damage_mult", 1.0))
	# Slot-based +damage modifier ids (kept generic so they work for any class):
	# "fw_damage" (slot 0), "ib_damage" (1), "cl_damage" (2), "mt_damage" (3).
	# Each class' slot 0..3 gets +30% per stack.
	var stack_bonus: float = 0.0
	var stack_ids := ["fw_damage", "ib_damage", "cl_damage", "mt_damage"]
	stack_bonus = 0.3 * float(get_modifier(slot, stack_ids[slot]))
	# Buff multiplier (from Battle Cry etc.).
	var buff_mult: float = _player_buff_dmg(caster)
	var scaled_damage: int = int(
		round(float(base_damage) * dmg_mult * (1.0 + stack_bonus) * buff_mult)
	)

	# Spawn scene.
	var skill_id: String = skill_id_local
	var scene_path: String = String(data.get("scene", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_warning("Missing skill scene: %s" % scene_path)
		return false
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return false
	var node: Node = packed.instantiate()

	# Spawn rules: position before add_child, setup before add_child.
	var spawn_kind: String = String(data.get("spawn", "at_caster"))
	var spawn_pos: Vector2 = caster.global_position
	var dir: Vector2 = mouse_world - caster.global_position
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	match spawn_kind:
		"ahead_of_caster":
			spawn_pos = caster.global_position + dir * 80.0
		"projectile":
			spawn_pos = caster.global_position + dir * 24.0
		"at_target":
			spawn_pos = mouse_world
		"attached_to_caster", "with_caster", "at_caster":
			spawn_pos = caster.global_position
		_:
			spawn_pos = caster.global_position
	(node as Node2D).position = spawn_pos

	# Build per-skill modifier dict.
	var mods: Dictionary = _build_mods_for(slot, skill_id, caster)
	if node.has_method("setup_with_mods"):
		node.call("setup_with_mods", dir, scaled_damage, mods)
	elif node.has_method("setup_meteor"):
		node.call("setup_meteor", scaled_damage, mods)
	elif node.has_method("setup"):
		# Generic fallbacks based on signature.
		node.call("setup", dir, scaled_damage)

	get_tree().current_scene.add_child(node)

	# If skill is "attached_to_caster" (whirlwind), reparent to caster so it follows.
	if spawn_kind == "attached_to_caster":
		var current_parent := node.get_parent()
		if current_parent:
			current_parent.remove_child(node)
		caster.add_child(node)
		(node as Node2D).position = Vector2.ZERO

	# Multiplayer: broadcast a visual-only copy so other peers see our cast.
	if NetManager and NetManager.is_multiplayer:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_skill_cast"):
			ns.call("broadcast_skill_cast", skill_id, scene_path, spawn_pos, dir, scaled_damage)

	return true


func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("NetSync")


func _build_mods_for(slot: int, skill_id: String, caster: Node) -> Dictionary:
	var mods: Dictionary = {
		"transform": get_transform(slot),
		"caster": caster,
	}
	match skill_id:
		"fire_wall":
			mods["duration_stacks"] = get_modifier(slot, "fw_duration")
			mods["radius_stacks"] = get_modifier(slot, "fw_radius")
		"ice_bolt":
			mods["pierce"] = get_modifier(slot, "ib_pierce") > 0
			mods["slow_stacks"] = get_modifier(slot, "ib_slow")
		"chain_lightning":
			mods["jumps_bonus"] = get_modifier(slot, "cl_jumps") * 2
		"meteor":
			mods["radius_bonus"] = 0.5 * float(get_modifier(slot, "mt_radius"))
		"battle_cry":
			mods["radius"] = 240.0
			mods["duration"] = 5.0
			mods["dmg_mult"] = 1.6
			mods["spd_mult"] = 1.3
	return mods


func _player_buff_dmg(caster: Node) -> float:
	if caster and caster.has_method("get_buff_damage_mult"):
		return float(caster.call("get_buff_damage_mult"))
	return 1.0
