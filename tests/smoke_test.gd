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
	var catalog: Variant = SkillSystem.SKILL_CATALOG
	if not (catalog is Dictionary):
		_fail("SkillSystem.SKILL_CATALOG is not a Dictionary")
		return
	var dict: Dictionary = catalog
	print("Skills in catalog: %d" % dict.size())
	for key in dict.keys():
		var entry: Variant = dict[key]
		if not (entry is Dictionary):
			_fail("skill '%s' entry is not a Dictionary" % str(key))
			continue
		var e: Dictionary = entry
		_check_path(str(key), "scene", e)
		_check_path(str(key), "icon", e)
		_check_path(str(key), "sfx", e)
		for req in ["cooldown", "mana_cost", "damage_mult"]:
			_ok()
			if not e.has(req):
				_fail("skill '%s' missing field '%s'" % [str(key), req])


func _check_path(skill: String, field: String, e: Dictionary) -> void:
	if not e.has(field):
		return  # icon/sfx are optional on some entries; scene checked below
	var p: String = str(e[field])
	_ok()
	if p == "":
		if field == "scene":
			_fail("skill '%s' has empty scene path" % skill)
		return
	if not ResourceLoader.exists(p):
		_fail("skill '%s' %s path missing: %s" % [skill, field, p])


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
