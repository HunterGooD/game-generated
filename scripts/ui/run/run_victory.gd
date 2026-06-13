extends CanvasLayer

## Run-victory end screen, shown after the uber-boss (the final run-map node) falls. Built
## in code (no .tscn — same pattern as run_map_ui / spec_path_choice). Pauses in solo, shows
## the run's stats, and returns the party to the hub (ending the run) on confirm.

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Solo pauses for the moment; co-op keeps simulating (can't pause the other player).
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = true
	if VfxManager and VfxManager.has_method("screen_flash"):
		VfxManager.screen_flash(Color(1.0, 0.86, 0.35, 0.35), 0.6)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/enemy/enemy_boss_appear.mp3", -6.0)
	_build()


func _build() -> void:
	var dim := UIBuilder.dim_overlay(Color(0.03, 0.02, 0.06, 0.93))
	add_child(dim)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	dim.add_child(vb)

	var title := Label.new()
	title.text = "★  П О Б Е Д А  ★"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 6)
	vb.add_child(title)
	# Gentle pulse.
	var tw := title.create_tween().set_loops()
	tw.tween_property(title, "modulate", Color(1.3, 1.1, 0.6, 1), 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(title, "modulate", Color(0.95, 0.8, 0.4, 1), 1.0).set_trans(Tween.TRANS_SINE)

	var sub := Label.new()
	sub.text = "Убер-босс пал. Забег ваш."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82))
	vb.add_child(sub)

	var stats := Label.new()
	stats.text = _stats_text()
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 18)
	stats.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	vb.add_child(stats)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vb.add_child(row)

	# Continue: a fresh map at the next difficulty tier (capped at max), keeping
	# the whole build — level, talents, gear, materials. Co-op: host-only (the
	# run_start broadcast pulls every client onto the new map automatically).
	var next_tier: int = Difficulty.clamp_tier(
		(GameManager.run_difficulty if GameManager else 0) + 1
	)
	var next_loop: int = (GameManager.run_loop if GameManager else 0) + 1
	var btn_continue := Button.new()
	btn_continue.text = "Продолжить — виток %d (%s)" % [next_loop, Difficulty.name_of(next_tier)]
	btn_continue.custom_minimum_size = Vector2(300, 54)
	btn_continue.pressed.connect(_on_continue.bind(next_tier))
	row.add_child(btn_continue)

	var btn_hub := Button.new()
	btn_hub.text = "Вернуться в хаб"
	btn_hub.custom_minimum_size = Vector2(240, 54)
	btn_hub.pressed.connect(_on_hub)
	row.add_child(btn_hub)

	var btn_menu := Button.new()
	btn_menu.text = "Главное меню"
	btn_menu.custom_minimum_size = Vector2(240, 54)
	btn_menu.pressed.connect(_on_main_menu)
	row.add_child(btn_menu)

	if NetManager and NetManager.is_multiplayer and not NetManager.is_host:
		btn_continue.disabled = true
		var hint := Label.new()
		hint.text = "Продолжить забег может только хост — вы последуете автоматически."
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		vb.add_child(hint)
		btn_hub.grab_focus()
	else:
		btn_continue.grab_focus()


func _stats_text() -> String:
	if GameManager == null:
		return ""
	var diff_name: String = Difficulty.name_of(GameManager.run_difficulty)
	var loop_part: String = ""
	if GameManager.run_loop > 0:
		loop_part = "Виток %d        " % GameManager.run_loop
	return (
		"%sСложность: %s        Уровень %d        Золото %d        Врагов убито %d"
		% [loop_part, diff_name, GameManager.player_level, GameManager.gold, GameManager.enemies_killed]
	)


# Continue the adventure: generate a fresh run map one tier up (capped), keeping
# the character exactly as-is. Solo starts directly; the co-op host broadcasts
# run_start so the whole party lands on the new map together.
func _on_continue(next_tier: int) -> void:
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = false
	if RunFlow:
		RunFlow.continue_run(next_tier)


# Button 1: end the run and return to the hub. Co-op "all players confirm → hub together"
# is a relay TODO; for now the confirming player goes.
func _on_hub() -> void:
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = false
	if RunFlow:
		RunFlow.exit_to_hub()  # clears run state + swaps the scene (frees this overlay)
	else:
		_change_scene("res://scenes/world/hub.tscn")


# Button 2: leave to the main menu. In co-op, disconnect from the lobby first.
func _on_main_menu() -> void:
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = false
	if NetManager and NetManager.is_multiplayer:
		NetManager.disconnect_from_room()
	if GameManager:
		GameManager.run_state = null
		GameManager.run_node_active = {}
	_change_scene("res://scenes/main.tscn")


func _change_scene(path: String) -> void:
	var ls = get_tree().root.get_node_or_null("LoadingScreen")
	if ls and ls.has_method("preload_and_change_scene"):
		ls.call("preload_and_change_scene", path)
	elif ls and ls.has_method("change_scene"):
		ls.call("change_scene", path)
	else:
		get_tree().change_scene_to_file(path)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			# Enter = continue (solo / host); co-op clients can't start a run,
			# so for them Enter falls back to the hub.
			if NetManager and NetManager.is_multiplayer and not NetManager.is_host:
				_on_hub()
			else:
				_on_continue(
					Difficulty.clamp_tier((GameManager.run_difficulty if GameManager else 0) + 1)
				)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_on_main_menu()
			get_viewport().set_input_as_handled()
