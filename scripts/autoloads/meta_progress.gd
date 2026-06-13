extends Node

# MetaProgress — persistent meta-progression ("mirror") state, saved to user://meta.save.
# Per class we track a meta-level (grown by run XP), the set of allocated tree nodes, and
# per-socket gem slots. GLOBAL (cross-class) state: the mirror-shard wallet (meta currency
# dropped by mini-bosses/bosses) and the gem inventory (uber-boss drops + the hub Fortune
# Teller's gamble). Bonuses from allocated nodes AND socketed gems are folded into
# GameManager at the start of every run (reset_run).
#
# Co-op: this is purely LOCAL — each peer loads its own save and applies its own tree to
# its own player. Nothing here is networked (HP/stat authority is owner-side; see the
# coop sync audit), so two players' mirrors never need to agree.
#
# Phase A = infra; Phase B = tree UI; Phase C = all class trees; Phase E (this) = gems:
# shards, gem inventory, socketing. Gem DATA lives in MetaGems; tree DATA in MetaTrees;
# this autoload owns only the per-player STATE.

# Emitted on wallet/inventory changes so open UIs (gamble shop, tree panel) refresh live.
signal shards_changed(total: int)
signal gems_changed

const SAVE_PATH: String = "user://meta.save"
const SAVE_VERSION: int = 2
# 1 passive point per meta level past the first (level 1 = 0 points; the start node is
# always free). XP needed to reach the next level scales linearly with the current level.
const XP_PER_LEVEL_BASE: int = 100

# {
#   "version": int,
#   "shards": int,                      — mirror shards (global meta currency)
#   "gems": { <gem_id>: count },        — unsocketed gem inventory (global)
#   "classes": { <class_id>: { meta_level, meta_xp, allocated[], sockets{}, ranks{} } }
# }   sockets: socket node id -> gem_id (or null while empty)
var _data: Dictionary = {"version": SAVE_VERSION, "classes": {}, "shards": 0, "gems": {}}


func _ready() -> void:
	_load()
	# Flush any mid-run meta XP to disk when a run wraps up — a natural, infrequent save
	# point (level-ups already persist immediately; this catches the leftover XP).
	if GameManager != null and GameManager.has_signal("run_completed"):
		GameManager.run_completed.connect(_save)


# ── persistence ───────────────────────────────────────────────────────────────
func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("meta.save unreadable — starting fresh")
		return
	_data = _migrate(parsed)


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("could not write meta.save")
		return
	f.store_string(JSON.stringify(_data))
	f.close()


# Schema migration hook — bump SAVE_VERSION and branch here when the format changes.
func _migrate(d: Dictionary) -> Dictionary:
	var v: int = int(d.get("version", 0))
	if v < SAVE_VERSION:
		# v1 → v2 just adds the global shard wallet + gem inventory (defaulted below).
		d["version"] = SAVE_VERSION
	if not d.has("classes") or typeof(d["classes"]) != TYPE_DICTIONARY:
		d["classes"] = {}
	if typeof(d.get("shards")) != TYPE_FLOAT and typeof(d.get("shards")) != TYPE_INT:
		d["shards"] = 0
	if typeof(d.get("gems")) != TYPE_DICTIONARY:
		d["gems"] = {}
	return d


# Return the live (mutable) state dict for a class, creating a default entry on first use.
func _entry(class_id: String) -> Dictionary:
	var classes: Dictionary = _data["classes"]
	if not classes.has(class_id):
		classes[class_id] = {"meta_level": 1, "meta_xp": 0, "allocated": [], "sockets": {}, "ranks": {}}
	var e: Dictionary = classes[class_id]
	# Forward-compat: older saves predate `ranks` (repeatable-node levels).
	if not e.has("ranks"):
		e["ranks"] = {}
	return e


# ── queries ───────────────────────────────────────────────────────────────────
func get_meta_level(class_id: String) -> int:
	return int(_entry(class_id).get("meta_level", 1))


func get_meta_xp(class_id: String) -> int:
	return int(_entry(class_id).get("meta_xp", 0))


func xp_to_next(class_id: String) -> int:
	return XP_PER_LEVEL_BASE * get_meta_level(class_id)


func allocated_nodes(class_id: String) -> Array:
	var a: Array = _entry(class_id).get("allocated", [])
	return a


# Total passive points granted by the class's meta level (start node is free, so level 1
# grants 0; each level after grants one).
func points_total(class_id: String) -> int:
	return maxi(0, get_meta_level(class_id) - 1)


func points_available(class_id: String) -> int:
	return points_total(class_id) - _points_spent(class_id)


# Total points sunk: one per distinct allocated node, plus every EXTRA rank on a repeatable
# node (the first rank is already counted in the allocated set).
func _points_spent(class_id: String) -> int:
	var spent: int = allocated_nodes(class_id).size()
	var ranks: Dictionary = _entry(class_id).get("ranks", {})
	for id in ranks:
		spent += maxi(0, int(ranks[id]) - 1)
	return spent


func is_allocated(class_id: String, node_id: String) -> bool:
	return allocated_nodes(class_id).has(node_id)


# How many times a repeatable node has been ranked up (0 = not taken).
func node_rank(class_id: String, node_id: String) -> int:
	return int(_entry(class_id).get("ranks", {}).get(node_id, 0))


func is_repeatable(class_id: String, node_id: String) -> bool:
	return bool(MetaTrees.node_data(class_id, node_id).get("repeatable", false))


# ── progression ───────────────────────────────────────────────────────────────
# Add meta XP to a class's persistent meta level. Callers convert run progress
# to meta XP BEFORE calling (see GameManager: per character level-up, not per
# raw run XP — run XP grows exponentially with character level while meta level
# costs grow linearly, so mirroring raw XP exploded into thousands of meta
# levels on a deep run). Local & per-class; mid-level XP stays in memory until
# a level-up (persisted immediately) or run_completed (flushed via _save).
func award_xp(class_id: String, amount: int) -> void:
	if amount <= 0 or class_id == "":
		return
	var e: Dictionary = _entry(class_id)
	var xp: int = int(e.get("meta_xp", 0)) + amount
	var lvl: int = int(e.get("meta_level", 1))
	var levelled: bool = false
	while xp >= XP_PER_LEVEL_BASE * lvl:
		xp -= XP_PER_LEVEL_BASE * lvl
		lvl += 1
		levelled = true
	e["meta_xp"] = xp
	e["meta_level"] = lvl
	if levelled:
		_save()


# ── allocation ────────────────────────────────────────────────────────────────
func can_allocate(class_id: String, node_id: String) -> bool:
	if not MetaTrees.has_node(class_id, node_id):
		return false
	var nd: Dictionary = MetaTrees.node_data(class_id, node_id)
	if String(nd.get("type", "")) == "start":
		return false  # start is implicitly taken & free
	if points_available(class_id) <= 0:
		return false
	if is_allocated(class_id, node_id):
		# Already taken — only repeatable nodes accept further ranks (no re-check of
		# connectivity, since an allocated node is trivially connected).
		return is_repeatable(class_id, node_id)
	return _is_connected(class_id, node_id)


# A node is reachable if any undirected neighbour is the start node or already allocated.
func _is_connected(class_id: String, node_id: String) -> bool:
	for nb in _neighbours(class_id, node_id):
		var nbd: Dictionary = MetaTrees.node_data(class_id, nb)
		if String(nbd.get("type", "")) == "start" or is_allocated(class_id, nb):
			return true
	return false


# Undirected adjacency: this node's own links plus any node that links back to it.
func _neighbours(class_id: String, node_id: String) -> Array:
	var out: Array = []
	var nd: Dictionary = MetaTrees.node_data(class_id, node_id)
	var links: Array = nd.get("links", [])
	for l in links:
		var lid: String = String(l)
		if not out.has(lid):
			out.append(lid)
	var tree: Dictionary = MetaTrees.tree_for(class_id)
	for other in tree:
		var oid: String = String(other)
		if oid == node_id or out.has(oid):
			continue
		var od: Dictionary = tree[other]
		var olinks: Array = od.get("links", [])
		if olinks.has(node_id):
			out.append(oid)
	return out


func allocate(class_id: String, node_id: String) -> bool:
	if not can_allocate(class_id, node_id):
		return false
	var e: Dictionary = _entry(class_id)
	if is_allocated(class_id, node_id):
		# Repeatable rank-up (can_allocate guaranteed it's repeatable).
		var ranks: Dictionary = e["ranks"]
		ranks[node_id] = int(ranks.get(node_id, 1)) + 1
		_save()
		return true
	var alloc: Array = e["allocated"]
	alloc.append(node_id)
	if is_repeatable(class_id, node_id):
		e["ranks"][node_id] = 1  # first rank
	# Reserve an (empty) gem slot the first time a socket node is taken.
	if String(MetaTrees.node_data(class_id, node_id).get("type", "")) == "socket":
		var sockets: Dictionary = e["sockets"]
		if not sockets.has(node_id):
			sockets[node_id] = null
	_save()
	return true


# Free full respec — wipe all allocated nodes (and the socket slots they opened). Points
# return to the pool automatically (points_available is derived, not stored); socketed
# gems are NOT lost — they pop back into the global inventory.
func respec(class_id: String) -> void:
	var e: Dictionary = _entry(class_id)
	var sockets: Dictionary = e.get("sockets", {})
	var returned: bool = false
	for sid in sockets:
		var gid: Variant = sockets[sid]
		if gid != null and String(gid) != "":
			_gem_add_raw(String(gid), 1)
			returned = true
	e["allocated"] = []
	e["sockets"] = {}
	e["ranks"] = {}
	_save()
	if returned:
		gems_changed.emit()


# ── mirror shards (global meta currency) ──────────────────────────────────────
func get_shards() -> int:
	return int(_data.get("shards", 0))


func add_shards(amount: int) -> void:
	if amount <= 0:
		return
	_data["shards"] = get_shards() + amount
	_save()
	shards_changed.emit(get_shards())


func spend_shards(amount: int) -> bool:
	if amount <= 0 or get_shards() < amount:
		return false
	_data["shards"] = get_shards() - amount
	_save()
	shards_changed.emit(get_shards())
	return true


# ── gem inventory (global, unsocketed gems) ───────────────────────────────────
func gem_counts() -> Dictionary:
	var gems: Dictionary = _data.get("gems", {})
	return gems


func gem_count(gem_id: String) -> int:
	return int(gem_counts().get(gem_id, 0))


func add_gem(gem_id: String, n: int = 1) -> void:
	if n <= 0 or not MetaGems.has_gem(gem_id):
		return
	_gem_add_raw(gem_id, n)
	_save()
	gems_changed.emit()


# Inventory mutation without save/signal — callers batch those.
func _gem_add_raw(gem_id: String, n: int) -> void:
	var gems: Dictionary = _data["gems"]
	var next: int = int(gems.get(gem_id, 0)) + n
	if next <= 0:
		gems.erase(gem_id)
	else:
		gems[gem_id] = next


# ── socketing ─────────────────────────────────────────────────────────────────
# The gem id sitting in a socket node ("" while empty / socket not opened).
func socketed_gem(class_id: String, socket_id: String) -> String:
	var gid: Variant = _entry(class_id).get("sockets", {}).get(socket_id, null)
	return String(gid) if gid != null else ""


# Place an owned gem into an ALLOCATED socket node. An occupied socket swaps — the old
# gem returns to the inventory. Returns whether the gem went in.
func socket_gem(class_id: String, socket_id: String, gem_id: String) -> bool:
	if gem_count(gem_id) <= 0:
		return false
	if String(MetaTrees.node_data(class_id, socket_id).get("type", "")) != "socket":
		return false
	if not is_allocated(class_id, socket_id):
		return false
	var old: String = socketed_gem(class_id, socket_id)
	if old == gem_id:
		return false  # already holds this gem — nothing to do
	if old != "":
		_gem_add_raw(old, 1)
	_gem_add_raw(gem_id, -1)
	_entry(class_id)["sockets"][socket_id] = gem_id
	_save()
	gems_changed.emit()
	return true


# Pop a socket's gem back into the inventory. Returns whether anything was removed.
func unsocket_gem(class_id: String, socket_id: String) -> bool:
	var old: String = socketed_gem(class_id, socket_id)
	if old == "":
		return false
	_gem_add_raw(old, 1)
	_entry(class_id)["sockets"][socket_id] = null
	_save()
	gems_changed.emit()
	return true


# ── bonus application ─────────────────────────────────────────────────────────
# Sum of every allocated node's flat stat bonuses PLUS the flat lines of socketed gems,
# keyed for GameManager._apply_stat_dict. GameManager folds this on top of the base stat
# line at the start of each run. Empty {} when the class has no tree or nothing allocated
# (a no-op through _apply_stat_dict).
func meta_bonus(class_id: String) -> Dictionary:
	var total: Dictionary = {}
	for node_id in allocated_nodes(class_id):
		var stats: Dictionary = MetaTrees.node_data(class_id, String(node_id)).get("stats", {})
		for k in stats:
			total[k] = total.get(k, 0) + stats[k]
	for gem_id in _socketed_gems(class_id):
		var gstats: Dictionary = MetaGems.get_gem(gem_id).stats
		for k in gstats:
			total[k] = total.get(k, 0) + gstats[k]
	return total


# Per-rank PERCENT bonuses from repeatable nodes (summed × their rank) plus socketed
# gems' percent lines (fractions: 0.001 = +0.1%). Keys match the player stats GameManager
# scales by these at run start (damage, max_hp, move_speed). Separate channel from
# meta_bonus because these multiply rather than add.
func meta_percent(class_id: String) -> Dictionary:
	var total: Dictionary = {}
	var ranks: Dictionary = _entry(class_id).get("ranks", {})
	for id in ranks:
		var rp: Dictionary = MetaTrees.node_data(class_id, String(id)).get("rank_pct", {})
		var n: int = int(ranks[id])
		for k in rp:
			total[k] = float(total.get(k, 0.0)) + float(rp[k]) * float(n)
	for gem_id in _socketed_gems(class_id):
		var gp: Dictionary = MetaGems.get_gem(gem_id).pct
		for k in gp:
			total[k] = float(total.get(k, 0.0)) + float(gp[k])
	return total


# Run-start economy perks from the fortune arm (summed "grants" of allocated nodes):
# {"gold": int, "materials": {id: n}, "start_gems": int, "socket_chance": float}.
# Consumed by GameManager.reset_run (gold/materials), InventorySystem (start gems)
# and LootRoller (socketed-loot chance).
func run_grants(class_id: String) -> Dictionary:
	var out: Dictionary = {"gold": 0, "materials": {}, "start_gems": 0, "socket_chance": 0.0}
	if class_id == "":
		return out
	for node_id in allocated_nodes(class_id):
		var grants: Dictionary = MetaTrees.node_data(class_id, String(node_id)).get("grants", {})
		out["gold"] = int(out["gold"]) + int(grants.get("gold", 0))
		out["start_gems"] = int(out["start_gems"]) + int(grants.get("start_gems", 0))
		out["socket_chance"] = float(out["socket_chance"]) + float(grants.get("socket_chance", 0.0))
		var mats: Dictionary = grants.get("materials", {})
		for k in mats:
			var m: Dictionary = out["materials"]
			m[k] = int(m.get(k, 0)) + int(mats[k])
	return out


# Gem ids sitting in this class's ALLOCATED sockets (a socket only exists once its node
# is taken, but stay defensive against stale saves).
func _socketed_gems(class_id: String) -> Array:
	var out: Array = []
	var sockets: Dictionary = _entry(class_id).get("sockets", {})
	for sid in sockets:
		var gid: Variant = sockets[sid]
		if gid != null and String(gid) != "" and is_allocated(class_id, String(sid)):
			out.append(String(gid))
	return out


# Compact snapshot for UI / dev readout.
func summary(class_id: String) -> Dictionary:
	return {
		"meta_level": get_meta_level(class_id),
		"meta_xp": get_meta_xp(class_id),
		"xp_to_next": xp_to_next(class_id),
		"points_total": points_total(class_id),
		"points_available": points_available(class_id),
		"allocated": allocated_nodes(class_id).duplicate(),
	}
