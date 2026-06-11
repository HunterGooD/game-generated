extends GutTest

# RunFlow + the run-node combat plan. Covers which node types resolve as a bounded wave
# fight vs auto-resolve on the map, the wave/elite plan per type (and node-affix nudges),
# and GameManager's run-node context (begin/clear + run_node_cleared signal).

var _node0: Dictionary


func before_each() -> void:
	_node0 = GameManager.run_node_active


func after_each() -> void:
	GameManager.run_node_active = _node0


func _node(type: String, affixes: Array = []) -> Dictionary:
	return {"id": 0, "row": 1, "col": 0, "type": type, "affixes": affixes, "next": []}


# ── combat classification ─────────────────────────────────────────────────────
func test_combat_types() -> void:
	for t in [RunMap.TYPE_ARENA, RunMap.TYPE_ELITE, RunMap.TYPE_DUNGEON, RunMap.TYPE_BOSS]:
		assert_true(RunMap.is_combat_type(t), "%s is a combat node" % t)
	for t in [RunMap.TYPE_MERCHANT, RunMap.TYPE_CAMPFIRE]:
		assert_false(RunMap.is_combat_type(t), "%s auto-resolves on the map" % t)


func test_combat_plan_per_type() -> void:
	assert_eq(int(RunMap.combat_plan(_node(RunMap.TYPE_ARENA))["waves"]), 5)
	assert_eq(int(RunMap.combat_plan(_node(RunMap.TYPE_DUNGEON))["waves"]), 5)
	var elite := RunMap.combat_plan(_node(RunMap.TYPE_ELITE))
	assert_eq(int(elite["waves"]), 3)
	assert_gt(float(elite["elite_chance"]), 0.0, "elite node forces a higher elite chance")
	# Non-combat nodes get a zero-wave plan.
	assert_eq(int(RunMap.combat_plan(_node(RunMap.TYPE_MERCHANT))["waves"]), 0)


func test_elite_pack_affix_raises_elite_chance() -> void:
	var plain := RunMap.combat_plan(_node(RunMap.TYPE_ARENA))
	var packed := RunMap.combat_plan(_node(RunMap.TYPE_ARENA, ["elite_pack"]))
	assert_eq(float(plain["elite_chance"]), -1.0, "plain arena uses the difficulty default")
	assert_gte(float(packed["elite_chance"]), 0.5, "elite_pack affix forces elites")


# ── RunFlow routing ───────────────────────────────────────────────────────────
func test_routing_targets() -> void:
	assert_eq(RunFlow.target_for_node(_node(RunMap.TYPE_ARENA)), RunFlow.SCENE_COMBAT)
	assert_eq(RunFlow.target_for_node(_node(RunMap.TYPE_BOSS)), RunFlow.SCENE_COMBAT)
	assert_eq(RunFlow.target_for_node(_node(RunMap.TYPE_DUNGEON)), RunFlow.SCENE_DUNGEON, "dungeon → its own runner scene")
	assert_eq(RunFlow.target_for_node(_node(RunMap.TYPE_MERCHANT)), RunFlow.SCENE_NODE_ROOM)
	assert_eq(RunFlow.target_for_node(_node(RunMap.TYPE_CAMPFIRE)), RunFlow.SCENE_NODE_ROOM)


# ── GameManager run-node context ──────────────────────────────────────────────
func test_begin_and_clear_node_emits_signal() -> void:
	var n := _node(RunMap.TYPE_ARENA)
	GameManager.begin_run_node(n)
	assert_eq(GameManager.run_node_active, n, "node marked active during play")
	watch_signals(GameManager)
	GameManager.clear_run_node()
	assert_signal_emitted(GameManager, "run_node_cleared")
	assert_eq(GameManager.run_node_active, {}, "node cleared after completion")


# Regression: RunFlow must NOT hijack the scene from stray GameManager run signals (it
# only drives scene changes while it owns an active flow via start_run/open_map). If this
# guard breaks, unit tests that exercise run_travel_to will swap the scene mid-run.
func test_runflow_inert_without_active_flow() -> void:
	assert_false(RunFlow._flow_active, "RunFlow is inert until it starts a flow")
	GameManager.clear_run_node()  # emits run_node_cleared
	assert_false(RunFlow._flow_active, "a stray signal does not activate RunFlow")
