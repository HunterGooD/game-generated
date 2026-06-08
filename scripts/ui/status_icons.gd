class_name StatusIcons
extends Control

# Reusable row of status squares with a clock-dial countdown (status_dial.gdshader).
# Each entry is a placeholder tinted square now; an art Texture can replace the
# square later by setting `use_icon`/an icon TextureRect — the dial stays on top.
#
# Used in two places: the player's HUD bar (bigger, with letter labels) and above
# each enemy (small, no labels). Lays squares out manually (left→right, optionally
# centered) so it works the same whether parented under a Control or a Node2D.
#
# Feed it `update_statuses([...])`, where each item is:
#   { id, label:String, color:Color, progress:float(0..1 remaining) }

const DIAL_SHADER := preload("res://assets/shaders/status_dial.gdshader")

@export var icon_size: float = 28.0
@export var gap: float = 4.0
@export var show_labels: bool = true
@export var centered: bool = false  # true: row centered on local x=0 (enemy use)

var _pool: Array = []  # [{root:Control, mat:ShaderMaterial, label:Label}]


func update_statuses(list: Array) -> void:
	while _pool.size() < list.size():
		_pool.append(_make_icon())
	var visible_count: int = list.size()
	var total_w: float = float(visible_count) * icon_size + max(0.0, float(visible_count - 1)) * gap
	var start_x: float = -total_w * 0.5 if centered else 0.0
	for i in _pool.size():
		var entry: Dictionary = _pool[i]
		var root: Control = entry["root"]
		if i < visible_count:
			var s: Dictionary = list[i]
			root.visible = true
			root.position = Vector2(start_x + float(i) * (icon_size + gap), 0.0)
			var mat: ShaderMaterial = entry["mat"]
			mat.set_shader_parameter("tint", s.get("color", Color(0.1, 0.1, 0.12)))
			mat.set_shader_parameter("progress", clampf(float(s.get("progress", 1.0)), 0.0, 1.0))
			var label: Label = entry["label"]
			if label:
				label.text = String(s.get("label", ""))
		else:
			root.visible = false


func _make_icon() -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(icon_size, icon_size)
	root.size = Vector2(icon_size, icon_size)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = DIAL_SHADER
	rect.material = mat
	root.add_child(rect)

	var label: Label = null
	if show_labels:
		label = Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", int(icon_size * 0.42))
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		label.add_theme_constant_override("outline_size", 3)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(label)

	return {"root": root, "mat": mat, "label": label}
