extends Control

const PLAY_TARGET_SCENE := "res://scenes/world/game_world.tscn"
const HUB_SCENE := "res://scenes/world/hub.tscn"

# Buttons detected by scanning assets/ui/btn_*.tres at provisioning time.
# Parallel arrays (rather than Array[Dictionary]) because GDScript const
# Dictionary literals have spotty support across Godot 4.x point releases.
const BUTTON_IDS: PackedStringArray = ["play", "back", "quit", "choose"]
const BUTTON_STYLEBOXES: PackedStringArray = [
	"res://assets/ui/btn_play.tres",
	"res://assets/ui/btn_back.tres",
	"res://assets/ui/btn_quit.tres",
	"res://assets/ui/btn_choose.tres"
]

# Runtime-resolved per-game asset paths (first existing wins).
const BG_CANDIDATES: PackedStringArray = [
	"res://assets/ui/title_poster.webp",
	"res://assets/ui/title_poster.png",
	"res://assets/textures/backgrounds/menu_background.webp",
	"res://assets/textures/backgrounds/menu_bg.png",
	"res://assets/ui/menu_background.png",
]
const CLICK_SFX_CANDIDATES: PackedStringArray = [
	"res://assets/audio/sfx/ui/ui_ui_menu_click.mp3",
	"res://assets/audio/sfx/ui/ui_menu_click.mp3",
	"res://assets/audio/sfx/ui/ui_button_click.mp3",
	"res://assets/audio/sfx/ui/ui_click.mp3",
	"res://assets/audio/sfx/ui/ui_ui_click.mp3",
	"res://assets/audio/sfx/ui/ui_merchant_purchase.mp3",
]
const SETTINGS_SCENE_CANDIDATES: PackedStringArray = [
	"res://scenes/ui/settings.tscn",
	"res://scenes/settings.tscn",
]
const CREDITS_SCENE_CANDIDATES: PackedStringArray = [
	"res://scenes/ui/credits.tscn",
	"res://scenes/credits.tscn",
]

var _click_sfx_stream: AudioStream = null
var _wordmark: TextureRect = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if ResourceLoader.exists("res://assets/ui/theme.tres"):
		theme = load("res://assets/ui/theme.tres") as Theme

	var sfx_path := _first_existing(CLICK_SFX_CANDIDATES)
	if sfx_path != "":
		_click_sfx_stream = load(sfx_path) as AudioStream

	_build_background()
	_build_wordmark()
	_build_buttons()


func _first_existing(paths: PackedStringArray) -> String:
	for p in paths:
		if ResourceLoader.exists(p):
			return p
	return ""


func _build_background() -> void:
	var bg_path := _first_existing(BG_CANDIDATES)
	if bg_path != "":
		var bg := TextureRect.new()
		bg.texture = load(bg_path)
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var solid := ColorRect.new()
		solid.color = Color(0.08, 0.08, 0.10, 1.0)
		solid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(solid)
		solid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Vignette overlay so wordmark + buttons read against busy backgrounds.
	var vignette := ColorRect.new()
	vignette.color = Color(0, 0, 0, 0.35)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_wordmark() -> void:
	if not ResourceLoader.exists("res://assets/ui/wordmark_title.webp"):
		return
	_wordmark = TextureRect.new()
	_wordmark.texture = load("res://assets/ui/wordmark_title.webp")
	_wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wordmark.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wordmark)
	# R1: explicit anchors, symmetric +/- around 0.5. No CenterContainer
	# wrapper (that was test-16's Rule-4 trap).
	_wordmark.anchor_left = 0.5
	_wordmark.anchor_right = 0.5
	_wordmark.anchor_top = 0.0
	_wordmark.anchor_bottom = 0.0
	_wordmark.offset_left = -450
	_wordmark.offset_right = 450
	_wordmark.offset_top = 80
	_wordmark.offset_bottom = 380


func _build_buttons() -> void:
	# Single CenterContainer + single VBoxContainer holds every button.
	# R4-safe: do NOT introduce a band wrapper (PRESET_TOP_WIDE etc.); on
	# a Control parent, that fights the centering and produces the kind
	# of layout drift test-16 had.
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	# Push the VBox below the wordmark so buttons sit in the lower half.
	if _wordmark != null:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 240)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(spacer)

	var n := BUTTON_IDS.size()
	for i in n:
		var btn := _make_button(BUTTON_IDS[i], BUTTON_STYLEBOXES[i])
		vbox.add_child(btn)


func _make_button(id: String, stylebox_path: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(360, 110)
	btn.text = ""  # kit buttons bake their label into the art
	btn.focus_mode = Control.FOCUS_NONE
	if ResourceLoader.exists(stylebox_path):
		var sb := load(stylebox_path) as StyleBox
		if sb:
			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_stylebox_override("hover", sb)
			btn.add_theme_stylebox_override("pressed", sb)
			btn.add_theme_stylebox_override("focus", sb)
			btn.add_theme_stylebox_override("disabled", sb)
	btn.mouse_entered.connect(_on_button_hover.bind(btn, true))
	btn.mouse_exited.connect(_on_button_hover.bind(btn, false))
	btn.pressed.connect(_on_button_pressed.bind(id))
	return btn


func _on_button_hover(btn: Button, entering: bool) -> void:
	var target := Color(1.10, 1.10, 1.10, 1.0) if entering else Color(1.0, 1.0, 1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(btn, "modulate", target, 0.08)


func _on_button_pressed(id: String) -> void:
	_play_click_sfx()
	match id:
		"play", "continue", "new_game":
			# Straight into the hub as the last-played hero (no solo/co-op picker — co-op
			# create/join via the hub is a later task). You pick difficulty + nodes from
			# the run map reached through the hub portal.
			_go_to_hub()
		"settings", "options":
			_open_settings_or_noop()
		"credits":
			_open_credits_or_noop()
		"back":
			# Direct multiplayer entry (legacy back button).
			_go_to_lobby("multiplayer")
		"choose":
			# Direct multiplayer entry (legacy choose button).
			_go_to_lobby("multiplayer")
		"quit", "exit":
			_quit_game()
		_:
			push_warning("Main menu: unknown button id '" + id + "' (no action wired).")


# ─────────────────────────────────────────────────────────────────────────────
# Solo / Multiplayer chooser modal.
var _mode_modal: Control = null


func _show_mode_picker_modal() -> void:
	if _mode_modal and is_instance_valid(_mode_modal):
		return
	_mode_modal = _build_mode_modal()
	add_child(_mode_modal)
	_mode_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_mode_modal() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DialogPanel"
	root.add_child(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -240
	panel.offset_bottom = 240
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vb)
	var title := Label.new()
	title.text = "CHOOSE YOUR PATH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.5, 1))
	title.add_theme_color_override("font_outline_color", Color(0.2, 0.05, 0.05, 1))
	title.add_theme_constant_override("outline_size", 5)
	vb.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Descend alone — or bring up to 3 friends"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62, 1))
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	subtitle.add_theme_constant_override("outline_size", 3)
	vb.add_child(subtitle)
	var solo_btn := _modal_button("PLAY SOLO", Color(0.95, 0.7, 0.4, 1))
	solo_btn.pressed.connect(
		func():
			_close_modal()
			_go_to_lobby("solo")
	)
	vb.add_child(solo_btn)
	var mp_btn := _modal_button("ONLINE CO-OP", Color(1.0, 0.4, 0.35, 1))
	mp_btn.pressed.connect(
		func():
			_close_modal()
			_go_to_lobby("multiplayer")
	)
	vb.add_child(mp_btn)
	var cancel_btn := _modal_button("Cancel", Color(0.85, 0.78, 0.62, 1))
	cancel_btn.custom_minimum_size = Vector2(220, 56)
	cancel_btn.pressed.connect(_close_modal)
	vb.add_child(cancel_btn)
	return root


func _modal_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = ""  # Label child carries the text.
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(360, 80)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Blank gothic stylebox so every kit-button looks the same.
	const BLANK_PATH := "res://assets/ui/btn_blank.tres"
	if ResourceLoader.exists(BLANK_PATH):
		var sb := load(BLANK_PATH) as StyleBox
		if sb:
			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_stylebox_override("hover", sb)
			btn.add_theme_stylebox_override("pressed", sb)
			btn.add_theme_stylebox_override("focus", sb)
			btn.add_theme_stylebox_override("disabled", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.03, 0.0, 1))
	lbl.add_theme_constant_override("outline_size", 3)
	btn.add_child(lbl)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.mouse_entered.connect(func(): btn.modulate = Color(1.15, 1.15, 1.15, 1))
	btn.mouse_exited.connect(func(): btn.modulate = Color(1, 1, 1, 1))
	return btn


func _close_modal() -> void:
	if _mode_modal and is_instance_valid(_mode_modal):
		_mode_modal.queue_free()
		_mode_modal = null


func _go_to_lobby(intent: String) -> void:
	# Clear any stale connection and stamp the intent so the lobby knows
	# whether to show Pre-Room (Host/Join) or jump straight to Solo in-room.
	if NetManager:
		NetManager.disconnect_from_room()
		NetManager.lobby_intent = intent
	const LOBBY_PATH := "res://scenes/ui/multiplayer_lobby.tscn"
	if not ResourceLoader.exists(LOBBY_PATH):
		push_warning("Multiplayer lobby scene missing.")
		return
	var loader := get_node_or_null("/root/LoadingScreen")
	if loader and loader.has_method("preload_and_change_scene"):
		loader.preload_and_change_scene(LOBBY_PATH)
	else:
		get_tree().change_scene_to_file(LOBBY_PATH)


# (_open_multiplayer_lobby / _go_to_play_solo replaced by _go_to_lobby + modal above.)


func _go_to_play() -> void:
	var loader := get_node_or_null("/root/LoadingScreen")
	if loader and loader.has_method("preload_and_change_scene"):
		loader.preload_and_change_scene(PLAY_TARGET_SCENE)
	else:
		get_tree().change_scene_to_file(PLAY_TARGET_SCENE)


# Enter the walkable hub (solo). Drop any stale net connection so the hub/run are solo.
func _go_to_hub() -> void:
	if NetManager:
		NetManager.disconnect_from_room()
		NetManager.lobby_intent = ""
	var loader := get_node_or_null("/root/LoadingScreen")
	if loader and loader.has_method("preload_and_change_scene"):
		loader.preload_and_change_scene(HUB_SCENE)
	else:
		get_tree().change_scene_to_file(HUB_SCENE)


func _open_settings_or_noop() -> void:
	var path := _first_existing(SETTINGS_SCENE_CANDIDATES)
	if path != "":
		get_tree().change_scene_to_file(path)


func _open_credits_or_noop() -> void:
	var path := _first_existing(CREDITS_SCENE_CANDIDATES)
	if path != "":
		get_tree().change_scene_to_file(path)


func _quit_game() -> void:
	get_tree().quit()


func _play_click_sfx() -> void:
	# Inline AudioStreamPlayer so we don't depend on AudioManager. Some
	# games' AudioManager.play_sfx takes (AudioStream, db), others take
	# (String, db); calling the wrong signature is a runtime error
	# GDScript can't catch. Playing the click ourselves sidesteps that.
	if _click_sfx_stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = _click_sfx_stream
	p.volume_db = -4.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
