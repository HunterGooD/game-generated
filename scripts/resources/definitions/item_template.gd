class_name ItemTemplate
extends RefCounted

# Typed, unified view of an item's catalog template. ItemInstance.get_template()
# resolves the right source dict per kind — gem (SocketGems.template_for), unique
# (ItemDatabase.find_unique) or base gear (ItemDatabase.find_base) — and wraps it
# in this one shape, so the instance's accessors read typed fields instead of
# stringly-typed get_template().get("title", ...). The underlying catalogs
# (BASE_ITEMS/UNIQUE_ITEMS/gem templates) stay dicts for their other consumers.
#
# Weapon-only fields default to the non-weapon values; unique-only fields
# (transform*/requires_label) default empty so base/gem templates are valid too.

var title: String = "Unknown"
var icon: String = ""
var slot: int = -1
var kind: String = "armor"
var weapon_hands: int = 1
var weapon_damage_mult: float = 1.0
var transform: String = ""
var transform_desc: String = ""
var requires_label: String = ""
var class_lock: String = ""


static func from_dict(d: Dictionary) -> ItemTemplate:
	var t := ItemTemplate.new()
	t.title = String(d.get("title", "Unknown"))
	t.icon = String(d.get("icon", ""))
	t.slot = int(d.get("slot", -1))
	t.kind = String(d.get("kind", "armor"))
	t.weapon_hands = int(d.get("weapon_hands", 1))
	t.weapon_damage_mult = float(d.get("weapon_damage_mult", 1.0))
	t.transform = String(d.get("transform", ""))
	t.transform_desc = String(d.get("transform_desc", ""))
	t.requires_label = String(d.get("requires_label", ""))
	t.class_lock = String(d.get("class_lock", ""))
	return t
