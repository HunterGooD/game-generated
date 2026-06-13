extends CanvasLayer

# Class selector overlay — shown by game_world if no class has been chosen yet.
# Once a class is picked, this layer is freed and gameplay begins.

signal class_chosen(class_id: String)

@export var card_row: HBoxContainer
@export var title: Label
@export var subtitle: Label

var selected_class: String = ""


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_build_cards()


const CARDS_PER_ROW: int = 4


func _build_cards() -> void:
	if card_row == null:
		return
	for c in card_row.get_children():
		c.queue_free()
	# Wrap into a vertical stack of rows so 7+ classes fit on screen.
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 14)
	card_row.add_child(stack)
	var current_row: HBoxContainer = null
	var idx: int = 0
	for cid in GameManager.class_order():
		if idx % CARDS_PER_ROW == 0:
			current_row = HBoxContainer.new()
			current_row.alignment = BoxContainer.ALIGNMENT_CENTER
			current_row.add_theme_constant_override("separation", 14)
			stack.add_child(current_row)
		var data: Dictionary = GameManager.get_class_data(cid)
		var card := _build_card(cid, data)
		current_row.add_child(card)
		idx += 1


func _build_card(class_id: String, data: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InventoryPanel"
	# Reduced from 380×600 so 4 cards per row fit at 1080p, with a second
	# row picking up the rest of the class roster.
	panel.custom_minimum_size = Vector2(280, 460)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(v)

	# Class name.
	var name_label := Label.new()
	name_label.text = String(data.get("display", class_id.capitalize()))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color(1, 0.9, 0.7, 1))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	name_label.add_theme_constant_override("outline_size", 5)
	name_label.add_theme_font_size_override("font_size", 30)
	v.add_child(name_label)

	# Primary attribute tag.
	var prim_label := Label.new()
	prim_label.text = "Основное: " + String(data.get("primary_label", ""))
	prim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prim_label.add_theme_color_override("font_color", Color(0.95, 0.6, 0.4, 1))
	prim_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	prim_label.add_theme_constant_override("outline_size", 4)
	prim_label.add_theme_font_size_override("font_size", 16)
	v.add_child(prim_label)

	# Portrait.
	var portrait_path: String = String(data.get("portrait", ""))
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		var p_rect := TextureRect.new()
		p_rect.texture = load(portrait_path) as Texture2D
		p_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		p_rect.custom_minimum_size = Vector2(200, 200)
		v.add_child(p_rect)

	# Description.
	var desc := Label.new()
	desc.text = String(data.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62, 1))
	desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	desc.add_theme_constant_override("outline_size", 3)
	desc.add_theme_font_size_override("font_size", 14)
	desc.custom_minimum_size = Vector2(0, 56)
	v.add_child(desc)

	# Stat block.
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 2)
	v.add_child(stats)
	var base: Dictionary = data.get("base", {})
	_add_stat_row(stats, "Здоровье", str(int(base.get("max_hp", 0))))
	_add_stat_row(stats, "Мана", str(int(base.get("max_mana", 0))))
	_add_stat_row(stats, "Урон", str(int(base.get("damage", 0))))
	_add_stat_row(stats, "Скорость", "%d%%" % int(float(base.get("move_speed", 200.0)) / 2.2))
	_add_stat_row(stats, "Крит", "%d%%" % int(float(base.get("crit_chance", 0.0)) * 100.0))
	_add_stat_row(stats, "Сила", str(int(base.get("strength", 0))))
	_add_stat_row(stats, "Ловкость", str(int(base.get("dexterity", 0))))
	_add_stat_row(stats, "Интеллект", str(int(base.get("intelligence", 0))))

	# Choose button.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	v.add_child(spacer)

	var btn := Button.new()
	btn.text = "Выбрать"
	btn.custom_minimum_size = Vector2(220, 64)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(1, 0.92, 0.7, 1))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	btn.add_theme_constant_override("outline_size", 4)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var btn_normal_path := "res://assets/ui/btn_choose.tres"
	if ResourceLoader.exists(btn_normal_path):
		var sb: StyleBox = load(btn_normal_path) as StyleBox
		if sb:
			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_stylebox_override("hover", sb)
			btn.add_theme_stylebox_override("pressed", sb)
			btn.add_theme_stylebox_override("focus", sb)
			btn.add_theme_stylebox_override("disabled", sb)
	btn.pressed.connect(_on_choose.bind(class_id))
	btn.mouse_entered.connect(func(): btn.modulate = Color(1.15, 1.15, 1.15, 1))
	btn.mouse_exited.connect(func(): btn.modulate = Color(1, 1, 1, 1))
	v.add_child(btn)

	return panel


func _add_stat_row(parent: VBoxContainer, label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_font_size_override("font_size", 15)
	row.add_child(l)

	var v := Label.new()
	v.text = value_text
	v.add_theme_color_override("font_color", Color(1, 0.92, 0.6, 1))
	v.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	v.add_theme_constant_override("outline_size", 3)
	v.add_theme_font_size_override("font_size", 15)
	row.add_child(v)


func _on_choose(class_id: String) -> void:
	selected_class = class_id
	if GameManager:
		GameManager.choose_class(class_id)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_ui_menu_click.mp3", -8.0)
	# Broadcast to peers so their remote_player puppets pick the right sprite.
	if NetManager and NetManager.is_multiplayer:
		var world := get_tree().current_scene
		if world:
			var sync := world.get_node_or_null("NetSync")
			if sync and sync.has_method("broadcast_local_class"):
				sync.call("broadcast_local_class", class_id)
	class_chosen.emit(class_id)
	# Resume game and remove overlay.
	var t := get_tree().create_timer(0.05)
	t.timeout.connect(_finish)


func _finish() -> void:
	get_tree().paused = false
	queue_free()
