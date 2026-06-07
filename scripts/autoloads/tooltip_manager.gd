extends CanvasLayer

# Tooltip manager — global hover tooltip. Anyone calls TooltipManager.show_tooltip(...)
# to display a hover bubble that follows the mouse and disappears on hide_tooltip().

const RARITY_COLORS := {
	"common": Color(0.85, 0.85, 0.9, 1),
	"rare": Color(0.45, 0.75, 1.0, 1),
	"legendary": Color(1.0, 0.65, 0.25, 1),
	"unique": Color(1.0, 0.4, 0.3, 1),
}

var _root: Control
var _panel: PanelContainer
var _title_label: Label
var _rarity_label: Label
var _body_label: Label
var _meta_label: Label

var _visible: bool = false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"DialogPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(280, 0)
	# Try to load the theme so the panel has the dark style.
	if ResourceLoader.exists("res://assets/ui/theme.tres"):
		_panel.theme = load("res://assets/ui/theme.tres") as Theme
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)

	_title_label = Label.new()
	_title_label.add_theme_color_override("font_color", Color(1, 0.92, 0.6, 1))
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_title_label.add_theme_constant_override("outline_size", 4)
	_title_label.add_theme_font_size_override("font_size", 20)
	v.add_child(_title_label)

	_rarity_label = Label.new()
	_rarity_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_rarity_label.add_theme_constant_override("outline_size", 3)
	_rarity_label.add_theme_font_size_override("font_size", 13)
	v.add_child(_rarity_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1))
	_body_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_body_label.add_theme_constant_override("outline_size", 3)
	_body_label.add_theme_font_size_override("font_size", 15)
	_body_label.custom_minimum_size = Vector2(252, 0)
	v.add_child(_body_label)

	_meta_label = Label.new()
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_meta_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5, 1))
	_meta_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_meta_label.add_theme_constant_override("outline_size", 3)
	_meta_label.add_theme_font_size_override("font_size", 13)
	_meta_label.custom_minimum_size = Vector2(252, 0)
	v.add_child(_meta_label)


func show_tooltip(title: String, rarity: String, body: String, meta: String = "") -> void:
	if _title_label == null:
		return
	_title_label.text = title
	var rar_color: Color = RARITY_COLORS.get(rarity, Color(0.85, 0.85, 0.9, 1))
	_rarity_label.text = rarity.to_upper()
	_rarity_label.add_theme_color_override("font_color", rar_color)
	_body_label.text = body
	if meta != "":
		_meta_label.text = meta
		_meta_label.visible = true
	else:
		_meta_label.text = ""
		_meta_label.visible = false
	_root.visible = true
	_visible = true
	_update_position()


func hide_tooltip() -> void:
	if _root:
		_root.visible = false
	_visible = false


func _process(_delta: float) -> void:
	if _visible:
		_update_position()


func _update_position() -> void:
	if _panel == null or _root == null:
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var mouse: Vector2 = vp.get_mouse_position()
	var size: Vector2 = _panel.size
	if size == Vector2.ZERO:
		size = Vector2(280, 100)
	var view_size: Vector2 = vp.get_visible_rect().size
	var pos: Vector2 = mouse + Vector2(18, 18)
	if pos.x + size.x > view_size.x - 8:
		pos.x = mouse.x - size.x - 18
	if pos.y + size.y > view_size.y - 8:
		pos.y = mouse.y - size.y - 18
	pos.x = max(8.0, pos.x)
	pos.y = max(8.0, pos.y)
	_panel.position = pos
