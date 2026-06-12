extends GutTest

# Crafting-material wallet (GameManager) + salvage economy (InventorySystem).


func before_each() -> void:
	GameManager.gold = 0
	GameManager.materials = {"scrap": 0, "cloth": 0, "essence": 0}
	GameManager.set_stones = {}
	InventorySystem.inventory.clear()


func after_each() -> void:
	GameManager.gold = 0
	GameManager.materials = {"scrap": 0, "cloth": 0, "essence": 0}
	GameManager.set_stones = {}
	InventorySystem.inventory.clear()


func _mk_item(rarity: String, ilvl: int, base_id: String = "iron_helmet") -> ItemInstance:
	var it := ItemInstance.new()
	it.base_id = base_id
	it.rarity = rarity
	it.ilvl = ilvl
	return it


# ── wallet ────────────────────────────────────────────────────────────────────
func test_add_and_get_materials() -> void:
	GameManager.add_materials({"scrap": 5, "essence": 2})
	assert_eq(GameManager.get_material("scrap"), 5)
	assert_eq(GameManager.get_material("cloth"), 0)
	assert_eq(GameManager.get_material("essence"), 2)


func test_materials_never_negative() -> void:
	GameManager.add_materials({"scrap": -10})
	assert_eq(GameManager.get_material("scrap"), 0)


func test_can_afford_mixed_cost() -> void:
	GameManager.gold = 100
	GameManager.add_materials({"scrap": 3})
	assert_true(GameManager.can_afford_cost({"gold": 100, "scrap": 3}))
	assert_false(GameManager.can_afford_cost({"gold": 101, "scrap": 3}))
	assert_false(GameManager.can_afford_cost({"gold": 100, "scrap": 4}))
	assert_false(GameManager.can_afford_cost({}), "empty cost = unavailable")


func test_spend_cost_atomic() -> void:
	GameManager.gold = 50
	GameManager.add_materials({"cloth": 2})
	# Unaffordable (needs 3 cloth) — nothing deducted.
	assert_false(GameManager.spend_cost({"gold": 10, "cloth": 3}))
	assert_eq(GameManager.gold, 50)
	assert_eq(GameManager.get_material("cloth"), 2)
	# Affordable — everything deducted.
	assert_true(GameManager.spend_cost({"gold": 10, "cloth": 2}))
	assert_eq(GameManager.gold, 40)
	assert_eq(GameManager.get_material("cloth"), 0)


func test_spend_cost_with_stones() -> void:
	GameManager.add_set_stone("hunters_oath", 2)
	assert_true(GameManager.can_afford_cost({"stones": {"hunters_oath": 2}}))
	assert_false(GameManager.can_afford_cost({"stones": {"hunters_oath": 3}}))
	assert_true(GameManager.spend_cost({"stones": {"hunters_oath": 2}}))
	assert_eq(GameManager.get_set_stones("hunters_oath"), 0)


func test_reset_run_clears_wallet() -> void:
	GameManager.add_materials({"scrap": 9, "cloth": 9, "essence": 9})
	GameManager.add_set_stone("hunters_oath")
	GameManager.reset_run()
	assert_eq(GameManager.get_material("scrap"), 0)
	assert_eq(GameManager.get_material("essence"), 0)
	assert_eq(GameManager.get_set_stones("hunters_oath"), 0)


# ── salvage table ─────────────────────────────────────────────────────────────
func test_salvage_materials_by_slot() -> void:
	# Weapons + heavy armor → scrap; light armor + jewelry → cloth.
	var w: Dictionary = ItemDatabase.salvage_materials_for(
		ItemDatabase.SLOT_WEAPON_MAIN, ItemDatabase.RARITY_COMMON, 1
	)
	assert_true(w.has("scrap"), "weapon salvages to scrap")
	var b: Dictionary = ItemDatabase.salvage_materials_for(
		ItemDatabase.SLOT_BOOTS, ItemDatabase.RARITY_COMMON, 1
	)
	assert_true(b.has("cloth"), "boots salvage to cloth")
	var h: Dictionary = ItemDatabase.salvage_materials_for(
		ItemDatabase.SLOT_HELMET, ItemDatabase.RARITY_COMMON, 1
	)
	assert_true(h.has("scrap"), "helmet salvages to scrap")


func test_salvage_essence_by_rarity() -> void:
	var expectations := {
		ItemDatabase.RARITY_COMMON: 1,
		ItemDatabase.RARITY_RARE: 2,
		ItemDatabase.RARITY_LEGENDARY: 4,
		ItemDatabase.RARITY_UNIQUE: 8,
	}
	for rarity in expectations:
		var mats: Dictionary = ItemDatabase.salvage_materials_for(
			ItemDatabase.SLOT_HELMET, String(rarity), 1
		)
		assert_eq(
			int(mats.get("essence", 0)), int(expectations[rarity]), "essence for %s" % rarity
		)


func test_salvage_item_grants_and_removes() -> void:
	var it := _mk_item(ItemDatabase.RARITY_RARE, 1)
	InventorySystem.inventory.append(it)
	var mats: Dictionary = InventorySystem.salvage_item(it)
	assert_false(mats.is_empty(), "salvage returns the granted materials")
	assert_false(InventorySystem.inventory.has(it), "item removed from the bag")
	assert_eq(GameManager.get_material("essence"), 2, "rare yields 2 essence")
	assert_gt(GameManager.get_material("scrap"), 0, "helmet yields scrap")


# ── merchant cost dicts ───────────────────────────────────────────────────────
func test_merchant_costs_are_dicts() -> void:
	var it := _mk_item(ItemDatabase.RARITY_RARE, 4)
	assert_false(InventorySystem.upgrade_cost(it).is_empty())
	assert_false(InventorySystem.reroll_cost(it).is_empty())
	assert_false(InventorySystem.add_affix_cost(it).is_empty())
	# Uniques can't be modified.
	var uq := ItemInstance.new()
	uq.is_unique = true
	uq.unique_id = "pyrocrown"
	uq.rarity = ItemDatabase.RARITY_UNIQUE
	assert_true(InventorySystem.upgrade_cost(uq).is_empty())
	assert_true(InventorySystem.reroll_cost(uq).is_empty())


func test_upgrade_spends_materials() -> void:
	var it := _mk_item(ItemDatabase.RARITY_COMMON, 1)
	InventorySystem.inventory.append(it)
	var cost: Dictionary = InventorySystem.upgrade_cost(it)
	GameManager.gold = int(cost.get("gold", 0))
	GameManager.add_materials({"scrap": int(cost.get("scrap", 0))})
	assert_true(InventorySystem.upgrade_item(it))
	assert_eq(it.ilvl, 2)
	assert_eq(GameManager.gold, 0)
	assert_eq(GameManager.get_material("scrap"), 0)
	# Broke now — second upgrade refused.
	assert_false(InventorySystem.upgrade_item(it))
	assert_eq(it.ilvl, 2)
