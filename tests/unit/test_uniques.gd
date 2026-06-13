extends GutTest

# Uniques after the rework: every unique is a (possibly conditional) skill
# EFFECT — never a node-rank grant, never a slot swap.

# Ids a conditional unique may require: a SkillTrees variant transform or a
# constellation root skill (the ex-talent transforms that are now base skills).
var _requirable_ids: Dictionary = {}


func before_all() -> void:
	for cls in SkillTrees.CLASS_IDS:
		for n in SkillTrees.nodes_for(String(cls)):
			match String(n.get("kind", "")):
				"skill":
					_requirable_ids[String(n["skill_id"])] = true
				"variant":
					_requirable_ids[String(n["transform"])] = true


func after_each() -> void:
	InventorySystem.equipment.clear()
	InventorySystem._rebuild_transform_cache()
	GameManager.tree_nodes = {}


func test_every_unique_has_effect_id() -> void:
	for u in ItemDatabase.UNIQUE_ITEMS:
		assert_ne(
			String(u.get("transform", "")), "", "%s has no effect id" % u.get("id")
		)


func test_requires_transform_points_at_real_tree_entry() -> void:
	for u in ItemDatabase.UNIQUE_ITEMS:
		var req: String = String(u.get("requires_transform", ""))
		if req == "":
			continue
		assert_true(
			_requirable_ids.has(req),
			"%s requires unknown tree skill/variant %s" % [u.get("id"), req]
		)
		# Conditional uniques must use their OWN effect id, distinct from the
		# skill/variant they enhance (otherwise equipping the item would
		# masquerade as having made that choice).
		assert_ne(
			String(u.get("transform", "")), req, "%s effect id collides with its requirement" % u.get("id")
		)
		assert_ne(String(u.get("requires_label", "")), "", "%s missing requires_label" % u.get("id"))


func test_equipped_unique_grants_no_node_ranks() -> void:
	# The old ITEM_NODE_GRANTS path is gone: wearing Bone Spear no longer
	# grants Crimson Vow ranks.
	var uq := ItemInstance.new()
	uq.is_unique = true
	uq.unique_id = "bone_spear_unique"
	uq.rarity = ItemDatabase.RARITY_UNIQUE
	InventorySystem.equipment[ItemDatabase.SLOT_WEAPON_MAIN] = uq
	InventorySystem._rebuild_transform_cache()
	assert_eq(GameManager.get_talent_rank("necro_pact_power"), 0)
	assert_true(InventorySystem.has_unique("bone_spear_splinters"), "effect id active")


func test_has_unique_sees_talent_transforms() -> void:
	# Talent nodes that reuse unique effect ids (hexen_bloodmoon, storm_stormveil,
	# stone_armor_grinder, …) activate the effect WITHOUT the item: has_unique
	# scans the local player's SkillSystem.active_transforms.
	var holder := Node2D.new()
	holder.add_to_group("player")
	var ss := SkillSystem.new()
	ss.name = "SkillSystem"
	holder.add_child(ss)
	add_child_autofree(holder)
	assert_false(InventorySystem.has_unique("hexen_bloodmoon"))
	ss.apply_transform(0, "hexen_bloodmoon")
	assert_true(InventorySystem.has_unique("hexen_bloodmoon"), "talent transform = effect on")


func test_legacy_slot_transform_path_removed() -> void:
	# Equipped uniques never swap a slot's skill anymore.
	var holder := Node2D.new()
	var ss := SkillSystem.new()
	ss.name = "SkillSystem"
	holder.add_child(ss)
	add_child_autofree(holder)
	var uq := ItemInstance.new()
	uq.is_unique = true
	uq.unique_id = "bone_spear_unique"
	uq.rarity = ItemDatabase.RARITY_UNIQUE
	InventorySystem.equipment[ItemDatabase.SLOT_WEAPON_MAIN] = uq
	InventorySystem._rebuild_transform_cache()
	assert_eq(ss.get_transform(0), "", "no item-driven slot swap")
