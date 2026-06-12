class_name RewardData
extends RefCounted

# Shared catalogs of stat boosts, skill modifiers, and uniques.
# Used by the level-up overlay AND the character sheet items tab.

const STAT_REWARDS := [
	{"id": "hp+20", "title": "Железное сердце", "desc": "+20 к макс. здоровью", "rarity": "common"},
	{"id": "hp+40", "title": "Прилив жизни", "desc": "+40 к макс. здоровью", "rarity": "rare"},
	{"id": "mana+15", "title": "Внутренний источник", "desc": "+15 к макс. мане", "rarity": "common"},
	{"id": "mana+30", "title": "Глубокий резервуар", "desc": "+30 к макс. мане", "rarity": "rare"},
	{"id": "dmg+3", "title": "Заточенное лезвие", "desc": "+3 к урону", "rarity": "common"},
	{"id": "dmg+7", "title": "Смертельная сосредоточенность", "desc": "+7 к урону", "rarity": "rare"},
	{"id": "crit+5", "title": "Инстинкт убийцы", "desc": "+5% к шансу крита", "rarity": "common"},
	{
		"id": "crit_dmg+0.25",
		"title": "Жестокий удар",
		"desc": "+25% к крит. урону",
		"rarity": "rare"
	},
	{"id": "speed+15", "title": "Быстрый шаг", "desc": "+15 к скорости бега", "rarity": "common"},
	{
		"id": "heal_full",
		"title": "Обновление крови",
		"desc": "Полностью восстановить здоровье",
		"rarity": "common"
	},
]

const SKILL_MODIFIERS := [
	{
		"id": "fw_duration",
		"slot": 0,
		"title": "Вечный костёр",
		"desc": "Огненная стена держится дольше и бьёт чаще",
		"rarity": "common",
		"stack_bonus": "+1,5 с длительности и чаще тики"
	},
	{
		"id": "fw_radius",
		"slot": 0,
		"title": "Бескрайнее пекло",
		"desc": "Огненная стена шире",
		"rarity": "common",
		"stack_bonus": "+35% ширины"
	},
	{
		"id": "fw_damage",
		"slot": 0,
		"title": "Пиромантия",
		"desc": "+30% к урону Огненной стены",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "ib_pierce",
		"slot": 1,
		"title": "Пронзающий мороз",
		"desc": "Ледяная стрела пронзает врагов насквозь",
		"rarity": "rare",
		"stack_bonus": "Уже пронзает"
	},
	{
		"id": "ib_slow",
		"slot": 1,
		"title": "Глубокая заморозка",
		"desc": "Ледяная стрела замедляет сильнее и дольше",
		"rarity": "common",
		"stack_bonus": "+1,5 с замедления и сильнее"
	},
	{
		"id": "ib_damage",
		"slot": 1,
		"title": "Закалённый лёд",
		"desc": "+30% к урону Ледяной стрелы",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "cl_jumps",
		"slot": 2,
		"title": "Мастерство дуги",
		"desc": "Цепная молния поражает на две цели больше",
		"rarity": "rare",
		"stack_bonus": "+2 прыжка"
	},
	{
		"id": "cl_damage",
		"slot": 2,
		"title": "Высокое напряжение",
		"desc": "+30% к урону Цепной молнии",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "mt_radius",
		"slot": 3,
		"title": "Большее воздействие",
		"desc": "Радиус взрыва Метеора +50%",
		"rarity": "common",
		"stack_bonus": "+50% радиуса"
	},
	{
		"id": "mt_damage",
		"slot": 3,
		"title": "Небесный молот",
		"desc": "+40% к урону Метеора",
		"rarity": "rare",
		"stack_bonus": "+40% урона"
	},
	# DRUID
	{
		"id": "wolf_duration",
		"slot": 0,
		"title": "Дикая выносливость",
		"desc": "Облик волка держится дольше",
		"rarity": "common",
		"stack_bonus": "+4 с длительности"
	},
	{
		"id": "bear_duration",
		"slot": 1,
		"title": "Железная шкура",
		"desc": "Облик медведя держится дольше",
		"rarity": "common",
		"stack_bonus": "+4 с длительности"
	},
	{
		"id": "stone_armor_charges",
		"slot": 2,
		"title": "Щит горы",
		"desc": "Каменная броня поглощает один лишний удар",
		"rarity": "rare",
		"stack_bonus": "+1 поглощённый удар"
	},
	{
		"id": "spirit_pets",
		"slot": 3,
		"title": "Зов стаи",
		"desc": "Призыв духа может держать на одного зверя больше",
		"rarity": "rare",
		"stack_bonus": "+1 к пределу духов"
	},
	{
		"id": "spirit_summon_damage",
		"slot": 3,
		"title": "Дикие духи",
		"desc": "+30% к урону Призыва духа",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "eagle_duration",
		"slot": 4,
		"title": "Владыка небес",
		"desc": "Облик орла держится дольше",
		"rarity": "common",
		"stack_bonus": "+4 с длительности"
	},
	# NECROMANCER
	{
		"id": "necro_skel_count",
		"slot": 0,
		"title": "Восставший легион",
		"desc": "Поднять скелета может держать на одного бойца больше",
		"rarity": "rare",
		"stack_bonus": "+1 к пределу скелетов"
	},
	{
		"id": "necro_knight_armor",
		"slot": 1,
		"title": "Бронированные кости",
		"desc": "+40 макс. здоровья каждому призванному Костяному рыцарю",
		"rarity": "common",
		"stack_bonus": "+40 здоровья рыцаря"
	},
	{
		"id": "necro_pact_power",
		"slot": 2,
		"title": "Багровый обет",
		"desc": "Кровавый договор даёт приспешникам на +25% больше урона",
		"rarity": "rare",
		"stack_bonus": "+25% урона договора"
	},
	{
		"id": "necro_pulse_radius",
		"slot": 3,
		"title": "Широкий охват",
		"desc": "Радиус Пульса смерти +30%",
		"rarity": "common",
		"stack_bonus": "+30% радиуса"
	},
	{
		"id": "necro_pulse_damage",
		"slot": 3,
		"title": "Могильный резонанс",
		"desc": "+30% к урону Пульса смерти",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	# BARBARIAN — slots: Whirlwind(0), Leap Slam(1), Battle Cry(2), Earthquake(3)
	{
		"id": "barb_whirl_damage",
		"slot": 0,
		"title": "Рассекающее вращение",
		"desc": "+30% к урону Вихря",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "barb_leap_damage",
		"slot": 1,
		"title": "Создатель кратеров",
		"desc": "+30% к урону Прыжка-удара",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "barb_quake_damage",
		"slot": 3,
		"title": "Тектоническая ярость",
		"desc": "+30% к урону Землетрясения",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "barb_cry_power",
		"slot": 2,
		"title": "Рык вождя",
		"desc": "Боевой клич длится дольше и сильнее ускоряет бег",
		"rarity": "rare",
		"stack_bonus": "+2 с длительности и +15% скорости"
	},
	{
		"id": "barb_quake_waves",
		"slot": 3,
		"title": "Повторные толчки",
		"desc": "Землетрясение выпускает ещё одно кольцо ударной волны",
		"rarity": "rare",
		"stack_bonus": "+1 ударная волна"
	},
	# ROGUE — slots: Caltrops(0), Smoke Bomb(1), Poison Vial(2), Fan of Knives(3)
	{
		"id": "rogue_knives_damage",
		"slot": 3,
		"title": "Отточенные клинки",
		"desc": "+30% к урону Веера ножей",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "rogue_knives_count",
		"slot": 3,
		"title": "Буря клинков",
		"desc": "Веер ножей метает на два кинжала больше",
		"rarity": "rare",
		"stack_bonus": "+2 кинжала"
	},
	{
		"id": "rogue_caltrops_duration",
		"slot": 0,
		"title": "Стойкие колючки",
		"desc": "Шипы дольше лежат на земле",
		"rarity": "common",
		"stack_bonus": "+4 с длительности"
	},
	{
		"id": "rogue_caltrops_damage",
		"slot": 0,
		"title": "Зазубренные шипы",
		"desc": "+30% к урону Шипов",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "rogue_poison_damage",
		"slot": 2,
		"title": "Едкое варево",
		"desc": "+30% к урону Склянки яда",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	# HEXEN — slots: Hex Mark(0), Blood Whip(1), Soul Tether(2), Crimson Ritual(3)
	{
		"id": "hexen_mark_damage",
		"slot": 0,
		"title": "Углубляющееся проклятие",
		"desc": "+30% к урону Метки проклятия",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "hexen_mark_duration",
		"slot": 0,
		"title": "Затяжная порча",
		"desc": "Метка проклятия тикает дольше перед подрывом",
		"rarity": "rare",
		"stack_bonus": "+1,5 с длительности"
	},
	{
		"id": "hexen_whip_damage",
		"slot": 1,
		"title": "Свежующая плеть",
		"desc": "+30% к урону Кровавого хлыста",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "hexen_tether_damage",
		"slot": 2,
		"title": "Вытягивание души",
		"desc": "+30% к урону Уз души",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "hexen_ritual_damage",
		"slot": 3,
		"title": "Кровавое крещендо",
		"desc": "+30% к урону Багрового ритуала",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	# STORMCALLER — slots: Chain Bolt(0), Storm Step(1), Sky Strike(2), Static Discharge(3)
	{
		"id": "storm_bolt_damage",
		"slot": 0,
		"title": "Перегруженная дуга",
		"desc": "+30% к урону Цепного разряда",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "storm_bolt_jumps",
		"slot": 0,
		"title": "Раздвоенный путь",
		"desc": "Цепной разряд перескакивает ещё на одну цель",
		"rarity": "rare",
		"stack_bonus": "+1 прыжок"
	},
	{
		"id": "storm_sky_damage",
		"slot": 2,
		"title": "Грозовая туча",
		"desc": "+30% к урону Небесного удара",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
	{
		"id": "storm_discharge_damage",
		"slot": 3,
		"title": "Перегрузка",
		"desc": "+30% к урону Разряда статики",
		"rarity": "common",
		"stack_bonus": "+30% урона"
	},
]

const UNIQUES := [
	{
		"id": "transform_ice_wall",
		"slot": 0,
		"title": "Стена льда",
		"desc": "Огненная стена становится Стеной льда — замораживает и преграждает путь",
		"rarity": "unique",
		"transform": "ice_wall"
	},
	{
		"id": "transform_frost_nova",
		"slot": 1,
		"title": "Морозная нова",
		"desc": "Ледяная стрела становится круговым морозным взрывом вокруг вас",
		"rarity": "unique",
		"transform": "frost_nova"
	},
	{
		"id": "transform_death_beam",
		"slot": 2,
		"title": "Луч смерти",
		"desc": "Цепная молния становится сфокусированным лучом смерти",
		"rarity": "unique",
		"transform": "death_beam"
	},
	{
		"id": "transform_meteor_shower",
		"slot": 3,
		"title": "Метеоритный дождь",
		"desc": "Метеор становится дождём из трёх метеоров поменьше",
		"rarity": "unique",
		"transform": "meteor_shower"
	},
	{
		"id": "stone_armor_grinder",
		"slot": 2,
		"title": "Жернова",
		"desc": "Осколки Каменной брони вращаются и наносят контактный урон врагам рядом",
		"rarity": "unique",
		"transform": "stone_armor_grinder"
	},
	# DRUID UNIQUES — replace shapeshift slots with alternates.
	{
		"id": "transform_druid_hurricane",
		"slot": 0,
		"title": "Око бури",
		"desc": "Облик волка заменяется кружащим Ураганом, преследующим врагов 8 секунд",
		"rarity": "unique",
		"transform": "druid_hurricane"
	},
	{
		"id": "transform_druid_dire_wolf",
		"slot": 1,
		"title": "Альфа-хищник",
		"desc":
		"Облик медведя заменяется Обликом лютого волка — волчий набор приёмов с жестоким уроном и скоростью",
		"rarity": "unique",
		"transform": "druid_dire_wolf"
	},
	{
		"id": "transform_necro_bone_spear",
		"slot": 0,
		"title": "Костяное копьё",
		"desc":
		"Поднять скелета заменяется пронзающим костяным копьём. Вы отдаёте лёгких приспешников ради прямого урона.",
		# NECROMANCER UNIQUES — replace summon slots with direct-damage tools.
		"rarity": "unique",
		"transform": "necro_bone_spear"
	},
	{
		"id": "transform_necro_curse_field",
		"slot": 1,
		"title": "Поле проклятия",
		"desc":
		"Поднять рыцаря заменяется проклятой землёй: враги внутри получают +50% урона в течение 8 секунд",
		"rarity": "unique",
		"transform": "necro_curse_field"
	},
	{
		"id": "transform_hexen_eternal_mark",
		"slot": 0,
		"title": "Вечная метка",
		"desc":
		"Метки проклятия не истекают сами — их подрывают только Узы души или Кровавый хлыст",
		# HEXEN UNIQUES.
		"rarity": "unique",
		"transform": "hexen_eternal_mark"
	},
	{
		"id": "transform_hexen_tether_shock",
		"slot": 2,
		"title": "Шок уз",
		"desc":
		"Узы души ненадолго оглушают связанных врагов, если первый удар превышает половину их здоровья",
		"rarity": "unique",
		"transform": "hexen_tether_shock"
	},
	{
		"id": "transform_hexen_bloodmoon",
		"slot": 3,
		"title": "Ритуал кровавой луны",
		"desc":
		"Багровый ритуал взрывается по истечении; убийство внутри возвращает перезарядку",
		"rarity": "unique",
		"transform": "hexen_bloodmoon"
	},
	# BASIC-ATTACK UNIQUES — one per class. Recognized by player.gd via the
	{
		"id": "basic_barb_shockwave",
		"slot": -1,
		"title": "Рассекающая волна",
		"desc":
		"Базовая атака варвара посылает вперёд ударную волну, проходящую сквозь врагов с 50% урона",
		# "basic_<id>" key in InventorySystem.has_unique().
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_shockwave.png",
		"basic_for": "barbarian"
	},
	{
		"id": "basic_rogue_triple_throw",
		"slot": -1,
		"title": "Тройной бросок",
		"desc": "Базовый кинжал разбойника теперь метает три кинжала коротким веером",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_triple_throw.png",
		"basic_for": "rogue"
	},
	{
		"id": "basic_mage_phantom_edge",
		"slot": -1,
		"title": "Призрачное лезвие",
		"desc": "Снаряд мага заменяется размашистой дугой эфирного меча в ближнем бою",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_phantom_edge.png",
		"basic_for": "mage"
	},
	{
		"id": "basic_druid_thunder_sphere",
		"slot": -1,
		"title": "Громовая сфера",
		"desc": "Коготь друида становится дальнобойным трещащим шаром молний",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_thunder_sphere.png",
		"basic_for": "druid"
	},
	{
		"id": "basic_necro_bone_lance",
		"slot": -1,
		"title": "Костяная пика",
		"desc": "Снаряд некроманта становится выпадом костяной пикой в ближнем бою",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_bone_lance.png",
		"basic_for": "necromancer"
	},
	{
		"id": "basic_hexen_whipcrack",
		"slot": -1,
		"title": "Щелчок хлыста",
		"desc": "Базовая атака ведьмы — быстрый хлыст, вешающий мини-проклятие на 0,5 с при попадании",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_whipcrack.png",
		"basic_for": "hexen"
	},
	{
		"id": "basic_storm_voltaic_tonfa",
		"slot": -1,
		"title": "Вольтова тонфа",
		"desc":
		"Базовая атака буревестницы заменяется взмахом молниевой тонфы, перескакивающим на вторую цель",
		"rarity": "unique",
		"icon": "res://assets/sprites/items/icon_unique_basic_voltaic_tonfa.png",
		"basic_for": "stormcaller"
	},
	# STORMCALLER UNIQUES
	{
		"id": "storm_stormveil",
		"slot": 1,
		"title": "Грозовая вуаль",
		"desc": "Грозовой шаг вдобавок ослепляет врагов на пути: замедление 50% на 1,5 с",
		"rarity": "unique",
		"transform": "storm_stormveil"
	},
	{
		"id": "storm_heavens_spear",
		"slot": 2,
		"title": "Копьё небес",
		"desc":
		"Небесный удар оставляет на земле заряженный участок, бьющий врагов током 1,2 с",
		"rarity": "unique",
		"transform": "storm_heavens_spear"
	},
	{
		"id": "storm_capacitor_core",
		"slot": 3,
		"title": "Ядро конденсатора",
		"desc":
		"Лимит Статического заряда повышен до 9, а Разряд статики возвращает половину перезарядки при 6+ потраченных стаках",
		"rarity": "unique",
		"transform": "storm_capacitor_core"
	},
]

const CLASS_SLOT_NAMES := {
	"mage": ["Огненная стена", "Ледяная стрела", "Цепная молния", "Метеор"],
	"barbarian": ["Вихрь", "Прыжок-удар", "Боевой клич", "Землетрясение"],
	"rogue": ["Шипы", "Дымовая бомба", "Склянка яда", "Веер ножей"],
	"druid": ["Облик волка", "Облик медведя", "Каменная броня", "Призыв духа", "Облик орла"],
	"necromancer": ["Поднять скелета", "Поднять рыцаря", "Кровавый договор", "Пульс смерти"],
	"hexen": ["Метка проклятия", "Кровавый хлыст", "Узы души", "Багровый ритуал"],
	"stormcaller": ["Цепной разряд", "Грозовой шаг", "Небесный удар", "Разряд статики"],
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
		return "Неизвестно"
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
