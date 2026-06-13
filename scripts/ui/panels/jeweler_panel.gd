extends CanvasLayer

## Ювелир (hub overlay, code-built like gamble_shop). Работает с САМОЦВЕТАМИ
## в сумке (ран-скоупными камнями для гнёзд экипировки):
##   • Слияние: 3 одинаковых камня → случайный камень тиром выше
##     (common→rare→legendary→unique). Неперекрашенные тратятся первыми.
##   • Перекраска: выбери камень → грань (▲▶▼◀) → цвет; стоит золото + эссенцию
##     (InventorySystem.REPAINT_COST). Уникальные камни не перекрашиваются.
##
## Чисто локальное состояние — ничего не сетевое и не ставит дерево на паузу.

signal closed

const FACE_ARROWS: Array = ["▲", "▶", "▼", "◀"]
const PAINT_COLORS: Array = ["red", "green", "blue", "white"]

var _wallet_label: Label = null
var _list_box: VBoxContainer = null
var _detail_box: VBoxContainer = null
var _selected: ItemInstance = null
var _selected_face: int = 0


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if InventorySystem:
		InventorySystem.inventory_changed.connect(_refresh)
	if GameManager:
		GameManager.gold_changed.connect(func(_g): _refresh())
		GameManager.materials_changed.connect(_refresh)


func _build() -> void:
	var dim := UIBuilder.dim_overlay(Color(0.03, 0.02, 0.05, 0.88))
	add_child(dim)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.13, 0.97)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.78, 0.66, 0.35)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -430
	panel.offset_right = 430
	panel.offset_top = -290
	panel.offset_bottom = 290
	dim.add_child(panel)

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 24)
	panel.add_child(margin)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	margin.add_child(main)

	main.add_child(_label("ЮВЕЛИР", 28, Color(0.95, 0.85, 0.5)))
	main.add_child(
		_label("«Грань решает всё. Принесите три — заберёте один, но какой!»", 13, Color(0.78, 0.74, 0.62))
	)
	_wallet_label = _label("", 16, Color(0.72, 0.86, 1.0))
	main.add_child(_wallet_label)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(cols)

	# Лево: список самоцветов в сумке (клик = выбрать).
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(370, 0)
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	left.add_child(_label("Самоцветы в сумке", 16, Color(0.9, 0.85, 0.95)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_box)

	# Право: мастерская выбранного камня (слияние + перекраска).
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 8)
	_detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_detail_box)

	var leave := Button.new()
	leave.text = "Уйти"
	leave.custom_minimum_size = Vector2(160, 42)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(_close)
	main.add_child(leave)

	_refresh()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 3)
	return l


func _bag_gems() -> Array:
	var out: Array = []
	if InventorySystem:
		for it in InventorySystem.inventory:
			if it is ItemInstance and (it as ItemInstance).is_gem():
				out.append(it)
	return out


func _refresh() -> void:
	if _wallet_label == null or GameManager == null:
		return
	_wallet_label.text = (
		"Золото: %d   Эссенция: %d" % [GameManager.gold, GameManager.get_material("essence")]
	)
	# Список слева.
	for c in _list_box.get_children():
		c.queue_free()
	var gems: Array = _bag_gems()
	if not gems.has(_selected):
		_selected = null
	if gems.is_empty():
		_list_box.add_child(
			_label("Пусто — самоцветы падают в забегах\nи из сундуков.", 13, Color(0.6, 0.58, 0.66))
		)
	for it in gems:
		_list_box.add_child(_make_row(it as ItemInstance))
	_rebuild_detail()


func _make_row(item: ItemInstance) -> Button:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 44)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var painted: String = "  (перекрашен)" if not item.gem_faces.is_empty() else ""
	row.text = "   ◆ %s%s" % [item.get_title(), painted]
	row.add_theme_font_size_override("font_size", 14)
	row.add_theme_color_override(
		"font_color", ItemDatabase.rarity_color(item.rarity).lightened(0.2)
	)
	row.tooltip_text = SocketGems.describe(item.gem_id, 0, item.gem_faces)
	var icon := GemFaceIcon.new()
	icon.faces = item.get_gem_faces()
	icon.custom_minimum_size = Vector2(30, 30)
	icon.size = Vector2(30, 30)
	icon.position = Vector2(8, 7)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	if item == _selected:
		row.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	row.pressed.connect(
		func():
			_selected = item
			_selected_face = 0
			_refresh()
	)
	return row


# ── Правая панель: слияние + перекраска выбранного камня ─────────────────────
func _rebuild_detail() -> void:
	for c in _detail_box.get_children():
		c.queue_free()
	if _selected == null:
		_detail_box.add_child(
			_label("Выберите самоцвет слева:\nслияние 3 → 1 тиром выше,\nперекраска граней.", 14, Color(0.7, 0.68, 0.6))
		)
		return
	var item: ItemInstance = _selected
	_detail_box.add_child(_label(item.get_title(), 19, ItemDatabase.rarity_color(item.rarity)))

	# Крупное превью с выделенной гранью.
	var preview := GemFaceIcon.new()
	preview.faces = item.get_gem_faces()
	preview.custom_minimum_size = Vector2(96, 96)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail_box.add_child(preview)

	# Слияние.
	var have: int = InventorySystem.count_bag_gems(item.gem_id) if InventorySystem else 0
	var next_rarity: String = String(SocketGems.RARITY_NEXT.get(item.rarity, ""))
	if next_rarity != "":
		var fuse := Button.new()
		fuse.text = (
			"Слить 3 «%s» (%d/%d) → случайный %s"
			% [
				item.get_title(),
				have,
				InventorySystem.FUSE_COUNT,
				ItemDatabase.rarity_display(next_rarity)
			]
		)
		fuse.add_theme_font_size_override("font_size", 14)
		fuse.custom_minimum_size = Vector2(0, 44)
		fuse.disabled = have < InventorySystem.FUSE_COUNT
		fuse.pressed.connect(_on_fuse.bind(item.gem_id))
		_detail_box.add_child(fuse)
	else:
		_detail_box.add_child(
			_label("Уникальный камень — выше сливать некуда.", 13, Color(0.7, 0.6, 0.55))
		)

	# Перекраска.
	if item.rarity == ItemDatabase.RARITY_UNIQUE:
		_detail_box.add_child(
			_label("Грани уникальных камней не перекрашиваются.", 13, Color(0.7, 0.6, 0.55))
		)
		return
	_detail_box.add_child(
		_label(
			"Перекраска грани: %s" % ItemDatabase.format_cost(InventorySystem.REPAINT_COST),
			14,
			Color(1.0, 0.85, 0.4)
		)
	)
	var faces: Array = item.get_gem_faces()
	var face_row := HBoxContainer.new()
	face_row.alignment = BoxContainer.ALIGNMENT_CENTER
	face_row.add_theme_constant_override("separation", 8)
	_detail_box.add_child(face_row)
	for i in 4:
		var fb := Button.new()
		fb.text = String(FACE_ARROWS[i])
		fb.custom_minimum_size = Vector2(52, 52)
		fb.add_theme_font_size_override("font_size", 22)
		fb.add_theme_color_override("font_color", SocketGems.color_tint(String(faces[i])))
		fb.tooltip_text = String(SocketGems.COLOR_NAMES.get(String(faces[i]), "?"))
		if i == _selected_face:
			fb.add_theme_color_override("font_outline_color", Color(1, 0.95, 0.6))
			fb.add_theme_constant_override("outline_size", 4)
		fb.pressed.connect(
			func():
				_selected_face = i
				_rebuild_detail()
		)
		face_row.add_child(fb)
	_detail_box.add_child(
		_label("Покрасить грань %s в:" % String(FACE_ARROWS[_selected_face]), 14, Color(0.9, 0.85, 0.95))
	)
	var color_row := HBoxContainer.new()
	color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	color_row.add_theme_constant_override("separation", 8)
	_detail_box.add_child(color_row)
	for color in PAINT_COLORS:
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(52, 36)
		cb.tooltip_text = String(SocketGems.COLOR_NAMES.get(color, color))
		var csb := StyleBoxFlat.new()
		csb.bg_color = SocketGems.color_tint(String(color)).darkened(0.2)
		csb.set_corner_radius_all(8)
		cb.add_theme_stylebox_override("normal", csb)
		var hsb: StyleBoxFlat = csb.duplicate()
		hsb.bg_color = hsb.bg_color.lightened(0.2)
		cb.add_theme_stylebox_override("hover", hsb)
		cb.disabled = String(faces[_selected_face]) == String(color)
		cb.pressed.connect(_on_repaint.bind(item, String(color)))
		color_row.add_child(cb)


func _on_fuse(gem_id: String) -> void:
	if InventorySystem == null:
		return
	var result: ItemInstance = InventorySystem.fuse_gems(gem_id)
	if result == null:
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_fail.mp3", -8.0)
		return
	_selected = result
	_selected_face = 0
	if GameManager:
		GameManager.notice.emit(
			"Слияние: %s (%s)" % [result.get_title(), ItemDatabase.rarity_display(result.rarity)],
			ItemDatabase.rarity_color(result.rarity)
		)
	_refresh()


func _on_repaint(item: ItemInstance, color: String) -> void:
	if InventorySystem == null:
		return
	if not InventorySystem.repaint_gem_face(item, _selected_face, color):
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_fail.mp3", -8.0)
	# inventory_changed уже дёрнул _refresh; выбор сохраняем.
	_selected = item
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
