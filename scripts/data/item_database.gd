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
	SLOT_HELMET: "Шлем",
	SLOT_CHEST: "Доспех",
	SLOT_GLOVES: "Перчатки",
	SLOT_BOOTS: "Сапоги",
	SLOT_AMULET: "Амулет",
	SLOT_RING_1: "Кольцо 1",
	SLOT_RING_2: "Кольцо 2",
	SLOT_WEAPON_MAIN: "Правая рука",
	SLOT_WEAPON_OFF: "Левая рука",
}

const SLOT_COUNT: int = 9

# Rarity tiers — count of rolled affixes and weight in random rolls.
const RARITY_COMMON: String = "common"
const RARITY_RARE: String = "rare"
const RARITY_LEGENDARY: String = "legendary"
# Set items (green): 3 affixes (2 from the set's theme pool) + 2/4/5-piece
# bonuses. Desirability sits between legendary and unique. Armor + jewelry only.
const RARITY_SET: String = "set"
const RARITY_UNIQUE: String = "unique"

const RARITY_AFFIX_COUNT: Dictionary = {
	RARITY_COMMON: 1,
	RARITY_RARE: 2,
	RARITY_SET: 3,
	RARITY_LEGENDARY: 4,
	RARITY_UNIQUE: 5,
}

# Base drop weights (modified by item level — uniques get bonus on high waves).
const RARITY_WEIGHTS: Dictionary = {
	RARITY_COMMON: 25.0,
	RARITY_RARE: 25.0,
	RARITY_LEGENDARY: 25.0,
	RARITY_SET: 12.0,
	RARITY_UNIQUE: 25.0,
}

const RARITY_COLORS: Dictionary = {
	RARITY_COMMON: Color(0.82, 0.82, 0.86, 1),
	RARITY_RARE: Color(0.45, 0.72, 1.0, 1),
	RARITY_LEGENDARY: Color(1.0, 0.65, 0.18, 1),
	RARITY_SET: Color(0.35, 0.9, 0.35, 1),
	RARITY_UNIQUE: Color(1.0, 0.35, 0.25, 1),
}

const RARITY_DISPLAY: Dictionary = {
	RARITY_COMMON: "Обычный",
	RARITY_RARE: "Редкий",
	RARITY_LEGENDARY: "Легендарный",
	RARITY_SET: "Комплектный",
	RARITY_UNIQUE: "Уникальный",
}

# Salvage gold per rarity (multiplied by ilvl). Used by sell_item ONLY —
# salvaging (disassembly) yields crafting materials, not gold.
const RARITY_SALVAGE: Dictionary = {
	RARITY_COMMON: 8,
	RARITY_RARE: 25,
	RARITY_LEGENDARY: 75,
	RARITY_SET: 120,
	RARITY_UNIQUE: 220,
}

# ── Crafting materials ────────────────────────────────────────────────────────
# Salvaging an item yields its slot's base material (scrap from weapons + heavy
# armor, cloth from light armor + jewelry) plus essence scaled by rarity.
const MATERIAL_IDS: Array = ["scrap", "cloth", "essence"]

const MATERIAL_DISPLAY: Dictionary = {
	"scrap": "Лом",
	"cloth": "Ткань",
	"essence": "Эссенция",
}

const MATERIAL_COLORS: Dictionary = {
	"scrap": Color(0.75, 0.75, 0.8, 1),
	"cloth": Color(0.85, 0.7, 0.95, 1),
	"essence": Color(0.4, 0.9, 0.95, 1),
}

const RARITY_SALVAGE_ESSENCE: Dictionary = {
	RARITY_COMMON: 1,
	RARITY_RARE: 2,
	RARITY_SET: 4,
	RARITY_LEGENDARY: 4,
	RARITY_UNIQUE: 8,
}

const SLOT_SALVAGE_MATERIAL: Dictionary = {
	SLOT_HELMET: "scrap",
	SLOT_CHEST: "scrap",
	SLOT_WEAPON_MAIN: "scrap",
	SLOT_WEAPON_OFF: "scrap",
	SLOT_GLOVES: "cloth",
	SLOT_BOOTS: "cloth",
	SLOT_AMULET: "cloth",
	SLOT_RING_1: "cloth",
	SLOT_RING_2: "cloth",
}

# ── Set catalog ───────────────────────────────────────────────────────────────
# A set item's set_id is rolled onto the ItemInstance at drop time (any armor /
# jewelry base can become any eligible set's piece). Shape:
#   classes        — [] = generic (drops for everyone), else ["mage"].
#   theme_affixes  — 2 of the item's 3 affixes roll from this list, the 3rd
#                    from the slot pool. This is WHY you chase a specific set's
#                    jewelry: it guarantees the theme on a slot that normally
#                    rolls anything.
#   bonus2.stats   — flat stat bonuses folded into InventorySystem totals.
#   bonus4.grants  — free ranks of a talent node while 4+ pieces are worn
#                    (generic sets resolve per class via grants_by_class).
#   bonus5.effect  — mini-transform effect id, checked at the relevant combat
#                    site via InventorySystem.has_set_effect().
# Piece counting: every equipped piece counts (armor slots + amulet + both
# rings), so jewelry-only pairs trigger 2pc and any mix can reach the 5pc cap.
const SETS: Dictionary = {
	"hunters_oath":
	{
		"name": "Клятва охотника",
		"flavor": "Добыча уже мертва.",
		"classes": [],
		"theme_affixes": ["crit_chance", "crit_dmg", "dexterity"],
		"bonus2": {"stats": {"crit_chance": 6}, "label": "+6% к шансу крита"},
		"bonus4":
		{
			"grants_by_class":
			{
				"barbarian": {"node": "stat_dexterity", "ranks": 2},
				"rogue": {"node": "stat_dexterity", "ranks": 2},
				"mage": {"node": "stat_dexterity", "ranks": 2},
				"stormcaller": {"node": "stat_dexterity", "ranks": 2},
				"hexen": {"node": "stat_dexterity", "ranks": 2},
				"necromancer": {"node": "stat_dexterity", "ranks": 2},
				"druid": {"node": "stat_dexterity", "ranks": 2},
			},
			"label": "+4 к Ловкости",
		},
		"bonus5":
		{
			"effect": "hunt_mark",
			"label": "Удары метят добычу: +4% получаемого урона за стак (макс. 5)",
		},
	},
	"bastion_vow":
	{
		"name": "Обет бастиона",
		"flavor": "Стена не преклоняет колен.",
		"classes": [],
		"theme_affixes": ["armor", "max_hp", "strength"],
		"bonus2": {"stats": {"max_hp": 40, "armor": 10}, "label": "+40 к макс. здоровью, +10 к броне"},
		"bonus4":
		{
			"grants_by_class":
			{
				"barbarian": {"node": "stat_strength", "ranks": 2},
				"rogue": {"node": "stat_strength", "ranks": 2},
				"mage": {"node": "stat_strength", "ranks": 2},
				"stormcaller": {"node": "stat_strength", "ranks": 2},
				"hexen": {"node": "stat_strength", "ranks": 2},
				"necromancer": {"node": "stat_strength", "ranks": 2},
				"druid": {"node": "stat_strength", "ranks": 2},
			},
			"label": "+4 к Силе",
		},
		"bonus5":
		{
			"effect": "bastion_shield",
			"label": "Ниже 30% здоровья: щит на 25% макс. здоровья (перезарядка 30 с)",
		},
	},
	"cinderweave":
	{
		"name": "Пепельное плетение",
		"flavor": "Всё возвращается в пепел.",
		"classes": ["mage"],
		"theme_affixes": ["fire_dmg", "max_mana", "intelligence"],
		"bonus2": {"stats": {"max_mana": 25}, "label": "+25 к макс. мане"},
		"bonus4":
		{"grants": {"node": "mt_radius", "ranks": 2}, "label": "+2 ранга радиуса Метеора"},
		"bonus5":
		{
			"effect": "mage_emberfall",
			"label": "Удары Метеора оставляют горящее огненное кольцо",
		},
	},
	"warbreaker_plate":
	{
		"name": "Латы сокрушителя войн",
		"flavor": "Откованы в проломе.",
		"classes": ["barbarian"],
		"theme_affixes": ["damage", "max_hp", "strength"],
		"bonus2": {"stats": {"damage": 12}, "label": "+12% к урону"},
		"bonus4":
		{
			"grants": {"node": "barb_cry_power", "ranks": 2},
			"label": "+2 ранга силы Боевого клича"
		},
		"bonus5":
		{
			"effect": "barb_aftershock",
			"label": "Ударные волны Землетрясения обездвиживают врагов на 0,6 с",
		},
	},
	"nightshade_silks":
	{
		"name": "Шелка ночной тени",
		"flavor": "Шёпот — и тишина.",
		"classes": ["rogue"],
		"theme_affixes": ["crit_chance", "move_speed", "dexterity"],
		"bonus2": {"stats": {"move_speed": 8}, "label": "+8% к скорости бега"},
		"bonus4":
		{
			"grants": {"node": "rogue_knives_count", "ranks": 2},
			"label": "+2 ранга клинков Веера ножей",
		},
		"bonus5":
		{
			"effect": "rogue_toxin",
			"label": "Кинжалы Веера ножей оставляют ядовитые лужи",
		},
	},
	"stormcage_array":
	{
		"name": "Грозовая клеть",
		"flavor": "Небо повинуется.",
		"classes": ["stormcaller"],
		"theme_affixes": ["damage", "max_mana", "crit_dmg"],
		"bonus2": {"stats": {"max_mana": 20}, "label": "+20 к макс. мане"},
		"bonus4":
		{
			"grants": {"node": "storm_bolt_jumps", "ranks": 2},
			"label": "+2 ранга прыжков Цепного разряда",
		},
		"bonus5":
		{
			"effect": "storm_overcharge",
			"label": "Разряд статики при 6+ стаках бесплатно бьёт Небесным ударом",
		},
	},
	"covenant_threads":
	{
		"name": "Нити договора",
		"flavor": "Каждый договор оплачен кровью.",
		"classes": ["hexen"],
		"theme_affixes": ["damage", "max_hp", "intelligence"],
		"bonus2": {"stats": {"max_hp": 30}, "label": "+30 к макс. здоровью"},
		"bonus4":
		{
			"grants": {"node": "hexen_mark_duration", "ranks": 2},
			"label": "+2 ранга длительности Метки проклятия",
		},
		"bonus5":
		{
			"effect": "hexen_echo_mark",
			"label": "Подрыв Метки проклятия переносит её на ближайшего врага без метки",
		},
	},
	"gravewrought_regalia":
	{
		"name": "Могильные регалии",
		"flavor": "Служба не кончается со смертью.",
		"classes": ["necromancer"],
		"theme_affixes": ["max_mana", "damage", "intelligence"],
		"bonus2": {"stats": {"max_mana": 20}, "label": "+20 к макс. мане"},
		"bonus4":
		{
			"grants": {"node": "necro_pact_power", "ranks": 2},
			"label": "+2 ранга силы Кровавого договора",
		},
		"bonus5":
		{
			"effect": "necro_grave_burst",
			"label": "Ваши приспешники, умирая, взрываются костяной новой",
		},
	},
	"wildheart_totems":
	{
		"name": "Тотемы дикого сердца",
		"flavor": "Лес помнит своих.",
		"classes": ["druid"],
		"theme_affixes": ["max_hp", "move_speed", "strength"],
		"bonus2":
		{
			"stats": {"move_speed": 5, "max_hp": 20},
			"label": "+5% к скорости бега, +20 к макс. здоровью"
		},
		"bonus4":
		{
			"grants": {"node": "wolf_duration", "ranks": 2},
			"label": "+2 ранга длительности Облика волка"
		},
		"bonus5":
		{
			"effect": "druid_thorns",
			"label": "В зверином облике атакующие получают 15% нанесённого урона",
		},
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
		"title": "Железный шлем",
		"icon": "res://assets/sprites/items/gear_helmet_iron.png",
		"class_lock": "",
	},
	{
		"id": "plate_chest",
		"kind": "armor",
		"slot": SLOT_CHEST,
		"title": "Латный нагрудник",
		"icon": "res://assets/sprites/items/gear_chest_plate.png",
		"class_lock": "",
	},
	{
		"id": "iron_gauntlets",
		"kind": "armor",
		"slot": SLOT_GLOVES,
		"title": "Железные рукавицы",
		"icon": "res://assets/sprites/items/gear_gloves_gauntlets.png",
		"class_lock": "",
	},
	{
		"id": "iron_greaves",
		"kind": "armor",
		"slot": SLOT_BOOTS,
		"title": "Железные поножи",
		"icon": "res://assets/sprites/items/gear_boots_greaves.png",
		"class_lock": "",
	},
	{
		"id": "gothic_amulet",
		"kind": "armor",
		"slot": SLOT_AMULET,
		"title": "Готический кулон",
		"icon": "res://assets/sprites/items/gear_amulet_pendant.png",
		"class_lock": "",
	},
	{
		"id": "signet_ring",
		"kind": "armor",
		"slot": SLOT_RING_1,
		"title": "Перстень-печатка",
		"icon": "res://assets/sprites/items/gear_ring_signet.png",
		"class_lock": "",
	},
	# Barbarian weapons
	{
		"id": "barb_2h_axe",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Рубящий топор",
		"icon": "res://assets/sprites/items/weapon_barb_2h_axe.png",
		"class_lock": "barbarian",
		"weapon_hands": 2,
		"weapon_damage_mult": 1.7
	},
	{
		"id": "barb_1h_axe",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Боевая секира",
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
		"title": "Изогнутый кинжал",
		"icon": "res://assets/sprites/items/weapon_rogue_dagger.png",
		"class_lock": "rogue",
		"weapon_hands": 1,
		"weapon_damage_mult": 1.0
	},
	{
		"id": "rogue_bow",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Охотничий лук",
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
		"title": "Чародейский жезл",
		"icon": "res://assets/sprites/items/weapon_mage_wand.png",
		"class_lock": "mage",
		"weapon_hands": 1,
		"weapon_damage_mult": 1.0
	},
	{
		"id": "mage_staff",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Хрустальный посох",
		"icon": "res://assets/sprites/items/weapon_mage_staff.png",
		"class_lock": "mage",
		"weapon_hands": 1,
		"weapon_damage_mult": 1.3
	},
	{
		# Caster off-hand catalyst — lands in the OFF hand so a mage wields two
		# slots (e.g. staff + tome). TODO(art): dedicated off-hand sprite; reuses
		# the wand icon as a placeholder for now. A "totem" variant can be added
		# the same way later.
		"id": "mage_spell_tome",
		"kind": "weapon",
		"slot": SLOT_WEAPON_OFF,
		"title": "Том заклинаний",
		"icon": "res://assets/sprites/items/weapon_mage_wand.png",
		"class_lock": "mage",
		"weapon_hands": 1,
		"weapon_damage_mult": 0.7
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
		"title": "Нимб берсерка",
		"icon": "res://assets/sprites/items/unique_berserker_halo.png",
		"class_lock": "barbarian",
		"transform": "berserkers_halo",
		"transform_desc": "Вихрь оставляет огненное кольцо, обжигающее врагов 3 секунды.",
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
		"title": "Багровая эгида",
		"icon": "res://assets/sprites/items/unique_crimson_aegis.png",
		"class_lock": "barbarian",
		"transform": "crimson_aegis",
		"transform_desc": "Боевой клич создаёт пылающую ауру, ранящую всех врагов поблизости.",
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
		"title": "Рукавицы землехвата",
		"icon": "res://assets/sprites/items/unique_quakegrasp_gauntlets.png",
		"class_lock": "barbarian",
		"transform": "quakegrasp_gauntlets",
		"transform_desc": "Землетрясение выпускает 5 ударных волн вместо 3, и они летят быстрее.",
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
		"title": "Мирокол",
		"icon": "res://assets/sprites/items/unique_worldcleaver.png",
		"class_lock": "barbarian",
		"weapon_hands": 2,
		"weapon_damage_mult": 2.0,
		"transform": "worldcleaver",
		"transform_desc": "Прыжок-удар обрушивает мини-землетрясение при приземлении.",
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
		"title": "Призрачные подошвы",
		"icon": "res://assets/sprites/items/unique_phantom_soles.png",
		"class_lock": "rogue",
		"transform": "phantom_soles",
		"transform_desc": "Рывок сокращает перезарядку Дымовой бомбы на 60%.",
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
		"title": "Ядоплетение",
		"icon": "res://assets/sprites/items/unique_venomweave.png",
		"class_lock": "rogue",
		"transform": "venomweave",
		"transform_desc": "Каждый клинок Веера ножей оставляет ядовитую лужу.",
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
		"title": "Знак Кольца",
		"icon": "res://assets/sprites/items/unique_mark_of_coil.png",
		"class_lock": "rogue",
		"transform": "mark_of_coil",
		"transform_desc": "Шипы детонируют через 4 секунды, нанося взрывной урон.",
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
		"title": "Шёпот-клинок",
		"icon": "res://assets/sprites/items/unique_whisper_edge.png",
		"class_lock": "rogue",
		"weapon_hands": 1,
		"weapon_damage_mult": 1.3,
		"transform": "whisper_edge",
		"transform_desc": "Атаки из скрытности бьют по площади широкой дугой вокруг вас.",
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
		"title": "Грозовая печать",
		"icon": "res://assets/sprites/items/unique_storm_sigil.png",
		"class_lock": "mage",
		"transform": "storm_sigil",
		"transform_desc": "Цепная молния перескакивает на 3 дополнительные цели.",
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
		"title": "Ледоход",
		"icon": "res://assets/sprites/items/unique_frostwalker.png",
		"class_lock": "mage",
		"transform": "frostwalker",
		"transform_desc": "Каждый шаг оставляет ледяной след, замедляющий врагов.",
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
		"title": "Пирокорона",
		"icon": "res://assets/sprites/items/unique_pyrocrown.png",
		"class_lock": "mage",
		"transform": "pyrocrown",
		"transform_desc": "Метеор падает быстрее и оставляет горящий кратер.",
		"fixed_affixes":
		[
			{"id": "fire_dmg", "value": 40},
			{"id": "damage", "value": 18},
			{"id": "max_mana", "value": 30},
			{"id": "crit_chance", "value": 8},
		]
	},
	# Mage talent-transform uniques — only matter when the matching talent
	# transform is taken (the effect code lives inside that skill's script).
	{
		"id": "cinder_cascade",
		"kind": "armor",
		"slot": SLOT_AMULET,
		"title": "Каскад углей",
		"icon": "res://assets/sprites/items/icon_skill_meteor.png",
		"class_lock": "mage",
		"transform": "shower_cascade",
		"requires_transform": "meteor_shower",
		"requires_label": "Требуется вариант: Метеоритный дождь",
		"transform_desc": "Метеоритный дождь обрушивает 2 дополнительных метеора.",
		"fixed_affixes":
		[
			{"id": "fire_dmg", "value": 25},
			{"id": "damage", "value": 15},
			{"id": "max_mana", "value": 20},
		]
	},
	{
		"id": "glacial_heart",
		"kind": "armor",
		"slot": SLOT_RING_1,
		"title": "Ледниковое сердце",
		"icon": "res://assets/sprites/items/icon_skill_ice_bolt.png",
		"class_lock": "mage",
		"transform": "nova_glacial",
		"requires_transform": "frost_nova",
		"requires_label": "Требуется навык: Морозная нова",
		"transform_desc": "Морозная нова вдобавок охлаждает — повторные новы намертво замораживают врагов.",
		"fixed_affixes":
		[
			{"id": "max_mana", "value": 25},
			{"id": "cdr", "value": 5},
			{"id": "intelligence", "value": 4},
		]
	},
	{
		"id": "abyssal_lens",
		"kind": "armor",
		"slot": SLOT_GLOVES,
		"title": "Линза бездны",
		"icon": "res://assets/sprites/items/icon_skill_chain_lightning.png",
		"class_lock": "mage",
		"transform": "beam_twin",
		"requires_transform": "death_beam",
		"requires_label": "Требуется навык: Луч смерти",
		"transform_desc": "Луч смерти выпускает второй луч позади вас.",
		"fixed_affixes":
		[
			{"id": "damage", "value": 20},
			{"id": "crit_dmg", "value": 30},
			{"id": "crit_chance", "value": 8},
		]
	},
	{
		"id": "voidstaff",
		"kind": "weapon",
		"slot": SLOT_WEAPON_MAIN,
		"title": "Посох пустоты",
		"icon": "res://assets/sprites/items/unique_voidstaff.png",
		"class_lock": "mage",
		"weapon_hands": 2,
		"weapon_damage_mult": 1.9,
		"transform": "voidstaff",
		"transform_desc": "Магический снаряд пронзает всех врагов насквозь.",
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
		"title": "Вольтова тонфа",
		"icon": "res://assets/sprites/items/icon_unique_basic_voltaic_tonfa.png",
		"class_lock": "stormcaller",
		"weapon_hands": 1,
		"weapon_damage_mult": 1.45,
		"transform": "basic_storm_voltaic_tonfa",
		"transform_desc":
		"Базовая атака становится молниевой тонфой ближнего боя, перескакивающей на вторую цель.",
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
		"title": "Грозовая вуаль",
		"icon": "res://assets/sprites/items/icon_storm_stormveil.png",
		"class_lock": "stormcaller",
		"transform": "storm_stormveil",
		"transform_desc": "Грозовой шаг ослепляет врагов на пути, замедляя их на 1,5 с.",
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
		"title": "Копьё небес",
		"icon": "res://assets/sprites/items/icon_storm_heavens_spear.png",
		"class_lock": "stormcaller",
		"transform": "storm_heavens_spear",
		"transform_desc": "Небесный удар оставляет заряженные участки земли, бьющие врагов током 1,2 с.",
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
		"title": "Ядро конденсатора",
		"icon": "res://assets/sprites/items/icon_storm_capacitor_core.png",
		"class_lock": "stormcaller",
		"transform": "storm_capacitor_core",
		"transform_desc":
		"Лимит Статического заряда повышен до 9. Разряд статики при 6+ стаках возвращает половину перезарядки.",
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
		"title": "Вечная метка",
		"icon": "res://assets/sprites/items/icon_hexen_eternal_mark.png",
		"class_lock": "hexen",
		"transform": "hexen_eternal_mark",
		"transform_desc":
		"Метки проклятия не истекают сами — их подрывают только Узы души или Кровавый хлыст.",
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
		"title": "Шок уз",
		"icon": "res://assets/sprites/items/icon_hexen_tether_shock.png",
		"class_lock": "hexen",
		"transform": "hexen_tether_shock",
		"transform_desc": "Узы души ненадолго оглушают связанных врагов при сильных первых ударах.",
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
		"title": "Ритуал кровавой луны",
		"icon": "res://assets/sprites/items/icon_hexen_bloodmoon.png",
		"class_lock": "hexen",
		"transform": "hexen_bloodmoon",
		"transform_desc": "Багровый ритуал взрывается по истечении; убийства внутри возвращают перезарядку.",
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
		"title": "Костяное копьё",
		"icon": "res://assets/sprites/items/icon_necro_bone_spear.png",
		"class_lock": "necromancer",
		"weapon_hands": 2,
		"weapon_damage_mult": 1.85,
		"transform": "bone_spear_splinters",
		"requires_transform": "necro_bone_spear",
		"requires_label": "Требуется навык: Костяное копьё",
		"transform_desc":
		"Костяное копьё на последнем пробитии раскалывается на 3 осколка (50% урона).",
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
		"title": "Поле проклятия",
		"icon": "res://assets/sprites/items/icon_necro_curse_field.png",
		"class_lock": "necromancer",
		"transform": "curse_field_harvest",
		"requires_transform": "necro_curse_field",
		"requires_label": "Требуется навык: Поле проклятия",
		"transform_desc":
		"Враги, гибнущие в Поле проклятия, продлевают его на 1 с (до +5 с) и лечат приспешников на 10%.",
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
		"title": "Око бури",
		"icon": "res://assets/sprites/items/icon_druid_hurricane.png",
		"class_lock": "druid",
		"transform": "hurricane_twin",
		"requires_transform": "druid_hurricane",
		"requires_label": "Требуется вариант: Ураган",
		"transform_desc": "Ураган призывает второй, меньший ураган (60% размера и урона).",
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
		"title": "Альфа-хищник",
		"icon": "res://assets/sprites/items/icon_druid_dire_wolf.png",
		"class_lock": "druid",
		"transform": "dire_wolf_rend",
		"requires_transform": "druid_dire_wolf",
		"requires_label": "Требуется вариант: Лютый волк",
		"transform_desc": "В облике лютого волка укусы рвут: цели кровоточат на 60% урона за 3 с.",
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
#   slots  — SLOT_* ints this affix can roll on; [] = every slot. Jewelry
#            (amulet + rings) takes everything; the four armor slots have
#            themed pools: helmet = casting, chest = defense, gloves = offense,
#            boots = mobility/economy.
const AFFIX_POOL: Array = [
	{
		"id": "armor",
		"title": "Броня",
		"min": 4,
		"max": 9,
		"per_ilvl": 2.0,
		"suffix": "",
		"slots":
		[SLOT_HELMET, SLOT_CHEST, SLOT_BOOTS, SLOT_AMULET, SLOT_RING_1, SLOT_RING_2]
	},
	{
		"id": "max_hp",
		"title": "Макс. здоровье",
		"min": 8,
		"max": 18,
		"per_ilvl": 3.0,
		"suffix": "",
		"slots": [SLOT_CHEST, SLOT_AMULET, SLOT_RING_1, SLOT_RING_2]
	},
	{
		"id": "max_mana",
		"title": "Макс. мана",
		"min": 6,
		"max": 14,
		"per_ilvl": 2.0,
		"suffix": "",
		"slots": [SLOT_HELMET, SLOT_AMULET, SLOT_RING_1, SLOT_RING_2]
	},
	{
		"id": "hp_regen",
		"title": "Восст. здоровья",
		"min": 1,
		"max": 2,
		"per_ilvl": 0.4,
		"suffix": "/s",
		"slots": [SLOT_CHEST, SLOT_AMULET, SLOT_RING_1, SLOT_RING_2]
	},
	{
		"id": "damage",
		"title": "Урон",
		"min": 4,
		"max": 8,
		"per_ilvl": 1.5,
		"suffix": "%",
		"slots":
		[
			SLOT_GLOVES,
			SLOT_WEAPON_MAIN,
			SLOT_WEAPON_OFF,
			SLOT_AMULET,
			SLOT_RING_1,
			SLOT_RING_2
		]
	},
	{
		"id": "move_speed",
		"title": "Скорость бега",
		"min": 4,
		"max": 8,
		"per_ilvl": 0.6,
		"suffix": "%",
		"slots": [SLOT_BOOTS, SLOT_AMULET, SLOT_RING_1, SLOT_RING_2]
	},
	{
		"id": "crit_chance",
		"title": "Шанс крита",
		"min": 3,
		"max": 7,
		"per_ilvl": 0.4,
		"suffix": "%",
		"slots":
		[
			SLOT_GLOVES,
			SLOT_WEAPON_MAIN,
			SLOT_WEAPON_OFF,
			SLOT_AMULET,
			SLOT_RING_1,
			SLOT_RING_2
		]
	},
	{
		"id": "crit_dmg",
		"title": "Крит. урон",
		"min": 8,
		"max": 16,
		"per_ilvl": 1.2,
		"suffix": "%",
		"slots":
		[
			SLOT_GLOVES,
			SLOT_WEAPON_MAIN,
			SLOT_WEAPON_OFF,
			SLOT_AMULET,
			SLOT_RING_1,
			SLOT_RING_2
		]
	},
	{
		"id": "fire_dmg",
		"title": "Урон огнём",
		"min": 5,
		"max": 10,
		"per_ilvl": 1.0,
		"suffix": "%",
		"slots":
		[
			SLOT_GLOVES,
			SLOT_WEAPON_MAIN,
			SLOT_WEAPON_OFF,
			SLOT_AMULET,
			SLOT_RING_1,
			SLOT_RING_2
		]
	},
	{
		"id": "gold_gain",
		"title": "Добыча золота",
		"min": 8,
		"max": 16,
		"per_ilvl": 1.2,
		"suffix": "%",
		"slots": [SLOT_BOOTS, SLOT_AMULET, SLOT_RING_1, SLOT_RING_2]
	},
	{
		"id": "xp_gain",
		"title": "Получение опыта",
		"min": 6,
		"max": 12,
		"per_ilvl": 0.8,
		"suffix": "%",
		"slots": [SLOT_BOOTS, SLOT_AMULET, SLOT_RING_1, SLOT_RING_2]
	},
	{
		"id": "cdr",
		"title": "Сокращение перезарядки",
		"min": 3,
		"max": 6,
		"per_ilvl": 0.3,
		"suffix": "%",
		"slots": [SLOT_HELMET, SLOT_AMULET, SLOT_RING_1, SLOT_RING_2]
	},
	# Attributes — universal: legal on every slot.
	{
		"id": "strength",
		"title": "Сила",
		"min": 1,
		"max": 3,
		"per_ilvl": 0.5,
		"suffix": "",
		"slots": []
	},
	{
		"id": "dexterity",
		"title": "Ловкость",
		"min": 1,
		"max": 3,
		"per_ilvl": 0.5,
		"suffix": "",
		"slots": []
	},
	{
		"id": "intelligence",
		"title": "Интеллект",
		"min": 1,
		"max": 3,
		"per_ilvl": 0.5,
		"suffix": "",
		"slots": []
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


# Lazily-built typed view of AFFIX_POOL (affix id -> AffixDefinition). AFFIX_POOL
# stays the authoring source.
static var _affix_defs_cache: Dictionary = {}


static func _affix_defs() -> Dictionary:
	if _affix_defs_cache.is_empty():
		for a in AFFIX_POOL:
			var def := AffixDefinition.from_dict(a)
			_affix_defs_cache[def.id] = def
	return _affix_defs_cache


static func has_affix(id: String) -> bool:
	return _affix_defs().has(id)


# Typed affix template. Returns an AffixDefinition.unknown() placeholder for an
# unknown id (guard with has_affix() to detect a genuine miss).
static func find_affix(id: String) -> AffixDefinition:
	var d = _affix_defs().get(id, null)
	return d if d != null else AffixDefinition.unknown(id)


# All affix templates legal on `slot` (empty `slots` = universal). Ring 2 shares
# Ring 1's pool; unknown slots fall back to the full pool.
static func affixes_for_slot(slot: int) -> Array:
	var s: int = slot
	if s == SLOT_RING_2:
		s = SLOT_RING_1
	var out: Array = []
	for a in _affix_defs().values():
		if a.slots.is_empty() or a.slots.has(s) or s < 0:
			out.append(a)
	return out


static func slot_name(slot: int) -> String:
	return String(SLOT_NAMES.get(slot, "Неизвестно"))


# Lazily-built typed view of SETS (set id -> SetDefinition). SETS stays the
# authoring source.
static var _set_defs_cache: Dictionary = {}


static func _set_defs() -> Dictionary:
	if _set_defs_cache.is_empty():
		for sid in SETS:
			_set_defs_cache[sid] = SetDefinition.from_dict(String(sid), SETS[sid])
	return _set_defs_cache


static func has_set(set_id: String) -> bool:
	return SETS.has(set_id)


# Typed set definition. Returns a SetDefinition.unknown() placeholder for an
# unknown id (guard with has_set() to detect a genuine miss).
static func find_set(set_id: String) -> SetDefinition:
	var d = _set_defs().get(set_id, null)
	return d if d != null else SetDefinition.unknown(set_id)


# Sets a class can drop/wear: both generics + the class's own set.
static func sets_for_class(class_id: String) -> Array:
	var out: Array = []
	for sid in SETS:
		var classes: Array = SETS[sid].get("classes", [])
		if classes.is_empty() or classes.has(class_id):
			out.append(sid)
	return out


# Slots set items can occupy — armor + jewelry, never weapons.
static func set_eligible_slots() -> Array:
	return [SLOT_HELMET, SLOT_CHEST, SLOT_GLOVES, SLOT_BOOTS, SLOT_AMULET, SLOT_RING_1, SLOT_RING_2]


# The 4pc node grant for a set, resolved for a class (generic sets carry a
# per-class table). Returns {"node": id, "ranks": int} or {} — including {}
# when a class set is asked about a foreign class (a gifted foreign set piece
# must never grant nodes the wearer's tree doesn't have).
static func set_node_grant(set_id: String, class_id: String) -> Dictionary:
	var s: Dictionary = SETS.get(set_id, {})
	var classes: Array = s.get("classes", [])
	if not classes.is_empty() and not classes.has(class_id):
		return {}
	var b4: Dictionary = s.get("bonus4", {})
	if b4.has("grants"):
		return b4["grants"]
	return b4.get("grants_by_class", {}).get(class_id, {})


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


# Materials yielded by disassembling an item: base material by slot (scaling
# slowly with ilvl) + essence by rarity. Set-stone grants live in salvage_item
# (they need the instance's set_id, not just the slot/rarity).
static func salvage_materials_for(slot: int, rarity: String, ilvl: int) -> Dictionary:
	var base_mat: String = String(SLOT_SALVAGE_MATERIAL.get(slot, "scrap"))
	var out: Dictionary = {base_mat: 1 + int(float(max(1, ilvl)) / 4.0)}
	var essence: int = int(RARITY_SALVAGE_ESSENCE.get(rarity, 1))
	if essence > 0:
		out["essence"] = int(out.get("essence", 0)) + essence
	return out


# «120з + 3 Лом + 2 Эссенция» — для кнопок торговца, подсказок и предпросмотра разбора.
static func format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "—"
	var parts: Array = []
	var g: int = int(cost.get("gold", 0))
	if g > 0:
		parts.append("%dз" % g)
	for id in MATERIAL_IDS:
		var n: int = int(cost.get(id, 0))
		if n > 0:
			parts.append("%d %s" % [n, String(MATERIAL_DISPLAY.get(id, id))])
	var stones: Dictionary = cost.get("stones", {})
	for set_id in stones:
		parts.append("%d Камень" % int(stones[set_id]))
	if parts.is_empty():
		return "бесплатно"
	return " + ".join(parts)
