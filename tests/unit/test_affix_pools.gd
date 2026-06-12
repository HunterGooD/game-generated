extends GutTest

# Slot-restricted affix pools + per-rarity affix counts.

const ARMOR_JEWELRY_SLOTS := [
	ItemDatabase.SLOT_HELMET,
	ItemDatabase.SLOT_CHEST,
	ItemDatabase.SLOT_GLOVES,
	ItemDatabase.SLOT_BOOTS,
	ItemDatabase.SLOT_AMULET,
	ItemDatabase.SLOT_RING_1,
	ItemDatabase.SLOT_RING_2,
]


func after_each() -> void:
	GameManager.gold = 0
	GameManager.materials = {"scrap": 0, "cloth": 0, "essence": 0}


func test_pool_slots_fields_valid() -> void:
	for a in ItemDatabase.AFFIX_POOL:
		assert_true(a.has("slots"), "%s missing slots field" % a.get("id"))
		for s in a.get("slots", []):
			assert_between(
				int(s), 0, ItemDatabase.SLOT_COUNT - 1, "%s has invalid slot" % a.get("id")
			)


func test_every_slot_pool_big_enough() -> void:
	# Unique items roll fixed + 1 extra and legendaries roll 4 distinct — every
	# slot needs at least 5 legal affixes.
	var slots: Array = ARMOR_JEWELRY_SLOTS.duplicate()
	slots.append(ItemDatabase.SLOT_WEAPON_MAIN)
	for slot in slots:
		var pool: Array = ItemDatabase.affixes_for_slot(int(slot))
		assert_gte(pool.size(), 5, "pool too small for slot %d" % int(slot))


func test_slot_pools_respect_restrictions() -> void:
	# gold_gain is boots/jewelry-only; damage never on helmet/chest/boots.
	var helmet_ids: Array = []
	for a in ItemDatabase.affixes_for_slot(ItemDatabase.SLOT_HELMET):
		helmet_ids.append(String(a.get("id", "")))
	assert_does_not_have(helmet_ids, "gold_gain", "no gold_gain on helmets")
	assert_does_not_have(helmet_ids, "damage", "no damage on helmets")
	assert_has(helmet_ids, "cdr", "helmets roll cdr")
	assert_has(helmet_ids, "strength", "attributes are universal")
	var boots_ids: Array = []
	for a in ItemDatabase.affixes_for_slot(ItemDatabase.SLOT_BOOTS):
		boots_ids.append(String(a.get("id", "")))
	assert_has(boots_ids, "move_speed", "boots roll move speed")
	assert_does_not_have(boots_ids, "crit_chance", "no crit on boots")


func test_rolled_items_only_carry_legal_affixes() -> void:
	# Fuzz: every affix on a rolled base item must be legal for its slot.
	for _i in 200:
		var item: ItemInstance = LootRoller._roll_base(
			ItemDatabase.RARITY_LEGENDARY, 5, "mage"
		)
		assert_not_null(item)
		if item == null:
			continue
		var legal: Dictionary = {}
		for a in ItemDatabase.affixes_for_slot(item.get_slot()):
			legal[String(a.get("id", ""))] = true
		for a in item.affixes:
			var aid: String = String(a.get("id", ""))
			assert_true(
				legal.has(aid),
				"illegal affix %s on slot %d (%s)" % [aid, item.get_slot(), item.base_id]
			)


func test_affix_counts_per_rarity() -> void:
	assert_eq(int(ItemDatabase.RARITY_AFFIX_COUNT[ItemDatabase.RARITY_COMMON]), 1)
	assert_eq(int(ItemDatabase.RARITY_AFFIX_COUNT[ItemDatabase.RARITY_RARE]), 2)
	assert_eq(int(ItemDatabase.RARITY_AFFIX_COUNT[ItemDatabase.RARITY_LEGENDARY]), 4)
	assert_eq(int(ItemDatabase.RARITY_AFFIX_COUNT[ItemDatabase.RARITY_UNIQUE]), 5)
	var leg: ItemInstance = LootRoller._roll_base(ItemDatabase.RARITY_LEGENDARY, 3, "mage")
	assert_eq(leg.affixes.size(), 4, "legendary rolls 4 affixes")


func test_unique_rolls_five_affixes() -> void:
	for _i in 20:
		var uq: ItemInstance = LootRoller._roll_unique("mage", 3)
		assert_not_null(uq)
		if uq == null:
			continue
		assert_eq(uq.affixes.size(), 5, "unique %s carries 5 affixes" % uq.unique_id)
		# No duplicate affix ids.
		var seen: Dictionary = {}
		for a in uq.affixes:
			var aid: String = String(a.get("id", ""))
			assert_false(seen.has(aid), "duplicate affix %s on %s" % [aid, uq.unique_id])
			seen[aid] = true


func test_add_affix_bump_thresholds() -> void:
	GameManager.add_materials({"essence": 99, "cloth": 99, "scrap": 99})
	GameManager.gold = 99999
	var it := ItemInstance.new()
	it.base_id = "iron_helmet"
	it.rarity = ItemDatabase.RARITY_COMMON
	it.ilvl = 1
	it.affixes = LootRoller._roll_affixes(1, 1, it.rarity, ItemDatabase.SLOT_HELMET)
	assert_true(InventorySystem.add_affix_to(it))
	assert_eq(it.rarity, ItemDatabase.RARITY_RARE, "2 affixes → rare")
	assert_true(InventorySystem.add_affix_to(it))
	assert_eq(it.rarity, ItemDatabase.RARITY_RARE, "3 affixes still rare")
	assert_true(InventorySystem.add_affix_to(it))
	assert_eq(it.rarity, ItemDatabase.RARITY_LEGENDARY, "4 affixes → legendary")
	# Capped at 4.
	assert_true(InventorySystem.add_affix_cost(it).is_empty(), "no 5th affix")
	assert_false(InventorySystem.add_affix_to(it))
