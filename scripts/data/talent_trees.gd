class_name TalentTrees
extends RefCounted

# In-run talent trees (WoW-style). Each class has 3 branches mirroring its
# SpecPaths trio (same ids → the ult cluster knows which branch it belongs to).
# A level-up grants 1 talent point (GameManager.talent_points); points are spent
# on nodes here via GameManager.spend_talent_point().
#
# Branch dict: {id, name, stat, tiers}. `stat` is the branch's profile stat —
# purely thematic for stat nodes placed in it (effects of str/dex/int are
# universal, see GameManager stat getters). `tiers` is an Array of node Arrays;
# tier i unlocks once POINTS_PER_TIER * i points are SPENT in that branch.
#
# Node kinds:
#   stat      — +`amount` to `stat` per rank (unlimited ranks).
#   modifier  — one rank of a RewardData skill modifier (title/desc/slot are
#               resolved from RewardData, no duplication). Unlimited ranks.
#   transform — REPLACES a skill slot (the old level-up "unique" cards moved
#               here). Single rank. Does not stack with an ascension transform
#               on the same slot — spend validation blocks that.
#   perk      — one-off special (Berserker's Grip). Single rank.
#   ult       — ascension-ability upgrades (shared ULT_NODES cluster, shown in
#               the branch matching the chosen spec path; require an ascension).

const POINTS_PER_TIER: int = 3

# Ult cluster — appended to the chosen ascension's branch (branch.id ==
# GameManager.player_spec_path). Read by SkillSystem.cast_ascension.
const ULT_POWER_PER_RANK: float = 0.10
const ULT_HASTE_PER_RANK: float = 0.05
const ULT_HASTE_MAX_RANKS: int = 10

const ULT_NODES := [
	{
		"id": "ult_power",
		"kind": "ult",
		"name": "Awakened Might",
		"desc": "+10% ultimate (R) damage per rank.",
		"max_ranks": -1,
	},
	{
		"id": "ult_haste",
		"kind": "ult",
		"name": "Awakened Tempo",
		"desc": "-5% ultimate (R) cooldown per rank (max -50%).",
		"max_ranks": ULT_HASTE_MAX_RANKS,
	},
]

# Equipped unique items no longer replace skills — they grant FREE ranks of a
# related modifier node while worn (keyed by ItemInstance.unique_id). Free ranks
# ignore tier gates (early access to power) and vanish on unequip.
const ITEM_NODE_GRANTS := {
	"bone_spear_unique": {"node": "necro_pact_power", "ranks": 2},
	"curse_field_unique": {"node": "necro_knight_armor", "ranks": 2},
	"druid_hurricane_unique": {"node": "wolf_duration", "ranks": 2},
	"druid_dire_wolf_unique": {"node": "bear_duration", "ranks": 2},
}


# Shorthand builders keep the tree tables readable.
static func _stat(branch_id: String, stat: String) -> Dictionary:
	const NAMES := {"strength": "Might", "dexterity": "Finesse", "intelligence": "Insight"}
	const DESCS := {
		"strength": "+2 Strength per rank (melee/basic damage, max HP).",
		"dexterity": "+2 Dexterity per rank (attack speed, move speed, crit).",
		"intelligence": "+2 Intelligence per rank (skill damage, mana, cooldowns).",
	}
	return {
		"id": "%s_%s" % [branch_id, stat],
		"kind": "stat",
		"name": String(NAMES[stat]),
		"desc": String(DESCS[stat]),
		"stat": stat,
		"amount": 2,
		"max_ranks": -1,
	}


static func _mod(modifier_id: String) -> Dictionary:
	return {"id": modifier_id, "kind": "modifier", "modifier": modifier_id, "max_ranks": -1}


static func _xform(transform_id: String) -> Dictionary:
	return {"id": "t_" + transform_id, "kind": "transform", "transform": transform_id, "max_ranks": 1}


# Per-class trees. Branch ids/names mirror SpecPaths.PATHS so the ult cluster
# lands in the branch of the chosen ascension. Profile stats follow the role:
# warrior → strength, caster → intelligence, support → dexterity.
static func branches_for(cls: String) -> Array:
	match cls:
		"mage":
			return [
				{
					"id": "battlemage",
					"name": "Battlemage",
					"stat": "strength",
					"tiers":
					[
						[_stat("battlemage", "strength"), _mod("fw_radius")],
						[_mod("fw_damage"), _mod("fw_duration")],
						[_xform("ice_wall")],
					],
				},
				{
					"id": "elementalist",
					"name": "Elementalist",
					"stat": "intelligence",
					"tiers":
					[
						[_stat("elementalist", "intelligence"), _mod("ib_slow")],
						[_mod("ib_damage"), _mod("ib_pierce"), _mod("mt_radius")],
						[_mod("mt_damage"), _xform("frost_nova"), _xform("meteor_shower")],
					],
				},
				{
					"id": "chronomancer",
					"name": "Chronomancer",
					"stat": "dexterity",
					"tiers":
					[
						[_stat("chronomancer", "dexterity"), _mod("cl_damage")],
						[_mod("cl_jumps")],
						[_xform("death_beam")],
					],
				},
			]
		"barbarian":
			return [
				{
					"id": "berserker",
					"name": "Berserker",
					"stat": "strength",
					"tiers":
					[
						[_stat("berserker", "strength"), _mod("barb_whirl_damage")],
						[
							{
								"id": "berserker_grip",
								"kind": "perk",
								"name": "Berserker's Grip",
								"desc": "Wield TWO two-handed weapons at once. Weapon damage stacks.",
								"max_ranks": 1,
							}
						],
					],
				},
				{
					"id": "warchief",
					"name": "Warchief",
					"stat": "dexterity",
					"tiers":
					[
						[_stat("warchief", "dexterity"), _mod("barb_cry_power")],
						[_mod("barb_leap_damage")],
					],
				},
				{
					"id": "titanbreaker",
					"name": "Titanbreaker",
					"stat": "intelligence",
					"tiers":
					[
						[_stat("titanbreaker", "intelligence"), _mod("barb_quake_damage")],
						[_mod("barb_quake_waves")],
					],
				},
			]
		"rogue":
			return [
				{
					"id": "assassin",
					"name": "Assassin",
					"stat": "strength",
					"tiers":
					[
						[_stat("assassin", "strength"), _mod("rogue_knives_damage")],
						[_mod("rogue_knives_count")],
					],
				},
				{
					"id": "trickster",
					"name": "Trickster",
					"stat": "dexterity",
					"tiers":
					[
						[_stat("trickster", "dexterity"), _mod("rogue_caltrops_duration")],
						[_mod("rogue_caltrops_damage")],
					],
				},
				{
					"id": "venomancer",
					"name": "Venomancer",
					"stat": "intelligence",
					"tiers": [[_stat("venomancer", "intelligence"), _mod("rogue_poison_damage")]],
				},
			]
		"druid":
			return [
				{
					"id": "primal_alpha",
					"name": "Primal Alpha",
					"stat": "strength",
					"tiers":
					[
						[_stat("primal_alpha", "strength"), _mod("wolf_duration")],
						[_mod("bear_duration")],
						[_xform("druid_dire_wolf")],
					],
				},
				{
					"id": "grovekeeper",
					"name": "Grovekeeper",
					"stat": "dexterity",
					"tiers":
					[
						[_stat("grovekeeper", "dexterity"), _mod("stone_armor_charges")],
						[_mod("eagle_duration")],
						[_xform("stone_armor_grinder")],
					],
				},
				{
					"id": "stormshaper",
					"name": "Stormshaper",
					"stat": "intelligence",
					"tiers":
					[
						[_stat("stormshaper", "intelligence"), _mod("spirit_pets")],
						[_mod("spirit_summon_damage")],
						[_xform("druid_hurricane")],
					],
				},
			]
		"necromancer":
			return [
				{
					"id": "deathlord",
					"name": "Deathlord",
					"stat": "strength",
					"tiers":
					[
						[_stat("deathlord", "strength"), _mod("necro_knight_armor")],
						[_mod("necro_skel_count")],
					],
				},
				{
					"id": "bone_architect",
					"name": "Bone Architect",
					"stat": "intelligence",
					"tiers":
					[
						[_stat("bone_architect", "intelligence"), _mod("necro_pulse_damage")],
						[_mod("necro_pulse_radius")],
						[_xform("necro_bone_spear")],
					],
				},
				{
					"id": "gravebinder",
					"name": "Gravebinder",
					"stat": "dexterity",
					"tiers":
					[
						[_stat("gravebinder", "dexterity"), _mod("necro_pact_power")],
						[_xform("necro_curse_field")],
					],
				},
			]
		"hexen":
			return [
				{
					"id": "blood_witch",
					"name": "Blood Witch",
					"stat": "strength",
					"tiers":
					[
						[_stat("blood_witch", "strength"), _mod("hexen_whip_damage")],
						[_mod("hexen_ritual_damage")],
						[_xform("hexen_bloodmoon")],
					],
				},
				{
					"id": "curseweaver",
					"name": "Curseweaver",
					"stat": "intelligence",
					"tiers":
					[
						[_stat("curseweaver", "intelligence"), _mod("hexen_mark_damage")],
						[_mod("hexen_mark_duration")],
						[_xform("hexen_eternal_mark")],
					],
				},
				{
					"id": "coven_mother",
					"name": "Coven Mother",
					"stat": "dexterity",
					"tiers":
					[
						[_stat("coven_mother", "dexterity"), _mod("hexen_tether_damage")],
						[_xform("hexen_tether_shock")],
					],
				},
			]
		"stormcaller":
			return [
				{
					"id": "thunderblade",
					"name": "Thunderblade",
					"stat": "strength",
					"tiers":
					[
						[_stat("thunderblade", "strength"), _mod("storm_discharge_damage")],
						[_xform("storm_capacitor_core")],
					],
				},
				{
					"id": "tempest_lord",
					"name": "Tempest Lord",
					"stat": "intelligence",
					"tiers":
					[
						[_stat("tempest_lord", "intelligence"), _mod("storm_bolt_damage")],
						[_mod("storm_bolt_jumps")],
						[_xform("storm_heavens_spear")],
					],
				},
				{
					"id": "conductor",
					"name": "Conductor",
					"stat": "dexterity",
					"tiers":
					[
						[_stat("conductor", "dexterity"), _mod("storm_sky_damage")],
						[_xform("storm_stormveil")],
					],
				},
			]
	return []


# ─────────────────────────────────────────────────────────────────────────────
# Lookup / progression helpers (talents = GameManager.talents: node_id → ranks).


# {node, branch_index, tier_index} for tree nodes; ult nodes return tier -1 and
# the branch of the CHOSEN spec path (-1 if none/mortal). {} = unknown id.
static func node_info(cls: String, node_id: String) -> Dictionary:
	var branches: Array = branches_for(cls)
	for b in branches.size():
		var tiers: Array = branches[b]["tiers"]
		for t in tiers.size():
			for node in tiers[t]:
				if String(node["id"]) == node_id:
					return {"node": node, "branch_index": b, "tier_index": t}
	for node in ULT_NODES:
		if String(node["id"]) == node_id:
			return {"node": node, "branch_index": _ascended_branch_index(cls), "tier_index": -1}
	return {}


static func _ascended_branch_index(cls: String) -> int:
	var path_id: String = _read_spec_path()
	if path_id == "":
		return -1
	var branches: Array = branches_for(cls)
	for b in branches.size():
		if String(branches[b]["id"]) == path_id:
			return b
	return -1


static func _read_spec_path() -> String:
	var loop = Engine.get_main_loop()
	if loop and loop.has_method("get_root"):
		var gm = loop.call("get_root").get_node_or_null("GameManager")
		if gm:
			return String(gm.get("player_spec_path"))
	return ""


# Points SPENT in a branch (item-granted free ranks don't count toward tiers).
static func points_in_branch(cls: String, branch_index: int, talents: Dictionary) -> int:
	var branches: Array = branches_for(cls)
	if branch_index < 0 or branch_index >= branches.size():
		return 0
	var total: int = 0
	for tier in branches[branch_index]["tiers"]:
		for node in tier:
			total += int(talents.get(String(node["id"]), 0))
	return total


static func tier_unlocked(cls: String, branch_index: int, tier_index: int, talents: Dictionary) -> bool:
	return points_in_branch(cls, branch_index, talents) >= POINTS_PER_TIER * tier_index


# node_id → free ranks from currently equipped unique items.
static func _equipped_grants() -> Dictionary:
	var loop = Engine.get_main_loop()
	if loop == null or not loop.has_method("get_root"):
		return {}
	var inv = loop.call("get_root").get_node_or_null("InventorySystem")
	if inv == null:
		return {}
	var out: Dictionary = {}
	var equipment: Dictionary = inv.get("equipment") if inv.get("equipment") != null else {}
	for slot in equipment:
		var it = equipment[slot]
		if it == null:
			continue
		var uid: String = String(it.get("unique_id")) if it.get("unique_id") != null else ""
		if uid == "" or not ITEM_NODE_GRANTS.has(uid):
			continue
		var grant: Dictionary = ITEM_NODE_GRANTS[uid]
		var node_id: String = String(grant["node"])
		out[node_id] = int(out.get(node_id, 0)) + int(grant["ranks"])
	return out


# Free ranks granted to one node by currently equipped unique items.
static func item_grant_ranks(node_id: String) -> int:
	return int(_equipped_grants().get(node_id, 0))


# modifier_id → equipped-item free ranks, filtered to one skill slot. Used by
# SkillSystem's generic "_damage" stacking so item-granted ranks count even when
# the player never bought the node.
static func item_granted_modifiers(slot: int) -> Dictionary:
	var grants: Dictionary = _equipped_grants()
	var out: Dictionary = {}
	for node_id in grants:
		var m: Dictionary = RewardData.find_modifier(String(node_id))
		if m.is_empty() or int(m.get("slot", -1)) != slot:
			continue
		out[node_id] = grants[node_id]
	return out


# Display name/desc/icon source — modifier & transform nodes pull from RewardData
# so titles stay in one place.
static func display_name(node: Dictionary) -> String:
	match String(node["kind"]):
		"modifier":
			var m: Dictionary = RewardData.find_modifier(String(node["modifier"]))
			return String(m.get("title", node["modifier"]))
		"transform":
			var u: Dictionary = RewardData.find_unique_by_transform(String(node["transform"]))
			return String(u.get("title", node["transform"]))
	return String(node.get("name", "?"))


static func display_desc(node: Dictionary) -> String:
	match String(node["kind"]):
		"modifier":
			var m: Dictionary = RewardData.find_modifier(String(node["modifier"]))
			var desc: String = String(m.get("desc", ""))
			var stack: String = String(m.get("stack_bonus", ""))
			if stack != "":
				desc += "\nPer rank: " + stack
			return desc
		"transform":
			var u: Dictionary = RewardData.find_unique_by_transform(String(node["transform"]))
			return "REPLACES a skill: " + String(u.get("desc", ""))
	return String(node.get("desc", ""))


# Skill slot a node touches (-1 = none/whole character).
static func node_slot(node: Dictionary) -> int:
	match String(node["kind"]):
		"modifier":
			var m: Dictionary = RewardData.find_modifier(String(node["modifier"]))
			return int(m.get("slot", -1))
		"transform":
			var u: Dictionary = RewardData.find_unique_by_transform(String(node["transform"]))
			return int(u.get("slot", -1))
	return -1


static func max_ranks(node: Dictionary) -> int:
	return int(node.get("max_ranks", -1))
