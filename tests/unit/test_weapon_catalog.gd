extends GutTest

# Guards the basic-attack weapon catalog (WeaponCatalog / WeaponDefinition). Values
# are a 1:1 lift of the old hardcoded `match basic_attack_kind` in player.gd, so
# these assertions also pin that behaviour as player.gd migrates onto the catalog.


func test_all_kinds_resolve_with_expected_fields() -> void:
	var melee := WeaponCatalog.get_def("melee")
	assert_eq(melee.interval, 0.45, "melee cadence")
	assert_eq(melee.spawn, "ahead", "melee spawns in front")
	assert_eq(melee.offset, 30.0, "melee front offset")
	assert_eq(melee.scene_path, "res://scenes/combat/player/melee_swing.tscn")

	var claw := WeaponCatalog.get_def("claw")
	assert_eq(claw.interval, 0.40, "claw is faster than melee")
	assert_eq(claw.scene_path, melee.scene_path, "claw reuses the melee swing scene")

	var dagger := WeaponCatalog.get_def("dagger")
	assert_eq(dagger.interval, 0.40)
	assert_eq(dagger.spawn, "at_origin", "thrown dagger spawns at cast origin")
	assert_eq(dagger.scene_path, "res://scenes/combat/player/thrown_dagger.tscn")

	var bolt := WeaponCatalog.get_def("bolt")
	assert_eq(bolt.interval, 0.55, "bolt cadence")
	assert_eq(bolt.mana_cost, 4.0, "bolt costs mana")
	assert_eq(bolt.team, "player", "bolt passes a team to setup()")
	assert_eq(bolt.scene_path, "res://scenes/combat/player/magic_bolt.tscn")

	assert_eq(melee.sfx_db, -8.0, "melee/dagger sfx volume")
	assert_eq(bolt.sfx_db, -10.0, "bolt sfx is quieter")


func test_unknown_kind_falls_back_to_bolt() -> void:
	# Old `match`'s `_:` branch treated any non-melee/claw/dagger as a ranged bolt.
	var unknown := WeaponCatalog.get_def("nonsense_weapon")
	assert_eq(unknown.scene_path, WeaponCatalog.get_def("bolt").scene_path, "unknown -> bolt scene")
	assert_eq(unknown.mana_cost, 4.0, "unknown -> bolt mana")


func test_has_kind() -> void:
	assert_true(WeaponCatalog.has_kind("melee"))
	assert_false(WeaponCatalog.has_kind("nonsense_weapon"))
	assert_eq(WeaponCatalog.all_kinds().size(), 4, "four authored weapon kinds")
