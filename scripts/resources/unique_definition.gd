class_name UniqueDefinition
extends RefCounted

# Typed view of one entry in ItemDatabase.UNIQUE_ITEMS. A unique is a superset of
# the generic ItemTemplate view (it adds fixed_affixes + the requires_* gate), so
# to_template() projects it down to an ItemTemplate for ItemInstance.get_template().
# UNIQUE_ITEMS stays the authoring source; find_unique / get_uniques_for_class /
# find_unique_by_transform hand out cached UniqueDefinitions.
#
# `fixed_affixes` entries stay plain {id, value} dicts (LootRoller reads them when
# building the rolled affix list), same as item-instance affixes.

var id: String = ""
var kind: String = "armor"
var slot: int = -1
var title: String = ""
var icon: String = ""
var class_lock: String = ""
var transform: String = ""
var transform_desc: String = ""
var requires_transform: String = ""
var requires_label: String = ""
var fixed_affixes: Array = []
var weapon_hands: int = 1
var weapon_damage_mult: float = 1.0


static func from_dict(d: Dictionary) -> UniqueDefinition:
	var u := UniqueDefinition.new()
	u.id = String(d.get("id", ""))
	u.kind = String(d.get("kind", "armor"))
	u.slot = int(d.get("slot", -1))
	u.title = String(d.get("title", u.id))
	u.icon = String(d.get("icon", ""))
	u.class_lock = String(d.get("class_lock", ""))
	u.transform = String(d.get("transform", ""))
	u.transform_desc = String(d.get("transform_desc", ""))
	u.requires_transform = String(d.get("requires_transform", ""))
	u.requires_label = String(d.get("requires_label", ""))
	u.fixed_affixes = (d.get("fixed_affixes", []) as Array).duplicate(true)
	u.weapon_hands = int(d.get("weapon_hands", 1))
	u.weapon_damage_mult = float(d.get("weapon_damage_mult", 1.0))
	return u


static func unknown(unique_id: String) -> UniqueDefinition:
	var u := UniqueDefinition.new()
	u.id = unique_id
	u.title = unique_id
	return u


# Project to the generic template view ItemInstance.get_template() returns.
func to_template() -> ItemTemplate:
	var t := ItemTemplate.new()
	t.title = title
	t.icon = icon
	t.slot = slot
	t.kind = kind
	t.weapon_hands = weapon_hands
	t.weapon_damage_mult = weapon_damage_mult
	t.transform = transform
	t.transform_desc = transform_desc
	t.requires_label = requires_label
	t.class_lock = class_lock
	return t
