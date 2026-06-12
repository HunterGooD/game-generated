class_name MetaTreeUI
extends CanvasLayer

## Meta-mirror tree overlay (Phase B). Code-built (same pattern as hero_select /
## run_map_ui — no .tscn node_paths). A pannable, zoomable PoE-style passive graph: nodes
## are buttons, edges are drawn behind them. Opens on the active class's tab; class tabs
## switch which tree you view/spend on (each class has its own meta level + points).
##
## Allocating costs a point and needs a neighbour already taken (start is free). Respec is
## a free full reset. Bonuses don't apply live in the hub — they fold into GameManager at
## the next run start (reset_run). Sockets render as empty slots; gems land in Phase E.
##
## Co-op note: this is purely local UI over the local MetaProgress save; nothing networked.

const CLASS_ORDER: Array = ["barbarian", "rogue", "mage", "druid", "necromancer", "hexen", "stormcaller"]
const CLASS_COLORS: Dictionary = {
	"barbarian": Color(0.86, 0.42, 0.30),
	"rogue": Color(0.55, 0.80, 0.45),
	"mage": Color(0.45, 0.62, 1.0),
	"druid": Color(0.55, 0.85, 0.55),
	"necromancer": Color(0.65, 0.55, 0.85),
	"hexen": Color(0.85, 0.45, 0.78),
	"stormcaller": Color(0.45, 0.85, 0.95),
}
# stat key -> [label, is_percent]
const STAT_LABELS: Dictionary = {
	"max_hp": ["Макс. здоровье", false],
	"max_mana": ["Макс. мана", false],
	"damage": ["Урон", false],
	"move_speed": ["Скорость бега", false],
	"crit_chance": ["Шанс крита", true],
	"crit_damage": ["Крит. урон", true],
	"strength": ["Сила", false],
	"dexterity": ["Ловкость", false],
	"intelligence": ["Интеллект", false],
}
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 2.0

signal closed

var _view_class: String = "barbarian"
var _zoom: float = 1.0
var _dragging: bool = false
var _clip: Control = null
var _world: Control = null
var _edges: Node = null  # _EdgeCanvas
var _header: Label = null
var _node_btns: Dictionary = {}  # node id -> Button
var _node_pos: Dictionary = {}  # node id -> Vector2 (centre, world space)
var _tab_btns: Dictionary = {}  # class id -> Button
var _empty_label: Label = null  # shown for classes whose tree isn't built yet


# Edge layer — its own Control so _draw renders the links behind the node buttons.
class _EdgeCanvas:
	extends Control
	var segments: Array = []  # [{from, to, color, width}]

	func _draw() -> void:
		for s in segments:
			draw_line(s.from, s.to, s.color, s.width, true)

	func set_segments(seg: Array) -> void:
		segments = seg
		queue_redraw()


func _ready() -> void:
	layer = 33
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager:
		var c: String = String(GameManager.player_class)
		_view_class = c if c != "" else String(GameManager.last_class)
	if not CLASS_ORDER.has(_view_class):
		_view_class = "barbarian"
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Graph viewport (clips the pannable world) — sits behind the chrome panels.
	_clip = Control.new()
	_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_STOP
	_clip.gui_input.connect(_on_graph_input)
	dim.add_child(_clip)

	_world = Control.new()
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE  # empty space falls through to _clip (pan)
	_clip.add_child(_world)

	_edges = _EdgeCanvas.new()
	_edges.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(_edges)

	_build_chrome(dim)
	_rebuild_graph()


# ── chrome (top bar / tabs / footer) ──────────────────────────────────────────
func _build_chrome(dim: Control) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 92
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.10, 0.96)
	sb.set_border_width_all(0)
	sb.border_width_bottom = 2
	sb.border_color = Color(0.3, 0.3, 0.4)
	bar.add_theme_stylebox_override("panel", sb)
	dim.add_child(bar)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	bar.add_child(vb)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 24)
	_header.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	vb.add_child(_header)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	vb.add_child(tabs)
	for cid in CLASS_ORDER:
		var data: Dictionary = GameManager.get_class_data(cid) if GameManager else {}
		var t := Button.new()
		t.custom_minimum_size = Vector2(118, 30)
		t.text = "%s  (%d)" % [String(data.get("display", cid.capitalize())), MetaProgress.get_meta_level(cid)]
		t.pressed.connect(_on_tab.bind(cid))
		tabs.add_child(t)
		_tab_btns[cid] = t

	# Footer: respec + close + hint.
	var respec := Button.new()
	respec.text = "Сброс (бесплатно)"
	respec.custom_minimum_size = Vector2(150, 36)
	respec.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	respec.position = Vector2(20, -52)
	respec.pressed.connect(_on_respec)
	dim.add_child(respec)

	var close := Button.new()
	close.text = "Назад в хаб"
	close.custom_minimum_size = Vector2(150, 36)
	close.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	close.position = Vector2(-170, -52)
	close.pressed.connect(_close)
	dim.add_child(close)

	var hint := Label.new()
	hint.text = "Перетаскивание — обзор · колесо — масштаб · клик по узлу — вложить очко · Esc — закрыть"
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(0, -22)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
	dim.add_child(hint)


# ── graph build / refresh ─────────────────────────────────────────────────────
func _rebuild_graph() -> void:
	for id in _node_btns:
		var b: Button = _node_btns[id]
		if is_instance_valid(b):
			b.queue_free()
	_node_btns.clear()
	_node_pos.clear()
	if _empty_label != null and is_instance_valid(_empty_label):
		_empty_label.queue_free()
	_empty_label = null

	# Centre the world so the tree's start node sits mid-screen at zoom 1.
	_zoom = 1.0
	_world.scale = Vector2.ONE
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_world.position = Vector2(vp.x * 0.5, vp.y * 0.5 + 30.0)

	var tree: Dictionary = MetaTrees.tree_for(_view_class)
	if tree.is_empty():
		_edges.set_segments([])
		_empty_label = Label.new()
		_empty_label.text = "Дерево для этого класса появится позже."
		_empty_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_empty_label.add_theme_font_size_override("font_size", 22)
		_empty_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
		_clip.add_child(_empty_label)
		_refresh()
		return

	for id in tree:
		var nd: Dictionary = tree[id]
		var pos: Vector2 = nd.get("pos", Vector2.ZERO)
		_node_pos[id] = pos
		var b := _make_node_button(String(id), nd)
		_world.add_child(b)
		_node_btns[id] = b
	_refresh()


func _make_node_button(node_id: String, nd: Dictionary) -> Button:
	var b := Button.new()
	var sz: Vector2 = _node_size(String(nd.get("type", "stat")))
	b.size = sz
	b.position = _node_pos[node_id] - sz * 0.5
	b.text = _node_glyph(nd)
	b.add_theme_font_size_override("font_size", 18)
	b.tooltip_text = _node_desc(node_id, nd)
	b.pressed.connect(_on_node.bind(node_id))
	return b


func _refresh() -> void:
	# Header + tab labels.
	var data: Dictionary = GameManager.get_class_data(_view_class) if GameManager else {}
	var disp: String = String(data.get("display", _view_class.capitalize()))
	_header.text = "Зеркало — %s · Ур. %d · Очки: %d/%d" % [
		disp,
		MetaProgress.get_meta_level(_view_class),
		MetaProgress.points_available(_view_class),
		MetaProgress.points_total(_view_class),
	]
	for cid in _tab_btns:
		var t: Button = _tab_btns[cid]
		var col: Color = CLASS_COLORS.get(cid, Color(0.7, 0.7, 0.8))
		var active: bool = cid == _view_class
		_style_button(t, col.darkened(0.1) if active else col.darkened(0.45), active)

	# Node states.
	for id in _node_btns:
		var b: Button = _node_btns[id]
		var nd: Dictionary = MetaTrees.node_data(_view_class, String(id))
		var ntype: String = String(nd.get("type", "stat"))
		var col: Color = _node_color(ntype)
		var allocated: bool = ntype == "start" or MetaProgress.is_allocated(_view_class, String(id))
		var can: bool = MetaProgress.can_allocate(_view_class, String(id))
		var tint: Color = col
		if allocated:
			tint = col.lightened(0.15)
		elif can:
			tint = col.darkened(0.15)
		else:
			tint = col.darkened(0.6)
		_style_node(b, tint, allocated, can)
		# Repeatable notables show their rank count and a live tooltip (the infinite sink).
		if MetaProgress.is_repeatable(_view_class, String(id)):
			var rank: int = MetaProgress.node_rank(_view_class, String(id))
			b.text = _node_glyph(nd) + ("  ×%d" % rank if rank > 0 else "")
			b.tooltip_text = _node_desc(String(id), nd)

	_redraw_edges()


func _redraw_edges() -> void:
	if _edges == null:
		return
	var tree: Dictionary = MetaTrees.tree_for(_view_class)
	var segs: Array = []
	var seen: Dictionary = {}
	for id in tree:
		var nd: Dictionary = tree[id]
		var from: Vector2 = _node_pos.get(id, Vector2.ZERO)
		var a_alloc: bool = String(nd.get("type", "")) == "start" or MetaProgress.is_allocated(_view_class, String(id))
		var links: Array = nd.get("links", [])
		for l in links:
			var lid: String = String(l)
			var key: String = lid + "|" + String(id) if lid < String(id) else String(id) + "|" + lid
			if seen.has(key):
				continue
			seen[key] = true
			if not _node_pos.has(lid):
				continue
			var to: Vector2 = _node_pos[lid]
			var l_nd: Dictionary = tree.get(lid, {})
			var b_alloc: bool = String(l_nd.get("type", "")) == "start" or MetaProgress.is_allocated(_view_class, lid)
			var live: bool = a_alloc and b_alloc
			var col: Color = Color(1.0, 0.86, 0.45, 0.9) if live else Color(0.4, 0.4, 0.5, 0.45)
			segs.append({"from": from, "to": to, "color": col, "width": 4.0 if live else 2.0})
	_edges.set_segments(segs)


# ── interaction ───────────────────────────────────────────────────────────────
func _on_node(node_id: String) -> void:
	if MetaProgress.allocate(_view_class, node_id):
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_button_click.mp3", -6.0)
		_refresh()
	else:
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_button_click.mp3", -16.0)


func _on_tab(class_id: String) -> void:
	if class_id == _view_class:
		return
	_view_class = class_id
	_rebuild_graph()


func _on_respec() -> void:
	MetaProgress.respec(_view_class)
	# Refresh the tab label count is unaffected, but node + header states change.
	_refresh()


func _on_graph_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		_world.position += (event as InputEventMouseMotion).relative


func _zoom_at(focus: Vector2, factor: float) -> void:
	var old_z: float = _zoom
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(_zoom, old_z):
		return
	# Keep the point under the cursor stationary while scaling.
	_world.position = focus - (focus - _world.position) * (_zoom / old_z)
	_world.scale = Vector2(_zoom, _zoom)


# ── styling helpers ───────────────────────────────────────────────────────────
func _node_size(ntype: String) -> Vector2:
	match ntype:
		"start":
			return Vector2(56, 56)
		"notable":
			return Vector2(62, 62)
		"socket":
			return Vector2(50, 50)
		_:
			return Vector2(44, 44)


func _node_color(ntype: String) -> Color:
	match ntype:
		"start":
			return Color(0.95, 0.82, 0.40)
		"notable":
			return CLASS_COLORS.get(_view_class, Color(0.7, 0.7, 0.8)).lightened(0.1)
		"socket":
			return Color(0.55, 0.85, 0.95)
		_:
			return CLASS_COLORS.get(_view_class, Color(0.7, 0.7, 0.8))


func _node_glyph(nd: Dictionary) -> String:
	match String(nd.get("type", "stat")):
		"start":
			return "◆"
		"notable":
			return "★"
		"socket":
			return "◇"
		_:
			return "●"


func _style_node(b: Button, tint: Color, allocated: bool, can: bool) -> void:
	for sname in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = tint if sname != "hover" else tint.lightened(0.15)
		sb.set_corner_radius_all(int(b.size.x * 0.5))
		sb.set_border_width_all(3 if (allocated or can) else 1)
		sb.border_color = Color(1, 1, 0.75) if allocated else (tint.lightened(0.4) if can else Color(0.15, 0.15, 0.18))
		b.add_theme_stylebox_override(sname, sb)
	b.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04) if allocated else Color(0.9, 0.9, 0.95))


func _style_button(b: Button, tint: Color, bright: bool) -> void:
	for sname in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = tint if sname == "normal" else tint.lightened(0.15)
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2 if bright else 1)
		sb.border_color = Color(1, 1, 0.7) if bright else tint.lightened(0.3)
		b.add_theme_stylebox_override(sname, sb)
	b.add_theme_color_override("font_color", Color(1, 1, 1))


# ── tooltip text ──────────────────────────────────────────────────────────────
func _node_desc(node_id: String, nd: Dictionary) -> String:
	var ntype: String = String(nd.get("type", "stat"))
	var lines: Array = []
	match ntype:
		"start":
			lines.append("Старт — всегда взят (бесплатно)")
		"socket":
			lines.append("Гнездо — слот для камня (пусто)")
			lines.append("Камни появятся вместе с системой азартных игр.")
		"notable":
			lines.append("Значимый: " + node_id.capitalize().replace("_", " "))
		_:
			lines.append("Пассивка")
	var stats: Dictionary = nd.get("stats", {})
	for k in stats:
		lines.append("  " + _stat_line(String(k), stats[k]))
	# Repeatable nodes: current rank + the per-rank percent bump (the endless sink).
	if bool(nd.get("repeatable", false)):
		lines.append(
			"Повторяемый — ранг %d (кликайте, чтобы продолжать)"
			% MetaProgress.node_rank(_view_class, node_id)
		)
		var rp: Dictionary = nd.get("rank_pct", {})
		var parts: Array = []
		for k in rp:
			var meta: Array = STAT_LABELS.get(k, [String(k).capitalize(), false])
			parts.append("+%.1f%% %s" % [float(rp[k]) * 100.0, String(meta[0])])
		if not parts.is_empty():
			lines.append("  за ранг: " + ", ".join(parts))
	var effect: String = String(nd.get("effect", ""))
	if effect != "":
		lines.append("(эффект: %s)" % effect)
	return "\n".join(lines)


func _stat_line(key: String, value) -> String:
	var meta: Array = STAT_LABELS.get(key, [key.capitalize(), false])
	var label: String = String(meta[0])
	var is_pct: bool = bool(meta[1])
	if is_pct:
		return "+%d%% %s" % [int(round(float(value) * 100.0)), label]
	return "+%s %s" % [str(value), label]


# ── lifecycle ─────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
