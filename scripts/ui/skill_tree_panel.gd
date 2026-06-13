class_name SkillTreePanel
extends CanvasLayer

# Панель развития [T] — НАСТОЯЩЕЕ дерево умений (граф с круглыми узлами и связями).
# Слева — колонка статов (Сила/Ловкость/Интеллект) и ниже узлы пробуждения (ult).
# Справа — холст-граф: сверху корни-навыки, вниз пассивки/варианты/статус-узлы,
# рёбра рисуются линиями; общие узлы переплетают ветки. Холст пролистывается
# колесом и перетаскиванием. Вознесение (выбор пути) — отдельный оверлей на 7 ур.
#
# Code-built оверлей. Co-op инвариант: НИКОГДА не паузит дерево.

signal closed

const CELL_W := 96
const CELL_H := 104
const NODE := 64
const MARGIN := 28

const PASSIVE_COLOR := Color(0.7, 0.85, 0.7)
const SKILL_COLOR := Color(1.0, 0.86, 0.45)
const VARIANT_COLOR := Color(1.0, 0.55, 0.4)
const VARIANT_ACTIVE_COLOR := Color(0.45, 0.95, 0.5)
const SHARED_COLOR := Color(0.55, 0.78, 1.0)
const PERK_COLOR := Color(1.0, 0.6, 0.2)
const STATUS_COLOR := Color(0.9, 0.5, 0.85)
const ULT_COLOR := Color(0.6, 0.85, 1.0)
const CHOICE_COLOR := Color(1.0, 0.8, 0.3)

var _points_label: Label = null
var _body_row: HBoxContainer = null
var _scroll: ScrollContainer = null
var _dragging: bool = false


# Слой рёбер: рисует линии между центрами узлов (под кнопками).
class _EdgeLayer:
	extends Control
	var edges: Array = []  # [{from:Vector2, to:Vector2, on:bool}]

	func _draw() -> void:
		for e in edges:
			var col: Color = (
				Color(0.85, 0.8, 0.5, 0.9) if bool(e["on"]) else Color(0.4, 0.42, 0.5, 0.5)
			)
			draw_line(e["from"], e["to"], col, 3.0 if bool(e["on"]) else 2.0, true)


func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_chrome()
	_rebuild()
	if GameManager:
		GameManager.talents_changed.connect(_rebuild)
		# NOT player_stats_changed — it fires every frame from HP/mana regen (the
		# tree doesn't pause the game), which would rebuild + reset scroll constantly.
		GameManager.player_levelled_up.connect(_on_levelled_up)
		GameManager.spec_path_chosen.connect(_on_spec_path_chosen)


func _on_levelled_up(_lv: int) -> void:
	_rebuild()


func _on_spec_path_chosen(_path_id: String) -> void:
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("ui_cancel")
		or event.is_action_pressed("open_talents")
		or event.is_action_pressed("open_skills")
	):
		_close()
		get_viewport().set_input_as_handled()


func _build_chrome() -> void:
	var dim := UIBuilder.dim_overlay(Color(0.02, 0.02, 0.05, 0.86))
	add_child(dim)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InventoryPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -680
	panel.offset_right = 680
	panel.offset_top = -400
	panel.offset_bottom = 400
	dim.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var title := Label.new()
	title.text = "Развитие — %s   [T]" % _class_display()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.92, 0.65))
	v.add_child(title)

	_body_row = HBoxContainer.new()
	_body_row.add_theme_constant_override("separation", 14)
	_body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body_row)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	v.add_child(footer)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 22)
	_points_label.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	footer.add_child(_points_label)

	var hint := Label.new()
	hint.text = "Колесо/перетаскивание — листать. Корень-навык: +урон, −кд. Вариант — 2 очка. Сброс у костра."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)

	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.custom_minimum_size = Vector2(140, 40)
	close_btn.pressed.connect(_close)
	footer.add_child(close_btn)


func _class_display() -> String:
	if GameManager == null:
		return "?"
	return String(GameManager.get_class_data().get("display", GameManager.player_class))


func _rebuild() -> void:
	if _body_row == null or GameManager == null:
		return
	# Preserve scroll position so buying a node doesn't snap the view to the top.
	var sh: int = 0
	var sv: int = 0
	if _scroll != null and is_instance_valid(_scroll):
		sh = _scroll.scroll_horizontal
		sv = _scroll.scroll_vertical
	for c in _body_row.get_children():
		c.queue_free()
	_body_row.add_child(_build_stat_column())
	_body_row.add_child(_build_graph())
	_refresh_footer()
	if _scroll != null:
		_scroll.set_deferred("scroll_horizontal", sh)
		_scroll.set_deferred("scroll_vertical", sv)


# ── Колонка статов + узлы пробуждения ────────────────────────────────────────
func _build_stat_column() -> Control:
	var col := PanelContainer.new()
	col.custom_minimum_size = Vector2(196, 0)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	col.add_child(v)

	v.add_child(_header("Атрибуты", Color(0.8, 0.95, 1.0)))
	for s in SkillTrees.STAT_NODES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = "%s: %d" % [String(s["name"]), _stat_value(String(s["stat"]))]
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(40, 34)
		plus.disabled = GameManager.node_block_reason(String(s["id"])) != ""
		plus.pressed.connect(_on_node_pressed.bind(String(s["id"])))
		row.add_child(plus)
		v.add_child(row)

	v.add_child(_header("Пробуждение", ULT_COLOR))
	for u in TalentTrees.ULT_NODES:
		v.add_child(_list_node_button(u))
	return col


func _stat_value(stat: String) -> int:
	match stat:
		"strength":
			return GameManager.get_effective_strength()
		"dexterity":
			return GameManager.get_effective_dexterity()
		"intelligence":
			return GameManager.get_effective_intelligence()
	return 0


# ── Граф навыков ─────────────────────────────────────────────────────────────
func _build_graph() -> Control:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.clip_contents = true
	# Middle / left drag on empty graph space pans the view.
	_scroll.gui_input.connect(_on_scroll_gui_input)

	var cls: String = String(GameManager.player_class)
	var nodes: Array = SkillTrees.nodes_for(cls)
	var grid: Vector2 = SkillTrees.canvas_size(cls)

	var canvas := Control.new()
	# SHRINK (not expand) so the ScrollContainer scrolls the fixed-size canvas
	# instead of stretching it to fit — this is what makes panning work.
	canvas.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	canvas.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	canvas.custom_minimum_size = Vector2(grid.x * CELL_W + 2 * MARGIN, grid.y * CELL_H + 2 * MARGIN)
	_scroll.add_child(canvas)

	var node_by_id: Dictionary = {}
	for n in nodes:
		node_by_id[String(n["id"])] = n

	# Слой рёбер под кнопками.
	var edge_layer := _EdgeLayer.new()
	edge_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edge_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(edge_layer)
	var edges: Array = []
	for n in nodes:
		var child_c: Vector2 = _node_center(n)
		for pid in SkillTrees.node_parents(n):
			if not node_by_id.has(String(pid)):
				continue
			var parent_on: bool = int(GameManager.tree_nodes.get(String(pid), 0)) > 0
			edges.append(
				{"from": _node_center(node_by_id[String(pid)]), "to": child_c, "on": parent_on}
			)
	edge_layer.edges = edges

	# Круглые кнопки узлов поверх рёбер.
	for n in nodes:
		var btn := _graph_node_button(n)
		btn.position = Vector2(
			int(n["col"]) * CELL_W + MARGIN + (CELL_W - NODE) * 0.5, int(n["row"]) * CELL_H + MARGIN
		)
		canvas.add_child(btn)
	return _scroll


func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging and _scroll != null:
		var mm := event as InputEventMouseMotion
		_scroll.scroll_horizontal -= int(mm.relative.x)
		_scroll.scroll_vertical -= int(mm.relative.y)


func _node_center(node: Dictionary) -> Vector2:
	return Vector2(
		int(node["col"]) * CELL_W + MARGIN + CELL_W * 0.5,
		int(node["row"]) * CELL_H + MARGIN + NODE * 0.5
	)


func _node_color(node: Dictionary, rank: int) -> Color:
	# Choice nodes (mutually-exclusive forks) get a distinct gold tint.
	if String(node.get("exclusive", "")) != "":
		return VARIANT_ACTIVE_COLOR if rank > 0 else CHOICE_COLOR
	match String(node.get("kind", "")):
		"skill":
			return SKILL_COLOR
		"variant":
			return VARIANT_ACTIVE_COLOR if rank > 0 else VARIANT_COLOR
		"perk":
			return PERK_COLOR
		_:
			if String(node.get("on_hit", "")) != "":
				return STATUS_COLOR
			return SHARED_COLOR if (node.get("targets", []) as Array).size() > 1 else PASSIVE_COLOR


# Скруглённый стиль (большой радиус → круг) с цветной рамкой по типу узла.
func _circle_style(border: Color, dim: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.16, 0.95) if not dim else Color(0.1, 0.1, 0.12, 0.7)
	sb.set_corner_radius_all(NODE / 2)
	sb.border_color = border if not dim else border.darkened(0.45)
	sb.set_border_width_all(3)
	return sb


func _graph_node_button(node: Dictionary) -> Button:
	var node_id: String = String(node["id"])
	var kind: String = String(node.get("kind", ""))
	var rank: int = int(GameManager.tree_nodes.get(node_id, 0))
	var reason: String = GameManager.node_block_reason(node_id)
	var locked: bool = reason != "" and not (kind == "variant" and rank > 0)
	var color: Color = _node_color(node, rank)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(NODE, NODE)
	btn.size = Vector2(NODE, NODE)
	btn.icon = _node_icon(node)
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", NODE - 18)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(st, _circle_style(color, locked and st == "disabled"))
	btn.disabled = locked
	btn.pressed.connect(_on_node_pressed.bind(node_id))
	btn.mouse_entered.connect(
		_on_tip.bind(SkillTrees.node_display_name(node), SkillTrees.node_display_desc(node), reason)
	)
	btn.mouse_exited.connect(_on_tip_exit)

	# Бейдж ранга в правом-нижнем углу.
	var badge_text: String = ""
	match kind:
		"skill":
			badge_text = "Ур.%d" % rank if rank > 0 else ""
		"variant":
			badge_text = "✓" if rank > 0 else "2"
		"perk":
			badge_text = "✓" if rank > 0 else ""
		_:
			badge_text = str(rank) if rank > 0 else ""
	if badge_text != "":
		var badge := Label.new()
		badge.text = badge_text
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_color_override("font_color", Color(1, 1, 0.85))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		badge.add_theme_constant_override("outline_size", 4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(NODE - 26, NODE - 24)
		btn.add_child(badge)
	return btn


# Узел статов/ult в колонке — простая строка-кнопка (не на холсте).
func _list_node_button(node: Dictionary) -> Button:
	var node_id: String = String(node["id"])
	var rank: int = int(GameManager.tree_nodes.get(node_id, 0))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.clip_text = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", ULT_COLOR)
	btn.text = "%s   [%d]" % [String(node.get("name", node_id)), rank]
	var reason: String = GameManager.node_block_reason(node_id)
	btn.disabled = reason != ""
	btn.pressed.connect(_on_node_pressed.bind(node_id))
	btn.mouse_entered.connect(
		_on_tip.bind(String(node.get("name", node_id)), String(node.get("desc", "")), reason)
	)
	btn.mouse_exited.connect(_on_tip_exit)
	return btn


func _node_icon(node: Dictionary) -> Texture2D:
	var tex: Texture2D = null
	match String(node["kind"]):
		"skill":
			var d: SkillDefinition = SkillCatalog.get_def(String(node["skill_id"]))
			tex = d.get_icon() if d != null else null
		"variant":
			var sid: String = String(
				SkillCatalog.transform_overrides().get(String(node["transform"]), "")
			)
			var dv: SkillDefinition = SkillCatalog.get_def(sid) if sid != "" else null
			tex = (
				dv.get_icon()
				if dv != null
				else _load_icon("res://assets/sprites/items/crystal_blue.png")
			)
		"passive":
			var t: Array = node.get("targets", [])
			tex = RewardData.slot_icon(int(t[0]["slot"])) if not t.is_empty() else null
			if tex == null:
				tex = _load_icon("res://assets/sprites/items/crystal_blue.png")
		"perk":
			tex = _load_icon("res://assets/sprites/items/rune_circle.png")
	return tex


func _load_icon(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


# ── Общие виджеты ────────────────────────────────────────────────────────────
func _header(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", color)
	return l


func _on_node_pressed(node_id: String) -> void:
	if GameManager.spend_node(node_id):
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_ui_menu_click.mp3", -8.0)


func _on_tip(title: String, desc: String, reason: String) -> void:
	if TooltipManager == null:
		return
	TooltipManager.show_tooltip(title, "common", desc, reason)


func _on_tip_exit() -> void:
	if TooltipManager:
		TooltipManager.hide_tooltip()


func _refresh_footer() -> void:
	if GameManager == null or _points_label == null:
		return
	_points_label.text = "Очки: %d" % GameManager.talent_points


func _close() -> void:
	if TooltipManager:
		TooltipManager.hide_tooltip()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_button_click.mp3", -8.0)
	closed.emit()
	queue_free()
