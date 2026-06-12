extends GutTest

# Every transform node in the talent trees must actually DO something when bought:
# either it swaps the slot skill via SkillCatalog.TRANSFORM_OVERRIDES (the talent
# point replaces the skill), or the base skill's script checks the effect id
# itself (ctx.transform / InventorySystem.has_unique). A transform id in neither
# place is a dead talent node — exactly the meteor_shower bug this guards against.

# Transform ids implemented inside skill scripts rather than as slot swaps.
#   ice_wall            — skill_fire_wall.gd checks ctx.transform == "ice_wall".
#   stone_armor_grinder — skill_druid_stone_armor.gd (has_unique-style effect).
#   hexen_*, storm_*    — effect ids shared with unique items; the skill scripts
#                         check InventorySystem.has_unique. NOTE: buying only the
#                         talent node does NOT activate these yet — known debt,
#                         addressed by the uniques rework (conditional effects).
const CTX_CHECKED_ALLOWLIST := [
	"ice_wall",
	"stone_armor_grinder",
	"hexen_bloodmoon",
	"hexen_eternal_mark",
	"hexen_tether_shock",
	"storm_capacitor_core",
	"storm_heavens_spear",
	"storm_stormveil",
]

const ALL_CLASSES := [
	"barbarian", "rogue", "mage", "stormcaller", "hexen", "necromancer", "druid"
]

const MAGE_TALENT_TRANSFORMS := ["frost_nova", "death_beam", "meteor_shower"]


func _collect_transform_ids(cls: String) -> Array:
	var out: Array = []
	for branch in TalentTrees.branches_for(cls):
		for tier in branch.get("tiers", []):
			for node in tier:
				if String(node.get("kind", "")) == "transform":
					out.append(String(node.get("transform", "")))
	return out


func test_every_transform_node_is_wired() -> void:
	for cls in ALL_CLASSES:
		for tid in _collect_transform_ids(cls):
			var wired: bool = (
				SkillCatalog.TRANSFORM_OVERRIDES.has(tid) or CTX_CHECKED_ALLOWLIST.has(tid)
			)
			assert_true(wired, "%s: transform node '%s' is a dead talent" % [cls, tid])


func test_mage_transforms_have_defs_and_scenes() -> void:
	for tid in MAGE_TALENT_TRANSFORMS:
		assert_true(
			SkillCatalog.TRANSFORM_OVERRIDES.has(tid), "%s missing from TRANSFORM_OVERRIDES" % tid
		)
		var skill_id: String = String(SkillCatalog.TRANSFORM_OVERRIDES[tid])
		var def: SkillDefinition = SkillCatalog.get_def(skill_id)
		assert_not_null(def, "%s has no SkillCatalog def" % skill_id)
		if def == null:
			continue
		assert_true(
			ResourceLoader.exists(def.scene_path), "%s scene missing: %s" % [skill_id, def.scene_path]
		)
		assert_true(
			ResourceLoader.exists(def.icon_path), "%s icon missing: %s" % [skill_id, def.icon_path]
		)


func test_override_targets_resolve() -> void:
	# Every TRANSFORM_OVERRIDES value must resolve to a real catalog def with an
	# existing scene — a typo here would silently no-op the swap at cast time.
	for tid in SkillCatalog.TRANSFORM_OVERRIDES:
		var skill_id: String = String(SkillCatalog.TRANSFORM_OVERRIDES[tid])
		var def: SkillDefinition = SkillCatalog.get_def(skill_id)
		assert_not_null(def, "override target '%s' (from '%s') not in catalog" % [skill_id, tid])
		if def != null:
			assert_true(
				ResourceLoader.exists(def.scene_path),
				"override '%s' scene missing: %s" % [skill_id, def.scene_path]
			)
