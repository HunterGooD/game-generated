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


func test_trade_panel_instantiates_and_wires() -> void:
	var scene: PackedScene = load("res://scenes/ui/trade_panel.tscn")
	assert_not_null(scene, "trade_panel.tscn loads as PackedScene")
	var tp: Node = scene.instantiate()
	add_child_autofree(tp)  # _ready runs: connects buttons, refreshes grid.
	assert_not_null(tp.get("item_grid"), "item_grid @export resolved")
	assert_not_null(tp.get("recipient_label"), "recipient_label @export resolved")
	assert_not_null(tp.get("selected_label"), "selected_label @export resolved")
	assert_not_null(tp.get("send_btn"), "send_btn @export resolved")
	assert_not_null(tp.get("cycle_btn"), "cycle_btn @export resolved")
	assert_not_null(tp.get("close_btn"), "close_btn @export resolved")


func test_hud_instantiates_and_wires() -> void:
	# hud.tscn was already an authored template; this guards its @export wiring
	# (hp/mp/gold/level/class labels, hotbar, xp, wave, character_sheet) and that
	# the heavy _ready (globes/hotbar/bands/signal hookup) runs without error.
	var scene: PackedScene = load("res://scenes/ui/hud.tscn")
	assert_not_null(scene, "hud.tscn loads as PackedScene")
	var h: Node = scene.instantiate()
	add_child_autofree(h)
	assert_not_null(h.get("hotbar"), "hotbar @export resolved")
	assert_not_null(h.get("hp_bar"), "hp_bar @export resolved")
	assert_not_null(h.get("xp_fill"), "xp_fill @export resolved")
	assert_not_null(h.get("character_sheet"), "character_sheet @export resolved")


func test_character_sheet_instantiates_and_wires() -> void:
	var scene: PackedScene = load("res://scenes/ui/character_sheet.tscn")
	assert_not_null(scene, "character_sheet.tscn loads as PackedScene")
	var cs: Node = scene.instantiate()
	add_child_autofree(cs)  # _ready connects salvage btn + inventory signals.
	assert_not_null(cs.get("inventory_grid"), "inventory_grid @export resolved")
	assert_not_null(cs.get("paper_doll"), "paper_doll @export resolved")
	assert_not_null(cs.get("stats_box"), "stats_box @export resolved")
	assert_not_null(cs.get("portrait"), "portrait @export resolved")
	assert_not_null(cs.get("salvage_all_btn"), "salvage_all_btn @export resolved")
	assert_not_null(cs.get("set_summary_label"), "set_summary_label @export resolved")
