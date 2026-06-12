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

var dim: ColorRect = null
var panel: PanelContainer = null
var title_label: Label = null
var status_label: Label = null
var continue_btn: Button = null
var exit_btn: Button = null

var is_coop: bool = false
var closing: bool = false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS

	is_coop = NetManager != null and NetManager.is_multiplayer

	_build_ui()

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


func _build_ui() -> void:
	# Dim background.
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Centered panel.
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	title_label = Label.new()
	title_label.text = "ПАУЗА"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45, 1))
	title_label.add_theme_color_override("font_outline_color", Color(0.1, 0.02, 0.0, 1))
	title_label.add_theme_constant_override("outline_size", 5)
	vbox.add_child(title_label)

	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7, 1))
	status_label.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.0, 1))
	status_label.add_theme_constant_override("outline_size", 3)
	status_label.visible = false
	vbox.add_child(status_label)

	continue_btn = Button.new()
	continue_btn.text = "Продолжить"
	continue_btn.custom_minimum_size = Vector2(0, 48)
	continue_btn.add_theme_font_size_override("font_size", 20)
	continue_btn.pressed.connect(_on_continue)
	vbox.add_child(continue_btn)

	exit_btn = Button.new()
	exit_btn.text = "Вернуться в лобби" if is_coop else "Выйти в главное меню"
	exit_btn.custom_minimum_size = Vector2(0, 48)
	exit_btn.add_theme_font_size_override("font_size", 20)
	exit_btn.pressed.connect(_on_exit)
	vbox.add_child(exit_btn)


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
