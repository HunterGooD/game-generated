extends CanvasLayer

# Лист персонажа — модальное окно по Tab. Единый экран без вкладок:
# слева персонаж + характеристики, в центре кукла экипировки,
# справа инвентарь. Всё видно одновременно — никаких переключений.

const RARITY_COLORS := {
	"common": Color(0.85, 0.85, 0.9, 1),
	"rare": Color(0.45, 0.75, 1.0, 1),
	"legendary": Color(1.0, 0.65, 0.18, 1),
	"set": Color(0.35, 0.9, 0.35, 1),
	"unique": Color(1.0, 0.4, 0.3, 1),
}

# Диаметр кружка-гнезда на кукле (в сумке — умножается на масштаб ячейки).
const SOCKET_DOT: float = 30.0

var open: bool = false
var selected_item: ItemInstance = null

# Ссылки на построенные в коде узлы.
var portrait: TextureRect = null
var class_name_label: Label = null
var level_label: Label = null
var xp_bar: ProgressBar = null
var xp_label: Label = null
var gold_label: Label = null
var materials_label: Label = null
var stats_box: VBoxContainer = null
var paper_doll: Control = null
var set_summary_label: Label = null
var inventory_grid: GridContainer = null

# ПКМ-меню для предметов в сумке (Надеть / Разобрать / Продать) и на кукле
# (Снять / Просверлить гнездо). _ctx_slot >= 0 — предмет сейчас надет.
var _ctx_menu: PopupMenu = null
var _ctx_item: ItemInstance = null
var _ctx_slot: int = -1

# Кукла в стиле Diablo — (x, y) в пикселях внутри области 340×470.
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

# ── Drag & drop ячейки ────────────────────────────────────────────────────────
# Данные перетаскивания: {"item": ItemInstance, "from_slot": int} (-1 = из сумки).


# Ячейка сумки. Перетаскивание начинает payload; сброс НАДЕТОГО предмета сюда
# снимает его обратно в сумку, сброс камня ИЗ ГНЕЗДА — вынимает его.
class BagCell:
	extends PanelContainer
	var item: ItemInstance = null
	var sheet: Node = null

	func _get_drag_data(_pos: Vector2) -> Variant:
		if item == null or sheet == null:
			return null
		set_drag_preview(sheet.make_drag_preview(item))
		return {"item": item, "from_slot": -1}

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not (data is Dictionary):
			return false
		var d := data as Dictionary
		return int(d.get("from_slot", -1)) >= 0 or d.get("socket_item") is ItemInstance

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if InventorySystem == null:
			return
		var d := data as Dictionary
		if d.get("socket_item") is ItemInstance:
			InventorySystem.unsocket_gem(d["socket_item"] as ItemInstance, int(d.get("socket_idx", -1)))
		else:
			InventorySystem.unequip_slot(int(d.get("from_slot", -1)))


# Слот куклы. Принимает подходящие предметы; перетаскивание наружу тоже
# работает (сброс на сумку = снять).
class EquipCell:
	extends PanelContainer
	var slot: int = -1
	var item: ItemInstance = null
	var sheet: Node = null

	func _get_drag_data(_pos: Vector2) -> Variant:
		if item == null or sheet == null:
			return null
		set_drag_preview(sheet.make_drag_preview(item))
		return {"item": item, "from_slot": slot}

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not (data is Dictionary):
			return false
		var it = (data as Dictionary).get("item")
		if not (it is ItemInstance) or sheet == null:
			return false
		return sheet.item_fits_slot(it as ItemInstance, slot)

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		var it = (data as Dictionary).get("item")
		if it is ItemInstance and InventorySystem:
			InventorySystem.equip_item(it as ItemInstance, slot)


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_layout()
	if InventorySystem:
		InventorySystem.equipment_changed.connect(_on_inventory_dirty)
		InventorySystem.inventory_changed.connect(_on_inventory_dirty)
	if GameManager:
		GameManager.materials_changed.connect(_on_inventory_dirty)


func _on_inventory_dirty() -> void:
	if open:
		_rebuild_equipment()
		_refresh_header()
		_populate_stats()


# ── Построение каркаса ───────────────────────────────────────────────────────
func _build_layout() -> void:
	var margin := get_node_or_null("Root/Panel/Margin") as MarginContainer
	if margin == null:
		return

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	margin.add_child(main)

	_build_header(main)
	main.add_child(HSeparator.new())

	# ── Три колонки: характеристики | кукла | инвентарь ──
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(cols)

	_build_stats_column(cols)
	_build_equipment_column(cols)
	_build_inventory_column(cols)
	_build_hint(main)


# Шапка: класс + уровень + полоса опыта + золото/материалы.
func _build_header(main: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	main.add_child(head)

	class_name_label = Label.new()
	class_name_label.text = "Герой"
	class_name_label.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3, 1))
	class_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	class_name_label.add_theme_constant_override("outline_size", 6)
	class_name_label.add_theme_font_size_override("font_size", 30)
	head.add_child(class_name_label)

	level_label = Label.new()
	level_label.text = "Уровень 1"
	level_label.add_theme_color_override("font_color", Color(1, 0.92, 0.55, 1))
	level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	level_label.add_theme_constant_override("outline_size", 5)
	level_label.add_theme_font_size_override("font_size", 24)
	level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(level_label)

	var xp_box := VBoxContainer.new()
	xp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_box.add_theme_constant_override("separation", 2)
	head.add_child(xp_box)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(0, 16)
	xp_bar.show_percentage = false
	xp_box.add_child(xp_bar)
	xp_label = Label.new()
	xp_label.text = "0 / 50 опыта"
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.add_theme_color_override("font_color", Color(0.9, 0.55, 0.4, 1))
	xp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	xp_label.add_theme_constant_override("outline_size", 3)
	xp_label.add_theme_font_size_override("font_size", 13)
	xp_box.add_child(xp_label)

	var money_box := VBoxContainer.new()
	money_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	money_box.add_theme_constant_override("separation", 2)
	head.add_child(money_box)
	gold_label = Label.new()
	gold_label.text = "Золото: 0"
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1))
	gold_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	gold_label.add_theme_constant_override("outline_size", 4)
	gold_label.add_theme_font_size_override("font_size", 18)
	money_box.add_child(gold_label)
	materials_label = Label.new()
	materials_label.text = ""
	materials_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	materials_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.9, 1))
	materials_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	materials_label.add_theme_constant_override("outline_size", 3)
	materials_label.add_theme_font_size_override("font_size", 13)
	money_box.add_child(materials_label)


# ЛЕВО: портрет + характеристики (прокручиваемые).
func _build_stats_column(cols: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(180, 180)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(portrait)
	var stats_title := Label.new()
	stats_title.text = "Характеристики"
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_title.add_theme_color_override("font_color", Color(0.95, 0.7, 0.4, 1))
	stats_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	stats_title.add_theme_constant_override("outline_size", 4)
	stats_title.add_theme_font_size_override("font_size", 19)
	left.add_child(stats_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	stats_box = VBoxContainer.new()
	stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_box.add_theme_constant_override("separation", 1)
	scroll.add_child(stats_box)


# ЦЕНТР: кукла экипировки + бонусы комплектов.
func _build_equipment_column(cols: HBoxContainer) -> void:
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(360, 0)
	mid.add_theme_constant_override("separation", 8)
	cols.add_child(mid)
	var doll_lbl := Label.new()
	doll_lbl.text = "Экипировка"
	doll_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	doll_lbl.add_theme_color_override("font_color", Color(0.95, 0.7, 0.4, 1))
	doll_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	doll_lbl.add_theme_constant_override("outline_size", 4)
	doll_lbl.add_theme_font_size_override("font_size", 19)
	mid.add_child(doll_lbl)
	paper_doll = Control.new()
	paper_doll.custom_minimum_size = Vector2(340, 470)
	paper_doll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mid.add_child(paper_doll)
	_add_backdrop(paper_doll, Color(0.6, 0.55, 0.55, 0.9))
	set_summary_label = Label.new()
	set_summary_label.text = ""
	set_summary_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.45, 1))
	set_summary_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	set_summary_label.add_theme_constant_override("outline_size", 3)
	set_summary_label.add_theme_font_size_override("font_size", 13)
	set_summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(set_summary_label)


# ПРАВО: инвентарь.
func _build_inventory_column(cols: HBoxContainer) -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	var inv_head := HBoxContainer.new()
	inv_head.add_theme_constant_override("separation", 12)
	right.add_child(inv_head)
	var inv_lbl := Label.new()
	inv_lbl.text = "Инвентарь"
	inv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_lbl.add_theme_color_override("font_color", Color(0.95, 0.7, 0.4, 1))
	inv_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	inv_lbl.add_theme_constant_override("outline_size", 4)
	inv_lbl.add_theme_font_size_override("font_size", 19)
	inv_head.add_child(inv_lbl)
	var salvage_all_btn := Button.new()
	salvage_all_btn.text = "Разобрать обычные и редкие"
	salvage_all_btn.add_theme_font_size_override("font_size", 13)
	salvage_all_btn.focus_mode = Control.FOCUS_NONE
	salvage_all_btn.pressed.connect(_on_salvage_all)
	inv_head.add_child(salvage_all_btn)
	var inv_wrap := Control.new()
	inv_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(inv_wrap)
	_add_backdrop(inv_wrap, Color(0.55, 0.5, 0.5, 0.9))
	var inv_margin := MarginContainer.new()
	inv_margin.add_theme_constant_override("margin_left", 12)
	inv_margin.add_theme_constant_override("margin_right", 12)
	inv_margin.add_theme_constant_override("margin_top", 12)
	inv_margin.add_theme_constant_override("margin_bottom", 12)
	inv_wrap.add_child(inv_margin)
	inv_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inventory_grid = GridContainer.new()
	inventory_grid.columns = 11
	inventory_grid.add_theme_constant_override("h_separation", 6)
	inventory_grid.add_theme_constant_override("v_separation", 6)
	inv_margin.add_child(inventory_grid)


# ── Подсказка снизу ──
func _build_hint(main: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "Tab / Esc — закрыть  •  ЛКМ — надеть/снять  •  ПКМ — действия  •  самоцветы тащите в гнёзда, ПКМ по гнезду — повернуть"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4, 1))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hint.add_theme_constant_override("outline_size", 3)
	hint.add_theme_font_size_override("font_size", 13)
	main.add_child(hint)


func _add_backdrop(parent: Control, tint: Color) -> void:
	var bg := TextureRect.new()
	var bg_path: String = "res://assets/textures/backgrounds/inventory_bg_dark.webp"
	if ResourceLoader.exists(bg_path):
		bg.texture = load(bg_path) as Texture2D
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = tint
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ── Открытие/закрытие ────────────────────────────────────────────────────────
func toggle() -> void:
	if open:
		close()
	else:
		show_sheet()


# Совместимость со старым API (вкладок больше нет — всё на одном экране).
func show_with_tab(_tab: String) -> void:
	show_sheet()


func show_sheet() -> void:
	open = true
	visible = true
	# Кооп: не ставим общий мир на паузу ради одного игрока (заморозит и
	# рассинхронизирует остальных). В соло пауза — для удобства.
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = true
	_refresh_header()
	_populate_stats()
	_rebuild_equipment()


func close() -> void:
	open = false
	visible = false
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = false
	if TooltipManager:
		TooltipManager.hide_tooltip()


# ── Шапка ────────────────────────────────────────────────────────────────────
func _refresh_header() -> void:
	if GameManager == null:
		return
	var data: Dictionary = GameManager.get_class_data()
	if portrait:
		var p_path: String = String(data.get("portrait", ""))
		if p_path != "" and ResourceLoader.exists(p_path):
			portrait.texture = load(p_path) as Texture2D
	if class_name_label:
		class_name_label.text = String(data.get("display", "Герой"))
	if level_label:
		level_label.text = "Уровень %d" % GameManager.player_level
	if xp_bar:
		xp_bar.max_value = GameManager.player_xp_to_next
		xp_bar.value = GameManager.player_xp
	if xp_label:
		xp_label.text = "%d / %d опыта" % [GameManager.player_xp, GameManager.player_xp_to_next]
	if gold_label:
		gold_label.text = "Золото: %d" % GameManager.gold
	if materials_label:
		var parts: Array = []
		for mid in ItemDatabase.MATERIAL_IDS:
			parts.append(
				"%s: %d" % [String(ItemDatabase.MATERIAL_DISPLAY[mid]), GameManager.get_material(mid)]
			)
		# Камни комплектов — показываем только имеющиеся.
		for set_id in GameManager.set_stones:
			parts.append(
				"Камень «%s»: %d"
				% [
					ItemDatabase.find_set(String(set_id)).name,
					GameManager.get_set_stones(String(set_id))
				]
			)
		materials_label.text = "   ".join(parts)


# ── Характеристики ───────────────────────────────────────────────────────────
func _populate_stats() -> void:
	if GameManager == null or stats_box == null:
		return
	for c in stats_box.get_children():
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
	var s: int = GameManager.get_effective_strength()
	var d: int = GameManager.get_effective_dexterity()
	var i: int = GameManager.get_effective_intelligence()
	# Повторяет формулы GameManager.get_stat_* / get_effective_*.
	var rows: Array = [
		["СИЛА", str(s), "header"],
		["Базовый урон", "+%d%%" % s, "sub"],
		["Макс. здоровье", "+%d" % (5 * s), "sub"],
		["ЛОВКОСТЬ", str(d), "header"],
		["Скорость атаки", "+%d%%" % d, "sub"],
		["Скорость бега", "+%d" % (2 * d), "sub"],
		["Шанс крита", "+%.1f%%" % (0.3 * float(d)), "sub"],
		["ИНТЕЛЛЕКТ", str(i), "header"],
		["Урон навыков", "+%d%%" % i, "sub"],
		["Макс. мана", "+%d" % (3 * i), "sub"],
		["Восстановление умений", "+%.1f%%" % (0.3 * float(i)), "sub"],
		["БОЙ", "", "header"],
		["Здоровье", "%d / %d" % [GameManager.player_hp, GameManager.get_effective_max_hp()], "sub"],
		[
			"Мана",
			"%d / %d" % [int(GameManager.player_mana), GameManager.get_effective_max_mana()],
			"sub"
		],
		["Урон", "%d (+%d%%)" % [GameManager.get_effective_damage(), int(dmg_bonus_pct)], "sub"],
		["Броня", str(armor), "sub"],
		[
			"Шанс крита",
			"%d%%" % int((GameManager.player_crit_chance + crit_ch_bonus) * 100.0),
			"sub"
		],
		["Крит. урон", "x%.2f" % (GameManager.player_crit_damage + crit_dm_bonus), "sub"],
		["ЗАБЕГ", "", "header"],
		["Золото", str(GameManager.gold), "sub"],
		["Золота всего", str(GameManager.total_gold_earned), "sub"],
		["Лучшая волна", str(GameManager.highest_wave), "sub"],
		["Врагов убито", str(GameManager.enemies_killed), "sub"],
	]
	for row in rows:
		var is_header: bool = String(row[2]) == "header"
		var line := HBoxContainer.new()
		stats_box.add_child(line)
		var l := Label.new()
		l.text = String(row[0]) if is_header else "    " + String(row[0])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override(
			"font_color",
			Color(1.0, 0.78, 0.35, 1) if is_header else Color(0.85, 0.78, 0.62, 1)
		)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		l.add_theme_constant_override("outline_size", 3)
		l.add_theme_font_size_override("font_size", 17 if is_header else 14)
		line.add_child(l)
		var v := Label.new()
		v.text = String(row[1])
		v.add_theme_color_override(
			"font_color",
			Color(1.0, 0.85, 0.4, 1) if is_header else Color(1.0, 0.9, 0.55, 1)
		)
		v.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		v.add_theme_constant_override("outline_size", 3)
		v.add_theme_font_size_override("font_size", 17 if is_header else 14)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(v)


# ── Экипировка + инвентарь ───────────────────────────────────────────────────
func _rebuild_equipment() -> void:
	if paper_doll == null or inventory_grid == null:
		return
	# Чистим слоты куклы (фоновый TextureRect оставляем).
	for c in paper_doll.get_children():
		if c is TextureRect:
			continue
		c.queue_free()
	for c in inventory_grid.get_children():
		c.queue_free()
	# Сводка бонусов надетых комплектов под куклой.
	if set_summary_label and InventorySystem:
		var lines: Array = []
		for info in InventorySystem.get_active_set_bonuses():
			lines.append("%s  (%d/5)" % [String(info.get("name", "")), int(info.get("pieces", 0))])
			for b in info.get("bonuses", []):
				if bool(b.get("active", false)):
					lines.append("  ✓ %s" % String(b.get("label", "")))
		# Цепи самоцветов: итоги связей, резонансы, контуры, эффекты камней.
		lines += SocketGems.summary_lines(InventorySystem.get_socket_links())
		set_summary_label.text = "\n".join(lines)

	# Слоты куклы на своих позициях.
	for slot_id in PAPER_DOLL_LAYOUT.keys():
		var pos: Vector2 = PAPER_DOLL_LAYOUT[slot_id]
		var tile := _build_equip_slot_tile(int(slot_id))
		tile.custom_minimum_size = SLOT_SIZE
		tile.size = SLOT_SIZE
		paper_doll.add_child(tile)
		tile.position = pos

	# Линии активных связей между гнёздами — поверх плиток, мышь игнорируют.
	_add_link_overlay()

	# Инвентарь: 11×9 = 99 ячеек.
	var items: Array = InventorySystem.inventory if InventorySystem else []
	var cap: int = InventorySystem.INVENTORY_CAPACITY if InventorySystem else 99
	for i in cap:
		var item: ItemInstance = items[i] if i < items.size() and items[i] is ItemInstance else null
		var cell := _build_inventory_cell(item)
		inventory_grid.add_child(cell)


# Центры гнёзд внутри плитки 100×100 (большие круги поверх предмета).
# Доспех — квадрат 2×2; остальные — ряд по горизонтали.
static func socket_centers(slot: int, count: int) -> Array:
	if slot == ItemDatabase.SLOT_CHEST:
		var grid: Array = [Vector2(33, 45), Vector2(67, 45), Vector2(33, 79), Vector2(67, 79)]
		return grid.slice(0, count)
	if count == 1:
		return [Vector2(50, 62)]
	return [Vector2(33, 62), Vector2(67, 62)].slice(0, count)


# Центр кружка-гнезда в координатах куклы ((INF,INF), если гнезда нет на кукле).
func _socket_dot_center(slot: int, idx: int) -> Vector2:
	if not PAPER_DOLL_LAYOUT.has(slot) or InventorySystem == null:
		return Vector2.INF
	var item: ItemInstance = InventorySystem.get_equipped(slot)
	if item == null:
		return Vector2.INF
	var centers: Array = socket_centers(slot, item.sockets.size())
	if idx < 0 or idx >= centers.size():
		return Vector2.INF
	return Vector2(PAPER_DOLL_LAYOUT[slot]) + Vector2(centers[idx])


func _add_link_overlay() -> void:
	if InventorySystem == null or paper_doll == null:
		return
	var overlay := SocketLinkOverlay.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var widths: Dictionary = {"full": 4.0, "half": 2.5, "bridge": 1.5}
	var segs: Array = []
	for l in InventorySystem.get_socket_links().get("links", []):
		var link: Dictionary = l
		var a: Dictionary = link.get("a", {})
		var b: Dictionary = link.get("b", {})
		var pa: Vector2 = _socket_dot_center(int(a.get("slot", -1)), int(a.get("idx", -1)))
		var pb: Vector2 = _socket_dot_center(int(b.get("slot", -1)), int(b.get("idx", -1)))
		if not pa.is_finite() or not pb.is_finite():
			continue
		(
			segs
			. append(
				{
					"from": pa,
					"to": pb,
					"color": SocketGems.color_tint(String(link.get("color", "white"))),
					"width": float(widths.get(String(link.get("kind", "")), 2.0)),
				}
			)
		)
	overlay.segments = segs
	paper_doll.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# Кружки-гнёзда поверх плитки предмета (`scale_f` < 1 в ячейках сумки).
func _add_socket_dots(parent: Control, item: ItemInstance, slot: int, scale_f: float) -> void:
	if item == null or item.sockets.is_empty():
		return
	var d: float = SOCKET_DOT * scale_f
	var centers: Array = socket_centers(slot, item.sockets.size())
	for i in item.sockets.size():
		if i >= centers.size():
			break
		var dot := SocketDot.new()
		dot.owner_item = item
		dot.idx = i
		dot.sheet = self
		var e: Dictionary = item.socket_entry(i)
		if not e.is_empty():
			dot.world_faces = SocketGems.entry_world_faces(e)
		dot.size = Vector2(d, d)
		dot.position = Vector2(centers[i]) * scale_f - Vector2(d, d) * 0.5
		parent.add_child(dot)


func _build_equip_slot_tile(slot: int) -> Control:
	var root := EquipCell.new()
	root.theme_type_variation = &"InventoryPanel"
	root.custom_minimum_size = SLOT_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var item: ItemInstance = InventorySystem.get_equipped(slot) if InventorySystem else null
	root.slot = slot
	root.item = item
	root.sheet = self
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(inner)
	# Название слота мелким текстом сверху.
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
			# Пульсация уникальных.
			var tw := root.create_tween().set_loops()
			tw.tween_property(root, "modulate", Color(1.4, 0.55, 0.45, 1), 0.8).set_trans(
				Tween.TRANS_SINE
			)
			tw.tween_property(root, "modulate", Color(1.1, 0.4, 0.35, 1), 0.8).set_trans(
				Tween.TRANS_SINE
			)
		elif item.rarity == ItemDatabase.RARITY_SET:
			# Мягкая зелёная пульсация комплектных.
			var tws := root.create_tween().set_loops()
			tws.tween_property(root, "modulate", Color(0.6, 1.35, 0.6, 1), 0.9).set_trans(
				Tween.TRANS_SINE
			)
			tws.tween_property(root, "modulate", Color(0.5, 1.05, 0.5, 1), 0.9).set_trans(
				Tween.TRANS_SINE
			)
		root.mouse_entered.connect(_on_inv_hover.bind(item))
		root.mouse_exited.connect(_on_inv_exit)
		root.gui_input.connect(_on_equip_click.bind(slot, item))
		_add_socket_dots(inner, item, slot, 1.0)
	else:
		# Пустой слот — приглушён.
		root.modulate = Color(0.4, 0.4, 0.4, 0.85)
		if InventorySystem and InventorySystem.is_slot_locked_by_2h(slot):
			var lock_lbl := Label.new()
			lock_lbl.text = "2Р"
			lock_lbl.add_theme_color_override("font_color", Color(0.9, 0.6, 0.4, 1))
			lock_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			lock_lbl.add_theme_constant_override("outline_size", 2)
			lock_lbl.add_theme_font_size_override("font_size", 22)
			lock_lbl.position = Vector2(SLOT_SIZE.x * 0.5 - 14.0, SLOT_SIZE.y * 0.5 - 14.0)
			lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner.add_child(lock_lbl)
	return root


func _build_inventory_cell(item: ItemInstance) -> Control:
	var root := BagCell.new()
	root.theme_type_variation = &"InventoryPanel"
	root.custom_minimum_size = Vector2(72, 72)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.item = item
	root.sheet = self
	if item != null:
		if item.is_gem():
			# Самоцветы рисуются процедурно: квадрат с цветными гранями = его данные.
			var gem_icon := GemFaceIcon.new()
			gem_icon.faces = item.get_gem_faces()
			gem_icon.custom_minimum_size = Vector2(54, 54)
			gem_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			gem_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			gem_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(gem_icon)
		else:
			var icon := TextureRect.new()
			icon.texture = item.get_icon()
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(62, 62)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(icon)
			if not item.sockets.is_empty():
				var dots := Control.new()
				dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
				root.add_child(dots)
				_add_socket_dots(dots, item, item.get_slot(), 0.72)
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
		elif item.rarity == ItemDatabase.RARITY_SET:
			var tws := root.create_tween().set_loops()
			tws.tween_property(root, "modulate", Color(0.6, 1.35, 0.6, 1), 0.9).set_trans(
				Tween.TRANS_SINE
			)
			tws.tween_property(root, "modulate", Color(0.5, 1.05, 0.5, 1), 0.9).set_trans(
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
	if item.is_gem():
		TooltipManager.show_tooltip(
			item.get_title(),
			item.rarity,
			(
				SocketGems.describe(item.gem_id, 0, item.gem_faces)
				+ "\nПеретащите на гнездо экипировки."
			),
			"Самоцвет  •  %s" % ItemDatabase.rarity_display(item.rarity),
		)
		return
	var body_parts: Array = item.get_affix_lines()
	var body: String = "\n".join(body_parts)
	# Гнёзда: сколько просверлено / максимум, и что вставлено.
	if item.max_sockets() > 0:
		body += "\nГнёзда: %d/%d" % [item.sockets.size(), item.max_sockets()]
		for i in item.sockets.size():
			var e: Dictionary = item.socket_entry(i)
			if e.is_empty():
				body += "\n  ○ пусто"
			else:
				body += "\n  ◆ " + SocketGems.display_name(String(e.get("gem", "")))
	if item.is_weapon():
		body += (
			"\nОружие: x%.2f урона  (%s)"
			% [
				item.get_weapon_damage_mult(),
				"двуручное" if item.is_two_handed() else "одноручное"
			]
		)
	if item.is_unique:
		body += "\n✦ " + item.get_transform_desc()
		if item.get_requires_label() != "":
			body += "\n⚑ " + item.get_requires_label()
	# Комплектные: имя комплекта + бонусы порогов с отметкой надетых.
	if item.get_set_id() != "":
		var counts: Dictionary = InventorySystem.get_set_piece_counts() if InventorySystem else {}
		var worn: int = int(counts.get(item.get_set_id(), 0))
		body += "\n\n%s  (%d/5)" % [item.get_set_name(), worn]
		var def := ItemDatabase.find_set(item.get_set_id())
		for threshold in [2, 4, 5]:
			var mark: String = "✓" if worn >= threshold else "·"
			body += "\n %s (%d) %s" % [mark, threshold, def.bonus_for(threshold).label]
	# Сравнение с надетым в тот же слот (только при наведении на предмет ИЗ СУМКИ).
	if InventorySystem and not InventorySystem.equipment.values().has(item):
		var eq: ItemInstance = InventorySystem.get_equipped(item.get_slot())
		if eq == null and item.get_slot() == ItemDatabase.SLOT_RING_1:
			eq = InventorySystem.get_equipped(ItemDatabase.SLOT_RING_2)
		if eq != null and eq != item:
			body += (
				"\n\n— Надето: %s (%s, ур. %d) —"
				% [eq.get_title(), ItemDatabase.rarity_display(eq.rarity), eq.ilvl]
			)
			for line in eq.get_affix_lines():
				body += "\n  " + String(line)
	var meta: String = (
		"%s  •  ур. предмета %d  •  %s"
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
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	# Быстрое надевание срабатывает на ОТПУСКАНИИ, не на нажатии — реакция на
	# нажатие перестроила бы сетку (освободив эту ячейку) до того, как порог
	# перетаскивания Godot успел бы начать drag. Завершённый drag поглощает
	# отпускание, так что перетаскивания никогда не «быстро-надевают».
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		_try_equip(item, -1)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_show_ctx_menu(item)


func _try_equip(item: ItemInstance, target_slot: int) -> void:
	if InventorySystem == null or item == null:
		return
	var lock: String = item.get_class_lock()
	if lock != "" and GameManager and lock != GameManager.player_class:
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_loot_reveal_common.mp3", -18.0)
		return
	InventorySystem.equip_item(item, target_slot)


# ── Drag & drop / контекстное меню ───────────────────────────────────────────
# Может ли `item` лечь в слот куклы `slot` (подсветка целей перетаскивания).
func item_fits_slot(item: ItemInstance, slot: int) -> bool:
	if item == null or InventorySystem == null:
		return false
	var lock: String = item.get_class_lock()
	if lock != "" and GameManager and lock != String(GameManager.player_class):
		return false
	if item.is_weapon():
		if slot == ItemDatabase.SLOT_WEAPON_MAIN:
			return true
		if slot == ItemDatabase.SLOT_WEAPON_OFF:
			return not item.is_two_handed() or InventorySystem.has_berserker_grip
		return false
	var s: int = item.get_slot()
	if s == ItemDatabase.SLOT_RING_1 or s == ItemDatabase.SLOT_RING_2:
		return slot == ItemDatabase.SLOT_RING_1 or slot == ItemDatabase.SLOT_RING_2
	return slot == s


func make_drag_preview(item: ItemInstance) -> Control:
	if item.is_gem():
		var gem := GemFaceIcon.new()
		gem.faces = item.get_gem_faces()
		gem.custom_minimum_size = Vector2(48, 48)
		gem.size = Vector2(48, 48)
		gem.modulate = Color(1, 1, 1, 0.85)
		return gem
	var icon := TextureRect.new()
	icon.texture = item.get_icon()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(64, 64)
	icon.size = Vector2(64, 64)
	icon.modulate = Color(1, 1, 1, 0.85)
	return icon


# `equipped_slot` >= 0 — меню для НАДЕТОГО предмета (Снять/Просверлить),
# иначе обычное меню сумки.
func _show_ctx_menu(item: ItemInstance, equipped_slot: int = -1) -> void:
	if item == null:
		return
	_ctx_item = item
	_ctx_slot = equipped_slot
	if _ctx_menu == null:
		_ctx_menu = PopupMenu.new()
		add_child(_ctx_menu)
		_ctx_menu.id_pressed.connect(_on_ctx_menu_id)
	_ctx_menu.clear()
	if equipped_slot >= 0:
		_ctx_menu.add_item("Снять", 4)
	elif not item.is_gem():
		_ctx_menu.add_item("Надеть", 0)
		if item.is_weapon() and not item.is_two_handed():
			_ctx_menu.add_item("Надеть во вторую руку", 1)
	# Сверление нового гнезда — за материалы разборки, до максимума слота.
	var dcost: Dictionary = InventorySystem.drill_cost(item) if InventorySystem else {}
	if not dcost.is_empty():
		_ctx_menu.add_item("Просверлить гнездо  (%s)" % ItemDatabase.format_cost(dcost), 5)
		if GameManager and not GameManager.can_afford_cost(dcost):
			_ctx_menu.set_item_disabled(_ctx_menu.get_item_index(5), true)
	if equipped_slot < 0:
		_ctx_menu.add_separator()
		(
			_ctx_menu
			. add_item(
				"Разобрать  (+%s)" % ItemDatabase.format_cost(item.get_salvage_preview()), 2
			)
		)
		_ctx_menu.add_item("Продать  (+%dз)" % (item.get_salvage_gold() * 2), 3)
	if TooltipManager:
		TooltipManager.hide_tooltip()
	_ctx_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(4, 4)
	_ctx_menu.popup()


func _on_ctx_menu_id(id: int) -> void:
	if _ctx_item == null or InventorySystem == null:
		return
	match id:
		0:
			_try_equip(_ctx_item, -1)
		1:
			_try_equip(_ctx_item, ItemDatabase.SLOT_WEAPON_OFF)
		2:
			InventorySystem.salvage_item(_ctx_item)
		3:
			InventorySystem.sell_item(_ctx_item)
		4:
			InventorySystem.unequip_slot(_ctx_slot)
		5:
			InventorySystem.drill_socket(_ctx_item)
	_ctx_item = null
	_ctx_slot = -1


# Разобрать все обычные и редкие предметы в сумке одним кликом.
func _on_salvage_all() -> void:
	if InventorySystem == null:
		return
	var targets: Array = []
	for it in InventorySystem.inventory:
		if (
			it is ItemInstance
			and not (it as ItemInstance).is_gem()
			and (it as ItemInstance).rarity
			in [ItemDatabase.RARITY_COMMON, ItemDatabase.RARITY_RARE]
		):
			targets.append(it)
	for it in targets:
		InventorySystem.salvage_item(it)


func _on_equip_click(event: InputEvent, slot: int, item: ItemInstance) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	# ЛКМ снимает на ОТПУСКАНИИ, чтобы нажатие могло начать drag (см. _on_inv_click).
	# ПКМ открывает меню (Снять / Просверлить гнездо).
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		if InventorySystem:
			InventorySystem.unequip_slot(slot)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_show_ctx_menu(item, slot)


func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("tab_panel"):
		close()
		get_viewport().set_input_as_handled()
