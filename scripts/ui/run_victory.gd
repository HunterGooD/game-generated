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
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.93)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	dim.add_child(vb)

	var title := Label.new()
	title.text = "★  V I C T O R Y  ★"
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
	sub.text = "The uber-boss falls. The run is yours."
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

	var btn := Button.new()
	btn.text = "Return to Hub"
	btn.custom_minimum_size = Vector2(260, 54)
	btn.pressed.connect(_on_return)
	vb.add_child(btn)
	btn.grab_focus()


func _stats_text() -> String:
	if GameManager == null:
		return ""
	var diff_name: String = Difficulty.name_of(GameManager.run_difficulty)
	return (
		"Difficulty: %s        Level %d        Gold %d        Foes slain %d"
		% [diff_name, GameManager.player_level, GameManager.gold, GameManager.enemies_killed]
	)


func _on_return() -> void:
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = false
	# Ends the run and returns to the hub (RunFlow clears run state + swaps the scene,
	# which frees this overlay).
	if RunFlow:
		RunFlow.exit_to_hub()
	else:
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			_on_return()
			get_viewport().set_input_as_handled()
