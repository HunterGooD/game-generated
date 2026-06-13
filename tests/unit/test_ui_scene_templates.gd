extends GutTest

# Guards the Трек E "author UI panels as scene templates" work: each refactored
# panel must instantiate, run _ready without error, and resolve its @export
# node_paths to real child nodes (a wrong path nulls the ref and crashes on the
# first use — e.g. `continue_btn.pressed.connect`). Smoke only LOADS scenes, so
# this is the headless net for the @export wiring; visual parity still needs /run.


func test_pause_menu_instantiates_and_wires() -> void:
	var scene: PackedScene = load("res://scenes/ui/pause_menu.tscn")
	assert_not_null(scene, "pause_menu.tscn loads as PackedScene")
	var pm: Node = scene.instantiate()
	add_child_autofree(pm)  # _ready runs here; solo path sets the tree paused.
	# Solo _ready pauses the tree — undo so GUT keeps ticking.
	get_tree().paused = false
	assert_not_null(pm.get("continue_btn"), "continue_btn @export resolved")
	assert_not_null(pm.get("exit_btn"), "exit_btn @export resolved")
	assert_not_null(pm.get("status_label"), "status_label @export resolved")
