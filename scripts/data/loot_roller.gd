class_name LootRoller
extends RefCounted

# Generates ItemInstance objects from wave + class context.
# Stateless — every method is static.


# Roll a single item based on the current wave number and the player class.
# wave_number: 1+ — drives ilvl and rarity bias.
# class_id: barbarian/rogue/mage — filters weapons and uniques.
static func roll_item(wave_number: int, class_id: String) -> ItemInstance:
	var ilvl: int = max(1, 1 + int(float(wave_number) / 2.0))
	var rarity: String = _roll_rarity(wave_number)
	if rarity == ItemDatabase.RARITY_UNIQUE:
		var uniq := _roll_unique(class_id)
		if uniq != null:
			uniq.ilvl = ilvl
			return uniq
		# Fallback to legendary if no uniques exist for this class.
		rarity = ItemDatabase.RARITY_LEGENDARY
	return _roll_base(rarity, ilvl, class_id)


# Generate N preview items for the loot roulette belt — does NOT actually
# give them to the player. Mix of rarities to make the strip look exciting.
static func roll_preview_strip(count: int, wave_number: int, class_id: String) -> Array:
	var out: Array = []
	for i in count:
		out.append(roll_item(wave_number, class_id))
	return out


# ─────────────────────────────────────────────────────────────────────────────
# Rarity rolling
static func _roll_rarity(wave_number: int) -> String:
	# Base weights, with a small bonus to legendary+ every 5 waves.
	var bonus: float = float(int(wave_number / 5)) * 0.04
	var w_common: float = ItemDatabase.RARITY_WEIGHTS[ItemDatabase.RARITY_COMMON]
	var w_rare: float = ItemDatabase.RARITY_WEIGHTS[ItemDatabase.RARITY_RARE]
	var w_leg: float = (
		ItemDatabase.RARITY_WEIGHTS[ItemDatabase.RARITY_LEGENDARY] * (1.0 + bonus * 3.0)
	)
	var w_uni: float = ItemDatabase.RARITY_WEIGHTS[ItemDatabase.RARITY_UNIQUE] * (1.0 + bonus * 4.0)
	# Slight common→rare migration as waves climb.
	var migrate: float = float(min(wave_number - 1, 20)) * 0.5
	w_common = max(15.0, w_common - migrate)
	w_rare = w_rare + migrate * 0.6
	var total: float = w_common + w_rare + w_leg + w_uni
	var r: float = randf() * total
	if r < w_common:
		return ItemDatabase.RARITY_COMMON
	r -= w_common
	if r < w_rare:
		return ItemDatabase.RARITY_RARE
	r -= w_rare
	if r < w_leg:
		return ItemDatabase.RARITY_LEGENDARY
	return ItemDatabase.RARITY_UNIQUE


# ─────────────────────────────────────────────────────────────────────────────
# Unique rolling
static func _roll_unique(class_id: String) -> ItemInstance:
	var pool: Array = ItemDatabase.get_uniques_for_class(class_id)
	if pool.is_empty():
		return null
	var pick: Dictionary = pool[randi() % pool.size()]
	var inst := ItemInstance.new()
	inst.is_unique = true
	inst.unique_id = String(pick.get("id", ""))
	inst.rarity = ItemDatabase.RARITY_UNIQUE
	# Copy fixed affixes (deep) and append title/suffix from the affix pool.
	var fixed: Array = pick.get("fixed_affixes", [])
	for f in fixed:
		var aid: String = String(f.get("id", ""))
		var ameta: Dictionary = ItemDatabase.find_affix(aid)
		var entry: Dictionary = {
			"id": aid,
			"value": float(f.get("value", 0)),
			"title": String(ameta.get("title", aid.capitalize())),
			"suffix": String(ameta.get("suffix", "")),
		}
		inst.affixes.append(entry)
	return inst


# ─────────────────────────────────────────────────────────────────────────────
# Base item rolling
static func _roll_base(rarity: String, ilvl: int, class_id: String) -> ItemInstance:
	# Pick a random slot that has at least one matching base item for the class.
	# Helmet/Chest/Gloves/Boots/Amulet/Ring + Weapon (one per class).
	var candidate_slots: Array = [
		ItemDatabase.SLOT_HELMET,
		ItemDatabase.SLOT_CHEST,
		ItemDatabase.SLOT_GLOVES,
		ItemDatabase.SLOT_BOOTS,
		ItemDatabase.SLOT_AMULET,
		ItemDatabase.SLOT_RING_1,
		ItemDatabase.SLOT_WEAPON_MAIN,
	]
	# Weight: weapons + armor 1:1, ring drops can be either slot.
	var slot: int = candidate_slots[randi() % candidate_slots.size()]
	var pool: Array = ItemDatabase.get_base_items_for_slot(slot, class_id)
	if pool.is_empty():
		# Fallback to whatever helmets exist.
		pool = ItemDatabase.get_base_items_for_slot(ItemDatabase.SLOT_HELMET, class_id)
		if pool.is_empty():
			return null
	var pick: Dictionary = pool[randi() % pool.size()]
	var inst := ItemInstance.new()
	inst.is_unique = false
	inst.base_id = String(pick.get("id", ""))
	inst.rarity = rarity
	inst.ilvl = ilvl
	# Roll affix_count distinct affixes.
	var n: int = int(ItemDatabase.RARITY_AFFIX_COUNT.get(rarity, 1))
	inst.affixes = _roll_affixes(n, ilvl, rarity)
	return inst


static func _roll_affixes(count: int, ilvl: int, rarity: String) -> Array:
	var pool: Array = ItemDatabase.AFFIX_POOL.duplicate()
	# In co-op the XP-gain affix does nothing — party XP is shared and granted
	# flat at the kill (see enemy._die / net_sync), ignoring per-player multipliers.
	# Drop it from the pool so it never rolls in co-op; this also makes solo vs
	# co-op gear meaningfully different (XP-gain is a singleplayer-only perk).
	if NetManager and NetManager.is_multiplayer:
		pool = pool.filter(func(a): return String(a.get("id", "")) != "xp_gain")
	pool.shuffle()
	var out: Array = []
	for i in min(count, pool.size()):
		var a: Dictionary = pool[i]
		var min_v: float = float(a.get("min", 1))
		var max_v: float = float(a.get("max", 1))
		var per_ilvl: float = float(a.get("per_ilvl", 0.5))
		var base: float = randf_range(min_v, max_v)
		var ilvl_bonus: float = per_ilvl * float(ilvl - 1)
		var v: float = base + ilvl_bonus
		# Legendary gets +30% on rolled values to feel meaningfully stronger.
		if rarity == ItemDatabase.RARITY_LEGENDARY:
			v *= 1.3
		# Round armor/hp/mana/damage to integers — feels cleaner.
		var suffix: String = String(a.get("suffix", ""))
		if suffix == "":
			v = float(round(v))
		else:
			v = float(round(v * 10.0) / 10.0)
		(
			out
			. append(
				{
					"id": String(a.get("id", "")),
					"value": v,
					"title": String(a.get("title", "?")),
					"suffix": suffix,
				}
			)
		)
	return out
