class_name TalentPanel
extends CanvasLayer

# In-run talent tree panel (WoW-style): one column per branch, nodes in tiers
# top-to-bottom, the next tier unlocks at POINTS_PER_TIER points spent in that
# branch. Spending goes through GameManager.spend_talent_point (validation +
# effect application live there). Code-built overlay like rest_choice.
#
# Co-op invariant: NEVER pauses the tree — you pick talents while the fight
# keeps running (same as the character sheet / merchant).

signal closed

const COLUMN_WIDTH: int = 340
const TRANSFORM_COLOR := Color(1.0, 0.45, 0.35)
const ULT_COLOR := Color(0.6, 0.85, 1.0)
const STAT_NAMES := {"strength": "Str", "dexterity": "Dex", "intelligence": "Int"}
# TODO(art): dedicated str/dex/int icons; themed gear placeholders for now.
const STAT_ICONS := {
	"strength": "res://assets/sprites/items/gear_chest_plate.png",
	"dexterity": "res://assets/sprites/items/gear_boots_greaves.png",
	"intelligence": "res://assets/sprites/items/crystal_blue.png",
}

var _points_label: Label = null
var _stats_label: Label = null
var _columns_row: HBoxContainer = null


func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_chrome()
	_rebuild()
	if GameManager:
		GameManager.talents_changed.connect(_rebuild)
		GameManager.player_stats_changed.connect(_refresh_footer)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_talents"):
		_close()
		get_viewport().set_input_as_handled()


func _build_chrome() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InventoryPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -560
	panel.offset_right = 560
	panel.offset_top = -330
	panel.offset_bottom = 330
	dim.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var title := Label.new()
	title.text = "Таланты — %s   [T]" % _class_display()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.92, 0.65))
	v.add_child(title)

	_columns_row = HBoxContainer.new()
	_columns_row.add_theme_constant_override("separation", 14)
	_columns_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_columns_row)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	v.add_child(footer)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 20)
	_points_label.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	footer.add_child(_points_label)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 16)
	_stats_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62))
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_stats_label)

	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.custom_minimum_size = Vector2(140, 40)
	close_btn.pressed.connect(_close)
	footer.add_child(close_btn)


func _class_display() -> String:
	if GameManager == null:
		return "?"
	return String(GameManager.get_class_data().get("display", GameManager.player_class))


func _rebuild() -> void:
	if _columns_row == null or GameManager == null:
		return
	for c in _columns_row.get_children():
		c.queue_free()
	var cls: String = String(GameManager.player_class)
	var branches: Array = TalentTrees.branches_for(cls)
	if branches.is_empty():
		var empty := Label.new()
		empty.text = "У этого класса пока нет дерева талантов."
		_columns_row.add_child(empty)
	for b in branches.size():
		_columns_row.add_child(_build_branch_column(cls, b, branches[b]))
	_refresh_footer()


func _build_branch_column(cls: String, branch_index: int, branch: Dictionary) -> Control:
	var col_panel := PanelContainer.new()
	col_panel.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	col_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	col_panel.add_child(v)

	var spent: int = TalentTrees.points_in_branch(cls, branch_index, GameManager.talents)
	var header := Label.new()
	header.text = (
		"%s  (%d)  •  %s"
		% [String(branch["name"]), spent, String(STAT_NAMES.get(String(branch["stat"]), "?"))]
	)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 19)
	header.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	v.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var tiers: Array = branch["tiers"]
	for t in tiers.size():
		if t > 0:
			var gate := Label.new()
			var unlocked: bool = TalentTrees.tier_unlocked(cls, branch_index, t, GameManager.talents)
			var req: int = TalentTrees.POINTS_PER_TIER * t
			gate.text = "━━ tier %d %s ━━" % [t + 1, "" if unlocked else "(%d pts needed)" % req]
			gate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			gate.add_theme_font_size_override("font_size", 13)
			gate.add_theme_color_override(
				"font_color", Color(0.6, 0.75, 0.5) if unlocked else Color(0.5, 0.45, 0.4)
			)
			list.add_child(gate)
		for node in tiers[t]:
			list.add_child(_build_node_button(node))

	# Ult cluster lives in the branch of the CHOSEN ascension.
	if String(GameManager.player_spec_path) == String(branch["id"]):
		var ult_head := Label.new()
		ult_head.text = "━━ Awakening ━━"
		ult_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ult_head.add_theme_font_size_override("font_size", 13)
		ult_head.add_theme_color_override("font_color", ULT_COLOR)
		list.add_child(ult_head)
		for node in TalentTrees.ULT_NODES:
			list.add_child(_build_node_button(node))

	return col_panel


func _build_node_button(node: Dictionary) -> Button:
	var node_id: String = String(node["id"])
	var rank: int = int(GameManager.talents.get(node_id, 0))
	var free_ranks: int = TalentTrees.set_grant_ranks(node_id)
	var max_r: int = TalentTrees.max_ranks(node)
	var kind: String = String(node["kind"])

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 44)
	btn.clip_text = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var rank_text: String = ("%d/%d" % [rank, max_r]) if max_r >= 0 else str(rank)
	if free_ranks > 0:
		rank_text += " +%d" % free_ranks
	btn.text = "%s   [%s]" % [TalentTrees.display_name(node), rank_text]
	btn.add_theme_font_size_override("font_size", 15)
	# Per-node icon so the player reads the tree at a glance: skill icon for
	# modifier/transform/ult nodes, themed placeholders for stat/perk nodes.
	var node_icon: Texture2D = _node_icon(node, kind)
	if node_icon != null:
		btn.icon = node_icon
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 30)
		btn.add_theme_constant_override("h_separation", 8)
	match kind:
		"transform":
			btn.add_theme_color_override("font_color", TRANSFORM_COLOR)
		"ult":
			btn.add_theme_color_override("font_color", ULT_COLOR)
		"stat":
			btn.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
		"perk":
			btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))

	var reason: String = GameManager.talent_block_reason(node_id)
	btn.disabled = reason != ""
	btn.pressed.connect(_on_node_pressed.bind(node_id))
	btn.mouse_entered.connect(_on_node_hover.bind(node, reason))
	btn.mouse_exited.connect(_on_node_exit)
	return btn


func _node_icon(node: Dictionary, kind: String) -> Texture2D:
	match kind:
		"stat":
			return _load_icon(STAT_ICONS.get(String(node.get("stat", "")), ""))
		"perk":
			return _load_icon("res://assets/sprites/items/rune_circle.png")
		"ult":
			return _load_icon("res://assets/sprites/items/crystal_purple.png")
	# modifier / transform — the affected slot's skill icon.
	var slot: int = TalentTrees.node_slot(node)
	if slot >= 0:
		var tex: Texture2D = RewardData.slot_icon(slot)
		if tex != null:
			return tex
	return _load_icon("res://assets/sprites/items/crystal_blue.png")


func _load_icon(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _on_node_pressed(node_id: String) -> void:
	if GameManager.spend_talent_point(node_id):
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_ui_menu_click.mp3", -8.0)
		# talents_changed → _rebuild repaints ranks/gates/disabled states.


func _on_node_hover(node: Dictionary, reason: String) -> void:
	if TooltipManager == null:
		return
	var kind: String = String(node["kind"])
	var meta: String = ""
	var slot: int = TalentTrees.node_slot(node)
	if slot >= 0:
		meta = "Влияет на: %s" % RewardData.slot_name(slot)
	if reason != "":
		meta += ("    " if meta != "" else "") + reason
	var rarity: String = "unique" if kind == "transform" else "common"
	TooltipManager.show_tooltip(
		TalentTrees.display_name(node), rarity, TalentTrees.display_desc(node), meta
	)


func _on_node_exit() -> void:
	if TooltipManager:
		TooltipManager.hide_tooltip()


func _refresh_footer() -> void:
	if GameManager == null or _points_label == null:
		return
	_points_label.text = "Очки: %d" % GameManager.talent_points
	_stats_label.text = (
		"Сила %d  •  Лвк %d  •  Инт %d      сброс у любого костра"
		% [
			GameManager.get_effective_strength(),
			GameManager.get_effective_dexterity(),
			GameManager.get_effective_intelligence(),
		]
	)


func _close() -> void:
	if TooltipManager:
		TooltipManager.hide_tooltip()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_button_click.mp3", -8.0)
	closed.emit()
	queue_free()
