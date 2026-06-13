class_name HubCoopPanel
extends CanvasLayer

## Co-op NPC dialog shown at the hub "summoning beacon". The host CREATES a lobby
## (picks party size 2–MAX) and a "Лобби <CODE>" banner appears at the top of the
## hub; friends pick JOIN, enter the code, and connect. Party members then walk the
## hub together and step into the Portal — the host launches the run for everyone.
##
## Code-built overlay (same pattern as hero_select). It must NOT pause the tree —
## the net transport/sync run on PROCESS_MODE_ALWAYS and a paused peer desyncs the
## party (see the co-op pause/transport invariant). It only captures the mouse.

signal closed
signal leave_requested

const PANEL_W: float = 560.0

var _state: String = "choose"  # choose | create | join | connected
var _busy: bool = false

# UI refs
var _content: VBoxContainer = null
var _status: Label = null
var _size_spin: SpinBox = null
var _server_edit: LineEdit = null
var _code_edit: LineEdit = null


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_shell()
	if NetManager:
		NetManager.room_created.connect(_on_room_created)
		NetManager.connected_to_room.connect(_on_connected)
		NetManager.player_joined.connect(_on_player_joined)
		NetManager.player_disconnected.connect(_on_player_disconnected)
		NetManager.connection_failed.connect(_on_connection_failed)
	# If we re-open the NPC while already in a lobby, jump straight to the
	# connected view (Leave / Close) rather than offering Create/Join again.
	if NetManager and NetManager.is_multiplayer and NetManager.room_code != "":
		_show_connected()
	else:
		_show_choose()


# ─────────────────────────────────────────────────────────────────────────────
func _build_shell() -> void:
	var dim := UIBuilder.dim_overlay(Color(0.02, 0.02, 0.05, 0.82))
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DialogPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_W * 0.5
	panel.offset_right = PANEL_W * 0.5
	panel.offset_top = -300
	panel.offset_bottom = 300
	# Fallback frame so it reads even without the DialogPanel variation.
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.10, 0.09, 0.13, 0.98)
	frame.set_corner_radius_all(14)
	frame.set_border_width_all(2)
	frame.border_color = Color(0.85, 0.66, 0.36, 0.7)
	frame.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", frame)
	dim.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	panel.add_child(outer)

	var title := _label("СБОР ОТРЯДА", 32, Color(1, 0.85, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	_status = _label("Создайте лобби или присоединитесь к другу.", 16, Color(0.85, 0.78, 0.62))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PANEL_W - 60, 0)
	outer.add_child(_status)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(_content)


func _clear_content() -> void:
	for c in _content.get_children():
		c.queue_free()


# ─────────────────────────────────────────────────────────────────────────────
# Screens
func _show_choose() -> void:
	_state = "choose"
	_clear_content()
	_status.text = "Создайте лобби или присоединитесь к другу."
	var create_btn := _big_button("СОЗДАТЬ ЛОББИ", Color(0.95, 0.7, 0.4))
	create_btn.pressed.connect(_show_create)
	_content.add_child(create_btn)
	var join_btn := _big_button("ПРИСОЕДИНИТЬСЯ", Color(0.5, 0.8, 1.0))
	join_btn.pressed.connect(_show_join)
	_content.add_child(join_btn)
	_content.add_child(_close_button("Закрыть"))


func _show_create() -> void:
	_state = "create"
	_clear_content()
	_status.text = "Сколько героев в отряде? (%d–%d)" % [_min_players(), _max_players()]

	_content.add_child(_server_field())

	var size_row := HBoxContainer.new()
	size_row.alignment = BoxContainer.ALIGNMENT_CENTER
	size_row.add_theme_constant_override("separation", 12)
	size_row.add_child(_label("Размер лобби", 16, Color(0.9, 0.7, 0.4)))
	_size_spin = SpinBox.new()
	_size_spin.min_value = _min_players()
	_size_spin.max_value = _max_players()
	_size_spin.step = 1
	_size_spin.value = clamp(4, _min_players(), _max_players())
	_size_spin.custom_minimum_size = Vector2(110, 44)
	size_row.add_child(_size_spin)
	_content.add_child(size_row)

	var go := _big_button("СОЗДАТЬ", Color(0.95, 0.7, 0.4))
	go.pressed.connect(_on_create_pressed)
	_content.add_child(go)
	_content.add_child(_back_button())


func _show_join() -> void:
	_state = "join"
	_clear_content()
	_status.text = "Введите код лобби друга."

	_content.add_child(_server_field())

	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "КОД ЛОББИ"
	_code_edit.max_length = 8
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.custom_minimum_size = Vector2(300, 52)
	_code_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_code_edit.add_theme_font_size_override("font_size", 28)
	_code_edit.text_submitted.connect(func(_t): _on_join_pressed())
	_content.add_child(_code_edit)

	var go := _big_button("ВОЙТИ", Color(0.5, 0.8, 1.0))
	go.pressed.connect(_on_join_pressed)
	_content.add_child(go)
	_content.add_child(_back_button())


func _show_connected() -> void:
	_state = "connected"
	_clear_content()
	_busy = false
	var code: String = NetManager.room_code if NetManager else ""
	_status.text = "Лобби %s\nИдите к Порталу — хост откроет врата для всех." % code

	var count_lbl := _label(_party_text(), 18, Color(0.9, 0.85, 0.6))
	count_lbl.name = "PartyCount"
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(count_lbl)

	var copy := _big_button("Скопировать код", Color(0.85, 0.78, 0.62))
	copy.pressed.connect(_copy_code)
	_content.add_child(copy)

	var leave := _big_button("Покинуть лобби", Color(1.0, 0.45, 0.4))
	leave.pressed.connect(
		func():
			leave_requested.emit()
			_close()
	)
	_content.add_child(leave)
	_content.add_child(_close_button("Свернуть"))


func _party_text() -> String:
	if NetManager == null:
		return ""
	var c: int = max(1, NetManager.connected_players)
	return "В отряде: %d / %d" % [c, NetManager.max_players]


# ─────────────────────────────────────────────────────────────────────────────
# Actions
func _on_create_pressed() -> void:
	if _busy or NetManager == null:
		return
	if not _apply_server():
		return
	_busy = true
	_status.text = "Создание лобби..."
	NetManager.is_multiplayer = true
	NetManager.create_room(int(_size_spin.value))


func _on_join_pressed() -> void:
	if _busy or NetManager == null or _code_edit == null:
		return
	if not _apply_server():
		return
	var code: String = _code_edit.text.strip_edges().to_upper()
	if code.length() < 3:
		_status.text = "Введите корректный код лобби."
		return
	_busy = true
	_status.text = "Подключение к %s..." % code
	NetManager.is_multiplayer = true
	NetManager.is_host = false
	NetManager.connect_to_room(code)
	NetManager.room_code = code


func _apply_server() -> bool:
	if NetManager == null or _server_edit == null:
		return false
	var raw: String = _server_edit.text.strip_edges()
	if raw == "":
		raw = "127.0.0.1:7777"
	if ":" in raw:
		var parts: PackedStringArray = raw.split(":", false, 1)
		NetManager.server_host = parts[0]
		NetManager.server_port = int(parts[1]) if parts.size() > 1 else 7777
	else:
		NetManager.server_host = raw
		NetManager.server_port = 7777
	return true


func _copy_code() -> void:
	if NetManager == null or NetManager.room_code == "":
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			'try { navigator.clipboard.writeText("%s"); } catch (e) {}' % NetManager.room_code
		)
	else:
		DisplayServer.clipboard_set(NetManager.room_code)
	_status.text = "Код скопирован — отправьте друзьям!"


# ─────────────────────────────────────────────────────────────────────────────
# Net callbacks
func _on_room_created(_code: String) -> void:
	_show_connected()


func _on_connected() -> void:
	# Joiner: socket open. Move to the connected view.
	if _state != "connected":
		_show_connected()


func _on_player_joined(_pid: int, _total: int) -> void:
	if _state == "connected":
		var lbl := _content.get_node_or_null("PartyCount") as Label
		if lbl:
			lbl.text = _party_text()


func _on_player_disconnected(pid: int) -> void:
	if pid < 0:
		_status.text = "Соединение потеряно."
		return
	if _state == "connected":
		var lbl := _content.get_node_or_null("PartyCount") as Label
		if lbl:
			lbl.text = _party_text()


func _on_connection_failed(reason: String) -> void:
	_busy = false
	_status.text = "Не удалось подключиться: " + reason


# ─────────────────────────────────────────────────────────────────────────────
# Widgets
func _min_players() -> int:
	return int(NetManager.MIN_PLAYERS) if NetManager else 2


func _max_players() -> int:
	return int(NetManager.MAX_PLAYERS) if NetManager else 10


func _server_field() -> Control:
	var row := VBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	var lbl := _label("Адрес сервера", 13, Color(0.78, 0.72, 0.55))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	_server_edit = LineEdit.new()
	_server_edit.text = "%s:%d" % [NetManager.server_host, NetManager.server_port] if NetManager else "127.0.0.1:7777"
	_server_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_server_edit.custom_minimum_size = Vector2(300, 40)
	_server_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(_server_edit)
	return row


func _big_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(360, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 22)
	for sname in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.darkened(0.55) if sname != "hover" else color.darkened(0.4)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(2)
		sb.border_color = color
		sb.set_content_margin_all(10)
		b.add_theme_stylebox_override(sname, sb)
	b.add_theme_color_override("font_color", color.lightened(0.4))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	return b


func _back_button() -> Button:
	var b := _big_button("Назад", Color(0.7, 0.7, 0.78))
	b.custom_minimum_size = Vector2(200, 48)
	b.pressed.connect(_show_choose)
	return b


func _close_button(text: String) -> Button:
	var b := _big_button(text, Color(0.7, 0.7, 0.78))
	b.custom_minimum_size = Vector2(200, 48)
	b.pressed.connect(_close)
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	return l


# ─────────────────────────────────────────────────────────────────────────────
func _on_dim_input(event: InputEvent) -> void:
	# Click on the dimmed margin (outside the panel) closes — but never mid-action.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not _busy:
		_close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
