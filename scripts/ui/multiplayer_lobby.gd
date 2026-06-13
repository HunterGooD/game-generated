extends CanvasLayer

# Unified lobby — works for SOLO (1 slot, max_players=1, instant in-room)
# and ONLINE (2-4 slots, Host/Join pre-room then in-room with full class
# selection + ready system).
#
# Sub-states:
#   "preroom"  → Host vs Join chooser (multiplayer only; solo skips here)
#   "inroom"   → Player slots + class picker + Ready + Start

const GAME_WORLD_PATH: String = "res://scenes/world/game_world.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"

const CLASS_ORDER: Array = [
	"barbarian", "rogue", "mage", "druid", "necromancer", "hexen", "stormcaller"
]
const CLASS_COLORS: Dictionary = {
	"barbarian": Color(0.85, 0.25, 0.2, 1),
	"rogue": Color(0.9, 0.55, 0.2, 1),
	"mage": Color(0.7, 0.25, 0.85, 1),
	"druid": Color(0.4, 0.78, 0.32, 1),
	"necromancer": Color(0.55, 0.25, 0.75, 1),
	"hexen": Color(0.92, 0.18, 0.28, 1),
	"stormcaller": Color(0.45, 0.75, 1.0, 1),
}

# How many class buttons fit per row in the lobby picker before wrapping
# to the next line. Picked so the row stays comfortably inside 1080px.
const CLASS_BUTTONS_PER_ROW: int = 4

@export var auto_solo: bool = false

var state: String = "preroom"
var picked_count: int = 4
var local_class: String = ""
var local_ready: bool = false
var peer_classes: Dictionary = {}  # pid -> class_id
var peer_ready: Dictionary = {}  # pid -> bool

# UI refs (built procedurally in _ready).
var bg: TextureRect = null
var preroom_root: Control = null
var inroom_root: Control = null
var status_label: Label = null
var code_label: Label = null
var url_label: Label = null
var copy_code_btn: Button = null
var copy_url_btn: Button = null
var slot_panels: Array = []  # Array[PanelContainer] in P1..P4 order
var class_buttons: Array = []  # Array[Button] for barb/rogue/mage
var ready_btn: Button = null
var start_btn: Button = null
var leave_btn: Button = null
var host_btn: Button = null
var join_btn: Button = null
var join_input: LineEdit = null
var server_input: LineEdit = null
var host_count_buttons: Array = []
var preroom_status: Label = null


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists("res://assets/ui/theme.tres"):
		var t: Theme = load("res://assets/ui/theme.tres") as Theme
		var root_ctrl := Control.new()
		root_ctrl.name = "RootCtrl"
		root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root_ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
		root_ctrl.theme = t
		add_child(root_ctrl)
	else:
		var root_ctrl := Control.new()
		root_ctrl.name = "RootCtrl"
		root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root_ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(root_ctrl)
	_build_background()
	_build_preroom_ui()
	_build_inroom_ui()
	if NetManager:
		NetManager.room_created.connect(_on_room_created)
		NetManager.player_joined.connect(_on_peer_joined)
		NetManager.all_players_joined.connect(_on_all_joined)
		NetManager.player_disconnected.connect(_on_peer_disconnected)
		NetManager.connection_failed.connect(_on_conn_failed)
		NetManager.connected_to_room.connect(_on_ws_open)
		NetManager.message_received.connect(_on_message)
	# Decide initial state from the intent flag set by main_menu before scene change.
	var intent: String = ""
	if NetManager:
		intent = NetManager.lobby_intent
		# Clear so a subsequent return-from-game-over default re-checks.
		NetManager.lobby_intent = ""
	if auto_solo or intent == "solo":
		_enter_solo()
	elif intent == "multiplayer":
		_show_state("preroom")
	elif NetManager and NetManager.is_multiplayer:
		# Coming back from a multiplayer game over — keep the room view.
		_show_state("inroom")
		if code_label and NetManager.room_code != "":
			code_label.text = "ROOM CODE: %s" % NetManager.room_code
		_set_url_label()
	else:
		# No intent set — default to solo (safer than dropping into preroom).
		_enter_solo()


# ─────────────────────────────────────────────────────────────────────────────
# Background
func _build_background() -> void:
	var root_ctrl := get_node("RootCtrl")
	bg = TextureRect.new()
	var bg_paths: Array = [
		"res://assets/ui/title_poster.webp",
		"res://assets/ui/title_poster.png",
		"res://assets/textures/backgrounds/menu_background.webp",
	]
	for p in bg_paths:
		if ResourceLoader.exists(p):
			bg.texture = load(p)
			break
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := UIBuilder.dim_overlay(Color(0, 0, 0, 0.7), false)
	root_ctrl.add_child(dim)


# ─────────────────────────────────────────────────────────────────────────────
# Pre-room UI (Host vs Join)
func _build_preroom_ui() -> void:
	var root_ctrl := get_node("RootCtrl")
	preroom_root = Control.new()
	preroom_root.mouse_filter = Control.MOUSE_FILTER_PASS
	root_ctrl.add_child(preroom_root)
	preroom_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DialogPanel"
	preroom_root.add_child(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -360
	panel.offset_right = 360
	panel.offset_top = -320
	panel.offset_bottom = 320

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)

	var title := _label("СЕТЕВОЙ КООПЕРАТИВ", 34, Color(1, 0.85, 0.5, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	preroom_status = _label("Создайте сессию или присоединитесь", 17, Color(0.85, 0.78, 0.62, 1))
	preroom_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(preroom_status)

	var server_lbl := _label("Адрес сервера", 14, Color(0.9, 0.7, 0.4, 1))
	server_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(server_lbl)

	server_input = LineEdit.new()
	server_input.placeholder_text = "127.0.0.1:7777"
	server_input.text = "127.0.0.1:7777"
	server_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	server_input.custom_minimum_size = Vector2(280, 44)
	server_input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	server_input.add_theme_font_size_override("font_size", 20)
	vb.add_child(server_input)

	# Host count picker.
	var host_lbl := _label("Создать сессию — выберите размер лобби", 14, Color(0.9, 0.7, 0.4, 1))
	host_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(host_lbl)

	var count_row := HBoxContainer.new()
	count_row.alignment = BoxContainer.ALIGNMENT_CENTER
	count_row.add_theme_constant_override("separation", 12)
	vb.add_child(count_row)
	for n in [2, 3, 4]:
		var b := _make_button("%dP" % n, 100, 56, 20)
		b.pressed.connect(_pick_count.bind(n))
		count_row.add_child(b)
		host_count_buttons.append(b)
	_pick_count(4)

	host_btn = _make_button("СОЗДАТЬ ИГРУ", 320, 70, 22)
	host_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	host_btn.pressed.connect(_on_host)
	vb.add_child(host_btn)

	var join_lbl := _label("Или зайдите к другу — введите его код", 14, Color(0.9, 0.7, 0.4, 1))
	join_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(join_lbl)

	join_input = LineEdit.new()
	join_input.placeholder_text = "КОД КОМНАТЫ"
	join_input.max_length = 8
	join_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_input.custom_minimum_size = Vector2(280, 50)
	join_input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	join_input.add_theme_font_size_override("font_size", 28)
	vb.add_child(join_input)

	join_btn = _make_button("ПРИСОЕДИНИТЬСЯ", 320, 70, 22)
	join_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	join_btn.pressed.connect(_on_join)
	vb.add_child(join_btn)

	var back_btn := _make_button("Назад в меню", 220, 50, 16)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(_on_back_to_menu)
	vb.add_child(back_btn)


# ─────────────────────────────────────────────────────────────────────────────
# In-room UI (player slots + class pick + ready + start)
func _build_inroom_ui() -> void:
	var root_ctrl := get_node("RootCtrl")
	inroom_root = Control.new()
	inroom_root.mouse_filter = Control.MOUSE_FILTER_PASS
	inroom_root.visible = false
	root_ctrl.add_child(inroom_root)
	inroom_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	inroom_root.add_child(vb)
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.0
	vb.anchor_bottom = 1.0
	vb.offset_left = -640
	vb.offset_right = 640
	vb.offset_top = 30
	vb.offset_bottom = -30

	var title := _label("ОТРЯД СОБИРАЕТСЯ", 38, Color(1, 0.85, 0.5, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	# Room code row.
	var code_row := HBoxContainer.new()
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	code_row.add_theme_constant_override("separation", 16)
	vb.add_child(code_row)
	code_label = _label("КОД КОМНАТЫ: ----", 32, Color(1.0, 0.4, 0.35, 1))
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_row.add_child(code_label)
	copy_code_btn = _make_button("Скопировать код", 180, 56, 16)
	copy_code_btn.pressed.connect(_copy_code)
	code_row.add_child(copy_code_btn)

	# URL row.
	var url_row := HBoxContainer.new()
	url_row.alignment = BoxContainer.ALIGNMENT_CENTER
	url_row.add_theme_constant_override("separation", 16)
	vb.add_child(url_row)
	url_label = _label("Поделитесь ссылкой с друзьями: …", 14, Color(0.78, 0.72, 0.55, 1))
	url_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	url_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	url_row.add_child(url_label)
	copy_url_btn = _make_button("Скопировать URL", 180, 48, 14)
	copy_url_btn.pressed.connect(_copy_url)
	url_row.add_child(copy_url_btn)

	status_label = _label("Ждём, пока хост начнёт...", 18, Color(0.9, 0.85, 0.6, 1))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(status_label)

	# Slot grid (4 cards horizontally).
	var slot_row := HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", 14)
	vb.add_child(slot_row)
	for i in 4:
		var card := _build_slot_card(i)
		slot_row.add_child(card)
		slot_panels.append(card)

	# Class chooser row.
	var your_lbl := _label("ВАШ ПЕРСОНАЖ", 24, Color(1.0, 0.85, 0.4, 1))
	your_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(your_lbl)

	# Class chooser — multi-row layout so all classes fit on screen.
	var class_box := VBoxContainer.new()
	class_box.alignment = BoxContainer.ALIGNMENT_CENTER
	class_box.add_theme_constant_override("separation", 10)
	vb.add_child(class_box)
	var current_row: HBoxContainer = null
	var idx: int = 0
	for cid in CLASS_ORDER:
		if idx % CLASS_BUTTONS_PER_ROW == 0:
			current_row = HBoxContainer.new()
			current_row.alignment = BoxContainer.ALIGNMENT_CENTER
			current_row.add_theme_constant_override("separation", 18)
			class_box.add_child(current_row)
		var btn := _build_class_btn(cid)
		current_row.add_child(btn)
		class_buttons.append(btn)
		idx += 1

	# Ready + Start + Leave row.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 18)
	vb.add_child(btn_row)
	ready_btn = _make_button("ГОТОВ", 260, 72, 26)
	ready_btn.pressed.connect(_toggle_ready)
	btn_row.add_child(ready_btn)
	start_btn = _make_button("НАЧАТЬ ИГРУ", 320, 72, 26)
	start_btn.disabled = true
	start_btn.pressed.connect(_on_start)
	btn_row.add_child(start_btn)
	leave_btn = _make_button("Выйти", 180, 56, 16)
	leave_btn.pressed.connect(_on_leave)
	btn_row.add_child(leave_btn)


func _build_slot_card(idx: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"InventoryPanel"
	card.custom_minimum_size = Vector2(220, 220)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = "Пусто"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55, 1))
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	name_lbl.add_theme_constant_override("outline_size", 3)
	vb.add_child(name_lbl)
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(140, 140)
	portrait.modulate = Color(0.4, 0.4, 0.4, 0.6)
	vb.add_child(portrait)
	var class_lbl := Label.new()
	class_lbl.name = "ClassName"
	class_lbl.text = "..."
	class_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	class_lbl.add_theme_font_size_override("font_size", 14)
	class_lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62, 1))
	class_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	class_lbl.add_theme_constant_override("outline_size", 2)
	vb.add_child(class_lbl)
	var ready_lbl := Label.new()
	ready_lbl.name = "ReadyBadge"
	ready_lbl.text = ""
	ready_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_lbl.add_theme_font_size_override("font_size", 14)
	ready_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 1))
	ready_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	ready_lbl.add_theme_constant_override("outline_size", 2)
	vb.add_child(ready_lbl)
	card.set_meta("idx", idx)
	return card


func _build_class_btn(class_id: String) -> Button:
	var data: Dictionary = GameManager.get_class_data(class_id) if GameManager else {}
	var display: String = String(data.get("display", class_id.capitalize())).to_upper()
	var col: Color = CLASS_COLORS.get(class_id, Color.WHITE)
	# Blend the class color with yellow for warm, readable labels.
	var label_col: Color = col.lerp(Color(1.0, 0.9, 0.55, 1), 0.4)
	var btn := _make_button(display, 260, 88, 26, label_col)
	btn.pressed.connect(_pick_class.bind(class_id))
	btn.set_meta("class_id", class_id)
	return btn


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 4)
	return l


# ─────────────────────────────────────────────────────────────────────────────
# Button helper — uses the blank stylebox and overlays a yellow Label so the
# button face stays free of baked text. Returns the Button (with the Label as
# child named "TextLabel" so callers can update it via _set_btn_text).
const BTN_BLANK_STYLEBOX: String = "res://assets/ui/btn_blank.tres"


func _make_button(
	text: String,
	w: int = 280,
	h: int = 64,
	font_size: int = 20,
	color: Color = Color(1.0, 0.85, 0.45, 1)
) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(w, h)
	btn.text = ""  # blank — Label child shows the text
	btn.focus_mode = Control.FOCUS_NONE
	# Stylebox override — the blank crimson/gold frame.
	if ResourceLoader.exists(BTN_BLANK_STYLEBOX):
		var sb: StyleBox = load(BTN_BLANK_STYLEBOX) as StyleBox
		if sb:
			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_stylebox_override("hover", sb)
			btn.add_theme_stylebox_override("pressed", sb)
			btn.add_theme_stylebox_override("focus", sb)
			btn.add_theme_stylebox_override("disabled", sb)
	# Yellow label centered on top.
	var lbl := Label.new()
	lbl.name = "TextLabel"
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.03, 0.0, 1))
	lbl.add_theme_constant_override("outline_size", 3)
	btn.add_child(lbl)
	# Anchor the Label to fill the button after it's in the tree.
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Hover modulate (no scale to keep layout stable).
	btn.mouse_entered.connect(func(): btn.modulate = Color(1.15, 1.15, 1.15, 1))
	btn.mouse_exited.connect(func(): btn.modulate = Color(1, 1, 1, 1))
	return btn


func _set_btn_text(btn: Button, text: String) -> void:
	if btn == null:
		return
	var lbl := btn.get_node_or_null("TextLabel") as Label
	if lbl:
		lbl.text = text
	else:
		btn.text = text


func _set_btn_color(btn: Button, color: Color) -> void:
	if btn == null:
		return
	var lbl := btn.get_node_or_null("TextLabel") as Label
	if lbl:
		lbl.add_theme_color_override("font_color", color)


func _show_state(s: String) -> void:
	state = s
	if preroom_root:
		preroom_root.visible = (s == "preroom")
	if inroom_root:
		inroom_root.visible = (s == "inroom")
	if s == "inroom":
		_refresh_inroom()


# ─────────────────────────────────────────────────────────────────────────────
# Solo entry
func _enter_solo() -> void:
	if NetManager:
		NetManager.is_multiplayer = false
		NetManager.local_player_id = 0
		NetManager.max_players = 1
	_show_state("inroom")
	if code_label:
		code_label.text = "ОДИНОЧНЫЙ ЗАБЕГ"
	if url_label:
		url_label.text = "Выберите класс и начните своё нисхождение."
	if copy_code_btn:
		copy_code_btn.visible = false
	if copy_url_btn:
		copy_url_btn.visible = false
	if status_label:
		status_label.text = "Выберите класс и нажмите ГОТОВ, чтобы начать."
	_refresh_inroom()


# ─────────────────────────────────────────────────────────────────────────────
# Pre-room actions
func _apply_server_address() -> bool:
	if NetManager == null or server_input == null:
		return false
	var raw: String = server_input.text.strip_edges()
	if raw == "":
		if preroom_status:
			preroom_status.text = "Введите адрес сервера"
		return false
	if ":" in raw:
		var parts: PackedStringArray = raw.split(":", false, 1)
		NetManager.server_host = parts[0]
		NetManager.server_port = int(parts[1]) if parts.size() > 1 else 7777
	else:
		NetManager.server_host = raw
		NetManager.server_port = 7777
	return true


func _pick_count(n: int) -> void:
	picked_count = n
	for b in host_count_buttons:
		var v := int((b as Button).text.replace("P", "").strip_edges())
		(b as Button).modulate = Color(1.2, 1.05, 0.7, 1) if v == n else Color(0.7, 0.7, 0.75, 1)


func _on_host() -> void:
	if NetManager == null:
		return
	if not _apply_server_address():
		return
	NetManager.is_multiplayer = true
	NetManager.create_room(picked_count)
	if preroom_status:
		preroom_status.text = "Создаём комнату..."
	if host_btn:
		host_btn.disabled = true
	if join_btn:
		join_btn.disabled = true


func _on_join() -> void:
	if NetManager == null:
		return
	if join_input == null:
		return
	if not _apply_server_address():
		return
	var code: String = join_input.text.strip_edges().to_upper()
	if code.length() < 3:
		if preroom_status:
			preroom_status.text = "Введите корректный код комнаты"
		return
	NetManager.is_multiplayer = true
	NetManager.is_host = false
	NetManager.connect_to_room(code)
	NetManager.room_code = code
	if preroom_status:
		preroom_status.text = "Заходим в " + code + "..."
	if host_btn:
		host_btn.disabled = true
	if join_btn:
		join_btn.disabled = true


func _on_back_to_menu() -> void:
	if NetManager:
		NetManager.disconnect_from_room()
	_change_scene(MAIN_SCENE_PATH)


# ─────────────────────────────────────────────────────────────────────────────
# Network receive
func _on_room_created(code: String) -> void:
	# Show the code right away and move to in-room.
	_show_state("inroom")
	if code_label:
		code_label.text = "КОД КОМНАТЫ: %s" % code
	_set_url_label()
	if status_label:
		status_label.text = "Ждём игроков (1/%d)..." % NetManager.max_players


func _on_peer_joined(player_id: int, total: int) -> void:
	# Transition to in-room if a non-host has just been added to the room.
	if state == "preroom":
		_show_state("inroom")
		if code_label:
			code_label.text = "КОД КОМНАТЫ: %s" % NetManager.room_code
		_set_url_label()
	if status_label:
		status_label.text = "Подключено: %d / %d" % [total, NetManager.max_players]
	# Mark this player slot as occupied (even before class picked).
	peer_classes[player_id] = peer_classes.get(player_id, "")
	peer_ready[player_id] = peer_ready.get(player_id, false)
	# Whenever someone new joins, re-broadcast our state so they can see us.
	if local_class != "":
		NetManager.send("lobby_class", {"class_id": local_class})
	if local_ready:
		NetManager.send("lobby_ready", {"ready": local_ready})
	if NetManager.is_host:
		NetManager.send("room_config", {"max_players": NetManager.max_players})
	_refresh_inroom()


func _on_all_joined() -> void:
	if status_label:
		status_label.text = "Все игроки на месте. Выберите класс и нажмите ГОТОВ."


func _on_ws_open() -> void:
	# Transition the joiner into the in-room view as soon as the socket is
	# open, BEFORE the relay's "joined" event fires (which only happens when
	# the room is full). Otherwise non-host peers in an under-full lobby
	# hang on the "Joining..." status forever.
	if state == "preroom" and NetManager and NetManager.is_multiplayer:
		_show_state("inroom")
		if code_label and NetManager.room_code != "":
			code_label.text = "КОД КОМНАТЫ: %s" % NetManager.room_code
		_set_url_label()
		if status_label:
			status_label.text = "Подключено — ждём, пока хост начнёт забег..."


func _on_peer_disconnected(pid: int) -> void:
	if pid < 0:
		# Server / host disconnect — bounce to main menu.
		if status_label:
			status_label.text = "Связь потеряна — возвращаемся в меню..."
		var t := get_tree().create_timer(1.6)
		t.timeout.connect(_on_back_to_menu)
		return
	peer_classes.erase(pid)
	peer_ready.erase(pid)
	_refresh_inroom()


func _on_conn_failed(reason: String) -> void:
	if preroom_status:
		preroom_status.text = "Не удалось подключиться: " + reason
	if host_btn:
		host_btn.disabled = false
	if join_btn:
		join_btn.disabled = false


func _on_message(type: String, msg: Dictionary, from_player: int) -> void:
	match type:
		"lobby_class":
			peer_classes[from_player] = String(msg.get("class_id", ""))
			_refresh_inroom()
		"lobby_ready":
			peer_ready[from_player] = bool(msg.get("ready", false))
			_refresh_inroom()
		"lobby_start":
			_do_start()
		"room_config":
			if NetManager and not NetManager.is_host:
				NetManager.max_players = int(msg.get("max_players", NetManager.max_players))
				_refresh_inroom()


# ─────────────────────────────────────────────────────────────────────────────
# Local actions
func _pick_class(class_id: String) -> void:
	if local_ready:
		# Unreadying when changing class.
		local_ready = false
		if NetManager and NetManager.is_multiplayer:
			NetManager.send("lobby_ready", {"ready": false})
	local_class = class_id
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_ui_menu_click.mp3", -10.0)
	# Broadcast.
	if NetManager and NetManager.is_multiplayer:
		NetManager.send("lobby_class", {"class_id": class_id})
	_refresh_inroom()


func _toggle_ready() -> void:
	if local_class == "":
		if status_label:
			status_label.text = "Сначала выберите класс!"
		return
	local_ready = not local_ready
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_ui_menu_click.mp3", -10.0)
	if NetManager and NetManager.is_multiplayer:
		NetManager.send("lobby_ready", {"ready": local_ready})
	# Solo: pressing READY immediately starts the game.
	if NetManager == null or not NetManager.is_multiplayer:
		if local_ready:
			_do_start()
		return
	_refresh_inroom()


func _on_start() -> void:
	# Host-only — broadcast lobby_start so every peer changes scene together.
	if NetManager == null or not NetManager.is_host:
		return
	if not _all_players_ready():
		if status_label:
			status_label.text = "Сначала все игроки должны нажать ГОТОВ."
		return
	NetManager.send("lobby_start", {})
	_do_start()


func _do_start() -> void:
	if local_class == "" and NetManager and not NetManager.is_multiplayer:
		# Fallback for solo — should not happen but be safe.
		local_class = "mage"
	if GameManager and local_class != "":
		GameManager.choose_class(local_class)
	_change_scene(GAME_WORLD_PATH)


func _on_leave() -> void:
	if NetManager:
		NetManager.disconnect_from_room()
	_change_scene(MAIN_SCENE_PATH)


# ─────────────────────────────────────────────────────────────────────────────
# UI refresh
func _refresh_inroom() -> void:
	if slot_panels.is_empty():
		return
	var is_solo: bool = NetManager == null or not NetManager.is_multiplayer
	var visible_slots: int = 1 if is_solo else (NetManager.max_players if NetManager else 4)
	for i in slot_panels.size():
		var card: PanelContainer = slot_panels[i]
		card.visible = (i < visible_slots)
		if not card.visible:
			continue
		var name_lbl: Label = card.find_child("Name", true, false) as Label
		var portrait: TextureRect = card.find_child("Portrait", true, false) as TextureRect
		var class_lbl: Label = card.find_child("ClassName", true, false) as Label
		var ready_lbl: Label = card.find_child("ReadyBadge", true, false) as Label
		var occupied: bool = (
			(i == (NetManager.local_player_id if NetManager else 0))
			or peer_classes.has(i)
			or is_solo
		)
		if not occupied:
			if name_lbl:
				name_lbl.text = "Пусто"
			if portrait:
				portrait.texture = null
				portrait.modulate = Color(0.4, 0.4, 0.4, 0.6)
			if class_lbl:
				class_lbl.text = "Ожидание..."
			if ready_lbl:
				ready_lbl.text = ""
			continue
		var is_local: bool = i == (NetManager.local_player_id if NetManager else 0)
		if name_lbl:
			name_lbl.text = "И%d (вы)" % (i + 1) if is_local else "И%d" % (i + 1)
		var cid: String = local_class if is_local else String(peer_classes.get(i, ""))
		if cid != "":
			var data: Dictionary = GameManager.get_class_data(cid) if GameManager else {}
			if portrait:
				var ppath: String = String(data.get("portrait", ""))
				if ppath != "" and ResourceLoader.exists(ppath):
					portrait.texture = load(ppath) as Texture2D
				portrait.modulate = Color(1, 1, 1, 1)
			if class_lbl:
				class_lbl.text = String(data.get("display", cid))
				class_lbl.add_theme_color_override("font_color", CLASS_COLORS.get(cid, Color.WHITE))
		else:
			if portrait:
				portrait.texture = null
				portrait.modulate = Color(0.4, 0.4, 0.4, 0.6)
			if class_lbl:
				class_lbl.text = "Выбирает..."
		var r: bool = local_ready if is_local else bool(peer_ready.get(i, false))
		if ready_lbl:
			ready_lbl.text = "✓ ГОТОВ" if r else ""

	# Highlight selected class button.
	for b in class_buttons:
		var btn := b as Button
		var cid := String(btn.get_meta("class_id", ""))
		btn.modulate = Color(1.3, 1.1, 0.8, 1) if cid == local_class else Color(1, 1, 1, 1)

	# Ready button text.
	if ready_btn:
		_set_btn_text(ready_btn, "НЕ ГОТОВ" if local_ready else "ГОТОВ")
		_set_btn_color(
			ready_btn, Color(0.4, 1.0, 0.5, 1) if local_ready else Color(1.0, 0.85, 0.45, 1)
		)

	# Start button — only visible/enabled for host when everyone is ready.
	if start_btn:
		if is_solo:
			start_btn.visible = false
		else:
			start_btn.visible = (NetManager != null and NetManager.is_host)
			start_btn.disabled = not _all_players_ready()


func _all_players_ready() -> bool:
	if NetManager == null or not NetManager.is_multiplayer:
		return local_ready
	# Local player.
	if not local_ready:
		return false
	# Every other connected peer (we have lobby_class entry for them) must be ready.
	for pid in peer_classes.keys():
		if int(pid) == NetManager.local_player_id:
			continue
		if not bool(peer_ready.get(pid, false)):
			return false
		if String(peer_classes.get(pid, "")) == "":
			return false
	return true


# ─────────────────────────────────────────────────────────────────────────────
# URL / Copy helpers
func _set_url_label() -> void:
	var url: String = _get_current_url()
	if url_label:
		url_label.text = (
			"Друзья открывают: %s   (Выбрать → Присоединиться → %s)"
			% [url, NetManager.room_code if NetManager else "----"]
		)


func _get_current_url() -> String:
	if OS.has_feature("web"):
		var s: Variant = JavaScriptBridge.eval("window.location.href", true)
		var raw: String = String(s) if s != null else ""
		# Strip query / hash so the shareable URL is clean.
		var q: int = raw.find("?")
		if q > 0:
			raw = raw.substr(0, q)
		var h: int = raw.find("#")
		if h > 0:
			raw = raw.substr(0, h)
		if raw != "":
			return raw
		return "адрес этой игры"
	return "адрес этой игры"


func _copy_code() -> void:
	if NetManager == null:
		return
	var code: String = NetManager.room_code
	if code == "":
		return
	# Web: DisplayServer.clipboard_set is restricted to input callbacks only,
	# so use the JS bridge — it's allowed from any button.pressed callback.
	if OS.has_feature("web"):
		var js := 'try { navigator.clipboard.writeText("%s"); } catch (e) {}' % code
		JavaScriptBridge.eval(js)
	else:
		DisplayServer.clipboard_set(code)
	if status_label:
		status_label.text = "Код скопирован — поделитесь с друзьями!"


func _copy_url() -> void:
	var url: String = _get_current_url()
	if OS.has_feature("web"):
		var js := 'try { navigator.clipboard.writeText("%s"); } catch (e) {}' % url.c_escape()
		JavaScriptBridge.eval(js)
	else:
		DisplayServer.clipboard_set(url)
	if status_label:
		status_label.text = "Ссылка скопирована — отправьте её другу!"


# ─────────────────────────────────────────────────────────────────────────────
# Scene change helper
func _change_scene(path: String) -> void:
	var ls = get_tree().root.get_node_or_null("LoadingScreen")
	if ls and ls.has_method("preload_and_change_scene"):
		ls.call("preload_and_change_scene", path)
	elif ls and ls.has_method("change_scene"):
		ls.call("change_scene", path)
	else:
		get_tree().change_scene_to_file(path)
