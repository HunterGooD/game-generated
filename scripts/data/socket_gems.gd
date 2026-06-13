class_name SocketGems
extends RefCounted

# Socket gems ("самоцветы") — run-scoped stones socketed into GEAR sockets.
# NOT the persistent meta "камни зеркала" (MetaGems): these drop in-run, live in
# the bag as ItemInstance (gem_id != ""), die with the run, and their power is
# the LINK system: every gem has a color per face (up/right/down/left); when two
# touching faces of adjacent equipment match color, a link forms and feeds
# attribute bonuses. White faces are conductors: half-strength, but they relay
# a color onward (two blues joined through a white count as full blue links).
#
# Stateless catalog + pure link resolver — socket STATE lives on ItemInstance
# (sockets array), operations in InventorySystem (socket/unsocket/rotate/drill).

# Face colors. Faces are listed [up, right, down, left] (indices 0..3).
const COLOR_RED := "red"  # Сила
const COLOR_GREEN := "green"  # Ловкость
const COLOR_BLUE := "blue"  # Интеллект
const COLOR_WHITE := "white"  # проводник
const COLOR_PRISM := "prism"  # универсальная грань уникальных камней

const FACE_UP := 0
const FACE_RIGHT := 1
const FACE_DOWN := 2
const FACE_LEFT := 3

const COLOR_NAMES: Dictionary = {
	"red": "Красный (Сила)",
	"green": "Зелёный (Ловкость)",
	"blue": "Синий (Интеллект)",
	"white": "Белый (проводник)",
	"prism": "Призма (любой цвет)",
}

# Стрелки граней для тултипов (порядок = up/right/down/left).
const _FACE_ARROWS: Array = ["▲", "▶", "▼", "◀"]

const COLOR_TINTS: Dictionary = {
	"red": Color(0.92, 0.28, 0.24, 1),
	"green": Color(0.32, 0.85, 0.36, 1),
	"blue": Color(0.32, 0.58, 1.0, 1),
	"white": Color(0.9, 0.9, 0.94, 1),
	"prism": Color(0.85, 0.55, 0.95, 1),
}

# Эффекты уникальных камней — активны, пока камень состоит хотя бы в одной связи.
# keystone/chain_echo обрабатывает сам резолвер; blood_obsidian читает GameManager.
const EFFECTS: Dictionary = {
	"keystone":
	{"name": "Замковый камень", "desc": "Все белые связи считаются полными, пока камень в цепи."},
	"chain_echo":
	{"name": "Эхо цепи", "desc": "Цепи с этим камнем считаются на 2 звена длиннее."},
	"blood_obsidian":
	{"name": "Кровавый обсидиан", "desc": "+2% вампиризма, пока камень в цепи."},
}

# Контуры: замкнутый цикл связей цвета (≥2 звена цвета, ≥2 предмета) включает
# билдо-образующий эффект. Боевые крючки живут в GameManager.
const LOOPS: Dictionary = {
	"red": {"name": "Контур крови", "desc": "3% вампиризма от наносимого урона"},
	"green": {"name": "Контур ветра", "desc": "раз в 10 с полностью уклоняет от удара"},
	"blue": {"name": "Контур разума", "desc": "каждый 4-й каст не тратит ману"},
}

# Which attribute a colored link feeds, and how much per link-point.
const LINK_ATTR: Dictionary = {"red": "strength", "green": "dexterity", "blue": "intelligence"}
const LINK_ATTR_NAMES: Dictionary = {"red": "Сила", "green": "Ловкость", "blue": "Интеллект"}
const ATTR_PER_LINK_POINT: float = 5.0
# Each link in a chain beyond the first multiplies the chain's value (+40%/звено).
const CHAIN_BONUS_PER_LINK: float = 0.4

# Резонанс: цепь с 3/5/7 звеньями одного цвета даёт именной процентный бафф
# (ключи — те же, что у аффиксов экипировки: damage/crit_chance/cdr в %-пунктах).
const RESONANCE_THRESHOLDS: Array = [3, 5, 7]
const RESONANCE: Dictionary = {
	"red": {"name": "Кровавый резонанс", "stat": "damage", "values": [8, 16, 25]},
	"green": {"name": "Резонанс ветра", "stat": "crit_chance", "values": [3, 6, 10]},
	"blue": {"name": "Резонанс разума", "stat": "cdr", "values": [4, 8, 12]},
}

# Max sockets per ARMOR slot (weapons: 2H = 2, 1H = 1 — see max_sockets_for_item).
const MAX_SOCKETS: Dictionary = {
	ItemDatabase.SLOT_HELMET: 2,
	ItemDatabase.SLOT_CHEST: 4,
	ItemDatabase.SLOT_GLOVES: 1,
	ItemDatabase.SLOT_BOOTS: 2,
	ItemDatabase.SLOT_AMULET: 1,
	ItemDatabase.SLOT_RING_1: 1,
	ItemDatabase.SLOT_RING_2: 1,
}

# ── Gem catalog ───────────────────────────────────────────────────────────────
# faces = [up, right, down, left]; stats = small flat bonus while socketed
# (the real power is links). rarity reuses item rarity ids for tinting.
const GEMS: Dictionary = {
	# ── common: one color axis + white sides, or a pure conductor ─────────────
	"ruby_shard":
	{
		"name": "Осколок рубина",
		"rarity": "common",
		"faces": ["red", "white", "red", "white"],
		"stats": {"strength": 2},
	},
	"emerald_shard":
	{
		"name": "Осколок изумруда",
		"rarity": "common",
		"faces": ["green", "white", "green", "white"],
		"stats": {"dexterity": 2},
	},
	"sapphire_shard":
	{
		"name": "Осколок сапфира",
		"rarity": "common",
		"faces": ["blue", "white", "blue", "white"],
		"stats": {"intelligence": 2},
	},
	"smoky_quartz":
	{
		"name": "Дымчатый кварц",
		"rarity": "common",
		"faces": ["white", "white", "white", "white"],
		"stats": {"max_hp": 12},
	},
	# ── rare: full mono / alternating duals ───────────────────────────────────
	"ruby":
	{
		"name": "Рубин",
		"rarity": "rare",
		"faces": ["red", "red", "red", "red"],
		"stats": {"strength": 4},
	},
	"emerald":
	{
		"name": "Изумруд",
		"rarity": "rare",
		"faces": ["green", "green", "green", "green"],
		"stats": {"dexterity": 4},
	},
	"sapphire":
	{
		"name": "Сапфир",
		"rarity": "rare",
		"faces": ["blue", "blue", "blue", "blue"],
		"stats": {"intelligence": 4},
	},
	"amber":
	{
		"name": "Янтарь",
		"rarity": "rare",
		"faces": ["red", "green", "red", "green"],
		"stats": {"strength": 2, "dexterity": 2},
	},
	"tourmaline":
	{
		"name": "Турмалин",
		"rarity": "rare",
		"faces": ["green", "blue", "green", "blue"],
		"stats": {"dexterity": 2, "intelligence": 2},
	},
	"amethyst":
	{
		"name": "Аметист",
		"rarity": "rare",
		"faces": ["blue", "red", "blue", "red"],
		"stats": {"intelligence": 2, "strength": 2},
	},
	# ── epic: tri-color / heavy hybrids ───────────────────────────────────────
	"rainbow_opal":
	{
		"name": "Радужный опал",
		"rarity": "legendary",
		"faces": ["red", "green", "blue", "white"],
		"stats": {"strength": 2, "dexterity": 2, "intelligence": 2},
	},
	"volcano_heart":
	{
		"name": "Сердце вулкана",
		"rarity": "legendary",
		"faces": ["red", "red", "blue", "blue"],
		"stats": {"strength": 3, "intelligence": 3, "max_hp": 15},
	},
	"storm_eye":
	{
		"name": "Око бури",
		"rarity": "legendary",
		"faces": ["green", "green", "blue", "blue"],
		"stats": {"dexterity": 3, "intelligence": 3, "max_mana": 15},
	},
	# ── unique: не роллятся обычным дропом — шанс с босс-ноды (см. award_node_essence)
	"prism_shard":
	{
		"name": "Призма",
		"rarity": "unique",
		"faces": ["prism", "prism", "prism", "prism"],
		"stats": {"strength": 2, "dexterity": 2, "intelligence": 2},
	},
	"keystone":
	{
		"name": "Замковый камень",
		"rarity": "unique",
		"faces": ["white", "white", "white", "white"],
		"effect": "keystone",
		"stats": {"max_hp": 20},
	},
	"chain_echo":
	{
		"name": "Эхо цепи",
		"rarity": "unique",
		"faces": ["red", "green", "blue", "white"],
		"effect": "chain_echo",
		"stats": {"max_mana": 20},
	},
	"blood_obsidian":
	{
		"name": "Кровавый обсидиан",
		"rarity": "unique",
		"faces": ["red", "red", "red", "red"],
		"effect": "blood_obsidian",
		"stats": {"strength": 3},
	},
}

# Drop weights by gem rarity (legendary = "epic" tier; uniques are boss-only).
const GEM_RARITY_WEIGHTS: Dictionary = {"common": 100.0, "rare": 36.0, "legendary": 9.0}

# Слияние у Ювелира: 3 одинаковых камня → случайный камень тиром выше.
const RARITY_NEXT: Dictionary = {"common": "rare", "rare": "legendary", "legendary": "unique"}

# ── External wiring: which socket faces touch across the paper doll ──────────
# [slot_a, sock_a, face_a, slot_b, sock_b, face_b] — fixed adjacency graph the
# character sheet also renders as lines. Each (slot, sock, face) appears once.
const WIRING: Array = [
	# Шлем ↕ Доспех (верхний ряд 2×2).
	[ItemDatabase.SLOT_HELMET, 0, FACE_DOWN, ItemDatabase.SLOT_CHEST, 0, FACE_UP],
	[ItemDatabase.SLOT_HELMET, 1, FACE_DOWN, ItemDatabase.SLOT_CHEST, 1, FACE_UP],
	# Украшения: шлем → амулет → кольцо 1 → кольцо 2 (цепочка), кольца ↔ доспех/сапоги.
	[ItemDatabase.SLOT_HELMET, 1, FACE_RIGHT, ItemDatabase.SLOT_AMULET, 0, FACE_LEFT],
	[ItemDatabase.SLOT_AMULET, 0, FACE_DOWN, ItemDatabase.SLOT_RING_1, 0, FACE_UP],
	[ItemDatabase.SLOT_CHEST, 1, FACE_RIGHT, ItemDatabase.SLOT_RING_1, 0, FACE_LEFT],
	[ItemDatabase.SLOT_RING_1, 0, FACE_DOWN, ItemDatabase.SLOT_RING_2, 0, FACE_UP],
	[ItemDatabase.SLOT_BOOTS, 1, FACE_RIGHT, ItemDatabase.SLOT_RING_2, 0, FACE_LEFT],
	# Перчатки ↔ доспех и оружие правой руки.
	[ItemDatabase.SLOT_GLOVES, 0, FACE_RIGHT, ItemDatabase.SLOT_CHEST, 2, FACE_LEFT],
	[ItemDatabase.SLOT_GLOVES, 0, FACE_DOWN, ItemDatabase.SLOT_WEAPON_MAIN, 0, FACE_UP],
	# Доспех (нижний ряд) ↕ сапоги.
	[ItemDatabase.SLOT_CHEST, 2, FACE_DOWN, ItemDatabase.SLOT_BOOTS, 0, FACE_UP],
	[ItemDatabase.SLOT_CHEST, 3, FACE_DOWN, ItemDatabase.SLOT_BOOTS, 1, FACE_UP],
	# Второе гнездо двуручника смотрит вверх на сапоги; левая рука ↔ кольцо 2.
	[ItemDatabase.SLOT_WEAPON_MAIN, 1, FACE_UP, ItemDatabase.SLOT_BOOTS, 0, FACE_DOWN],
	[ItemDatabase.SLOT_RING_2, 0, FACE_DOWN, ItemDatabase.SLOT_WEAPON_OFF, 0, FACE_UP],
]

# Internal adjacency inside one item, by slot (filtered to drilled sockets).
# Chest is a 2×2 grid (0 TL, 1 TR, 2 BL, 3 BR); two-socket rows are horizontal.
const _CHEST_INTERNAL: Array = [
	[0, FACE_RIGHT, 1, FACE_LEFT],
	[2, FACE_RIGHT, 3, FACE_LEFT],
	[0, FACE_DOWN, 2, FACE_UP],
	[1, FACE_DOWN, 3, FACE_UP],
]
const _ROW_INTERNAL: Array = [[0, FACE_RIGHT, 1, FACE_LEFT]]


# ── Catalog lookups ───────────────────────────────────────────────────────────
# Lazily-built typed view of GEMS (gem_id -> GemDefinition). GEMS stays the
# authoring source; this caches one definition per entry.
static var _defs_cache: Dictionary = {}


static func _defs() -> Dictionary:
	if _defs_cache.is_empty():
		for gid in GEMS:
			_defs_cache[gid] = GemDefinition.from_dict(String(gid), GEMS[gid])
	return _defs_cache


static func has_gem(id: String) -> bool:
	return GEMS.has(id)


# Typed catalog entry. Returns a GemDefinition.unknown() placeholder (name == id,
# default fields) for an unknown id, so callers never get null.
static func get_gem(id: String) -> GemDefinition:
	var d = _defs().get(id, null)
	return d if d != null else GemDefinition.unknown(id)


static func display_name(id: String) -> String:
	return get_gem(id).name


static func rarity_of(id: String) -> String:
	return get_gem(id).rarity


static func color_tint(color: String) -> Color:
	return COLOR_TINTS.get(color, Color(0.6, 0.6, 0.6, 1))


# ItemInstance template shim for gem items (kind "gem" never equips: slot -1).
static func template_for(gem_id: String) -> Dictionary:
	return {
		"id": gem_id,
		"kind": "gem",
		"slot": -1,
		"title": display_name(gem_id),
		"icon": "res://assets/sprites/items/crystal_blue.png",
		"class_lock": "",
	}


# Базовые грани из каталога (копия; 4 белых для неизвестного id).
static func base_faces(gem_id: String) -> Array:
	var base: Array = get_gem(gem_id).faces
	if base.size() != 4:
		return ["white", "white", "white", "white"]
	return base.duplicate()


# Корректный массив граней: ровно 4 легальных цвета.
static func valid_faces(faces) -> bool:
	if not (faces is Array) or (faces as Array).size() != 4:
		return false
	for f in (faces as Array):
		if not COLOR_TINTS.has(String(f)):
			return false
	return true


# Повернуть массив граней на `rot` четвертей по часовой.
static func rotate_faces(base: Array, rot: int) -> Array:
	if base.size() != 4:
		return ["white", "white", "white", "white"]
	var out: Array = []
	for dir in 4:
		out.append(String(base[(dir - rot % 4 + 4) % 4]))
	return out


# World-space face colors of a gem after `rot` clockwise quarter-turns.
static func world_faces(gem_id: String, rot: int) -> Array:
	return rotate_faces(base_faces(gem_id), rot)


# Грани вставленного камня с учётом перекраски ("faces" в socket entry) и поворота.
static func entry_world_faces(entry: Dictionary) -> Array:
	var base: Array
	if valid_faces(entry.get("faces", null)):
		base = entry["faces"]
	else:
		base = base_faces(String(entry.get("gem", "")))
	return rotate_faces(base, int(entry.get("rot", 0)))


static func max_sockets_for_item(item: ItemInstance) -> int:
	if item == null or item.is_gem():
		return 0
	if item.is_weapon():
		return 2 if item.is_two_handed() else 1
	return int(MAX_SOCKETS.get(item.get_slot(), 0))


static func internal_links_for(slot: int, count: int) -> Array:
	var raw: Array = []
	if slot == ItemDatabase.SLOT_CHEST:
		raw = _CHEST_INTERNAL
	elif count >= 2:
		raw = _ROW_INTERNAL
	var out: Array = []
	for l in raw:
		if int(l[0]) < count and int(l[2]) < count:
			out.append(l)
	return out


# ── Rolling ───────────────────────────────────────────────────────────────────
static func ids_of_rarity(rarity: String) -> Array:
	var out: Array = []
	for id in GEMS:
		if String((GEMS[id] as Dictionary).get("rarity", "")) == rarity:
			out.append(String(id))
	return out


# Roll one gem id; `luck` shifts rarity weights upward (same shape as MetaGems.roll).
static func roll(luck: float = 0.0) -> String:
	var order: Array = ["common", "rare", "legendary"]
	var total: float = 0.0
	var weights: Dictionary = {}
	for i in order.size():
		var r: String = String(order[i])
		var w: float = float(GEM_RARITY_WEIGHTS.get(r, 0.0)) * (1.0 + maxf(0.0, luck) * float(i))
		weights[r] = w
		total += w
	var pick: float = randf() * total
	var rarity: String = String(order[0])
	for r in order:
		pick -= float(weights[r])
		if pick <= 0.0:
			rarity = String(r)
			break
	var pool: Array = ids_of_rarity(rarity)
	if pool.is_empty():
		return "ruby_shard"
	return String(pool[randi() % pool.size()])


# Случайный УНИКАЛЬНЫЙ камень (босс-нода кидает их отдельным шансом).
static func roll_unique() -> String:
	var pool: Array = ids_of_rarity("unique")
	if pool.is_empty():
		return "prism_shard"
	return String(pool[randi() % pool.size()])


# ── Link resolver ─────────────────────────────────────────────────────────────
# Input: equipment Dictionary[slot → ItemInstance] (InventorySystem.equipment).
# Output:
#   links     — [{a:{slot,idx}, b:{slot,idx}, color, kind:"full"/"half"/"bridge"}]
#               every formed connection, for the character sheet's line overlay.
#   stats     — link bonuses incl. resonance, keyed by stat id (chains folded in).
#   chains    — [{color, links:int, value:float}] per same-color chain (tooltips).
#   resonance — [{color, name, tier:1..3, links:int, stat, value}] active buffs.
#   loops     — Array of colors whose links form a closed cycle (≥2 звена цвета,
#               ≥2 предмета) — «контуры», see LOOPS.
#   effects   — {effect_id: true} of unique gems sitting in ≥1 link, see EFFECTS.
#
# Rules: same colored faces → full link (1.0). Colored face on white → half
# (0.5), UPGRADED to full when its chain carries ≥2 links of that color (the
# white relays: blue→white→blue counts as two full blue links). White on white →
# bridge (0.25 per color it actually connects). A chain of n links multiplies
# its summed value by (1 + 0.4·(n-1)) — длиннее цепь, выше бонус. Цепь с 3/5/7
# звеньями одного цвета дополнительно включает резонанс (см. RESONANCE).
static func resolve(equipment: Dictionary) -> Dictionary:
	var occupied: Dictionary = {}  # "slot:idx" → world faces Array
	var socket_counts: Dictionary = {}  # slot → drilled socket count
	var slots_of: Dictionary = {}  # ItemInstance → [slot,…] (2H mirrors into both hands)
	for slot in equipment:
		var it = equipment[slot]
		if it is ItemInstance:
			if not slots_of.has(it):
				slots_of[it] = []
			(slots_of[it] as Array).append(int(slot))
	for it in slots_of:
		var item := it as ItemInstance
		var slots: Array = slots_of[it]
		slots.sort()  # MAIN(7) < OFF(8) — a both-hands 2H wires through the main hand
		var s: int = int(slots[0])
		if item.sockets.is_empty():
			continue
		socket_counts[s] = item.sockets.size()
		for idx in item.sockets.size():
			var entry = item.sockets[idx]
			if entry is Dictionary and String((entry as Dictionary).get("gem", "")) != "":
				var e := entry as Dictionary
				var gid: String = String(e.get("gem", ""))
				occupied["%d:%d" % [s, idx]] = {
					"faces": entry_world_faces(e),
					"gem": gid,
				}

	# Candidate links: internal (inside one item) + external wiring.
	var links: Array = []
	for s in socket_counts:
		for l in internal_links_for(int(s), int(socket_counts[s])):
			_try_link(occupied, int(s), int(l[0]), int(l[1]), int(s), int(l[2]), int(l[3]), links)
	for w in WIRING:
		_try_link(
			occupied, int(w[0]), int(w[1]), int(w[2]), int(w[3]), int(w[4]), int(w[5]), links
		)

	# Unique-gem effects: active while the gem participates in at least one link.
	var effects: Dictionary = {}
	for l in links:
		for endpoint in ["a", "b"]:
			var p: Dictionary = (l as Dictionary)[endpoint]
			var key: String = "%d:%d" % [int(p["slot"]), int(p["idx"])]
			var eff: String = get_gem(
				String((occupied[key] as Dictionary).get("gem", ""))
			).effect
			if eff != "":
				effects[eff] = true
	var keystone: bool = effects.has("keystone")

	# Per color: split links into chains (connected components) and score them.
	var stats: Dictionary = {}
	var chains: Array = []
	var resonance: Array = []
	var loops: Array = []
	for color in LINK_ATTR:
		var c: String = String(color)
		# Indices of links that can carry this color (own color or white bridge).
		var carriers: Array = []
		for i in links.size():
			var lc: String = String((links[i] as Dictionary).get("color", ""))
			if lc == c or lc == COLOR_WHITE:
				carriers.append(i)
		var best_real: int = 0  # самая длинная одноцветная цепь — порог резонанса
		var loop_found: bool = false
		for comp in _components(links, carriers):
			var real: int = 0
			var echo: bool = false
			for i in comp:
				var l: Dictionary = links[i]
				if String(l.get("color", "")) == c:
					real += 1
				for endpoint in ["a", "b"]:
					var p: Dictionary = l[endpoint]
					var key: String = "%d:%d" % [int(p["slot"]), int(p["idx"])]
					var gid: String = String((occupied[key] as Dictionary).get("gem", ""))
					if get_gem(gid).effect == "chain_echo":
						echo = true
			if real == 0:
				continue  # whites bridging nothing of this color
			best_real = maxi(best_real, real)
			# Замковый камень: ВСЕ белые половинки полные; иначе — правило реле.
			var upgrade: bool = keystone or real >= 2
			var value: float = 0.0
			for i in comp:
				var l: Dictionary = links[i]
				if String(l.get("color", "")) == c:
					if String(l.get("kind", "")) == "full":
						value += 1.0
					else:
						value += 1.0 if upgrade else 0.5
				else:
					value += 0.25
			# Эхо цепи: цепь считается на 2 звена длиннее.
			var n: int = comp.size() + (2 if echo else 0)
			var total: float = value * (1.0 + CHAIN_BONUS_PER_LINK * float(n - 1))
			var attr: String = String(LINK_ATTR[c])
			stats[attr] = float(stats.get(attr, 0.0)) + total * ATTR_PER_LINK_POINT
			chains.append({"color": c, "links": comp.size(), "value": total})
			if not loop_found and _has_color_loop(links, comp, c):
				loop_found = true
		if loop_found:
			loops.append(c)
		# Резонанс — по лучшей цепи цвета (пороги не суммируются между цепями).
		var tier: int = 0
		for t in RESONANCE_THRESHOLDS.size():
			if best_real >= int(RESONANCE_THRESHOLDS[t]):
				tier = t + 1
		if tier > 0:
			var r: Dictionary = RESONANCE[c]
			var stat: String = String(r["stat"])
			var v: int = int((r["values"] as Array)[tier - 1])
			stats[stat] = float(stats.get(stat, 0.0)) + float(v)
			(
				resonance
				. append(
					{
						"color": c,
						"name": String(r["name"]),
						"tier": tier,
						"links": best_real,
						"stat": stat,
						"value": v,
					}
				)
			)
	for k in stats:
		stats[k] = int(round(float(stats[k])))
	return {
		"links": links,
		"stats": stats,
		"chains": chains,
		"resonance": resonance,
		"loops": loops,
		"effects": effects,
	}


# «Контур»: внутри компоненты есть цикл (звено, чьё удаление не разрывает его
# концы), цикловые звенья охватывают ≥2 предмета и несут ≥2 звена цвета `c`.
static func _has_color_loop(links: Array, comp: Array, c: String) -> bool:
	var cycle_links: Array = []
	for i in comp:
		var l: Dictionary = links[i]
		var ka: String = "%d:%d" % [int(l["a"]["slot"]), int(l["a"]["idx"])]
		var kb: String = "%d:%d" % [int(l["b"]["slot"]), int(l["b"]["idx"])]
		if _connected_without(links, comp, int(i), ka, kb):
			cycle_links.append(i)
	if cycle_links.is_empty():
		return false
	var slots: Dictionary = {}
	var colored: int = 0
	for i in cycle_links:
		var l: Dictionary = links[i]
		slots[int(l["a"]["slot"])] = true
		slots[int(l["b"]["slot"])] = true
		if String(l.get("color", "")) == c:
			colored += 1
	return slots.size() >= 2 and colored >= 2


# BFS: достижим ли `goal` из `start` по звеньям `comp`, исключая звено `skip`.
static func _connected_without(
	links: Array, comp: Array, skip: int, start: String, goal: String
) -> bool:
	var frontier: Array = [start]
	var seen: Dictionary = {start: true}
	while not frontier.is_empty():
		var cur: String = String(frontier.pop_back())
		if cur == goal:
			return true
		for i in comp:
			if int(i) == skip:
				continue
			var l: Dictionary = links[i]
			var ka: String = "%d:%d" % [int(l["a"]["slot"]), int(l["a"]["idx"])]
			var kb: String = "%d:%d" % [int(l["b"]["slot"]), int(l["b"]["idx"])]
			var next: String = ""
			if ka == cur:
				next = kb
			elif kb == cur:
				next = ka
			if next != "" and not seen.has(next):
				seen[next] = true
				frontier.append(next)
	return false


# Append a link if both sockets hold gems and the touching faces are compatible.
static func _try_link(
	occupied: Dictionary,
	slot_a: int,
	sock_a: int,
	face_a: int,
	slot_b: int,
	sock_b: int,
	face_b: int,
	out: Array
) -> void:
	var ka: String = "%d:%d" % [slot_a, sock_a]
	var kb: String = "%d:%d" % [slot_b, sock_b]
	if not occupied.has(ka) or not occupied.has(kb):
		return
	var ca: String = String(((occupied[ka] as Dictionary)["faces"] as Array)[face_a])
	var cb: String = String(((occupied[kb] as Dictionary)["faces"] as Array)[face_b])
	# Призма подстраивается под соседа (призма-призма/призма-белый = мост).
	if ca == COLOR_PRISM and cb != COLOR_PRISM and cb != COLOR_WHITE:
		ca = cb
	elif cb == COLOR_PRISM and ca != COLOR_PRISM and ca != COLOR_WHITE:
		cb = ca
	elif ca == COLOR_PRISM or cb == COLOR_PRISM:
		ca = COLOR_WHITE
		cb = COLOR_WHITE
	var color: String = ""
	var kind: String = ""
	if ca == cb and ca != COLOR_WHITE:
		color = ca
		kind = "full"
	elif ca == COLOR_WHITE and cb == COLOR_WHITE:
		color = COLOR_WHITE
		kind = "bridge"
	elif ca == COLOR_WHITE:
		color = cb
		kind = "half"
	elif cb == COLOR_WHITE:
		color = ca
		kind = "half"
	else:
		return  # два разных цвета лицом к лицу — связи нет
	(
		out
		. append(
			{
				"a": {"slot": slot_a, "idx": sock_a},
				"b": {"slot": slot_b, "idx": sock_b},
				"color": color,
				"kind": kind,
			}
		)
	)


# Connected components over the subset `idxs` of `links` (nodes = socket keys).
# Returns Array of Arrays of link indices.
static func _components(links: Array, idxs: Array) -> Array:
	var adj: Dictionary = {}  # socket key → [link index,…]
	for i in idxs:
		var l: Dictionary = links[i]
		for endpoint in ["a", "b"]:
			var p: Dictionary = l[endpoint]
			var key: String = "%d:%d" % [int(p["slot"]), int(p["idx"])]
			if not adj.has(key):
				adj[key] = []
			(adj[key] as Array).append(i)
	var seen_links: Dictionary = {}
	var out: Array = []
	for i in idxs:
		if seen_links.has(i):
			continue
		var comp: Array = []
		var queue: Array = [i]
		seen_links[i] = true
		while not queue.is_empty():
			var li: int = int(queue.pop_back())
			comp.append(li)
			var l: Dictionary = links[li]
			for endpoint in ["a", "b"]:
				var p: Dictionary = l[endpoint]
				var key: String = "%d:%d" % [int(p["slot"]), int(p["idx"])]
				for nb in adj.get(key, []):
					if not seen_links.has(nb):
						seen_links[nb] = true
						queue.append(nb)
		out.append(comp)
	return out


# ── Display helpers ───────────────────────────────────────────────────────────
# Multiline RU tooltip for a gem (rot rotates the shown faces; faces_override —
# перекрашенные Ювелиром грани вместо каталожных).
static func describe(gem_id: String, rot: int = 0, faces_override: Array = []) -> String:
	if not has_gem(gem_id):
		return gem_id
	var g := get_gem(gem_id)
	var lines: Array = []
	lines.append(g.name)
	lines.append("Самоцвет — %s" % ItemDatabase.rarity_display(g.rarity))
	var repainted: bool = valid_faces(faces_override) and faces_override != base_faces(gem_id)
	var faces: Array
	if valid_faces(faces_override):
		faces = rotate_faces(faces_override, rot)
	else:
		faces = world_faces(gem_id, rot)
	if repainted:
		lines.append("Перекрашен ювелиром.")
	var face_parts: Array = []
	for dir in 4:
		face_parts.append(
			"%s %s" % [String(_FACE_ARROWS[dir]), String(COLOR_NAMES.get(faces[dir], "?"))]
		)
	lines.append("Грани: " + "  ".join(face_parts))
	for line in stat_lines(gem_id):
		lines.append("  " + String(line))
	var eff: String = g.effect
	if eff != "" and EFFECTS.has(eff):
		lines.append("✦ " + String((EFFECTS[eff] as Dictionary).get("desc", "")))
	lines.append("Вставляется в гнездо экипировки; совпавшие грани соседей дают связь.")
	return "\n".join(lines)


# Готовые строки сводки связей для листа персонажа: итоги по цветам, резонансы,
# длинные цепи, контуры и активные эффекты уникальных камней. [] — связей нет.
static func summary_lines(res: Dictionary) -> Array:
	var out: Array = []
	if (res.get("chains", []) as Array).is_empty():
		return out
	out.append("Связи самоцветов:")
	var totals: Dictionary = res.get("stats", {})
	for color in LINK_ATTR:
		var attr: String = String(LINK_ATTR[color])
		if int(totals.get(attr, 0)) > 0:
			out.append("  ✓ +%d %s" % [int(totals[attr]), String(LINK_ATTR_NAMES[color])])
	var stat_names: Dictionary = {
		"damage": "к урону", "crit_chance": "к шансу крита", "cdr": "к перезарядке"
	}
	for r in res.get("resonance", []):
		var rd: Dictionary = r
		out.append(
			"  ✦ %s %s — +%d%% %s (цепь %d)" % [
				String(rd.get("name", "")),
				"III".substr(0, int(rd.get("tier", 1))),
				int(rd.get("value", 0)),
				String(stat_names.get(String(rd.get("stat", "")), "")),
				int(rd.get("links", 0)),
			]
		)
	for ch in res.get("chains", []):
		var c: Dictionary = ch
		if int(c.get("links", 0)) >= 2:
			out.append(
				"    цепь ×%d (%s)" % [int(c.get("links", 0)), String(
					LINK_ATTR_NAMES.get(String(c.get("color", "")), "?")
				)]
			)
	for loop_color in res.get("loops", []):
		var ld: Dictionary = LOOPS.get(String(loop_color), {})
		out.append("  ⭘ %s — %s" % [String(ld.get("name", loop_color)), String(ld.get("desc", ""))])
	for eff_id in res.get("effects", {}):
		var ed: Dictionary = EFFECTS.get(String(eff_id), {})
		out.append("  ✦ %s — %s" % [String(ed.get("name", eff_id)), String(ed.get("desc", ""))])
	return out


# "+2 Сила"-style lines for the gem's flat stats (bag cells, roulette).
static func stat_lines(gem_id: String) -> Array:
	var labels: Dictionary = {
		"strength": "Сила",
		"dexterity": "Ловкость",
		"intelligence": "Интеллект",
		"max_hp": "Макс. здоровье",
		"max_mana": "Макс. мана",
	}
	var out: Array = []
	var stats: Dictionary = get_gem(gem_id).stats
	for k in stats:
		out.append("+%d %s" % [int(stats[k]), String(labels.get(k, String(k).capitalize()))])
	return out
