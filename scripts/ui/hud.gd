extends CanvasLayer

# Phase 3 HUD — stats top-left, gold top-right, hotbar bottom with XP bar above.
# Character sheet toggled with Tab.

@export var hp_bar: ProgressBar
@export var mp_bar: ProgressBar
@export var hp_label: Label
@export var mp_label: Label
@export var gold_label: Label
@export var level_label: Label
@export var class_label: Label
@export var hint_label: Label
@export var hotbar: HBoxContainer
@export var xp_fill: ColorRect
@export var xp_bg: ColorRect
@export var xp_label: Label
@export var wave_label: Label
@export var character_sheet: CanvasLayer

const XP_SHADER: Shader = preload("res://assets/ui/xp_bar.gdshader")
const PAUSE_MENU_SCENE: PackedScene = preload("res://scenes/ui/pause_menu.tscn")
const LOW_HP_SHADER: Shader = preload("res://assets/shaders/low_hp_vignette.gdshader")
const GLOBE_SHADER: Shader = preload("res://assets/shaders/resource_globe.gdshader")

# Diablo-style globes: HP is always bright-red liquid; the right globe is the
# class resource — blue mana for the casters, distinct flavors elsewhere
# (barbarian rage = dark crimson with a murkier shader, rogue amber energy,
# druid green essence, hexen violet ichor).
const GLOBE_SIZE: float = 148.0
const HP_LIQUID := {"color": Color(0.85, 0.08, 0.1), "darkness": 0.0}
const RESOURCE_LIQUID := {
	"mage": {"color": Color(0.16, 0.42, 1.0), "darkness": 0.0},
	"stormcaller": {"color": Color(0.2, 0.55, 1.0), "darkness": 0.0},
	"necromancer": {"color": Color(0.25, 0.4, 0.95), "darkness": 0.1},
	"hexen": {"color": Color(0.5, 0.18, 0.8), "darkness": 0.15},
	"druid": {"color": Color(0.15, 0.65, 0.3), "darkness": 0.15},
	"rogue": {"color": Color(0.8, 0.65, 0.15), "darkness": 0.2},
	"barbarian": {"color": Color(0.45, 0.03, 0.08), "darkness": 0.5},
}

var low_hp_overlay: ColorRect = null
var static_charge_label: Label = null
# Globe materials/labels (built in _build_globes; replace the legacy bars).
var _hp_globe_mat: ShaderMaterial = null
var _res_globe_mat: ShaderMaterial = null
var _hp_globe_label: Label = null
var _res_globe_label: Label = null

var skill_slots: Array = []
# Ultimate (R / spec-path ascension) slot — built alongside the hotbar but driven
# by the SkillSystem's separate ascension cooldown. Hidden until a path is chosen.
var ult_slot: Dictionary = {}
var skill_system_ref: Node = null
var player_ref: Node = null
var status_row: StatusIcons = null
var pause_menu_open: bool = false

# Boss bar — built on demand.
var boss_bar_root: Control = null
var boss_bar_fill: ColorRect = null
var boss_bar_label: Label = null
var boss_ref: Node = null

# Downed banner — built on demand (co-op bleed-out indicator).
var downed_banner: Label = null


func _ready() -> void:
	layer = 10
	if GameManager:
		GameManager.player_stats_changed.connect(_refresh)
		GameManager.gold_changed.connect(_refresh_gold)
		GameManager.player_levelled_up.connect(_on_level_up)
		GameManager.wave_started.connect(_on_wave_started)
		GameManager.wave_cleared.connect(_on_wave_cleared)
		GameManager.xp_gained.connect(_on_xp_gained)
		GameManager.class_selected.connect(_on_class_selected)
		GameManager.notice.connect(_show_banner)
		GameManager.arena_timer.connect(_on_arena_timer)
		GameManager.arena_currency_changed.connect(_on_arena_currency)
		GameManager.run_node_cleared.connect(_on_run_node_cleared)
	_refresh()
	_refresh_gold(GameManager.gold if GameManager else 0)
	if hint_label:
		var is_druid: bool = GameManager and String(GameManager.player_class) == "druid"
		if is_druid:
			hint_label.text = "WASD — движение   |   Клик — атака   |   1 2 3 4 — навыки   |   Q — орёл   |   Пробел — рывок   |   Tab — персонаж"
		else:
			hint_label.text = "WASD — движение   |   Клик — атака   |   1 2 3 4 — навыки   |   Пробел — рывок   |   Tab — персонаж"
	if class_label and GameManager:
		var data: Dictionary = GameManager.get_class_data()
		class_label.text = String(data.get("display", "Герой"))
	_build_hotbar()
	_setup_xp_shader()
	_update_xp_bar()
	_build_boss_bar()
	_build_wave_counter()
	_build_low_hp_overlay()
	_build_static_charge_counter()
	_build_status_row()
	_build_globes()
	call_deferred("_find_skill_system")


# Player buff/shield status row — added under the mana bar in the top-left stats
# panel. Squares are placeholders (status_dial.gdshader) with a clock-dial timer;
# art can replace each square later without changing the layout.
func _build_status_row() -> void:
	if mp_bar == null:
		return
	var stats: Node = mp_bar.get_parent().get_parent()  # Stats VBoxContainer
	if stats == null:
		return
	status_row = StatusIcons.new()
	status_row.icon_size = 26.0
	status_row.show_labels = true
	status_row.centered = false
	status_row.custom_minimum_size = Vector2(0, 30)
	stats.add_child(status_row)


# Persistent wave counter pinned top-center, separate from the transient banner.
var wave_counter_label: Label = null
# Arena wave countdown, just under the wave counter (built lazily on first arena_timer).
var arena_timer_label: Label = null


func _on_arena_timer(seconds_left: int) -> void:
	if seconds_left < 0:
		if arena_timer_label:
			arena_timer_label.visible = false
		return
	if arena_timer_label == null:
		var band := Control.new()
		band.name = "ArenaTimer"
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(band)
		band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		band.offset_top = 46
		band.offset_bottom = 78
		arena_timer_label = Label.new()
		arena_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arena_timer_label.add_theme_font_size_override("font_size", 20)
		arena_timer_label.add_theme_color_override("font_color", Color(0.6, 0.92, 1.0, 1))
		arena_timer_label.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.1, 1))
		arena_timer_label.add_theme_constant_override("outline_size", 4)
		band.add_child(arena_timer_label)
		arena_timer_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena_timer_label.visible = true
	arena_timer_label.text = "⏱ %d" % seconds_left


# Local arena currency — a gold coin counter pinned top-right, shown during an arena node.
var arena_coin_label: Label = null


func _on_arena_currency(amount: int) -> void:
	if arena_coin_label == null:
		var band := Control.new()
		band.name = "ArenaCoins"
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(band)
		band.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		band.offset_left = -260
		band.offset_right = -16
		band.offset_top = 12
		band.offset_bottom = 46
		arena_coin_label = Label.new()
		arena_coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		arena_coin_label.add_theme_font_size_override("font_size", 22)
		arena_coin_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25, 1))
		arena_coin_label.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.0, 1))
		arena_coin_label.add_theme_constant_override("outline_size", 4)
		band.add_child(arena_coin_label)
		arena_coin_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena_coin_label.visible = true
	arena_coin_label.text = "🪙 %d" % amount


func _on_run_node_cleared(_node: Dictionary) -> void:
	if arena_coin_label:
		arena_coin_label.visible = false
	if arena_timer_label:
		arena_timer_label.visible = false


func _build_wave_counter() -> void:
	var band := Control.new()
	band.name = "WaveCounter"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	band.offset_top = 10
	band.offset_bottom = 50
	wave_counter_label = Label.new()
	wave_counter_label.text = "ВОЛНА 1"
	wave_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_counter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wave_counter_label.add_theme_font_size_override("font_size", 26)
	wave_counter_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45, 1))
	wave_counter_label.add_theme_color_override("font_outline_color", Color(0.15, 0.03, 0.0, 1))
	wave_counter_label.add_theme_constant_override("outline_size", 5)
	band.add_child(wave_counter_label)
	wave_counter_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func update_wave_counter(wave: int, label: String = "") -> void:
	if wave_counter_label == null:
		return
	var text: String = label
	if text == "":
		text = "ВОЛНА %d" % wave
	wave_counter_label.text = text
	# Boss waves are red, rest waves green, normal waves gold.
	var boss_id: String = BossDatabase.boss_for_wave(wave)
	if boss_id != "":
		wave_counter_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3, 1))
	elif label.begins_with("ОТДЫХ") or label.find("Портал") >= 0:
		wave_counter_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.6, 1))
	else:
		wave_counter_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45, 1))


func _build_boss_bar() -> void:
	# Big red HP bar at the top of the screen with the boss name. Hidden by default.
	boss_bar_root = Control.new()
	boss_bar_root.name = "BossBar"
	boss_bar_root.visible = false
	boss_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(boss_bar_root)
	boss_bar_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	boss_bar_root.offset_top = 18
	boss_bar_root.offset_bottom = 80
	# Centered band.
	var band := Control.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_bar_root.add_child(band)
	band.anchor_left = 0.5
	band.anchor_right = 0.5
	band.anchor_top = 0.0
	band.anchor_bottom = 1.0
	band.offset_left = -360
	band.offset_right = 360
	# Name label on top.
	boss_bar_label = Label.new()
	boss_bar_label.text = "БОСС"
	boss_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4, 1))
	boss_bar_label.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.0, 1))
	boss_bar_label.add_theme_constant_override("outline_size", 5)
	boss_bar_label.add_theme_font_size_override("font_size", 22)
	band.add_child(boss_bar_label)
	boss_bar_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	boss_bar_label.offset_bottom = 28
	# HP bar (background + fill).
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.02, 0.04, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(bg)
	bg.anchor_left = 0.0
	bg.anchor_right = 1.0
	bg.anchor_top = 0.0
	bg.anchor_bottom = 0.0
	bg.offset_top = 32
	bg.offset_bottom = 58
	boss_bar_fill = ColorRect.new()
	boss_bar_fill.color = Color(0.95, 0.18, 0.18, 1)
	boss_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(boss_bar_fill)
	boss_bar_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	boss_bar_fill.offset_right = bg.size.x


func show_boss_bar(boss_name: String, boss: Node) -> void:
	if boss_bar_root == null:
		return
	boss_bar_root.visible = true
	if boss_bar_label:
		boss_bar_label.text = boss_name
	boss_ref = boss
	if boss and boss.has_signal("boss_hp_changed"):
		if not boss.is_connected("boss_hp_changed", _on_boss_hp_changed):
			boss.connect("boss_hp_changed", _on_boss_hp_changed)
	if boss and boss.has_signal("boss_phase_changed"):
		if not boss.is_connected("boss_phase_changed", _on_boss_phase_changed):
			boss.connect("boss_phase_changed", _on_boss_phase_changed)
	if boss and boss.get("hp") != null and boss.get("max_hp") != null:
		_on_boss_hp_changed(int(boss.get("hp")), int(boss.get("max_hp")))
	# Pop animation.
	var tw := boss_bar_root.create_tween()
	boss_bar_root.modulate = Color(1, 1, 1, 0)
	tw.tween_property(boss_bar_root, "modulate:a", 1.0, 0.4)


func hide_boss_bar() -> void:
	if boss_bar_root == null:
		return
	var tw := boss_bar_root.create_tween()
	tw.tween_property(boss_bar_root, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): boss_bar_root.visible = false)
	boss_ref = null


func _on_boss_hp_changed(hp: int, max_hp: int) -> void:
	if boss_bar_fill == null or max_hp <= 0:
		return
	var parent := boss_bar_fill.get_parent() as Control
	if parent == null:
		return
	var frac: float = clamp(float(hp) / float(max_hp), 0.0, 1.0)
	boss_bar_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	boss_bar_fill.offset_right = parent.size.x * frac


func _on_boss_phase_changed(phase_idx: int) -> void:
	# Flash the bar yellow then red for the next phase.
	if boss_bar_fill == null:
		return
	var tw := boss_bar_fill.create_tween()
	tw.tween_property(boss_bar_fill, "color", Color(1.0, 0.85, 0.3, 1), 0.15)
	tw.tween_property(boss_bar_fill, "color", Color(0.95, 0.18, 0.18, 1), 0.3)
	if boss_bar_label:
		var pop := boss_bar_label.create_tween()
		pop.tween_property(boss_bar_label, "modulate", Color(1.6, 1.0, 0.8, 1), 0.15)
		pop.tween_property(boss_bar_label, "modulate", Color(1, 1, 1, 1), 0.25)
	# Avoid unused warning.
	var _ignore := phase_idx


func _setup_xp_shader() -> void:
	if xp_fill == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = XP_SHADER
	mat.set_shader_parameter("base_color", Color(0.78, 0.12, 0.18, 1))
	mat.set_shader_parameter("highlight_color", Color(1.0, 0.78, 0.32, 1))
	xp_fill.material = mat


func _find_skill_system() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var players := tree.get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node = players[0]
	player_ref = player
	skill_system_ref = player.get_node_or_null("SkillSystem")
	if skill_system_ref:
		_refresh_hotbar_icons()
		if skill_system_ref.has_signal("skill_ids_changed"):
			if not skill_system_ref.is_connected("skill_ids_changed", _refresh_hotbar_icons):
				skill_system_ref.connect("skill_ids_changed", _refresh_hotbar_icons)


func _refresh_hotbar_icons() -> void:
	if skill_system_ref == null:
		return
	for i in 4:
		if i >= skill_slots.size():
			continue
		if not skill_slots[i].has("icon"):
			continue
		var icon: Texture2D = skill_system_ref.call("get_skill_icon", i)
		if icon:
			skill_slots[i]["icon"].texture = icon
	_update_ult_slot()


func _build_hotbar() -> void:
	if hotbar == null:
		return
	for c in hotbar.get_children():
		c.queue_free()
	skill_slots.clear()
	# Druid gets a 5th slot for Eagle Form on Q. Other classes stay at 4.
	var slot_count: int = 4
	var key_labels := ["1", "2", "3", "4", "Q"]
	# Initial fallback — actual icons replaced from the live SkillSystem after _find_skill_system.
	var fallback_icons := [
		"res://assets/sprites/items/icon_skill_fire_wall.png",
		"res://assets/sprites/items/icon_skill_ice_bolt.png",
		"res://assets/sprites/items/icon_skill_chain_lightning.png",
		"res://assets/sprites/items/icon_skill_meteor.png",
	]
	if GameManager:
		var cls: String = GameManager.player_class
		if RewardData.CLASS_SLOT_ICONS.has(cls):
			fallback_icons = RewardData.CLASS_SLOT_ICONS[cls].duplicate()
		if cls == "druid":
			slot_count = 5
			# Make sure the fallback list has a 5th entry for Eagle Form.
			if fallback_icons.size() < 5:
				fallback_icons.append("res://assets/sprites/items/icon_druid_eagle_form.png")
	for i in slot_count:
		var icon_path: String = fallback_icons[i] if i < fallback_icons.size() else ""
		var slot: Dictionary = _make_hotbar_slot(key_labels[i], icon_path)
		hotbar.add_child(slot["root"])
		skill_slots.append(slot)

	_build_ult_slot()


# Build one hotbar slot subtree (panel → icon → cooldown overlay/label → key tag
# → mana tag) and return its node refs as a dict. Caller parents the "root".
func _make_hotbar_slot(key_text: String, icon_path: String) -> Dictionary:
	var slot_root := PanelContainer.new()
	slot_root.theme_type_variation = &"HudPanel"
	slot_root.custom_minimum_size = Vector2(88, 88)

	var inner := Control.new()
	inner.custom_minimum_size = Vector2(80, 80)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_root.add_child(inner)

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(72, 72)
	inner.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path) as Texture2D

	var cd_overlay := ColorRect.new()
	cd_overlay.color = Color(0, 0, 0, 0.55)
	cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_overlay.visible = false
	inner.add_child(cd_overlay)
	cd_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var cd_label := Label.new()
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd_label.add_theme_color_override("font_color", Color(1, 0.95, 0.7, 1))
	cd_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	cd_label.add_theme_constant_override("outline_size", 4)
	cd_label.add_theme_font_size_override("font_size", 28)
	cd_label.text = ""
	cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(cd_label)
	cd_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var key_label := Label.new()
	key_label.text = key_text
	key_label.add_theme_color_override("font_color", Color(1, 0.92, 0.55, 1))
	key_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	key_label.add_theme_constant_override("outline_size", 4)
	key_label.add_theme_font_size_override("font_size", 16)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(key_label)
	key_label.position = Vector2(4, 4)

	var mana_label := _make_mana_label()
	inner.add_child(mana_label)
	mana_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	mana_label.offset_left = -40
	mana_label.offset_top = -26
	mana_label.offset_right = -4
	mana_label.offset_bottom = -4

	return {
		"root": slot_root,
		"icon": icon,
		"cd_overlay": cd_overlay,
		"cd_label": cd_label,
		"key_label": key_label,
		"mana_label": mana_label,
	}


# A small mana-cost tag pinned to a slot's bottom-right corner. Blue when affordable,
# red when the player can't pay for it (see _update_mana_labels). Skills with no mana
# cost hide the tag entirely.
const MANA_COLOR_OK := Color(0.55, 0.85, 1.0, 1)
const MANA_COLOR_LOW := Color(1.0, 0.32, 0.3, 1)
const SLOT_DIM := Color(0.42, 0.42, 0.5, 1)


func _make_mana_label() -> Label:
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.add_theme_color_override("font_color", MANA_COLOR_OK)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.03, 0.08, 1))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# The ultimate (R) slot lives at the end of the hotbar. It mirrors a normal slot
# but reads the SkillSystem's ascension cooldown and stays hidden until the
# player picks a spec path at level 7. An amber border marks it as the ultimate.
func _build_ult_slot() -> void:
	ult_slot = {}
	var slot_root := PanelContainer.new()
	slot_root.theme_type_variation = &"HudPanel"
	slot_root.custom_minimum_size = Vector2(88, 88)
	slot_root.modulate = Color(1.0, 0.85, 0.4, 1)  # amber tint = ultimate
	hotbar.add_child(slot_root)

	var inner := Control.new()
	inner.custom_minimum_size = Vector2(80, 80)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_root.add_child(inner)

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(72, 72)
	inner.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var cd_overlay := ColorRect.new()
	cd_overlay.color = Color(0, 0, 0, 0.55)
	cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_overlay.visible = false
	inner.add_child(cd_overlay)
	cd_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var cd_label := Label.new()
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd_label.add_theme_color_override("font_color", Color(1, 0.95, 0.7, 1))
	cd_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	cd_label.add_theme_constant_override("outline_size", 4)
	cd_label.add_theme_font_size_override("font_size", 24)
	cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(cd_label)
	cd_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var key_label := Label.new()
	key_label.text = "R"
	key_label.add_theme_color_override("font_color", Color(1, 0.92, 0.55, 1))
	key_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	key_label.add_theme_constant_override("outline_size", 4)
	key_label.add_theme_font_size_override("font_size", 16)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(key_label)
	key_label.position = Vector2(4, 4)

	var mana_label := _make_mana_label()
	inner.add_child(mana_label)
	mana_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	mana_label.offset_left = -40
	mana_label.offset_top = -26
	mana_label.offset_right = -4
	mana_label.offset_bottom = -4

	ult_slot = {
		"root": slot_root,
		"icon": icon,
		"cd_overlay": cd_overlay,
		"cd_label": cd_label,
		"mana_label": mana_label,
	}
	slot_root.visible = false
	_update_ult_slot()


# Show/hide + icon for the ultimate slot based on whether a spec path is active.
func _update_ult_slot() -> void:
	if ult_slot.is_empty() or skill_system_ref == null:
		return
	var ability_id: String = ""
	if skill_system_ref.has_method("get_ascension_skill_id"):
		ability_id = String(skill_system_ref.call("get_ascension_skill_id"))
	var root: Control = ult_slot["root"]
	root.visible = ability_id != ""
	if ability_id != "" and skill_system_ref.has_method("get_ascension_icon"):
		var tex: Texture2D = skill_system_ref.call("get_ascension_icon")
		if tex:
			(ult_slot["icon"] as TextureRect).texture = tex


func _refresh() -> void:
	if GameManager == null:
		return
	_update_globes()
	if level_label:
		level_label.text = "Ур. %d" % GameManager.player_level
	_update_xp_bar()


func _update_xp_bar() -> void:
	if GameManager == null or xp_fill == null or xp_bg == null:
		return
	var ratio: float = 0.0
	if GameManager.player_xp_to_next > 0:
		ratio = clamp(float(GameManager.player_xp) / float(GameManager.player_xp_to_next), 0.0, 1.0)
	# Resize the fill rect proportionally to ratio.
	xp_fill.anchor_left = 0.0
	xp_fill.anchor_top = 0.0
	xp_fill.anchor_bottom = 1.0
	xp_fill.anchor_right = ratio
	xp_fill.offset_left = 0.0
	xp_fill.offset_top = 0.0
	xp_fill.offset_right = 0.0
	xp_fill.offset_bottom = 0.0
	if xp_label:
		xp_label.text = (
			"Ур. %d    %d / %d опыта"
			% [GameManager.player_level, GameManager.player_xp, GameManager.player_xp_to_next]
		)


func _refresh_gold(amount: int) -> void:
	if gold_label:
		gold_label.text = str(amount)


func _on_level_up(lv: int) -> void:
	_refresh()
	if VfxManager:
		VfxManager.screen_flash(Color(1.0, 0.4, 0.2, 0.35), 0.5)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_level_up.mp3", -4.0)
	_show_banner("Новый уровень — %d" % lv, Color(1.0, 0.85, 0.4, 1))
	# Flash XP bar.
	if xp_fill:
		var tw := create_tween()
		tw.tween_property(xp_fill, "modulate", Color(1.6, 1.4, 0.8, 1), 0.15)
		tw.tween_property(xp_fill, "modulate", Color(1, 1, 1, 1), 0.45)


func _on_xp_gained(_amount: int) -> void:
	_update_xp_bar()


func _on_class_selected(_cid: String) -> void:
	_apply_resource_style()
	_refresh()
	if class_label and GameManager:
		class_label.text = String(GameManager.get_class_data().get("display", "Герой"))


func _on_wave_started(wave: int) -> void:
	# Use the boss intro text if this is a boss wave.
	var boss_id: String = BossDatabase.boss_for_wave(wave)
	if boss_id != "":
		var boss_data: Dictionary = BossDatabase.get_boss(boss_id)
		_show_banner(String(boss_data.get("intro", "ПРИБЛИЖАЕТСЯ БОСС")), Color(1.0, 0.3, 0.25, 1))
		update_wave_counter(wave, "ВОЛНА БОССА %d" % wave)
	else:
		_show_banner("Волна %d" % wave, Color(1.0, 0.4, 0.4, 1))
		update_wave_counter(wave)
	if GameManager and wave > GameManager.highest_wave:
		GameManager.highest_wave = wave


func _on_wave_cleared(wave: int) -> void:
	_show_banner("Волна зачищена!", Color(0.7, 1.0, 0.7, 1))
	# If this is a merchant-break wave, swap counter to a rest indicator.
	if BossDatabase.boss_for_wave(wave) == "" and wave % 3 == 0:
		update_wave_counter(wave, "ОТДЫХ · Портал, чтобы продолжить")


func _show_banner(text: String, color: Color) -> void:
	if wave_label == null:
		return
	wave_label.text = text
	wave_label.add_theme_color_override("font_color", color)
	wave_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(wave_label, "modulate:a", 0.0, 0.8)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tab_panel"):
		if character_sheet and character_sheet.has_method("toggle"):
			character_sheet.toggle()
		get_viewport().set_input_as_handled()
	elif (
		event.is_action_pressed("pause")
		or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)
	):
		_open_pause_menu()
		get_viewport().set_input_as_handled()


func _open_pause_menu() -> void:
	if pause_menu_open:
		return
	if GameManager and GameManager.game_over:
		return
	pause_menu_open = true
	var menu: CanvasLayer = PAUSE_MENU_SCENE.instantiate()
	if menu.has_signal("closed"):
		menu.connect("closed", _on_pause_menu_closed)
	get_tree().current_scene.add_child(menu)


func _on_pause_menu_closed() -> void:
	pause_menu_open = false


func _build_low_hp_overlay() -> void:
	# Fullscreen ColorRect with the low-hp vignette shader. Sits BEHIND the
	# rest of the HUD widgets so health/mana stay readable.
	low_hp_overlay = ColorRect.new()
	low_hp_overlay.name = "LowHpVignette"
	low_hp_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low_hp_overlay.color = Color(1, 1, 1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = LOW_HP_SHADER
	mat.set_shader_parameter("intensity", 0.0)
	mat.set_shader_parameter("tint_color", Color(0.95, 0.12, 0.18, 1.0))
	low_hp_overlay.material = mat
	add_child(low_hp_overlay)
	low_hp_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Lower the overlay node in tree order so other widgets sit on top.
	move_child(low_hp_overlay, 0)


func _build_static_charge_counter() -> void:
	# Tiny lightning-bolt counter for the Stormcaller (hidden for other classes).
	static_charge_label = Label.new()
	static_charge_label.name = "StaticChargeLabel"
	static_charge_label.text = "⚡ 0"
	static_charge_label.add_theme_font_size_override("font_size", 22)
	static_charge_label.add_theme_color_override("font_color", Color(0.55, 0.95, 1.5, 1))
	static_charge_label.add_theme_color_override("font_outline_color", Color(0.02, 0.08, 0.2, 1))
	static_charge_label.add_theme_constant_override("outline_size", 5)
	static_charge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	static_charge_label.visible = false
	add_child(static_charge_label)
	static_charge_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	static_charge_label.position = Vector2(40, 220)


func _update_low_hp_overlay() -> void:
	if low_hp_overlay == null or low_hp_overlay.material == null or GameManager == null:
		return
	var max_hp: float = float(max(1, GameManager.player_max_hp))
	var hp_frac: float = clamp(float(GameManager.player_hp) / max_hp, 0.0, 1.0)
	# Threshold below 25% HP, ramps up to full intensity at 0%.
	var raw: float = clamp((0.25 - hp_frac) * 4.0, 0.0, 1.0)
	(low_hp_overlay.material as ShaderMaterial).set_shader_parameter("intensity", raw)


func _update_static_charge_counter() -> void:
	if static_charge_label == null or GameManager == null:
		return
	var is_storm: bool = String(GameManager.player_class) == "stormcaller"
	static_charge_label.visible = is_storm
	if not is_storm:
		return
	var tree := get_tree()
	if tree == null:
		return
	var ps := tree.get_nodes_in_group("player")
	for p in ps:
		if p.is_in_group("remote_player"):
			continue
		if p.get("static_charge") != null:
			var cur: int = int(p.get("static_charge"))
			var cap: int = 5
			if p.has_method("get_static_charge_cap"):
				cap = int(p.call("get_static_charge_cap"))
			static_charge_label.text = "⚡ %d / %d" % [cur, cap]
			return


# Shield sheath: the HP globe shader draws shield_hp/max_hp as a pale glassy
# layer over the red liquid (the old ProgressBar overlay is gone with the bars).
func _update_shield_overlay() -> void:
	if _hp_globe_mat == null:
		return
	var sh: float = 0.0
	if player_ref and is_instance_valid(player_ref) and player_ref.get("shield_hp") != null:
		sh = float(player_ref.get("shield_hp"))
	var mhp: float = float(GameManager.get_effective_max_hp()) if GameManager else 100.0
	_hp_globe_mat.set_shader_parameter("shield_frac", clampf(sh / maxf(1.0, mhp), 0.0, 1.0))


# Build the two bottom-corner globes and retire the legacy top-left bars.
func _build_globes() -> void:
	if hp_bar and hp_bar.get_parent():
		(hp_bar.get_parent() as Control).visible = false  # HpRow
	if mp_bar and mp_bar.get_parent():
		(mp_bar.get_parent() as Control).visible = false  # MpRow
	var hp_built: Dictionary = _build_globe(false)
	_hp_globe_mat = hp_built["mat"]
	_hp_globe_label = hp_built["label"]
	_hp_globe_mat.set_shader_parameter("liquid_color", HP_LIQUID["color"])
	_hp_globe_mat.set_shader_parameter("darkness", HP_LIQUID["darkness"])
	var res_built: Dictionary = _build_globe(true)
	_res_globe_mat = res_built["mat"]
	_res_globe_label = res_built["label"]
	_apply_resource_style()
	_update_globes()


# One globe: rect with the globe shader + a number label floating above it.
# `right` = bottom-right corner (resource), else bottom-left (health).
func _build_globe(right: bool) -> Dictionary:
	var holder := Control.new()
	holder.name = "ResourceGlobe" if right else "HealthGlobe"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	holder.anchor_left = 1.0 if right else 0.0
	holder.anchor_right = 1.0 if right else 0.0
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	var margin: float = 14.0
	holder.offset_left = (-margin - GLOBE_SIZE) if right else margin
	holder.offset_right = -margin if right else (margin + GLOBE_SIZE)
	holder.offset_top = -margin - GLOBE_SIZE - 26.0
	holder.offset_bottom = -margin

	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	holder.add_child(label)
	label.anchor_right = 1.0
	label.offset_top = 0.0
	label.offset_bottom = 24.0

	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)  # shader overwrites COLOR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GLOBE_SHADER
	mat.set_shader_parameter("fill", 1.0)
	mat.set_shader_parameter("seed_offset", randf() * 10.0)
	rect.material = mat
	holder.add_child(rect)
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_top = 26.0

	return {"mat": mat, "label": label}


func _apply_resource_style() -> void:
	if _res_globe_mat == null or GameManager == null:
		return
	var cls: String = String(GameManager.player_class)
	var style: Dictionary = RESOURCE_LIQUID.get(cls, RESOURCE_LIQUID["mage"])
	_res_globe_mat.set_shader_parameter("liquid_color", style["color"])
	_res_globe_mat.set_shader_parameter("darkness", style["darkness"])


func _update_globes() -> void:
	if GameManager == null or _hp_globe_mat == null:
		return
	var max_hp: float = float(GameManager.get_effective_max_hp())
	var max_mana: float = float(GameManager.get_effective_max_mana())
	_hp_globe_mat.set_shader_parameter(
		"fill", clampf(float(GameManager.player_hp) / maxf(1.0, max_hp), 0.0, 1.0)
	)
	_res_globe_mat.set_shader_parameter(
		"fill", clampf(float(GameManager.player_mana) / maxf(1.0, max_mana), 0.0, 1.0)
	)
	if _hp_globe_label:
		_hp_globe_label.text = "%d / %d" % [int(GameManager.player_hp), int(max_hp)]
	if _res_globe_label:
		_res_globe_label.text = "%d / %d" % [int(GameManager.player_mana), int(max_mana)]


func _process(_delta: float) -> void:
	_update_shield_overlay()
	_update_low_hp_overlay()
	_update_static_charge_counter()
	_update_downed_banner()
	if status_row and player_ref and is_instance_valid(player_ref) and player_ref.has_method("get_active_statuses"):
		status_row.update_statuses(player_ref.call("get_active_statuses"))
	_update_globes()  # mana drains/regens continuously — keep the liquid live
	if skill_system_ref:
		var cur_mana: float = float(GameManager.player_mana) if GameManager else 0.0
		for i in skill_slots.size():
			var slot: Dictionary = skill_slots[i]
			var remaining: float = skill_system_ref.call("get_cooldown_remaining", i)
			var cd_overlay: ColorRect = slot["cd_overlay"]
			var cd_label: Label = slot["cd_label"]
			if remaining > 0.01:
				cd_overlay.visible = true
				cd_label.text = "%.1f" % remaining
			else:
				cd_overlay.visible = false
				cd_label.text = ""
			var cost: float = float(skill_system_ref.call("get_skill_mana_cost", i))
			_update_slot_mana(slot, cost, cur_mana)
		_update_ult_cooldown()
		_update_ult_mana(cur_mana)


# Show a slot's mana cost (bottom-right) and grey the icon when it's unaffordable.
# A zero-cost skill hides the tag and is never greyed for mana.
func _update_slot_mana(slot: Dictionary, cost: float, cur_mana: float) -> void:
	var mana_label: Label = slot.get("mana_label")
	var icon: TextureRect = slot.get("icon")
	if mana_label == null:
		return
	if cost <= 0.0:
		mana_label.visible = false
		if icon:
			icon.modulate = Color.WHITE
		return
	mana_label.visible = true
	mana_label.text = "%d" % int(round(cost))
	var affordable: bool = cur_mana >= cost
	mana_label.add_theme_color_override("font_color", MANA_COLOR_OK if affordable else MANA_COLOR_LOW)
	if icon:
		icon.modulate = Color.WHITE if affordable else SLOT_DIM


func _update_ult_mana(cur_mana: float) -> void:
	if ult_slot.is_empty() or skill_system_ref == null:
		return
	var root: Control = ult_slot["root"]
	if not root.visible:
		return
	if not skill_system_ref.has_method("get_ascension_mana_cost"):
		return
	var cost: float = float(skill_system_ref.call("get_ascension_mana_cost"))
	_update_slot_mana(ult_slot, cost, cur_mana)


# Drive the ultimate slot's cooldown overlay from the SkillSystem's ascension CD.
func _update_ult_cooldown() -> void:
	if ult_slot.is_empty() or skill_system_ref == null:
		return
	var root: Control = ult_slot["root"]
	if not root.visible:
		return
	var cd_overlay: ColorRect = ult_slot["cd_overlay"]
	var cd_label: Label = ult_slot["cd_label"]
	var remaining: float = 0.0
	if skill_system_ref.has_method("get_ascension_cooldown_remaining"):
		remaining = float(skill_system_ref.call("get_ascension_cooldown_remaining"))
	if remaining > 0.01:
		cd_overlay.visible = true
		cd_label.text = "%.0f" % ceil(remaining)
	else:
		cd_overlay.visible = false
		cd_label.text = ""


# Co-op bleed-out indicator — shown while the local player is downed, counting
# the seconds left before they bleed out. Built lazily on first use.
func _update_downed_banner() -> void:
	if GameManager == null:
		return
	if not GameManager.player_downed:
		if downed_banner:
			downed_banner.visible = false
		return
	if downed_banner == null:
		downed_banner = Label.new()
		downed_banner.add_theme_font_size_override("font_size", 30)
		downed_banner.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1))
		downed_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		downed_banner.add_theme_constant_override("outline_size", 5)
		downed_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		downed_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(downed_banner)
		downed_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		downed_banner.offset_top = 150.0
		downed_banner.offset_left = -280.0
		downed_banner.offset_right = 280.0
	downed_banner.visible = true
	downed_banner.text = "ВЫ ПОВЕРЖЕНЫ — ждите союзника  (%d)" % int(ceil(GameManager.downed_time_left))
