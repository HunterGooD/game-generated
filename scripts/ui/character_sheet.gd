extends CanvasLayer

# Character sheet — modal overlay opened via Tab key.
# Three tabs: Stats (text rows), Equipment+Inventory (paper doll + bag),
# Talents (passive modifiers + skill uniques from level-up cards).

const RARITY_COLORS := {
	"common": Color(0.85, 0.85, 0.9, 1),
	"rare": Color(0.45, 0.75, 1.0, 1),
	"legendary": Color(1.0, 0.65, 0.18, 1),
	"set": Color(0.35, 0.9, 0.35, 1),
	"unique": Color(1.0, 0.4, 0.3, 1),
}

@export var portrait: TextureRect
@export var class_name_label: Label
@export var primary_label: Label
@export var left_col: VBoxContainer
@export var stats_grid: GridContainer
@export var items_grid: GridContainer
@export var stats_title: Label
@export var items_title: Label
@export var items_empty: Label
@export var xp_bar: ProgressBar
@export var xp_label: Label
@export var level_label: Label
@export var tab_stats: Button
@export var tab_items: Button
@export var tabs_box: HBoxContainer
@export var right_col: VBoxContainer

var open: bool = false
var active_tab: String = "stats"
var tab_equipment: Button = null
var equipment_root: Control = null
var paper_doll: Control = null  # Absolute-positioned container of slot tiles.
var inventory_grid: GridContainer = null
var inventory_bg: TextureRect = null
var gold_label: Label = null
var materials_label: Label = null
var set_summary_label: Label = null
var selected_item: ItemInstance = null

# Diablo-style paper-doll layout — (x, y) in pixels inside the 340×470 paper-doll area.
const SLOT_SIZE: Vector2 = Vector2(100, 100)
const PAPER_DOLL_LAYOUT: Dictionary = {
	ItemDatabase.SLOT_HELMET: Vector2(120, 0),
	ItemDatabase.SLOT_AMULET: Vector2(235, 30),
	ItemDatabase.SLOT_RING_1: Vector2(235, 140),
	ItemDatabase.SLOT_RING_2: Vector2(235, 250),
	ItemDatabase.SLOT_GLOVES: Vector2(5, 140),
	ItemDatabase.SLOT_CHEST: Vector2(120, 120),
	ItemDatabase.SLOT_BOOTS: Vector2(120, 235),
	ItemDatabase.SLOT_WEAPON_MAIN: Vector2(5, 360),
	ItemDatabase.SLOT_WEAPON_OFF: Vector2(235, 360),
}


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if tab_stats:
		tab_stats.pressed.connect(func(): _switch_tab("stats"))
		tab_stats.text = "Stats"
	if tab_items:
		tab_items.pressed.connect(func(): _switch_tab("talents"))
		tab_items.text = "Talents"
	_build_equipment_tab()
	if InventorySystem:
		InventorySystem.equipment_changed.connect(_on_inventory_dirty)
		InventorySystem.inventory_changed.connect(_on_inventory_dirty)
	if GameManager:
		GameManager.materials_changed.connect(_on_inventory_dirty)


func _on_inventory_dirty() -> void:
	if open and active_tab == "equipment":
		_rebuild_equipment()


func _build_equipment_tab() -> void:
	# Add a 3rd tab button.
	if tabs_box == null:
		return
	tab_equipment = Button.new()
	tab_equipment.text = "Gear"
	tab_equipment.custom_minimum_size = Vector2(140, 36)
	tab_equipment.add_theme_font_size_override("font_size", 16)
	tabs_box.add_child(tab_equipment)
	tab_equipment.pressed.connect(func(): _switch_tab("equipment"))

	# Container for equipment view.
	equipment_root = Control.new()
	equipment_root.visible = false
	equipment_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(equipment_root)
	equipment_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vb := VBoxContainer.new()
	equipment_root.add_child(vb)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 10)

	# Heading + gold counter.
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 16)
	vb.add_child(head_row)
	var equip_title := Label.new()
	equip_title.text = "Equipment & Inventory"
	equip_title.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25, 1))
	equip_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	equip_title.add_theme_constant_override("outline_size", 5)
	equip_title.add_theme_font_size_override("font_size", 22)
	equip_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(equip_title)
	gold_label = Label.new()
	gold_label.text = "Gold: 0"
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1))
	gold_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	gold_label.add_theme_constant_override("outline_size", 4)
	gold_label.add_theme_font_size_override("font_size", 18)
	head_row.add_child(gold_label)
	# Crafting materials — currency-style readout next to gold.
	materials_label = Label.new()
	materials_label.text = ""
	materials_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.9, 1))
	materials_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	materials_label.add_theme_constant_override("outline_size", 4)
	materials_label.add_theme_font_size_override("font_size", 15)
	head_row.add_child(materials_label)

	# Paper doll (left) + inventory (right) row.
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(split)

	# ── LEFT: Paper-doll with absolute slot positions (Diablo-style) ──
	var doll_box := VBoxContainer.new()
	doll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doll_box.custom_minimum_size = Vector2(360, 0)
	split.add_child(doll_box)
	var doll_lbl := Label.new()
	doll_lbl.text = "Equipped"
	doll_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	doll_lbl.add_theme_color_override("font_color", Color(0.95, 0.7, 0.4, 1))
	doll_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	doll_lbl.add_theme_constant_override("outline_size", 3)
	doll_lbl.add_theme_font_size_override("font_size", 18)
	doll_box.add_child(doll_lbl)
	# Absolute-positioned slot container, sized to fit the layout (340w x 470h).
	paper_doll = Control.new()
	paper_doll.custom_minimum_size = Vector2(340, 470)
	paper_doll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	paper_doll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	doll_box.add_child(paper_doll)
	# Active set bonus summary under the doll (filled in _rebuild_equipment).
	set_summary_label = Label.new()
	set_summary_label.text = ""
	set_summary_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.45, 1))
	set_summary_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	set_summary_label.add_theme_constant_override("outline_size", 3)
	set_summary_label.add_theme_font_size_override("font_size", 13)
	doll_box.add_child(set_summary_label)
	# Backdrop behind the paper doll.
	var doll_bg := TextureRect.new()
	var bg_path: String = "res://assets/textures/backgrounds/inventory_bg_dark.webp"
	if ResourceLoader.exists(bg_path):
		doll_bg.texture = load(bg_path) as Texture2D
	doll_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	doll_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	doll_bg.modulate = Color(0.6, 0.55, 0.55, 0.9)
	doll_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper_doll.add_child(doll_bg)
	doll_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ── RIGHT: Inventory grid with backdrop ──
	var inv_box := VBoxContainer.new()
	inv_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_box.size_flags_stretch_ratio = 1.4
	split.add_child(inv_box)
	var inv_lbl := Label.new()
	inv_lbl.text = "Inventory  (click to equip / unequip)"
	inv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_lbl.add_theme_color_override("font_color", Color(0.95, 0.7, 0.4, 1))
	inv_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	inv_lbl.add_theme_constant_override("outline_size", 3)
	inv_lbl.add_theme_font_size_override("font_size", 14)
	inv_box.add_child(inv_lbl)
	# Wrap inventory in a Control with bg behind grid.
	var inv_wrap := Control.new()
	inv_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_wrap.custom_minimum_size = Vector2(0, 460)
	inv_box.add_child(inv_wrap)
	inventory_bg = TextureRect.new()
	if ResourceLoader.exists(bg_path):
		inventory_bg.texture = load(bg_path) as Texture2D
	inventory_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	inventory_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	inventory_bg.modulate = Color(0.55, 0.5, 0.5, 0.9)
	inventory_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_wrap.add_child(inventory_bg)
	inventory_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Margin so the grid breathes inside the backdrop.
	var inv_margin := MarginContainer.new()
	inv_margin.add_theme_constant_override("margin_left", 12)
	inv_margin.add_theme_constant_override("margin_right", 12)
	inv_margin.add_theme_constant_override("margin_top", 12)
	inv_margin.add_theme_constant_override("margin_bottom", 12)
	inv_wrap.add_child(inv_margin)
	inv_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inventory_grid = GridContainer.new()
	inventory_grid.columns = 6
	inventory_grid.add_theme_constant_override("h_separation", 6)
	inventory_grid.add_theme_constant_override("v_separation", 6)
	inv_margin.add_child(inventory_grid)


func toggle() -> void:
	if open:
		close()
	else:
		show_sheet()


func show_with_tab(tab: String) -> void:
	active_tab = tab
	show_sheet()


func show_sheet() -> void:
	open = true
	visible = true
	# Co-op: don't pause the shared world for one player (would freeze/desync the
	# other players). Solo pauses for convenience.
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = true
	_populate()
	_switch_tab(active_tab)


func close() -> void:
	open = false
	visible = false
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = false
	if TooltipManager:
		TooltipManager.hide_tooltip()


func _switch_tab(tab: String) -> void:
	active_tab = tab
	var show_stats: bool = tab == "stats"
	var show_equip: bool = tab == "equipment"
	var show_talents: bool = tab == "talents"
	if stats_grid:
		stats_grid.visible = show_stats
	if stats_title:
		stats_title.visible = show_stats
	if items_grid:
		items_grid.visible = show_talents
	if items_title:
		items_title.visible = show_talents
	if items_empty:
		items_empty.visible = show_talents and items_grid.get_child_count() == 0
	if equipment_root:
		equipment_root.visible = show_equip
	# Hide class portrait column on Equipment tab so inventory gets the full width.
	if left_col:
		left_col.visible = not show_equip
	if tab_stats:
		tab_stats.modulate = Color(1.2, 1.05, 0.7, 1) if show_stats else Color(0.7, 0.7, 0.75, 1)
	if tab_items:
		tab_items.modulate = Color(1.2, 1.05, 0.7, 1) if show_talents else Color(0.7, 0.7, 0.75, 1)
	if tab_equipment:
		tab_equipment.modulate = (
			Color(1.2, 1.05, 0.7, 1) if show_equip else Color(0.7, 0.7, 0.75, 1)
		)
	if show_talents:
		_rebuild_items()
	elif show_equip:
		_rebuild_equipment()


func _populate() -> void:
	if GameManager == null:
		return
	var data: Dictionary = GameManager.get_class_data()
	if portrait:
		var p_path: String = String(data.get("portrait", ""))
		if p_path != "" and ResourceLoader.exists(p_path):
			portrait.texture = load(p_path) as Texture2D
	if class_name_label:
		class_name_label.text = String(data.get("display", "Hero"))
	if primary_label:
		primary_label.text = "Primary: " + String(data.get("primary_label", ""))
	if level_label:
		level_label.text = "Level %d" % GameManager.player_level
	if xp_bar:
		xp_bar.max_value = GameManager.player_xp_to_next
		xp_bar.value = GameManager.player_xp
	if xp_label:
		xp_label.text = "%d / %d XP" % [GameManager.player_xp, GameManager.player_xp_to_next]

	# Stats rows.
	if stats_grid:
		for c in stats_grid.get_children():
			c.queue_free()
		var armor: int = 0
		var dmg_bonus_pct: float = 0.0
		var crit_ch_bonus: float = 0.0
		var crit_dm_bonus: float = 0.0
		if InventorySystem:
			armor = InventorySystem.get_total_armor()
			dmg_bonus_pct = InventorySystem.get_damage_mult_bonus() * 100.0
			crit_ch_bonus = InventorySystem.get_crit_chance_bonus()
			crit_dm_bonus = InventorySystem.get_crit_dmg_bonus()
		var rows: Array = [
			["Health", "%d / %d" % [GameManager.player_hp, GameManager.get_effective_max_hp()]],
			[
				"Mana",
				"%d / %d" % [int(GameManager.player_mana), GameManager.get_effective_max_mana()]
			],
			["Damage", "%d (+%d%%)" % [GameManager.get_effective_damage(), int(dmg_bonus_pct)]],
			["Armor", str(armor)],
			["Move Speed", "%d%%" % int(GameManager.get_effective_move_speed() / 2.2)],
			["Crit Chance", "%d%%" % int((GameManager.player_crit_chance + crit_ch_bonus) * 100.0)],
			["Crit Damage", "x%.2f" % (GameManager.player_crit_damage + crit_dm_bonus)],
			["Strength", str(GameManager.get_effective_strength())],
			["Dexterity", str(GameManager.get_effective_dexterity())],
			["Intelligence", str(GameManager.get_effective_intelligence())],
			["Gold", str(GameManager.gold)],
			["Total Gold", str(GameManager.total_gold_earned)],
			["Wave Reached", str(GameManager.highest_wave)],
			["Enemies Slain", str(GameManager.enemies_killed)],
		]
		for row in rows:
			var l := Label.new()
			l.text = String(row[0])
			l.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62, 1))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			l.add_theme_constant_override("outline_size", 3)
			l.add_theme_font_size_override("font_size", 17)
			stats_grid.add_child(l)
			var v := Label.new()
			v.text = String(row[1])
			v.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55, 1))
			v.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			v.add_theme_constant_override("outline_size", 3)
			v.add_theme_font_size_override("font_size", 17)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			stats_grid.add_child(v)


# ─────────────────────────────────────────────────────────────────────────────
# Talents tab (passive level-up rewards) — same as before, retitled.
func _rebuild_items() -> void:
	if items_grid == null:
		return
	for c in items_grid.get_children():
		c.queue_free()
	var ss := _find_skill_system()
	if ss == null:
		if items_empty:
			items_empty.visible = true
		return
	var entries: Array = []
	var modifiers_arr: Array = ss.modifiers if ss.get("modifiers") != null else []
	for slot in modifiers_arr.size():
		var mods: Dictionary = modifiers_arr[slot]
		for mod_id in mods.keys():
			var stacks: int = int(mods[mod_id])
			var meta: Dictionary = RewardData.find_modifier(String(mod_id))
			if meta.is_empty():
				continue
			(
				entries
				. append(
					{
						"kind": "modifier",
						"id": String(mod_id),
						"slot": slot,
						"stacks": stacks,
						"title": String(meta.get("title", mod_id)),
						"desc": String(meta.get("desc", "")),
						"rarity": String(meta.get("rarity", "common")),
						"stack_bonus": String(meta.get("stack_bonus", "")),
					}
				)
			)
	var transforms_arr: Array = ss.transforms if ss.get("transforms") != null else []
	for slot in transforms_arr.size():
		var transform_id: String = String(transforms_arr[slot])
		if transform_id == "":
			continue
		var meta: Dictionary = RewardData.find_unique_by_transform(transform_id)
		if meta.is_empty():
			continue
		(
			entries
			. append(
				{
					"kind": "unique",
					"id": String(meta.get("id", transform_id)),
					"slot": slot,
					"stacks": 1,
					"title": String(meta.get("title", transform_id)),
					"desc": String(meta.get("desc", "")),
					"rarity": "unique",
					"stack_bonus": "",
				}
			)
		)
	if items_empty:
		items_empty.visible = entries.is_empty()
	for e in entries:
		var tile := _build_item_tile(e)
		items_grid.add_child(tile)


func _build_item_tile(entry: Dictionary) -> Control:
	var rarity: String = String(entry.get("rarity", "common"))
	var rar_color: Color = RARITY_COLORS.get(rarity, Color.WHITE)
	var root := PanelContainer.new()
	root.theme_type_variation = &"HudPanel"
	root.custom_minimum_size = Vector2(88, 100)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.modulate = Color(
		rar_color.r * 0.85 + 0.15, rar_color.g * 0.85 + 0.15, rar_color.b * 0.85 + 0.15, 1
	)
	root.mouse_entered.connect(_on_item_hover.bind(entry))
	root.mouse_exited.connect(_on_item_exit)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(80, 92)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(inner)
	var icon := TextureRect.new()
	icon.texture = RewardData.slot_icon(int(entry.get("slot", 0)))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(72, 72)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stacks: int = int(entry.get("stacks", 1))
	if stacks > 1:
		var stack_lbl := Label.new()
		stack_lbl.text = "x%d" % stacks
		stack_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1))
		stack_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		stack_lbl.add_theme_constant_override("outline_size", 4)
		stack_lbl.add_theme_font_size_override("font_size", 18)
		stack_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack_lbl.position = Vector2(52, 50)
		inner.add_child(stack_lbl)
	if String(entry.get("kind", "")) == "unique":
		var tw := root.create_tween().set_loops()
		tw.tween_property(root, "modulate", Color(1.45, 0.55, 0.45, 1), 0.8).set_trans(
			Tween.TRANS_SINE
		)
		tw.tween_property(root, "modulate", Color(1.2, 0.4, 0.35, 1), 0.8).set_trans(
			Tween.TRANS_SINE
		)
	return root


func _on_item_hover(entry: Dictionary) -> void:
	if TooltipManager == null:
		return
	var title: String = String(entry.get("title", ""))
	var rarity: String = String(entry.get("rarity", "common"))
	var body: String = String(entry.get("desc", ""))
	var slot: int = int(entry.get("slot", 0))
	var meta: String = "Affects: %s" % RewardData.slot_name(slot)
	var stacks: int = int(entry.get("stacks", 1))
	if String(entry.get("kind", "")) == "modifier" and stacks > 1:
		meta += "    Stacks: x%d" % stacks
		var sb: String = String(entry.get("stack_bonus", ""))
		if sb != "":
			meta += "  (per stack: %s)" % sb
	elif String(entry.get("kind", "")) == "unique":
		meta = "Transforms: %s" % RewardData.slot_name(slot)
	TooltipManager.show_tooltip(title, rarity, body, meta)


func _on_item_exit() -> void:
	if TooltipManager:
		TooltipManager.hide_tooltip()


func _find_skill_system() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var players := tree.get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0].get_node_or_null("SkillSystem")


# ─────────────────────────────────────────────────────────────────────────────
# Equipment tab
func _rebuild_equipment() -> void:
	if paper_doll == null or inventory_grid == null:
		return
	# Clear paper doll slot tiles (keep the backdrop TextureRect at index 0).
	for c in paper_doll.get_children():
		if c is TextureRect:
			continue
		c.queue_free()
	for c in inventory_grid.get_children():
		c.queue_free()
	if gold_label and GameManager:
		gold_label.text = "Gold: %d" % GameManager.gold
	if materials_label and GameManager:
		var parts: Array = []
		for mid in ItemDatabase.MATERIAL_IDS:
			parts.append(
				"%s: %d" % [String(ItemDatabase.MATERIAL_DISPLAY[mid]), GameManager.get_material(mid)]
			)
		# Set stones — listed only when owned (one entry per set).
		for set_id in GameManager.set_stones:
			parts.append(
				"%s Stone: %d"
				% [
					String(ItemDatabase.find_set(String(set_id)).get("name", set_id)),
					GameManager.get_set_stones(String(set_id))
				]
			)
		materials_label.text = "   ".join(parts)
	# Worn set bonus summary under the paper doll.
	if set_summary_label and InventorySystem:
		var lines: Array = []
		for info in InventorySystem.get_active_set_bonuses():
			lines.append("%s  (%d/5)" % [String(info.get("name", "")), int(info.get("pieces", 0))])
			for b in info.get("bonuses", []):
				if bool(b.get("active", false)):
					lines.append("  ✓ %s" % String(b.get("label", "")))
		set_summary_label.text = "\n".join(lines)

	# Place each slot at its Diablo-style hand-tuned position.
	for slot_id in PAPER_DOLL_LAYOUT.keys():
		var pos: Vector2 = PAPER_DOLL_LAYOUT[slot_id]
		var tile := _build_equip_slot_tile(int(slot_id))
		tile.custom_minimum_size = SLOT_SIZE
		tile.size = SLOT_SIZE
		paper_doll.add_child(tile)
		tile.position = pos

	# Inventory: build 30 cells.
	var items: Array = InventorySystem.inventory if InventorySystem else []
	var cap: int = InventorySystem.INVENTORY_CAPACITY if InventorySystem else 30
	for i in cap:
		var item: ItemInstance = items[i] if i < items.size() and items[i] is ItemInstance else null
		var cell := _build_inventory_cell(item)
		inventory_grid.add_child(cell)


func _build_equip_slot_tile(slot: int) -> Control:
	var root := PanelContainer.new()
	root.theme_type_variation = &"InventoryPanel"
	root.custom_minimum_size = SLOT_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var item: ItemInstance = InventorySystem.get_equipped(slot) if InventorySystem else null
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(inner)
	# Slot name in tiny text top.
	var name_lbl := Label.new()
	name_lbl.text = ItemDatabase.slot_name(slot)
	name_lbl.add_theme_color_override("font_color", Color(0.7, 0.6, 0.45, 1))
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	name_lbl.add_theme_constant_override("outline_size", 2)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.position = Vector2(6, 2)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(name_lbl)
	if item != null:
		var icon := TextureRect.new()
		icon.texture = item.get_icon()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(6, 16)
		icon.size = Vector2(SLOT_SIZE.x - 12.0, SLOT_SIZE.y - 22.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(icon)
		var col: Color = ItemDatabase.rarity_color(item.rarity)
		root.modulate = Color(col.r * 0.6 + 0.4, col.g * 0.6 + 0.4, col.b * 0.6 + 0.4, 1)
		if item.is_unique:
			# Pulse for uniques.
			var tw := root.create_tween().set_loops()
			tw.tween_property(root, "modulate", Color(1.4, 0.55, 0.45, 1), 0.8).set_trans(
				Tween.TRANS_SINE
			)
			tw.tween_property(root, "modulate", Color(1.1, 0.4, 0.35, 1), 0.8).set_trans(
				Tween.TRANS_SINE
			)
		root.mouse_entered.connect(_on_inv_hover.bind(item))
		root.mouse_exited.connect(_on_inv_exit)
		root.gui_input.connect(_on_equip_click.bind(slot, item))
	else:
		# Empty slot indicator — dim.
		root.modulate = Color(0.4, 0.4, 0.4, 0.85)
		if InventorySystem and InventorySystem.is_slot_locked_by_2h(slot):
			var lock_lbl := Label.new()
			lock_lbl.text = "2H"
			lock_lbl.add_theme_color_override("font_color", Color(0.9, 0.6, 0.4, 1))
			lock_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			lock_lbl.add_theme_constant_override("outline_size", 2)
			lock_lbl.add_theme_font_size_override("font_size", 22)
			lock_lbl.position = Vector2(SLOT_SIZE.x * 0.5 - 14.0, SLOT_SIZE.y * 0.5 - 14.0)
			lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner.add_child(lock_lbl)
	return root


func _build_inventory_cell(item: ItemInstance) -> Control:
	var root := PanelContainer.new()
	root.theme_type_variation = &"InventoryPanel"
	root.custom_minimum_size = Vector2(78, 78)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if item != null:
		var icon := TextureRect.new()
		icon.texture = item.get_icon()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(68, 68)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(icon)
		var col: Color = ItemDatabase.rarity_color(item.rarity)
		root.modulate = Color(col.r * 0.6 + 0.4, col.g * 0.6 + 0.4, col.b * 0.6 + 0.4, 1)
		if item.is_unique:
			var tw := root.create_tween().set_loops()
			tw.tween_property(root, "modulate", Color(1.4, 0.55, 0.45, 1), 0.7).set_trans(
				Tween.TRANS_SINE
			)
			tw.tween_property(root, "modulate", Color(1.1, 0.4, 0.35, 1), 0.7).set_trans(
				Tween.TRANS_SINE
			)
		root.mouse_entered.connect(_on_inv_hover.bind(item))
		root.mouse_exited.connect(_on_inv_exit)
		root.gui_input.connect(_on_inv_click.bind(item))
	else:
		root.modulate = Color(0.35, 0.35, 0.4, 0.7)
	return root


func _on_inv_hover(item: ItemInstance) -> void:
	if TooltipManager == null or item == null:
		return
	var body_parts: Array = item.get_affix_lines()
	var body: String = "\n".join(body_parts)
	if item.is_weapon():
		body += (
			"\nWeapon: x%.2f damage  (%s)"
			% [
				item.get_weapon_damage_mult(),
				"Two-handed" if item.is_two_handed() else "One-handed"
			]
		)
	if item.is_unique:
		body += "\n✦ " + item.get_transform_desc()
		if item.get_requires_label() != "":
			body += "\n⚑ " + item.get_requires_label()
	# Set items: show set name + per-threshold bonuses with worn-count state.
	if item.get_set_id() != "":
		var counts: Dictionary = InventorySystem.get_set_piece_counts() if InventorySystem else {}
		var worn: int = int(counts.get(item.get_set_id(), 0))
		body += "\n\n%s  (%d/5)" % [item.get_set_name(), worn]
		var def: Dictionary = ItemDatabase.find_set(item.get_set_id())
		for pair in [[2, "bonus2"], [4, "bonus4"], [5, "bonus5"]]:
			var b: Dictionary = def.get(String(pair[1]), {})
			var mark: String = "✓" if worn >= int(pair[0]) else "·"
			body += "\n %s (%d) %s" % [mark, int(pair[0]), String(b.get("label", ""))]
	var meta: String = (
		"%s  •  ilvl %d  •  %s"
		% [
			ItemDatabase.rarity_display(item.rarity),
			item.ilvl,
			ItemDatabase.slot_name(item.get_slot())
		]
	)
	TooltipManager.show_tooltip(item.get_title(), item.rarity, body, meta)


func _on_inv_exit() -> void:
	if TooltipManager:
		TooltipManager.hide_tooltip()


func _on_inv_click(event: InputEvent, item: ItemInstance) -> void:
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_LEFT:
		# Equip. Left-click auto-routes (first free hand); right-click forces a
		# one-handed weapon into the OFF hand so the player can choose the slot
		# without drag-and-drop. Non-weapons ignore the distinction.
		if InventorySystem:
			# Class lock check.
			var lock: String = item.get_class_lock()
			if lock != "" and GameManager and lock != GameManager.player_class:
				if AudioManager:
					AudioManager.play_sfx_path(
						"res://assets/audio/sfx/ui/ui_loot_reveal_common.mp3", -18.0
					)
				return
			var force_off: bool = (
				mb.button_index == MOUSE_BUTTON_RIGHT
				and item.is_weapon()
				and not item.is_two_handed()
			)
			if force_off:
				InventorySystem.equip_item(item, ItemDatabase.SLOT_WEAPON_OFF)
			else:
				InventorySystem.equip_item(item)
	# 'S' on the cell is keyboard-only; handled in _unhandled_input by selected_item.


func _on_equip_click(event: InputEvent, slot: int, _item: ItemInstance) -> void:
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_LEFT:
		if InventorySystem:
			InventorySystem.unequip_slot(slot)


func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("tab_panel"):
		close()
		get_viewport().set_input_as_handled()
