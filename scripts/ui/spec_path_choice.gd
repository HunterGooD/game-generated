class_name SpecPathChoice
extends CanvasLayer

# Level-7 ascension choice: 3 class paths (each: new R ability + passive) plus a
# 4th "Remain Mortal" card (no R, just a base-stat boost). Built in code; each card
# is a ColorRect driven by ascension_card.gdshader (role-tinted glow; the mortal
# card is desaturated). Picking applies via GameManager.choose_spec_path.

const CARD_SHADER := preload("res://assets/shaders/ascension_card.gdshader")

const ROLE_TINT := {
	"warrior": Color(1.0, 0.42, 0.18),
	"caster": Color(0.55, 0.5, 1.0),
	"support": Color(0.3, 0.92, 0.8),
}

# Minimised WITHOUT choosing — game_world keeps the awakening pending and re-shows its HUD
# button (mirrors the level-up overlay). The choice itself reports via GameManager.spec_path_chosen.
signal collapsed

var _did_pause: bool = false
var _locked: bool = false


func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Mandatory pick. In SOLO we pause the tree. In CO-OP we must NOT freeze the tree
	# (players don't always reach level 7 on the same kill, and a tree pause would
	# stall the host sim + stop this player's damage for everyone). Instead give the
	# local player a personal pause — invulnerable + control-locked — so the choice is
	# safe and can't be abused, exactly like the boss-reward reels.
	if NetManager and NetManager.is_multiplayer:
		_locked = true
		_apply_lock(true)
	else:
		get_tree().paused = true
		_did_pause = true
	_build()


# Freeze + protect ONLY the local player (remote puppets take no local input).
func _apply_lock(locked: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for p in tree.get_nodes_in_group("player"):
		if not is_instance_valid(p) or p.is_in_group("remote_player"):
			continue
		if p.get("control_locked") != null:
			p.set("control_locked", locked)
		if p.get("invuln_t") != null:
			p.set("invuln_t", 99999.0 if locked else 1.0)


func _exit_tree() -> void:
	# Backstop: never strand the player frozen/invuln if freed without _choose().
	if _locked:
		_apply_lock(false)
		_locked = false


func _build() -> void:
	var dim := UIBuilder.dim_overlay(Color(0.02, 0.01, 0.04, 0.82))
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	center.add_child(vb)

	var title := Label.new()
	title.text = "ВОЗНЕСЕНИЕ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55, 1))
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 1))
	title.add_theme_constant_override("outline_size", 6)
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "Выберите путь — новая способность (R) + пассивка — или останьтесь смертным ради чистой силы."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.82, 0.82, 0.88, 1))
	vb.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)

	var cls: String = String(GameManager.player_class) if GameManager else "mage"
	const ROLE_NAMES := {"warrior": "ВОИН", "caster": "ЗАКЛИНАТЕЛЬ", "support": "ПОДДЕРЖКА"}
	for p in SpecPaths.paths_for(cls):
		var role: String = String(p.get("role", "caster"))
		var tint: Color = ROLE_TINT.get(role, Color(0.7, 0.7, 0.8))
		var body: String = (
			"— %s —\n\n%s\n\n[R] новая способность + пассивка"
			% [String(ROLE_NAMES.get(role, role.to_upper())), String(p.get("desc", ""))]
		)
		row.add_child(_make_card(String(p.get("name", "?")), body, tint, 0.0, String(p.get("id", ""))))

	var mortal_body: String = (
		"— СМЕРТНЫЙ —\n\nОтказаться от вознесения.\n\nБез способности R, но солидное всестороннее усиление базовых характеристик."
	)
	row.add_child(
		_make_card("Остаться смертным", mortal_body, Color(0.62, 0.64, 0.72), 1.0, SpecPaths.MORTAL_ID)
	)

	# Minimise button — dismiss the choice and keep fighting; reopen from the HUD button when
	# it's safe. The awakening stays unspent until a card is actually picked.
	var collapse_btn := Button.new()
	collapse_btn.text = "Свернуть — выбрать позже"
	collapse_btn.focus_mode = Control.FOCUS_NONE
	collapse_btn.custom_minimum_size = Vector2(320, 44)
	collapse_btn.add_theme_font_size_override("font_size", 18)
	collapse_btn.pressed.connect(_collapse)
	vb.add_child(collapse_btn)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_collapse()
		get_viewport().set_input_as_handled()


func _collapse() -> void:
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_button_click.mp3", -8.0)
	if _did_pause:
		get_tree().paused = false
		_did_pause = false
	if _locked:
		_apply_lock(false)
		_locked = false
	collapsed.emit()
	queue_free()


func _make_card(title: String, body: String, tint: Color, grey: float, choice_id: String) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(278, 400)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = CARD_SHADER
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("grey", grey)
	mat.set_shader_parameter("intensity", 1.0)
	bg.material = mat
	card.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	card.add_child(margin)

	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 12)
	margin.add_child(cvb)

	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	name_lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 1))
	name_lbl.add_theme_constant_override("outline_size", 5)
	cvb.add_child(name_lbl)

	var body_lbl := Label.new()
	body_lbl.text = body
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_lbl.add_theme_font_size_override("font_size", 16)
	body_lbl.add_theme_color_override("font_color", Color(0.96, 0.96, 1, 1))
	body_lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 1))
	body_lbl.add_theme_constant_override("outline_size", 3)
	body_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cvb.add_child(body_lbl)

	card.gui_input.connect(_on_card_input.bind(choice_id))
	card.mouse_entered.connect(func(): mat.set_shader_parameter("intensity", 1.6))
	card.mouse_exited.connect(func(): mat.set_shader_parameter("intensity", 1.0))
	return card


func _on_card_input(event: InputEvent, choice_id: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_choose(choice_id)


func _choose(choice_id: String) -> void:
	if GameManager and GameManager.has_method("choose_spec_path"):
		GameManager.choose_spec_path(choice_id)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_level_up.mp3", -6.0)
	if _did_pause:
		get_tree().paused = false
	if _locked:
		_apply_lock(false)
		_locked = false
	queue_free()
