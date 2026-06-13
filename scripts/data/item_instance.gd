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
# Non-empty for socket GEMS (bag items that go into gear sockets, not slots).
var gem_id: String = ""
# Перекраска Ювелира: непустой массив из 4 цветов замещает грани каталога.
var gem_faces: Array = []
# Drilled gear sockets: each entry is null (empty) or
# {"gem": gem_id, "rot": 0..3, "faces": [...]?} (faces — перекрашенные грани).
var sockets: Array = []


# Typed unified template for this instance. Resolves the source dict per kind
# (gem / unique / base) and wraps it in ItemTemplate.
func get_template() -> ItemTemplate:
	if gem_id != "":
		return ItemTemplate.from_dict(SocketGems.template_for(gem_id))
	if is_unique:
		return ItemTemplate.from_dict(ItemDatabase.find_unique(unique_id))
	return ItemTemplate.from_dict(ItemDatabase.find_base(base_id))


func is_gem() -> bool:
	return gem_id != ""


# Действующие грани самоцвета: перекраска Ювелира или базовые из каталога.
func get_gem_faces() -> Array:
	if SocketGems.valid_faces(gem_faces):
		return gem_faces
	return SocketGems.base_faces(gem_id)


# ── Sockets ───────────────────────────────────────────────────────────────────
func max_sockets() -> int:
	return SocketGems.max_sockets_for_item(self)


# The gem entry in socket `idx` ({} while empty / out of range).
func socket_entry(idx: int) -> Dictionary:
	if idx < 0 or idx >= sockets.size():
		return {}
	var e = sockets[idx]
	if e is Dictionary and String((e as Dictionary).get("gem", "")) != "":
		return e
	return {}


func socketed_gem_ids() -> Array:
	var out: Array = []
	for i in sockets.size():
		var e: Dictionary = socket_entry(i)
		if not e.is_empty():
			out.append(String(e.get("gem", "")))
	return out


func get_title() -> String:
	return get_template().title


func get_icon_path() -> String:
	return get_template().icon


func get_icon() -> Texture2D:
	var p: String = get_icon_path()
	if p == "" or not ResourceLoader.exists(p):
		return null
	return load(p) as Texture2D


func get_slot() -> int:
	return get_template().slot


func get_kind() -> String:
	return get_template().kind


func is_weapon() -> bool:
	return get_kind() == "weapon"


func is_two_handed() -> bool:
	if not is_weapon():
		return false
	return get_template().weapon_hands == 2


func get_weapon_damage_mult() -> float:
	if not is_weapon():
		return 0.0
	return get_template().weapon_damage_mult


func get_transform_id() -> String:
	if not is_unique:
		return ""
	return get_template().transform


func get_transform_desc() -> String:
	if not is_unique:
		return ""
	return get_template().transform_desc


# Some uniques only do something while a specific talent transform is taken
# (e.g. Bone Spear splinters require the Bone Spear talent). Tooltip line.
func get_requires_label() -> String:
	if not is_unique:
		return ""
	return get_template().requires_label


func get_class_lock() -> String:
	return get_template().class_lock


func get_set_id() -> String:
	return set_id


func get_set_name() -> String:
	if set_id == "":
		return ""
	return ItemDatabase.find_set(set_id).name


func get_salvage_gold() -> int:
	return ItemDatabase.rarity_salvage_gold(rarity, ilvl)


# Materials this item disassembles into (does NOT include the set stone a set
# item also yields — see InventorySystem.salvage_item). Gems melt into essence.
func get_salvage_preview() -> Dictionary:
	if is_gem():
		var by_rarity: Dictionary = {"common": 1, "rare": 2, "legendary": 4, "unique": 8}
		return {"essence": int(by_rarity.get(rarity, 1))}
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
	# Socketed gems add their small flat lines (link bonuses are computed
	# cross-item by InventorySystem via SocketGems.resolve, not here).
	for gid in socketed_gem_ids():
		var gstats: Dictionary = SocketGems.get_gem(String(gid)).stats
		for k in gstats:
			totals[k] = float(totals.get(k, 0.0)) + float(gstats[k])
	# Weapons contribute a base damage multiplier as a separate key.
	if is_weapon():
		totals["weapon_dmg_mult"] = (
			float(totals.get("weapon_dmg_mult", 0.0)) + get_weapon_damage_mult()
		)


# ─────────────────────────────────────────────────────────────────────────────
# Display
func get_affix_lines() -> Array:
	# Gems carry no affixes — show their flat stats so generic item UIs
	# (roulette, trade) still render something meaningful.
	if is_gem():
		return SocketGems.stat_lines(gem_id)
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
		"gem_id": gem_id,
		"gem_faces": gem_faces.duplicate(),
		"sockets": sockets.duplicate(true),
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
	# Gems / sockets — absent on items from older clients.
	inst.gem_id = String(data.get("gem_id", ""))
	if inst.gem_id != "" and not SocketGems.has_gem(inst.gem_id):
		return null  # unknown gem id from a foreign build — drop the gift
	var gf: Variant = data.get("gem_faces", [])
	if gf is Array and SocketGems.valid_faces(gf as Array):
		for f in (gf as Array):
			inst.gem_faces.append(String(f))
	var socks: Variant = data.get("sockets", [])
	if socks is Array:
		for s in (socks as Array):
			if s is Dictionary and SocketGems.has_gem(String((s as Dictionary).get("gem", ""))):
				var e := s as Dictionary
				var entry: Dictionary = {
					"gem": String(e.get("gem", "")), "rot": int(e.get("rot", 0)) % 4
				}
				var ef: Variant = e.get("faces", [])
				if ef is Array and SocketGems.valid_faces(ef as Array):
					var faces: Array = []
					for f in (ef as Array):
						faces.append(String(f))
					entry["faces"] = faces
				inst.sockets.append(entry)
			else:
				inst.sockets.append(null)
	# Never trust more sockets than the item legally supports.
	var cap: int = inst.max_sockets()
	if inst.sockets.size() > cap:
		inst.sockets.resize(cap)
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
