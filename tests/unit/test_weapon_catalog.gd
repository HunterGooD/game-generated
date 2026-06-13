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


func test_authored_weapons_have_no_active_combo() -> void:
	# Behaviour-preserving: the combo machine is dormant until a weapon defines steps.
	for kind in WeaponCatalog.all_kinds():
		assert_eq(WeaponCatalog.get_def(kind).combo.size(), 0, "%s has no live combo yet" % kind)


func test_next_combo_step_advances_within_window_else_resets() -> void:
	# 3-step combo: chaining within the window walks 0->1->2->0 (wraps).
	assert_eq(WeaponDefinition.next_combo_step(3, 0, true), 1)
	assert_eq(WeaponDefinition.next_combo_step(3, 1, true), 2)
	assert_eq(WeaponDefinition.next_combo_step(3, 2, true), 0, "wraps at the end")
	# Window lapsed -> restart at step 0 regardless of current.
	assert_eq(WeaponDefinition.next_combo_step(3, 2, false), 0)
	# No combo -> always 0.
	assert_eq(WeaponDefinition.next_combo_step(0, 0, true), 0)


func test_combo_steps_parse_from_dict() -> void:
	var w := WeaponDefinition.from_dict(
		"test",
		{
			"scene": "x.tscn",
			"combo":
			[
				{"anim": "attack", "dmg_mult": 0.8, "window": 0.6},
				{"anim": "attack2", "dmg_mult": 1.4, "window": 0.0},
			],
		}
	)
	assert_eq(w.combo.size(), 2, "combo steps parsed")
	assert_eq(float(w.combo[1].get("dmg_mult", 1.0)), 1.4, "step fields preserved")


func test_basic_uniques_resolve_with_expected_shape() -> void:
	# All 7 class basic-uniques resolve; unknown -> null.
	for uid in WeaponCatalog.BASIC_UNIQUES.keys():
		assert_not_null(WeaponCatalog.get_unique(uid), "%s resolves" % uid)
	assert_null(WeaponCatalog.get_unique("nope"), "unknown unique -> null")

	# Triple throw: spread of 3 at reduced damage.
	var triple := WeaponCatalog.get_unique("basic_rogue_triple_throw")
	assert_eq(triple.spread.size(), 3, "triple throw fires 3")
	assert_eq(triple.dmg_mult, 0.7, "each dagger reduced")

	# Whipcrack: resolves via the skill catalog (its .tscn was removed — script-
	# carrier), spawned through SkillContext.
	var whip := WeaponCatalog.get_unique("basic_hexen_whipcrack")
	assert_eq(whip.skill_id, "hexen_blood_whip", "whipcrack reuses the blood whip skill")
	assert_eq(whip.via, "context", "whipcrack spawns via SkillContext")
	assert_eq(whip.scene_path, "", "whipcrack has no direct scene (uses skill_id)")
	assert_not_null(SkillCatalog.get_def("hexen_blood_whip"), "blood whip still in skill catalog")

	# Melee-skin unique carries theme + core colour for the swing.
	var tonfa := WeaponCatalog.get_unique("basic_storm_voltaic_tonfa")
	assert_eq(tonfa.melee_theme, "storm")
	assert_eq(tonfa.anchor, "global")
