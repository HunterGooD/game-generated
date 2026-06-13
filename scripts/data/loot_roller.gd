class_name LootRoller
extends RefCounted

# Generates ItemInstance objects from wave + class context.
# Stateless — every method is static.

# Base chance a dropped piece of gear arrives with one socket already drilled
# («очень низкий шанс») — meta tree nodes add on top (MetaProgress.run_grants).
const SOCKET_DROP_CHANCE: float = 0.05


# Roll a single item based on the current wave number and the player class.
# wave_number: 1+ — drives ilvl and rarity bias.
# class_id: barbarian/rogue/mage — filters weapons and uniques.
static func roll_item(wave_number: int, class_id: String, difficulty: int = -1) -> ItemInstance:
	var ilvl: int = max(1, 1 + int(float(wave_number) / 2.0))
	var rarity: String = _roll_rarity(wave_number, difficulty)
	if rarity == ItemDatabase.RARITY_UNIQUE:
		var uniq := _roll_unique(class_id, ilvl)
		if uniq != null:
			return uniq
		# Fallback to legendary if no uniques exist for this class.
		rarity = ItemDatabase.RARITY_LEGENDARY
	if rarity == ItemDatabase.RARITY_SET:
		var set_item := _roll_set(ilvl, class_id)
		if set_item != null:
			return set_item
		rarity = ItemDatabase.RARITY_LEGENDARY
	return _roll_base(rarity, ilvl, class_id)


# Roll an item of at least `min_rarity` (re-rolling with a wave bump, like boss chests).
# Used for boss-reward candidates so the slot reels always offer worthwhile loot.
static func roll_at_least(wave_number: int, class_id: String, difficulty: int, min_rarity: String) -> ItemInstance:
	var item: ItemInstance = roll_item(wave_number, class_id, difficulty)
	if item == null:
		return null
	var ranks := {"common": 0, "rare": 1, "legendary": 2, "set": 3, "unique": 4}
	var target: int = int(ranks.get(min_rarity, 0))
	for _i in 12:
		if int(ranks.get(item.rarity, 0)) >= target:
			break
		item = roll_item(wave_number + 5, class_id, difficulty)
	return item


# Generate N preview items for the loot roulette belt — does NOT actually
# give them to the player. Mix of rarities to make the strip look exciting.
static func roll_preview_strip(count: int, wave_number: int, class_id: String) -> Array:
	var out: Array = []
	for i in count:
		out.append(roll_item(wave_number, class_id))
	return out


# ─────────────────────────────────────────────────────────────────────────────
# Gear sockets + socket gems
# Roll a socket gem as a bag item (loot chests / dev console / meta start grants).
static func roll_gem_item(luck: float = 0.0) -> ItemInstance:
	var inst := ItemInstance.new()
	inst.gem_id = SocketGems.roll(luck)
	inst.rarity = SocketGems.rarity_of(inst.gem_id)
	return inst


# Low chance for fresh gear to drop with one socket pre-drilled; the meta tree's
# fortune arm raises it. No-op for items whose slot takes no sockets.
static func _maybe_add_socket(inst: ItemInstance) -> void:
	if inst == null or inst.max_sockets() <= 0:
		return
	var chance: float = SOCKET_DROP_CHANCE
	if MetaProgress and GameManager:
		chance += float(MetaProgress.run_grants(GameManager.player_class).get("socket_chance", 0.0))
	if randf() < chance:
		inst.sockets.append(null)


# ─────────────────────────────────────────────────────────────────────────────
# Rarity rolling
static func _roll_rarity(wave_number: int, difficulty: int = -1) -> String:
	# Base weights, with a small bonus to legendary+ every 5 waves, plus a run-difficulty
	# bonus (higher tiers drop better loot). difficulty < 0 → no difficulty bonus (tier 0);
	# callers that know the run tier pass GameManager.run_difficulty.
	var diff: int = difficulty if difficulty >= 0 else 0
	var bonus: float = float(int(wave_number / 5)) * 0.04 + Difficulty.value(diff, "loot_rarity_bonus", 0.0)
	# Fortune's Favor (dungeon positive affix) nudges every drop toward higher
	# rarity; endless-run loops stack more luck on top (risk ↔ reward).
	if GameManager:
		bonus += GameManager.dungeon_loot_luck
		bonus += GameManager.loop_loot_luck()
	var w_common: float = ItemDatabase.RARITY_WEIGHTS[ItemDatabase.RARITY_COMMON]
	var w_rare: float = ItemDatabase.RARITY_WEIGHTS[ItemDatabase.RARITY_RARE]
	var w_leg: float = (
		ItemDatabase.RARITY_WEIGHTS[ItemDatabase.RARITY_LEGENDARY] * (1.0 + bonus * 3.0)
	)
	# Sets sit between legendary and unique in desirability — their luck scaling does too.
	var w_set: float = ItemDatabase.RARITY_WEIGHTS[ItemDatabase.RARITY_SET] * (1.0 + bonus * 3.5)
	var w_uni: float = ItemDatabase.RARITY_WEIGHTS[ItemDatabase.RARITY_UNIQUE] * (1.0 + bonus * 4.0)
	# Slight common→rare migration as waves climb.
	var migrate: float = float(min(wave_number - 1, 20)) * 0.5
	w_common = max(15.0, w_common - migrate)
	w_rare = w_rare + migrate * 0.6
	var total: float = w_common + w_rare + w_leg + w_set + w_uni
	var r: float = randf() * total
	if r < w_common:
		return ItemDatabase.RARITY_COMMON
	r -= w_common
	if r < w_rare:
		return ItemDatabase.RARITY_RARE
	r -= w_rare
	if r < w_leg:
		return ItemDatabase.RARITY_LEGENDARY
	r -= w_leg
	if r < w_set:
		return ItemDatabase.RARITY_SET
	return ItemDatabase.RARITY_UNIQUE


# ─────────────────────────────────────────────────────────────────────────────
# Unique rolling
static func _roll_unique(class_id: String, ilvl: int = 1) -> ItemInstance:
	var pool: Array = ItemDatabase.get_uniques_for_class(class_id)
	if pool.is_empty():
		return null
	var pick: Dictionary = pool[randi() % pool.size()]
	var inst := ItemInstance.new()
	inst.is_unique = true
	inst.unique_id = String(pick.get("id", ""))
	inst.rarity = ItemDatabase.RARITY_UNIQUE
	inst.ilvl = max(1, ilvl)
	# Copy fixed affixes (deep) and append title/suffix from the affix pool.
	var fixed: Array = pick.get("fixed_affixes", [])
	var used: Dictionary = {}
	for f in fixed:
		var aid: String = String(f.get("id", ""))
		var ameta := ItemDatabase.find_affix(aid)
		var entry: Dictionary = {
			"id": aid,
			"value": float(f.get("value", 0)),
			"title": ameta.title,
			"suffix": ameta.suffix,
		}
		inst.affixes.append(entry)
		used[aid] = true
	# Uniques carry 5 affixes: the fixed identity + one rolled from the slot
	# pool, so two copies of the same unique are never quite identical.
	var slot: int = int(pick.get("slot", -1))
	var want: int = int(ItemDatabase.RARITY_AFFIX_COUNT.get(ItemDatabase.RARITY_UNIQUE, 5))
	var extra: int = max(0, want - inst.affixes.size())
	if extra > 0:
		inst.affixes += _roll_affixes_excluding(extra, inst.ilvl, inst.rarity, slot, used)
	_maybe_add_socket(inst)
	return inst


# ─────────────────────────────────────────────────────────────────────────────
# Set item rolling — armor + jewelry only; the set_id lands on the INSTANCE.
static func _roll_set(ilvl: int, class_id: String) -> ItemInstance:
	var sets: Array = ItemDatabase.sets_for_class(class_id)
	if sets.is_empty():
		return null
	var slots: Array = ItemDatabase.set_eligible_slots()
	var slot: int = int(slots[randi() % slots.size()])
	var pool: Array = ItemDatabase.get_base_items_for_slot(slot, class_id)
	if pool.is_empty():
		pool = ItemDatabase.get_base_items_for_slot(ItemDatabase.SLOT_HELMET, class_id)
		if pool.is_empty():
			return null
	var pick: Dictionary = pool[randi() % pool.size()]
	var inst := ItemInstance.new()
	inst.is_unique = false
	inst.base_id = String(pick.get("id", ""))
	inst.rarity = ItemDatabase.RARITY_SET
	inst.set_id = String(sets[randi() % sets.size()])
	inst.ilvl = ilvl
	inst.affixes = roll_set_affixes(inst.set_id, int(pick.get("slot", slot)), ilvl)
	_maybe_add_socket(inst)
	return inst


# 3 affixes: 2 distinct from the set's theme pool + 1 from the slot pool.
# The theme picks ignore slot legality on purpose — that's the chase: a set
# ring can carry an affix its slot could never roll.
static func roll_set_affixes(set_id: String, slot: int, ilvl: int) -> Array:
	var theme: Array = ItemDatabase.find_set(set_id).get("theme_affixes", []).duplicate()
	theme.shuffle()
	var out: Array = []
	var used: Dictionary = {}
	for i in min(2, theme.size()):
		if not ItemDatabase.has_affix(String(theme[i])):
			continue
		var meta := ItemDatabase.find_affix(String(theme[i]))
		out.append(roll_affix_entry(meta, ilvl, ItemDatabase.RARITY_SET))
		used[String(theme[i])] = true
	out += _roll_affixes_excluding(3 - out.size(), ilvl, ItemDatabase.RARITY_SET, slot, used)
	return out


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
	# Roll affix_count distinct affixes from the item's SLOT pool.
	var n: int = int(ItemDatabase.RARITY_AFFIX_COUNT.get(rarity, 1))
	inst.affixes = _roll_affixes(n, ilvl, rarity, int(pick.get("slot", -1)))
	_maybe_add_socket(inst)
	return inst


static func _roll_affixes(count: int, ilvl: int, rarity: String, slot: int = -1) -> Array:
	return _roll_affixes_excluding(count, ilvl, rarity, slot, {})


# Slot-aware affix rolling. `slot` < 0 = no slot restriction (full pool);
# `exclude` maps affix ids that must not roll (already on the item).
static func _roll_affixes_excluding(
	count: int, ilvl: int, rarity: String, slot: int, exclude: Dictionary
) -> Array:
	var pool: Array = ItemDatabase.affixes_for_slot(slot)
	# In co-op the XP-gain affix does nothing — party XP is shared and granted
	# flat at the kill (see enemy._die / net_sync), ignoring per-player multipliers.
	# Drop it from the pool so it never rolls in co-op; this also makes solo vs
	# co-op gear meaningfully different (XP-gain is a singleplayer-only perk).
	if NetManager and NetManager.is_multiplayer:
		pool = pool.filter(func(a): return a.id != "xp_gain")
	if not exclude.is_empty():
		pool = pool.filter(func(a): return not exclude.has(a.id))
	pool.shuffle()
	var out: Array = []
	for i in min(count, pool.size()):
		var a: AffixDefinition = pool[i]
		out.append(roll_affix_entry(a, ilvl, rarity))
	return out


# Roll one affix value entry from its pool meta (shared by drop rolls and the
# merchant's add-affix service).
static func roll_affix_entry(meta: AffixDefinition, ilvl: int, rarity: String) -> Dictionary:
	var v: float = randf_range(meta.roll_min, meta.roll_max) + meta.per_ilvl * float(ilvl - 1)
	# Legendary gets +30% on rolled values to feel meaningfully stronger.
	if rarity == ItemDatabase.RARITY_LEGENDARY:
		v *= 1.3
	# Round flat stats to integers — feels cleaner.
	var suffix: String = meta.suffix
	if suffix == "":
		v = float(round(v))
	else:
		v = float(round(v * 10.0) / 10.0)
	return {
		"id": meta.id,
		"value": v,
		"title": meta.title,
		"suffix": suffix,
	}
