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
			"name": "Боевой маг",
			"role": "warrior",
			"desc": "Ближний бой клинком маны. Базовая атака становится огненным мечом; R: Чародейский пламеклинок усиливает ближний бой на 20 с.",
			"ability": "arcane_flameblade",
			"basic_attack": "melee",
			"transforms": {0: "flame_cleave", 1: "frost_guard", 3: "falling_brand"},
			"passive": "battlemage_stacks",
			"stats": {"max_hp": 60, "move_speed": 30.0, "damage": 4},
		},
		{
			"id": "elementalist",
			"name": "Элементалист",
			"role": "caster",
			"desc": "Комбо-артиллерия. Навыки создают стихийные сферы; R: Орбита стихий выпускает их (3 стихии = Призматический взрыв).",
			"ability": "elemental_orbit",
			"transforms": {},
			"passive": "tri_element_fracture",
			"stats": {"damage": 10, "max_mana": 40, "crit_chance": 0.04},
		},
		{
			"id": "chronomancer",
			"name": "Хрономант",
			"role": "support",
			"desc": "Власть над временем. R: Купол времени — замедляет врагов и усиливает союзников в поле на 8 с.",
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
			"name": "Берсерк",
			"role": "warrior",
			"desc": "Ярость стеклянной пушки. R: Кровавое неистовство — быстрее, с вампиризмом, но уязвимее. Машина боли: чем меньше здоровья, тем сильнее удары.",
			"ability": "barb_blood_frenzy",
			"transforms": {0: "barb_bloodstorm", 1: "barb_skullcrack_leap", 2: "barb_rage_howl"},
			"passive": "pain_engine",
			"stats": {"damage": 8, "move_speed": 20.0, "crit_damage": 0.3},
		},
		{
			"id": "warchief",
			"name": "Вождь",
			"role": "support",
			"desc": "Командир передовой. R: Знамя предков — усиливает союзников, провоцирует врагов. Держать строй: защищает союзников рядом.",
			"ability": "barb_banner",
			"transforms": {1: "barb_guardian_leap", 2: "barb_commanding_shout", 3: "barb_war_ground"},
			"passive": "hold_the_line",
			"stats": {"max_hp": 80, "max_mana": 30},
		},
		{
			"id": "titanbreaker",
			"name": "Крушитель титанов",
			"role": "caster",
			"desc": "Ваятель земли. R: Раскол мира — трещина, извергающаяся дважды. Сейсмический разгон: контроль копится в более мощные толчки.",
			"ability": "barb_worldsplitter",
			"transforms": {0: "barb_stone_grinder", 2: "barb_tremor_roar", 3: "barb_fault_zone"},
			"passive": "seismic_momentum",
			"stats": {"max_hp": 40, "damage": 6, "max_mana": 30},
		},
	],
	"rogue":
	[
		{
			"id": "assassin",
			"name": "Ассасин",
			"role": "warrior",
			"desc": "Уничтожение одиночных целей. R: Рывок смертной метки проносит сквозь цель и казнит ослабленных. Окно для удара в спину после рывков и Исчезновения.",
			"ability": "rogue_deathmark_dash",
			"transforms": {0: "rogue_razor_trap", 1: "rogue_vanish", 3: "rogue_execution_fan"},
			"passive": "backstab_window",
			"stats": {"damage": 8, "crit_chance": 0.05, "crit_damage": 0.3},
		},
		{
			"id": "trickster",
			"name": "Ловкач",
			"role": "support",
			"desc": "Иллюзии и побеги. R: Мираж-приманка провоцирует и взрывается, ослепляя врагов и прикрывая союзников. Грязный побег обманывает смерть.",
			"ability": "rogue_decoy_mirage",
			"transforms": {0: "rogue_trick_field", 1: "rogue_safehouse", 2: "rogue_confusion_flask"},
			"passive": "dirty_escape",
			"stats": {"max_hp": 50, "max_mana": 30, "move_speed": 20.0},
		},
		{
			"id": "venomancer",
			"name": "Отравитель",
			"role": "caster",
			"desc": "Накапливающийся яд. R: Чумной цвет заражает зону, расползающуюся с убийствами. Токсичные стаки на 10 мутируют в Некротические.",
			"ability": "rogue_plague_bloom",
			"transforms": {0: "rogue_toxic_spikes", 2: "rogue_triple_flask", 3: "rogue_venom_fan"},
			"passive": "toxic_stacking",
			"stats": {"damage": 6, "max_mana": 50, "crit_chance": 0.03},
		},
	],
	"stormcaller":
	[
		{
			"id": "thunderblade",
			"name": "Громовой клинок",
			"role": "warrior",
			"desc": "Дуэлянт молний. R: Грозовой форсаж усиливает вас, а затем взрывается. Короткое замыкание: чем ближе бой, тем выше урон.",
			"ability": "storm_lightning_overdrive",
			"transforms": {0: "storm_charged_slash", 1: "storm_thunder_lunge", 3: "storm_body_discharge"},
			"passive": "close_circuit",
			"stats": {"damage": 7, "move_speed": 25.0, "crit_chance": 0.04},
		},
		{
			"id": "tempest_lord",
			"name": "Повелитель бури",
			"role": "caster",
			"desc": "Истинный маг бури. R: Око бури обрушивает молнии на зону. Каскад статики цепляется от гибнущих наэлектризованных врагов.",
			"ability": "storm_eye_of_storm",
			"transforms": {0: "storm_forked_bolt", 2: "storm_pillar", 3: "storm_controlled_discharge"},
			"passive": "static_cascade",
			"stats": {"damage": 8, "max_mana": 50, "crit_chance": 0.03},
		},
		{
			"id": "conductor",
			"name": "Проводник",
			"role": "support",
			"desc": "Батарея отряда. R: Живая батарея ускоряет союзников и питает вас. Проводящая командная игра пускает цепи, когда союзники бьют наэлектризованных врагов.",
			"ability": "storm_living_battery",
			"transforms": {0: "storm_ally_arc", 1: "storm_rescue_step", 3: "storm_energizing_discharge"},
			"passive": "conductive_teamwork",
			"stats": {"max_hp": 50, "max_mana": 40, "move_speed": 15.0},
		},
	],
	"hexen":
	[
		{
			"id": "blood_witch",
			"name": "Кровавая ведьма",
			"role": "warrior",
			"desc": "Кровавый ближний бой ценой собственной крови. R: Алая одержимость усиливает хлыст. Дивиденд боли обращает самоистязание во взрывной урон.",
			"ability": "hexen_scarlet_possession",
			"transforms": {0: "hexen_open_wound", 1: "hexen_blood_scythe", 3: "hexen_blood_arena"},
			"passive": "pain_dividend",
			"stats": {"damage": 8, "max_hp": 40, "crit_damage": 0.25},
		},
		{
			"id": "curseweaver",
			"name": "Ткачиха проклятий",
			"role": "caster",
			"desc": "Комбо проклятий. R: Великое злословие проклинает всю область и подрывает метки. Тройное проклятие взрывается при стопке дебаффов.",
			"ability": "hexen_grand_malediction",
			"transforms": {0: "hexen_rotating_hex", 2: "hexen_curse_chain", 3: "hexen_ritual_of_doom"},
			"passive": "threefold_curse",
			"stats": {"damage": 9, "max_mana": 50, "crit_chance": 0.03},
		},
		{
			"id": "coven_mother",
			"name": "Мать ковена",
			"role": "support",
			"desc": "Поддержка кровавых уз. R: Договор ковена делит урон между союзниками. Общий грех даёт ману и щиты, когда союзники бьют по меткам.",
			"ability": "hexen_coven_pact",
			"transforms": {1: "hexen_binding_whip", 2: "hexen_ally_tether", 3: "hexen_safe_ritual"},
			"passive": "shared_sin",
			"stats": {"max_hp": 50, "max_mana": 50, "move_speed": 10.0},
		},
	],
	"necromancer":
	[
		{
			"id": "deathlord",
			"name": "Лорд смерти",
			"role": "warrior",
			"desc": "Командир передовой. R: Корона мёртвых усиливает всё ваше воинство. Метка командира направляет приспешников на вашу цель.",
			"ability": "necro_crown_of_dead",
			"transforms": {0: "necro_skeletal_legion", 1: "necro_grave_champion", 3: "necro_rally_pulse"},
			"passive": "commanders_mark",
			"stats": {"max_hp": 50, "damage": 6, "move_speed": 15.0},
		},
		{
			"id": "bone_architect",
			"name": "Костяной зодчий",
			"role": "caster",
			"desc": "Костяные конструкции. R: Костяная цитадель возводит стреляющую крепость. Кости из смерти копят осколки для усиленных навыков.",
			"ability": "necro_bone_citadel",
			"transforms": {0: "necro_bone_turret", 1: "necro_bone_golem", 3: "necro_bone_nova"},
			"passive": "bones_from_death",
			"stats": {"damage": 9, "max_mana": 50, "crit_chance": 0.03},
		},
		{
			"id": "gravebinder",
			"name": "Могильный вязатель",
			"role": "support",
			"desc": "Поддержка на грани жизни и смерти. R: Вторые похороны ненадолго делают отряд неубиваемым. Общая могила переносит урон союзников на приспешников.",
			"ability": "necro_second_funeral",
			"transforms": {1: "necro_oathbound_knight", 2: "necro_blood_ward", 3: "necro_mending_pulse"},
			"passive": "shared_grave",
			"stats": {"max_hp": 60, "max_mana": 40},
		},
	],
	"druid":
	[
		{
			"id": "primal_alpha",
			"name": "Первобытный альфа",
			"role": "warrior",
			"desc": "Верховный оборотень. R: Облик хищника — гибридный всплеск силы. Шкура зверя и Дух стаи укрепляют ваши облики.",
			"ability": "druid_apex_form",
			"transforms": {2: "druid_hide_of_beast", 3: "druid_pack_spirit"},
			"passive": "predator_rhythm",
			"stats": {"max_hp": 50, "damage": 6, "move_speed": 20.0},
		},
		{
			"id": "grovekeeper",
			"name": "Хранитель рощи",
			"role": "support",
			"desc": "Страж-защитник. R: Живая роща лечит и прикрывает союзников, опутывая врагов корнями. Аура коры и Дух-хранитель оберегают отряд.",
			"ability": "druid_living_grove",
			"transforms": {2: "druid_barkskin_aura", 3: "druid_guardian_spirit"},
			"passive": "rootbound_spirits",
			"stats": {"max_hp": 60, "max_mana": 40},
		},
		{
			"id": "stormshaper",
			"name": "Ваятель бурь",
			"role": "caster",
			"desc": "Буря самой природы. R: Единение с бурей поднимает шторм вокруг вас. Земляной пульс и Грозовой тотем добавляют стихийной мощи.",
			"ability": "druid_tempest_communion",
			"transforms": {2: "druid_earthen_pulse", 3: "druid_storm_totem"},
			"passive": "form_casting",
			"stats": {"damage": 8, "max_mana": 50, "crit_chance": 0.03},
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
