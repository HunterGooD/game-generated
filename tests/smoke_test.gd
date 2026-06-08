extends Node

# Headless smoke test — catches the class of latent bug that has repeatedly
# surfaced only at play time: broken scene refs, missing asset paths, and
# invalid skill-catalog entries. Pure validation: it loads resources but does
# NOT instantiate gameplay scenes into the tree, so there are no _ready side
# effects and no false failures from autoload/setup expectations.
#
# Runs as a booted scene (not -s) so project autoloads — GameManager,
# SkillSystem, NetManager, … — are present and scene scripts compile.
#
# Run:  godot --headless res://tests/smoke_test.tscn --path .
# Exit: 0 = all checks passed, 1 = at least one failure.

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	print("=== SMOKE TEST ===")
	_check_all_scenes_load()
	_check_skill_catalog()
	_check_composed_skills()
	_check_reward_class_mapping()
	_check_unique_item_transforms()
	print("=== RESULT: %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(msg: String) -> void:
	_failures += 1
	printerr("FAIL: " + msg)


func _ok() -> void:
	_checks += 1


# Every .tscn in the project must load as a PackedScene. A broken ext_resource
# reference (moved script, renamed asset) fails here instead of mid-game.
func _check_all_scenes_load() -> void:
	var scenes: PackedStringArray = _find_files("res://scenes", ".tscn")
	print("Scenes found: %d" % scenes.size())
	for path in scenes:
		_ok()
		if not ResourceLoader.exists(path):
			_fail("scene does not exist: " + path)
			continue
		var packed: Resource = ResourceLoader.load(path)
		if packed == null or not (packed is PackedScene):
			_fail("scene failed to load as PackedScene: " + path)


# Validate the skill catalog: every referenced scene/icon/sfx path must exist,
# and core numeric fields must be present. This is the index that drives skill
# casting, so a typo'd path is a silent dead skill.
func _check_skill_catalog() -> void:
	var ids: Array = SkillCatalog.all_ids()
	print("Skills in catalog: %d" % ids.size())
	for key in ids:
		var def: SkillDefinition = SkillCatalog.get_def(String(key))
		if def == null:
			_fail("skill '%s' has no SkillDefinition" % str(key))
			continue
		_check_def_path(str(key), "scene", def.scene_path)
		_check_def_path(str(key), "icon", def.icon_path)
		_check_def_path(str(key), "sfx", def.sfx_path)
		# Core numeric fields are typed on SkillDefinition — sanity-check ranges.
		_ok()
		if def.cooldown < 0.0:
			_fail("skill '%s' has negative cooldown" % str(key))
		_ok()
		if def.mana_cost < 0.0:
			_fail("skill '%s' has negative mana_cost" % str(key))
		_ok()
		if def.damage_mult < 0.0:
			_fail("skill '%s' has negative damage_mult" % str(key))


# Validate data-driven (composed) skills: any skill carrying `effects` must have
# every block resolve to a non-null SkillEffect with its required field set, so an
# authoring typo in the catalog (bad effect type / missing method) fails here
# instead of casting a silent no-op at play time.
func _check_composed_skills() -> void:
	var composed: int = 0
	for key in SkillCatalog.all_ids():
		var def: SkillDefinition = SkillCatalog.get_def(String(key))
		if def == null or def.effects.is_empty():
			continue
		composed += 1
		for effect in def.effects:
			_ok()
			if effect == null:
				_fail("skill '%s' has an unresolved (null) effect" % str(key))
				continue
			if effect is SkillEffectCasterCall and (effect as SkillEffectCasterCall).method == "":
				_fail("skill '%s' caster_call effect has empty method" % str(key))
			elif effect is SkillEffectGroupCall:
				var g := effect as SkillEffectGroupCall
				if g.group == "" or g.method == "":
					_fail("skill '%s' group_call effect missing group/method" % str(key))
			elif effect is SkillEffectAreaDamage and (effect as SkillEffectAreaDamage).radius <= 0.0:
				_fail("skill '%s' area_damage effect has non-positive radius" % str(key))
			elif effect is SkillEffectSummon:
				var s := effect as SkillEffectSummon
				if s.kind == "" or s.scene_path == "":
					_fail("skill '%s' summon effect missing kind/scene_path" % str(key))
				elif not ResourceLoader.exists(s.scene_path):
					_fail("skill '%s' summon scene missing: %s" % [str(key), s.scene_path])
			elif effect is SkillEffectGroupHeal and (effect as SkillEffectGroupHeal).group == "":
				_fail("skill '%s' group_heal effect has empty group" % str(key))
			elif effect is SkillEffectGroupShield and (effect as SkillEffectGroupShield).groups.is_empty():
				_fail("skill '%s' group_shield effect has no groups" % str(key))
			elif effect is SkillEffectTransform and (effect as SkillEffectTransform).form == "":
				_fail("skill '%s' transform effect has empty form" % str(key))
			elif effect is SkillEffectDash and (effect as SkillEffectDash).max_distance <= 0.0:
				_fail("skill '%s' dash effect has non-positive max_distance" % str(key))
			elif effect is SkillEffectProjectile:
				var pr := effect as SkillEffectProjectile
				if pr.scene_path == "":
					_fail("skill '%s' projectile effect has empty scene_path" % str(key))
				elif not ResourceLoader.exists(pr.scene_path):
					_fail("skill '%s' projectile scene missing: %s" % [str(key), pr.scene_path])
			elif effect is SkillEffectAura:
				var au := effect as SkillEffectAura
				if au.radius <= 0.0 or au.lifetime <= 0.0:
					_fail("skill '%s' aura effect has non-positive radius/lifetime" % str(key))
			elif effect is SkillEffectTelegraph and (effect as SkillEffectTelegraph).radius <= 0.0:
				_fail("skill '%s' telegraph effect has non-positive radius" % str(key))
	print("Composed skills: %d" % composed)


func _check_def_path(skill: String, field: String, p: String) -> void:
	_ok()
	if p == "":
		if field == "scene":
			_fail("skill '%s' has empty scene path" % skill)
		return  # icon/sfx may legitimately be empty on some entries
	if not ResourceLoader.exists(p):
		_fail("skill '%s' %s path missing: %s" % [skill, field, p])


# Every skill modifier and transform unique must resolve to exactly one known
# class — an orphan (unmapped) entry would be offered to the WRONG class (or no
# class) in the level-up overlay. This guards future content additions.
func _check_reward_class_mapping() -> void:
	var classes := {
		"mage": true,
		"barbarian": true,
		"rogue": true,
		"druid": true,
		"necromancer": true,
		"hexen": true,
		"stormcaller": true,
	}
	for m in RewardData.SKILL_MODIFIERS:
		_ok()
		var c: String = RewardData.class_for_entry(m)
		if c == "" or not classes.has(c):
			_fail("modifier '%s' maps to unknown class '%s'" % [str(m.get("id", "?")), c])
	for u in RewardData.UNIQUES:
		# Only transform uniques are class-filtered; basic uniques use basic_for.
		if String(u.get("transform", "")) == "" and String(u.get("basic_for", "")) == "":
			continue
		_ok()
		var cu: String = RewardData.class_for_entry(u)
		if cu == "" or not classes.has(cu):
			_fail("unique '%s' maps to unknown class '%s'" % [str(u.get("id", "?")), cu])
	# Per-class summary so the offered pools are visible at a glance.
	for cls in classes.keys():
		var nmods: int = RewardData.modifiers_for_class(cls).size()
		var nuniq: int = RewardData.uniques_for_class(cls).size()
		print("  class %s: %d modifiers, %d transform-uniques" % [cls, nmods, nuniq])


# Every unique item must actually DO something when equipped. A unique's
# `transform` is consumed one of two ways: a slot-swap (in
# SkillCatalog.TRANSFORM_OVERRIDES, which needs a slot mapping in
# SkillCatalog.ITEM_TRANSFORM_SLOT) or a has_unique() behaviour flag read by a
# skill. This guards the bug where slot-swap item uniques set the flag but never
# swapped.
func _check_unique_item_transforms() -> void:
	var overrides: Dictionary = SkillCatalog.TRANSFORM_OVERRIDES
	var slot_map: Dictionary = SkillCatalog.ITEM_TRANSFORM_SLOT
	for u in ItemDatabase.UNIQUE_ITEMS:
		var tid: String = String(u.get("transform", ""))
		if tid == "":
			continue
		# Slot-swap transforms must have a slot mapping, or equipping does nothing.
		if overrides.has(tid):
			_ok()
			if not slot_map.has(tid):
				_fail(
					(
						"unique item '%s' transform '%s' is a slot-swap but has no _ITEM_TRANSFORM_SLOT mapping — equipping it does nothing"
						% [str(u.get("id", "?")), tid]
					)
				)


# Recursive .tscn walk. Returns absolute res:// paths.
func _find_files(dir_path: String, suffix: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname == "." or fname == "..":
			fname = dir.get_next()
			continue
		var full: String = dir_path + "/" + fname
		if dir.current_is_dir():
			out.append_array(_find_files(full, suffix))
		elif fname.ends_with(suffix):
			out.append(full)
		fname = dir.get_next()
	dir.list_dir_end()
	return out
