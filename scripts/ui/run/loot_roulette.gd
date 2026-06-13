extends CanvasLayer

# Fullscreen CS:GO-style loot reveal.
# Horizontal strip of ~40 item icons scrolls under a center marker, then stops on
# the awarded item. Player can Take or Salvage.

const STRIP_COUNT: int = 42
const FINAL_INDEX: int = 36  # which strip cell holds the actual award
const CELL_WIDTH: float = 196.0
const CELL_HEIGHT: float = 220.0
const SCROLL_DURATION: float = 4.2
const FRAME_COLORS: Dictionary = {
	"common": Color(0.65, 0.65, 0.70, 1),
	"rare": Color(0.4, 0.7, 1.0, 1),
	"legendary": Color(1.0, 0.65, 0.18, 1),
	"set": Color(0.35, 0.9, 0.35, 1),
	"unique": Color(1.0, 0.35, 0.25, 1),
}

@export var dim: ColorRect
@export var strip_root: Control
@export var strip_inner: Control
@export var marker: ColorRect
@export var detail_panel: Control
@export var detail_title: Label
@export var detail_rarity: Label
@export var detail_affixes: VBoxContainer
@export var detail_transform: Label
@export var detail_ilvl: Label
@export var take_btn: Button
@export var salvage_btn: Button
@export var heading: Label

var award_item: ItemInstance = null
var strip_items: Array = []
var tick_t: float = 0.0
var scrolling: bool = false
var scroll_x: float = 0.0
var scroll_v: float = 0.0
var revealed: bool = false
var scroll_tween: Tween = null
var ease_distance: float = 0.0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	if detail_panel:
		detail_panel.visible = false
	if take_btn:
		take_btn.pressed.connect(_on_take)
	if salvage_btn:
		salvage_btn.pressed.connect(_on_salvage)


func start(item: ItemInstance, wave: int, class_id: String) -> void:
	award_item = item
	# Build strip — many random items, with the award at FINAL_INDEX.
	strip_items = LootRoller.roll_preview_strip(STRIP_COUNT, wave, class_id)
	strip_items[FINAL_INDEX] = item
	_build_strip()
	# In co-op the world keeps simulating while one player browses the
	# roulette — otherwise the other player's enemies stop taking damage.
	# Solo still pauses for convenience.
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = true
	scrolling = true
	# Single source of truth: strip_inner.position.x = center_x - scroll_x - CELL_WIDTH*0.5
	# At scroll_x = FINAL_INDEX * CELL_WIDTH, the cell at FINAL_INDEX is centered
	# under the marker — that cell IS award_item, so visual and award match.
	ease_distance = float(FINAL_INDEX) * CELL_WIDTH
	scroll_x = 0.0
	tick_t = 0.0
	_set_scroll(0.0)
	scroll_tween = create_tween()
	(
		scroll_tween
		. tween_method(_set_scroll, 0.0, ease_distance, SCROLL_DURATION)
		. set_trans(Tween.TRANS_QUART)
		. set_ease(Tween.EASE_OUT)
	)
	scroll_tween.tween_callback(_on_scroll_done)


func _set_scroll(x: float) -> void:
	scroll_x = x
	var center_x: float = strip_root.size.x * 0.5
	strip_inner.position.x = center_x - scroll_x - CELL_WIDTH * 0.5
	# Tick sound at every cell crossing.
	var idx: int = int(scroll_x / CELL_WIDTH)
	if idx != int(tick_t):
		tick_t = float(idx)
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_loot_roulette_tick.mp3", -16.0)


func _on_scroll_done() -> void:
	scrolling = false
	revealed = true
	# Snap to exact final position so visual cell == award cell.
	var center_x: float = strip_root.size.x * 0.5
	strip_inner.position.x = center_x - float(FINAL_INDEX) * CELL_WIDTH - CELL_WIDTH * 0.5
	# Play reveal sfx by rarity.
	var path: String = "res://assets/audio/sfx/ui/ui_loot_reveal_common.mp3"
	match String(award_item.rarity):
		"rare":
			path = "res://assets/audio/sfx/ui/ui_loot_reveal_rare.mp3"
		"legendary", "set":
			path = "res://assets/audio/sfx/ui/ui_loot_reveal_legendary.mp3"
		"unique":
			path = "res://assets/audio/sfx/ui/ui_loot_reveal_unique.mp3"
	if AudioManager:
		AudioManager.play_sfx_path(path, -6.0)
	if VfxManager:
		VfxManager.screen_flash(FRAME_COLORS.get(award_item.rarity, Color(1, 1, 1, 0.2)), 0.4)
	_show_detail()


func _build_strip() -> void:
	if strip_inner == null:
		return
	for c in strip_inner.get_children():
		c.queue_free()
	for i in strip_items.size():
		var item: ItemInstance = strip_items[i]
		var cell := _build_cell(item)
		cell.position = Vector2(float(i) * CELL_WIDTH, 0.0)
		cell.size = Vector2(CELL_WIDTH - 8.0, CELL_HEIGHT - 8.0)
		strip_inner.add_child(cell)


func _build_cell(item: ItemInstance) -> Control:
	var root := PanelContainer.new()
	root.theme_type_variation = &"InventoryPanel"
	var frame_col: Color = FRAME_COLORS.get(String(item.rarity), Color(1, 1, 1, 1))
	root.modulate = Color(
		frame_col.r * 0.6 + 0.4, frame_col.g * 0.6 + 0.4, frame_col.b * 0.6 + 0.4, 1
	)
	root.custom_minimum_size = Vector2(CELL_WIDTH - 8.0, CELL_HEIGHT - 8.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(vb)
	var icon := TextureRect.new()
	icon.texture = item.get_icon()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(150, 150)
	vb.add_child(icon)
	var lbl := Label.new()
	lbl.text = item.get_title()
	lbl.add_theme_color_override("font_color", frame_col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(lbl)
	return root


func _show_detail() -> void:
	if award_item == null or detail_panel == null:
		return
	detail_panel.visible = true
	var rarity_col: Color = FRAME_COLORS.get(String(award_item.rarity), Color.WHITE)
	if detail_title:
		detail_title.text = award_item.get_title()
		detail_title.add_theme_color_override("font_color", rarity_col)
	if detail_rarity:
		detail_rarity.text = ItemDatabase.rarity_display(award_item.rarity)
		detail_rarity.add_theme_color_override("font_color", rarity_col)
	if detail_ilvl:
		detail_ilvl.text = "Уровень предмета %d" % award_item.ilvl
	if detail_affixes:
		for c in detail_affixes.get_children():
			c.queue_free()
		for line in award_item.get_affix_lines():
			var l := Label.new()
			l.text = line
			l.add_theme_color_override("font_color", Color(0.92, 0.86, 0.58, 1))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			l.add_theme_constant_override("outline_size", 3)
			l.add_theme_font_size_override("font_size", 18)
			detail_affixes.add_child(l)
		# Weapon damage line.
		if award_item.is_weapon():
			var wl := Label.new()
			wl.text = (
				"Урон оружия: x%.2f%s"
				% [
					award_item.get_weapon_damage_mult(),
					" (2Р)" if award_item.is_two_handed() else " (1Р)"
				]
			)
			wl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.55, 1))
			wl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			wl.add_theme_constant_override("outline_size", 3)
			wl.add_theme_font_size_override("font_size", 18)
			detail_affixes.add_child(wl)
	if detail_transform:
		var td: String = award_item.get_transform_desc()
		if td != "":
			detail_transform.text = "✦ " + td
			if award_item.get_requires_label() != "":
				detail_transform.text += "\n⚑ " + award_item.get_requires_label()
			detail_transform.visible = true
		elif award_item.get_set_id() != "":
			detail_transform.text = "◆ Часть комплекта «%s»" % award_item.get_set_name()
			detail_transform.visible = true
		else:
			detail_transform.visible = false
	if salvage_btn:
		salvage_btn.text = "Разобрать  (+%s)" % ItemDatabase.format_cost(award_item.get_salvage_preview())


func _on_take() -> void:
	if award_item == null:
		_close()
		return
	if InventorySystem:
		InventorySystem.add_item(award_item)
	_close(true)


func _on_salvage() -> void:
	if award_item == null:
		_close()
		return
	if InventorySystem:
		InventorySystem.salvage_item(award_item)
	elif GameManager:
		# Fallback — grant the materials directly.
		GameManager.add_materials(award_item.get_salvage_preview())
	_close(false)


func _close(open_inventory: bool = false) -> void:
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = false
	# Open inventory if requested.
	if open_inventory:
		var sheet := _find_character_sheet()
		if sheet and sheet.has_method("show_with_tab"):
			sheet.call("show_with_tab", "equipment")
		elif sheet and sheet.has_method("show_sheet"):
			sheet.call("show_sheet")
	queue_free()


func _find_character_sheet() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	# Search the current scene for a CharacterSheet node.
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.find_child("CharacterSheet", true, false)


func _unhandled_input(event: InputEvent) -> void:
	if scrolling:
		# Click / Enter / Space during the spin = skip the animation and
		# reveal the result immediately. This is much friendlier on repeated
		# chest opens during long runs.
		var skip: bool = false
		if event is InputEventMouseButton and event.pressed:
			skip = true
		elif event is InputEventKey and event.pressed:
			if (
				event.keycode == KEY_ENTER
				or event.keycode == KEY_KP_ENTER
				or event.keycode == KEY_SPACE
			):
				skip = true
		if skip:
			_skip_to_reveal()
			get_viewport().set_input_as_handled()
		return
	# Allow Enter / Space to Take, S to Salvage.
	if event is InputEventKey and event.pressed:
		if (
			event.keycode == KEY_ENTER
			or event.keycode == KEY_KP_ENTER
			or event.keycode == KEY_SPACE
		):
			_on_take()
		elif event.keycode == KEY_S:
			_on_salvage()


func _skip_to_reveal() -> void:
	if not scrolling:
		return
	# Kill the scroll tween so it doesn't keep moving after we snap.
	if scroll_tween and scroll_tween.is_valid():
		scroll_tween.kill()
	scroll_tween = null
	_set_scroll(ease_distance)
	_on_scroll_done()
