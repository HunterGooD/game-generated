extends CanvasLayer

# Pause menu — opens on ESC during gameplay.
#
# Solo: pauses the tree, two buttons (Continue / Exit to Main Menu).
# Co-op: does NOT pause the tree by itself. Sends a pause_request to peers
# via NetSync; the tree only freezes when EVERY player has the pause menu
# open. Continue retracts the request; Exit leaves the room and returns to
# the main menu.

signal closed

const MAIN_MENU_PATH: String = "res://scenes/main.tscn"

# Wired from pause_menu.tscn (the static frame — dim / centred panel / title /
# status / buttons — lives in the scene now; the script keeps only logic).
@export var status_label: Label
@export var continue_btn: Button
@export var exit_btn: Button

var is_coop: bool = false
var closing: bool = false


func _ready() -> void:
	# layer (90) + process_mode (ALWAYS, so the menu still processes input while
	# the tree is paused) are set on the scene root.
	is_coop = NetManager != null and NetManager.is_multiplayer

	# Co-op relabels the exit button; the scene ships the solo label.
	if is_coop:
		exit_btn.text = "Вернуться в лобби"
	continue_btn.pressed.connect(_on_continue)
	exit_btn.pressed.connect(_on_exit)

	# Request pause. In solo this freezes the tree directly. In co-op this
	# broadcasts a pause_request and the tree only freezes when everyone is
	# in the menu.
	if is_coop:
		var ns := _find_net_sync()
		if ns and ns.has_method("request_pause"):
			ns.call("request_pause", true)
		_update_status_label()
	else:
		get_tree().paused = true


func _update_status_label() -> void:
	if status_label == null:
		return
	if not is_coop:
		status_label.visible = false
		return
	status_label.visible = true
	status_label.text = "Ждём, пока товарищ тоже поставит паузу…\nМир продолжает бой, пока не соберутся все."


func _unhandled_input(event: InputEvent) -> void:
	if closing:
		return
	if (
		event.is_action_pressed("pause")
		or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)
	):
		_on_continue()
		get_viewport().set_input_as_handled()


func _on_continue() -> void:
	if closing:
		return
	closing = true
	if is_coop:
		var ns := _find_net_sync()
		if ns and ns.has_method("request_pause"):
			ns.call("request_pause", false)
	else:
		get_tree().paused = false
	closed.emit()
	queue_free()


func _on_exit() -> void:
	if closing:
		return
	closing = true
	# Tell peers we're no longer pause-requesting (otherwise their tree could
	# stay locked) and disconnect cleanly.
	if is_coop:
		var ns := _find_net_sync()
		if ns and ns.has_method("request_pause"):
			ns.call("request_pause", false)
		if NetManager:
			NetManager.disconnect_from_room()
	# Always unpause before changing scenes — paused trees can swallow input.
	get_tree().paused = false
	closed.emit()
	# Reset run state so the next entry from the menu is clean.
	if GameManager:
		GameManager.game_over = false
	queue_free()
	_change_scene_to_main_menu()


func _change_scene_to_main_menu() -> void:
	# Prefer the LoadingScreen autoload if present (matches the rest of the
	# game's transitions); otherwise fall back to a direct scene change.
	var tree := get_tree()
	if tree == null:
		return
	if Engine.has_singleton("LoadingScreen"):
		var ls = Engine.get_singleton("LoadingScreen")
		if ls and ls.has_method("change_scene"):
			ls.call("change_scene", MAIN_MENU_PATH)
			return
	var ls_node: Node = tree.root.get_node_or_null("LoadingScreen")
	if ls_node and ls_node.has_method("change_scene"):
		ls_node.call("change_scene", MAIN_MENU_PATH)
		return
	tree.change_scene_to_file(MAIN_MENU_PATH)


func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("NetSync")
