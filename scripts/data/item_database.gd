class_name ItemDatabase
extends RefCounted

# Static catalog of all base items, uniques, affixes, and slot rules.
# Used by InventorySystem + LootRoller. Lookup-only — no runtime state.

# Equipment slots (indexes into InventorySystem.equipment).
const SLOT_HELMET: int = 0
const SLOT_CHEST: int = 1
const SLOT_GLOVES: int = 2
const SLOT_BOOTS: int = 3
const SLOT_AMULET: int = 4
const SLOT_RING_1: int = 5
const SLOT_RING_2: int = 6
const SLOT_WEAPON_MAIN: int = 7
const SLOT_WEAPON_OFF: int = 8

const SLOT_NAMES: Dictionary = {
	SLOT_HELMET: "Helmet",
	SLOT_CHEST: "Chest",
	SLOT_GLOVES: "Gloves",
	SLOT_BOOTS: "Boots",
	SLOT_AMULET: "Amulet",
	SLOT_RING_1: "Ring 1",
	SLOT_RING_2: "Ring 2",
	SLOT_WEAPON_MAIN: "Main Hand",
	SLOT_WEAPON_OFF: "Off Hand",
}

const SLOT_COUNT: int = 9

# Rarity tiers — count of rolled affixes and weight in random rolls.
const RARITY_COMMON: String = "common"
const RARITY_RARE: String = "rare"
const RARITY_LEGENDARY: String = "legendary"
const RARITY_UNIQUE: String = "unique"

const RARITY_AFFIX_COUNT: Dictionary = {
	RARITY_COMMON: 1,
	RARITY_RARE: 2,
	RARITY_LEGENDARY: 3,
	RARITY_UNIQUE: 4,
}

# Base drop weights (modified by item level — uniques get bonus on high waves).
const RARITY_WEIGHTS: Dictionary = {
	RARITY_COMMON: 25.0,
	RARITY_RARE: 25.0,
	RARITY_LEGENDARY: 25.0,
	RARITY_UNIQUE: 25.0,
}

const RARITY_COLORS: Dictionary = {
	RARITY_COMMON: Color(0.82, 0.82, 0.86, 1),
	RARITY_RARE: Color(0.45, 0.72, 1.0, 1),
	RARITY_LEGENDARY: Color(1.0, 0.65, 0.18, 1),
	RARITY_UNIQUE: Color(1.0, 0.35, 0.25, 1),
}

const RARITY_DISPLAY: Dictionary = {
	RARITY_COMMON: "Common",
	RARITY_RARE: "Rare",
	RARITY_LEGENDARY: "Legendary",
	RARITY_UNIQUE: "Unique",
}

# Salvage gold per rarity (multiplied by ilvl).
const RARITY_SALVAGE: Dictionary = {
	RARITY_COMMON: 8,
	RARITY_RARE: 25,
	RARITY_LEGENDARY: 75,
	RARITY_UNIQUE: 220,
}

# Set-bonus catalog. Each set lists which "set_id" tag qualifies pieces, plus
# 2-piece and 4-piece thresholds with flat stat bonuses.
const SET_BONUSES: Dictionary = {
	"ironclad":
	{
		"name": "Ironclad",
		"flavor": "Stand firm.",
		"2pc": {"max_hp": 30, "label": "+30 max HP"},
		"4pc": {"armor": 25, "label": "+25 armor"},
	},
	"voidweave":
	{
		"name": "Voidweave",
		"flavor": "Bend the dark.",
		"2pc": {"max_mana": 25, "label": "+25 max mana"},
		"4pc": {"damage": 12, "label": "+12% damage"},
	},
	"shadowsilk":
	{
		"name": "Shadowsilk",
		"flavor": "Faster than thought.",
		"2pc": {"move_speed": 10, "label": "+10% move speed"},
		"4pc": {"crit_chance": 8, "label": "+8% crit chance"},
	},
}

# Base item catalog — non-unique gear shapes.
# kind: armor / weapon
# slot: one of SLOT_*
# class_lock: "" (any) or "barbarian"/"rogue"/"mage"
# weapon_hands: 0 (n/a), 1 (one-handed), 2 (two-handed)
# weapon_damage_mult: multiplier on player base damage when wielded
const BASE_ITEMS: Array = [
	# Armor — anyone can wear. set_id groups pieces into named set bonuses.
	{
		"id": "iron_helmet",
		"kind": "armor",
		"slot": SLOT_HELMET,
		"title": "Iron Helmet",
		"icon": "res://assets/sprites/items/gear_helmet_iron.png",
		"class_lock": "",
		"set_id": "ironclad"
	},
	{
		"id": "plate_chest",
		"kind": "armor",
		"slot": SLOT_CHEST,
		"title": "Plated Chestguard",
		"icon": "res://assets/sprites/items/gear_chest_plate.png",
		"class_lock": "",
		"set_id": "ironclad"
	},
	{
		"id": "iron_gauntlets",
		"kind": "armor",
		"slot": SLOT_GLOVES,
		"title": "Iron Gauntlets",
		"icon": "res://assets/sprites/items/gear_gloves_gauntlets.png",
		"class_lock": "",
		"set_id": "ironclad"
	},
	{
		"id": "iron_greaves",
		"kind": "armor",
		"slot": SLOT_BOOTS,
		"title": "Iron Greaves",
		"icon": "res://assets/sprites/items/gear_boots_greaves.png",
		"class_lock": "",
		"set_id": "ironclad"
	},
	{
		"id": "gothic_amulet",
		"kind": "armor",
		"slot": SLOT_AMULET,
		"title": "Gothic Pendant",
		"icon": "res://assets/sprites/items/gear_amulet_pendant.png",
		"class_lock": "",
		"set_id": "voidweave"
	},
	{
		"id": "signet_ring",
		"kind": "armor",
		"slot": SLOT_RING_1,
		"title": "Signet Ring",
		"icon": "res://assets/sprites/items/gear_ring_signet.png",
		"class_lock": "",
		"set_id": "voidweave"
	},
	# Barbarian weapons
	{
		"id": "barb_2h_axe",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Cleaving Axe",
		"icon": "res://assets/sprites/items/weapon_barb_2h_axe.png",
		"class_lock": "barbarian",
		"weapon_hands": 2,
		"weapon_damage_mult": 1.7
	},
	{
		"id": "barb_1h_axe",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "War Hatchet",
		"icon": "res://assets/sprites/items/weapon_barb_1h_axe.png",
		"class_lock": "barbarian",
		"weapon_hands": 1,
		"weapon_damage_mult": 1.05
	},
	# Rogue weapons
	{
		"id": "rogue_dagger",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Curved Dagger",
		"icon": "res://assets/sprites/items/weapon_rogue_dagger.png",
		"class_lock": "rogue",
		"weapon_hands": 1,
		"weapon_damage_mult": 1.0
	},
	{
		"id": "rogue_bow",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Hunting Bow",
		"icon": "res://assets/sprites/items/weapon_rogue_bow.png",
		"class_lock": "rogue",
		"weapon_hands": 2,
		"weapon_damage_mult": 1.65
	},
	# Mage weapons
	{
		"id": "mage_wand",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Arcane Wand",
		"icon": "res://assets/sprites/items/weapon_mage_wand.png",
		"class_lock": "mage",
		"weapon_hands": 1,
		"weapon_damage_mult": 1.0
	},
	{
		"id": "mage_staff",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Crystal Staff",
		"icon": "res://assets/sprites/items/weapon_mage_staff.png",
		"class_lock": "mage",
		"weapon_hands": 2,
		"weapon_damage_mult": 1.7
	},
]

# Unique items — fixed affixes, class-locked, each has a transform_id that
# changes a specific skill's behavior.
const UNIQUE_ITEMS: Array = [
	# Barbarian uniques
	{
		"id": "berserkers_halo",
		"kind": "armor",
		"slot": SLOT_HELMET,
		"title": "Berserker's Halo",
		"icon": "res://assets/sprites/items/unique_berserker_halo.png",
		"class_lock": "barbarian",
		"transform": "berserkers_halo",
		"transform_desc": "Whirlwind leaves a ring of fire that burns enemies for 3 seconds.",
		"fixed_affixes":
		[
			{"id": "armor", "value": 24},
			{"id": "fire_dmg", "value": 25},
			{"id": "damage", "value": 12},
			{"id": "max_hp", "value": 25},
		]
	},
	{
		"id": "crimson_aegis",
		"kind": "armor",
		"slot": SLOT_CHEST,
		"title": "Crimson Aegis",
		"icon": "res://assets/sprites/items/unique_crimson_aegis.png",
		"class_lock": "barbarian",
		"transform": "crimson_aegis",
		"transform_desc": "Battle Cry creates a burning aura that damages every enemy nearby.",
		"fixed_affixes":
		[
			{"id": "armor", "value": 50},
			{"id": "max_hp", "value": 80},
			{"id": "fire_dmg", "value": 35},
			{"id": "damage", "value": 15},
		]
	},
	{
		"id": "quakegrasp_gauntlets",
		"kind": "armor",
		"slot": SLOT_GLOVES,
		"title": "Quake-Grasp Gauntlets",
		"icon": "res://assets/sprites/items/unique_quakegrasp_gauntlets.png",
		"class_lock": "barbarian",
		"transform": "quakegrasp_gauntlets",
		"transform_desc": "Earthquake sends 5 shockwaves instead of 3, and they travel faster.",
		"fixed_affixes":
		[
			{"id": "armor", "value": 20},
			{"id": "damage", "value": 20},
			{"id": "crit_chance", "value": 8},
			{"id": "fire_dmg", "value": 20},
		]
	},
	{
		"id": "worldcleaver",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Worldcleaver",
		"icon": "res://assets/sprites/items/unique_worldcleaver.png",
		"class_lock": "barbarian",
		"weapon_hands": 2,
		"weapon_damage_mult": 2.0,
		"transform": "worldcleaver",
		"transform_desc": "Leap Slam unleashes a mini-earthquake on landing.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 35},
			{"id": "crit_chance", "value": 10},
			{"id": "crit_dmg", "value": 30},
			{"id": "fire_dmg", "value": 25},
		]
	},
	# Rogue uniques
	{
		"id": "phantom_soles",
		"kind": "armor",
		"slot": SLOT_BOOTS,
		"title": "Phantom Soles",
		"icon": "res://assets/sprites/items/unique_phantom_soles.png",
		"class_lock": "rogue",
		"transform": "phantom_soles",
		"transform_desc": "Dashing slashes Smoke Bomb's cooldown by 60%.",
		"fixed_affixes":
		[
			{"id": "move_speed", "value": 20},
			{"id": "crit_chance", "value": 12},
			{"id": "armor", "value": 15},
			{"id": "damage", "value": 12},
		]
	},
	{
		"id": "venomweave",
		"kind": "armor",
		"slot": SLOT_GLOVES,
		"title": "Venomweave",
		"icon": "res://assets/sprites/items/unique_venomweave.png",
		"class_lock": "rogue",
		"transform": "venomweave",
		"transform_desc": "Each Fan of Knives blade leaves a poison puddle.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 18},
			{"id": "crit_chance", "value": 10},
			{"id": "armor", "value": 12},
			{"id": "fire_dmg", "value": 15},
		]
	},
	{
		"id": "mark_of_coil",
		"kind": "armor",
		"slot": SLOT_AMULET,
		"title": "Mark of the Coil",
		"icon": "res://assets/sprites/items/unique_mark_of_coil.png",
		"class_lock": "rogue",
		"transform": "mark_of_coil",
		"transform_desc": "Caltrops detonate after 4 seconds, dealing burst damage.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 22},
			{"id": "crit_chance", "value": 15},
			{"id": "crit_dmg", "value": 40},
			{"id": "max_hp", "value": 30},
		]
	},
	{
		"id": "whisper_edge",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Whisper-Edge",
		"icon": "res://assets/sprites/items/unique_whisper_edge.png",
		"class_lock": "rogue",
		"weapon_hands": 1,
		"weapon_damage_mult": 1.3,
		"transform": "whisper_edge",
		"transform_desc": "Stealth attacks deal radial damage in a wide arc around you.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 28},
			{"id": "crit_chance", "value": 18},
			{"id": "crit_dmg", "value": 50},
			{"id": "move_speed", "value": 15},
		]
	},
	# Mage uniques
	{
		"id": "storm_sigil",
		"kind": "armor",
		"slot": SLOT_RING_1,
		"title": "Storm Sigil",
		"icon": "res://assets/sprites/items/unique_storm_sigil.png",
		"class_lock": "mage",
		"transform": "storm_sigil",
		"transform_desc": "Chain Lightning leaps to 3 extra targets.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 18},
			{"id": "crit_chance", "value": 10},
			{"id": "max_mana", "value": 25},
			{"id": "fire_dmg", "value": 25},
		]
	},
	{
		"id": "frostwalker",
		"kind": "armor",
		"slot": SLOT_BOOTS,
		"title": "Frostwalker",
		"icon": "res://assets/sprites/items/unique_frostwalker.png",
		"class_lock": "mage",
		"transform": "frostwalker",
		"transform_desc": "Each step leaves an icy trail that slows enemies.",
		"fixed_affixes":
		[
			{"id": "move_speed", "value": 18},
			{"id": "max_mana", "value": 20},
			{"id": "armor", "value": 15},
			{"id": "damage", "value": 15},
		]
	},
	{
		"id": "pyrocrown",
		"kind": "armor",
		"slot": SLOT_HELMET,
		"title": "Pyrocrown",
		"icon": "res://assets/sprites/items/unique_pyrocrown.png",
		"class_lock": "mage",
		"transform": "pyrocrown",
		"transform_desc": "Meteor lands faster and leaves a burning crater.",
		"fixed_affixes":
		[
			{"id": "fire_dmg", "value": 40},
			{"id": "damage", "value": 18},
			{"id": "max_mana", "value": 30},
			{"id": "crit_chance", "value": 8},
		]
	},
	{
		"id": "voidstaff",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Voidstaff",
		"icon": "res://assets/sprites/items/unique_voidstaff.png",
		"class_lock": "mage",
		"weapon_hands": 2,
		"weapon_damage_mult": 1.9,
		"transform": "voidstaff",
		"transform_desc": "Magic Bolt pierces straight through every enemy.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 32},
			{"id": "crit_chance", "value": 12},
			{"id": "crit_dmg", "value": 35},
			{"id": "max_mana", "value": 30},
		]
	},
	# ─────────────────────────────────────────────────────────────────────
	# STORMCALLER UNIQUES — fixes "can't buy unique" by adding her to the pool.
	{
		"id": "voltaic_tonfa",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Voltaic Tonfa",
		"icon": "res://assets/sprites/items/icon_unique_basic_voltaic_tonfa.png",
		"class_lock": "stormcaller",
		"weapon_hands": 1,
		"weapon_damage_mult": 1.45,
		"transform": "basic_storm_voltaic_tonfa",
		"transform_desc":
		"Basic attack becomes a melee lightning tonfa that chains to a second target.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 22},
			{"id": "crit_chance", "value": 10},
			{"id": "move_speed", "value": 6},
			{"id": "max_mana", "value": 20},
		]
	},
	{
		"id": "stormveil",
		"kind": "armor",
		"slot": SLOT_CHEST,
		"title": "Stormveil",
		"icon": "res://assets/sprites/items/icon_storm_stormveil.png",
		"class_lock": "stormcaller",
		"transform": "storm_stormveil",
		"transform_desc": "Storm Step blinds enemies along the path with a 1.5s slow.",
		"fixed_affixes":
		[
			{"id": "armor", "value": 30},
			{"id": "max_hp", "value": 50},
			{"id": "crit_chance", "value": 6},
			{"id": "move_speed", "value": 8},
		]
	},
	{
		"id": "heavens_spear",
		"kind": "armor",
		"slot": SLOT_GLOVES,
		"title": "Heaven's Spear",
		"icon": "res://assets/sprites/items/icon_storm_heavens_spear.png",
		"class_lock": "stormcaller",
		"transform": "storm_heavens_spear",
		"transform_desc": "Sky Strike leaves charged ground patches that shock enemies for 1.2s.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 20},
			{"id": "crit_dmg", "value": 30},
			{"id": "max_mana", "value": 25},
		]
	},
	{
		"id": "capacitor_core",
		"kind": "armor",
		"slot": SLOT_AMULET,
		"title": "Capacitor Core",
		"icon": "res://assets/sprites/items/icon_storm_capacitor_core.png",
		"class_lock": "stormcaller",
		"transform": "storm_capacitor_core",
		"transform_desc":
		"Raises Static Charge cap to 9. Static Discharge refunds half its cooldown on 6+ stacks.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 18},
			{"id": "max_mana", "value": 35},
			{"id": "crit_chance", "value": 8},
			{"id": "crit_dmg", "value": 25},
		]
	},
	# ─────────────────────────────────────────────────────────────────────
	# HEXEN UNIQUES
	{
		"id": "eternal_mark",
		"kind": "armor",
		"slot": SLOT_AMULET,
		"title": "Eternal Mark",
		"icon": "res://assets/sprites/items/icon_hexen_eternal_mark.png",
		"class_lock": "hexen",
		"transform": "hexen_eternal_mark",
		"transform_desc":
		"Hex Marks never expire on their own — only Soul Tether or Blood Whip detonates them.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 18},
			{"id": "max_hp", "value": 35},
			{"id": "max_mana", "value": 25},
		]
	},
	{
		"id": "tether_shock",
		"kind": "armor",
		"slot": SLOT_GLOVES,
		"title": "Tether Shock",
		"icon": "res://assets/sprites/items/icon_hexen_tether_shock.png",
		"class_lock": "hexen",
		"transform": "hexen_tether_shock",
		"transform_desc": "Soul Tether briefly stuns linked enemies on big initial hits.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 20},
			{"id": "crit_chance", "value": 10},
			{"id": "crit_dmg", "value": 30},
		]
	},
	{
		"id": "bloodmoon_ritual",
		"kind": "armor",
		"slot": SLOT_HELMET,
		"title": "Bloodmoon Ritual",
		"icon": "res://assets/sprites/items/icon_hexen_bloodmoon.png",
		"class_lock": "hexen",
		"transform": "hexen_bloodmoon",
		"transform_desc": "Crimson Ritual bursts on expiry; kills inside refund its cooldown.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 24},
			{"id": "max_hp", "value": 45},
			{"id": "max_mana", "value": 20},
		]
	},
	# ─────────────────────────────────────────────────────────────────────
	# NECROMANCER UNIQUES
	{
		"id": "bone_spear_unique",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Bone Spear",
		"icon": "res://assets/sprites/items/icon_necro_bone_spear.png",
		"class_lock": "necromancer",
		"weapon_hands": 2,
		"weapon_damage_mult": 1.85,
		"transform": "necro_bone_spear",
		"transform_desc":
		"Raise Skeleton is replaced by a piercing bone-spear projectile (3 enemy pierce).",
		"fixed_affixes":
		[
			{"id": "damage", "value": 30},
			{"id": "crit_dmg", "value": 35},
			{"id": "max_mana", "value": 25},
		]
	},
	{
		"id": "curse_field_unique",
		"kind": "armor",
		"slot": SLOT_CHEST,
		"title": "Curse Field",
		"icon": "res://assets/sprites/items/icon_necro_curse_field.png",
		"class_lock": "necromancer",
		"transform": "necro_curse_field",
		"transform_desc": "Raise Knight is replaced by a curse zone (+50% damage taken inside).",
		"fixed_affixes":
		[
			{"id": "armor", "value": 28},
			{"id": "max_hp", "value": 50},
			{"id": "damage", "value": 16},
			{"id": "max_mana", "value": 20},
		]
	},
	# ─────────────────────────────────────────────────────────────────────
	# DRUID UNIQUES
	{
		"id": "druid_hurricane_unique",
		"kind": "armor",
		"slot": SLOT_HELMET,
		"title": "Eye of the Storm",
		"icon": "res://assets/sprites/items/icon_druid_hurricane.png",
		"class_lock": "druid",
		"transform": "druid_hurricane",
		"transform_desc": "Wolf Form is replaced by a hurricane that chases enemies for 8s.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 22},
			{"id": "max_hp", "value": 40},
			{"id": "move_speed", "value": 8},
		]
	},
	{
		"id": "druid_dire_wolf_unique",
		"kind": "armor",
		"slot": SLOT_GLOVES,
		"title": "Alpha Predator",
		"icon": "res://assets/sprites/items/icon_druid_dire_wolf.png",
		"class_lock": "druid",
		"transform": "druid_dire_wolf",
		"transform_desc":
		"Bear Form is replaced by Dire Wolf Form — wolf moveset with crimson tint.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 26},
			{"id": "crit_chance", "value": 8},
			{"id": "move_speed", "value": 10},
		]
	},
]

# Affix pool used for rolled (non-unique) items. Each affix has:
#   id     — used to aggregate stats
#   title  — short display
#   min/max — base range at ilvl 1
#   per_ilvl — additive scaling per item level
#   suffix — "%" or "" for display
const AFFIX_POOL: Array = [
	{"id": "armor", "title": "Armor", "min": 4, "max": 9, "per_ilvl": 2.0, "suffix": ""},
	{"id": "max_hp", "title": "Max HP", "min": 8, "max": 18, "per_ilvl": 3.0, "suffix": ""},
	{"id": "max_mana", "title": "Max Mana", "min": 6, "max": 14, "per_ilvl": 2.0, "suffix": ""},
	{"id": "damage", "title": "Damage", "min": 4, "max": 8, "per_ilvl": 1.5, "suffix": "%"},
	{"id": "move_speed", "title": "Move Speed", "min": 4, "max": 8, "per_ilvl": 0.6, "suffix": "%"},
	{
		"id": "crit_chance",
		"title": "Crit Chance",
		"min": 3,
		"max": 7,
		"per_ilvl": 0.4,
		"suffix": "%"
	},
	{"id": "crit_dmg", "title": "Crit Damage", "min": 8, "max": 16, "per_ilvl": 1.2, "suffix": "%"},
	{"id": "fire_dmg", "title": "Fire Damage", "min": 5, "max": 10, "per_ilvl": 1.0, "suffix": "%"},
	{"id": "gold_gain", "title": "Gold Gain", "min": 8, "max": 16, "per_ilvl": 1.2, "suffix": "%"},
	{"id": "xp_gain", "title": "XP Gain", "min": 6, "max": 12, "per_ilvl": 0.8, "suffix": "%"},
	{
		"id": "cdr",
		"title": "Cooldown Reduction",
		"min": 3,
		"max": 6,
		"per_ilvl": 0.3,
		"suffix": "%"
	},
]


# ─────────────────────────────────────────────────────────────────────────────
# Lookups
static func find_base(id: String) -> Dictionary:
	for b in BASE_ITEMS:
		if String(b.get("id", "")) == id:
			return b
	return {}


static func find_unique(id: String) -> Dictionary:
	for u in UNIQUE_ITEMS:
		if String(u.get("id", "")) == id:
			return u
	return {}


static func find_affix(id: String) -> Dictionary:
	for a in AFFIX_POOL:
		if String(a.get("id", "")) == id:
			return a
	return {}


static func slot_name(slot: int) -> String:
	return String(SLOT_NAMES.get(slot, "Unknown"))


static func get_base_items_for_slot(slot: int, class_id: String) -> Array:
	# Return all base item templates that fit a slot for a class (any-class allowed).
	var out: Array = []
	# Treat both ring slots as one for matching.
	var s: int = slot
	if s == SLOT_RING_2:
		s = SLOT_RING_1
	for b in BASE_ITEMS:
		if int(b.get("slot", -1)) != s:
			continue
		var lock: String = String(b.get("class_lock", ""))
		if lock != "" and lock != class_id:
			continue
		out.append(b)
	return out


static func get_uniques_for_class(class_id: String) -> Array:
	var out: Array = []
	for u in UNIQUE_ITEMS:
		if String(u.get("class_lock", "")) == class_id:
			out.append(u)
	return out


static func find_unique_by_transform(transform_id: String) -> Dictionary:
	for u in UNIQUE_ITEMS:
		if String(u.get("transform", "")) == transform_id:
			return u
	return {}


static func rarity_color(rarity: String) -> Color:
	return Color(RARITY_COLORS.get(rarity, Color.WHITE))


static func rarity_display(rarity: String) -> String:
	return String(RARITY_DISPLAY.get(rarity, "?"))


static func rarity_salvage_gold(rarity: String, ilvl: int) -> int:
	var base: int = int(RARITY_SALVAGE.get(rarity, 5))
	return base + int(float(base) * 0.25 * float(max(0, ilvl - 1)))
