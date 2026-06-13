extends CanvasLayer

# Co-op trade window. Lets the local player gift items from their inventory
# to a connected teammate during a merchant break. One-way (gift) for now —
# the recipient gets the item via NetSync; the sender's copy is removed
# locally as soon as the gift is broadcast (relay is reliable).

signal closed

var selected_item: ItemInstance = null
var recipient_pid: int = -1
var item_grid: GridContainer = null
var recipient_label: Label = null
var send_btn: Button = null
var selected_label: Label = null

# Built procedurally.
var dim: ColorRect = null
var root: Control = null


func _ready() -> void:
	layer = 75
	process_mode = Node.PROCESS_MODE_ALWAYS
	# In coop we don't want to pause the world during a trade — combat may be
	# happening on the other player's screen.
	_build_ui()
	_pick_default_recipient()
	_refresh()
	if InventorySystem and not InventorySystem.inventory_changed.is_connected(_on_inv_changed):
		InventorySystem.inventory_changed.connect(_on_inv_changed)


func _on_inv_changed() -> void:
	# If the selected item was just removed (gifted), clear and refresh.
	if (
		selected_item != null
		and InventorySystem
		and not InventorySystem.inventory.has(selected_item)
	):
		selected_item = null
	_refresh()


func _build_ui() -> void:
	dim = UIBuilder.dim_overlay(Color(0, 0, 0, 0.78))
	add_child(dim)

	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InventoryPanel"
	panel.custom_minimum_size = Vector2(900, 640)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -450
	panel.offset_top = -320
	panel.offset_right = 450
	panel.offset_bottom = 320

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)

	var title := _label("ОБМЕН В ОТРЯДЕ", 30, Color(1.0, 0.85, 0.45, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := _label(
		"Выберите предмет из инвентаря, укажите товарища и отправьте.",
		14,
		Color(0.85, 0.75, 0.55, 1)
	)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	# Recipient row.
	var recip_row := HBoxContainer.new()
	recip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	recip_row.add_theme_constant_override("separation", 14)
	vb.add_child(recip_row)
	var send_to_lbl := _label("Кому:", 18, Color(0.95, 0.85, 0.55, 1))
	recip_row.add_child(send_to_lbl)
	recipient_label = _label("(нет товарища)", 18, Color(1.0, 0.85, 0.4, 1))
	recip_row.add_child(recipient_label)
	var cycle_btn := _make_button("Следующий товарищ", 220, 44, 14)
	cycle_btn.pressed.connect(_cycle_recipient)
	recip_row.add_child(cycle_btn)

	# Inventory grid.
	var inv_lbl := _label("ВАШ ИНВЕНТАРЬ", 18, Color(1.0, 0.7, 0.4, 1))
	inv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(inv_lbl)
	item_grid = GridContainer.new()
	item_grid.columns = 8
	item_grid.add_theme_constant_override("h_separation", 6)
	item_grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(item_grid)

	selected_label = _label("Выберите предмет для отправки", 16, Color(0.95, 0.85, 0.55, 1))
	selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(selected_label)

	# Buttons.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 18)
	vb.add_child(btn_row)
	send_btn = _make_button("Подарить предмет", 240, 56, 20, Color(0.65, 1.0, 0.5, 1))
	send_btn.pressed.connect(_do_gift)
	btn_row.add_child(send_btn)
	var close_btn := _make_button("Закрыть", 180, 56, 18)
	close_btn.pressed.connect(_close)
	btn_row.add_child(close_btn)


func _pick_default_recipient() -> void:
	if NetManager == null or not NetManager.is_multiplayer:
		recipient_pid = -1
		return
	# Pick the first player slot that isn't us.
	for pid in NetManager.max_players:
		if pid != NetManager.local_player_id:
			recipient_pid = pid
			return
	recipient_pid = -1


func _cycle_recipient() -> void:
	if NetManager == null or not NetManager.is_multiplayer:
		return
	var start: int = recipient_pid
	for step in NetManager.max_players:
		recipient_pid = (recipient_pid + 1) % NetManager.max_players
		if recipient_pid != NetManager.local_player_id and recipient_pid != start:
			break
	_refresh()


func _refresh() -> void:
	# Recipient label.
	if recipient_label:
		if recipient_pid < 0:
			recipient_label.text = "(нет товарища)"
		else:
			recipient_label.text = "Игрок %d" % (recipient_pid + 1)
	# Inventory grid.
	if item_grid and InventorySystem:
		for c in item_grid.get_children():
			c.queue_free()
		for item in InventorySystem.inventory:
			if item is ItemInstance:
				item_grid.add_child(_build_inv_cell(item))
	# Selected item label.
	if selected_label:
		if selected_item == null:
			selected_label.text = "Выберите предмет для отправки"
		else:
			var col: Color = ItemDatabase.rarity_color(selected_item.rarity)
			selected_label.text = (
				"%s  [%s ур. %d]"
				% [
					selected_item.get_title(),
					ItemDatabase.rarity_display(selected_item.rarity),
					selected_item.ilvl
				]
			)
			selected_label.add_theme_color_override("font_color", col)
	# Send button state.
	if send_btn:
		send_btn.disabled = (selected_item == null) or (recipient_pid < 0)


func _build_inv_cell(item: ItemInstance) -> Control:
	var cell := PanelContainer.new()
	cell.theme_type_variation = &"InventoryPanel"
	cell.custom_minimum_size = Vector2(72, 72)
	cell.tooltip_text = (
		"%s [%s, ilvl %d]" % [item.get_title(), ItemDatabase.rarity_display(item.rarity), item.ilvl]
	)
	# Tint by rarity.
	var col: Color = ItemDatabase.rarity_color(item.rarity)
	cell.modulate = Color(col.r * 0.5 + 0.5, col.g * 0.5 + 0.5, col.b * 0.5 + 0.5, 1)
	# Highlight if selected.
	if item == selected_item:
		cell.modulate = Color(col.r * 0.8 + 0.6, col.g * 0.8 + 0.6, col.b * 0.8 + 0.6, 1)
	var icon := TextureRect.new()
	icon.texture = item.get_icon()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(64, 64)
	cell.add_child(icon)
	var btn := Button.new()
	btn.flat = true
	btn.text = ""
	btn.custom_minimum_size = Vector2(64, 64)
	btn.pressed.connect(_on_pick.bind(item))
	icon.add_child(btn)
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return cell


func _on_pick(item: ItemInstance) -> void:
	selected_item = item
	_refresh()


func _do_gift() -> void:
	if selected_item == null or recipient_pid < 0 or InventorySystem == null:
		return
	# Refuse to gift equipped items.
	for slot in InventorySystem.equipment.keys():
		if InventorySystem.equipment.get(slot, null) == selected_item:
			if AudioManager:
				AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_fail.mp3", -8.0)
			return
	var ns := _find_net_sync()
	if ns == null or not ns.has_method("broadcast_item_gift"):
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_fail.mp3", -8.0)
		return
	var ok: bool = ns.call("broadcast_item_gift", recipient_pid, selected_item)
	if not ok:
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_fail.mp3", -8.0)
		return
	# Optimistically remove the item from our inventory on send.
	InventorySystem.inventory.erase(selected_item)
	InventorySystem.inventory_changed.emit()
	selected_item = null
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_purchase.mp3", -8.0)
	_refresh()


func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("NetSync")


func _close() -> void:
	emit_signal("closed")
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("pause")
		or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE)
	):
		_close()
		get_viewport().set_input_as_handled()


# ─────────────────────────────────────────────────────────────────────────────
# Tiny UI helpers (consistent with merchant_panel.gd's button shape).
func _label(t: String, sz: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", sz)
	return l


func _make_button(
	text: String, min_w: int, min_h: int, font_size: int, color: Color = Color(1.0, 0.9, 0.55, 1)
) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(min_w, min_h)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	btn.add_theme_constant_override("outline_size", 4)
	return btn
