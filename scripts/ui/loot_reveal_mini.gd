extends CanvasLayer

## Compact, NON-BLOCKING loot reveal used while you're IN COMBAT. A small panel in
## the bottom-right rolls through item icons, decelerates onto the award, then drops
## it straight into your inventory and fades. It never pauses, never captures input,
## and grants no safe window — so you keep moving and fighting and can't die just
## because you opened a chest. The juicy full-screen roulette (with Take/Salvage) is
## still used out of combat, where it's safe. Speed scales with how hot the fight is.

const FRAME_COLORS: Dictionary = {
	"common": Color(0.65, 0.65, 0.70, 1),
	"rare": Color(0.4, 0.7, 1.0, 1),
	"legendary": Color(1.0, 0.65, 0.18, 1),
	"unique": Color(1.0, 0.35, 0.25, 1),
}

var _award: ItemInstance = null
var _strip: Array = []
var _duration: float = 1.3
var _elapsed: float = 0.0
var _swap_t: float = 0.0
var _strip_idx: int = 0
var _settled: bool = false

var _icon: TextureRect = null
var _name: Label = null
var _panel: PanelContainer = null


func start(item: ItemInstance, wave: int, class_id: String, duration: float = 1.3) -> void:
	_award = item
	_duration = maxf(0.5, duration)
	_strip = LootRoller.roll_preview_strip(16, wave, class_id)
	if _strip.is_empty():
		_strip = [item]
	_build()


func _ready() -> void:
	layer = 55
	# NOT process_mode ALWAYS — in combat the tree isn't paused, and we explicitly
	# don't want a safe window. It runs with the world.


func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.12, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.85, 0.7, 0.4, 0.8)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom-right, clear of the bottom-left LEVEL UP button and the hotbar centre.
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -300
	_panel.offset_right = -24
	_panel.offset_top = -210
	_panel.offset_bottom = -90
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(84, 84)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(vb)
	var head := _label("Добыча", 13, Color(0.8, 0.75, 0.6))
	vb.add_child(head)
	_name = _label("...", 17, Color(1, 0.92, 0.65))
	_name.custom_minimum_size = Vector2(170, 0)
	vb.add_child(_name)

	_show_item(_strip[0])


func _process(delta: float) -> void:
	if _settled:
		return
	_elapsed += delta
	if _elapsed >= _duration:
		_settle()
		return
	# Decelerating icon swaps: fast at the start, slowing as we approach the award.
	var frac: float = _elapsed / _duration
	var interval: float = lerpf(0.05, 0.22, frac)
	_swap_t -= delta
	if _swap_t <= 0.0:
		_swap_t = interval
		_strip_idx = (_strip_idx + 1) % _strip.size()
		_show_item(_strip[_strip_idx])


func _settle() -> void:
	_settled = true
	_show_item(_award)
	# Item drops into the inventory now (on finish, as requested).
	if InventorySystem:
		InventorySystem.add_item(_award)
	var rar: String = String(_award.rarity)
	if AudioManager:
		var path: String = "res://assets/audio/sfx/ui/ui_loot_reveal_%s.mp3" % rar
		if not ResourceLoader.exists(path):
			path = "res://assets/audio/sfx/ui/ui_loot_reveal_common.mp3"
		AudioManager.play_sfx_path(path, -7.0)
	# Pop + hold + fade.
	if _panel:
		var tw := _panel.create_tween()
		tw.tween_property(_panel, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_BACK)
		tw.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.12)
		tw.tween_interval(1.4)
		tw.tween_property(_panel, "modulate:a", 0.0, 0.4)
		tw.tween_callback(queue_free)
	else:
		queue_free()


func _show_item(item: ItemInstance) -> void:
	if item == null:
		return
	if _icon:
		_icon.texture = item.get_icon()
	if _name:
		var col: Color = FRAME_COLORS.get(String(item.rarity), Color.WHITE)
		_name.text = item.get_title()
		_name.add_theme_color_override("font_color", col)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l
