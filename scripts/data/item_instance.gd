class_name ItemInstance
extends RefCounted

# One concrete piece of loot — base template + rolled rarity + rolled affixes.
# Lightweight refcounted object, NOT a Resource (we don't persist on disk).

var base_id: String = ""
var unique_id: String = ""  # Non-empty for unique items.
var is_unique: bool = false
var rarity: String = ItemDatabase.RARITY_COMMON
# Set membership — rolled at drop time (rarity == "set"), "" otherwise.
var set_id: String = ""
var ilvl: int = 1
# Each affix is {"id": "armor", "value": 12, "title": "Armor", "suffix": ""}.
var affixes: Array = []


func get_template() -> Dictionary:
	if is_unique:
		return ItemDatabase.find_unique(unique_id)
	return ItemDatabase.find_base(base_id)


func get_title() -> String:
	return String(get_template().get("title", "Unknown"))


func get_icon_path() -> String:
	return String(get_template().get("icon", ""))


func get_icon() -> Texture2D:
	var p: String = get_icon_path()
	if p == "" or not ResourceLoader.exists(p):
		return null
	return load(p) as Texture2D


func get_slot() -> int:
	return int(get_template().get("slot", -1))


func get_kind() -> String:
	return String(get_template().get("kind", "armor"))


func is_weapon() -> bool:
	return get_kind() == "weapon"


func is_two_handed() -> bool:
	if not is_weapon():
		return false
	return int(get_template().get("weapon_hands", 1)) == 2


func get_weapon_damage_mult() -> float:
	if not is_weapon():
		return 0.0
	return float(get_template().get("weapon_damage_mult", 1.0))


func get_transform_id() -> String:
	if not is_unique:
		return ""
	return String(get_template().get("transform", ""))


func get_transform_desc() -> String:
	if not is_unique:
		return ""
	return String(get_template().get("transform_desc", ""))


# Some uniques only do something while a specific talent transform is taken
# (e.g. Bone Spear splinters require the Bone Spear talent). Tooltip line.
func get_requires_label() -> String:
	if not is_unique:
		return ""
	return String(get_template().get("requires_label", ""))


func get_class_lock() -> String:
	return String(get_template().get("class_lock", ""))


func get_set_id() -> String:
	return set_id


func get_set_name() -> String:
	if set_id == "":
		return ""
	return String(ItemDatabase.find_set(set_id).get("name", set_id))


func get_salvage_gold() -> int:
	return ItemDatabase.rarity_salvage_gold(rarity, ilvl)


# Materials this item disassembles into (does NOT include the set stone a set
# item also yields — see InventorySystem.salvage_item).
func get_salvage_preview() -> Dictionary:
	return ItemDatabase.salvage_materials_for(get_slot(), rarity, ilvl)


# ─────────────────────────────────────────────────────────────────────────────
# Stat aggregation — for InventorySystem.compute_totals.
func add_stats_to(totals: Dictionary) -> void:
	for a in affixes:
		var id: String = String(a.get("id", ""))
		if id == "":
			continue
		var v: float = float(a.get("value", 0))
		totals[id] = float(totals.get(id, 0.0)) + v
	# Weapons contribute a base damage multiplier as a separate key.
	if is_weapon():
		totals["weapon_dmg_mult"] = (
			float(totals.get("weapon_dmg_mult", 0.0)) + get_weapon_damage_mult()
		)


# ─────────────────────────────────────────────────────────────────────────────
# Display
func get_affix_lines() -> Array:
	var out: Array = []
	for a in affixes:
		var t: String = String(a.get("title", a.get("id", "?")))
		var v: float = float(a.get("value", 0))
		var suffix: String = String(a.get("suffix", ""))
		var val_str: String
		if abs(v - round(v)) < 0.01:
			val_str = "+%d" % int(round(v))
		else:
			val_str = "+%.1f" % v
		out.append("%s%s %s" % [val_str, suffix, t])
	return out


# ─────────────────────────────────────────────────────────────────────────────
# Wire-format serialization for co-op item gifting via NetSync.
func to_dict() -> Dictionary:
	return {
		"base_id": base_id,
		"unique_id": unique_id,
		"is_unique": is_unique,
		"rarity": rarity,
		"set_id": set_id,
		"ilvl": ilvl,
		"affixes": affixes.duplicate(true),
	}


static func from_dict(data: Dictionary) -> ItemInstance:
	if data == null or not (data is Dictionary):
		return null
	var inst := ItemInstance.new()
	inst.base_id = String(data.get("base_id", ""))
	inst.unique_id = String(data.get("unique_id", ""))
	inst.is_unique = bool(data.get("is_unique", false))
	inst.rarity = String(data.get("rarity", ItemDatabase.RARITY_COMMON))
	# Back-compat default: items gifted by older clients carry no set_id.
	inst.set_id = String(data.get("set_id", ""))
	inst.ilvl = int(data.get("ilvl", 1))
	var affs: Array = data.get("affixes", [])
	for a in affs:
		if a is Dictionary:
			inst.affixes.append((a as Dictionary).duplicate(true))
	return inst


# Pseudo-serialization (not persisted — useful for debug logging).
func describe() -> String:
	var parts: Array = []
	parts.append("[%s ilvl%d]" % [ItemDatabase.rarity_display(rarity), ilvl])
	parts.append(get_title())
	if is_unique:
		parts.append("[UNIQUE]")
	for a in get_affix_lines():
		parts.append("  " + a)
	return "\n".join(parts)
