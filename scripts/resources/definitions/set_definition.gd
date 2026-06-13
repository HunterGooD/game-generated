class_name SetDefinition
extends RefCounted

# Typed view of one entry in ItemDatabase.SETS. SETS stays the authoring source;
# ItemDatabase builds one definition per id (cached) and find_set() returns it.
# The 2/4/5-piece tiers are SetBonus sub-objects; use bonus_for(tier) for the
# dynamic-tier iteration the character sheet / set-bonus summary do.
#
# Unknown id -> unknown() placeholder (name == set_id, empty bonuses) so callers
# never get null; guard with ItemDatabase.has_set() to detect a genuine miss.

var id: String = ""
var name: String = ""
var flavor: String = ""
var classes: Array = []
var theme_affixes: Array = []
var bonus2: SetBonus = SetBonus.new()
var bonus4: SetBonus = SetBonus.new()
var bonus5: SetBonus = SetBonus.new()


static func from_dict(set_id: String, d: Dictionary) -> SetDefinition:
	var s := SetDefinition.new()
	s.id = set_id
	s.name = String(d.get("name", set_id))
	s.flavor = String(d.get("flavor", ""))
	s.classes = (d.get("classes", []) as Array).duplicate()
	s.theme_affixes = (d.get("theme_affixes", []) as Array).duplicate()
	s.bonus2 = SetBonus.from_dict(d.get("bonus2", {}))
	s.bonus4 = SetBonus.from_dict(d.get("bonus4", {}))
	s.bonus5 = SetBonus.from_dict(d.get("bonus5", {}))
	return s


static func unknown(set_id: String) -> SetDefinition:
	var s := SetDefinition.new()
	s.id = set_id
	s.name = set_id
	return s


# The SetBonus for an N-piece threshold (2 / 4 / 5). Empty SetBonus otherwise.
func bonus_for(tier: int) -> SetBonus:
	match tier:
		2:
			return bonus2
		4:
			return bonus4
		5:
			return bonus5
	return SetBonus.new()
