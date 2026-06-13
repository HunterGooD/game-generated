extends Node

# Inventory + Equipment autoload.
# Holds the player's bag (array of ItemInstance) and equipped slots
# (Dictionary[slot_index → ItemInstance]). Computes stat totals on demand
# so GameManager can layer equipment bonuses on top of base class stats.

signal inventory_changed
signal equipment_changed
signal item_added(item: ItemInstance)

# 11 колонок × 9 рядов (см. сетку в character_sheet).
const INVENTORY_CAPACITY: int = 99

# Ювелир (хаб): слияние — 3 одинаковых камня из сумки → случайный камень тиром
# выше (common→rare→legendary→unique); перекраска одной грани — дорогой сток.
const FUSE_COUNT: int = 3
const REPAINT_COST: Dictionary = {"gold": 150, "essence": 8}

# Inventory: ordered list, may contain nulls in deleted positions for stable indices.
var inventory: Array = []

# Equipment: slot_index → ItemInstance. Use ItemDatabase.SLOT_* constants.
var equipment: Dictionary = {}

# Track if barbarian unlocked dual-2H perk.
var has_berserker_grip: bool = false

# Cache transform_ids for fast lookup (rebuilt on equipment_changed).
var _active_transforms: Dictionary = {}

# Cache of active 5-piece set effect ids (rebuilt with the transform cache).
var _active_set_effects: Dictionary = {}

# Cached SocketGems.resolve() over the worn gear ({links, stats, chains,
# resonance, loops, effects}) — rebuilt with the transform cache on every
# equip/socket mutation.
var _socket_links: Dictionary = {
	"links": [], "stats": {}, "chains": [], "resonance": [], "loops": [], "effects": {}
}


func _ready() -> void:
	if GameManager:
		GameManager.player_died.connect(_on_player_died)
		GameManager.class_selected.connect(_on_class_changed)


func _on_player_died() -> void:
	# Roguelike: wipe everything on death.
	clear_run_state()


func _on_class_changed(_class_id: String) -> void:
	clear_run_state()
	_grant_meta_start_gems()


# Fortune-arm meta nodes seed the fresh run's bag with 1–3 random socket gems.
# Runs AFTER clear_run_state so the wipe can't eat the grant.
func _grant_meta_start_gems() -> void:
	if MetaProgress == null or GameManager == null or GameManager.player_class == "":
		return
	var n: int = int(MetaProgress.run_grants(GameManager.player_class).get("start_gems", 0))
	for _i in n:
		add_item(LootRoller.roll_gem_item())


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


# Disassemble an item into crafting materials (scrap/cloth + essence; set items
# additionally yield one stone of their set). Returns the granted materials dict.
func salvage_item(item: ItemInstance) -> Dictionary:
	if item == null:
		return {}
	var mats: Dictionary = item.get_salvage_preview()
	_pop_socketed_gems(item)
	remove_item(item)
	if GameManager:
		GameManager.add_materials(mats)
		# Set items also break down into one stone of their set (craft fuel).
		if item.rarity == ItemDatabase.RARITY_SET and item.get_set_id() != "":
			GameManager.add_set_stone(item.get_set_id())
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_salvage_dust.mp3", -8.0)
	return mats


func _auto_salvage_one_common() -> void:
	for it in inventory:
		# Gems are spared — they're craft fuel the player placed in the bag on purpose.
		if (
			it != null
			and String(it.rarity) == ItemDatabase.RARITY_COMMON
			and not (it as ItemInstance).is_gem()
		):
			salvage_item(it)
			return


# Eject every socketed gem of `item` back into the bag (called before the item
# is destroyed by salvage/sell so player-placed gems are never silently lost).
func _pop_socketed_gems(item: ItemInstance) -> void:
	if item == null:
		return
	for i in item.sockets.size():
		var e: Dictionary = item.socket_entry(i)
		if e.is_empty():
			continue
		item.sockets[i] = null
		add_item(make_gem_item(String(e.get("gem", "")), e.get("faces", [])))


# Build a bag ItemInstance for a gem id (rarity mirrors the gem tier for tinting).
# `faces` — перекрашенные Ювелиром грани, путешествуют с камнем.
static func make_gem_item(gid: String, faces: Array = []) -> ItemInstance:
	var inst := ItemInstance.new()
	inst.gem_id = gid
	inst.rarity = SocketGems.rarity_of(gid)
	if SocketGems.valid_faces(faces):
		inst.gem_faces = faces.duplicate()
	return inst


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
	# Drag-equip safety: if this item is ALREADY worn (e.g. dragged slot→slot, or
	# dropped back onto its own slot), strip it out of equipment first. Otherwise
	# the old slot keeps a stale reference and the item duplicates on next unequip
	# (or, when re-dropped onto its own slot, gets cloned straight into the bag).
	_detach_item_from_equipment(item)
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


func _detach_item_from_equipment(item: ItemInstance) -> void:
	# Erase `item` from every equipment slot it currently occupies (a 2H weapon
	# can mirror into both hands). keys() returns a copy, so erasing while
	# iterating is safe. Does NOT touch the bag or emit — the caller re-places.
	if item == null:
		return
	for s in equipment.keys():
		if equipment[s] == item:
			equipment.erase(s)


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
# Gear sockets (камни в экипировке — см. SocketGems)
# Place a bag gem into `item`'s socket `idx`. An occupied socket swaps (the old
# gem returns to the bag). Works on worn AND bagged items alike.
func socket_gem(item: ItemInstance, idx: int, gem_item: ItemInstance) -> bool:
	if item == null or gem_item == null or not gem_item.is_gem():
		return false
	if idx < 0 or idx >= item.sockets.size():
		return false
	if not inventory.has(gem_item):
		return false
	var old: Dictionary = item.socket_entry(idx)
	remove_item(gem_item)
	var entry: Dictionary = {"gem": gem_item.gem_id, "rot": 0}
	if SocketGems.valid_faces(gem_item.gem_faces):
		entry["faces"] = gem_item.gem_faces.duplicate()
	item.sockets[idx] = entry
	if not old.is_empty():
		add_item(make_gem_item(String(old.get("gem", "")), old.get("faces", [])))
	_after_socket_change()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_equip_armor.mp3", -10.0)
	return true


# Pop the gem out of `item`'s socket `idx` back into the bag (fails on full bag).
func unsocket_gem(item: ItemInstance, idx: int) -> bool:
	if item == null:
		return false
	var e: Dictionary = item.socket_entry(idx)
	if e.is_empty():
		return false
	if not add_item(make_gem_item(String(e.get("gem", "")), e.get("faces", []))):
		return false
	item.sockets[idx] = null
	_after_socket_change()
	return true


# Move a gem between two sockets (possibly across items); occupied target swaps.
# Rotation travels with the gem.
func move_socket_gem(
	src_item: ItemInstance, src_idx: int, dst_item: ItemInstance, dst_idx: int
) -> bool:
	if src_item == null or dst_item == null:
		return false
	if src_item == dst_item and src_idx == dst_idx:
		return false
	var e: Dictionary = src_item.socket_entry(src_idx)
	if e.is_empty():
		return false
	if dst_idx < 0 or dst_idx >= dst_item.sockets.size():
		return false
	var old: Dictionary = dst_item.socket_entry(dst_idx)
	dst_item.sockets[dst_idx] = e
	src_item.sockets[src_idx] = old if not old.is_empty() else null
	_after_socket_change()
	return true


# Rotate the gem in socket `idx` a quarter-turn clockwise (links re-resolve).
func rotate_socket_gem(item: ItemInstance, idx: int) -> bool:
	if item == null:
		return false
	var e: Dictionary = item.socket_entry(idx)
	if e.is_empty():
		return false
	(item.sockets[idx] as Dictionary)["rot"] = (int(e.get("rot", 0)) + 1) % 4
	_after_socket_change()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_loot_reveal_common.mp3", -16.0)
	return true


# Drill cost — ESSENCE only (steady +5 income per cleared map node, see
# GameManager.award_node_essence); escalates with the sockets the item already
# has; {} when the item can't take another socket. Any gear can be drilled
# (uniques and sets included — «на любой одежде»), up to its slot maximum.
static func drill_cost(item: ItemInstance) -> Dictionary:
	if item == null or item.is_gem():
		return {}
	var cap: int = item.max_sockets()
	var n: int = item.sockets.size()
	if cap <= 0 or n >= cap:
		return {}
	return {"essence": 3 + 3 * n}


# Drill one more (empty) socket into the item, paying materials.
func drill_socket(item: ItemInstance) -> bool:
	var cost: Dictionary = drill_cost(item)
	if cost.is_empty():
		return false
	if GameManager == null or not GameManager.spend_cost(cost):
		return false
	item.sockets.append(null)
	_after_socket_change()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_upgrade.mp3", -8.0)
	return true


# ── Ювелир (хаб): слияние и перекраска самоцветов ─────────────────────────────
# (Цены — FUSE_COUNT / REPAINT_COST у шапки файла.) Камни без перекраски
# тратятся при слиянии первыми — защищаем вложения игрока.
func count_bag_gems(gem_id: String) -> int:
	var n: int = 0
	for it in inventory:
		if it is ItemInstance and (it as ItemInstance).gem_id == gem_id:
			n += 1
	return n


# Returns the fused gem (already in the bag) or null.
func fuse_gems(gem_id: String) -> ItemInstance:
	var next_rarity: String = String(SocketGems.RARITY_NEXT.get(SocketGems.rarity_of(gem_id), ""))
	if next_rarity == "" or not SocketGems.has_gem(gem_id):
		return null
	# Собираем жертвы: сначала неперекрашенные (защищаем вложения игрока).
	var plain: Array = []
	var painted: Array = []
	for it in inventory:
		if it is ItemInstance and (it as ItemInstance).gem_id == gem_id:
			if (it as ItemInstance).gem_faces.is_empty():
				plain.append(it)
			else:
				painted.append(it)
	var victims: Array = plain + painted
	if victims.size() < FUSE_COUNT:
		return null
	for i in FUSE_COUNT:
		remove_item(victims[i] as ItemInstance)
	var pool: Array = SocketGems.ids_of_rarity(next_rarity)
	if pool.is_empty():
		return null
	var result := make_gem_item(String(pool[randi() % pool.size()]))
	add_item(result)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_upgrade.mp3", -6.0)
	return result


# Перекрасить грань `face` (0..3 = ▲▶▼◀) сумочного камня в `color`.
# Уникальные камни не перекрашиваются — их грани и есть их идентичность.
func repaint_gem_face(gem_item: ItemInstance, face: int, color: String) -> bool:
	if gem_item == null or not gem_item.is_gem() or gem_item.rarity == ItemDatabase.RARITY_UNIQUE:
		return false
	var legal_color: bool = SocketGems.LINK_ATTR.has(color) or color == SocketGems.COLOR_WHITE
	if face < 0 or face > 3 or not legal_color or not inventory.has(gem_item):
		return false
	var faces: Array = gem_item.get_gem_faces().duplicate()
	if String(faces[face]) == color:
		return false  # уже этот цвет — не списываем оплату
	if GameManager == null or not GameManager.spend_cost(REPAINT_COST):
		return false
	faces[face] = color
	gem_item.gem_faces = faces
	inventory_changed.emit()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_upgrade.mp3", -8.0)
	return true


# The cached cross-item link resolution ({links, stats, chains, …}) for UI overlays.
func get_socket_links() -> Dictionary:
	return _socket_links


# «Контур» цвета активен (замкнутый цикл связей — см. SocketGems.LOOPS).
func has_socket_loop(color: String) -> bool:
	return (_socket_links.get("loops", []) as Array).has(color)


# Эффект уникального камня активен (камень состоит в связи — см. SocketGems.EFFECTS).
func has_socket_effect(effect_id: String) -> bool:
	return (_socket_links.get("effects", {}) as Dictionary).has(effect_id)


func _after_socket_change() -> void:
	_rebuild_transform_cache()
	inventory_changed.emit()
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
	return (
		float(compute_stat_totals().get(stat_id, 0.0))
		+ _set_bonus(stat_id)
		+ float(_socket_links.get("stats", {}).get(stat_id, 0))
	)


# Adds the 2-piece flat stat bonuses of every worn set to the totals.
# (4pc = talent node ranks, 5pc = combat effects — neither flows through here.)
func _set_bonus(stat_id: String) -> float:
	var counts: Dictionary = get_set_piece_counts()
	var total: float = 0.0
	for set_id in counts.keys():
		if int(counts[set_id]) < 2:
			continue
		var def := ItemDatabase.find_set(String(set_id))
		total += float(def.bonus2.stats.get(stat_id, 0))
	return total


# Public — returns {set_id: equipped_count}. EVERY equipped piece counts —
# amulet and both rings included — so a ring+amulet pair is a valid 2pc and a
# player may reach 5pc through any mix of armor and jewelry (max raw count 7;
# thresholds stop mattering past 5).
func get_set_piece_counts() -> Dictionary:
	var counts: Dictionary = {}
	for slot in equipment.keys():
		var it = equipment.get(slot, null)
		if not (it is ItemInstance):
			continue
		var sid: String = (it as ItemInstance).get_set_id()
		if sid == "":
			continue
		counts[sid] = int(counts.get(sid, 0)) + 1
	return counts


# Returns ready-to-display set bonus info for the character sheet / tooltips:
# {set_id, name, flavor, pieces, bonuses: [{threshold, label, active}]}.
func get_active_set_bonuses() -> Array:
	var out: Array = []
	var counts: Dictionary = get_set_piece_counts()
	for set_id in counts.keys():
		if not ItemDatabase.has_set(String(set_id)):
			continue
		var def := ItemDatabase.find_set(String(set_id))
		var n: int = int(counts[set_id])
		var bonuses: Array = []
		for threshold in [2, 4, 5]:
			(
				bonuses
				. append(
					{
						"threshold": threshold,
						"label": def.bonus_for(threshold).label,
						"active": n >= threshold,
					}
				)
			)
		(
			out
			. append(
				{
					"set_id": set_id,
					"name": def.name,
					"flavor": def.flavor,
					"pieces": n,
					"bonuses": bonuses,
				}
			)
		)
	return out


# 5-piece set effect check — the set analogue of has_unique(). Cache rebuilt by
# _rebuild_transform_cache on every equip/unequip.
func has_set_effect(effect_id: String) -> bool:
	return _active_set_effects.has(effect_id)


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
	# 5-piece set effects (NOTE co-op: evaluated against the LOCAL inventory —
	# remote visual-only skill copies skip damage, so this stays cosmetic-safe).
	_active_set_effects.clear()
	var counts: Dictionary = get_set_piece_counts()
	for set_id in counts.keys():
		if int(counts[set_id]) < 5:
			continue
		var eff: String = ItemDatabase.find_set(String(set_id)).bonus5.effect
		if eff != "":
			_active_set_effects[eff] = true
	# Gear-socket links — resolved once per equipment/socket mutation, read by
	# get_total (stat bonuses) and the character sheet (line overlay).
	_socket_links = SocketGems.resolve(equipment)


# True when the EFFECT identified by `transform_id` is active — either the
# unique item carrying it is equipped, or the matching talent-tree transform
# node was bought (several tree nodes deliberately reuse unique effect ids:
# hexen_bloodmoon, storm_stormveil, stone_armor_grinder, …). Remote player
# puppets carry no SkillSystem child, so only the LOCAL player ever matches.
func has_unique(transform_id: String) -> bool:
	if _active_transforms.has(transform_id):
		return true
	var tree := get_tree()
	if tree == null:
		return false
	for p in tree.get_nodes_in_group("player"):
		var ss = p.get_node_or_null("SkillSystem")
		if ss == null:
			continue
		var at = ss.get("active_transforms")
		if at is Array and (at as Array).has(transform_id):
			return true
	return false


# ─────────────────────────────────────────────────────────────────────────────
# Merchant operations
const _RARITY_MULT: Dictionary = {
	ItemDatabase.RARITY_COMMON: 1.0,
	ItemDatabase.RARITY_RARE: 2.0,
	ItemDatabase.RARITY_LEGENDARY: 4.0,
	ItemDatabase.RARITY_UNIQUE: 8.0,
}


# Rarity rank used to scale material costs (common 0 … unique 3).
static func _rarity_rank(rarity: String) -> int:
	match rarity:
		ItemDatabase.RARITY_RARE:
			return 1
		ItemDatabase.RARITY_LEGENDARY:
			return 2
		ItemDatabase.RARITY_SET:
			return 2
		ItemDatabase.RARITY_UNIQUE:
			return 3
	return 0


# Merchant operation costs are cost dicts ({"gold", "scrap", "cloth", "essence"});
# an EMPTY dict means the operation is unavailable for this item. Spend via
# GameManager.spend_cost (atomic), afford-check via GameManager.can_afford_cost.
static func upgrade_cost(item: ItemInstance) -> Dictionary:
	if item == null or item.is_unique:
		return {}
	var m: float = float(_RARITY_MULT.get(item.rarity, 1.0))
	return {
		"gold": int(15.0 * float(item.ilvl) * m),
		"scrap": 2 + int(float(item.ilvl) / 3.0),
	}


static func reroll_cost(item: ItemInstance) -> Dictionary:
	if item == null or item.is_unique:
		return {}
	return {
		"cloth": 2 + int(float(item.ilvl) / 4.0),
		"essence": maxi(1, _rarity_rank(item.rarity)),
	}


static func add_affix_cost(item: ItemInstance) -> Dictionary:
	if item == null or item.is_unique:
		return {}
	# Set items are locked at 3 affixes — their power is the set bonus.
	if item.rarity == ItemDatabase.RARITY_SET:
		return {}
	if item.affixes.size() >= 4:
		return {}
	return {"essence": 3 + 2 * _rarity_rank(item.rarity) + int(float(max(1, item.ilvl)) / 4.0)}


func upgrade_item(item: ItemInstance) -> bool:
	if item == null or item.is_unique:
		return false
	var cost: Dictionary = upgrade_cost(item)
	if GameManager == null or not GameManager.spend_cost(cost):
		return false
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
	var cost: Dictionary = reroll_cost(item)
	if GameManager == null or not GameManager.spend_cost(cost):
		return false
	_rescale_affixes(item)
	inventory_changed.emit()
	equipment_changed.emit()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_upgrade.mp3", -6.0)
	return true


func add_affix_to(item: ItemInstance) -> bool:
	if item == null or item.is_unique:
		return false
	var cost: Dictionary = add_affix_cost(item)
	if GameManager == null or not GameManager.can_afford_cost(cost):
		return false
	# Pick a new affix legal for the item's SLOT and not already on it.
	var used: Dictionary = {}
	for a in item.affixes:
		used[String(a.get("id", ""))] = true
	var pool: Array = []
	for ameta in ItemDatabase.affixes_for_slot(item.get_slot()):
		if not used.has(ameta.id):
			pool.append(ameta)
	if pool.is_empty():
		return false
	if not GameManager.spend_cost(cost):
		return false
	var pick: AffixDefinition = pool[randi() % pool.size()]
	item.affixes.append(LootRoller.roll_affix_entry(pick, item.ilvl, item.rarity))
	# Bump rarity tier as affix count grows (mirrors RARITY_AFFIX_COUNT: rare
	# carries 2 affixes, legendary 4).
	if item.affixes.size() >= 2 and item.rarity == ItemDatabase.RARITY_COMMON:
		item.rarity = ItemDatabase.RARITY_RARE
	elif item.affixes.size() >= 4 and item.rarity == ItemDatabase.RARITY_RARE:
		item.rarity = ItemDatabase.RARITY_LEGENDARY
	inventory_changed.emit()
	equipment_changed.emit()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_upgrade.mp3", -6.0)
	return true


# ─────────────────────────────────────────────────────────────────────────────
# Set crafting: 2 stones of a set + any non-unique, non-set armor/jewelry item
# + essence → the item BECOMES that set's piece (slot preserved, affixes
# re-rolled by the set's rules).
static func craft_cost(item: ItemInstance, set_id: String) -> Dictionary:
	if item == null or item.is_unique or item.rarity == ItemDatabase.RARITY_SET:
		return {}
	if not ItemDatabase.SETS.has(set_id):
		return {}
	if not ItemDatabase.set_eligible_slots().has(item.get_slot()):
		return {}
	return {
		"essence": 6 + int(float(item.ilvl) / 2.0),
		"stones": {set_id: 2},
	}


func craft_set_item(item: ItemInstance, set_id: String) -> bool:
	var cost: Dictionary = craft_cost(item, set_id)
	if GameManager == null or not GameManager.spend_cost(cost):
		return false
	item.rarity = ItemDatabase.RARITY_SET
	item.set_id = set_id
	item.affixes = LootRoller.roll_set_affixes(set_id, item.get_slot(), item.ilvl)
	_rebuild_transform_cache()
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
	_pop_socketed_gems(item)
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
		item = LootRoller._roll_unique(actual_class, max(1, 1 + int(float(wave_hint) / 2.0)))
		if item == null:
			return false
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
		if not ItemDatabase.has_affix(aid):
			continue
		var meta := ItemDatabase.find_affix(aid)
		var min_v: float = meta.roll_min
		var max_v: float = meta.roll_max
		var per_ilvl: float = meta.per_ilvl
		var base: float = randf_range(min_v, max_v)
		var v: float = (base + per_ilvl * float(item.ilvl - 1)) * rar_bonus
		var suffix: String = String(item.affixes[i].get("suffix", ""))
		if suffix == "":
			v = float(round(v))
		else:
			v = float(round(v * 10.0) / 10.0)
		item.affixes[i]["value"] = v
