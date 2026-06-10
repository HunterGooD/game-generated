extends GutTest

# DungeonAffixes data table — the single source of truth for the 6 affixes the Rust
# generator rolls. Ids must match echoes-dungeon's affix.rs (as_str()); negatives are
# shown on the map, positives stay hidden until entry.

const EXPECTED_NEG := ["suffocating_gloom", "volatile_spheres", "heavens_wrath"]
const EXPECTED_POS := ["gold_vein", "echo_of_power", "fortunes_favor"]


func after_each() -> void:
	# Tests below tweak global dungeon-luck state — always restore it.
	if GameManager:
		GameManager.dungeon_loot_luck = 0.0
		GameManager.dungeon_extra_reel = false


func test_all_six_affixes_present() -> void:
	for id in EXPECTED_NEG + EXPECTED_POS:
		assert_true(DungeonAffixes.has(id), "missing affix def: %s" % id)
	assert_eq(DungeonAffixes.DEFS.size(), 6, "exactly six affixes in the pool")


func test_negatives_are_negative_and_visible() -> void:
	for id in EXPECTED_NEG:
		assert_true(DungeonAffixes.is_negative(id), "%s should be negative" % id)
		assert_false(DungeonAffixes.is_positive(id), "%s not positive" % id)
		assert_false(DungeonAffixes.is_hidden(id), "%s shown on the map" % id)


func test_positives_are_positive_and_hidden() -> void:
	for id in EXPECTED_POS:
		assert_true(DungeonAffixes.is_positive(id), "%s should be positive" % id)
		assert_true(DungeonAffixes.is_hidden(id), "%s hidden until entry" % id)


func test_display_name_and_desc_nonempty() -> void:
	for id in EXPECTED_NEG + EXPECTED_POS:
		assert_ne(DungeonAffixes.display_name(id), "", "%s has a name" % id)
		assert_ne(DungeonAffixes.description(id), "", "%s has a description" % id)


func test_unknown_id_is_safe() -> void:
	assert_false(DungeonAffixes.has("nope"))
	assert_eq(DungeonAffixes.get_def("nope"), {})
	assert_eq(DungeonAffixes.display_name("nope"), "nope", "falls back to the id")


# ids_from() splits the bridge's affix dictionaries by polarity.
func test_ids_from_filters_by_polarity() -> void:
	var affixes := [
		{"id": "suffocating_gloom", "polarity": -1, "hidden": false, "magnitude": 1.0},
		{"id": "gold_vein", "polarity": 1, "hidden": true, "magnitude": 1.1},
		{"id": "heavens_wrath", "polarity": -1, "hidden": false, "magnitude": 0.9},
	]
	var negs := DungeonAffixes.ids_from(affixes, "negative")
	var poss := DungeonAffixes.ids_from(affixes, "positive")
	assert_eq(negs.size(), 2, "two negatives")
	assert_true("suffocating_gloom" in negs and "heavens_wrath" in negs)
	assert_eq(poss, ["gold_vein"], "one positive")
	assert_eq(DungeonAffixes.ids_from(affixes, "all").size(), 3)


# Fortune's Favor feeds GameManager.dungeon_loot_luck → LootRoller rarity.
func _non_common_fraction() -> float:
	var hits: int = 0
	var n: int = 3000
	for i in n:
		if LootRoller._roll_rarity(5, 0) != ItemDatabase.RARITY_COMMON:
			hits += 1
	return float(hits) / float(n)


func test_loot_luck_raises_rarity() -> void:
	if GameManager == null:
		pass_test("no GameManager in this harness")
		return
	GameManager.dungeon_loot_luck = 0.0
	var f_base := _non_common_fraction()
	GameManager.dungeon_loot_luck = 0.5
	var f_lucky := _non_common_fraction()
	assert_gt(f_lucky, f_base, "Fortune's Favor luck increases non-common drops")
