extends CanvasLayer

# Wandering Echo merchant shop modal. Buy items by rarity OR pick an item
# from your inventory to upgrade / re-roll / add affix.

signal closed

const BTN_BLANK_STYLEBOX: String = "res://assets/ui/btn_blank.tres"
const TRADE_PANEL_SCENE: PackedScene = preload("res://scenes/ui/trade_panel.tscn")

# Built procedurally inside _build_ui() — not present in the .tscn.
var dim: ColorRect = null
var root: Control = null

var gold_label: Label = null
var selected_item: ItemInstance = null
var selected_label: Label = null
var item_grid: GridContainer = null
var affix_box: VBoxContainer = null
var upgrade_btn: Button = null
var reroll_btn: Button = null
var add_affix_btn: Button = null
var buy_btns: Dictionary = {}  # rarity → Button
var current_wave: int = 1


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_build_ui()
	_refresh()
	if InventorySystem:
		if not InventorySystem.inventory_changed.is_connected(_on_inv_changed):
			InventorySystem.inventory_changed.connect(_on_inv_changed)
	if GameManager:
		if not GameManager.gold_changed.is_connected(_on_gold_changed):
			GameManager.gold_changed.connect(_on_gold_changed)
	# Pull current wave from the spawner if any.
	var spawner := get_tree().current_scene.find_child("EnemySpawner", true, false)
	if spawner and spawner.get("current_wave") != null:
		current_wave = max(1, int(spawner.get("current_wave")))


func _on_inv_changed() -> void:
	# If selected item was removed (e.g. salvaged elsewhere), clear selection.
	if (
		selected_item != null
		and InventorySystem
		and not InventorySystem.inventory.has(selected_item)
		and InventorySystem.get_equipped(selected_item.get_slot()) != selected_item
	):
		selected_item = null
	_refresh()


func _on_gold_changed(_g: int) -> void:
	_refresh()


# ─────────────────────────────────────────────────────────────────────────────
# UI build
func _build_ui() -> void:
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Apply theme.
	if ResourceLoader.exists("res://assets/ui/theme.tres"):
		root.theme = load("res://assets/ui/theme.tres") as Theme

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DialogPanel"
	root.add_child(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -640
	panel.offset_right = 640
	panel.offset_top = -380
	panel.offset_bottom = 380

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)

	# Header row.
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := _label("THE WANDERING ECHO", 32, Color(1, 0.85, 0.5, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	gold_label = _label("Gold: 0", 22, Color(1.0, 0.85, 0.4, 1))
	head.add_child(gold_label)

	var subtitle := _label(
		"Spend your hoard before the next wave...", 14, Color(0.85, 0.75, 0.6, 1)
	)
	vb.add_child(subtitle)

	# BUY section.
	var buy_lbl := _label("BUY GEAR", 18, Color(1.0, 0.7, 0.4, 1))
	vb.add_child(buy_lbl)
	var buy_row := HBoxContainer.new()
	buy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	buy_row.add_theme_constant_override("separation", 12)
	vb.add_child(buy_row)
	for cfg in [
		[ItemDatabase.RARITY_COMMON, "Common\n40g", 40, Color(0.82, 0.82, 0.86, 1)],
		[ItemDatabase.RARITY_RARE, "Rare\n150g", 150, Color(0.45, 0.72, 1, 1)],
		[ItemDatabase.RARITY_LEGENDARY, "Legendary\n450g", 450, Color(1, 0.65, 0.18, 1)],
		[ItemDatabase.RARITY_UNIQUE, "Unique\n900g", 900, Color(1.0, 0.35, 0.25, 1)],
	]:
		var rarity: String = cfg[0]
		var btn := _make_button(cfg[1], 200, 80, 18, cfg[3])
		btn.pressed.connect(_buy_rarity.bind(rarity))
		buy_row.add_child(btn)
		buy_btns[rarity] = btn

	# UPGRADE section split.
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(split)

	# Left: inventory.
	var left_box := VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.add_theme_constant_override("separation", 6)
	split.add_child(left_box)
	var inv_title := _label("UPGRADE YOUR GEAR", 18, Color(1.0, 0.7, 0.4, 1))
	left_box.add_child(inv_title)
	var hint := _label("Click an item to select", 12, Color(0.78, 0.72, 0.55, 1))
	left_box.add_child(hint)
	item_grid = GridContainer.new()
	item_grid.columns = 6
	item_grid.add_theme_constant_override("h_separation", 6)
	item_grid.add_theme_constant_override("v_separation", 6)
	left_box.add_child(item_grid)

	# Right: selected item details.
	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.size_flags_stretch_ratio = 0.8
	right_box.add_theme_constant_override("separation", 6)
	split.add_child(right_box)
	selected_label = _label("Select an item to upgrade", 16, Color(0.95, 0.85, 0.55, 1))
	right_box.add_child(selected_label)
	affix_box = VBoxContainer.new()
	affix_box.add_theme_constant_override("separation", 2)
	right_box.add_child(affix_box)
	var upgrades_row := VBoxContainer.new()
	upgrades_row.add_theme_constant_override("separation", 8)
	right_box.add_child(upgrades_row)
	upgrade_btn = _make_button("Upgrade ilvl", 280, 56, 18)
	upgrade_btn.pressed.connect(_do_upgrade)
	upgrades_row.add_child(upgrade_btn)
	reroll_btn = _make_button("Re-roll affixes", 280, 56, 18)
	reroll_btn.pressed.connect(_do_reroll)
	upgrades_row.add_child(reroll_btn)
	add_affix_btn = _make_button("Add affix", 280, 56, 18)
	add_affix_btn.pressed.connect(_do_add_affix)
	upgrades_row.add_child(add_affix_btn)
	# Sell button — converts the selected inventory item into gold.
	var sell_btn := _make_button("Sell item", 280, 56, 18, Color(1.0, 0.8, 0.45, 1))
	sell_btn.pressed.connect(_do_sell)
	upgrades_row.add_child(sell_btn)

	# Footer — Trade button (co-op only) above Leave Shop.
	if NetManager and NetManager.is_multiplayer:
		var trade_btn := _make_button("TRADE WITH PARTY", 280, 56, 18, Color(0.95, 0.95, 0.55, 1))
		trade_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		trade_btn.pressed.connect(_open_trade)
		vb.add_child(trade_btn)

	var leave_btn := _make_button("LEAVE SHOP", 280, 60, 22, Color(0.95, 0.7, 0.4, 1))
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_btn.pressed.connect(_close)
	vb.add_child(leave_btn)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 3)
	return l


func _make_button(
	text: String, w: int, h: int, font_size: int, color: Color = Color(1.0, 0.85, 0.45, 1)
) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(w, h)
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	if ResourceLoader.exists(BTN_BLANK_STYLEBOX):
		var sb: StyleBox = load(BTN_BLANK_STYLEBOX) as StyleBox
		if sb:
			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_stylebox_override("hover", sb)
			btn.add_theme_stylebox_override("pressed", sb)
			btn.add_theme_stylebox_override("focus", sb)
			btn.add_theme_stylebox_override("disabled", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.03, 0.0, 1))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_child(lbl)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.mouse_entered.connect(func(): btn.modulate = Color(1.15, 1.15, 1.15, 1))
	btn.mouse_exited.connect(func(): btn.modulate = Color(1, 1, 1, 1))
	return btn


func _set_btn_text(btn: Button, text: String) -> void:
	if btn == null:
		return
	var children := btn.get_children()
	for c in children:
		if c is Label:
			(c as Label).text = text
			return


func _set_btn_disabled(btn: Button, dis: bool) -> void:
	if btn == null:
		return
	btn.disabled = dis
	btn.modulate = Color(0.55, 0.55, 0.55, 1) if dis else Color(1, 1, 1, 1)


# ─────────────────────────────────────────────────────────────────────────────
# Refresh
func _refresh() -> void:
	if gold_label and GameManager:
		gold_label.text = "Gold: %dg" % GameManager.gold
	# Refresh buy buttons (gray out unaffordable).
	if GameManager:
		var costs: Dictionary = {
			ItemDatabase.RARITY_COMMON: 40,
			ItemDatabase.RARITY_RARE: 150,
			ItemDatabase.RARITY_LEGENDARY: 450,
			ItemDatabase.RARITY_UNIQUE: 900,
		}
		for r in buy_btns.keys():
			_set_btn_disabled(buy_btns[r], GameManager.gold < int(costs[r]))
	# Inventory grid.
	if item_grid and InventorySystem:
		for c in item_grid.get_children():
			c.queue_free()
		for item in InventorySystem.inventory:
			if item is ItemInstance:
				item_grid.add_child(_build_inv_cell(item))
	_refresh_selected()


func _build_inv_cell(item: ItemInstance) -> Control:
	var root_cell := PanelContainer.new()
	root_cell.theme_type_variation = &"InventoryPanel"
	root_cell.custom_minimum_size = Vector2(78, 78)
	root_cell.mouse_filter = Control.MOUSE_FILTER_STOP
	var icon := TextureRect.new()
	icon.texture = item.get_icon()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(68, 68)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_cell.add_child(icon)
	var col: Color = ItemDatabase.rarity_color(item.rarity)
	root_cell.modulate = Color(col.r * 0.6 + 0.4, col.g * 0.6 + 0.4, col.b * 0.6 + 0.4, 1)
	if selected_item == item:
		root_cell.modulate = Color(1.4, 1.2, 0.6, 1)
	root_cell.gui_input.connect(_on_cell_click.bind(item))
	return root_cell


func _on_cell_click(event: InputEvent, item: ItemInstance) -> void:
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	selected_item = item
	_refresh()


func _refresh_selected() -> void:
	if selected_label == null or affix_box == null:
		return
	for c in affix_box.get_children():
		c.queue_free()
	if selected_item == null:
		selected_label.text = "Select an item to upgrade"
		_set_btn_disabled(upgrade_btn, true)
		_set_btn_disabled(reroll_btn, true)
		_set_btn_disabled(add_affix_btn, true)
		_set_btn_text(upgrade_btn, "Upgrade ilvl")
		_set_btn_text(reroll_btn, "Re-roll affixes")
		_set_btn_text(add_affix_btn, "Add affix")
		return
	var col: Color = ItemDatabase.rarity_color(selected_item.rarity)
	selected_label.text = (
		"%s  [%s, ilvl %d]"
		% [
			selected_item.get_title(),
			ItemDatabase.rarity_display(selected_item.rarity),
			selected_item.ilvl
		]
	)
	selected_label.add_theme_color_override("font_color", col)
	for line in selected_item.get_affix_lines():
		var l := Label.new()
		l.text = "  " + line
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color(0.92, 0.86, 0.58, 1))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		l.add_theme_constant_override("outline_size", 2)
		affix_box.add_child(l)
	# Cost labels + enable state.
	var u_cost: int = InventorySystem.upgrade_cost(selected_item)
	var r_cost: int = InventorySystem.reroll_cost(selected_item)
	var a_cost: int = InventorySystem.add_affix_cost(selected_item)
	if u_cost < 0:
		_set_btn_text(upgrade_btn, "Upgrade ilvl\n(uniques unavailable)")
		_set_btn_disabled(upgrade_btn, true)
	else:
		_set_btn_text(upgrade_btn, "Upgrade ilvl\n%dg" % u_cost)
		_set_btn_disabled(upgrade_btn, GameManager.gold < u_cost)
	if r_cost < 0:
		_set_btn_text(reroll_btn, "Re-roll affixes\n(uniques unavailable)")
		_set_btn_disabled(reroll_btn, true)
	else:
		_set_btn_text(reroll_btn, "Re-roll affixes\n%dg" % r_cost)
		_set_btn_disabled(reroll_btn, GameManager.gold < r_cost)
	if a_cost < 0:
		_set_btn_text(add_affix_btn, "Add affix\n(unavailable)")
		_set_btn_disabled(add_affix_btn, true)
	else:
		_set_btn_text(add_affix_btn, "Add affix\n%dg" % a_cost)
		_set_btn_disabled(add_affix_btn, GameManager.gold < a_cost)


# ─────────────────────────────────────────────────────────────────────────────
# Actions
func _buy_rarity(rarity: String) -> void:
	if InventorySystem == null:
		return
	if not InventorySystem.buy_item(rarity, current_wave):
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_fail.mp3", -6.0)
	_refresh()


func _do_upgrade() -> void:
	if selected_item == null or InventorySystem == null:
		return
	if not InventorySystem.upgrade_item(selected_item):
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_fail.mp3", -6.0)
	_refresh()


func _do_reroll() -> void:
	if selected_item == null or InventorySystem == null:
		return
	if not InventorySystem.reroll_item(selected_item):
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_fail.mp3", -6.0)
	_refresh()


func _do_add_affix() -> void:
	if selected_item == null or InventorySystem == null:
		return
	if not InventorySystem.add_affix_to(selected_item):
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_fail.mp3", -6.0)
	_refresh()


func _do_sell() -> void:
	if selected_item == null or InventorySystem == null:
		return
	if not InventorySystem.sell_item(selected_item):
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_fail.mp3", -6.0)
	else:
		selected_item = null
	_refresh()


func _open_trade() -> void:
	# Spawn the trade overlay on top of the merchant panel. We don't close
	# the merchant — the user can pop back into shopping after gifting.
	var trade := TRADE_PANEL_SCENE.instantiate()
	get_tree().current_scene.add_child(trade)


func _close() -> void:
	get_tree().paused = false
	emit_signal("closed")
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("pause")
		or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE)
	):
		_close()
		get_viewport().set_input_as_handled()
