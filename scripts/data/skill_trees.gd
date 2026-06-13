class_name SkillTrees
extends RefCounted

# Дерево умений — НАСТОЯЩИЙ граф (а не список). На класс — плоский набор узлов с
# координатами (col,row) и рёбрами (parents) к узлам сверху. Сверху корни-навыки
# (4, у друида 5), вниз ветвятся пассивки и варианты-подмены; ветки переплетают
# ОБЩИЕ узлы (один узел качает характеристику у двух навыков).
#
# Узел:
#   id, kind: "skill"|"passive"|"variant"|"perk", col, row, parents:[id,...]
#   • skill  — КОРЕНЬ слота (всегда кастуется; ранг → +урон/−кд, пол 0.5с;
#              применяет SkillSystem). Поля slot, skill_id; id == skill_id.
#   • passive— targets:[{slot, modifier}] (1 цель обычно; 2+ = ОБЩИЙ узел).
#              id == modifier_id для одиночных (set-граны это используют).
#   • variant— подмена слота (radio, стоит VARIANT_COST). slot, transform,
#              опц. base_skill (формы друида), опц. requires_path (вознесение).
#   • perk   — спец (berserker_grip).
#
# Гейтинг ПО РЁБРАМ: узел открыт, если у хотя бы одного parent ранг ≥ 1; корни
# (parents пусто) открыты всегда. Состояние выбора — GameManager.tree_nodes.
# Карты подмен SkillCatalog СТРОИТ из all_variant_bindings (единый источник).

# Канонический список классов — GameManager.class_ids() (порядок UI-пикеров).

# Стоимость замены навыка (вариант) в очках; ранг навыка/пассивка/стат/ult — 1.
const VARIANT_COST := 2
# +N к стату за купленный ранг стат-узла (общий пул очков).
const STAT_PER_RANK := 2

# Колонка статов слева в панели (без гейтинга, общий пул).
const STAT_NODES := [
	{"id": "stat_strength", "stat": "strength", "name": "Сила"},
	{"id": "stat_dexterity", "stat": "dexterity", "name": "Ловкость"},
	{"id": "stat_intelligence", "stat": "intelligence", "name": "Интеллект"},
]

# Стихия on-hit статус-узлов по классу — ClassDefinition.on_hit_element.
const _ONHIT_LABEL := {
	"fire": ["Поджог", "Навык поджигает врагов при попадании (горение)."],
	"bleed": ["Кровоток", "Навык вызывает кровотечение при попадании."],
	"frost": ["Обморожение", "Навык морозит врагов при попадании (холод)."],
	"poison": ["Отравление", "Навык отравляет врагов при попадании (яд)."],
	"curse": ["Порча", "Навык накладывает стак проклятия при попадании."],
}
# Вертикальная раскладка: число лейнов (навыки складываются стопкой вниз → силуэт
# вытянут вертикально, как на скрине WoW), шаг между лейнами и высота блока навыка.
const _VLANES := {"druid": 3}
const _LANE_W := 4
const _BLOCK_H := 8

# Классы с ручной раскладкой графа (координаты/рёбра авторские, без авто-
# выпрямления). По мере доводки сюда добавляются классы.
const _HAND_AUTHORED := {
	"mage": true,
	"barbarian": true,
	"rogue": true,
	"stormcaller": true,
	"hexen": true,
	"necromancer": true,
	"druid": true,
}


# ── Конструкторы узлов ───────────────────────────────────────────────────────
static func _skill(slot: int, skill_id: String, name: String, col: int) -> Dictionary:
	return {
		"id": skill_id,
		"kind": "skill",
		"slot": slot,
		"skill_id": skill_id,
		"name": name,
		"col": col,
		"row": 0,
		"parents": [],
		"max_ranks": -1,
	}


# Пассивка (имя/описание из RewardData по modifier). targets — одна цель.
static func _passive(
	slot: int, modifier_id: String, col: int, row: int, parents: Array
) -> Dictionary:
	return {
		"id": modifier_id,
		"kind": "passive",
		"targets": [{"slot": slot, "modifier": modifier_id}],
		"col": col,
		"row": row,
		"parents": parents,
		"max_ranks": -1,
	}


# Общий переплетающий узел — кладёт несколько модификаторов в разные слоты.
static func _shared(
	id: String, name: String, desc: String, targets: Array, col: int, row: int, parents: Array
) -> Dictionary:
	return {
		"id": id,
		"kind": "passive",
		"name": name,
		"desc": desc,
		"targets": targets,
		"col": col,
		"row": row,
		"parents": parents,
		"max_ranks": -1,
	}


static func _variant(
	slot: int, transform: String, name: String, desc: String, col: int, row: int, parents: Array
) -> Dictionary:
	return {
		"id": transform,
		"kind": "variant",
		"slot": slot,
		"transform": transform,
		"name": name,
		"desc": desc,
		"col": col,
		"row": row,
		"parents": parents,
		"max_ranks": 1,
	}


static func _variant_base(
	slot: int,
	transform: String,
	base_skill: String,
	name: String,
	desc: String,
	col: int,
	row: int,
	parents: Array
) -> Dictionary:
	var n := _variant(slot, transform, name, desc, col, row, parents)
	n["base_skill"] = base_skill
	return n


static func _avariant(
	slot: int,
	transform: String,
	path_id: String,
	name: String,
	desc: String,
	col: int,
	row: int,
	parents: Array
) -> Dictionary:
	var n := _variant(slot, transform, name, desc, col, row, parents)
	n["requires_path"] = path_id
	return n


static func _perk(
	id: String, name: String, desc: String, slot: int, col: int, row: int, parents: Array
) -> Dictionary:
	return {
		"id": id,
		"kind": "perk",
		"slot": slot,
		"name": name,
		"desc": desc,
		"col": col,
		"row": row,
		"parents": parents,
		"max_ranks": 1,
	}


# Пассивка снижения кд: модификатор id оканчивается на "_cdr" (SkillSystem читает
# генерически, −5%/ранг, пол 0.5с). Инлайн имя/описание (нет в RewardData).
static func _cdr(
	slot: int, cdr_id: String, name: String, desc: String, col: int, row: int, parents: Array
) -> Dictionary:
	return {
		"id": cdr_id,
		"kind": "passive",
		"name": name,
		"desc": desc,
		"targets": [{"slot": slot, "modifier": cdr_id}],
		"col": col,
		"row": row,
		"parents": parents,
		"max_ranks": -1,
	}


# Пассивка урона с инлайн-именем: модификатор id оканчивается на "_damage"
# (try_cast читает генерически, +30%/стак). Для авторских «доп. урон» узлов, которых
# нет в RewardData (в отличие от _passive, который тянет имя из RewardData).
static func _dmg(
	slot: int, dmg_id: String, name: String, desc: String, col: int, row: int, parents: Array
) -> Dictionary:
	return {
		"id": dmg_id,
		"kind": "passive",
		"name": name,
		"desc": desc,
		"targets": [{"slot": slot, "modifier": dmg_id}],
		"col": col,
		"row": row,
		"parents": parents,
		"max_ranks": -1,
	}


# Статус-узел: навык начинает накладывать стихию при попадании (on_hit).
static func _onhit(
	slot: int,
	id: String,
	element: String,
	name: String,
	desc: String,
	col: int,
	row: int,
	parents: Array
) -> Dictionary:
	return {
		"id": id,
		"kind": "passive",
		"slot": slot,
		"on_hit": element,
		"name": name,
		"desc": desc,
		"col": col,
		"row": row,
		"parents": parents,
		"max_ranks": 1,
	}


# Помечает узел как часть взаимоисключающей развилки: взяв один узел группы,
# остальные той же группы блокируются (см. GameManager.node_block_reason).
static func _excl(node: Dictionary, group: String) -> Dictionary:
	node["exclusive"] = group
	return node


# Финальный граф: для «ручных» классов — авторские координаты как есть; иначе
# авто-углубление (+кд/+статус) + вертикальная раскладка стопкой.
static func nodes_for(cls: String) -> Array:
	if _HAND_AUTHORED.has(cls):
		return _base_nodes(cls)
	return _verticalize(_augment(_base_nodes(cls), cls), cls)


# Взят ли какой-то узел взаимоисключающей группы (кроме самого узла).
static func exclusive_group_taken(
	cls: String, group: String, except_id: String, tree_nodes: Dictionary
) -> bool:
	if group == "":
		return false
	for n in nodes_for(cls):
		if String(n.get("exclusive", "")) != group:
			continue
		if String(n["id"]) == except_id:
			continue
		if int(tree_nodes.get(String(n["id"]), 0)) > 0:
			return true
	return false


static func _root_id_for_slot_in(nodes: Array, slot: int) -> String:
	for n in nodes:
		if String(n.get("kind", "")) == "skill" and int(n["slot"]) == slot:
			return String(n["id"])
	return ""


# Пересчитывает col/row/parents так, чтобы каждый навык стал вертикальной цепочкой
# (корень сверху, пассивки/варианты/кд/статус вниз), а навыки складывались в
# несколько лейнов стопкой → силуэт вытянут вертикально. Узлы — свежие словари на
# каждый вызов nodes_for, так что их можно мутировать.
static func _verticalize(nodes: Array, cls: String) -> Array:
	var lanes: int = int(_VLANES.get(cls, 2))
	var roots: Array = []
	for n in nodes:
		if String(n.get("kind", "")) == "skill":
			roots.append(n)
	roots.sort_custom(func(a, b): return int(a["col"]) < int(b["col"]))
	var per_lane: int = int(ceil(float(roots.size()) / float(lanes)))
	per_lane = maxi(1, per_lane)
	var base_col: Dictionary = {}
	var base_row: Dictionary = {}
	for i in roots.size():
		var r: Dictionary = roots[i]
		var lane: int = i / per_lane
		var pos: int = i % per_lane
		var c: int = lane * _LANE_W + 1
		var rr: int = pos * _BLOCK_H
		r["col"] = c
		r["row"] = rr
		r["parents"] = []
		base_col[int(r["slot"])] = c
		base_row[int(r["slot"])] = rr

	for s in base_col:
		var center: int = int(base_col[s])
		var top: int = int(base_row[s])
		var passives: Array = []
		var variants: Array = []
		for n in nodes:
			if String(n.get("kind", "")) == "skill" or _node_slot_of(n) != int(s):
				continue
			if String(n["kind"]) == "variant":
				variants.append(n)
			else:
				passives.append(n)
		# Пассивки/кд/статус — центральная цепочка вниз.
		var prev_id: String = _root_id_for_slot_in(nodes, int(s))
		var row_center: Dictionary = {}
		var rr2: int = top + 1
		for p in passives:
			p["col"] = center
			p["row"] = rr2
			p["parents"] = [prev_id]
			row_center[rr2] = String(p["id"])
			prev_id = String(p["id"])
			rr2 += 1
		var last_row: int = maxi(top + 1, rr2 - 1)
		# Варианты — сбоку от цепочки, по одному на ряд (чередуя стороны).
		var idx: int = 0
		for v in variants:
			var vr: int = mini(top + 1 + idx, last_row)
			v["row"] = vr
			v["col"] = center + (1 if idx % 2 == 0 else -1)
			v["parents"] = [String(row_center.get(vr, _root_id_for_slot_in(nodes, int(s))))]
			idx += 1

	# Общие узлы (slot -1, 2+ целей) — между лейнами целевых навыков.
	for n in nodes:
		if String(n.get("kind", "")) == "skill" or _node_slot_of(n) != -1:
			continue
		var cols: Array = []
		var first_slot: int = -1
		for t in n.get("targets", []):
			if base_col.has(int(t["slot"])):
				cols.append(int(base_col[int(t["slot"])]))
				if first_slot < 0:
					first_slot = int(t["slot"])
		if cols.is_empty():
			continue
		var sum_c: int = 0
		for c2 in cols:
			sum_c += c2
		n["col"] = int(round(float(sum_c) / float(cols.size())))
		n["row"] = int(base_row.get(first_slot, 0)) + 3
	return nodes


# Слот, к которому относится узел (-1 для общих узлов с несколькими целями).
static func _node_slot_of(n: Dictionary) -> int:
	if n.has("slot"):
		return int(n["slot"])
	if String(n.get("kind", "")) == "passive":
		var t: Array = n.get("targets", [])
		if t.size() == 1:
			return int(t[0]["slot"])
	return -1


# Дотягивает каждую колонку-навык вниз: добавляет узел снижения кд и статус-узел
# (если их ещё нет), углубляя дерево на 2 ряда. Координаты можно править вручную.
static func _augment(base: Array, cls: String) -> Array:
	var out: Array = base.duplicate()
	var has_onhit: Dictionary = {}
	var has_cdr: Dictionary = {}
	for n in base:
		if String(n.get("on_hit", "")) != "":
			has_onhit[_node_slot_of(n)] = true
		if String(n["id"]).ends_with("_cdr"):
			has_cdr[_node_slot_of(n)] = true
	# on-hit status element per class (folded into ClassDefinition.on_hit_element).
	var element: String = GameManager.class_def(cls).on_hit_element
	if element == "":
		element = "bleed"
	var lbl: Array = _ONHIT_LABEL.get(element, ["Эффект", "Накладывает эффект."])
	for n in base:
		if String(n.get("kind", "")) != "skill":
			continue
		var slot: int = int(n["slot"])
		var col: int = int(n["col"])
		var sid: String = String(n["skill_id"])
		var sname: String = String(n.get("name", sid))
		var maxrow: int = 0
		var parent_id: String = sid
		for m in base:
			if _node_slot_of(m) != slot:
				continue
			maxrow = maxi(maxrow, int(m["row"]))
			if String(m.get("kind", "")) == "passive":
				parent_id = String(m["id"])
		var row: int = maxrow + 1
		if not has_cdr.has(slot):
			var cdr_id: String = sid + "_cdr"
			out.append(
				_cdr(
					slot,
					cdr_id,
					"Скорость: " + sname,
					"−5% перезарядки за ранг.",
					col,
					row,
					[parent_id]
				)
			)
			parent_id = cdr_id
			row += 1
		if not has_onhit.has(slot):
			out.append(
				_onhit(
					slot,
					sid + "_onhit",
					element,
					String(lbl[0]),
					String(lbl[1]),
					col,
					row,
					[parent_id]
				)
			)
	return out


# ── Граф по классам (плоский список узлов) ───────────────────────────────────
static func _base_nodes(cls: String) -> Array:
	match cls:
		"mage":
			return _mage_nodes()
		"barbarian":
			return _barbarian_nodes()
		"rogue":
			return _rogue_nodes()
		"stormcaller":
			return _stormcaller_nodes()
		"hexen":
			return _hexen_nodes()
		"necromancer":
			return _necromancer_nodes()
		"druid":
			return _druid_nodes()
	return []


static func _mage_nodes() -> Array:
	# Ручная раскладка-ОБРАЗЕЦ: СЕТКА (как на скрине WoW). 4 навыка ГОРИЗОНТАЛЬНО
	# сверху как точки входа (центры col 1/5/9/13), вниз — 7 рядов разных
	# пассивок: ряд1 ВИЛКА (2 пассивки), ряд2 РОМБ, ряд3 ВАРИАНТЫ-замены (радио,
	# одна из), ряд4 ещё пассивки, ряд5 РОМБ, ряд6 СТАТУС-РАЗВИЛКА (одна из, по
	# навыку, взаимоисключающая). Соседние навыки сшиты перемычками (col 3/7/11,
	# ряды 2 и 5) — рёбра пересекаются. Координаты/числа — правь здесь.
	return [
		# ── Огненная стена (slot0, центр col1) ──
		_skill(0, "fire_wall", "Огненная стена", 1),
		_passive(0, "fw_radius", 0, 1, ["fire_wall"]),
		_passive(0, "fw_damage", 2, 1, ["fire_wall"]),
		_passive(0, "fw_duration", 1, 2, ["fw_radius", "fw_damage"]),  # ромб
		_variant(
			0,
			"flame_cleave",
			"Огненный разруб",
			"Широкий огненный взмах вблизи.",
			0,
			3,
			["fw_duration"]
		),
		_variant(
			0,
			"ice_wall",
			"Стена льда",
			"Стена замораживает и преграждает путь.",
			1,
			3,
			["fw_duration"]
		),
		_variant(
			0,
			"time_wall",
			"Стена времени",
			"Враги медленнее, союзники быстрее.",
			2,
			3,
			["fw_duration"]
		),
		_cdr(
			0,
			"fw_cdr",
			"Беглое пламя",
			"−5% перезарядки Огненной стены за ранг.",
			0,
			4,
			["fw_duration"]
		),
		_dmg(
			0,
			"fw_ember_damage",
			"Тлеющие угли",
			"+урон Огненной стены за ранг.",
			2,
			4,
			["fw_duration"]
		),
		_dmg(
			0,
			"fw_inferno_damage",
			"Инферно",
			"+урон Огненной стены за ранг.",
			1,
			5,
			["fw_cdr", "fw_ember_damage"]
		),  # ромб
		_excl(
			_onhit(
				0,
				"fw_status_fire",
				"fire",
				"Поджог",
				"Огненная стена поджигает врагов (горение).",
				0,
				6,
				["fw_inferno_damage"]
			),
			"mage_status_fw"
		),
		_excl(
			_onhit(
				0,
				"fw_status_curse",
				"curse",
				"Порча",
				"Огненная стена проклинает задетых врагов.",
				2,
				6,
				["fw_inferno_damage"]
			),
			"mage_status_fw"
		),
		# ── Ледяная стрела (slot1, центр col5) ──
		_skill(1, "ice_bolt", "Ледяная стрела", 5),
		_passive(1, "ib_slow", 4, 1, ["ice_bolt"]),
		_passive(1, "ib_damage", 6, 1, ["ice_bolt"]),
		_cdr(
			1,
			"ib_cdr",
			"Беглый мороз",
			"−5% перезарядки Ледяной стрелы за ранг.",
			5,
			2,
			["ib_slow", "ib_damage"]
		),  # ромб
		_variant(
			1,
			"frost_nova",
			"Морозная нова",
			"Круговой морозный взрыв вокруг вас.",
			4,
			3,
			["ib_cdr"]
		),
		_variant(
			1,
			"frost_guard",
			"Ледяная стража",
			"Щит поглощает удар и взрывается новой.",
			6,
			3,
			["ib_cdr"]
		),
		_passive(1, "ib_pierce", 4, 4, ["ib_cdr"]),
		_dmg(
			1,
			"ib_shard_damage",
			"Ледяные осколки",
			"+урон Ледяной стрелы за ранг.",
			6,
			4,
			["ib_cdr"]
		),
		_dmg(
			1,
			"ib_glacier_damage",
			"Ледник",
			"+урон Ледяной стрелы за ранг.",
			5,
			5,
			["ib_pierce", "ib_shard_damage"]
		),  # ромб
		_excl(
			_onhit(
				1,
				"ib_status_frost",
				"frost",
				"Обморожение",
				"Ледяная стрела морозит врагов (холод).",
				4,
				6,
				["ib_glacier_damage"]
			),
			"mage_status_ib"
		),
		_excl(
			_onhit(
				1,
				"ib_status_bleed",
				"bleed",
				"Кровоток",
				"Ледяные осколки вызывают кровотечение.",
				6,
				6,
				["ib_glacier_damage"]
			),
			"mage_status_ib"
		),
		# ── Цепная молния (slot2, центр col9) ──
		_skill(2, "chain_lightning", "Цепная молния", 9),
		_passive(2, "cl_damage", 8, 1, ["chain_lightning"]),
		_passive(2, "cl_jumps", 10, 1, ["chain_lightning"]),
		_cdr(
			2,
			"cl_cdr",
			"Беглая дуга",
			"−5% перезарядки Цепной молнии за ранг.",
			9,
			2,
			["cl_damage", "cl_jumps"]
		),  # ромб
		_variant(
			2,
			"death_beam",
			"Луч смерти",
			"Сфокусированный луч, прожигающий линию.",
			8,
			3,
			["cl_cdr"]
		),
		_variant(
			2,
			"time_link",
			"Связь времени",
			"Цепь по союзникам (щит) и врагам.",
			10,
			3,
			["cl_cdr"]
		),
		_dmg(
			2,
			"cl_surge_damage",
			"Перегрузка",
			"+урон Цепной молнии за ранг.",
			8,
			4,
			["cl_cdr"]
		),
		_dmg(
			2,
			"cl_arc_damage",
			"Дуговой разряд",
			"+урон Цепной молнии за ранг.",
			10,
			4,
			["cl_cdr"]
		),
		_dmg(
			2,
			"cl_storm_damage",
			"Шторм",
			"+урон Цепной молнии за ранг.",
			9,
			5,
			["cl_surge_damage", "cl_arc_damage"]
		),  # ромб
		_excl(
			_onhit(
				2,
				"cl_status_slow",
				"frost",
				"Замедление",
				"Молния замедляет задетых врагов.",
				8,
				6,
				["cl_storm_damage"]
			),
			"mage_status_cl"
		),
		_excl(
			_onhit(
				2,
				"cl_status_curse",
				"curse",
				"Порча",
				"Молния проклинает задетых врагов.",
				10,
				6,
				["cl_storm_damage"]
			),
			"mage_status_cl"
		),
		# ── Метеор (slot3, центр col13) ──
		_skill(3, "meteor", "Метеор", 13),
		_passive(3, "mt_damage", 12, 1, ["meteor"]),
		_passive(3, "mt_radius", 14, 1, ["meteor"]),
		_cdr(
			3,
			"mt_cdr",
			"Беглый зенит",
			"−5% перезарядки Метеора за ранг.",
			13,
			2,
			["mt_damage", "mt_radius"]
		),  # ромб
		_variant(
			3,
			"falling_brand",
			"Падающее клеймо",
			"Мгновенный малый метеор перед собой.",
			12,
			3,
			["mt_cdr"]
		),
		_variant(
			3,
			"stasis_star",
			"Звезда стазиса",
			"Урон и заморозка врагам, щит союзникам.",
			13,
			3,
			["mt_cdr"]
		),
		_variant(
			3,
			"meteor_shower",
			"Метеоритный дождь",
			"Дождь из нескольких метеоров поменьше.",
			14,
			3,
			["mt_cdr"]
		),
		_dmg(3, "mt_impact_damage", "Удар", "+урон Метеора за ранг.", 12, 4, ["mt_cdr"]),
		_dmg(
			3,
			"mt_fall_damage",
			"Тяжёлое падение",
			"+урон Метеора за ранг.",
			14,
			4,
			["mt_cdr"]
		),
		_dmg(
			3,
			"mt_molten_damage",
			"Расплав",
			"+урон Метеора за ранг.",
			13,
			5,
			["mt_impact_damage", "mt_fall_damage"]
		),  # ромб
		_excl(
			_onhit(
				3,
				"mt_status_fire",
				"fire",
				"Пепелище",
				"Метеор поджигает зону попадания.",
				12,
				6,
				["mt_molten_damage"]
			),
			"mage_status_mt"
		),
		_excl(
			_onhit(
				3,
				"mt_status_frost",
				"frost",
				"Стужа",
				"Метеор морозит врагов в зоне удара.",
				14,
				6,
				["mt_molten_damage"]
			),
			"mage_status_mt"
		),
		# ── Перемычки между соседними навыками (ряды 2 и 5, рёбра пересекаются) ──
		_shared(
			"mage_weave_fw_ib",
			"Стихийный фокус",
			"+урон Огненной стены и Ледяной стрелы.",
			[{"slot": 0, "modifier": "fw_damage"}, {"slot": 1, "modifier": "ib_damage"}],
			3,
			2,
			["fw_damage", "ib_slow"]
		),
		_shared(
			"mage_weave_ib_cl",
			"Морозный разряд",
			"+урон Ледяной стрелы и Цепной молнии.",
			[{"slot": 1, "modifier": "ib_damage"}, {"slot": 2, "modifier": "cl_damage"}],
			7,
			2,
			["ib_damage", "cl_damage"]
		),
		_shared(
			"mage_weave_cl_mt",
			"Грозовой удар",
			"+урон Цепной молнии и Метеора.",
			[{"slot": 2, "modifier": "cl_damage"}, {"slot": 3, "modifier": "mt_damage"}],
			11,
			2,
			["cl_jumps", "mt_damage"]
		),
		_shared(
			"mage_weave_fw_ib2",
			"Двойной резонанс",
			"+урон Огненной стены и Ледяной стрелы.",
			[{"slot": 0, "modifier": "fw_damage"}, {"slot": 1, "modifier": "ib_damage"}],
			3,
			5,
			["fw_ember_damage", "ib_pierce"]
		),
		_shared(
			"mage_weave_ib_cl2",
			"Ледогром",
			"+урон Ледяной стрелы и Цепной молнии.",
			[{"slot": 1, "modifier": "ib_damage"}, {"slot": 2, "modifier": "cl_damage"}],
			7,
			5,
			["ib_shard_damage", "cl_surge_damage"]
		),
		_shared(
			"mage_weave_cl_mt2",
			"Расплавленная буря",
			"+урон Цепной молнии и Метеора.",
			[{"slot": 2, "modifier": "cl_damage"}, {"slot": 3, "modifier": "mt_damage"}],
			11,
			5,
			["cl_arc_damage", "mt_impact_damage"]
		),
	]


static func _barbarian_nodes() -> Array:
	# Грид: 4 корня горизонтально (центры col 2/7/12/17), 7 рядов. Урон-навыки
	# (Вихрь/Прыжок/Землетрясение) — статус-развилка (кровоток) на ряду 6; Боевой
	# клич (бафф) — power/haste-капстоун. Все варианты+вознесения на ряду 3 (радио).
	return [
		# ── Вихрь (slot0, центр col2) ──
		_skill(0, "whirlwind", "Вихрь", 2),
		_passive(0, "barb_whirl_damage", 1, 1, ["whirlwind"]),
		_cdr(
			0,
			"barb_whirl_cdr",
			"Размах",
			"−5% перезарядки Вихря за ранг.",
			3,
			1,
			["whirlwind"]
		),
		_dmg(
			0,
			"barb_whirl_power_damage",
			"Натиск",
			"+урон Вихря за ранг.",
			2,
			2,
			["barb_whirl_damage", "barb_whirl_cdr"]
		),
		_variant(
			0,
			"barb_cleave",
			"Разрез",
			"Широкий рубящий удар перед собой.",
			0,
			3,
			["barb_whirl_power_damage"]
		),
		_avariant(
			0,
			"barb_bloodstorm",
			"berserker",
			"Кровавый шторм",
			"Враги кровоточат, удары по ним сильнее.",
			1,
			3,
			["barb_whirl_power_damage"]
		),
		_variant(
			0,
			"barb_sword_throw",
			"Метание меча",
			"Метает клинок, пронзающий врагов.",
			3,
			3,
			["barb_whirl_power_damage"]
		),
		_avariant(
			0,
			"barb_stone_grinder",
			"titanbreaker",
			"Каменные жернова",
			"Затягивает лёгких врагов, перемалывая их.",
			4,
			3,
			["barb_whirl_power_damage"]
		),
		_dmg(
			0,
			"barb_whirl_rend_damage",
			"Рассечение",
			"+урон Вихря за ранг.",
			1,
			4,
			["barb_whirl_power_damage"]
		),
		_cdr(
			0,
			"barb_whirl_flow_cdr",
			"Поток",
			"−5% перезарядки Вихря за ранг.",
			3,
			4,
			["barb_whirl_power_damage"]
		),
		_dmg(
			0,
			"barb_whirl_storm_damage",
			"Буря клинков",
			"+урон Вихря за ранг.",
			2,
			5,
			["barb_whirl_rend_damage", "barb_whirl_flow_cdr"]
		),
		_excl(
			_onhit(
				0,
				"barb_whirl_status_bleed",
				"bleed",
				"Кровоток",
				"Вихрь рассекает врагов в кровь.",
				1,
				6,
				["barb_whirl_storm_damage"]
			),
			"barb_cap_0"
		),
		_excl(
			_cdr(
				0,
				"barb_whirl_haste_cdr",
				"Бешеный вихрь",
				"−5% перезарядки Вихря за ранг.",
				3,
				6,
				["barb_whirl_storm_damage"]
			),
			"barb_cap_0"
		),
		# ── Прыжок-удар (slot1, центр col7) ──
		_skill(1, "leap_slam", "Прыжок-удар", 7),
		_passive(1, "barb_leap_damage", 6, 1, ["leap_slam"]),
		_passive(1, "barb_hook_angle", 8, 1, ["leap_slam"]),
		_cdr(
			1,
			"barb_leap_cdr",
			"Разгон",
			"−5% перезарядки Прыжка-удара за ранг.",
			7,
			2,
			["barb_leap_damage", "barb_hook_angle"]
		),
		_variant(
			1,
			"barb_charge",
			"Сокрушительный рывок",
			"Рывок, наносящий урон всем на пути.",
			5,
			3,
			["barb_leap_cdr"]
		),
		_avariant(
			1,
			"barb_skullcrack_leap",
			"berserker",
			"Прыжок черепокола",
			"Приземление ломает броню врагам.",
			6,
			3,
			["barb_leap_cdr"]
		),
		_variant(
			1,
			"barb_chain_hook",
			"Цепной захват",
			"Цепь притягивает к вам врагов.",
			9,
			3,
			["barb_leap_cdr"]
		),
		_avariant(
			1,
			"barb_guardian_leap",
			"warchief",
			"Прыжок защитника",
			"Приземление укрывает вас и союзников щитом.",
			8,
			3,
			["barb_leap_cdr"]
		),
		_dmg(
			1,
			"barb_leap_quake_damage",
			"Толчок",
			"+урон Прыжка-удара за ранг.",
			6,
			4,
			["barb_leap_cdr"]
		),
		_cdr(
			1,
			"barb_leap_flow_cdr",
			"Импульс",
			"−5% перезарядки Прыжка-удара за ранг.",
			8,
			4,
			["barb_leap_cdr"]
		),
		_dmg(
			1,
			"barb_leap_crush_damage",
			"Сокрушение",
			"+урон Прыжка-удара за ранг.",
			7,
			5,
			["barb_leap_quake_damage", "barb_leap_flow_cdr"]
		),
		_excl(
			_onhit(
				1,
				"barb_leap_status_bleed",
				"bleed",
				"Кровоток",
				"Приземление рвёт врагов в кровь.",
				6,
				6,
				["barb_leap_crush_damage"]
			),
			"barb_cap_1"
		),
		_excl(
			_cdr(
				1,
				"barb_leap_haste_cdr",
				"Ярость прыжка",
				"−5% перезарядки Прыжка-удара за ранг.",
				8,
				6,
				["barb_leap_crush_damage"]
			),
			"barb_cap_1"
		),
		# ── Боевой клич (slot2, центр col12) — бафф: power/haste-капстоун ──
		_skill(2, "battle_cry", "Боевой клич", 12),
		_passive(2, "barb_cry_power", 11, 1, ["battle_cry"]),
		_cdr(
			2,
			"barb_cry_cdr",
			"Зычный голос",
			"−5% перезарядки Боевого клича за ранг.",
			13,
			1,
			["battle_cry"]
		),
		_dmg(
			2,
			"barb_cry_might_damage",
			"Воодушевление",
			"+урон под Боевым кличем за ранг.",
			12,
			2,
			["barb_cry_power", "barb_cry_cdr"]
		),
		_variant(
			2,
			"barb_banner_block",
			"Знамя победы",
			"Знамя: союзники усилены, враги стянуты.",
			10,
			3,
			["barb_cry_might_damage"]
		),
		_avariant(
			2,
			"barb_rage_howl",
			"berserker",
			"Вой ярости",
			"Больше урона взамен защиты.",
			11,
			3,
			["barb_cry_might_damage"]
		),
		_variant(
			2,
			"barb_tremor_roar",
			"Устрашающий рёв",
			"Ударная волна откидывает и замедляет.",
			13,
			3,
			["barb_cry_might_damage"]
		),
		_avariant(
			2,
			"barb_commanding_shout",
			"warchief",
			"Командный окрик",
			"Клич укрывает весь отряд щитом.",
			14,
			3,
			["barb_cry_might_damage"]
		),
		_dmg(
			2,
			"barb_cry_fury_damage",
			"Боевой раж",
			"+урон под Боевым кличем за ранг.",
			11,
			4,
			["barb_cry_might_damage"]
		),
		_cdr(
			2,
			"barb_cry_flow_cdr",
			"Неумолкающий",
			"−5% перезарядки Боевого клича за ранг.",
			13,
			4,
			["barb_cry_might_damage"]
		),
		_dmg(
			2,
			"barb_cry_warlord_damage",
			"Полководец",
			"+урон под Боевым кличем за ранг.",
			12,
			5,
			["barb_cry_fury_damage", "barb_cry_flow_cdr"]
		),
		_excl(
			_dmg(
				2,
				"barb_cry_overload_damage",
				"Мощь вождя",
				"+урон под Боевым кличем за ранг.",
				11,
				6,
				["barb_cry_warlord_damage"]
			),
			"barb_cap_2"
		),
		_excl(
			_cdr(
				2,
				"barb_cry_haste_cdr",
				"Без устали",
				"−5% перезарядки Боевого клича за ранг.",
				13,
				6,
				["barb_cry_warlord_damage"]
			),
			"barb_cap_2"
		),
		# ── Землетрясение (slot3, центр col17) ──
		_skill(3, "earthquake", "Землетрясение", 17),
		_passive(3, "barb_quake_damage", 16, 1, ["earthquake"]),
		_passive(3, "barb_quake_waves", 18, 1, ["earthquake"]),
		_cdr(
			3,
			"barb_quake_cdr",
			"Афтершок",
			"−5% перезарядки Землетрясения за ранг.",
			17,
			2,
			["barb_quake_damage", "barb_quake_waves"]
		),
		_variant(
			3,
			"barb_blood_frenzy_block",
			"Берсерк",
			"Быстрее и больнее, но вы уязвимее.",
			15,
			3,
			["barb_quake_cdr"]
		),
		_avariant(
			3,
			"barb_fault_zone",
			"titanbreaker",
			"Зона разлома",
			"Оставляет дрожащую зону, бьющую врагов.",
			16,
			3,
			["barb_quake_cdr"]
		),
		_perk(
			"berserker_grip",
			"Хватка берсерка",
			"Носите ДВА двуручных оружия разом. Урон складывается.",
			3,
			17,
			3,
			["barb_quake_cdr"]
		),
		_variant(
			3,
			"barb_worldsplitter_block",
			"Удар титана",
			"Трещина, извергающаяся мощным уроном.",
			18,
			3,
			["barb_quake_cdr"]
		),
		_avariant(
			3,
			"barb_war_ground",
			"warchief",
			"Поле битвы",
			"Зона защищает союзников, замедляет врагов.",
			19,
			3,
			["barb_quake_cdr"]
		),
		_dmg(
			3,
			"barb_quake_rift_damage",
			"Разлом",
			"+урон Землетрясения за ранг.",
			16,
			4,
			["barb_quake_cdr"]
		),
		_cdr(
			3,
			"barb_quake_flow_cdr",
			"Толчки",
			"−5% перезарядки Землетрясения за ранг.",
			18,
			4,
			["barb_quake_cdr"]
		),
		_dmg(
			3,
			"barb_quake_cataclysm_damage",
			"Катаклизм",
			"+урон Землетрясения за ранг.",
			17,
			5,
			["barb_quake_rift_damage", "barb_quake_flow_cdr"]
		),
		_excl(
			_onhit(
				3,
				"barb_quake_status_bleed",
				"bleed",
				"Кровоток",
				"Толчки рвут врагов в кровь.",
				16,
				6,
				["barb_quake_cataclysm_damage"]
			),
			"barb_cap_3"
		),
		_excl(
			_cdr(
				3,
				"barb_quake_haste_cdr",
				"Неистовство земли",
				"−5% перезарядки Землетрясения за ранг.",
				18,
				6,
				["barb_quake_cataclysm_damage"]
			),
			"barb_cap_3"
		),
		# ── Перемычки между соседними навыками (рёбра пересекаются) ──
		_shared(
			"barb_weave_might",
			"Берсеркова мощь",
			"+урон Вихря и Прыжка-удара.",
			[
				{"slot": 0, "modifier": "barb_whirl_damage"},
				{"slot": 1, "modifier": "barb_leap_damage"}
			],
			4,
			2,
			["barb_whirl_damage", "barb_leap_damage"]
		),
		_shared(
			"barb_weave_war",
			"Воинский дух",
			"+урон Боевого клича и Землетрясения.",
			[
				{"slot": 2, "modifier": "barb_cry_might_damage"},
				{"slot": 3, "modifier": "barb_quake_damage"}
			],
			14,
			2,
			["barb_cry_power", "barb_quake_damage"]
		),
		_shared(
			"barb_weave_rampage",
			"Лавина",
			"+урон Прыжка-удара и Боевого клича.",
			[
				{"slot": 1, "modifier": "barb_leap_damage"},
				{"slot": 2, "modifier": "barb_cry_might_damage"}
			],
			9,
			5,
			["barb_leap_quake_damage", "barb_cry_fury_damage"]
		),
	]


static func _rogue_nodes() -> Array:
	# Грид: Шипы/Склянка/Веер — статус-развилка (яд); Дымовая бомба (утилита) —
	# power/haste. Веер ножей composed → яд срабатывает сам.
	return [
		# ── Шипы (slot0, центр col2) ──
		_skill(0, "caltrops", "Шипы", 2),
		_passive(0, "rogue_caltrops_damage", 1, 1, ["caltrops"]),
		_passive(0, "rogue_caltrops_duration", 3, 1, ["caltrops"]),
		_cdr(
			0,
			"rogue_calt_cdr",
			"Быстрый сброс",
			"−5% перезарядки Шипов за ранг.",
			2,
			2,
			["rogue_caltrops_damage", "rogue_caltrops_duration"]
		),
		_variant(
			0,
			"rogue_razor_trap",
			"Бритвенный капкан",
			"Капкан, кромсающий наступившего врага.",
			1,
			3,
			["rogue_calt_cdr"]
		),
		_avariant(
			0,
			"rogue_toxic_spikes",
			"venomancer",
			"Токсичные шипы",
			"Шипы копят токсичные стаки.",
			2,
			3,
			["rogue_calt_cdr"]
		),
		_variant(
			0,
			"rogue_trick_field",
			"Поле трюков",
			"Зона иллюзий, сбивающая врагов с толку.",
			3,
			3,
			["rogue_calt_cdr"]
		),
		_dmg(
			0,
			"rogue_calt_edge_damage",
			"Заточка",
			"+урон Шипов за ранг.",
			1,
			4,
			["rogue_calt_cdr"]
		),
		_cdr(
			0,
			"rogue_calt_flow_cdr",
			"Рассыпь",
			"−5% перезарядки Шипов за ранг.",
			3,
			4,
			["rogue_calt_cdr"]
		),
		_dmg(
			0,
			"rogue_calt_apex_damage",
			"Ковёр шипов",
			"+урон Шипов за ранг.",
			2,
			5,
			["rogue_calt_edge_damage", "rogue_calt_flow_cdr"]
		),
		_excl(
			_onhit(
				0,
				"rogue_calt_status_poison",
				"poison",
				"Отравление",
				"Шипы отравляют врагов.",
				1,
				6,
				["rogue_calt_apex_damage"]
			),
			"rogue_cap_0"
		),
		_excl(
			_cdr(
				0,
				"rogue_calt_haste_cdr",
				"Скорая ловушка",
				"−5% перезарядки Шипов за ранг.",
				3,
				6,
				["rogue_calt_apex_damage"]
			),
			"rogue_cap_0"
		),
		# ── Дымовая бомба (slot1, центр col7) — утилита: power/haste ──
		_skill(1, "smoke_bomb", "Дымовая бомба", 7),
		_cdr(
			1,
			"rogue_smoke_cdr",
			"Скорый дым",
			"−5% перезарядки Дымовой бомбы за ранг.",
			6,
			1,
			["smoke_bomb"]
		),
		_dmg(
			1,
			"rogue_smoke_damage",
			"Едкий дым",
			"+урон в дыму за ранг.",
			8,
			1,
			["smoke_bomb"]
		),
		_cdr(
			1,
			"rogue_smoke_veil_cdr",
			"Завеса",
			"−5% перезарядки Дымовой бомбы за ранг.",
			7,
			2,
			["rogue_smoke_cdr", "rogue_smoke_damage"]
		),
		_variant(
			1,
			"rogue_vanish",
			"Исчезновение",
			"Мгновенно скрывает вас и ускоряет.",
			6,
			3,
			["rogue_smoke_veil_cdr"]
		),
		_variant(
			1,
			"rogue_safehouse",
			"Укрытие",
			"Зона-схрон, защищающая вас и союзников.",
			8,
			3,
			["rogue_smoke_veil_cdr"]
		),
		_dmg(
			1,
			"rogue_smoke_edge_damage",
			"Кинжалы в тумане",
			"+урон в дыму за ранг.",
			6,
			4,
			["rogue_smoke_veil_cdr"]
		),
		_cdr(
			1,
			"rogue_smoke_flow_cdr",
			"Клубы",
			"−5% перезарядки Дымовой бомбы за ранг.",
			8,
			4,
			["rogue_smoke_veil_cdr"]
		),
		_dmg(
			1,
			"rogue_smoke_apex_damage",
			"Чёрный туман",
			"+урон в дыму за ранг.",
			7,
			5,
			["rogue_smoke_edge_damage", "rogue_smoke_flow_cdr"]
		),
		_excl(
			_dmg(
				1,
				"rogue_smoke_overload_damage",
				"Ядовитая мгла",
				"+урон в дыму за ранг.",
				6,
				6,
				["rogue_smoke_apex_damage"]
			),
			"rogue_cap_1"
		),
		_excl(
			_cdr(
				1,
				"rogue_smoke_haste_cdr",
				"Дым без устали",
				"−5% перезарядки Дымовой бомбы за ранг.",
				8,
				6,
				["rogue_smoke_apex_damage"]
			),
			"rogue_cap_1"
		),
		# ── Склянка яда (slot2, центр col12) ──
		_skill(2, "poison_vial", "Склянка яда", 12),
		_passive(2, "rogue_poison_damage", 11, 1, ["poison_vial"]),
		_cdr(
			2,
			"rogue_vial_cdr",
			"Ловкий бросок",
			"−5% перезарядки Склянки яда за ранг.",
			13,
			1,
			["poison_vial"]
		),
		_dmg(
			2,
			"rogue_vial_core_damage",
			"Концентрат",
			"+урон Склянки яда за ранг.",
			12,
			2,
			["rogue_poison_damage", "rogue_vial_cdr"]
		),
		_variant(
			2,
			"rogue_confusion_flask",
			"Склянка смятения",
			"Враги нападают друг на друга.",
			11,
			3,
			["rogue_vial_core_damage"]
		),
		_variant(
			2,
			"rogue_triple_flask",
			"Тройная склянка",
			"Метает три склянки веером.",
			13,
			3,
			["rogue_vial_core_damage"]
		),
		_dmg(
			2,
			"rogue_vial_edge_damage",
			"Кислота",
			"+урон Склянки яда за ранг.",
			11,
			4,
			["rogue_vial_core_damage"]
		),
		_cdr(
			2,
			"rogue_vial_flow_cdr",
			"Быстрый замес",
			"−5% перезарядки Склянки яда за ранг.",
			13,
			4,
			["rogue_vial_core_damage"]
		),
		_dmg(
			2,
			"rogue_vial_apex_damage",
			"Чумная склянка",
			"+урон Склянки яда за ранг.",
			12,
			5,
			["rogue_vial_edge_damage", "rogue_vial_flow_cdr"]
		),
		_excl(
			_onhit(
				2,
				"rogue_vial_status_poison",
				"poison",
				"Отравление",
				"Склянка отравляет врагов.",
				11,
				6,
				["rogue_vial_apex_damage"]
			),
			"rogue_cap_2"
		),
		_excl(
			_cdr(
				2,
				"rogue_vial_haste_cdr",
				"Скорая отрава",
				"−5% перезарядки Склянки яда за ранг.",
				13,
				6,
				["rogue_vial_apex_damage"]
			),
			"rogue_cap_2"
		),
		# ── Веер ножей (slot3, центр col17) — composed, яд срабатывает сам ──
		_skill(3, "fan_of_knives", "Веер ножей", 17),
		_passive(3, "rogue_knives_damage", 16, 1, ["fan_of_knives"]),
		_passive(3, "rogue_knives_count", 18, 1, ["fan_of_knives"]),
		_cdr(
			3,
			"rogue_fan_cdr",
			"Быстрый веер",
			"−5% перезарядки Веера ножей за ранг.",
			17,
			2,
			["rogue_knives_damage", "rogue_knives_count"]
		),
		_variant(
			3,
			"rogue_execution_fan",
			"Веер казни",
			"Веер, казнящий ослабленных врагов.",
			16,
			3,
			["rogue_fan_cdr"]
		),
		_variant(
			3,
			"rogue_venom_fan",
			"Ядовитый веер",
			"Веер отравленных кинжалов.",
			18,
			3,
			["rogue_fan_cdr"]
		),
		_dmg(
			3,
			"rogue_fan_edge_damage",
			"Бритвы",
			"+урон Веера ножей за ранг.",
			16,
			4,
			["rogue_fan_cdr"]
		),
		_cdr(
			3,
			"rogue_fan_flow_cdr",
			"Шквал",
			"−5% перезарядки Веера ножей за ранг.",
			18,
			4,
			["rogue_fan_cdr"]
		),
		_dmg(
			3,
			"rogue_fan_apex_damage",
			"Стальной вихрь",
			"+урон Веера ножей за ранг.",
			17,
			5,
			["rogue_fan_edge_damage", "rogue_fan_flow_cdr"]
		),
		_excl(
			_onhit(
				3,
				"rogue_fan_status_poison",
				"poison",
				"Отравление",
				"Ножи отравляют врагов.",
				16,
				6,
				["rogue_fan_apex_damage"]
			),
			"rogue_cap_3"
		),
		_excl(
			_cdr(
				3,
				"rogue_fan_haste_cdr",
				"Без передышки",
				"−5% перезарядки Веера ножей за ранг.",
				18,
				6,
				["rogue_fan_apex_damage"]
			),
			"rogue_cap_3"
		),
		# ── Перемычки ──
		_shared(
			"rogue_weave_lethality",
			"Смертоносность",
			"+урон Склянки яда и Веера ножей.",
			[
				{"slot": 2, "modifier": "rogue_poison_damage"},
				{"slot": 3, "modifier": "rogue_knives_damage"}
			],
			14,
			2,
			["rogue_poison_damage", "rogue_knives_damage"]
		),
		_shared(
			"rogue_weave_traps",
			"Сеть ловушек",
			"+урон Шипов и в дыму.",
			[
				{"slot": 0, "modifier": "rogue_caltrops_damage"},
				{"slot": 1, "modifier": "rogue_smoke_damage"}
			],
			4,
			2,
			["rogue_caltrops_damage", "rogue_smoke_cdr"]
		),
		_shared(
			"rogue_weave_ambush",
			"Засада",
			"+урон в дыму и Склянки яда.",
			[
				{"slot": 1, "modifier": "rogue_smoke_damage"},
				{"slot": 2, "modifier": "rogue_poison_damage"}
			],
			9,
			5,
			["rogue_smoke_edge_damage", "rogue_vial_edge_damage"]
		),
	]


static func _stormcaller_nodes() -> Array:
	# Грид: Цепной разряд/Небесный удар/Разряд статики — статус-развилка (мороз/
	# замедление); Грозовой шаг (рывок) — power/haste.
	return [
		# ── Цепной разряд (slot0, центр col2) ──
		_skill(0, "storm_chain_bolt", "Цепной разряд", 2),
		_passive(0, "storm_bolt_damage", 1, 1, ["storm_chain_bolt"]),
		_passive(0, "storm_bolt_jumps", 3, 1, ["storm_chain_bolt"]),
		_cdr(
			0,
			"storm_bolt_cdr",
			"Скорый разряд",
			"−5% перезарядки Цепного разряда за ранг.",
			2,
			2,
			["storm_bolt_damage", "storm_bolt_jumps"]
		),
		_variant(
			0,
			"storm_charged_slash",
			"Заряженный взмах",
			"Электрический взмах в ближнем бою.",
			1,
			3,
			["storm_bolt_cdr"]
		),
		_avariant(
			0,
			"storm_forked_bolt",
			"tempest_lord",
			"Раздвоенная молния",
			"Разряд ветвится на две цепи.",
			2,
			3,
			["storm_bolt_cdr"]
		),
		_variant(
			0,
			"storm_ally_arc",
			"Дуга к союзнику",
			"Цепь через союзников, бьёт врагов рядом.",
			3,
			3,
			["storm_bolt_cdr"]
		),
		_dmg(
			0,
			"storm_bolt_edge_damage",
			"Перенапряжение",
			"+урон Цепного разряда за ранг.",
			1,
			4,
			["storm_bolt_cdr"]
		),
		_cdr(
			0,
			"storm_bolt_flow_cdr",
			"Проводник",
			"−5% перезарядки Цепного разряда за ранг.",
			3,
			4,
			["storm_bolt_cdr"]
		),
		_dmg(
			0,
			"storm_bolt_apex_damage",
			"Громовержец",
			"+урон Цепного разряда за ранг.",
			2,
			5,
			["storm_bolt_edge_damage", "storm_bolt_flow_cdr"]
		),
		_excl(
			_onhit(
				0,
				"storm_bolt_status_frost",
				"frost",
				"Замедление",
				"Разряд замедляет задетых врагов.",
				1,
				6,
				["storm_bolt_apex_damage"]
			),
			"storm_cap_0"
		),
		_excl(
			_cdr(
				0,
				"storm_bolt_haste_cdr",
				"Без перерыва",
				"−5% перезарядки Цепного разряда за ранг.",
				3,
				6,
				["storm_bolt_apex_damage"]
			),
			"storm_cap_0"
		),
		# ── Грозовой шаг (slot1, центр col7) — рывок: power/haste ──
		_skill(1, "storm_step", "Грозовой шаг", 7),
		_cdr(
			1,
			"storm_step_cdr",
			"Скорый шаг",
			"−5% перезарядки Грозового шага за ранг.",
			6,
			1,
			["storm_step"]
		),
		_dmg(
			1,
			"storm_step_damage",
			"Заряженный след",
			"+урон Грозового шага за ранг.",
			8,
			1,
			["storm_step"]
		),
		_cdr(
			1,
			"storm_step_core_cdr",
			"Лёгкость",
			"−5% перезарядки Грозового шага за ранг.",
			7,
			2,
			["storm_step_cdr", "storm_step_damage"]
		),
		_variant(
			1,
			"storm_thunder_lunge",
			"Громовой выпад",
			"Рывок, бьющий током всех на пути.",
			6,
			3,
			["storm_step_core_cdr"]
		),
		_variant(
			1,
			"storm_stormveil",
			"Грозовая вуаль",
			"Шаг ослепляет и замедляет врагов на пути.",
			7,
			3,
			["storm_step_core_cdr"]
		),
		_variant(
			1,
			"storm_rescue_step",
			"Шаг спасения",
			"Рывок к союзнику, защищающий обоих.",
			8,
			3,
			["storm_step_core_cdr"]
		),
		_dmg(
			1,
			"storm_step_edge_damage",
			"Электрошлейф",
			"+урон Грозового шага за ранг.",
			6,
			4,
			["storm_step_core_cdr"]
		),
		_cdr(
			1,
			"storm_step_flow_cdr",
			"Манёвренность",
			"−5% перезарядки Грозового шага за ранг.",
			8,
			4,
			["storm_step_core_cdr"]
		),
		_dmg(
			1,
			"storm_step_apex_damage",
			"Молниеносность",
			"+урон Грозового шага за ранг.",
			7,
			5,
			["storm_step_edge_damage", "storm_step_flow_cdr"]
		),
		_excl(
			_dmg(
				1,
				"storm_step_overload_damage",
				"Перегруз следа",
				"+урон Грозового шага за ранг.",
				6,
				6,
				["storm_step_apex_damage"]
			),
			"storm_cap_1"
		),
		_excl(
			_cdr(
				1,
				"storm_step_haste_cdr",
				"Вездесущность",
				"−5% перезарядки Грозового шага за ранг.",
				8,
				6,
				["storm_step_apex_damage"]
			),
			"storm_cap_1"
		),
		# ── Небесный удар (slot2, центр col12) ──
		_skill(2, "storm_sky_strike", "Небесный удар", 12),
		_passive(2, "storm_sky_damage", 11, 1, ["storm_sky_strike"]),
		_cdr(
			2,
			"storm_sky_cdr",
			"Скорый удар",
			"−5% перезарядки Небесного удара за ранг.",
			13,
			1,
			["storm_sky_strike"]
		),
		_dmg(
			2,
			"storm_sky_core_damage",
			"Гром небес",
			"+урон Небесного удара за ранг.",
			12,
			2,
			["storm_sky_damage", "storm_sky_cdr"]
		),
		_variant(
			2,
			"storm_pillar",
			"Грозовой столп",
			"Столп бури, бьющий врагов в области.",
			11,
			3,
			["storm_sky_core_damage"]
		),
		_variant(
			2,
			"storm_heavens_spear",
			"Копьё небес",
			"Удар оставляет заряженный участок.",
			12,
			3,
			["storm_sky_core_damage"]
		),
		_variant(
			2,
			"storm_eye_of_storm_block",
			"Око бури",
			"Шторм обрушивает молнии на зону.",
			13,
			3,
			["storm_sky_core_damage"]
		),
		_dmg(
			2,
			"storm_sky_edge_damage",
			"Разряд с небес",
			"+урон Небесного удара за ранг.",
			11,
			4,
			["storm_sky_core_damage"]
		),
		_cdr(
			2,
			"storm_sky_flow_cdr",
			"Шквал",
			"−5% перезарядки Небесного удара за ранг.",
			13,
			4,
			["storm_sky_core_damage"]
		),
		_dmg(
			2,
			"storm_sky_apex_damage",
			"Кара небес",
			"+урон Небесного удара за ранг.",
			12,
			5,
			["storm_sky_edge_damage", "storm_sky_flow_cdr"]
		),
		_excl(
			_onhit(
				2,
				"storm_sky_status_frost",
				"frost",
				"Замедление",
				"Удар замедляет задетых врагов.",
				11,
				6,
				["storm_sky_apex_damage"]
			),
			"storm_cap_2"
		),
		_excl(
			_cdr(
				2,
				"storm_sky_haste_cdr",
				"Шторм без устали",
				"−5% перезарядки Небесного удара за ранг.",
				13,
				6,
				["storm_sky_apex_damage"]
			),
			"storm_cap_2"
		),
		# ── Разряд статики (slot3, центр col17) ──
		_skill(3, "storm_static_discharge", "Разряд статики", 17),
		_passive(3, "storm_discharge_damage", 16, 1, ["storm_static_discharge"]),
		_cdr(
			3,
			"storm_disc_cdr",
			"Скорый сброс",
			"−5% перезарядки Разряда статики за ранг.",
			18,
			1,
			["storm_static_discharge"]
		),
		_dmg(
			3,
			"storm_disc_core_damage",
			"Перенасыщение",
			"+урон Разряда статики за ранг.",
			17,
			2,
			["storm_discharge_damage", "storm_disc_cdr"]
		),
		_variant(
			3,
			"storm_body_discharge",
			"Разряд тела",
			"Мощный электрический взрыв вокруг.",
			15,
			3,
			["storm_disc_core_damage"]
		),
		_variant(
			3,
			"storm_capacitor_core",
			"Ядро конденсатора",
			"Выше предел заряда; крупный разряд возвращает кд.",
			16,
			3,
			["storm_disc_core_damage"]
		),
		_variant(
			3,
			"storm_energizing_discharge",
			"Питающий разряд",
			"Разряд заряжает энергией союзников.",
			18,
			3,
			["storm_disc_core_damage"]
		),
		_avariant(
			3,
			"storm_controlled_discharge",
			"tempest_lord",
			"Управляемый разряд",
			"Разряд в точку, замедляющий врагов.",
			19,
			3,
			["storm_disc_core_damage"]
		),
		_dmg(
			3,
			"storm_disc_edge_damage",
			"Статика",
			"+урон Разряда статики за ранг.",
			16,
			4,
			["storm_disc_core_damage"]
		),
		_cdr(
			3,
			"storm_disc_flow_cdr",
			"Накопитель",
			"−5% перезарядки Разряда статики за ранг.",
			18,
			4,
			["storm_disc_core_damage"]
		),
		_dmg(
			3,
			"storm_disc_apex_damage",
			"Сверхразряд",
			"+урон Разряда статики за ранг.",
			17,
			5,
			["storm_disc_edge_damage", "storm_disc_flow_cdr"]
		),
		_excl(
			_onhit(
				3,
				"storm_disc_status_frost",
				"frost",
				"Замедление",
				"Разряд замедляет задетых врагов.",
				16,
				6,
				["storm_disc_apex_damage"]
			),
			"storm_cap_3"
		),
		_excl(
			_cdr(
				3,
				"storm_disc_haste_cdr",
				"Перезаряд",
				"−5% перезарядки Разряда статики за ранг.",
				18,
				6,
				["storm_disc_apex_damage"]
			),
			"storm_cap_3"
		),
		# ── Перемычки ──
		_shared(
			"storm_weave_overload",
			"Грозовой резонанс",
			"+урон Небесного удара и Разряда статики.",
			[
				{"slot": 2, "modifier": "storm_sky_damage"},
				{"slot": 3, "modifier": "storm_discharge_damage"}
			],
			14,
			2,
			["storm_sky_damage", "storm_discharge_damage"]
		),
		_shared(
			"storm_weave_arc",
			"Дуга бури",
			"+урон Цепного разряда и Грозового шага.",
			[
				{"slot": 0, "modifier": "storm_bolt_damage"},
				{"slot": 1, "modifier": "storm_step_damage"}
			],
			4,
			2,
			["storm_bolt_damage", "storm_step_cdr"]
		),
		_shared(
			"storm_weave_surge",
			"Перенапряжение",
			"+урон Грозового шага и Небесного удара.",
			[
				{"slot": 1, "modifier": "storm_step_damage"},
				{"slot": 2, "modifier": "storm_sky_damage"}
			],
			9,
			5,
			["storm_step_edge_damage", "storm_sky_edge_damage"]
		),
	]


static func _hexen_nodes() -> Array:
	# Грид: все 4 навыка — урон/проклятие, статус-развилка (порча) на ряду 6.
	return [
		# ── Метка проклятия (slot0, центр col2) ──
		_skill(0, "hexen_hex_mark", "Метка проклятия", 2),
		_passive(0, "hexen_mark_damage", 1, 1, ["hexen_hex_mark"]),
		_passive(0, "hexen_mark_duration", 3, 1, ["hexen_hex_mark"]),
		_cdr(
			0,
			"hexen_mark_cdr",
			"Скорая метка",
			"−5% перезарядки Метки проклятия за ранг.",
			2,
			2,
			["hexen_mark_damage", "hexen_mark_duration"]
		),
		_variant(
			0,
			"hexen_open_wound",
			"Открытая рана",
			"Метка ломает броню жертвы.",
			1,
			3,
			["hexen_mark_cdr"]
		),
		_variant(
			0,
			"hexen_eternal_mark",
			"Вечная метка",
			"Метки не истекают сами — подрываются хлыстом/узами.",
			2,
			3,
			["hexen_mark_cdr"]
		),
		_variant(
			0,
			"hexen_rotating_hex",
			"Блуждающая порча",
			"Метка прыгает на нового врага.",
			3,
			3,
			["hexen_mark_cdr"]
		),
		_dmg(
			0,
			"hexen_mark_edge_damage",
			"Сглаз",
			"+урон Метки проклятия за ранг.",
			1,
			4,
			["hexen_mark_cdr"]
		),
		_cdr(
			0,
			"hexen_mark_flow_cdr",
			"Лёгкая порча",
			"−5% перезарядки Метки проклятия за ранг.",
			3,
			4,
			["hexen_mark_cdr"]
		),
		_dmg(
			0,
			"hexen_mark_apex_damage",
			"Печать рока",
			"+урон Метки проклятия за ранг.",
			2,
			5,
			["hexen_mark_edge_damage", "hexen_mark_flow_cdr"]
		),
		_excl(
			_onhit(
				0,
				"hexen_mark_status_curse",
				"curse",
				"Порча",
				"Метка накладывает стак порчи.",
				1,
				6,
				["hexen_mark_apex_damage"]
			),
			"hexen_cap_0"
		),
		_excl(
			_cdr(
				0,
				"hexen_mark_haste_cdr",
				"Скорое клеймо",
				"−5% перезарядки Метки проклятия за ранг.",
				3,
				6,
				["hexen_mark_apex_damage"]
			),
			"hexen_cap_0"
		),
		# ── Кровавый хлыст (slot1, центр col7) ──
		_skill(1, "hexen_blood_whip", "Кровавый хлыст", 7),
		_passive(1, "hexen_whip_damage", 6, 1, ["hexen_blood_whip"]),
		_cdr(
			1,
			"hexen_whip_cdr",
			"Хлёсткость",
			"−5% перезарядки Кровавого хлыста за ранг.",
			8,
			1,
			["hexen_blood_whip"]
		),
		_dmg(
			1,
			"hexen_whip_core_damage",
			"Кровопускание",
			"+урон Кровавого хлыста за ранг.",
			7,
			2,
			["hexen_whip_damage", "hexen_whip_cdr"]
		),
		_variant(
			1,
			"hexen_blood_scythe",
			"Кровавая коса",
			"Широкий взмах косой из крови.",
			6,
			3,
			["hexen_whip_core_damage"]
		),
		_variant(
			1,
			"hexen_binding_whip",
			"Связующий хлыст",
			"Хлыст сковывает ударенных врагов.",
			8,
			3,
			["hexen_whip_core_damage"]
		),
		_dmg(
			1,
			"hexen_whip_edge_damage",
			"Шипы крови",
			"+урон Кровавого хлыста за ранг.",
			6,
			4,
			["hexen_whip_core_damage"]
		),
		_cdr(
			1,
			"hexen_whip_flow_cdr",
			"Гибкость",
			"−5% перезарядки Кровавого хлыста за ранг.",
			8,
			4,
			["hexen_whip_core_damage"]
		),
		_dmg(
			1,
			"hexen_whip_apex_damage",
			"Кровавый смерч",
			"+урон Кровавого хлыста за ранг.",
			7,
			5,
			["hexen_whip_edge_damage", "hexen_whip_flow_cdr"]
		),
		_excl(
			_onhit(
				1,
				"hexen_whip_status_curse",
				"curse",
				"Порча",
				"Хлыст накладывает стак порчи.",
				6,
				6,
				["hexen_whip_apex_damage"]
			),
			"hexen_cap_1"
		),
		_excl(
			_cdr(
				1,
				"hexen_whip_haste_cdr",
				"Без устали",
				"−5% перезарядки Кровавого хлыста за ранг.",
				8,
				6,
				["hexen_whip_apex_damage"]
			),
			"hexen_cap_1"
		),
		# ── Узы души (slot2, центр col12) ──
		_skill(2, "hexen_soul_tether", "Узы души", 12),
		_passive(2, "hexen_tether_damage", 11, 1, ["hexen_soul_tether"]),
		_cdr(
			2,
			"hexen_tether_cdr",
			"Скорые узы",
			"−5% перезарядки Уз души за ранг.",
			13,
			1,
			["hexen_soul_tether"]
		),
		_dmg(
			2,
			"hexen_tether_core_damage",
			"Высасывание",
			"+урон Уз души за ранг.",
			12,
			2,
			["hexen_tether_damage", "hexen_tether_cdr"]
		),
		_variant(
			2,
			"hexen_curse_chain",
			"Цепь проклятий",
			"Цепь разносит проклятие по стае.",
			11,
			3,
			["hexen_tether_core_damage"]
		),
		_variant(
			2,
			"hexen_tether_shock",
			"Шок уз",
			"Узы оглушают связанных от сильного удара.",
			12,
			3,
			["hexen_tether_core_damage"]
		),
		_variant(
			2,
			"hexen_ally_tether",
			"Узы ковена",
			"Связь с союзниками: делит урон и лечение.",
			13,
			3,
			["hexen_tether_core_damage"]
		),
		_dmg(
			2,
			"hexen_tether_edge_damage",
			"Изнурение",
			"+урон Уз души за ранг.",
			11,
			4,
			["hexen_tether_core_damage"]
		),
		_cdr(
			2,
			"hexen_tether_flow_cdr",
			"Тонкие нити",
			"−5% перезарядки Уз души за ранг.",
			13,
			4,
			["hexen_tether_core_damage"]
		),
		_dmg(
			2,
			"hexen_tether_apex_damage",
			"Похищение душ",
			"+урон Уз души за ранг.",
			12,
			5,
			["hexen_tether_edge_damage", "hexen_tether_flow_cdr"]
		),
		_excl(
			_onhit(
				2,
				"hexen_tether_status_curse",
				"curse",
				"Порча",
				"Узы накладывают стак порчи.",
				11,
				6,
				["hexen_tether_apex_damage"]
			),
			"hexen_cap_2"
		),
		_excl(
			_cdr(
				2,
				"hexen_tether_haste_cdr",
				"Скорая связь",
				"−5% перезарядки Уз души за ранг.",
				13,
				6,
				["hexen_tether_apex_damage"]
			),
			"hexen_cap_2"
		),
		# ── Багровый ритуал (slot3, центр col17) ──
		_skill(3, "hexen_crimson_ritual", "Багровый ритуал", 17),
		_passive(3, "hexen_ritual_damage", 16, 1, ["hexen_crimson_ritual"]),
		_cdr(
			3,
			"hexen_ritual_cdr",
			"Скорый обряд",
			"−5% перезарядки Багрового ритуала за ранг.",
			18,
			1,
			["hexen_crimson_ritual"]
		),
		_dmg(
			3,
			"hexen_ritual_core_damage",
			"Жертвенность",
			"+урон Багрового ритуала за ранг.",
			17,
			2,
			["hexen_ritual_damage", "hexen_ritual_cdr"]
		),
		_variant(
			3,
			"hexen_ritual_of_doom",
			"Ритуал рока",
			"Круг копит погибель для всех внутри.",
			15,
			3,
			["hexen_ritual_core_damage"]
		),
		_variant(
			3,
			"hexen_bloodmoon",
			"Ритуал кровавой луны",
			"Ритуал взрывается; убийство возвращает кд.",
			16,
			3,
			["hexen_ritual_core_damage"]
		),
		_variant(
			3,
			"hexen_blood_arena",
			"Кровавая арена",
			"Арена крови: врагам некуда бежать.",
			18,
			3,
			["hexen_ritual_core_damage"]
		),
		_avariant(
			3,
			"hexen_safe_ritual",
			"coven_mother",
			"Безопасный ритуал",
			"Ритуал оберегает союзников внутри.",
			19,
			3,
			["hexen_ritual_core_damage"]
		),
		_dmg(
			3,
			"hexen_ritual_edge_damage",
			"Багряный круг",
			"+урон Багрового ритуала за ранг.",
			16,
			4,
			["hexen_ritual_core_damage"]
		),
		_cdr(
			3,
			"hexen_ritual_flow_cdr",
			"Скоротечный обряд",
			"−5% перезарядки Багрового ритуала за ранг.",
			18,
			4,
			["hexen_ritual_core_damage"]
		),
		_dmg(
			3,
			"hexen_ritual_apex_damage",
			"Кровавая жатва",
			"+урон Багрового ритуала за ранг.",
			17,
			5,
			["hexen_ritual_edge_damage", "hexen_ritual_flow_cdr"]
		),
		_excl(
			_onhit(
				3,
				"hexen_ritual_status_curse",
				"curse",
				"Порча",
				"Ритуал накладывает стак порчи.",
				16,
				6,
				["hexen_ritual_apex_damage"]
			),
			"hexen_cap_3"
		),
		_excl(
			_cdr(
				3,
				"hexen_ritual_haste_cdr",
				"Непрерывный обряд",
				"−5% перезарядки Багрового ритуала за ранг.",
				18,
				6,
				["hexen_ritual_apex_damage"]
			),
			"hexen_cap_3"
		),
		# ── Перемычки ──
		_shared(
			"hexen_weave_malice",
			"Злоба крови",
			"+урон Метки проклятия и Кровавого хлыста.",
			[
				{"slot": 0, "modifier": "hexen_mark_damage"},
				{"slot": 1, "modifier": "hexen_whip_damage"}
			],
			4,
			2,
			["hexen_mark_damage", "hexen_whip_damage"]
		),
		_shared(
			"hexen_weave_blood",
			"Кровавый завет",
			"+урон Уз души и Багрового ритуала.",
			[
				{"slot": 2, "modifier": "hexen_tether_damage"},
				{"slot": 3, "modifier": "hexen_ritual_damage"}
			],
			14,
			2,
			["hexen_tether_damage", "hexen_ritual_damage"]
		),
		_shared(
			"hexen_weave_curse",
			"Сглаз",
			"+урон Кровавого хлыста и Уз души.",
			[
				{"slot": 1, "modifier": "hexen_whip_damage"},
				{"slot": 2, "modifier": "hexen_tether_damage"}
			],
			9,
			5,
			["hexen_whip_edge_damage", "hexen_tether_edge_damage"]
		),
	]


static func _necromancer_nodes() -> Array:
	# Грид: Пульс смерти — урон, статус-развилка (яд); призывы/Договор — power/haste.
	return [
		# ── Поднять скелета (slot0, центр col2) — призыв ──
		_skill(0, "necro_raise_skeleton", "Поднять скелета", 2),
		_passive(0, "necro_skel_count", 1, 1, ["necro_raise_skeleton"]),
		_cdr(
			0,
			"necro_skel_cdr",
			"Скорый зов",
			"−5% перезарядки призыва скелета за ранг.",
			3,
			1,
			["necro_raise_skeleton"]
		),
		_dmg(
			0,
			"necro_skel_core_damage",
			"Острые кости",
			"+урон скелетов за ранг.",
			2,
			2,
			["necro_skel_count", "necro_skel_cdr"]
		),
		_variant(
			0,
			"necro_bone_turret",
			"Костяная турель",
			"Стреляющая костяная турель.",
			1,
			3,
			["necro_skel_core_damage"]
		),
		_avariant(
			0,
			"necro_skeletal_legion",
			"deathlord",
			"Костяной легион",
			"Поднимает сразу трёх скелетов.",
			2,
			3,
			["necro_skel_core_damage"]
		),
		_variant(
			0,
			"necro_bone_spear",
			"Костяное копьё",
			"Пронзающее копьё — урон вместо призыва.",
			3,
			3,
			["necro_skel_core_damage"]
		),
		_dmg(
			0,
			"necro_skel_edge_damage",
			"Костяная гниль",
			"+урон скелетов за ранг.",
			1,
			4,
			["necro_skel_core_damage"]
		),
		_cdr(
			0,
			"necro_skel_flow_cdr",
			"Неустанный зов",
			"−5% перезарядки призыва скелета за ранг.",
			3,
			4,
			["necro_skel_core_damage"]
		),
		_dmg(
			0,
			"necro_skel_apex_damage",
			"Орда костей",
			"+урон скелетов за ранг.",
			2,
			5,
			["necro_skel_edge_damage", "necro_skel_flow_cdr"]
		),
		_excl(
			_dmg(
				0,
				"necro_skel_overload_damage",
				"Мощь нежити",
				"+урон скелетов за ранг.",
				1,
				6,
				["necro_skel_apex_damage"]
			),
			"necro_cap_0"
		),
		_excl(
			_cdr(
				0,
				"necro_skel_haste_cdr",
				"Вечный зов",
				"−5% перезарядки призыва скелета за ранг.",
				3,
				6,
				["necro_skel_apex_damage"]
			),
			"necro_cap_0"
		),
		# ── Поднять рыцаря (slot1, центр col7) — призыв ──
		_skill(1, "necro_raise_knight", "Поднять рыцаря", 7),
		_passive(1, "necro_knight_armor", 6, 1, ["necro_raise_knight"]),
		_cdr(
			1,
			"necro_knight_cdr",
			"Скорый призыв",
			"−5% перезарядки призыва рыцаря за ранг.",
			8,
			1,
			["necro_raise_knight"]
		),
		_dmg(
			1,
			"necro_knight_core_damage",
			"Тяжёлый клинок",
			"+урон рыцаря за ранг.",
			7,
			2,
			["necro_knight_armor", "necro_knight_cdr"]
		),
		_variant(
			1,
			"necro_bone_golem",
			"Костяной голем",
			"Медленный, но несокрушимый голем.",
			5,
			3,
			["necro_knight_core_damage"]
		),
		_avariant(
			1,
			"necro_grave_champion",
			"deathlord",
			"Могильный чемпион",
			"Рыцарь становится чемпионом.",
			6,
			3,
			["necro_knight_core_damage"]
		),
		_variant(
			1,
			"necro_curse_field",
			"Поле проклятия",
			"Враги внутри получают больше урона.",
			8,
			3,
			["necro_knight_core_damage"]
		),
		_avariant(
			1,
			"necro_oathbound_knight",
			"gravebinder",
			"Клятвенный рыцарь",
			"Рыцарь принимает урон союзников.",
			9,
			3,
			["necro_knight_core_damage"]
		),
		_dmg(
			1,
			"necro_knight_edge_damage",
			"Закалённая сталь",
			"+урон рыцаря за ранг.",
			6,
			4,
			["necro_knight_core_damage"]
		),
		_cdr(
			1,
			"necro_knight_flow_cdr",
			"Скорая клятва",
			"−5% перезарядки призыва рыцаря за ранг.",
			8,
			4,
			["necro_knight_core_damage"]
		),
		_dmg(
			1,
			"necro_knight_apex_damage",
			"Гвардия смерти",
			"+урон рыцаря за ранг.",
			7,
			5,
			["necro_knight_edge_damage", "necro_knight_flow_cdr"]
		),
		_excl(
			_dmg(
				1,
				"necro_knight_overload_damage",
				"Мощь гвардии",
				"+урон рыцаря за ранг.",
				6,
				6,
				["necro_knight_apex_damage"]
			),
			"necro_cap_1"
		),
		_excl(
			_cdr(
				1,
				"necro_knight_haste_cdr",
				"Вечный страж",
				"−5% перезарядки призыва рыцаря за ранг.",
				8,
				6,
				["necro_knight_apex_damage"]
			),
			"necro_cap_1"
		),
		# ── Кровавый договор (slot2, центр col12) — бафф ──
		_skill(2, "necro_blood_pact", "Кровавый договор", 12),
		_passive(2, "necro_pact_power", 11, 1, ["necro_blood_pact"]),
		_cdr(
			2,
			"necro_pact_cdr",
			"Скорая сделка",
			"−5% перезарядки Кровавого договора за ранг.",
			13,
			1,
			["necro_blood_pact"]
		),
		_dmg(
			2,
			"necro_pact_core_damage",
			"Кровавая мощь",
			"+урон под Кровавым договором за ранг.",
			12,
			2,
			["necro_pact_power", "necro_pact_cdr"]
		),
		_variant(
			2,
			"necro_blood_ward",
			"Кровавый оберег",
			"Оберег защищает вас и приспешников.",
			11,
			3,
			["necro_pact_core_damage"]
		),
		_variant(
			2,
			"necro_crown_of_dead_block",
			"Корона мёртвых",
			"Венец усиливает всех ваших мертвецов.",
			13,
			3,
			["necro_pact_core_damage"]
		),
		_dmg(
			2,
			"necro_pact_edge_damage",
			"Жертва крови",
			"+урон под Кровавым договором за ранг.",
			11,
			4,
			["necro_pact_core_damage"]
		),
		_cdr(
			2,
			"necro_pact_flow_cdr",
			"Скорый обет",
			"−5% перезарядки Кровавого договора за ранг.",
			13,
			4,
			["necro_pact_core_damage"]
		),
		_dmg(
			2,
			"necro_pact_apex_damage",
			"Тёмный завет",
			"+урон под Кровавым договором за ранг.",
			12,
			5,
			["necro_pact_edge_damage", "necro_pact_flow_cdr"]
		),
		_excl(
			_dmg(
				2,
				"necro_pact_overload_damage",
				"Полная отдача",
				"+урон под Кровавым договором за ранг.",
				11,
				6,
				["necro_pact_apex_damage"]
			),
			"necro_cap_2"
		),
		_excl(
			_cdr(
				2,
				"necro_pact_haste_cdr",
				"Вечный договор",
				"−5% перезарядки Кровавого договора за ранг.",
				13,
				6,
				["necro_pact_apex_damage"]
			),
			"necro_cap_2"
		),
		# ── Пульс смерти (slot3, центр col17) — урон ──
		_skill(3, "necro_death_pulse", "Пульс смерти", 17),
		_passive(3, "necro_pulse_damage", 16, 1, ["necro_death_pulse"]),
		_passive(3, "necro_pulse_radius", 18, 1, ["necro_death_pulse"]),
		_cdr(
			3,
			"necro_pulse_cdr",
			"Скорый пульс",
			"−5% перезарядки Пульса смерти за ранг.",
			17,
			2,
			["necro_pulse_damage", "necro_pulse_radius"]
		),
		_variant(
			3,
			"necro_bone_nova",
			"Костяная нова",
			"Взрыв костяных осколков вокруг.",
			16,
			3,
			["necro_pulse_cdr"]
		),
		_avariant(
			3,
			"necro_rally_pulse",
			"deathlord",
			"Сплачивающий пульс",
			"Пульс вдобавок лечит приспешников.",
			17,
			3,
			["necro_pulse_cdr"]
		),
		_variant(
			3,
			"necro_mending_pulse",
			"Целящий пульс",
			"Ранит врагов и латает приспешников.",
			18,
			3,
			["necro_pulse_cdr"]
		),
		_dmg(
			3,
			"necro_pulse_edge_damage",
			"Волна тлена",
			"+урон Пульса смерти за ранг.",
			16,
			4,
			["necro_pulse_cdr"]
		),
		_cdr(
			3,
			"necro_pulse_flow_cdr",
			"Скорая волна",
			"−5% перезарядки Пульса смерти за ранг.",
			18,
			4,
			["necro_pulse_cdr"]
		),
		_dmg(
			3,
			"necro_pulse_apex_damage",
			"Погибель",
			"+урон Пульса смерти за ранг.",
			17,
			5,
			["necro_pulse_edge_damage", "necro_pulse_flow_cdr"]
		),
		_excl(
			_onhit(
				3,
				"necro_pulse_status_poison",
				"poison",
				"Отравление",
				"Пульс отравляет врагов.",
				16,
				6,
				["necro_pulse_apex_damage"]
			),
			"necro_cap_3"
		),
		_excl(
			_cdr(
				3,
				"necro_pulse_haste_cdr",
				"Непрерывный пульс",
				"−5% перезарядки Пульса смерти за ранг.",
				18,
				6,
				["necro_pulse_apex_damage"]
			),
			"necro_cap_3"
		),
		# ── Перемычки ──
		_shared(
			"necro_weave_grave",
			"Могильная сила",
			"+мощь Договора и урон Пульса смерти.",
			[
				{"slot": 2, "modifier": "necro_pact_power"},
				{"slot": 3, "modifier": "necro_pulse_damage"}
			],
			14,
			2,
			["necro_pact_power", "necro_pulse_damage"]
		),
		_shared(
			"necro_weave_legion",
			"Армия мёртвых",
			"+урон скелетов и рыцаря.",
			[
				{"slot": 0, "modifier": "necro_skel_core_damage"},
				{"slot": 1, "modifier": "necro_knight_core_damage"}
			],
			4,
			2,
			["necro_skel_count", "necro_knight_armor"]
		),
		_shared(
			"necro_weave_army",
			"Воля повелителя",
			"+урон рыцаря и под Договором.",
			[
				{"slot": 1, "modifier": "necro_knight_core_damage"},
				{"slot": 2, "modifier": "necro_pact_core_damage"}
			],
			9,
			5,
			["necro_knight_edge_damage", "necro_pact_edge_damage"]
		),
	]


static func _druid_nodes() -> Array:
	# Грид: 5 корней горизонтально (центры col 2/7/12/17/22). Облики/броня/дух —
	# не прямой урон, поэтому капстоун power/haste (без on-hit). Формы несут base_skill.
	return [
		# ── Облик волка (slot0, центр col2) ──
		_skill(0, "druid_wolf_form", "Облик волка", 2),
		_passive(0, "wolf_duration", 1, 1, ["druid_wolf_form"]),
		_cdr(
			0,
			"druid_wolf_cdr",
			"Скорая ярость",
			"−5% перезарядки Облика волка за ранг.",
			3,
			1,
			["druid_wolf_form"]
		),
		_dmg(
			0,
			"druid_wolf_core_damage",
			"Когти волка",
			"+урон в Облике волка за ранг.",
			2,
			2,
			["wolf_duration", "druid_wolf_cdr"]
		),
		_variant_base(
			0,
			"druid_hurricane",
			"druid_wolf_form",
			"Око бури",
			"Облик волка → кружащий Ураган.",
			2,
			3,
			["druid_wolf_core_damage"]
		),
		_dmg(
			0,
			"druid_wolf_edge_damage",
			"Клыки",
			"+урон в Облике волка за ранг.",
			1,
			4,
			["druid_wolf_core_damage"]
		),
		_cdr(
			0,
			"druid_wolf_flow_cdr",
			"Прыть",
			"−5% перезарядки Облика волка за ранг.",
			3,
			4,
			["druid_wolf_core_damage"]
		),
		_dmg(
			0,
			"druid_wolf_apex_damage",
			"Вожак стаи",
			"+урон в Облике волка за ранг.",
			2,
			5,
			["druid_wolf_edge_damage", "druid_wolf_flow_cdr"]
		),
		_excl(
			_dmg(
				0,
				"druid_wolf_overload_damage",
				"Хищный натиск",
				"+урон в Облике волка за ранг.",
				1,
				6,
				["druid_wolf_apex_damage"]
			),
			"druid_cap_0"
		),
		_excl(
			_cdr(
				0,
				"druid_wolf_haste_cdr",
				"Неутомимость",
				"−5% перезарядки Облика волка за ранг.",
				3,
				6,
				["druid_wolf_apex_damage"]
			),
			"druid_cap_0"
		),
		# ── Облик медведя (slot1, центр col7) ──
		_skill(1, "druid_bear_form", "Облик медведя", 7),
		_passive(1, "bear_duration", 6, 1, ["druid_bear_form"]),
		_cdr(
			1,
			"druid_bear_cdr",
			"Скорый рёв",
			"−5% перезарядки Облика медведя за ранг.",
			8,
			1,
			["druid_bear_form"]
		),
		_dmg(
			1,
			"druid_bear_core_damage",
			"Лапа медведя",
			"+урон в Облике медведя за ранг.",
			7,
			2,
			["bear_duration", "druid_bear_cdr"]
		),
		_variant_base(
			1,
			"druid_dire_wolf",
			"druid_bear_form",
			"Альфа-хищник",
			"Облик медведя → облик лютого волка.",
			7,
			3,
			["druid_bear_core_damage"]
		),
		_dmg(
			1,
			"druid_bear_edge_damage",
			"Мощь зверя",
			"+урон в Облике медведя за ранг.",
			6,
			4,
			["druid_bear_core_damage"]
		),
		_cdr(
			1,
			"druid_bear_flow_cdr",
			"Закалка",
			"−5% перезарядки Облика медведя за ранг.",
			8,
			4,
			["druid_bear_core_damage"]
		),
		_dmg(
			1,
			"druid_bear_apex_damage",
			"Ярость гризли",
			"+урон в Облике медведя за ранг.",
			7,
			5,
			["druid_bear_edge_damage", "druid_bear_flow_cdr"]
		),
		_excl(
			_dmg(
				1,
				"druid_bear_overload_damage",
				"Сокрушение",
				"+урон в Облике медведя за ранг.",
				6,
				6,
				["druid_bear_apex_damage"]
			),
			"druid_cap_1"
		),
		_excl(
			_cdr(
				1,
				"druid_bear_haste_cdr",
				"Несокрушимость",
				"−5% перезарядки Облика медведя за ранг.",
				8,
				6,
				["druid_bear_apex_damage"]
			),
			"druid_cap_1"
		),
		# ── Каменная броня (slot2, центр col12) — защита ──
		_skill(2, "druid_stone_armor", "Каменная броня", 12),
		_passive(2, "stone_armor_charges", 11, 1, ["druid_stone_armor"]),
		_cdr(
			2,
			"druid_stone_cdr",
			"Скорая броня",
			"−5% перезарядки Каменной брони за ранг.",
			13,
			1,
			["druid_stone_armor"]
		),
		_dmg(
			2,
			"druid_stone_core_damage",
			"Каменные шипы",
			"+урон от Каменной брони за ранг.",
			12,
			2,
			["stone_armor_charges", "druid_stone_cdr"]
		),
		_variant(
			2,
			"druid_hide_of_beast",
			"Шкура зверя",
			"Звериная шкура укрепляет облики.",
			10,
			3,
			["druid_stone_core_damage"]
		),
		_variant(
			2,
			"stone_armor_grinder",
			"Жернова",
			"Осколки брони вращаются и бьют врагов.",
			11,
			3,
			["druid_stone_core_damage"]
		),
		_variant(
			2,
			"druid_barkskin_aura",
			"Аура коры",
			"Кора оберегает вас и союзников рядом.",
			13,
			3,
			["druid_stone_core_damage"]
		),
		_avariant(
			2,
			"druid_earthen_pulse",
			"stormshaper",
			"Земляной пульс",
			"Броня периодически бьёт землёй.",
			14,
			3,
			["druid_stone_core_damage"]
		),
		_dmg(
			2,
			"druid_stone_edge_damage",
			"Гранит",
			"+урон от Каменной брони за ранг.",
			11,
			4,
			["druid_stone_core_damage"]
		),
		_cdr(
			2,
			"druid_stone_flow_cdr",
			"Прочность",
			"−5% перезарядки Каменной брони за ранг.",
			13,
			4,
			["druid_stone_core_damage"]
		),
		_dmg(
			2,
			"druid_stone_apex_damage",
			"Горный доспех",
			"+урон от Каменной брони за ранг.",
			12,
			5,
			["druid_stone_edge_damage", "druid_stone_flow_cdr"]
		),
		_excl(
			_dmg(
				2,
				"druid_stone_overload_damage",
				"Камнепад",
				"+урон от Каменной брони за ранг.",
				11,
				6,
				["druid_stone_apex_damage"]
			),
			"druid_cap_2"
		),
		_excl(
			_cdr(
				2,
				"druid_stone_haste_cdr",
				"Скорый камень",
				"−5% перезарядки Каменной брони за ранг.",
				13,
				6,
				["druid_stone_apex_damage"]
			),
			"druid_cap_2"
		),
		# ── Призыв духа (slot3, центр col17) — призыв ──
		_skill(3, "druid_summon_spirit", "Призыв духа", 17),
		_passive(3, "spirit_pets", 16, 1, ["druid_summon_spirit"]),
		_passive(3, "spirit_summon_damage", 18, 1, ["druid_summon_spirit"]),
		_cdr(
			3,
			"druid_spirit_cdr",
			"Скорый зов духа",
			"−5% перезарядки Призыва духа за ранг.",
			17,
			2,
			["spirit_pets", "spirit_summon_damage"]
		),
		_variant(
			3,
			"druid_pack_spirit",
			"Дух стаи",
			"Волчий дух усиливает ваши облики.",
			16,
			3,
			["druid_spirit_cdr"]
		),
		_avariant(
			3,
			"druid_storm_totem",
			"stormshaper",
			"Грозовой тотем",
			"Вместо духа — тотем, бьющий молниями.",
			17,
			3,
			["druid_spirit_cdr"]
		),
		_variant(
			3,
			"druid_guardian_spirit",
			"Дух-хранитель",
			"Дух оберегает вас и союзников.",
			18,
			3,
			["druid_spirit_cdr"]
		),
		_dmg(
			3,
			"druid_spirit_edge_damage",
			"Свирепый дух",
			"+урон духов за ранг.",
			16,
			4,
			["druid_spirit_cdr"]
		),
		_cdr(
			3,
			"druid_spirit_flow_cdr",
			"Зов природы",
			"−5% перезарядки Призыва духа за ранг.",
			18,
			4,
			["druid_spirit_cdr"]
		),
		_dmg(
			3,
			"druid_spirit_apex_damage",
			"Стая духов",
			"+урон духов за ранг.",
			17,
			5,
			["druid_spirit_edge_damage", "druid_spirit_flow_cdr"]
		),
		_excl(
			_dmg(
				3,
				"druid_spirit_overload_damage",
				"Дикий гнев",
				"+урон духов за ранг.",
				16,
				6,
				["druid_spirit_apex_damage"]
			),
			"druid_cap_3"
		),
		_excl(
			_cdr(
				3,
				"druid_spirit_haste_cdr",
				"Вечный зов",
				"−5% перезарядки Призыва духа за ранг.",
				18,
				6,
				["druid_spirit_apex_damage"]
			),
			"druid_cap_3"
		),
		# ── Облик орла (slot4, центр col22) ──
		_skill(4, "druid_eagle_form", "Облик орла", 22),
		_passive(4, "eagle_duration", 21, 1, ["druid_eagle_form"]),
		_cdr(
			4,
			"druid_eagle_cdr",
			"Скорый взлёт",
			"−5% перезарядки Облика орла за ранг.",
			23,
			1,
			["druid_eagle_form"]
		),
		_dmg(
			4,
			"druid_eagle_core_damage",
			"Когти орла",
			"+урон в Облике орла за ранг.",
			22,
			2,
			["eagle_duration", "druid_eagle_cdr"]
		),
		_dmg(
			4,
			"druid_eagle_edge_damage",
			"Перья-лезвия",
			"+урон в Облике орла за ранг.",
			21,
			4,
			["druid_eagle_core_damage"]
		),
		_cdr(
			4,
			"druid_eagle_flow_cdr",
			"Парение",
			"−5% перезарядки Облика орла за ранг.",
			23,
			4,
			["druid_eagle_core_damage"]
		),
		_dmg(
			4,
			"druid_eagle_apex_damage",
			"Небесный охотник",
			"+урон в Облике орла за ранг.",
			22,
			5,
			["druid_eagle_edge_damage", "druid_eagle_flow_cdr"]
		),
		_excl(
			_dmg(
				4,
				"druid_eagle_overload_damage",
				"Пикирование",
				"+урон в Облике орла за ранг.",
				21,
				6,
				["druid_eagle_apex_damage"]
			),
			"druid_cap_4"
		),
		_excl(
			_cdr(
				4,
				"druid_eagle_haste_cdr",
				"Лёгкость крыла",
				"−5% перезарядки Облика орла за ранг.",
				23,
				6,
				["druid_eagle_apex_damage"]
			),
			"druid_cap_4"
		),
		# ── Перемычки ──
		_shared(
			"druid_weave_wild",
			"Дикая выносливость",
			"+длительность обликов волка и медведя.",
			[
				{"slot": 0, "modifier": "wolf_duration"},
				{"slot": 1, "modifier": "bear_duration"}
			],
			4,
			2,
			["wolf_duration", "bear_duration"]
		),
		_shared(
			"druid_weave_grove",
			"Сила рощи",
			"+урон Каменной брони и духов.",
			[
				{"slot": 2, "modifier": "druid_stone_core_damage"},
				{"slot": 3, "modifier": "spirit_summon_damage"}
			],
			14,
			2,
			["stone_armor_charges", "spirit_pets"]
		),
		_shared(
			"druid_weave_pack",
			"Зов дикой стаи",
			"+урон духов и Облика орла.",
			[
				{"slot": 3, "modifier": "druid_spirit_edge_damage"},
				{"slot": 4, "modifier": "druid_eagle_core_damage"}
			],
			19,
			5,
			["druid_spirit_edge_damage", "druid_eagle_edge_damage"]
		),
	]


# ── Хелперы ──────────────────────────────────────────────────────────────────
static func node_cost(node: Dictionary) -> int:
	return VARIANT_COST if String(node.get("kind", "")) == "variant" else 1


static func node_parents(node: Dictionary) -> Array:
	return node.get("parents", [])


static func passive_targets(node: Dictionary) -> Array:
	return node.get("targets", [])


# Корневой skill-узел слота ("" если нет). Ранг этого узла = уровень навыка слота.
static func root_node_id_for_slot(cls: String, slot: int) -> String:
	for n in nodes_for(cls):
		if String(n["kind"]) == "skill" and int(n["slot"]) == slot:
			return String(n["id"])
	return ""


# Найти узел: {} или {group:"skill"|"stat"|"ult", node, slot}.
static func find_node(cls: String, node_id: String) -> Dictionary:
	for n in nodes_for(cls):
		if String(n["id"]) == node_id:
			return {"group": "skill", "node": n, "slot": int(n.get("slot", -1))}
	for s in STAT_NODES:
		if String(s["id"]) == node_id:
			return {"group": "stat", "node": s}
	for u in TalentTrees.ULT_NODES:
		if String(u["id"]) == node_id:
			return {"group": "ult", "node": u}
	return {}


# Все variant-node id, ложащиеся в данный слот (radio-эксклюзивность).
static func variant_ids_for_slot(cls: String, slot: int) -> Array:
	var out: Array = []
	for n in nodes_for(cls):
		if String(n["kind"]) == "variant" and int(n.get("slot", -1)) == slot:
			out.append(String(n["id"]))
	return out


# (transform, base_skill) каждого варианта — для построения карт SkillCatalog.
static func all_variant_bindings() -> Array:
	var out: Array = []
	for cls in GameManager.class_ids():
		var root_by_slot: Dictionary = {}
		for n in nodes_for(cls):
			if String(n["kind"]) == "skill":
				root_by_slot[int(n["slot"])] = String(n["skill_id"])
		for n in nodes_for(cls):
			if String(n["kind"]) != "variant":
				continue
			var slot: int = int(n.get("slot", -1))
			var base: String = String(n.get("base_skill", root_by_slot.get(slot, "")))
			out.append({"transform": String(n["transform"]), "base_skill": base})
	return out


# Размер холста графа (в ячейках сетки) для панели.
static func canvas_size(cls: String) -> Vector2:
	var max_col: int = 0
	var max_row: int = 0
	for n in nodes_for(cls):
		max_col = maxi(max_col, int(n["col"]))
		max_row = maxi(max_row, int(n["row"]))
	return Vector2(max_col + 1, max_row + 1)


# ── Display ──────────────────────────────────────────────────────────────────
static func node_display_name(node: Dictionary) -> String:
	if String(node.get("name", "")) != "":
		return String(node["name"])
	if String(node["kind"]) == "passive":
		var t: Array = node.get("targets", [])
		if not t.is_empty():
			var mid: String = String(t[0]["modifier"])
			if RewardData.has_modifier(mid):
				return RewardData.find_modifier(mid).title
	return String(node["id"])


static func node_display_desc(node: Dictionary) -> String:
	if String(node.get("desc", "")) != "":
		return String(node["desc"])
	if String(node["kind"]) == "passive":
		var t: Array = node.get("targets", [])
		if not t.is_empty():
			var m := RewardData.find_modifier(String(t[0]["modifier"]))
			var desc: String = m.desc
			var stack: String = m.stack_bonus
			if stack != "":
				desc += "\nЗа ранг: " + stack
			return desc
	if String(node["kind"]) == "skill":
		return "Прокачка навыка: +урон и −перезарядка за ранг (не ниже 0.5 с)."
	return ""


static func node_max_ranks(node: Dictionary) -> int:
	return int(node.get("max_ranks", -1))
