class_name AffixDefinition
extends RefCounted

# Typed view of one entry in ItemDatabase.AFFIX_POOL — the *template* an affix
# rolls from (not the rolled instance stored on an item, which stays a dict built
# by LootRoller.roll_affix_entry). AFFIX_POOL stays the authoring source;
# ItemDatabase builds one definition per id (cached) and find_affix/
# affixes_for_slot hand them out.
#
# `roll_min`/`roll_max` are named to avoid shadowing the min()/max() builtins.
# `slots` empty = the affix is legal on every slot.

var id: String = ""
var title: String = ""
var roll_min: float = 1.0
var roll_max: float = 1.0
var per_ilvl: float = 0.5
var suffix: String = ""
var slots: Array = []


static func from_dict(d: Dictionary) -> AffixDefinition:
	var a := AffixDefinition.new()
	a.id = String(d.get("id", ""))
	a.title = String(d.get("title", a.id.capitalize()))
	a.roll_min = float(d.get("min", 1))
	a.roll_max = float(d.get("max", 1))
	a.per_ilvl = float(d.get("per_ilvl", 0.5))
	a.suffix = String(d.get("suffix", ""))
	a.slots = (d.get("slots", []) as Array).duplicate()
	return a


# Placeholder for an id not in the pool — mirrors the empty-dict defaults the old
# find_affix(id).get(field, default) calls produced. Guard with has_affix() when
# you need to detect a genuine miss.
static func unknown(affix_id: String) -> AffixDefinition:
	var a := AffixDefinition.new()
	a.id = affix_id
	a.title = affix_id.capitalize() if affix_id != "" else "?"
	return a
