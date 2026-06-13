class_name SocketDot
extends Control

# Кружок-гнездо поверх предмета в листе персонажа. Принимает самоцветы из
# сумки и других гнёзд (drag&drop), отдаёт свой камень перетаскиванием;
# ПКМ — повернуть камень на 90° (связи пересчитываются).

var owner_item: ItemInstance = null
var idx: int = -1
var sheet: Node = null
var world_faces: Array = []  # пусто = пустое гнездо


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_exit)


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5
	draw_circle(c, radius, Color(0.05, 0.04, 0.06, 0.72))
	if world_faces.is_empty():
		draw_arc(c, radius - 1.5, 0.0, TAU, 24, Color(0.82, 0.74, 0.55, 0.95), 2.0, true)
	else:
		GemFaceIcon.draw_shape(self, Rect2(Vector2.ZERO, size).grow(-2.0), world_faces)
		draw_arc(c, radius - 1.0, 0.0, TAU, 24, Color(0.9, 0.88, 0.8, 0.8), 1.5, true)


func _gem_entry() -> Dictionary:
	if owner_item == null:
		return {}
	return owner_item.socket_entry(idx)


func _get_drag_data(_pos: Vector2) -> Variant:
	var e: Dictionary = _gem_entry()
	if e.is_empty() or sheet == null:
		return null
	var preview := GemFaceIcon.new()
	preview.faces = SocketGems.entry_world_faces(e)
	preview.custom_minimum_size = Vector2(40, 40)
	preview.size = Vector2(40, 40)
	set_drag_preview(preview)
	return {"socket_item": owner_item, "socket_idx": idx, "gem_id": String(e.get("gem", ""))}


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or owner_item == null:
		return false
	var d := data as Dictionary
	if d.get("socket_item") is ItemInstance:
		return not (d["socket_item"] == owner_item and int(d.get("socket_idx", -1)) == idx)
	var it = d.get("item")
	return it is ItemInstance and (it as ItemInstance).is_gem()


func _drop_data(_pos: Vector2, data: Variant) -> void:
	if InventorySystem == null:
		return
	var d := data as Dictionary
	if d.get("socket_item") is ItemInstance:
		InventorySystem.move_socket_gem(
			d["socket_item"] as ItemInstance, int(d.get("socket_idx", -1)), owner_item, idx
		)
	else:
		InventorySystem.socket_gem(owner_item, idx, d.get("item") as ItemInstance)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not _gem_entry().is_empty():
		if InventorySystem:
			InventorySystem.rotate_socket_gem(owner_item, idx)
		accept_event()


func _on_hover() -> void:
	if TooltipManager == null:
		return
	var e: Dictionary = _gem_entry()
	if e.is_empty():
		TooltipManager.show_tooltip(
			"Гнездо",
			"common",
			"Перетащите сюда самоцвет из сумки.",
			"Пустое гнездо",
		)
		return
	var gid: String = String(e.get("gem", ""))
	TooltipManager.show_tooltip(
		SocketGems.display_name(gid),
		SocketGems.rarity_of(gid),
		(
			SocketGems.describe(gid, int(e.get("rot", 0)), e.get("faces", []))
			+ "\nПКМ — повернуть. Перетащите, чтобы вынуть."
		),
		"Самоцвет в гнезде",
	)


func _on_exit() -> void:
	if TooltipManager:
		TooltipManager.hide_tooltip()
