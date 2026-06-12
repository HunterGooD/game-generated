class_name MetaTrees
extends RefCounted

# Meta mirror trees — persistent, per-class PoE-style passive trees. Every class has a tree
# with the SAME shape (one place to extend / rebalance): a central start node feeds three
# arms — warrior (upper-left), caster (upper-right), support (top) — each ending in a
# NOTABLE named after that class's level-7 ascension (SpecPaths trio), so a meta path themes
# toward an awakening. A socket hangs below the start (gem slot, filled in Phase E).
#
# The shape is assembled by `_build_tree` from a compact per-class spec (primary attribute +
# the three ascension ids) so all seven trees stay consistent; tune the layout/stat profile
# in ONE place. Numbers are placeholder pending a balance pass.
#
# Node fields (as consumed by MetaProgress):
#   pos    — Vector2 layout position for the UI renderer. Unused by logic.
#   type   — "start" (auto-taken, free) / "stat" / "notable" / "socket".
#   links  — neighbouring node ids (undirected: one taken neighbour unlocks a node).
#   stats  — flat additive bonuses; keys match GameManager player_* fields.
#   grants — run-start economy perks (fortune arm), summed by MetaProgress.run_grants:
#            gold / materials{} / start_gems / socket_chance.
#   effect — inert tag (reserved); set to the ascension id for future themed handlers.

# primary = the class's main attribute (drives the small stat nodes); warrior/caster/support
# = the SpecPaths ascension id for each arm (see scripts/data/spec_paths.gd).
const _CLASS_SPECS := {
	"barbarian":
	{"primary": "strength", "warrior": "berserker", "caster": "titanbreaker", "support": "warchief"},
	"rogue":
	{"primary": "dexterity", "warrior": "assassin", "caster": "venomancer", "support": "trickster"},
	"mage":
	{"primary": "intelligence", "warrior": "battlemage", "caster": "elementalist", "support": "chronomancer"},
	"stormcaller":
	{"primary": "dexterity", "warrior": "thunderblade", "caster": "tempest_lord", "support": "conductor"},
	"hexen":
	{"primary": "intelligence", "warrior": "blood_witch", "caster": "curseweaver", "support": "coven_mother"},
	"necromancer":
	{
		"primary": "intelligence",
		"warrior": "deathlord",
		"caster": "bone_architect",
		"support": "gravebinder",
	},
	"druid":
	{"primary": "intelligence", "warrior": "primal_alpha", "caster": "stormshaper", "support": "grovekeeper"},
}

# Built once on first access from _CLASS_SPECS (see _build_all). class id -> node dict.
static var TREES: Dictionary = _build_all()


static func _build_all() -> Dictionary:
	var out: Dictionary = {}
	for cid in _CLASS_SPECS:
		out[cid] = _build_tree(_CLASS_SPECS[cid])
	return out


# Construct one class's uniform 3-arm tree. Variable keys (the primary stat, the ascension
# node ids) are assigned explicitly rather than via dict literals — bulletproof against
# literal-key parsing quirks.
static func _build_tree(spec: Dictionary) -> Dictionary:
	var primary: String = String(spec["primary"])
	var w: String = String(spec["warrior"])
	var c: String = String(spec["caster"])
	var s: String = String(spec["support"])

	# Each arm: stat → stat → SOCKET (gem slot) → ascension notable. Plus a base socket
	# below the start. So a fully-pathed class has four sockets (one per arm + the base).
	var t: Dictionary = {
		"start": {"pos": Vector2(0, 0), "type": "start", "links": ["w1", "c1", "s1", "socket_1"]},
		# warrior arm (upper-left) — survivability + melee.
		"w1": {"pos": Vector2(-100, -55), "type": "stat", "links": ["start", "w2"], "stats": _one(primary, 3)},
		"w2": {"pos": Vector2(-170, -120), "type": "stat", "links": ["w1", "w_socket"], "stats": {"max_hp": 18}},
		"w_socket": {"pos": Vector2(-225, -195), "type": "socket", "links": ["w2", w]},
		# caster arm (upper-right) — spell power + mana.
		"c1": {"pos": Vector2(100, -55), "type": "stat", "links": ["start", "c2"], "stats": _one(primary, 3)},
		"c2": {"pos": Vector2(170, -120), "type": "stat", "links": ["c1", "c_socket"], "stats": {"max_mana": 20}},
		"c_socket": {"pos": Vector2(225, -195), "type": "socket", "links": ["c2", c]},
		# support arm (top) — durability + utility.
		"s1": {"pos": Vector2(0, -110), "type": "stat", "links": ["start", "s2"], "stats": _one(primary, 2)},
		"s2": {"pos": Vector2(0, -190), "type": "stat", "links": ["s1", "s_socket"], "stats": {"max_hp": 16}},
		"s_socket": {"pos": Vector2(0, -270), "type": "socket", "links": ["s2", s]},
		"socket_1": {"pos": Vector2(0, 115), "type": "socket", "links": ["start"]},
		# Fortune arm (bottom) — run-start economy + the gear-socket system: starting
		# gold/materials, socketed-loot chance, and starting socket gems (самоцветы).
		"fortune_gold":
		{
			"pos": Vector2(-110, 90),
			"type": "stat",
			"links": ["start", "fortune_socket"],
			"grants": {"gold": 100},
		},
		"fortune_socket":
		{
			"pos": Vector2(-180, 165),
			"type": "stat",
			"links": ["fortune_gold", "fortune_socket_2"],
			"grants": {"socket_chance": 0.06},
		},
		"fortune_socket_2":
		{
			"pos": Vector2(-250, 240),
			"type": "stat",
			"links": ["fortune_socket"],
			"grants": {"socket_chance": 0.06},
		},
		"fortune_materials":
		{
			"pos": Vector2(110, 90),
			"type": "stat",
			"links": ["start", "fortune_gems_1"],
			"grants": {"materials": {"scrap": 4, "cloth": 4, "essence": 2}},
		},
		"fortune_gems_1":
		{
			"pos": Vector2(180, 165),
			"type": "stat",
			"links": ["fortune_materials", "fortune_gems_2"],
			"grants": {"start_gems": 1},
		},
		"fortune_gems_2":
		{
			"pos": Vector2(250, 240),
			"type": "stat",
			"links": ["fortune_gems_1", "fortune_gems_3"],
			"grants": {"start_gems": 1},
		},
		"fortune_gems_3":
		{
			"pos": Vector2(320, 315),
			"type": "stat",
			"links": ["fortune_gems_2"],
			"grants": {"start_gems": 1},
		},
	}
	# Each arm's final notable is REPEATABLE: once taken it can be ranked up forever, each
	# extra rank a small percent bump (rank_pct, fractions: 0.001 = +0.1%). This is the
	# infinite sink — when the whole tree is bought, surplus points keep flowing here. The
	# one-time `stats` apply on the first rank; `rank_pct` applies per rank (incl. the first).
	var rank_pct: Dictionary = {"damage": 0.001, "max_hp": 0.001}
	t[w] = {
		"pos": Vector2(-270, -280),
		"type": "notable",
		"links": ["w_socket"],
		"stats": {"max_hp": 40, "damage": 5, "crit_damage": 0.15},
		"repeatable": true,
		"rank_pct": rank_pct,
		"effect": w,
	}
	t[c] = {
		"pos": Vector2(270, -280),
		"type": "notable",
		"links": ["c_socket"],
		"stats": {"damage": 7, "max_mana": 30, "crit_chance": 0.03},
		"repeatable": true,
		"rank_pct": rank_pct,
		"effect": c,
	}
	t[s] = {
		"pos": Vector2(0, -355),
		"type": "notable",
		"links": ["s_socket"],
		"stats": {"max_hp": 45, "max_mana": 30},
		"repeatable": true,
		"rank_pct": rank_pct,
		"effect": s,
	}
	return t


# Build a single-entry stat dict with a dynamic key.
static func _one(key: String, value: int) -> Dictionary:
	var d: Dictionary = {}
	d[key] = value
	return d


static func tree_for(class_id: String) -> Dictionary:
	return TREES.get(class_id, {})


static func has_node(class_id: String, node_id: String) -> bool:
	return tree_for(class_id).has(node_id)


static func node_data(class_id: String, node_id: String) -> Dictionary:
	var tree: Dictionary = tree_for(class_id)
	var nd: Dictionary = tree.get(node_id, {})
	return nd


# The single auto-taken start node id for a class tree ("" if the tree is absent/empty).
static func start_node(class_id: String) -> String:
	var tree: Dictionary = tree_for(class_id)
	for id in tree:
		var nd: Dictionary = tree[id]
		if String(nd.get("type", "")) == "start":
			return String(id)
	return ""
