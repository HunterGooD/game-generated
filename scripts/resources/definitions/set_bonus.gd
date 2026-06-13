class_name SetBonus
extends RefCounted

# One tier of an item set's bonus (the 2/4/5-piece reward). Union of the fields
# the different tiers use: `stats` (flat stat bonus, 2pc), `effect` (named gameplay
# hook, 5pc), `grants` / `grants_by_class` (skill-tree node grant, 4pc). `label`
# is the tooltip line. Missing fields default empty, so an absent tier is just an
# all-empty SetBonus.

var label: String = ""
var stats: Dictionary = {}
var effect: String = ""
var grants: Dictionary = {}
var grants_by_class: Dictionary = {}


static func from_dict(d: Dictionary) -> SetBonus:
	var b := SetBonus.new()
	b.label = String(d.get("label", ""))
	b.stats = (d.get("stats", {}) as Dictionary).duplicate()
	b.effect = String(d.get("effect", ""))
	b.grants = (d.get("grants", {}) as Dictionary).duplicate()
	b.grants_by_class = (d.get("grants_by_class", {}) as Dictionary).duplicate()
	return b
