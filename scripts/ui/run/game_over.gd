extends CanvasLayer

# Game Over overlay — appears when the player dies. Pauses the game.

@export var title_label: Label
@export var stat_grid: GridContainer
@export var btn_menu: Button
@export var btn_retry: Button


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_populate()
	# Button 1 → the hub (hero select / next run). Button 2 → the main menu
	# (co-op: leave the lobby back to the menu).
	if btn_menu:
		btn_menu.pressed.connect(_on_hub)
		btn_menu.text = "Вернуться в хаб"
	if btn_retry:
		btn_retry.pressed.connect(_on_main_menu)
		btn_retry.text = "Главное меню"

	# Tween title pulse.
	if title_label:
		var tw := title_label.create_tween().set_loops()
		tw.tween_property(title_label, "modulate", Color(1.3, 0.4, 0.4, 1), 0.9).set_trans(
			Tween.TRANS_SINE
		)
		tw.tween_property(title_label, "modulate", Color(0.9, 0.2, 0.2, 1), 0.9).set_trans(
			Tween.TRANS_SINE
		)

	# Lower music.
	if AudioManager:
		AudioManager.stop_music()
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/enemy/enemy_enemy_death_cultist.mp3", -4.0
		)


func _populate() -> void:
	if stat_grid == null or GameManager == null:
		return
	for c in stat_grid.get_children():
		c.queue_free()
	var data: Dictionary = GameManager.get_class_data()
	var class_display: String = String(data.get("display", "Герой"))
	var rows: Array = [
		["Класс", class_display],
		["Уровень", str(GameManager.player_level)],
		["Лучшая волна", str(max(GameManager.highest_wave, 1))],
		["Врагов убито", str(GameManager.enemies_killed)],
		["Золота добыто", str(GameManager.total_gold_earned)],
	]
	for row in rows:
		var l := Label.new()
		l.text = String(row[0])
		l.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62, 1))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		l.add_theme_constant_override("outline_size", 3)
		l.add_theme_font_size_override("font_size", 22)
		stat_grid.add_child(l)
		var v := Label.new()
		v.text = String(row[1])
		v.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45, 1))
		v.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		v.add_theme_constant_override("outline_size", 3)
		v.add_theme_font_size_override("font_size", 22)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat_grid.add_child(v)


# Button 1: end the run and return to the walkable hub (hero select / next run).
# Co-op "all players confirm → hub together" is a relay TODO; for now the local player goes.
func _on_hub() -> void:
	get_tree().paused = false
	if GameManager:
		GameManager.game_over = false
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_ui_menu_click.mp3", -8.0)
	if RunFlow:
		RunFlow.exit_to_hub()
	else:
		_change_scene("res://scenes/world/hub.tscn")


# Button 2: leave to the main menu. In co-op, disconnect from the lobby first.
func _on_main_menu() -> void:
	get_tree().paused = false
	if GameManager:
		GameManager.game_over = false
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_ui_menu_click.mp3", -8.0)
	if NetManager and NetManager.is_multiplayer:
		NetManager.disconnect_from_room()
	_change_scene("res://scenes/main.tscn")


func _change_scene(path: String) -> void:
	var ls = get_tree().root.get_node_or_null("LoadingScreen")
	if ls and ls.has_method("preload_and_change_scene"):
		ls.call("preload_and_change_scene", path)
	elif ls and ls.has_method("change_scene"):
		ls.call("change_scene", path)
	else:
		get_tree().change_scene_to_file(path)
