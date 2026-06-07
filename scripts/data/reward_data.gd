class_name RewardData
extends RefCounted

# Shared catalogs of stat boosts, skill modifiers, and uniques.
# Used by the level-up overlay AND the character sheet items tab.

const STAT_REWARDS := [
	{"id": "hp+20", "title": "Iron Heart", "desc": "+20 maximum health", "rarity": "common"},
	{"id": "hp+40", "title": "Vital Surge", "desc": "+40 maximum health", "rarity": "rare"},
	{"id": "mana+15", "title": "Inner Well", "desc": "+15 maximum mana", "rarity": "common"},
	{"id": "mana+30", "title": "Deep Reservoir", "desc": "+30 maximum mana", "rarity": "rare"},
	{"id": "dmg+3", "title": "Sharpened Edge", "desc": "+3 damage", "rarity": "common"},
	{"id": "dmg+7", "title": "Lethal Focus", "desc": "+7 damage", "rarity": "rare"},
	{"id": "crit+5", "title": "Killer Instinct", "desc": "+5% critical chance", "rarity": "common"},
	{
		"id": "crit_dmg+0.25",
		"title": "Brutal Strike",
		"desc": "+25% critical damage",
		"rarity": "rare"
	},
	{"id": "speed+15", "title": "Quick Step", "desc": "+15 move speed", "rarity": "common"},
	{
		"id": "heal_full",
		"title": "Blood Renewal",
		"desc": "Restore full health",
		"rarity": "common"
	},
]

const SKILL_MODIFIERS := [
	{
		"id": "fw_duration",
		"slot": 0,
		"title": "Eternal Pyre",
		"desc": "Fire Wall lasts longer and ticks faster",
		"rarity": "common",
		"stack_bonus": "+1.5s duration & faster ticks"
	},
	{
		"id": "fw_radius",
		"slot": 0,
		"title": "Vast Inferno",
		"desc": "Fire Wall is wider",
		"rarity": "common",
		"stack_bonus": "+35% width"
	},
	{
		"id": "fw_damage",
		"slot": 0,
		"title": "Pyromancy",
		"desc": "+30% Fire Wall damage",
		"rarity": "common",
		"stack_bonus": "+30% damage"
	},
	{
		"id": "ib_pierce",
		"slot": 1,
		"title": "Piercing Frost",
		"desc": "Ice Bolt pierces through enemies",
		"rarity": "rare",
		"stack_bonus": "Already piercing"
	},
	{
		"id": "ib_slow",
		"slot": 1,
		"title": "Deep Freeze",
		"desc": "Ice Bolt slows harder and longer",
		"rarity": "common",
		"stack_bonus": "+1.5s slow & stronger"
	},
	{
		"id": "ib_damage",
		"slot": 1,
		"title": "Hardened Ice",
		"desc": "+30% Ice Bolt damage",
		"rarity": "common",
		"stack_bonus": "+30% damage"
	},
	{
		"id": "cl_jumps",
		"slot": 2,
		"title": "Arc Mastery",
		"desc": "Chain Lightning hits two more targets",
		"rarity": "rare",
		"stack_bonus": "+2 jumps"
	},
	{
		"id": "cl_damage",
		"slot": 2,
		"title": "High Voltage",
		"desc": "+30% Chain Lightning damage",
		"rarity": "common",
		"stack_bonus": "+30% damage"
	},
	{
		"id": "mt_radius",
		"slot": 3,
		"title": "Greater Impact",
		"desc": "Meteor blast radius +50%",
		"rarity": "common",
		"stack_bonus": "+50% radius"
	},
	{
		"id": "mt_damage",
		"slot": 3,
		"title": "Heavenly Hammer",
		"desc": "+40% Meteor damage",
		"rarity": "rare",
		"stack_bonus": "+40% damage"
	},
	# DRUID
	{
		"id": "wolf_duration",
		"slot": 0,
		"title": "Wild Endurance",
		"desc": "Wolf Form lasts longer",
		"rarity": "common",
		"stack_bonus": "+4s duration"
	},
	{
		"id": "bear_duration",
		"slot": 1,
		"title": "Iron Hide",
		"desc": "Bear Form lasts longer",
		"rarity": "common",
		"stack_bonus": "+4s duration"
	},
	{
		"id": "stone_armor_charges",
		"slot": 2,
		"title": "Mountain's Shield",
		"desc": "Stone Armor absorbs one extra hit",
		"rarity": "rare",
		"stack_bonus": "+1 absorbed hit"
	},
	{
		"id": "spirit_pets",
		"slot": 3,
		"title": "Pack Caller",
		"desc": "Summon Spirit can call one more beast at a time",
		"rarity": "rare",
		"stack_bonus": "+1 max spirit pet"
	},
	{
		"id": "eagle_duration",
		"slot": 4,
		"title": "Sky Lord",
		"desc": "Eagle Form lasts longer",
		"rarity": "common",
		"stack_bonus": "+4s duration"
	},
	# NECROMANCER
	{
		"id": "necro_skel_count",
		"slot": 0,
		"title": "Risen Legion",
		"desc": "Raise Skeleton can summon one more soldier at a time",
		"rarity": "rare",
		"stack_bonus": "+1 max skeleton"
	},
	{
		"id": "necro_knight_armor",
		"slot": 1,
		"title": "Plated Bones",
		"desc": "+40 max HP for each Bone Knight you summon",
		"rarity": "common",
		"stack_bonus": "+40 knight HP"
	},
	{
		"id": "necro_pact_power",
		"slot": 2,
		"title": "Crimson Vow",
		"desc": "Blood Pact grants +25% more damage to your minions",
		"rarity": "rare",
		"stack_bonus": "+25% pact damage"
	},
	{
		"id": "necro_pulse_radius",
		"slot": 3,
		"title": "Wider Reach",
		"desc": "Death Pulse radius +30%",
		"rarity": "common",
		"stack_bonus": "+30% radius"
	},
	# BARBARIAN — slots: Whirlwind(0), Leap Slam(1), Battle Cry(2), Earthquake(3)
	{
		"id": "barb_whirl_damage",
		"slot": 0,
		"title": "Reaving Spin",
		"desc": "+30% Whirlwind damage",
		"rarity": "common",
		"stack_bonus": "+30% damage"
	},
	{
		"id": "barb_cry_power",
		"slot": 2,
		"title": "Warlord's Roar",
		"desc": "Battle Cry lasts longer and boosts move speed more",
		"rarity": "rare",
		"stack_bonus": "+2s duration & +15% speed"
	},
	{
		"id": "barb_quake_waves",
		"slot": 3,
		"title": "Aftershocks",
		"desc": "Earthquake sends one more shockwave ring",
		"rarity": "rare",
		"stack_bonus": "+1 shockwave"
	},
	# ROGUE — slots: Caltrops(0), Smoke Bomb(1), Poison Vial(2), Fan of Knives(3)
	{
		"id": "rogue_knives_damage",
		"slot": 3,
		"title": "Honed Blades",
		"desc": "+30% Fan of Knives damage",
		"rarity": "common",
		"stack_bonus": "+30% damage"
	},
	{
		"id": "rogue_knives_count",
		"slot": 3,
		"title": "Blade Tempest",
		"desc": "Fan of Knives throws two more daggers",
		"rarity": "rare",
		"stack_bonus": "+2 daggers"
	},
	{
		"id": "rogue_caltrops_duration",
		"slot": 0,
		"title": "Lasting Barbs",
		"desc": "Caltrops linger on the ground longer",
		"rarity": "common",
		"stack_bonus": "+4s duration"
	},
	# HEXEN — slots: Hex Mark(0), Blood Whip(1), Soul Tether(2), Crimson Ritual(3)
	{
		"id": "hexen_mark_damage",
		"slot": 0,
		"title": "Deepening Curse",
		"desc": "+30% Hex Mark damage",
		"rarity": "common",
		"stack_bonus": "+30% damage"
	},
	{
		"id": "hexen_mark_duration",
		"slot": 0,
		"title": "Lingering Hex",
		"desc": "Hex Mark ticks longer before it detonates",
		"rarity": "rare",
		"stack_bonus": "+1.5s duration"
	},
	{
		"id": "hexen_whip_damage",
		"slot": 1,
		"title": "Flensing Lash",
		"desc": "+30% Blood Whip damage",
		"rarity": "common",
		"stack_bonus": "+30% damage"
	},
	# STORMCALLER — slots: Chain Bolt(0), Storm Step(1), Sky Strike(2), Static Discharge(3)
	{
		"id": "storm_bolt_damage",
		"slot": 0,
		"title": "Overcharged Arc",
		"desc": "+30% Chain Bolt damage",
		"rarity": "common",
		"stack_bonus": "+30% damage"
	},
	{
		"id": "storm_bolt_jumps",
		"slot": 0,
		"title": "Forking Path",
		"desc": "Chain Bolt arcs to one more target",
		"rarity": "rare",
		"stack_bonus": "+1 jump"
	},
	{
		"id": "storm_sky_damage",
		"slot": 2,
		"title": "Thunderhead",
		"desc": "+30% Sky Strike damage",
		"rarity": "common",
		"stack_bonus": "+30% damage"
	},
]

const UNIQUES := [
	{
		"id": "transform_ice_wall",
		"slot": 0,
		"title": "Ice Wall",
		"desc": "Fire Wall becomes a Wall of Ice that freezes and blocks",
		"rarity": "unique",
		"transform": "ice_wall"
	},
	{
		"id": "transform_frost_nova",
		"slot": 1,
		"title": "Frost Nova",
		"desc": "Ice Bolt becomes a radial frost burst around you",
		"rarity": "unique",
		"transform": "frost_nova"
	},
	{
		"id": "transform_death_beam",
		"slot": 2,
		"title": "Death Beam",
		"desc": "Chain Lightning becomes a focused beam of death",
		"rarity": "unique",
		"transform": "death_beam"
	},
	{
		"id": "transform_meteor_shower",
		"slot": 3,
		"title": "Meteor Shower",
		"desc": "Meteor becomes a rain of three smaller meteors",
		"rarity": "unique",
		"transform": "meteor_shower"
	},
	{
		"id": "stone_armor_grinder",
		"slot": 2,
		"title": "Grinder Stones",
		"desc": "Stone Armor's shards also spin to deal contact damage to nearby enemies",
		"rarity": "unique",
		"transform": "stone_armor_grinder"
	},
	# DRUID UNIQUES — replace shapeshift slots with alternates.
	{
		"id": "transform_druid_hurricane",
		"slot": 0,
		"title": "Eye of the Storm",
		"desc": "Wolf Form is replaced by a swirling Hurricane that chases enemies for 8 seconds",
		"rarity": "unique",
		"transform": "druid_hurricane"
	},
	{
		"id": "transform_druid_dire_wolf",
		"slot": 1,
		"title": "Alpha Predator",
		"desc":
		"Bear Form is replaced by Dire Wolf Form — wolf moveset with brutal damage and speed",
		"rarity": "unique",
		"transform": "druid_dire_wolf"
	},
	{
		"id": "transform_necro_bone_spear",
		"slot": 0,
		"title": "Bone Spear",
		"desc":
		"Raise Skeleton is replaced by a piercing bone spear projectile. You give up your light minions for direct damage.",
		# NECROMANCER UNIQUES — replace summon slots with direct-damage tools.
		"rarity": "unique",
		"transform": "necro_bone_spear"
	},
	{
		"id": "transform_necro_curse_field",
		"slot": 1,
		"title": "Curse Field",
		"desc":
		"Raise Knight is replaced by a cursed ground that makes enemies inside take +50% damage for 8 seconds",
		"rarity": "unique",
		"transform": "necro_curse_field"
	},
	{
		"id": "transform_hexen_eternal_mark",
		"slot": 0,
		"title": "Eternal Mark",
		"desc":
		"Hex Marks never expire on their own — only Soul Tether or Blood Whip detonates them",
		# HEXEN UNIQUES.
		"rarity": "unique",
		"transform": "hexen_eternal_mark"
	},
	{
		"id": "transform_hexen_tether_shock",
		"slot": 2,
		"title": "Tether Shock",
		"desc":
		"Soul Tether briefly stuns linked enemies when the initial hit exceeds half their health",
		"rarity": "unique",
		"transform": "hexen_tether_shock"
	},
	{
		"id": "transform_hexen_bloodmoon",
		"slot": 3,
		"title": "Bloodmoon Ritual",
		"desc":
		"Crimson Ritual erupts in a damaging burst when it expires; a kill inside refunds the cooldown",
		"rarity": "unique",
		"transform": "hexen_bloodmoon"
	},
	# BASIC-ATTACK UNIQUES — one per class. Recognized by player.gd via the
	{
		"id": "basic_barb_shockwave",
		"slot": -1,
		"title": "Cleaving Shockwave",
		"desc":
		"Barbarian basic attack sends a forward shockwave that passes through enemies for 50% damage",
		# "basic_<id>" key in InventorySystem.has_unique().
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_shockwave.png",
		"basic_for": "barbarian"
	},
	{
		"id": "basic_rogue_triple_throw",
		"slot": -1,
		"title": "Triple Throw",
		"desc": "Rogue dagger basic now fires three daggers in a short fan",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_triple_throw.png",
		"basic_for": "rogue"
	},
	{
		"id": "basic_mage_phantom_edge",
		"slot": -1,
		"title": "Phantom Edge",
		"desc": "Mage bolt is replaced by a sweeping ethereal sword arc in melee range",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_phantom_edge.png",
		"basic_for": "mage"
	},
	{
		"id": "basic_druid_thunder_sphere",
		"slot": -1,
		"title": "Thunder Sphere",
		"desc": "Druid claw becomes a ranged crackling lightning ball",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_thunder_sphere.png",
		"basic_for": "druid"
	},
	{
		"id": "basic_necro_bone_lance",
		"slot": -1,
		"title": "Bone Lance",
		"desc": "Necromancer bolt becomes a forward bone-lance thrust at melee range",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_bone_lance.png",
		"basic_for": "necromancer"
	},
	{
		"id": "basic_hexen_whipcrack",
		"slot": -1,
		"title": "Whipcrack",
		"desc": "Hexen basic attack flicks a quick whip that applies a 0.5s mini-hex on hit",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_whipcrack.png",
		"basic_for": "hexen"
	},
	{
		"id": "basic_storm_voltaic_tonfa",
		"slot": -1,
		"title": "Voltaic Tonfa",
		"desc":
		"Stormcaller basic is replaced by a melee lightning tonfa swing that chains to a second target",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_voltaic_tonfa.png",
		"basic_for": "stormcaller"
	},
	# STORMCALLER UNIQUES
	{
		"id": "storm_stormveil",
		"slot": 1,
		"title": "Stormveil",
		"desc": "Storm Step also blinds enemies along your path with a 1.5s 50% slow",
		"rarity": "unique",
		"transform": "storm_stormveil"
	},
	{
		"id": "storm_heavens_spear",
		"slot": 2,
		"title": "Heaven's Spear",
		"desc":
		"Sky Strike leaves a small charged patch on the ground that shocks enemies for 1.2s",
		"rarity": "unique",
		"transform": "storm_heavens_spear"
	},
	{
		"id": "storm_capacitor_core",
		"slot": 3,
		"title": "Capacitor Core",
		"desc":
		"Static Charge cap raised to 9, and Static Discharge refunds half its cooldown on 6+ stacks consumed",
		"rarity": "unique",
		"transform": "storm_capacitor_core"
	},
]

const CLASS_SLOT_NAMES := {
	"mage": ["Fire Wall", "Ice Bolt", "Chain Lightning", "Meteor"],
	"barbarian": ["Whirlwind", "Leap Slam", "Battle Cry", "Earthquake"],
	"rogue": ["Caltrops", "Smoke Bomb", "Poison Vial", "Fan of Knives"],
	"druid": ["Wolf Form", "Bear Form", "Stone Armor", "Summon Spirit", "Eagle Form"],
	"necromancer": ["Raise Skeleton", "Raise Knight", "Blood Pact", "Death Pulse"],
	"hexen": ["Hex Mark", "Blood Whip", "Soul Tether", "Crimson Ritual"],
	"stormcaller": ["Chain Bolt", "Storm Step", "Sky Strike", "Static Discharge"],
}

const CLASS_SLOT_ICONS := {
	"mage":
	[
		"res://assets/sprites/items/icon_skill_fire_wall.png",
		"res://assets/sprites/items/icon_skill_ice_bolt.png",
		"res://assets/sprites/items/icon_skill_chain_lightning.png",
		"res://assets/sprites/items/icon_skill_meteor.png",
	],
	"barbarian":
	[
		"res://assets/sprites/items/icon_barb_whirlwind.png",
		"res://assets/sprites/items/icon_barb_leap.png",
		"res://assets/sprites/items/icon_barb_cry.png",
		"res://assets/sprites/items/icon_barb_quake.png",
	],
	"rogue":
	[
		"res://assets/sprites/items/icon_rogue_caltrops.png",
		"res://assets/sprites/items/icon_rogue_smoke.png",
		"res://assets/sprites/items/icon_rogue_poison.png",
		"res://assets/sprites/items/icon_rogue_knives.png",
	],
	"druid":
	[
		"res://assets/sprites/items/icon_druid_wolf_form.png",
		"res://assets/sprites/items/icon_druid_bear_form.png",
		"res://assets/sprites/items/icon_druid_stone_armor.png",
		"res://assets/sprites/items/icon_druid_summon_spirit.png",
		"res://assets/sprites/items/icon_druid_eagle_form.png",
	],
	"necromancer":
	[
		"res://assets/sprites/items/icon_necro_raise_skeleton.png",
		"res://assets/sprites/items/icon_necro_raise_knight.png",
		"res://assets/sprites/items/icon_necro_blood_pact.png",
		"res://assets/sprites/items/icon_necro_death_pulse.png",
	],
	"hexen":
	[
		"res://assets/sprites/items/icon_hexen_hex_mark.png",
		"res://assets/sprites/items/icon_hexen_blood_whip.png",
		"res://assets/sprites/items/icon_hexen_soul_tether.png",
		"res://assets/sprites/items/icon_hexen_crimson_ritual.png",
	],
	"stormcaller":
	[
		"res://assets/sprites/items/icon_storm_chain_bolt.png",
		"res://assets/sprites/items/icon_storm_step.png",
		"res://assets/sprites/items/icon_storm_sky_strike.png",
		"res://assets/sprites/items/icon_storm_static_discharge.png",
	],
}


# Each modifier / slot-transform unique belongs to exactly one class — it tweaks
# that class' skills. The class is encoded in the entry's id prefix (modifiers,
# storm uniques), its transform family (slot uniques), or `basic_for` (basic-
# attack uniques). Offering an entry to any other class is a bug, so the level-up
# overlay filters by class via class_for_entry().
const _ID_CLASS_PREFIXES := {
	"fw_": "mage",
	"ib_": "mage",
	"cl_": "mage",
	"mt_": "mage",
	"barb_": "barbarian",
	"rogue_": "rogue",
	"wolf_": "druid",
	"bear_": "druid",
	"stone_armor_": "druid",
	"spirit_": "druid",
	"eagle_": "druid",
	"necro_": "necromancer",
	"hexen_": "hexen",
	"storm_": "stormcaller",
}


# Returns the class that can use this modifier/unique, or "" if class-agnostic.
static func class_for_entry(entry: Dictionary) -> String:
	# Basic-attack uniques carry an explicit owner class.
	var basic_for: String = String(entry.get("basic_for", ""))
	if basic_for != "":
		return basic_for
	# Slot-transform uniques: class is encoded in the transform id family.
	var transform: String = String(entry.get("transform", ""))
	if transform != "":
		if transform.begins_with("druid_"):
			return "druid"
		if transform.begins_with("necro_"):
			return "necromancer"
		if transform.begins_with("hexen_"):
			return "hexen"
		if transform.begins_with("storm_"):
			return "stormcaller"
		if transform == "stone_armor_grinder":
			return "druid"
		if transform in ["ice_wall", "frost_nova", "death_beam", "meteor_shower"]:
			return "mage"
	# Modifiers (and storm uniques): class encoded in the id prefix.
	var id: String = String(entry.get("id", ""))
	for prefix in _ID_CLASS_PREFIXES:
		if id.begins_with(String(prefix)):
			return String(_ID_CLASS_PREFIXES[prefix])
	return ""


# Skill modifiers usable by `cls`.
static func modifiers_for_class(cls: String) -> Array:
	var out: Array = []
	for m in SKILL_MODIFIERS:
		if class_for_entry(m) == cls:
			out.append(m)
	return out


# Slot-transform uniques usable by `cls` in the level-up overlay. Basic-attack
# uniques (slot -1, no `transform`) are EXCLUDED: they aren't applied through
# apply_transform — they live in the equipped-item system and are read by
# player.gd via InventorySystem.has_unique(). Offering them here did nothing.
static func uniques_for_class(cls: String) -> Array:
	var out: Array = []
	for u in UNIQUES:
		if class_for_entry(u) != cls:
			continue
		if String(u.get("transform", "")) == "":
			continue
		out.append(u)
	return out


static func find_modifier(id: String) -> Dictionary:
	for m in SKILL_MODIFIERS:
		if String(m["id"]) == id:
			return m
	return {}


static func find_unique_by_transform(transform_id: String) -> Dictionary:
	for u in UNIQUES:
		if String(u.get("transform", "")) == transform_id:
			return u
	return {}


static func _current_class() -> String:
	if Engine.has_singleton("GameManager"):
		return ""
	# Static fallback: GameManager is an autoload — read via classdb if available.
	return ""


static func slot_icon(slot: int) -> Texture2D:
	var cls: String = _read_class()
	var icons: Array = CLASS_SLOT_ICONS.get(cls, CLASS_SLOT_ICONS["mage"])
	if slot < 0 or slot >= icons.size():
		return null
	var path: String = String(icons[slot])
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func slot_name(slot: int) -> String:
	var cls: String = _read_class()
	var names: Array = CLASS_SLOT_NAMES.get(cls, CLASS_SLOT_NAMES["mage"])
	if slot < 0 or slot >= names.size():
		return "Unknown"
	return String(names[slot])


static func _read_class() -> String:
	# Access GameManager autoload via Engine's main loop.
	var loop = Engine.get_main_loop()
	if loop and loop.has_method("get_root"):
		var root = loop.call("get_root")
		var gm = root.get_node_or_null("GameManager")
		if gm and gm.get("player_class") != null:
			var c: String = String(gm.get("player_class"))
			if c != "":
				return c
	return "mage"
