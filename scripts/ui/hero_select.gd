class_name HeroSelect
extends CanvasLayer

## Hero/class picker shown at the hub wardrobe. Code-built overlay (same pattern as
## spec_path_choice / run_map_ui — no .tscn node_paths). Picking a hero applies it live
## (GameManager.choose_class emits class_selected → the player re-applies) and remembers it
## as the last-played hero (GameManager.set_last_class), then closes.

const CLASS_ORDER: Array = [
	"barbarian", "rogue", "mage", "druid", "necromancer", "hexen", "stormcaller"
]
const CLASS_COLORS: Dictionary = {
	"barbarian": Color(0.86, 0.42, 0.30),
	"rogue": Color(0.55, 0.80, 0.45),
	"mage": Color(0.45, 0.62, 1.0),
	"druid": Color(0.55, 0.85, 0.55),
	"necromancer": Color(0.65, 0.55, 0.85),
	"hexen": Color(0.85, 0.45, 0.78),
	"stormcaller": Color(0.45, 0.85, 0.95),
}

signal closed


func _ready() -> void:
	layer = 32
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 12)
	dim.add_child(vb)

	var title := Label.new()
	title.text = "Гардероб — выберите героя"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	vb.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(grid)

	var current: String = GameManager.player_class if GameManager else GameManager.last_class
	for cid in CLASS_ORDER:
		grid.add_child(_make_card(cid, cid == current))

	var hint := Label.new()
	hint.text = "Esc / клик вне окна — закрыть"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
	vb.add_child(hint)


func _make_card(class_id: String, is_current: bool) -> Button:
	var data: Dictionary = GameManager.get_class_data(class_id) if GameManager else {}
	var display: String = String(data.get("display", class_id.capitalize()))
	var col: Color = CLASS_COLORS.get(class_id, Color(0.7, 0.7, 0.8))
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 64)
	var lvl: int = MetaProgress.get_meta_level(class_id) if MetaProgress else 1
	b.text = ("★ " + display if is_current else display) + "\nУр. %d" % lvl
	b.autowrap_mode = TextServer.AUTOWRAP_OFF
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	for sname in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.15) if sname == "normal" else col
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(3 if is_current else 1)
		sb.border_color = Color(1, 1, 0.7) if is_current else col.lightened(0.3)
		b.add_theme_stylebox_override(sname, sb)
	b.pressed.connect(_choose.bind(class_id))
	return b


func _choose(class_id: String) -> void:
	if GameManager:
		GameManager.choose_class(class_id)  # emits class_selected → player re-applies live
		GameManager.set_last_class(class_id)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_button_click.mp3", -6.0)
	_close()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
