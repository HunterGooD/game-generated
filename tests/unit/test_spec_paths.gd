extends GutTest

# SpecPaths data integrity: every class has 3 paths and every path's R ability and
# slot transforms resolve to a real SkillDefinition. Pure data — trivial to test.

const CLASSES := ["mage", "barbarian", "rogue", "stormcaller", "hexen", "necromancer", "druid"]


func test_each_class_has_three_paths() -> void:
	for cls in CLASSES:
		assert_eq(SpecPaths.paths_for(cls).size(), 3, "%s should have 3 spec paths" % cls)


func test_path_ability_and_transforms_resolve_in_catalog() -> void:
	for cls in CLASSES:
		for p in SpecPaths.paths_for(cls):
			var ability: String = String(p.get("ability", ""))
			if ability != "":
				assert_not_null(
					SkillCatalog.get_def(ability), "%s ability '%s' missing from catalog" % [cls, ability]
				)
			for slot_skill in (p.get("transforms", {}) as Dictionary).values():
				assert_not_null(
					SkillCatalog.get_def(String(slot_skill)),
					"%s transform '%s' missing from catalog" % [cls, slot_skill]
				)


func test_find_returns_matching_path() -> void:
	var p: Dictionary = SpecPaths.find("stormcaller", "tempest_lord")
	assert_eq(String(p.get("id", "")), "tempest_lord")
	assert_eq(String(p.get("passive", "")), "static_cascade")
