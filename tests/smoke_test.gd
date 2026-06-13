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
	_check_skill_trees()
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
		# A skill resolves its node from a scene OR (script-carrier) a script.
		if def.scene_path != "":
			_check_def_path(str(key), "scene", def.scene_path)
		elif def.script_path != "":
			_check_def_path(str(key), "script", def.script_path)
		else:
			_ok()
			_fail("skill '%s' has neither scene nor script" % str(key))
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
			elif (
				effect is SkillEffectAreaDamage and (effect as SkillEffectAreaDamage).radius <= 0.0
			):
				_fail("skill '%s' area_damage effect has non-positive radius" % str(key))
			elif effect is SkillEffectSummon:
				var s := effect as SkillEffectSummon
				if s.kind == "" or s.scene_path == "":
					_fail("skill '%s' summon effect missing kind/scene_path" % str(key))
				elif not ResourceLoader.exists(s.scene_path):
					_fail("skill '%s' summon scene missing: %s" % [str(key), s.scene_path])
			elif effect is SkillEffectGroupHeal and (effect as SkillEffectGroupHeal).group == "":
				_fail("skill '%s' group_heal effect has empty group" % str(key))
			elif (
				effect is SkillEffectGroupShield
				and (effect as SkillEffectGroupShield).groups.is_empty()
			):
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
# `transform` is a has_unique() behaviour flag read by a skill script — never a
# slot swap. Conditional uniques declare requires_transform: a SkillTrees variant
# (slot-swap in transform_overrides() or a ctx-id in transform_base()) or a base
# skill that's a constellation root the player can build into.
func _check_unique_item_transforms() -> void:
	var overrides: Dictionary = SkillCatalog.transform_overrides()
	var base_skills: Dictionary = SkillCatalog.transform_base()
	# Every root skill_id (constellation roots), across all classes.
	var root_ids := {}
	for cls in GameManager.class_ids():
		for n in SkillTrees.nodes_for(String(cls)):
			if String(n.get("kind", "")) == "skill":
				root_ids[String(n["skill_id"])] = true
	for u in ItemDatabase.UNIQUE_ITEMS:
		var tid: String = String(u.get("transform", ""))
		_ok()
		if tid == "":
			_fail("unique item '%s' has no transform effect id" % str(u.get("id", "?")))
			continue
		var req: String = String(u.get("requires_transform", ""))
		if req == "":
			continue
		_ok()
		if not overrides.has(req) and not base_skills.has(req) and not root_ids.has(req):
			_fail(
				(
					"unique item '%s' requires unknown transform/skill '%s'"
					% [str(u.get("id", "?")), req]
				)
			)


# Skill-tree graph stays consistent: roots resolve in the catalog, passive
# targets map to RewardData modifiers, variants are wired in the transform maps,
# every parent edge points at a real node of the same class, every node has
# coordinates, and item set grants target a real tree/stat node.
func _check_skill_trees() -> void:
	var total_nodes: int = 0
	var overrides: Dictionary = SkillCatalog.transform_overrides()
	var base_skills: Dictionary = SkillCatalog.transform_base()
	var status_elements := ["fire", "bleed", "frost", "poison", "curse"]
	for cls in GameManager.class_ids():
		var nodes: Array = SkillTrees.nodes_for(String(cls))
		var ids := {}
		var max_row: int = 0
		for node in nodes:
			ids[String(node["id"])] = true
			max_row = maxi(max_row, int(node.get("row", 0)))
		# Tree should be at least 6 rows deep (a real downward tree, not pyramids).
		_ok()
		if max_row < 5:
			_fail("class %s tree only %d rows deep (want >=6)" % [cls, max_row + 1])
		for node in nodes:
			total_nodes += 1
			var nid: String = String(node["id"])
			# Every node has grid coordinates.
			_ok()
			if not node.has("col") or not node.has("row"):
				_fail("class %s node '%s' missing col/row" % [cls, nid])
			# Parent edges reference real nodes of this class.
			for pid in SkillTrees.node_parents(node):
				_ok()
				if not ids.has(String(pid)):
					_fail("class %s node '%s' parent '%s' is unknown" % [cls, nid, pid])
			match String(node["kind"]):
				"skill":
					_ok()
					if SkillCatalog.get_def(String(node["skill_id"])) == null:
						_fail("class %s root '%s' missing from catalog" % [cls, node["skill_id"]])
				"passive":
					# On-hit status node: validate its element instead of modifiers.
					if String(node.get("on_hit", "")) != "":
						_ok()
						if not (String(node["on_hit"]) in status_elements):
							_fail(
								"status node '%s' has unknown element '%s'" % [nid, node["on_hit"]]
							)
						continue
					for t in SkillTrees.passive_targets(node):
						_ok()
						# "_cdr"/"_damage" passives are generic (try_cast handles them;
						# no RewardData entry needed).
						var mid: String = String(t["modifier"])
						if (
							not mid.ends_with("_cdr")
							and not mid.ends_with("_damage")
							and not RewardData.has_modifier(mid)
						):
							_fail(
								(
									"passive '%s' references unknown modifier '%s'"
									% [nid, t["modifier"]]
								)
							)
				"variant":
					_ok()
					var t2: String = String(node["transform"])
					if not overrides.has(t2) and not SkillCatalog.CTX_VARIANTS.has(t2):
						_fail("variant '%s' is wired nowhere" % nid)
					_ok()
					if not base_skills.has(t2):
						_fail("variant '%s' has no base-skill binding" % nid)
				"perk":
					_ok()  # inline name/desc, nothing to resolve
	# Set 4pc grants must target a real tree node or a stat-column node.
	for set_id in ItemDatabase.SETS:
		for cls in GameManager.class_ids():
			var grant: Dictionary = ItemDatabase.set_node_grant(String(set_id), String(cls))
			if grant.is_empty():
				continue
			_ok()
			if SkillTrees.find_node(String(cls), String(grant["node"])).is_empty():
				_fail(
					(
						"set '%s' 4pc grant targets unknown node '%s' for class %s"
						% [set_id, grant["node"], cls]
					)
				)
	print("Skill-tree nodes across classes: %d" % total_nodes)


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
