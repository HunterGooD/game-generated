extends CanvasLayer

# Co-op trade window. Lets the local player gift items from their inventory
# to a connected teammate during a merchant break. One-way (gift) for now —
# the recipient gets the item via NetSync; the sender's copy is removed
# locally as soon as the gift is broadcast (relay is reliable).

signal closed

var selected_item: ItemInstance = null
var recipient_pid: int = -1

# Wired from trade_panel.tscn (the static frame — dim / centred panel / title /
# recipient row / inventory grid / buttons). Dynamic content (item cells, the
# recipient/selected text, send-enabled state) is still built/updated in code.
@export var item_grid: GridContainer
@export var recipient_label: Label
@export var selected_label: Label
@export var send_btn: Button
@export var cycle_btn: Button
@export var close_btn: Button


func _ready() -> void:
	# layer (75) + process_mode (ALWAYS — a trade must NOT pause the coop world,
	# combat may be live on a teammate's screen) are set on the scene root.
	cycle_btn.pressed.connect(_cycle_recipient)
	send_btn.pressed.connect(_do_gift)
	close_btn.pressed.connect(_close)
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
