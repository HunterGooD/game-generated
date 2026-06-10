class_name RunMapUI
extends CanvasLayer

## Slay-the-Spire style run-map screen. Code-built (no .tscn — same pattern as
## spec_path_choice.gd, avoiding node_path export fragility). If no run is active it first
## shows a difficulty picker; once a run exists it draws the node DAG (entry row at the
## bottom, boss on top), lets the host travel to reachable nodes, and reflects progress.
##
## Co-op: travel is host-authoritative (GameManager.run_travel_to gates clients), so a
## client's clicks no-op for now — full client-follow is a Phase-1 relay addition.

const NODE_W: float = 92.0
const NODE_H: float = 46.0
const MARGIN_X: float = 90.0
const MARGIN_Y: float = 84.0

# type -> [display letter, base colour]
const TYPE_STYLE := {
	RunMap.TYPE_DUNGEON: ["D", Color(0.55, 0.42, 0.78)],
	RunMap.TYPE_ARENA: ["A", Color(0.86, 0.42, 0.30)],
	RunMap.TYPE_MERCHANT: ["$", Color(0.92, 0.78, 0.30)],
	RunMap.TYPE_CAMPFIRE: ["C", Color(0.96, 0.62, 0.28)],
	RunMap.TYPE_ELITE: ["E", Color(0.92, 0.30, 0.82)],
	RunMap.TYPE_BOSS: ["B", Color(0.86, 0.16, 0.20)],
}

var _positions: Dictionary = {}  # node id -> Vector2 centre
var _edges: Node = null  # _EdgeCanvas
var _root: Control = null
var _banner: Label = null


# Edge layer — its own Control so _draw can render the DAG lines behind the node buttons.
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
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not GameManager.run_started.is_connected(_rebuild):
		GameManager.run_started.connect(_rebuild)
	if not GameManager.run_node_entered.is_connected(_on_node_entered):
		GameManager.run_node_entered.connect(_on_node_entered)
	if not GameManager.run_completed.is_connected(_on_completed):
		GameManager.run_completed.connect(_on_completed)
	_rebuild()


func _rebuild(_a = null) -> void:
	for c in get_children():
		c.queue_free()
	_positions.clear()
	_edges = null
	_banner = null
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(_root)

	if GameManager.run_state == null or not GameManager.run_state.is_active():
		_build_difficulty_picker()
	else:
		_build_map()
	_build_chrome()


# ── difficulty picker ─────────────────────────────────────────────────────────
func _build_difficulty_picker() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	_root.add_child(vb)
	var title := Label.new()
	title.text = "Choose Difficulty"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	vb.add_child(title)
	for tier in Difficulty.count():
		var info: Dictionary = Difficulty.get_tier(tier)
		var b := Button.new()
		b.custom_minimum_size = Vector2(320, 52)
		b.text = "%s   (enemies ×%.1f hp / ×%.1f dmg, loot +%d%%)" % [
			String(info.get("name", "?")),
			float(info.get("enemy_hp_mult", 1.0)),
			float(info.get("enemy_dmg_mult", 1.0)),
			int(round(float(info.get("loot_rarity_bonus", 0.0)) * 100.0)),
		]
		b.pressed.connect(func(): GameManager.start_run(tier))
		vb.add_child(b)


# ── map view ──────────────────────────────────────────────────────────────────
func _build_map() -> void:
	var state = GameManager.run_state
	var m = state.map
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var rows: int = m.row_count()
	var usable_h: float = vp.y - 2.0 * MARGIN_Y
	var usable_w: float = vp.x - 2.0 * MARGIN_X

	# Compute centres: row 0 at the bottom, last row (boss) at the top.
	for r in rows:
		var row_nodes: Array = m.rows[r]
		var count: int = row_nodes.size()
		var y: float = MARGIN_Y + usable_h * (1.0 - float(r) / float(maxi(rows - 1, 1)))
		for c in count:
			var node: Dictionary = row_nodes[c]
			var x: float = MARGIN_X + usable_w * ((float(c) + 0.5) / float(count))
			_positions[int(node["id"])] = Vector2(x, y)

	# Edge layer first (drawn under the buttons).
	_edges = _EdgeCanvas.new()
	_edges.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_edges)

	# Node buttons on top.
	for node in m.all_nodes():
		_root.add_child(_make_node_button(node))

	_refresh()


func _make_node_button(node: Dictionary) -> Button:
	var id: int = int(node["id"])
	var b := Button.new()
	b.name = "node_%d" % id
	b.size = Vector2(NODE_W, NODE_H)
	b.position = _positions[id] - b.size * 0.5
	b.clip_text = true
	b.pressed.connect(func(): _on_node_pressed(id))
	return b


# Repaint node states (reachable / current / visited / locked) and the edges.
func _refresh() -> void:
	var state = GameManager.run_state
	if state == null:
		return
	var reachable: Array = state.reachable()
	for node in state.map.all_nodes():
		var id: int = int(node["id"])
		var b: Button = _root.get_node_or_null("node_%d" % id)
		if b == null:
			continue
		var style: Array = TYPE_STYLE.get(node["type"], ["?", Color(0.7, 0.7, 0.8)])
		var letter: String = style[0]
		var col: Color = style[1]
		var affix_mark: String = "*" if not (node["affixes"] as Array).is_empty() else ""
		b.text = "%s%s" % [letter, affix_mark]
		var is_current: bool = id == state.current_id
		var is_reachable: bool = id in reachable
		var is_visited: bool = state.visited.has(id)
		var tint: Color = col
		b.disabled = not is_reachable
		if is_current:
			tint = Color(0.30, 0.95, 1.0)
		elif is_visited:
			tint = col.darkened(0.45)
		elif not is_reachable:
			tint = col.darkened(0.6)
		b.add_theme_color_override("font_color", Color(1, 1, 1))
		_style_button(b, tint, is_reachable or is_current)
	_redraw_edges(reachable, state)


func _style_button(b: Button, tint: Color, bright: bool) -> void:
	for sname in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = tint if bright else tint.darkened(0.2)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(2)
		sb.border_color = tint.lightened(0.4) if bright else Color(0.1, 0.1, 0.12)
		b.add_theme_stylebox_override(sname, sb)


func _redraw_edges(reachable: Array, state) -> void:
	if _edges == null:
		return
	var segs: Array = []
	for node in state.map.all_nodes():
		var fid: int = int(node["id"])
		var from: Vector2 = _positions.get(fid, Vector2.ZERO)
		var from_current: bool = fid == state.current_id
		for nid in node["next"]:
			var to: Vector2 = _positions.get(int(nid), Vector2.ZERO)
			# Highlight edges leaving the current node onto a reachable choice.
			var live: bool = from_current and (int(nid) in reachable)
			var col: Color = Color(0.35, 0.95, 1.0, 0.9) if live else Color(0.4, 0.4, 0.5, 0.4)
			segs.append({"from": from, "to": to, "color": col, "width": 3.0 if live else 2.0})
	_edges.set_segments(segs)


# ── chrome (header / close) ───────────────────────────────────────────────────
func _build_chrome() -> void:
	var header := Label.new()
	header.position = Vector2(24, 18)
	var diff_name: String = Difficulty.name_of(GameManager.run_difficulty)
	header.text = "Run Map — %s" % diff_name
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color(0.92, 0.9, 0.78))
	_root.add_child(header)

	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(0, 52)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 20)
	_banner.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	_root.add_child(_banner)

	var close := Button.new()
	close.text = "Close"
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.position = Vector2(-104, 16)
	close.custom_minimum_size = Vector2(120, 36)
	close.text = "Back to Hub"
	close.pressed.connect(_on_close)
	_root.add_child(close)


func _on_close() -> void:
	# As a scene root, freeing ourselves would leave an empty tree — return to the hub.
	if get_parent() == get_tree().root:
		RunFlow.exit_to_hub()
	else:
		queue_free()  # overlay use (e.g. dev): just dismiss


# ── interaction ───────────────────────────────────────────────────────────────
func _on_node_pressed(id: int) -> void:
	GameManager.run_travel_to(id)  # host-auth; refresh happens via run_node_entered


func _on_node_entered(node: Dictionary) -> void:
	if _banner:
		var affixes: Array = node.get("affixes", [])
		var extra: String = "  [%s]" % ", ".join(affixes) if not affixes.is_empty() else ""
		_banner.text = "Entered: %s%s" % [String(node.get("type", "?")).capitalize(), extra]
	_refresh()


func _on_completed() -> void:
	if _banner:
		_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		_banner.text = "★ RUN COMPLETE — the uber-boss falls ★"
	_refresh()
