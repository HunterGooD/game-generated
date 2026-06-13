extends GutTest

# SpecPaths data integrity: every class has 3 paths and every path's R ability
# resolves to a real SkillDefinition. Slot transforms moved to SkillBlocks
# (`requires_path` sub-choices) — paths must NOT define them anymore.

const CLASSES := ["mage", "barbarian", "rogue", "stormcaller", "hexen", "necromancer", "druid"]


func test_each_class_has_three_paths() -> void:
	for cls in CLASSES:
		assert_eq(SpecPaths.paths_for(cls).size(), 3, "%s should have 3 spec paths" % cls)


func test_path_ability_resolves_in_catalog() -> void:
	for cls in CLASSES:
		for p in SpecPaths.paths_for(cls):
			var ability: String = String(p.get("ability", ""))
			if ability != "":
				assert_not_null(
					SkillCatalog.get_def(ability), "%s ability '%s' missing from catalog" % [cls, ability]
				)


func test_paths_define_no_slot_transforms() -> void:
	# Ascension slot swaps live in SkillBlocks as requires_path sub-choices now;
	# a transforms key here would silently do nothing (player.gd no longer applies it).
	for cls in CLASSES:
		for p in SpecPaths.paths_for(cls):
			assert_false(
				p.has("transforms"),
				"%s path '%s' still defines transforms — move them to SkillBlocks" % [cls, p.get("id")]
			)


func test_find_returns_matching_path() -> void:
	var p: Dictionary = SpecPaths.find("stormcaller", "tempest_lord")
	assert_eq(String(p.get("id", "")), "tempest_lord")
	assert_eq(String(p.get("passive", "")), "static_cascade")
