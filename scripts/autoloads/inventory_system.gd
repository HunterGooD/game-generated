extends Node

# Inventory + Equipment autoload.
# Holds the player's bag (array of ItemInstance) and equipped slots
# (Dictionary[slot_index → ItemInstance]). Computes stat totals on demand
# so GameManager can layer equipment bonuses on top of base class stats.

signal inventory_changed
signal equipment_changed
signal item_added(item: ItemInstance)

const INVENTORY_CAPACITY: int = 30

# Inventory: ordered list, may contain nulls in deleted positions for stable indices.
var inventory: Array = []

# Equipment: slot_index → ItemInstance. Use ItemDatabase.SLOT_* constants.
var equipment: Dictionary = {}

# Track if barbarian unlocked dual-2H perk.
var has_berserker_grip: bool = false

# Cache transform_ids for fast lookup (rebuilt on equipment_changed).
var _active_transforms: Dictionary = {}


func _ready() -> void:
	if GameManager:
		GameManager.player_died.connect(_on_player_died)
		GameManager.class_selected.connect(_on_class_changed)


func _on_player_died() -> void:
	# Roguelike: wipe everything on death.
	clear_run_state()


func _on_class_changed(_class_id: String) -> void:
	clear_run_state()


func clear_run_state() -> void:
	inventory.clear()
	equipment.clear()
	has_berserker_grip = false
	_rebuild_transform_cache()
	inventory_changed.emit()
	equipment_changed.emit()


# ─────────────────────────────────────────────────────────────────────────────
# Inventory operations
func add_item(item: ItemInstance) -> bool:
	if item == null:
		return false
	if inventory.size() >= INVENTORY_CAPACITY:
		# Auto-salvage common items to make space.
		_auto_salvage_one_common()
		if inventory.size() >= INVENTORY_CAPACITY:
			return false
	inventory.append(item)
	item_added.emit(item)
	inventory_changed.emit()
	return true


func remove_item(item: ItemInstance) -> void:
	if item == null:
		return
	var idx: int = inventory.find(item)
	if idx >= 0:
		inventory.remove_at(idx)
		inventory_changed.emit()


func salvage_item(item: ItemInstance) -> int:
	if item == null:
		return 0
	var gold: int = item.get_salvage_gold()
	remove_item(item)
	if GameManager:
		GameManager.add_gold(gold)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_salvage_dust.mp3", -8.0)
	return gold


func _auto_salvage_one_common() -> void:
	for it in inventory:
		if it != null and String(it.rarity) == ItemDatabase.RARITY_COMMON:
			salvage_item(it)
			return


# ─────────────────────────────────────────────────────────────────────────────
# Equipment operations
func equip_item(item: ItemInstance, target_slot: int = -1) -> bool:
	if item == null:
		return false
	# Class lock: a class-locked unique can only be worn by its class. This is
	# the authoritative gate — every equip path goes through equip_item, so a
	# wrong-class unique can never activate its transform (the character sheet
	# also blocks it earlier for immediate UI feedback).
	var lock: String = item.get_class_lock()
	if lock != "" and GameManager and lock != String(GameManager.player_class):
		return false
	var slot: int = target_slot if target_slot >= 0 else item.get_slot()
	if slot < 0:
		return false

	# Rings: allow either ring slot if user picked one specifically, else
	# prefer the first empty ring slot.
	if slot == ItemDatabase.SLOT_RING_1 or slot == ItemDatabase.SLOT_RING_2:
		if target_slot < 0:
			if not equipment.has(ItemDatabase.SLOT_RING_1):
				slot = ItemDatabase.SLOT_RING_1
			else:
				slot = ItemDatabase.SLOT_RING_2

	# Weapons: handle 1H vs 2H and off-hand logic. With no explicit target, a
	# one-handed weapon auto-routes to the first free hand so a SECOND 1H weapon
	# lands in the off-hand instead of displacing the main weapon (the old path
	# always normalized to main, so two weapons could never be worn together).
	if item.is_weapon():
		var weapon_slot: int = slot
		if target_slot < 0 and not item.is_two_handed():
			weapon_slot = _auto_weapon_slot(item)
		return _equip_weapon(item, weapon_slot)

	# Regular slot: swap.
	var existing = equipment.get(slot, null)
	# Remove the new item from inventory FIRST (it may already be unequipped).
	remove_item(item)
	if existing != null:
		add_item(existing)
	equipment[slot] = item
	_rebuild_transform_cache()
	equipment_changed.emit()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_equip_armor.mp3", -8.0)
	return true


func _auto_weapon_slot(item: ItemInstance) -> int:
	# Landing hand for a one-handed weapon equipped without an explicit target.
	# Off-hand "home" items (caster catalysts) prefer the off-hand; otherwise fill
	# the main hand if empty, else the off-hand when the main holds a 1H weapon,
	# else fall back to main (a swap).
	if item.get_slot() == ItemDatabase.SLOT_WEAPON_OFF:
		return ItemDatabase.SLOT_WEAPON_OFF
	var main_w = equipment.get(ItemDatabase.SLOT_WEAPON_MAIN, null)
	var off_w = equipment.get(ItemDatabase.SLOT_WEAPON_OFF, null)
	if main_w == null:
		return ItemDatabase.SLOT_WEAPON_MAIN
	if (
		off_w == null
		and main_w is ItemInstance
		and not (main_w as ItemInstance).is_two_handed()
	):
		return ItemDatabase.SLOT_WEAPON_OFF
	return ItemDatabase.SLOT_WEAPON_MAIN


func _equip_weapon(item: ItemInstance, target_slot: int) -> bool:
	# Normalize the slot — main hand is the canonical landing pad for weapons.
	var slot: int = target_slot
	if slot != ItemDatabase.SLOT_WEAPON_OFF:
		slot = ItemDatabase.SLOT_WEAPON_MAIN

	var two_handed: bool = item.is_two_handed()
	var main_existing = equipment.get(ItemDatabase.SLOT_WEAPON_MAIN, null)
	var off_existing = equipment.get(ItemDatabase.SLOT_WEAPON_OFF, null)

	remove_item(item)

	if two_handed:
		# Two-handed always lands in main hand.
		if main_existing != null:
			add_item(main_existing)
		# Off-hand handling:
		if off_existing != null:
			# Barbarian dual-2H perk lets the second 2H stay in off-hand.
			if has_berserker_grip and (off_existing as ItemInstance).is_two_handed():
				# Keep off-hand existing 2H — the new weapon stays in main only if
				# the existing main was 2H of equivalent class. Simplest behavior:
				# kick off-hand to bag unless the player is explicitly equipping
				# to off-hand.
				if slot != ItemDatabase.SLOT_WEAPON_OFF:
					add_item(off_existing)
					equipment.erase(ItemDatabase.SLOT_WEAPON_OFF)
			else:
				add_item(off_existing)
				equipment.erase(ItemDatabase.SLOT_WEAPON_OFF)
		# If equipping to off-hand with Berserker's Grip, allow it.
		if slot == ItemDatabase.SLOT_WEAPON_OFF and has_berserker_grip:
			equipment[ItemDatabase.SLOT_WEAPON_OFF] = item
		else:
			equipment[ItemDatabase.SLOT_WEAPON_MAIN] = item
	else:
		# One-handed.
		if slot == ItemDatabase.SLOT_WEAPON_OFF:
			# Can't put 1H in off-hand if main is 2H — kick main first.
			if (
				main_existing != null
				and (main_existing as ItemInstance).is_two_handed()
				and not has_berserker_grip
			):
				add_item(main_existing)
				equipment.erase(ItemDatabase.SLOT_WEAPON_MAIN)
			# Swap off-hand.
			if off_existing != null:
				add_item(off_existing)
			equipment[ItemDatabase.SLOT_WEAPON_OFF] = item
		else:
			# Main hand swap. If main was 2H, kick its off-hand entry too
			# (the off slot was always conceptually owned by the 2H).
			if main_existing != null and (main_existing as ItemInstance).is_two_handed():
				equipment.erase(ItemDatabase.SLOT_WEAPON_OFF)
			if main_existing != null:
				add_item(main_existing)
			equipment[ItemDatabase.SLOT_WEAPON_MAIN] = item

	_rebuild_transform_cache()
	equipment_changed.emit()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_equip_armor.mp3", -8.0)
	return true


func unequip_slot(slot: int) -> bool:
	if not equipment.has(slot):
		return false
	var item = equipment[slot]
	equipment.erase(slot)
	# If unequipping a 2H weapon from main, also clear off-hand if it was the same item.
	if (
		item is ItemInstance
		and (item as ItemInstance).is_two_handed()
		and slot == ItemDatabase.SLOT_WEAPON_MAIN
	):
		if equipment.get(ItemDatabase.SLOT_WEAPON_OFF, null) == item:
			equipment.erase(ItemDatabase.SLOT_WEAPON_OFF)
	if item != null:
		add_item(item)
	_rebuild_transform_cache()
	equipment_changed.emit()
	return true


func get_equipped(slot: int) -> ItemInstance:
	var item = equipment.get(slot, null)
	if item is ItemInstance:
		return item
	return null


func is_slot_locked_by_2h(slot: int) -> bool:
	# The off-hand is "locked" when the main wields a 2H and Berserker's Grip is not active.
	if slot != ItemDatabase.SLOT_WEAPON_OFF:
		return false
	var main_w = equipment.get(ItemDatabase.SLOT_WEAPON_MAIN, null)
	if main_w is ItemInstance and (main_w as ItemInstance).is_two_handed():
		return not has_berserker_grip
	return false


# ─────────────────────────────────────────────────────────────────────────────
# Barbarian dual-2H perk
func grant_berserker_grip() -> void:
	has_berserker_grip = true
	equipment_changed.emit()


# ─────────────────────────────────────────────────────────────────────────────
# Stat aggregation
func compute_stat_totals() -> Dictionary:
	var totals: Dictionary = {}
	for slot in equipment.keys():
		var it = equipment[slot]
		if it is ItemInstance:
			(it as ItemInstance).add_stats_to(totals)
	return totals


# Convenience accessors used by GameManager / Player at runtime.
func get_total(stat_id: String) -> float:
	return float(compute_stat_totals().get(stat_id, 0.0)) + _set_bonus(stat_id)


# Counts equipped pieces of each set and adds 2-pc / 4-pc threshold bonuses.
func _set_bonus(stat_id: String) -> float:
	var counts: Dictionary = get_set_piece_counts()
	var total: float = 0.0
	for set_id in counts.keys():
		var n: int = int(counts[set_id])
		var def: Dictionary = ItemDatabase.SET_BONUSES.get(set_id, {})
		if def.is_empty():
			continue
		if n >= 2:
			total += float(def.get("2pc", {}).get(stat_id, 0))
		if n >= 4:
			total += float(def.get("4pc", {}).get(stat_id, 0))
	return total


# Public — returns {set_id: equipped_count}. Used by character sheet UI too.
func get_set_piece_counts() -> Dictionary:
	var counts: Dictionary = {}
	for slot in equipment.keys():
		var it = equipment.get(slot, null)
		if it is ItemInstance:
			var tpl: Dictionary = (it as ItemInstance).get_template()
			var sid: String = String(tpl.get("set_id", ""))
			if sid != "":
				counts[sid] = int(counts.get(sid, 0)) + 1
	return counts


# Returns ready-to-display set bonus info for the character sheet.
func get_active_set_bonuses() -> Array:
	var out: Array = []
	var counts: Dictionary = get_set_piece_counts()
	for set_id in counts.keys():
		var def: Dictionary = ItemDatabase.SET_BONUSES.get(set_id, {})
		if def.is_empty():
			continue
		var n: int = int(counts[set_id])
		(
			out
			. append(
				{
					"set_id": set_id,
					"name": String(def.get("name", set_id)),
					"flavor": String(def.get("flavor", "")),
					"pieces": n,
					"two_pc_active": n >= 2,
					"four_pc_active": n >= 4,
					"two_pc_label": String(def.get("2pc", {}).get("label", "")),
					"four_pc_label": String(def.get("4pc", {}).get("label", "")),
				}
			)
		)
	return out


# Total armor (flat add).
func get_total_armor() -> int:
	return int(round(get_total("armor")))


# Damage % bonus (sum of all "damage" affixes, applied as multiplier).
func get_damage_mult_bonus() -> float:
	return get_total("damage") * 0.01


func get_move_speed_mult_bonus() -> float:
	return get_total("move_speed") * 0.01


func get_crit_chance_bonus() -> float:
	return get_total("crit_chance") * 0.01


func get_crit_dmg_bonus() -> float:
	return get_total("crit_dmg") * 0.01


func get_fire_dmg_mult_bonus() -> float:
	return get_total("fire_dmg") * 0.01


func get_max_hp_bonus() -> int:
	return int(round(get_total("max_hp")))


func get_max_mana_bonus() -> int:
	return int(round(get_total("max_mana")))


func get_gold_gain_mult() -> float:
	return 1.0 + get_total("gold_gain") * 0.01


func get_xp_gain_mult() -> float:
	return 1.0 + get_total("xp_gain") * 0.01


func get_cdr_mult() -> float:
	# Returns a multiplier ≤ 1.0 to apply to cooldown durations.
	var pct: float = clamp(get_total("cdr") * 0.01, 0.0, 0.5)
	return 1.0 - pct


func get_weapon_damage_mult() -> float:
	# Sum of equipped weapons' damage multipliers (1.0 base if nothing equipped).
	var total: float = 0.0
	var any: bool = false
	for slot in [ItemDatabase.SLOT_WEAPON_MAIN, ItemDatabase.SLOT_WEAPON_OFF]:
		var it = equipment.get(slot, null)
		if it is ItemInstance and (it as ItemInstance).is_weapon():
			total += (it as ItemInstance).get_weapon_damage_mult()
			any = true
	if not any:
		return 1.0
	return total


# ─────────────────────────────────────────────────────────────────────────────
# Transforms (unique skill modifiers)
func _rebuild_transform_cache() -> void:
	_active_transforms.clear()
	for slot in equipment.keys():
		var it = equipment[slot]
		if it is ItemInstance and (it as ItemInstance).is_unique:
			var tid: String = (it as ItemInstance).get_transform_id()
			if tid != "":
				_active_transforms[tid] = true


func has_unique(transform_id: String) -> bool:
	return _active_transforms.has(transform_id)


# ─────────────────────────────────────────────────────────────────────────────
# Merchant operations
const _RARITY_MULT: Dictionary = {
	ItemDatabase.RARITY_COMMON: 1.0,
	ItemDatabase.RARITY_RARE: 2.0,
	ItemDatabase.RARITY_LEGENDARY: 4.0,
	ItemDatabase.RARITY_UNIQUE: 8.0,
}


static func upgrade_cost(item: ItemInstance) -> int:
	if item == null or item.is_unique:
		return -1
	var m: float = float(_RARITY_MULT.get(item.rarity, 1.0))
	return int(30.0 * float(item.ilvl) * m)


static func reroll_cost(item: ItemInstance) -> int:
	if item == null or item.is_unique:
		return -1
	var m: float = float(_RARITY_MULT.get(item.rarity, 1.0))
	return int(20.0 * float(item.ilvl) * m)


static func add_affix_cost(item: ItemInstance) -> int:
	if item == null or item.is_unique:
		return -1
	if item.affixes.size() >= 3:
		return -1
	var m: float = float(_RARITY_MULT.get(item.rarity, 1.0))
	return int(60.0 * float(max(1, item.ilvl)) * m)


func upgrade_item(item: ItemInstance) -> bool:
	if item == null or item.is_unique:
		return false
	var cost: int = upgrade_cost(item)
	if cost < 0 or GameManager == null or GameManager.gold < cost:
		return false
	GameManager.gold -= cost
	GameManager.gold_changed.emit(GameManager.gold)
	item.ilvl += 1
	_rescale_affixes(item)
	inventory_changed.emit()
	equipment_changed.emit()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_upgrade.mp3", -6.0)
	return true


func reroll_item(item: ItemInstance) -> bool:
	if item == null or item.is_unique:
		return false
	var cost: int = reroll_cost(item)
	if cost < 0 or GameManager == null or GameManager.gold < cost:
		return false
	GameManager.gold -= cost
	GameManager.gold_changed.emit(GameManager.gold)
	_rescale_affixes(item)
	inventory_changed.emit()
	equipment_changed.emit()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_upgrade.mp3", -6.0)
	return true


func add_affix_to(item: ItemInstance) -> bool:
	if item == null or item.is_unique:
		return false
	var cost: int = add_affix_cost(item)
	if cost < 0 or GameManager == null or GameManager.gold < cost:
		return false
	# Pick a new affix not already on the item.
	var used: Dictionary = {}
	for a in item.affixes:
		used[String(a.get("id", ""))] = true
	var pool: Array = []
	for ameta in ItemDatabase.AFFIX_POOL:
		var aid: String = String(ameta.get("id", ""))
		if not used.has(aid):
			pool.append(ameta)
	if pool.is_empty():
		return false
	GameManager.gold -= cost
	GameManager.gold_changed.emit(GameManager.gold)
	var pick: Dictionary = pool[randi() % pool.size()]
	var min_v: float = float(pick.get("min", 1))
	var max_v: float = float(pick.get("max", 1))
	var per_ilvl: float = float(pick.get("per_ilvl", 0.5))
	var v: float = randf_range(min_v, max_v) + per_ilvl * float(item.ilvl - 1)
	var suffix: String = String(pick.get("suffix", ""))
	if suffix == "":
		v = float(round(v))
	else:
		v = float(round(v * 10.0) / 10.0)
	(
		item
		. affixes
		. append(
			{
				"id": String(pick.get("id", "")),
				"value": v,
				"title": String(pick.get("title", "?")),
				"suffix": suffix,
			}
		)
	)
	# Bump rarity tier as affix count grows.
	if item.affixes.size() == 2 and item.rarity == ItemDatabase.RARITY_COMMON:
		item.rarity = ItemDatabase.RARITY_RARE
	elif item.affixes.size() == 3 and item.rarity == ItemDatabase.RARITY_RARE:
		item.rarity = ItemDatabase.RARITY_LEGENDARY
	inventory_changed.emit()
	equipment_changed.emit()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_upgrade.mp3", -6.0)
	return true


# Sell an item directly from the inventory for gold based on its rarity.
# Mirrors the salvage prices but pays slightly more for the inconvenience
# of fully losing the item. Returns true on success.
func sell_item(item: ItemInstance) -> bool:
	if item == null:
		return false
	# Refuse to sell equipped items — must unequip first.
	for slot in equipment.keys():
		if equipment.get(slot, null) == item:
			return false
	if not inventory.has(item):
		return false
	var price: int = item.get_salvage_gold() * 2
	GameManager.gold += price
	GameManager.gold_changed.emit(GameManager.gold)
	inventory.erase(item)
	inventory_changed.emit()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_loot_reveal_common.mp3", -8.0)
	return true


func buy_item(rarity: String, wave_hint: int = 1, class_id: String = "") -> bool:
	if GameManager == null:
		return false
	# Costs.
	var costs: Dictionary = {
		ItemDatabase.RARITY_COMMON: 40,
		ItemDatabase.RARITY_RARE: 150,
		ItemDatabase.RARITY_LEGENDARY: 450,
		ItemDatabase.RARITY_UNIQUE: 900,
	}
	var cost: int = int(costs.get(rarity, 999999))
	if GameManager.gold < cost:
		return false
	# Roll the item.
	var actual_class: String = class_id
	if actual_class == "":
		actual_class = String(GameManager.player_class)
	var item: ItemInstance = null
	if rarity == ItemDatabase.RARITY_UNIQUE:
		item = LootRoller._roll_unique(actual_class)
		if item == null:
			return false
		item.ilvl = max(1, 1 + int(float(wave_hint) / 2.0))
	else:
		item = LootRoller._roll_base(rarity, max(1, 1 + int(float(wave_hint) / 2.0)), actual_class)
		if item == null:
			return false
	GameManager.gold -= cost
	GameManager.gold_changed.emit(GameManager.gold)
	add_item(item)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_purchase.mp3", -6.0)
	return true


func _rescale_affixes(item: ItemInstance) -> void:
	# Re-roll the VALUES of the existing affixes based on current ilvl + rarity.
	var rar_bonus: float = 1.3 if item.rarity == ItemDatabase.RARITY_LEGENDARY else 1.0
	for i in item.affixes.size():
		var aid: String = String(item.affixes[i].get("id", ""))
		var meta: Dictionary = ItemDatabase.find_affix(aid)
		if meta.is_empty():
			continue
		var min_v: float = float(meta.get("min", 1))
		var max_v: float = float(meta.get("max", 1))
		var per_ilvl: float = float(meta.get("per_ilvl", 0.5))
		var base: float = randf_range(min_v, max_v)
		var v: float = (base + per_ilvl * float(item.ilvl - 1)) * rar_bonus
		var suffix: String = String(item.affixes[i].get("suffix", ""))
		if suffix == "":
			v = float(round(v))
		else:
			v = float(round(v * 10.0) / 10.0)
		item.affixes[i]["value"] = v
