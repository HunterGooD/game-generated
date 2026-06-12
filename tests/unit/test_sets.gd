extends GutTest

# Set items: catalog integrity, instance counting (jewelry cap), rolling,
# stones + crafting, serialization.

const ALL_CLASSES := [
	"barbarian", "rogue", "mage", "stormcaller", "hexen", "necromancer", "druid"
]


func before_each() -> void:
	_reset()


func after_each() -> void:
	_reset()


func _reset() -> void:
	GameManager.gold = 0
	GameManager.materials = {"scrap": 0, "cloth": 0, "essence": 0}
	GameManager.set_stones = {}
	InventorySystem.inventory.clear()
	InventorySystem.equipment.clear()
	InventorySystem._rebuild_transform_cache()


func _node_exists(class_id: String, node_id: String) -> bool:
	for branch in TalentTrees.branches_for(class_id):
		for tier in branch.get("tiers", []):
			for node in tier:
				if String(node.get("id", "")) == node_id:
					return true
	return false


func _mk_set_piece(set_id: String, base_id: String) -> ItemInstance:
	var it := ItemInstance.new()
	it.base_id = base_id
	it.rarity = ItemDatabase.RARITY_SET
	it.set_id = set_id
	it.ilvl = 1
	return it


# ── catalog integrity ─────────────────────────────────────────────────────────
func test_sets_catalog_shape() -> void:
	assert_eq(ItemDatabase.SETS.size(), 9, "2 generic + 7 class sets")
	var generic: int = 0
	for sid in ItemDatabase.SETS:
		var s: Dictionary = ItemDatabase.SETS[sid]
		if (s.get("classes", []) as Array).is_empty():
			generic += 1
		for key in ["name", "theme_affixes", "bonus2", "bonus4", "bonus5"]:
			assert_true(s.has(key), "%s missing %s" % [sid, key])
		assert_ne(String(s.get("bonus5", {}).get("effect", "")), "", "%s 5pc effect id" % sid)
	assert_eq(generic, 2, "exactly two generic sets")


func test_theme_affixes_exist_in_pool() -> void:
	for sid in ItemDatabase.SETS:
		for aid in ItemDatabase.SETS[sid].get("theme_affixes", []):
			assert_false(
				ItemDatabase.find_affix(String(aid)).is_empty(),
				"%s theme affix %s not in AFFIX_POOL" % [sid, aid]
			)


func test_bonus4_nodes_exist() -> void:
	for sid in ItemDatabase.SETS:
		var classes: Array = ItemDatabase.SETS[sid].get("classes", [])
		if classes.is_empty():
			# Generic: per-class grants must cover all 7 classes with real nodes.
			for cls in ALL_CLASSES:
				var grant: Dictionary = ItemDatabase.set_node_grant(String(sid), String(cls))
				assert_false(grant.is_empty(), "%s has no grant for %s" % [sid, cls])
				assert_true(
					_node_exists(String(cls), String(grant.get("node", ""))),
					"%s grant node %s missing in %s tree" % [sid, grant.get("node"), cls]
				)
		else:
			var cls2: String = String(classes[0])
			var grant2: Dictionary = ItemDatabase.set_node_grant(String(sid), cls2)
			assert_true(
				_node_exists(cls2, String(grant2.get("node", ""))),
				"%s grant node %s missing in %s tree" % [sid, grant2.get("node"), cls2]
			)


# ── piece counting ────────────────────────────────────────────────────────────
func test_every_jewelry_piece_counts() -> void:
	# Ring + amulet of one set is a valid 2-piece (the second ring slot too).
	InventorySystem.equipment[ItemDatabase.SLOT_AMULET] = _mk_set_piece(
		"hunters_oath", "gothic_amulet"
	)
	InventorySystem.equipment[ItemDatabase.SLOT_RING_2] = _mk_set_piece(
		"hunters_oath", "signet_ring"
	)
	var counts: Dictionary = InventorySystem.get_set_piece_counts()
	assert_eq(int(counts.get("hunters_oath", 0)), 2, "amulet + ring2 = 2 pieces")
	assert_eq(InventorySystem.get_total("crit_chance"), 6.0, "2pc bonus active from jewelry")
	# Three sets at once across the doll all count independently.
	InventorySystem.equipment[ItemDatabase.SLOT_HELMET] = _mk_set_piece(
		"bastion_vow", "iron_helmet"
	)
	InventorySystem.equipment[ItemDatabase.SLOT_CHEST] = _mk_set_piece(
		"bastion_vow", "plate_chest"
	)
	InventorySystem.equipment[ItemDatabase.SLOT_RING_1] = _mk_set_piece(
		"cinderweave", "signet_ring"
	)
	counts = InventorySystem.get_set_piece_counts()
	assert_eq(int(counts.get("hunters_oath", 0)), 2)
	assert_eq(int(counts.get("bastion_vow", 0)), 2)
	assert_eq(int(counts.get("cinderweave", 0)), 1)
	assert_eq(InventorySystem.get_total("max_hp"), 40.0, "second set's 2pc active too")


func test_five_pieces_activate_effect() -> void:
	InventorySystem.equipment[ItemDatabase.SLOT_HELMET] = _mk_set_piece(
		"hunters_oath", "iron_helmet"
	)
	InventorySystem.equipment[ItemDatabase.SLOT_CHEST] = _mk_set_piece(
		"hunters_oath", "plate_chest"
	)
	InventorySystem.equipment[ItemDatabase.SLOT_GLOVES] = _mk_set_piece(
		"hunters_oath", "iron_gauntlets"
	)
	InventorySystem.equipment[ItemDatabase.SLOT_AMULET] = _mk_set_piece(
		"hunters_oath", "gothic_amulet"
	)
	InventorySystem.equipment[ItemDatabase.SLOT_RING_2] = _mk_set_piece(
		"hunters_oath", "signet_ring"
	)
	var counts: Dictionary = InventorySystem.get_set_piece_counts()
	assert_eq(int(counts.get("hunters_oath", 0)), 5, "3 armor + 2 jewelry = 5")
	InventorySystem._rebuild_transform_cache()
	assert_true(InventorySystem.has_set_effect("hunt_mark"), "5pc effect active")


func test_two_piece_stat_bonus() -> void:
	InventorySystem.equipment[ItemDatabase.SLOT_HELMET] = _mk_set_piece(
		"bastion_vow", "iron_helmet"
	)
	assert_eq(InventorySystem.get_total("max_hp"), 0.0, "1 piece = no bonus")
	InventorySystem.equipment[ItemDatabase.SLOT_CHEST] = _mk_set_piece(
		"bastion_vow", "plate_chest"
	)
	assert_eq(InventorySystem.get_total("max_hp"), 40.0, "2pc grants +40 HP")
	assert_eq(InventorySystem.get_total("armor"), 10.0, "2pc grants +10 armor")


# ── rolling ───────────────────────────────────────────────────────────────────
func test_roll_set_never_weapons_three_affixes() -> void:
	for _i in 200:
		var it: ItemInstance = LootRoller._roll_set(3, "mage")
		assert_not_null(it)
		if it == null:
			continue
		assert_eq(it.rarity, ItemDatabase.RARITY_SET)
		assert_ne(it.set_id, "", "set_id assigned at roll")
		assert_true(
			ItemDatabase.set_eligible_slots().has(it.get_slot()),
			"set items only on armor/jewelry (got slot %d)" % it.get_slot()
		)
		assert_eq(it.affixes.size(), 3, "set items carry exactly 3 affixes")
		# Set must be eligible for the class (generic or mage's own).
		var classes: Array = ItemDatabase.find_set(it.set_id).get("classes", [])
		assert_true(classes.is_empty() or classes.has("mage"), "no foreign class sets")
		# At least 2 affixes from the theme pool.
		var theme: Array = ItemDatabase.find_set(it.set_id).get("theme_affixes", [])
		var theme_n: int = 0
		for a in it.affixes:
			if theme.has(String(a.get("id", ""))):
				theme_n += 1
		assert_gte(theme_n, 2, "2 of 3 affixes from the set theme")


# ── stones + crafting ─────────────────────────────────────────────────────────
func test_salvage_set_item_yields_stone() -> void:
	var it := _mk_set_piece("cinderweave", "iron_helmet")
	InventorySystem.inventory.append(it)
	var mats: Dictionary = InventorySystem.salvage_item(it)
	assert_eq(GameManager.get_set_stones("cinderweave"), 1, "stone of the set granted")
	assert_eq(int(mats.get("essence", 0)) + 0, 4, "set salvage = 4 essence")


func test_craft_set_item() -> void:
	var it := ItemInstance.new()
	it.base_id = "iron_greaves"
	it.rarity = ItemDatabase.RARITY_RARE
	it.ilvl = 4
	InventorySystem.inventory.append(it)
	GameManager.add_set_stone("hunters_oath", 2)
	GameManager.add_materials({"essence": 99})
	var cost: Dictionary = InventorySystem.craft_cost(it, "hunters_oath")
	assert_false(cost.is_empty(), "rare boots are craftable")
	assert_true(InventorySystem.craft_set_item(it, "hunters_oath"))
	assert_eq(it.rarity, ItemDatabase.RARITY_SET)
	assert_eq(it.set_id, "hunters_oath")
	assert_eq(it.affixes.size(), 3)
	assert_eq(GameManager.get_set_stones("hunters_oath"), 0, "stones consumed")


func test_craft_refusals() -> void:
	GameManager.add_set_stone("hunters_oath", 9)
	GameManager.add_materials({"essence": 99})
	# Unique → refused.
	var uq := ItemInstance.new()
	uq.is_unique = true
	uq.unique_id = "pyrocrown"
	uq.rarity = ItemDatabase.RARITY_UNIQUE
	assert_true(InventorySystem.craft_cost(uq, "hunters_oath").is_empty())
	# Weapon → refused.
	var w := ItemInstance.new()
	w.base_id = "mage_wand"
	w.rarity = ItemDatabase.RARITY_RARE
	assert_true(InventorySystem.craft_cost(w, "hunters_oath").is_empty())
	# Already a set item → refused.
	var s := _mk_set_piece("cinderweave", "iron_helmet")
	assert_true(InventorySystem.craft_cost(s, "hunters_oath").is_empty())
	# Unknown set → refused.
	var ok := ItemInstance.new()
	ok.base_id = "iron_helmet"
	ok.rarity = ItemDatabase.RARITY_COMMON
	assert_true(InventorySystem.craft_cost(ok, "no_such_set").is_empty())


# ── serialization / 4pc grants ────────────────────────────────────────────────
func test_set_id_round_trip() -> void:
	var it := _mk_set_piece("wildheart_totems", "iron_greaves")
	it.affixes = [{"id": "max_hp", "value": 12.0, "title": "Max HP", "suffix": ""}]
	var copy := ItemInstance.from_dict(it.to_dict())
	assert_eq(copy.set_id, "wildheart_totems")
	assert_eq(copy.rarity, ItemDatabase.RARITY_SET)
	# Old clients' dicts (no set_id key) default to "".
	var d: Dictionary = it.to_dict()
	d.erase("set_id")
	assert_eq(ItemInstance.from_dict(d).set_id, "")


func test_four_piece_grants_node_ranks() -> void:
	var prev_class: String = GameManager.player_class
	GameManager.player_class = "mage"
	InventorySystem.equipment[ItemDatabase.SLOT_HELMET] = _mk_set_piece(
		"cinderweave", "iron_helmet"
	)
	InventorySystem.equipment[ItemDatabase.SLOT_CHEST] = _mk_set_piece(
		"cinderweave", "plate_chest"
	)
	InventorySystem.equipment[ItemDatabase.SLOT_GLOVES] = _mk_set_piece(
		"cinderweave", "iron_gauntlets"
	)
	assert_eq(TalentTrees.set_grant_ranks("mt_radius"), 0, "3 pieces — no grant yet")
	InventorySystem.equipment[ItemDatabase.SLOT_BOOTS] = _mk_set_piece(
		"cinderweave", "iron_greaves"
	)
	assert_eq(TalentTrees.set_grant_ranks("mt_radius"), 2, "4 pieces — +2 ranks")
	GameManager.player_class = prev_class
