extends GutTest

# RunState traversal logic + GameManager's run-flow wrapper (start_run / run_travel_to and
# the run_started / run_node_entered / run_completed signals).

var _state0
var _diff0: int


func before_each() -> void:
	_state0 = GameManager.run_state
	_diff0 = GameManager.run_difficulty


func after_each() -> void:
	GameManager.run_state = _state0
	GameManager.run_difficulty = _diff0


# ── RunState ──────────────────────────────────────────────────────────────────
func test_inactive_without_a_map() -> void:
	var s := RunState.new()
	assert_false(s.is_active())
	assert_eq(s.reachable(), [])
	assert_false(s.travel(0), "can't travel with no map")


func test_starts_at_entry_gate() -> void:
	var m = RunMap.generate(11, 0, 8)
	var s := RunState.new(m)
	assert_true(s.is_active())
	assert_eq(s.current_id, -1, "begins at the entry gate")
	assert_eq(s.reachable(), m.start_ids(), "entry row is reachable first")
	assert_eq(s.visited_count(), 0)


func test_legal_travel_advances_and_records() -> void:
	var m = RunMap.generate(22, 1, 8)
	var s := RunState.new(m)
	var first: int = m.start_ids()[0]
	assert_true(s.travel(first))
	assert_eq(s.current_id, first)
	assert_true(s.visited.has(first))
	# Next reachable = that node's outgoing edges.
	assert_eq(s.reachable(), m.node_by_id(first).next)


func test_illegal_travel_is_rejected() -> void:
	var m = RunMap.generate(33, 1, 8)
	var s := RunState.new(m)
	# The boss is never reachable from the entry gate.
	assert_false(s.can_travel(m.boss_id()))
	assert_false(s.travel(m.boss_id()), "jumping straight to the boss is illegal")
	assert_eq(s.current_id, -1, "rejected travel leaves state unchanged")


func test_greedy_path_reaches_the_boss() -> void:
	var m = RunMap.generate(44, 2, 8)
	var s := RunState.new(m)
	var guard: int = 0
	while not s.is_at_boss() and guard < 50:
		var opts := s.reachable()
		assert_gt(opts.size(), 0, "always a way forward until the boss")
		assert_true(s.travel(int(opts[0])))
		guard += 1
	assert_true(s.is_at_boss(), "greedy traversal funnels into the boss")
	assert_true(s.is_complete())
	assert_eq(s.current_node().type, RunMap.TYPE_BOSS)


# ── GameManager wrapper ───────────────────────────────────────────────────────
func test_start_run_generates_a_map() -> void:
	watch_signals(GameManager)
	GameManager.start_run(2, 9001)
	assert_signal_emitted(GameManager, "run_started")
	assert_not_null(GameManager.run_state)
	assert_true(GameManager.run_state.is_active())
	assert_eq(GameManager.run_difficulty, 2)
	assert_eq(GameManager.run_seed, 9001)


func test_start_run_is_deterministic_by_seed() -> void:
	GameManager.start_run(2, 9001)
	var a := GameManager.run_state.map.start_ids()
	GameManager.start_run(2, 9001)
	var b := GameManager.run_state.map.start_ids()
	assert_eq(a, b, "same seed → same map")


func test_travel_emits_node_entered() -> void:
	GameManager.start_run(1, 9001)
	watch_signals(GameManager)
	var first: int = GameManager.run_state.map.start_ids()[0]
	assert_true(GameManager.run_travel_to(first))
	assert_signal_emitted(GameManager, "run_node_entered")
	assert_eq(GameManager.run_state.current_id, first)


func test_run_completed_fires_at_boss() -> void:
	GameManager.start_run(0, 7);
	watch_signals(GameManager)
	var s = GameManager.run_state
	var guard: int = 0
	while not s.is_at_boss() and guard < 50:
		GameManager.run_travel_to(int(s.reachable()[0]))
		guard += 1
	assert_signal_emitted(GameManager, "run_completed")
	assert_true(s.is_complete())
