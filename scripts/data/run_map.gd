class_name RunMap
extends RefCounted

## Slay-the-Spire style run map: a layered DAG the party traverses one node at a time
## from an entry row up to the uber-boss at the top. Generation is DETERMINISTIC by
## seed + difficulty, so in co-op the host only has to broadcast (seed, difficulty) and
## every peer rebuilds the identical map (no need to replicate the whole structure).
##
## A node: { id:int, row:int, col:int, type:String, affixes:Array[String], next:Array[int] }
##   - `row` 0 is the entry row; the final row is a single boss node.
##   - `next` holds the ids of reachable nodes in row+1 (edges only go up one row).
## The generator guarantees: every node has at least one outgoing edge (except the boss),
## every non-entry node has at least one incoming edge, and the boss is reachable from
## every entry node — i.e. one fully-connected DAG funnelling into the boss.

# Node types.
const TYPE_DUNGEON := "dungeon"
const TYPE_ARENA := "arena"
const TYPE_MERCHANT := "merchant"
const TYPE_CAMPFIRE := "campfire"
const TYPE_ELITE := "elite"
const TYPE_BOSS := "boss"

# Optional per-node modifiers (the "node affixes" — extra reward/risk on that node).
const NODE_AFFIXES := ["bonus_xp", "extra_chest", "elite_pack", "treasure_vault"]

# Node types that resolve as a bounded wave fight (the rest auto-resolve on the map for
# now: merchant/campfire). Dungeon temporarily reuses the wave fight until the Rust
# generator lands (Phase 1); boss reuses it as a placeholder until a real boss encounter.
const COMBAT_TYPES := [TYPE_ARENA, TYPE_ELITE, TYPE_DUNGEON, TYPE_BOSS]


static func is_combat_type(t: String) -> bool:
	return t in COMBAT_TYPES


# Wave plan for a combat node: how many waves to clear + an elite-chance override
# (-1.0 = use the difficulty default). Node affixes nudge it (elite_pack → more elites).
static func combat_plan(node: Dictionary) -> Dictionary:
	var plan: Dictionary = {"waves": 0, "elite_chance": -1.0}
	match String(node.get("type", "")):
		TYPE_ARENA:
			plan = {"waves": 10, "elite_chance": -1.0}  # arena cycle = 10 waves → finale boss
		TYPE_ELITE:
			plan = {"waves": 3, "elite_chance": 0.6}
		TYPE_DUNGEON:
			plan = {"waves": 5, "elite_chance": -1.0}
		TYPE_BOSS:
			plan = {"waves": 3, "elite_chance": 0.4}
	if "elite_pack" in (node.get("affixes", []) as Array):
		plan["elite_chance"] = maxf(float(plan["elite_chance"]), 0.5)
	return plan


# ── data container ────────────────────────────────────────────────────────────
class RunMapData:
	extends RefCounted
	var seed_value: int = 0
	var difficulty: int = 0
	var rows: Array = []  # Array[Array[Dictionary]] — rows[r] is the list of nodes in row r

	func all_nodes() -> Array:
		var out: Array = []
		for row in rows:
			for n in row:
				out.append(n)
		return out

	func node_by_id(id: int) -> Dictionary:
		for row in rows:
			for n in row:
				if int(n["id"]) == id:
					return n
		return {}

	func start_ids() -> Array:
		var out: Array = []
		if not rows.is_empty():
			for n in rows[0]:
				out.append(int(n["id"]))
		return out

	func boss_id() -> int:
		if rows.is_empty() or rows[-1].is_empty():
			return -1
		return int(rows[-1][0]["id"])

	func row_count() -> int:
		return rows.size()


# ── generation ────────────────────────────────────────────────────────────────
# `rows` = total depth incl. the boss row. Returns a fully-connected RunMapData.
static func generate(seed_value: int, difficulty: int, rows: int = 8) -> RunMapData:
	rows = maxi(rows, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var data := RunMapData.new()
	data.seed_value = seed_value
	data.difficulty = Difficulty.clamp_tier(difficulty)

	var next_id: int = 0
	# Build each row's nodes (ids, type, affixes) — edges come after.
	for r in rows:
		var is_entry: bool = r == 0
		var is_boss: bool = r == rows - 1
		var is_preboss: bool = r == rows - 2
		var count: int = _row_count(rng, r, rows)
		var row_nodes: Array = []
		for c in count:
			var node: Dictionary = {
				"id": next_id,
				"row": r,
				"col": c,
				"type": _pick_type(rng, r, rows, data.difficulty, is_entry, is_boss, is_preboss),
				"affixes": [],
				"next": [],
			}
			# Boss + entry rows stay clean; interior nodes can carry a modifier.
			if not is_boss and not is_entry:
				node["affixes"] = _roll_node_affixes(rng, data.difficulty)
			row_nodes.append(node)
			next_id += 1
		data.rows.append(row_nodes)

	# Wire edges row → row+1.
	for r in rows - 1:
		_connect_rows(data.rows[r], data.rows[r + 1], rng)

	return data


static func _row_count(rng: RandomNumberGenerator, r: int, rows: int) -> int:
	if r == rows - 1:
		return 1  # single boss
	if r == 0:
		return 4 + (rng.randi() % 2)  # 2-3 entry points
	if r == rows - 2:
		return 2 + (rng.randi() % 2)  # 1-2 pre-boss nodes (funnel)
	return 3 + (rng.randi() % 3)  # 2-4 interior nodes


static func _pick_type(
	rng: RandomNumberGenerator,
	r: int,
	rows: int,
	difficulty: int,
	is_entry: bool,
	is_boss: bool,
	is_preboss: bool
) -> String:
	if is_boss:
		return TYPE_BOSS
	if is_preboss:
		# Rest/resupply before the boss.
		return TYPE_CAMPFIRE if rng.randf() < 0.6 else TYPE_MERCHANT
	# Weighted pool. Elites grow more common deeper and on higher difficulty; the
	# entry row is kept safe (no elites).
	var depth_frac: float = float(r) / float(maxi(rows - 1, 1))
	var elite_w: float = 0.0 if is_entry else (4.0 + 10.0 * depth_frac + 3.0 * float(difficulty))
	var weights := {
		TYPE_DUNGEON: 42.0,
		TYPE_ARENA: 22.0,
		TYPE_ELITE: elite_w,
		TYPE_MERCHANT: 8.0,
		TYPE_CAMPFIRE: 8.0,
	}
	return _weighted_pick(rng, weights)


static func _roll_node_affixes(rng: RandomNumberGenerator, difficulty: int) -> Array:
	# Most nodes are plain; chance of a single modifier rises with difficulty.
	var chance: float = 0.18 + 0.06 * float(difficulty)
	if rng.randf() >= chance:
		return []
	return [NODE_AFFIXES[rng.randi() % NODE_AFFIXES.size()]]


# Connect every node in `cur` upward, guaranteeing each `nxt` node gets an incoming edge.
static func _connect_rows(cur: Array, nxt: Array, rng: RandomNumberGenerator) -> void:
	var nc: int = nxt.size()
	for i in cur.size():
		var node: Dictionary = cur[i]
		var center: int = 0
		if cur.size() > 1:
			center = int(round(float(i) / float(cur.size() - 1) * float(nc - 1)))
		center = clampi(center, 0, nc - 1)
		var targets := {center: true}
		# Sometimes branch to an adjacent column (a real choice on the map).
		if nc > 1 and rng.randf() < 0.5:
			var off: int = -1 if rng.randf() < 0.5 else 1
			targets[clampi(center + off, 0, nc - 1)] = true
		for t in targets.keys():
			var tid: int = int(nxt[t]["id"])
			if not node["next"].has(tid):
				node["next"].append(tid)
	# Repair: any next-row node with no incoming edge gets one from its nearest source.
	for j in nc:
		var jid: int = int(nxt[j]["id"])
		var has_in: bool = false
		for node in cur:
			if node["next"].has(jid):
				has_in = true
				break
		if not has_in:
			var src: int = 0
			if cur.size() > 1:
				src = int(round(float(j) / float(maxi(nc - 1, 1)) * float(cur.size() - 1)))
			src = clampi(src, 0, cur.size() - 1)
			cur[src]["next"].append(jid)


static func _weighted_pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total: float = 0.0
	for k in weights:
		total += maxf(0.0, float(weights[k]))
	if total <= 0.0:
		return TYPE_DUNGEON
	var roll: float = rng.randf() * total
	for k in weights:
		var w: float = maxf(0.0, float(weights[k]))
		if roll < w:
			return String(k)
		roll -= w
	return TYPE_DUNGEON
