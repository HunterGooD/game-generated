extends Node

# Headless runtime test for the Phase-E gem system (shards / gem inventory / socketing /
# bonus folding). Run as a SCENE so autoloads exist (see godot-headless-validation):
#   godot --headless res://tests/gem_system_test.tscn --path <project>
# MUTATES user://meta.save — back it up before running (the CI wrapper does).
# Exit 0 = pass, 1 = failure.

var _fails: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_fails += 1
		printerr("  FAIL ", label)


func _ready() -> void:
	print("=== GEM SYSTEM TEST ===")
	var cls: String = "barbarian"
	MetaProgress.respec(cls)

	# Shards wallet.
	var s0: int = MetaProgress.get_shards()
	MetaProgress.add_shards(100)
	_check(MetaProgress.get_shards() == s0 + 100, "add_shards banks 100")
	_check(MetaProgress.spend_shards(40), "spend_shards 40 succeeds")
	_check(not MetaProgress.spend_shards(10 ** 9), "overspend refused")
	_check(MetaProgress.get_shards() == s0 + 60, "wallet math holds")

	# Gem inventory + rolls.
	for i in 30:
		var gid: String = MetaGems.roll(2.0)
		_check(MetaGems.has_gem(gid), "roll returns a real gem (%s)" % gid)
		break  # one labelled check; the loop below counts silently
	var ok_rolls: bool = true
	for i in 200:
		if not MetaGems.has_gem(MetaGems.roll(randf() * 3.0)):
			ok_rolls = false
	_check(ok_rolls, "200 random rolls all valid")
	MetaProgress.add_gem("ruby_fury", 2)
	_check(MetaProgress.gem_count("ruby_fury") >= 2, "add_gem stacks")

	# Socketing requires an ALLOCATED socket node.
	_check(not MetaProgress.socket_gem(cls, "socket_1", "ruby_fury"), "socket refused while node unallocated")
	# Allocate the base socket (level up enough for 1 point if fresh).
	if MetaProgress.points_available(cls) < 1:
		MetaProgress.award_xp(cls, MetaProgress.xp_to_next(cls) - MetaProgress.get_meta_xp(cls))
	_check(MetaProgress.allocate(cls, "socket_1"), "allocate socket_1")
	var rubies_before: int = MetaProgress.gem_count("ruby_fury")
	_check(MetaProgress.socket_gem(cls, "socket_1", "ruby_fury"), "gem seats into allocated socket")
	_check(MetaProgress.gem_count("ruby_fury") == rubies_before - 1, "socketing consumes inventory")
	_check(MetaProgress.socketed_gem(cls, "socket_1") == "ruby_fury", "socket reports its gem")

	# Bonus folding: ruby_fury = +6 damage flat.
	var bonus: Dictionary = MetaProgress.meta_bonus(cls)
	_check(int(bonus.get("damage", 0)) >= 6, "meta_bonus includes the gem's +6 damage")

	# Swap returns the old gem; percent gems fold into meta_percent.
	MetaProgress.add_gem("storm_heart", 1)
	_check(MetaProgress.socket_gem(cls, "socket_1", "storm_heart"), "swap seats the new gem")
	_check(MetaProgress.gem_count("ruby_fury") == rubies_before, "swap returns the old gem")
	var pct: Dictionary = MetaProgress.meta_percent(cls)
	_check(absf(float(pct.get("damage", 0.0)) - 0.04) < 0.0001 or float(pct.get("damage", 0.0)) > 0.0, "meta_percent includes the gem pct")

	# Unsocket + respec both return gems.
	_check(MetaProgress.unsocket_gem(cls, "socket_1"), "unsocket works")
	_check(MetaProgress.gem_count("storm_heart") == 1, "unsocket returns the gem")
	MetaProgress.socket_gem(cls, "socket_1", "storm_heart")
	MetaProgress.respec(cls)
	_check(MetaProgress.gem_count("storm_heart") == 1, "respec returns socketed gems")

	print("=== RESULT: %s ===" % ("PASS" if _fails == 0 else "%d FAILURES" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
