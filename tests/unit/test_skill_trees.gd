extends GutTest

# SkillTrees graph integrity + the GameManager skill-level / edge-gating / variant
# / shared-node / restore flow.

const ALL_CLASSES := ["barbarian", "rogue", "mage", "stormcaller", "hexen", "necromancer", "druid"]

var _saved_class: String = ""
var _saved_points: int = 0
var _saved_nodes: Dictionary = {}
var _saved_path: String = ""


func before_each() -> void:
	_saved_class = GameManager.player_class
	_saved_points = GameManager.talent_points
	_saved_nodes = GameManager.tree_nodes.duplicate(true)
	_saved_path = GameManager.player_spec_path


func after_each() -> void:
	GameManager.tree_nodes = _saved_nodes
	GameManager.talent_points = _saved_points
	GameManager.player_spec_path = _saved_path
	if _saved_class != "" and _saved_class != GameManager.player_class:
		GameManager.choose_class(_saved_class)


# ── graph integrity ──────────────────────────────────────────────────────────


func test_graph_is_well_formed() -> void:
	var overrides: Dictionary = SkillCatalog.transform_overrides()
	var base_map: Dictionary = SkillCatalog.transform_base()
	for cls in ALL_CLASSES:
		var nodes: Array = SkillTrees.nodes_for(cls)
		assert_gt(nodes.size(), 0, "%s has no nodes" % cls)
		var ids := {}
		var root_slots := {}
		for n in nodes:
			ids[String(n["id"])] = true
		for n in nodes:
			var nid := String(n["id"])
			# coords + parents reference real nodes
			assert_true(n.has("col") and n.has("row"), "%s node '%s' needs col/row" % [cls, nid])
			for pid in SkillTrees.node_parents(n):
				assert_true(
					ids.has(String(pid)), "%s node '%s' parent '%s' unknown" % [cls, nid, pid]
				)
			match String(n["kind"]):
				"skill":
					root_slots[int(n["slot"])] = true
					assert_not_null(
						SkillCatalog.get_def(String(n["skill_id"])),
						"%s root '%s' missing from catalog" % [cls, n["skill_id"]]
					)
				"passive":
					if String(n.get("on_hit", "")) != "":
						assert_true(
							String(n["on_hit"]) in ["fire", "bleed", "frost", "poison", "curse"],
							"%s status node '%s' bad element" % [cls, nid]
						)
						continue
					for t in SkillTrees.passive_targets(n):
						# "_cdr"/"_damage" passives are generic — no RewardData entry.
						var tmid := String(t["modifier"])
						if tmid.ends_with("_cdr") or tmid.ends_with("_damage"):
							continue
						assert_true(
							RewardData.has_modifier(tmid),
							"%s passive '%s' modifier '%s' unknown" % [cls, nid, t["modifier"]]
						)
				"variant":
					var tr := String(n["transform"])
					assert_true(
						overrides.has(tr) or SkillCatalog.CTX_VARIANTS.has(tr),
						"%s variant '%s' wired nowhere" % [cls, nid]
					)
					assert_true(
						base_map.has(tr), "%s variant '%s' has no base binding" % [cls, nid]
					)
					var rp := String(n.get("requires_path", ""))
					if rp != "":
						assert_false(
							SpecPaths.find(cls, rp).is_empty(),
							"%s variant '%s' requires unknown path '%s'" % [cls, nid, rp]
						)
		# Roots cover the class's skill slots (mage 4, druid 5 incl. forms+eagle).
		var want_roots: int = 5 if cls == "druid" else 4
		assert_eq(root_slots.size(), want_roots, "%s should have %d root slots" % [cls, want_roots])


func test_canvas_size_positive_and_deep() -> void:
	for cls in ALL_CLASSES:
		var g: Vector2 = SkillTrees.canvas_size(cls)
		assert_gt(g.x, 0.0, "%s canvas width" % cls)
		# Augmentation deepens every class to at least 6 rows (row index >= 5).
		assert_gte(g.y, 6.0, "%s tree should be >=6 rows deep" % cls)


func _buy_chain(node_id: String) -> bool:
	# Recursively buy a node's ancestors (edge prerequisites) then the node.
	var info: Dictionary = SkillTrees.find_node(GameManager.player_class, node_id)
	if info.is_empty():
		return false
	for pid in SkillTrees.node_parents(info["node"]):
		if int(GameManager.tree_nodes.get(String(pid), 0)) <= 0:
			_buy_chain(String(pid))
	return GameManager.spend_node(node_id)


func test_cdr_and_onhit_nodes_apply() -> void:
	GameManager.choose_class("mage")
	GameManager.tree_nodes = {}
	GameManager.talent_points = 30
	# Mage (hand-authored grid): fw_cdr on slot 0, ib_status_frost on slot 1.
	# Buy each via its prerequisite chain.
	assert_true(_buy_chain("fw_cdr"), "cdr buyable after its chain")
	assert_true(_buy_chain("ib_status_frost"), "on-hit status buyable after its chain")
	var ss := SkillSystem.new()
	add_child_autofree(ss)
	GameManager.reapply_talent_effects(ss)
	assert_gte(ss._slot_cdr_ranks(0), 1, "cdr modifier landed on slot 0")
	assert_true((ss.on_hit[1] as Array).has("frost"), "on-hit frost registered on slot 1")


func test_choice_nodes_are_mutually_exclusive() -> void:
	GameManager.choose_class("mage")
	GameManager.tree_nodes = {}
	GameManager.talent_points = 30
	# Status row is a per-skill choice: fw_status_fire and fw_status_curse share
	# group "mage_status_fw" — taking one locks the other.
	assert_true(_buy_chain("fw_status_fire"), "first status branch buyable")
	assert_eq(
		GameManager.node_block_reason("fw_status_curse"),
		"Выбрана другая ветвь",
		"sibling status locks"
	)
	# A different skill's status group is unaffected.
	assert_ne(
		GameManager.node_block_reason("ib_status_frost"),
		"Выбрана другая ветвь",
		"other skill's status group is independent"
	)
	# Respec frees the group again.
	GameManager.respec_talents()
	assert_false(
		SkillTrees.exclusive_group_taken(
			"mage", "mage_status_fw", "fw_status_curse", GameManager.tree_nodes
		),
		"respec frees the choice group"
	)


func test_mage_has_forks_diamonds_and_weaves() -> void:
	var nodes: Array = SkillTrees.nodes_for("mage")
	var by_id := {}
	for n in nodes:
		by_id[String(n["id"])] = n
	# Fork: a root with >=2 children.
	var children := {}
	for n in nodes:
		for p in SkillTrees.node_parents(n):
			children[String(p)] = int(children.get(String(p), 0)) + 1
	assert_gte(int(children.get("fire_wall", 0)), 2, "root forks into >=2 children")
	# Diamond: a node with >=2 parents.
	assert_gte(SkillTrees.node_parents(by_id["fw_duration"]).size(), 2, "fw_duration is a diamond")
	# Weave: a shared node spanning two slots (2 targets).
	assert_eq((by_id["mage_weave_fw_ib"]["targets"] as Array).size(), 2, "weave spans two skills")


func test_skill_tree_opens_in_run_not_hub() -> void:
	# Tree may open anywhere in a run (run_node_active set) but not in the hub
	# (run_node_active empty) nor on game over.
	var saved_node: Dictionary = GameManager.run_node_active.duplicate(true)
	var saved_over: bool = GameManager.game_over
	GameManager.game_over = false
	GameManager.run_node_active = {}
	assert_false(GameManager.can_open_skill_tree(), "hub (no active node) → closed")
	GameManager.run_node_active = {"type": "campfire"}
	assert_true(GameManager.can_open_skill_tree(), "in a run node → open")
	GameManager.game_over = true
	assert_false(GameManager.can_open_skill_tree(), "game over → closed")
	GameManager.run_node_active = saved_node
	GameManager.game_over = saved_over


# ── GameManager flow ─────────────────────────────────────────────────────────


func test_skill_root_levels_and_edge_gating() -> void:
	GameManager.choose_class("mage")
	GameManager.tree_nodes = {}
	GameManager.talent_points = 6
	# Passives hang off the root (a skill node) → available immediately.
	assert_eq(GameManager.node_block_reason("fw_damage"), "", "passive under root is open")
	# Variant sits under the row-2 diamond (fw_duration) → gated until it's taken.
	assert_ne(GameManager.node_block_reason("flame_cleave"), "", "variant gated before its passive")
	# Level the root skill itself.
	assert_true(GameManager.spend_node("fire_wall"))
	assert_eq(GameManager.get_skill_level(0), 1, "root rank = skill level")
	# Take the row-1 + row-2 passives → the variant opens.
	assert_true(GameManager.spend_node("fw_damage"))
	assert_true(GameManager.spend_node("fw_duration"))
	assert_eq(GameManager.node_block_reason("flame_cleave"), "", "variant opens after its passive")


func test_variant_costs_two_and_switches_net_zero() -> void:
	GameManager.choose_class("mage")
	GameManager.tree_nodes = {}
	GameManager.talent_points = 6
	# flame_cleave + ice_wall both hang off the fw_duration diamond.
	GameManager.spend_node("fw_damage")
	GameManager.spend_node("fw_radius")
	GameManager.spend_node("fw_duration")
	var pts: int = GameManager.talent_points
	assert_true(GameManager.spend_node("flame_cleave"), "select variant")
	assert_eq(GameManager.talent_points, pts - SkillTrees.VARIANT_COST, "variant costs 2")
	var pts2: int = GameManager.talent_points
	assert_true(GameManager.spend_node("ice_wall"), "switch variant")
	assert_eq(int(GameManager.tree_nodes.get("flame_cleave", 0)), 0, "old variant refunded")
	assert_eq(GameManager.talent_points, pts2, "switch is net-0 points")
	# Deselect refunds the cost.
	assert_true(GameManager.spend_node("ice_wall"))
	assert_eq(GameManager.talent_points, pts2 + SkillTrees.VARIANT_COST, "deselect refunds 2")


func test_shared_node_feeds_two_slots() -> void:
	GameManager.choose_class("mage")
	GameManager.tree_nodes = {}
	GameManager.talent_points = 6
	GameManager.spend_node("fw_damage")  # parent of mage_weave_fw_ib
	assert_eq(GameManager.node_block_reason("mage_weave_fw_ib"), "", "weave opens after a parent")
	assert_true(GameManager.spend_node("mage_weave_fw_ib"))
	# Restore onto a fresh SkillSystem and check BOTH slots got their modifier.
	var ss := SkillSystem.new()
	add_child_autofree(ss)
	GameManager.reapply_talent_effects(ss)
	assert_eq(ss.get_modifier(0, "fw_damage"), 2, "fw_damage = direct + weave")
	assert_eq(ss.get_modifier(1, "ib_damage"), 1, "weave also fed slot 1 (ice bolt)")


func test_respec_keeps_perks_refunds_rest() -> void:
	GameManager.choose_class("barbarian")
	GameManager.tree_nodes = {}
	GameManager.talent_points = 30
	# berserker_grip (perk) sits deep in the earthquake spine; buy its chain.
	assert_true(_buy_chain("berserker_grip"), "perk buyable via its chain")
	assert_eq(int(GameManager.tree_nodes.get("berserker_grip", 0)), 1)
	# Chain bought the root + 3 passives (quake_damage/waves + the cdr diamond) before
	# the perk; refund excludes the perk.
	var before: int = GameManager.talent_points
	var refund: int = GameManager.talent_respec_refund()
	assert_eq(refund, 4, "refund = root + 3 passives (perk kept)")
	GameManager.respec_talents()
	assert_eq(GameManager.talent_points, before + refund)
	assert_eq(int(GameManager.tree_nodes.get("berserker_grip", 0)), 1, "perk survives respec")
	assert_eq(int(GameManager.tree_nodes.get("barb_quake_damage", 0)), 0, "passive refunded")


func test_reapply_restores_passive_and_variant() -> void:
	GameManager.choose_class("mage")
	GameManager.tree_nodes = {}
	GameManager.talent_points = 6
	GameManager.spend_node("fw_damage")
	GameManager.spend_node("fw_duration")  # diamond parent of the variant
	GameManager.spend_node("flame_cleave")
	var ss := SkillSystem.new()
	add_child_autofree(ss)
	GameManager.reapply_talent_effects(ss)
	assert_eq(ss.get_modifier(0, "fw_damage"), 1, "passive restored")
	assert_eq(String(ss.get_transform(0)), "flame_cleave", "variant restored")
	# Base skills always present (nothing locked).
	ss._refresh_skill_ids()
	assert_eq(String(ss.skill_ids[0]), "fire_wall")
