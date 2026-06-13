class_name TalentTrees
extends RefCounted

# Остаток после перехода на единое древо (SkillTrees): здесь живёт только
# кластер ПРОБУЖДЕНИЯ (ult-узлы ультимейта) и хелперы set-бонусов сетов. Сами
# деревья навыков/статов/вариантов теперь в scripts/data/skill_trees.gd.

# Ult-кластер — показывается под выбранным вознесением (SkillTrees ascension
# column). Ранги читаются вживую SkillSystem.cast_ascension.
const ULT_POWER_PER_RANK: float = 0.10
const ULT_HASTE_PER_RANK: float = 0.05
const ULT_HASTE_MAX_RANKS: int = 10

const ULT_NODES := [
	{
		"id": "ult_power",
		"kind": "ult",
		"name": "Пробуждённая мощь",
		"desc": "+10% урона ультимейта (R) за ранг.",
		"max_ranks": -1,
	},
	{
		"id": "ult_haste",
		"kind": "ult",
		"name": "Пробуждённый темп",
		"desc": "−5% перезарядки ультимейта (R) за ранг (макс. −50%).",
		"max_ranks": ULT_HASTE_MAX_RANKS,
	},
]


# ── Set 4-piece node grants ──────────────────────────────────────────────────
# node_id → free ranks from worn 4+/5-piece sets (driven by ItemDatabase.SETS
# bonus4). Modifier nodes keep node_id == modifier_id; stat-column nodes are
# stat_strength / stat_dexterity / stat_intelligence.
static func _set_grants() -> Dictionary:
	var loop = Engine.get_main_loop()
	if loop == null or not loop.has_method("get_root"):
		return {}
	var root = loop.call("get_root")
	var inv = root.get_node_or_null("InventorySystem")
	var gm = root.get_node_or_null("GameManager")
	if inv == null or gm == null or not inv.has_method("get_set_piece_counts"):
		return {}
	var class_id: String = String(gm.get("player_class")) if gm.get("player_class") != null else ""
	var out: Dictionary = {}
	var counts: Dictionary = inv.call("get_set_piece_counts")
	for set_id in counts:
		if int(counts[set_id]) < 4:
			continue
		var grant: Dictionary = ItemDatabase.set_node_grant(String(set_id), class_id)
		if grant.is_empty():
			continue
		var node_id: String = String(grant.get("node", ""))
		if node_id == "":
			continue
		out[node_id] = int(out.get(node_id, 0)) + int(grant.get("ranks", 0))
	return out


# Free ranks granted to one node by worn set bonuses.
static func set_grant_ranks(node_id: String) -> int:
	return int(_set_grants().get(node_id, 0))


# modifier_id → set-granted free ranks, filtered to one skill slot. Used by
# SkillSystem's generic "_damage" stacking so granted ranks count even when the
# player never bought the node.
static func set_granted_modifiers(slot: int) -> Dictionary:
	var grants: Dictionary = _set_grants()
	var out: Dictionary = {}
	for node_id in grants:
		var m: Dictionary = RewardData.find_modifier(String(node_id))
		if m.is_empty() or int(m.get("slot", -1)) != slot:
			continue
		out[node_id] = grants[node_id]
	return out
