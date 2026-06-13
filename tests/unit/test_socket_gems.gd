extends GutTest

# Gear sockets + socket gems: catalog/wiring integrity, rotation, the link
# resolver (full/half/relay rules + chain bonus), inventory socket operations,
# drill costs, serialization, meta fortune grants.


func before_each() -> void:
	_reset()


func after_each() -> void:
	_reset()


func _reset() -> void:
	GameManager.gold = 0
	GameManager.materials = {"scrap": 0, "cloth": 0, "essence": 0}
	InventorySystem.inventory.clear()
	InventorySystem.equipment.clear()
	InventorySystem._rebuild_transform_cache()


func _mk(base_id: String) -> ItemInstance:
	var it := ItemInstance.new()
	it.base_id = base_id
	it.rarity = ItemDatabase.RARITY_COMMON
	return it


func _socketed(base_id: String, gems: Array) -> ItemInstance:
	# gems: array of null or [gem_id, rot]
	var it := _mk(base_id)
	for g in gems:
		if g == null:
			it.sockets.append(null)
		else:
			it.sockets.append({"gem": String((g as Array)[0]), "rot": int((g as Array)[1])})
	return it


# ── catalog / wiring integrity ────────────────────────────────────────────────
func test_catalog_and_wiring_integrity() -> void:
	var legal := ["red", "green", "blue", "white", "prism"]
	for id in SocketGems.GEMS:
		var g: Dictionary = SocketGems.GEMS[id]
		var faces: Array = g.get("faces", [])
		assert_eq(faces.size(), 4, "%s must have 4 faces" % id)
		for f in faces:
			assert_has(legal, String(f), "%s has illegal face color %s" % [id, f])
		var rarity := String(g.get("rarity", ""))
		assert_true(
			SocketGems.GEM_RARITY_WEIGHTS.has(rarity) or rarity == "unique",
			"%s rarity must be rollable or unique" % id
		)
		var eff := String(g.get("effect", ""))
		if eff != "":
			assert_true(SocketGems.EFFECTS.has(eff), "%s has unknown effect %s" % [id, eff])
	_check_wiring()
	_check_rotation_and_max_sockets()


func _check_wiring() -> void:
	# Каждая грань (slot, sock, face) задействована не более одного раза…
	var used: Dictionary = {}
	for w in SocketGems.WIRING:
		for side in [[0, 1, 2], [3, 4, 5]]:
			var key := "%d:%d:%d" % [int(w[side[0]]), int(w[side[1]]), int(w[side[2]])]
			assert_false(used.has(key), "wiring reuses face %s" % key)
			used[key] = true
	for slot in SocketGems.MAX_SOCKETS:
		var cap: int = int(SocketGems.MAX_SOCKETS[slot])
		for l in SocketGems.internal_links_for(int(slot), cap):
			for side in [[0, 1], [2, 3]]:
				var key := "%d:%d:%d" % [int(slot), int(l[side[0]]), int(l[side[1]])]
				assert_false(used.has(key), "internal link reuses face %s" % key)
				used[key] = true
	# …и индексы гнёзд не выходят за максимум слота.
	for w in SocketGems.WIRING:
		for side in [[0, 1], [3, 4]]:
			var slot: int = int(w[side[0]])
			var sock: int = int(w[side[1]])
			var cap: int
			if slot == ItemDatabase.SLOT_WEAPON_MAIN or slot == ItemDatabase.SLOT_WEAPON_OFF:
				cap = 2 if slot == ItemDatabase.SLOT_WEAPON_MAIN else 1
			else:
				cap = int(SocketGems.MAX_SOCKETS.get(slot, 0))
			assert_lt(sock, cap, "wiring socket %d exceeds slot %d max" % [sock, slot])


# ── rotation / max sockets ────────────────────────────────────────────────────
func _check_rotation_and_max_sockets() -> void:
	# ruby_shard = [red, white, red, white]; one clockwise turn moves up→right.
	assert_eq(SocketGems.world_faces("ruby_shard", 0), ["red", "white", "red", "white"])
	assert_eq(SocketGems.world_faces("ruby_shard", 1), ["white", "red", "white", "red"])
	assert_eq(SocketGems.world_faces("ruby_shard", 4), ["red", "white", "red", "white"])
	assert_eq(_mk("iron_helmet").max_sockets(), 2)
	assert_eq(_mk("plate_chest").max_sockets(), 4)
	assert_eq(_mk("signet_ring").max_sockets(), 1)
	assert_eq(_mk("barb_2h_axe").max_sockets(), 2)
	assert_eq(_mk("barb_1h_axe").max_sockets(), 1)
	assert_eq(InventorySystem.make_gem_item("ruby").max_sockets(), 0)


# ── link resolver ─────────────────────────────────────────────────────────────
func test_full_link_red_on_red() -> void:
	var eq := {
		ItemDatabase.SLOT_HELMET: _socketed("iron_helmet", [["ruby_shard", 0]]),
		ItemDatabase.SLOT_CHEST: _socketed("plate_chest", [["ruby_shard", 0]]),
	}
	var res: Dictionary = SocketGems.resolve(eq)
	assert_eq((res["links"] as Array).size(), 1)
	assert_eq(String((res["links"][0] as Dictionary)["kind"]), "full")
	# 1 full link × 5 strength, no chain bonus.
	assert_eq(int(res["stats"].get("strength", 0)), 5)
	# Два РАЗНЫХ цвета лицом к лицу — связи нет.
	var mismatch := {
		ItemDatabase.SLOT_HELMET: _socketed("iron_helmet", [["ruby", 0]]),
		ItemDatabase.SLOT_CHEST: _socketed("plate_chest", [["sapphire", 0]]),
	}
	var none: Dictionary = SocketGems.resolve(mismatch)
	assert_eq((none["links"] as Array).size(), 0)
	assert_true((none["stats"] as Dictionary).is_empty())


func test_rotated_gem_makes_half_link() -> void:
	# Helmet gem rotated: its down face becomes white → half link (0.5 × 5 → 3).
	var eq := {
		ItemDatabase.SLOT_HELMET: _socketed("iron_helmet", [["ruby_shard", 1]]),
		ItemDatabase.SLOT_CHEST: _socketed("plate_chest", [["ruby_shard", 0]]),
	}
	var res: Dictionary = SocketGems.resolve(eq)
	assert_eq((res["links"] as Array).size(), 1)
	assert_eq(String((res["links"][0] as Dictionary)["kind"]), "half")
	assert_eq(int(res["stats"].get("strength", 0)), 3)


func test_white_relay_upgrades_half_links() -> void:
	# Пример из спеки: синий → белый → синий считается как ДВЕ полные синие связи.
	# helmet socket 1 right(B, rot 1) ↔ amulet(all white) ↔ ring1 up(B).
	var helmet := _socketed("iron_helmet", [null, ["sapphire_shard", 1]])
	var amulet := _socketed("gothic_amulet", [["smoky_quartz", 0]])
	var ring := _socketed("signet_ring", [["sapphire_shard", 0]])
	var eq := {
		ItemDatabase.SLOT_HELMET: helmet,
		ItemDatabase.SLOT_AMULET: amulet,
		ItemDatabase.SLOT_RING_1: ring,
	}
	var res: Dictionary = SocketGems.resolve(eq)
	assert_eq((res["links"] as Array).size(), 2)
	# Both halves upgraded to 1.0 → value 2.0, chain ×1.4 → 2.8 × 5 = 14.
	assert_eq(int(res["stats"].get("intelligence", 0)), 14)


func test_internal_chest_links() -> void:
	# Two reds side by side INSIDE the chest link internally.
	var chest := _socketed("plate_chest", [["ruby", 0], ["ruby", 0]])
	var res: Dictionary = SocketGems.resolve({ItemDatabase.SLOT_CHEST: chest})
	assert_eq((res["links"] as Array).size(), 1)
	assert_eq(int(res["stats"].get("strength", 0)), 5)


func test_loops_and_unique_gems() -> void:
	# Контур: шлем(2×рубин) + доспех(2×рубин) = цикл из 4 красных звеньев на 2 предметах.
	var loop_eq := {
		ItemDatabase.SLOT_HELMET: _socketed("iron_helmet", [["ruby", 0], ["ruby", 0]]),
		ItemDatabase.SLOT_CHEST: _socketed("plate_chest", [["ruby", 0], ["ruby", 0]]),
	}
	var loop_res: Dictionary = SocketGems.resolve(loop_eq)
	assert_eq((loop_res["links"] as Array).size(), 4)
	assert_has(loop_res["loops"] as Array, "red", "красный контур замкнулся")
	# Призма коннектится с любым цветом как полная связь.
	var prism_eq := {
		ItemDatabase.SLOT_HELMET: _socketed("iron_helmet", [["prism_shard", 0]]),
		ItemDatabase.SLOT_CHEST: _socketed("plate_chest", [["ruby_shard", 0]]),
	}
	var prism_res: Dictionary = SocketGems.resolve(prism_eq)
	assert_eq(String((prism_res["links"][0] as Dictionary)["kind"]), "full")
	assert_eq(int(prism_res["stats"].get("strength", 0)), 5)
	# Эффект уникального камня активен, пока он состоит в связи.
	var obsidian_eq := {
		ItemDatabase.SLOT_HELMET: _socketed("iron_helmet", [["blood_obsidian", 0]]),
		ItemDatabase.SLOT_CHEST: _socketed("plate_chest", [["ruby", 0]]),
	}
	var ob_res: Dictionary = SocketGems.resolve(obsidian_eq)
	assert_true((ob_res["effects"] as Dictionary).has("blood_obsidian"))
	var lonely := {ItemDatabase.SLOT_HELMET: _socketed("iron_helmet", [["blood_obsidian", 0]])}
	assert_false(
		(SocketGems.resolve(lonely)["effects"] as Dictionary).has("blood_obsidian"),
		"камень без связей — эффект спит"
	)
	# Эхо цепи: цепь считается на 2 звена длиннее (1.0 × (1+0.4·2) × 5 = 9 инт).
	var echo_eq := {
		ItemDatabase.SLOT_HELMET: _socketed("iron_helmet", [["chain_echo", 0]]),
		ItemDatabase.SLOT_CHEST: _socketed("plate_chest", [["sapphire_shard", 0]]),
	}
	var echo_res: Dictionary = SocketGems.resolve(echo_eq)
	assert_eq(int(echo_res["stats"].get("intelligence", 0)), 9)
	# Замковый камень: белые половинки полные даже в одиночной связи цвета.
	var key_eq := {
		ItemDatabase.SLOT_HELMET: _socketed("iron_helmet", [["ruby_shard", 1]]),
		ItemDatabase.SLOT_CHEST: _socketed("plate_chest", [["ruby_shard", 0], ["keystone", 0]]),
	}
	var key_res: Dictionary = SocketGems.resolve(key_eq)
	assert_true((key_res["effects"] as Dictionary).has("keystone"))
	# half-красная 1.0 + мост 0.25 = 1.25 × (1+0.4) = 1.75 × 5 = 8.75 → 9.
	assert_eq(int(key_res["stats"].get("strength", 0)), 9)


func test_resonance_thresholds() -> void:
	# Полный доспех 2×2 из рубинов = 4 полные красные связи в одной цепи:
	# value 4 × (1 + 0.4·3) = 8.8 → 44 силы, и Кровавый резонанс I (+8% урона).
	var chest := _socketed(
		"plate_chest", [["ruby", 0], ["ruby", 0], ["ruby", 0], ["ruby", 0]]
	)
	var res: Dictionary = SocketGems.resolve({ItemDatabase.SLOT_CHEST: chest})
	assert_eq((res["links"] as Array).size(), 4)
	assert_eq(int(res["stats"].get("strength", 0)), 44)
	assert_eq(int(res["stats"].get("damage", 0)), 8)
	var reso: Array = res.get("resonance", [])
	assert_eq(reso.size(), 1)
	assert_eq(int((reso[0] as Dictionary).get("tier", 0)), 1)
	assert_eq(String((reso[0] as Dictionary).get("color", "")), "red")


func test_two_handed_weapon_resolves_once() -> void:
	# A 2H mirrored into both hands must not produce duplicate sockets/links.
	var axe := _socketed("barb_2h_axe", [["ruby", 0], ["ruby", 0]])
	var eq := {
		ItemDatabase.SLOT_WEAPON_MAIN: axe,
		ItemDatabase.SLOT_WEAPON_OFF: axe,
	}
	var res: Dictionary = SocketGems.resolve(eq)
	assert_eq((res["links"] as Array).size(), 1)
	assert_eq(int(res["stats"].get("strength", 0)), 5)


# ── inventory operations ──────────────────────────────────────────────────────
func test_socket_and_unsocket_roundtrip() -> void:
	var helmet := _socketed("iron_helmet", [null])
	InventorySystem.add_item(helmet)
	var gem := InventorySystem.make_gem_item("ruby")
	InventorySystem.add_item(gem)
	assert_true(InventorySystem.socket_gem(helmet, 0, gem))
	assert_false(InventorySystem.inventory.has(gem))
	assert_eq(String(helmet.socket_entry(0).get("gem", "")), "ruby")
	assert_true(InventorySystem.unsocket_gem(helmet, 0))
	assert_true(helmet.socket_entry(0).is_empty())
	var back: bool = false
	for it in InventorySystem.inventory:
		if it is ItemInstance and (it as ItemInstance).gem_id == "ruby":
			back = true
	assert_true(back, "unsocketed gem returns to the bag")
	# Поворот: четверть оборота по часовой за вызов.
	var rotated := _socketed("iron_helmet", [["ruby_shard", 0]])
	assert_true(InventorySystem.rotate_socket_gem(rotated, 0))
	assert_eq(int(rotated.socket_entry(0).get("rot", 0)), 1)


func test_move_socket_gem_swaps() -> void:
	var helmet := _socketed("iron_helmet", [["ruby", 0]])
	var chest := _socketed("plate_chest", [["sapphire", 2]])
	assert_true(InventorySystem.move_socket_gem(helmet, 0, chest, 0))
	assert_eq(String(helmet.socket_entry(0).get("gem", "")), "sapphire")
	assert_eq(int(helmet.socket_entry(0).get("rot", 0)), 2, "rotation travels with the gem")
	assert_eq(String(chest.socket_entry(0).get("gem", "")), "ruby")


func test_drilling() -> void:
	# Цена (только эссенция) растёт с числом гнёзд и исчезает на максимуме.
	var helmet := _mk("iron_helmet")
	assert_eq(InventorySystem.drill_cost(helmet), {"essence": 3})
	helmet.sockets.append(null)
	assert_eq(InventorySystem.drill_cost(helmet), {"essence": 6})
	helmet.sockets.append(null)
	assert_true(InventorySystem.drill_cost(helmet).is_empty(), "at max — no more drilling")
	assert_true(InventorySystem.drill_cost(InventorySystem.make_gem_item("ruby")).is_empty())
	# Сверление списывает материалы.
	var fresh := _mk("iron_helmet")
	assert_false(InventorySystem.drill_socket(fresh), "no materials — no socket")
	GameManager.materials = {"scrap": 0, "cloth": 0, "essence": 3}
	assert_true(InventorySystem.drill_socket(fresh))
	assert_eq(fresh.sockets.size(), 1)
	assert_eq(GameManager.get_material("essence"), 0)


func test_salvage_pops_gems_back() -> void:
	var helmet := _socketed("iron_helmet", [["ruby", 0]])
	InventorySystem.add_item(helmet)
	InventorySystem.salvage_item(helmet)
	var found: bool = false
	for it in InventorySystem.inventory:
		if it is ItemInstance and (it as ItemInstance).gem_id == "ruby":
			found = true
	assert_true(found, "salvaging a socketed item returns its gems")


func test_link_bonus_flows_into_totals() -> void:
	InventorySystem.equipment[ItemDatabase.SLOT_HELMET] = _socketed(
		"iron_helmet", [["ruby_shard", 0]]
	)
	InventorySystem.equipment[ItemDatabase.SLOT_CHEST] = _socketed(
		"plate_chest", [["ruby_shard", 0]]
	)
	InventorySystem._rebuild_transform_cache()
	# 2 × gem flat (+2 сила) + full link (+5) = 9.
	assert_eq(int(round(InventorySystem.get_total("strength"))), 9)


# ── serialization ─────────────────────────────────────────────────────────────
func test_serialization_roundtrip() -> void:
	var helmet := _socketed("iron_helmet", [null, ["ruby_shard", 3]])
	var copy := ItemInstance.from_dict(helmet.to_dict())
	assert_eq(copy.sockets.size(), 2)
	assert_true(copy.socket_entry(0).is_empty())
	assert_eq(String(copy.socket_entry(1).get("gem", "")), "ruby_shard")
	assert_eq(int(copy.socket_entry(1).get("rot", 0)), 3)
	var gem := InventorySystem.make_gem_item("storm_eye")
	var gem_copy := ItemInstance.from_dict(gem.to_dict())
	assert_eq(gem_copy.gem_id, "storm_eye")
	assert_true(gem_copy.is_gem())
	# Чужой пере-сокеченный предмет (старый/модифицированный клиент) обрезается.
	var d: Dictionary = _mk("signet_ring").to_dict()
	d["sockets"] = [null, null, null]
	var capped := ItemInstance.from_dict(d)
	assert_eq(capped.sockets.size(), 1, "foreign over-socketed item is clamped")


# ── meta fortune grants ───────────────────────────────────────────────────────
func test_fortune_nodes_exist_in_every_tree() -> void:
	for cid in ["barbarian", "rogue", "mage", "stormcaller", "hexen", "necromancer", "druid"]:
		for nid in [
			"fortune_gold",
			"fortune_socket",
			"fortune_socket_2",
			"fortune_materials",
			"fortune_gems_1",
			"fortune_gems_2",
			"fortune_gems_3",
		]:
			assert_true(MetaTrees.has_node(cid, nid), "%s missing %s" % [cid, nid])


func test_jeweler_fuse_and_repaint() -> void:
	# Слияние: 3 одинаковых → случайный камень тиром выше, жертвы исчезают.
	for _i in 3:
		InventorySystem.add_item(InventorySystem.make_gem_item("ruby_shard"))
	var fused: ItemInstance = InventorySystem.fuse_gems("ruby_shard")
	assert_not_null(fused)
	assert_eq(fused.rarity, "rare")
	assert_eq(InventorySystem.count_bag_gems("ruby_shard"), 0)
	# Fuse returns a RANDOM tier-up gem that can itself be a "ruby"; drop it so it
	# can't inflate the "only 2 ruby" count below (was an RNG-flaky CI failure).
	InventorySystem.inventory.erase(fused)
	# Двух не хватает; уникальные выше не сливаются.
	InventorySystem.add_item(InventorySystem.make_gem_item("ruby"))
	InventorySystem.add_item(InventorySystem.make_gem_item("ruby"))
	assert_null(InventorySystem.fuse_gems("ruby"))
	for _i in 3:
		InventorySystem.add_item(InventorySystem.make_gem_item("keystone"))
	assert_null(InventorySystem.fuse_gems("keystone"))
	# Перекраска: без средств — отказ; с оплатой меняет грань.
	var gem := InventorySystem.make_gem_item("ruby_shard")  # [R,W,R,W]
	InventorySystem.add_item(gem)
	assert_false(InventorySystem.repaint_gem_face(gem, 1, "red"), "no funds — refuse")
	GameManager.gold = 150
	GameManager.materials = {"scrap": 0, "cloth": 0, "essence": 8}
	assert_true(InventorySystem.repaint_gem_face(gem, 1, "red"))
	assert_eq(GameManager.gold, 0)
	assert_eq(gem.get_gem_faces(), ["red", "red", "red", "white"])
	# Перекрашенная грань реально работает в связи (шлем-гнездо 1 ▶ амулет ◀).
	var helmet := _mk("iron_helmet")
	helmet.sockets = [null, {"gem": "ruby_shard", "rot": 0, "faces": gem.gem_faces}]
	var amulet := _socketed("gothic_amulet", [["ruby", 0]])
	var res: Dictionary = SocketGems.resolve(
		{ItemDatabase.SLOT_HELMET: helmet, ItemDatabase.SLOT_AMULET: amulet}
	)
	assert_eq((res["links"] as Array).size(), 1)
	assert_eq(String((res["links"][0] as Dictionary)["kind"]), "full")
	# Сериализация переносит перекраску (и в сумке, и в гнезде).
	var copy := ItemInstance.from_dict(gem.to_dict())
	assert_eq(copy.gem_faces, ["red", "red", "red", "white"])
	var hcopy := ItemInstance.from_dict(helmet.to_dict())
	assert_eq(hcopy.socket_entry(1).get("faces", []), ["red", "red", "red", "white"])


func test_node_essence_rewards() -> void:
	# Магазин/костёр платят эссенцией на входе, боевые ноды — по победе.
	GameManager.run_node_active = {}
	GameManager.begin_run_node({"type": RunMap.TYPE_MERCHANT})
	assert_eq(GameManager.get_material("essence"), 5, "merchant pays on enter")
	GameManager.clear_run_node()
	assert_eq(GameManager.get_material("essence"), 5, "merchant clear pays nothing extra")
	GameManager.begin_run_node({"type": RunMap.TYPE_ELITE})
	assert_eq(GameManager.get_material("essence"), 5, "combat node pays on clear, not enter")
	GameManager.clear_run_node()
	assert_eq(GameManager.get_material("essence"), 10, "elite victory pays +5")


func test_run_grants_sums_allocated_fortune_nodes() -> void:
	var saved: Dictionary = MetaProgress._data
	MetaProgress._data = {
		"version": 2,
		"shards": 0,
		"gems": {},
		"classes":
		{
			"mage":
			{
				"meta_level": 5,
				"meta_xp": 0,
				"allocated":
				["fortune_gold", "fortune_materials", "fortune_gems_1", "fortune_socket"],
				"sockets": {},
				"ranks": {},
			}
		},
	}
	var g: Dictionary = MetaProgress.run_grants("mage")
	MetaProgress._data = saved
	assert_eq(int(g.get("gold", 0)), 100)
	assert_eq(int(g.get("start_gems", 0)), 1)
	assert_almost_eq(float(g.get("socket_chance", 0.0)), 0.06, 0.001)
	assert_eq(int((g.get("materials", {}) as Dictionary).get("scrap", 0)), 4)
