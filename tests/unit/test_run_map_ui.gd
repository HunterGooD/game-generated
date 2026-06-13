extends GutTest

# RunMapUI build-path coverage — exercises the difficulty picker, the map view (node
# buttons + edge layer) and the travel refresh, guarding against runtime errors in the
# code-built screen. Visual layout isn't asserted, only that it constructs and reacts.

var _state0


func before_each() -> void:
	_state0 = GameManager.run_state
	GameManager.run_state = null


func after_each() -> void:
	GameManager.run_state = _state0
	# RunMapUI pauses the tree (solo) in _ready as an overlay; undo so GUT keeps ticking.
	get_tree().paused = false


func _descendants(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_descendants(c))
	return out


func _node_buttons(ui: Node) -> int:
	var count: int = 0
	for d in _descendants(ui):
		if d is Button and String(d.name).begins_with("node_"):
			count += 1
	return count


func test_shows_picker_when_no_run() -> void:
	var ui := RunMapUI.new()
	add_child_autofree(ui)
	assert_gt(ui.get_child_count(), 0, "picker screen built")
	assert_eq(_node_buttons(ui), 0, "no map nodes before a run starts")


func test_builds_map_after_start_run() -> void:
	var ui := RunMapUI.new()
	add_child_autofree(ui)
	GameManager.start_run(1, 4242)  # run_started → rebuild into the map view
	assert_gt(_node_buttons(ui), 0, "map view created node buttons for the DAG")


func test_travel_refreshes_without_error() -> void:
	var ui := RunMapUI.new()
	add_child_autofree(ui)
	GameManager.start_run(0, 4242)
	var first: int = GameManager.run_state.map.start_ids()[0]
	GameManager.run_travel_to(first)  # run_node_entered → _on_node_entered → _refresh
	assert_eq(GameManager.run_state.current_id, first, "travel applied and UI refreshed")
