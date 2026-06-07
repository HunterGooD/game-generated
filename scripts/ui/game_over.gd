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
	if btn_menu:
		btn_menu.pressed.connect(_on_menu)
		btn_menu.text = "Return to Lobby"
	if btn_retry:
		btn_retry.pressed.connect(_on_retry)
		if NetManager and NetManager.is_multiplayer:
			btn_retry.text = "Back to Lobby"
		else:
			btn_retry.text = "Retry"

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
	var class_display: String = String(data.get("display", "Hero"))
	var rows: Array = [
		["Class", class_display],
		["Level", str(GameManager.player_level)],
		["Wave Reached", str(max(GameManager.highest_wave, 1))],
		["Enemies Slain", str(GameManager.enemies_killed)],
		["Gold Earned", str(GameManager.total_gold_earned)],
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


func _on_menu() -> void:
	# Return to the lobby (the new entry point for both solo and multiplayer)
	# instead of dropping all the way back to the main menu.
	get_tree().paused = false
	if GameManager:
		GameManager.player_class = ""
		GameManager.game_over = false
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_ui_menu_click.mp3", -8.0)
	# In multiplayer, keep the room alive so the party can re-ready together.
	# In solo, simply re-enter the lobby (which auto-enters in-room solo mode).
	var dest_path: String = "res://scenes/ui/multiplayer_lobby.tscn"
	if NetManager and NetManager.is_multiplayer:
		# Keep the connection. The lobby reconstructs the in-room view because
		# NetManager.is_multiplayer is still true.
		pass
	var ls = get_tree().root.get_node_or_null("LoadingScreen")
	if ls and ls.has_method("preload_and_change_scene"):
		ls.call("preload_and_change_scene", dest_path)
	elif ls and ls.has_method("change_scene"):
		ls.call("change_scene", dest_path)
	else:
		get_tree().change_scene_to_file(dest_path)


func _on_retry() -> void:
	get_tree().paused = false
	if GameManager:
		GameManager.game_over = false
		# Preserve class, reset stats.
		GameManager.reset_run()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_ui_menu_click.mp3", -8.0)
	# In multiplayer, retry isn't a sane local action — bounce to the lobby
	# so the host can press START GAME again for everyone.
	if NetManager and NetManager.is_multiplayer:
		_on_menu()
		return
	var ls = get_tree().root.get_node_or_null("LoadingScreen")
	if ls and ls.has_method("change_scene"):
		ls.call("change_scene", "res://scenes/world/game_world.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/world/game_world.tscn")
