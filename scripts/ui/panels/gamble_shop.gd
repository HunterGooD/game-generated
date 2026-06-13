extends CanvasLayer

## Fortune Teller gamble shop (hub overlay, code-built like merchant_panel / meta_tree_ui).
## Spends MIRROR SHARDS (the persistent meta currency from mini-bosses/bosses) on random
## META GEMS for the mirror tree's sockets. Pick 1–10 stones and pull the lever:
##   • 1 stone   → instant reveal toast.
##   • 2+ stones → the roulette window: up to 10 "?" cells (5 top / 5 bottom). Click each
##     to flip it, or press "Открыть все" to auto-flip the rest in order. Hovering a
##     flipped cell shows the gem's description. Gems are rolled & banked BEFORE the
##     reveal — the window is pure theatre, closing early loses nothing.
##
## Purely local meta state (MetaProgress) — nothing here networks or pauses the tree
## (the hub is shared in co-op).

signal closed

const PRICE_PER_GEM: int = 25
const MAX_BUY: int = 10

var _count: int = 1
var _shards_label: Label = null
var _count_label: Label = null
var _price_label: Label = null
var _buy_btn: Button = null
var _shop_box: VBoxContainer = null

# Reveal state.
var _reveal_root: Control = null
var _reveal_ids: Array = []  # rolled gem ids, in cell order
var _reveal_btns: Array = []  # Button per cell
var _revealed: Array = []  # bool per cell
var _reveal_done_btn: Button = null
var _auto_running: bool = false


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if MetaProgress:
		MetaProgress.shards_changed.connect(_on_shards_changed)


func _build() -> void:
	var dim := UIBuilder.dim_overlay(Color(0.03, 0.02, 0.05, 0.88))
	add_child(dim)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.07, 0.14, 0.97)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.62, 0.4, 0.78)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -310
	panel.offset_right = 310
	panel.offset_top = -250
	panel.offset_bottom = 250
	dim.add_child(panel)

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 26)
	panel.add_child(margin)

	_shop_box = VBoxContainer.new()
	_shop_box.add_theme_constant_override("separation", 14)
	margin.add_child(_shop_box)

	_shop_box.add_child(_label("ГАДАЛКА", 30, Color(0.9, 0.6, 1.0)))
	_shop_box.add_child(
		_label("«Зеркало жаждет камней… а камни жаждут осколков.»", 14, Color(0.75, 0.68, 0.85))
	)

	_shards_label = _label("", 20, Color(0.72, 0.86, 1.0))
	_shop_box.add_child(_shards_label)

	_shop_box.add_child(_label("Сколько камней испытать? (1–%d)" % MAX_BUY, 16, Color(0.9, 0.85, 0.95)))

	# − [n] + selector row.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_shop_box.add_child(row)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(56, 56)
	minus.add_theme_font_size_override("font_size", 26)
	minus.pressed.connect(_on_count.bind(-1))
	row.add_child(minus)
	_count_label = _label("1", 34, Color(1.0, 0.9, 0.6))
	_count_label.custom_minimum_size = Vector2(70, 0)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_count_label)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(56, 56)
	plus.add_theme_font_size_override("font_size", 26)
	plus.pressed.connect(_on_count.bind(1))
	row.add_child(plus)

	_price_label = _label("", 18, Color(1.0, 0.85, 0.4))
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_box.add_child(_price_label)

	_buy_btn = Button.new()
	_buy_btn.text = "ИСПЫТАТЬ СУДЬБУ"
	_buy_btn.custom_minimum_size = Vector2(280, 58)
	_buy_btn.add_theme_font_size_override("font_size", 20)
	_buy_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_buy_btn.pressed.connect(_on_buy)
	_shop_box.add_child(_buy_btn)

	var hint := _label(
		"Камни вставляются в гнёзда (◇) мета-древа у Зеркала.\nРедкость случайна — судьба слепа, но щедра.",
		13,
		Color(0.68, 0.64, 0.75)
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_box.add_child(hint)

	var leave := Button.new()
	leave.text = "Уйти"
	leave.custom_minimum_size = Vector2(160, 44)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(_close)
	_shop_box.add_child(leave)

	_refresh()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 3)
	return l


func _refresh() -> void:
	var shards: int = MetaProgress.get_shards() if MetaProgress else 0
	_shards_label.text = "Осколки зеркала: %d" % shards
	_count_label.text = str(_count)
	var price: int = PRICE_PER_GEM * _count
	_price_label.text = "Цена: %d осколков" % price
	_buy_btn.disabled = shards < price
	_buy_btn.modulate = Color(0.55, 0.55, 0.55) if _buy_btn.disabled else Color(1, 1, 1)


func _on_shards_changed(_total: int) -> void:
	_refresh()


func _on_count(delta: int) -> void:
	_count = clampi(_count + delta, 1, MAX_BUY)
	_refresh()


# ─────────────────────────────────────────────────────────────────────────────
# Purchase → roll everything up front → reveal window (the roll already happened;
# the cells are theatre, so an early Esc can't eat a paid-for gem).
func _on_buy() -> void:
	if MetaProgress == null or not MetaProgress.spend_shards(PRICE_PER_GEM * _count):
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_fail.mp3", -6.0)
		return
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_button_click.mp3", -6.0)
	var ids: Array = []
	for i in _count:
		var gid: String = MetaGems.roll()
		MetaProgress.add_gem(gid)
		ids.append(gid)
	if ids.size() == 1:
		# Single stone: skip the window, just announce it.
		var gid: String = String(ids[0])
		if GameManager:
			GameManager.notice.emit(
				"Выпал камень: %s (%s)" % [MetaGems.display_name(gid), MetaGems.rarity_display(MetaGems.rarity_of(gid))],
				MetaGems.rarity_color(MetaGems.rarity_of(gid))
			)
		_refresh()
		return
	_open_reveal(ids)


# ─────────────────────────────────────────────────────────────────────────────
# Reveal window — up to 10 cells, 5 top + 5 bottom, each a "?" until flipped.
func _open_reveal(ids: Array) -> void:
	_reveal_ids = ids
	_reveal_btns = []
	_revealed = []
	_auto_running = false

	_reveal_root = ColorRect.new()
	(_reveal_root as ColorRect).color = Color(0.02, 0.01, 0.04, 0.92)
	_reveal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reveal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_reveal_root)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	_reveal_root.add_child(vb)

	vb.add_child(_label("СУДЬБА БРОШЕНА", 28, Color(0.9, 0.6, 1.0)))
	var sub := _label("Кликните по «?», чтобы открыть камень — или откройте все разом.", 15, Color(0.8, 0.75, 0.88))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	# 5 cells per row: first five on top, the rest below.
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(grid)
	for i in ids.size():
		var cell := Button.new()
		cell.text = "?"
		cell.custom_minimum_size = Vector2(96, 96)
		cell.add_theme_font_size_override("font_size", 38)
		cell.tooltip_text = "Неизвестный камень"
		_style_cell(cell, Color(0.35, 0.3, 0.45), false)
		cell.pressed.connect(_on_cell.bind(i))
		grid.add_child(cell)
		_reveal_btns.append(cell)
		_revealed.append(false)

	_reveal_done_btn = Button.new()
	_reveal_done_btn.text = "Открыть все"
	_reveal_done_btn.custom_minimum_size = Vector2(220, 50)
	_reveal_done_btn.add_theme_font_size_override("font_size", 18)
	_reveal_done_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reveal_done_btn.pressed.connect(_on_reveal_action)
	vb.add_child(_reveal_done_btn)


func _style_cell(btn: Button, tint: Color, revealed: bool) -> void:
	for sname in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = tint.darkened(0.55) if not revealed else tint.darkened(0.35)
		if sname == "hover":
			sb.bg_color = sb.bg_color.lightened(0.12)
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(3 if revealed else 2)
		sb.border_color = tint if revealed else tint.lightened(0.2)
		btn.add_theme_stylebox_override(sname, sb)
	btn.add_theme_color_override("font_color", tint.lightened(0.25) if revealed else Color(0.85, 0.8, 0.95))


func _on_cell(i: int) -> void:
	if i < 0 or i >= _revealed.size() or _revealed[i]:
		return
	_flip(i)
	_check_all_revealed()


func _flip(i: int) -> void:
	_revealed[i] = true
	var gid: String = String(_reveal_ids[i])
	var btn: Button = _reveal_btns[i]
	var rarity: String = MetaGems.rarity_of(gid)
	var col: Color = MetaGems.rarity_color(rarity)
	btn.text = "◆"
	btn.tooltip_text = MetaGems.describe(gid)
	_style_cell(btn, col, true)
	# Little pop so flips feel tactile.
	btn.pivot_offset = btn.size * 0.5
	btn.scale = Vector2(0.6, 0.6)
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_button_click.mp3", -10.0)


# "Открыть все" → fast sequential auto-flip; once everything is open it turns into "Забрать".
func _on_reveal_action() -> void:
	if _all_revealed():
		_close_reveal()
		return
	if _auto_running:
		return
	_auto_running = true
	_reveal_done_btn.disabled = true
	_auto_flip_next()


func _auto_flip_next() -> void:
	for i in _revealed.size():
		if not _revealed[i]:
			_flip(i)
			break
	if _all_revealed():
		_auto_running = false
		_check_all_revealed()
		return
	var t := get_tree().create_timer(0.14)
	t.timeout.connect(_auto_flip_next)


func _all_revealed() -> bool:
	for r in _revealed:
		if not r:
			return false
	return true


func _check_all_revealed() -> void:
	if _all_revealed() and _reveal_done_btn != null:
		_reveal_done_btn.text = "Забрать"
		_reveal_done_btn.disabled = false


func _close_reveal() -> void:
	if _reveal_root != null and is_instance_valid(_reveal_root):
		_reveal_root.queue_free()
	_reveal_root = null
	_reveal_btns = []
	_reveal_ids = []
	_revealed = []
	_refresh()


# ─────────────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Esc inside the reveal closes just the window (gems are already banked).
		if _reveal_root != null:
			_close_reveal()
		else:
			_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
