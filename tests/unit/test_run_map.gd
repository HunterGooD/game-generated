extends GutTest

# RunMap — deterministic Slay-the-Spire DAG generation. Validates structure (entry row,
# single boss on top, edges only climb one row), full connectivity (every node reachable
# from an entry node and able to reach the boss), determinism by seed, and that difficulty
# pushes more elites onto the map.

const VALID_TYPES := [
	RunMap.TYPE_DUNGEON,
	RunMap.TYPE_ARENA,
	RunMap.TYPE_MERCHANT,
	RunMap.TYPE_CAMPFIRE,
	RunMap.TYPE_ELITE,
	RunMap.TYPE_BOSS,
	RunMap.TYPE_EVENT,
]


func _serialize(m) -> String:
	var parts: Array = []
	for n in m.all_nodes():
		parts.append("%d:%d:%d:%s:%s>%s" % [n.id, n.row, n.col, n.type, str(n.affixes), str(n.next)])
	return "|".join(parts)


# ── structure ─────────────────────────────────────────────────────────────────
func test_has_requested_depth_and_single_boss() -> void:
	var m = RunMap.generate(1, 0, 8)
	assert_eq(m.row_count(), 8, "map has the requested number of rows")
	assert_eq(m.rows[-1].size(), 1, "top row is a single node")
	assert_eq(m.rows[-1][0].type, RunMap.TYPE_BOSS, "top node is the boss")
	assert_eq(m.boss_id(), m.rows[-1][0].id)
	assert_gte(m.rows[0].size(), 2, "entry row offers more than one start")


func test_every_node_type_is_valid() -> void:
	var m = RunMap.generate(42, 2, 8)
	for n in m.all_nodes():
		assert_true(n.type in VALID_TYPES, "unknown node type: %s" % n.type)


func test_entry_row_is_safe_and_boss_only_on_top() -> void:
	var m = RunMap.generate(7, 3, 8)
	for n in m.rows[0]:
		assert_ne(n.type, RunMap.TYPE_ELITE, "entry row has no elites")
		assert_ne(n.type, RunMap.TYPE_BOSS, "entry row has no boss")
	for r in range(m.row_count() - 1):
		for n in m.rows[r]:
			assert_ne(n.type, RunMap.TYPE_BOSS, "boss only appears on the top row")


func test_edges_only_climb_one_row() -> void:
	var m = RunMap.generate(99, 1, 8)
	for n in m.all_nodes():
		for nid in n.next:
			var nb = m.node_by_id(nid)
			assert_false(nb.is_empty(), "edge points at a real node")
			assert_eq(int(nb.row), int(n.row) + 1, "edge goes exactly one row up")


# ── connectivity ──────────────────────────────────────────────────────────────
func _reachable_from_starts(m) -> Dictionary:
	var seen: Dictionary = {}
	var frontier: Array = m.start_ids()
	for id in frontier:
		seen[id] = true
	while not frontier.is_empty():
		var id: int = frontier.pop_back()
		for nid in m.node_by_id(id).next:
			if not seen.has(nid):
				seen[nid] = true
				frontier.append(nid)
	return seen


func test_every_node_reachable_from_an_entry() -> void:
	var m = RunMap.generate(123, 2, 8)
	var seen := _reachable_from_starts(m)
	for n in m.all_nodes():
		assert_true(seen.has(int(n.id)), "node %d unreachable from entry" % int(n.id))


func test_boss_reachable_and_nodes_have_forward_edges() -> void:
	var m = RunMap.generate(555, 1, 8)
	var seen := _reachable_from_starts(m)
	assert_true(seen.has(m.boss_id()), "boss reachable from entry")
	for n in m.all_nodes():
		if int(n.row) < m.row_count() - 1:
			assert_gt(n.next.size(), 0, "non-boss node %d has a way forward" % int(n.id))
		else:
			assert_eq(n.next.size(), 0, "boss has no outgoing edges")


func test_non_entry_nodes_have_incoming_edges() -> void:
	var m = RunMap.generate(2024, 3, 8)
	var has_incoming: Dictionary = {}
	for n in m.all_nodes():
		for nid in n.next:
			has_incoming[nid] = true
	for r in range(1, m.row_count()):
		for n in m.rows[r]:
			assert_true(has_incoming.has(int(n.id)), "node %d has no incoming edge" % int(n.id))


# ── determinism ───────────────────────────────────────────────────────────────
func test_same_seed_and_difficulty_is_identical() -> void:
	var a = RunMap.generate(31337, 2, 8)
	var b = RunMap.generate(31337, 2, 8)
	assert_eq(_serialize(a), _serialize(b), "identical seed+difficulty → identical map")


func test_different_seed_changes_the_map() -> void:
	var a = RunMap.generate(1, 2, 8)
	var b = RunMap.generate(2, 2, 8)
	assert_ne(_serialize(a), _serialize(b), "different seeds produce different maps")


# ── difficulty pushes elites ──────────────────────────────────────────────────
func _avg_elites(difficulty: int) -> float:
	var total: int = 0
	var samples: int = 40
	for s in samples:
		var m = RunMap.generate(s * 17 + 3, difficulty, 8)
		for n in m.all_nodes():
			if n.type == RunMap.TYPE_ELITE:
				total += 1
	return float(total) / float(samples)


func test_higher_difficulty_has_more_elites() -> void:
	assert_gt(_avg_elites(Difficulty.count() - 1), _avg_elites(0), "harder runs field more elites")
