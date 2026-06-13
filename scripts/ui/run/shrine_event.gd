class_name ShrineEvent
extends CanvasLayer

## "Алтарь сделки" — the event-node bargain overlay (Slay-the-Spire event beat). Offers three
## random Faustian deals: each grants real power for a permanent cost, plus a free "leave"
## option. Code-built, self-contained. Does NOT pause the tree (co-op pause/transport invariant)
## and applies effects to GameManager's run stats (per-client, like the level-up cards).

signal closed

const RARITY_COLORS := {
	"common": Color(0.8, 0.8, 0.85, 1),
	"rare": Color(0.4, 0.7, 1.0, 1),
	"legendary": Color(1.0, 0.6, 0.2, 1),
}

# Every deal: id + flavour + a green "gain" line and a red "cost" line. The actual numbers live
# in _apply so the text and the effect never drift apart.
const BARGAINS := [
	{
		"id": "blood_pact", "title": "Кровавый пакт", "rarity": "legendary",
		"gain": "+40% к урону", "cost": "−25% к макс. HP",
	},
	{
		"id": "glass_fury", "title": "Хрупкая ярость", "rarity": "rare",
		"gain": "+20% к шансу крита", "cost": "−20% к макс. HP",
	},
	{
		"id": "greed", "title": "Жадность", "rarity": "rare",
		"gain": "+1 макс. HP за каждые 4 золота", "cost": "Забирает ВСЁ твоё золото",
	},
	{
		"id": "swift_pact", "title": "Договор ветра", "rarity": "rare",
		"gain": "+20% к скорости и +20 маны", "cost": "−15% к макс. HP",
	},
	{
		"id": "sacrifice", "title": "Жертва крови", "rarity": "legendary",
		"gain": "+8 к урону навсегда", "cost": "Теряешь половину текущего HP",
	},
	{
		"id": "mana_flesh", "title": "Плоть из маны", "rarity": "common",
		"gain": "+60 к макс. HP", "cost": "−30% к макс. мане",
	},
	{
		"id": "cursed_luck", "title": "Проклятая удача", "rarity": "legendary",
		"gain": "+50% к крит-урону", "cost": "−10% к урону",
	},
]

var _offers: Array = []


func _ready() -> void:
	layer = 32
	process_mode = Node.PROCESS_MODE_ALWAYS
	_offers = _roll_offers()
	_build()


func _roll_offers() -> Array:
	var pool: Array = BARGAINS.duplicate()
	pool.shuffle()
	return pool.slice(0, 3)


func _build() -> void:
	var dim := UIBuilder.dim_overlay(Color(0.02, 0.03, 0.05, 0.88))
	add_child(dim)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	dim.add_child(vb)

	var title := Label.new()
	title.text = "◈ Алтарь сделки ◈"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.5, 0.95, 0.82))
	title.add_theme_color_override("font_outline_color", Color(0, 0.05, 0.05))
	title.add_theme_constant_override("outline_size", 5)
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "Сила требует жертвы. Выбери один договор — или уйди ни с чем."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.75, 0.82, 0.78))
	vb.add_child(sub)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	vb.add_child(row)
	for data in _offers:
		row.add_child(_build_card(data))

	var leave := Button.new()
	leave.text = "Уйти ни с чем"
	leave.custom_minimum_size = Vector2(280, 44)
	leave.focus_mode = Control.FOCUS_NONE
	leave.add_theme_font_size_override("font_size", 18)
	leave.pressed.connect(_on_leave)
	vb.add_child(leave)


func _build_card(data: Dictionary) -> Control:
	var rarity: String = String(data.get("rarity", "common"))
	var rc: Color = RARITY_COLORS.get(rarity, Color.WHITE)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InventoryPanel"
	panel.custom_minimum_size = Vector2(300, 320)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)

	var name_lbl := Label.new()
	name_lbl.text = String(data.get("title", "?"))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 23)
	name_lbl.add_theme_color_override("font_color", rc)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	name_lbl.add_theme_constant_override("outline_size", 4)
	v.add_child(name_lbl)

	var gain := Label.new()
	gain.text = "✦ " + String(data.get("gain", ""))
	gain.autowrap_mode = TextServer.AUTOWRAP_WORD
	gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gain.add_theme_font_size_override("font_size", 17)
	gain.add_theme_color_override("font_color", Color(0.45, 0.92, 0.5))
	gain.custom_minimum_size = Vector2(0, 60)
	v.add_child(gain)

	var cost := Label.new()
	cost.text = "✖ " + String(data.get("cost", ""))
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_font_size_override("font_size", 17)
	cost.add_theme_color_override("font_color", Color(0.95, 0.4, 0.38))
	cost.custom_minimum_size = Vector2(0, 60)
	v.add_child(cost)

	var btn := Button.new()
	btn.text = "Заключить"
	btn.custom_minimum_size = Vector2(0, 48)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 19)
	btn.pressed.connect(_on_pick.bind(data))
	v.add_child(btn)

	return panel


func _on_pick(data: Dictionary) -> void:
	_apply(String(data.get("id", "")))
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_ui_menu_click.mp3", -6.0)
	if VfxManager:
		var rc: Color = RARITY_COLORS.get(String(data.get("rarity", "common")), Color.WHITE)
		VfxManager.screen_flash(Color(rc.r, rc.g, rc.b, 0.25), 0.3)
	_close()


func _on_leave() -> void:
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_button_click.mp3", -8.0)
	_close()


# Each deal's real numbers. Costs clamp so the player can never be killed or zeroed out by a
# bargain (max HP / mana floor at a safe minimum, current HP floors at 1).
func _apply(id: String) -> void:
	if GameManager == null:
		return
	match id:
		"blood_pact":
			GameManager.player_damage = int(round(float(GameManager.player_damage) * 1.4))
			_scale_max_hp(0.75)
		"glass_fury":
			GameManager.player_crit_chance += 0.20
			_scale_max_hp(0.80)
		"greed":
			var g: int = GameManager.gold
			if g > 0:
				var hp_gain: int = int(g / 4)
				GameManager.player_max_hp += hp_gain
				GameManager.player_hp += hp_gain
				GameManager.gold = 0
				GameManager.gold_changed.emit(0)
		"swift_pact":
			GameManager.player_move_speed *= 1.2
			GameManager.player_max_mana += 20
			GameManager.player_mana = min(GameManager.player_mana + 20.0, float(GameManager.player_max_mana))
			_scale_max_hp(0.85)
		"sacrifice":
			GameManager.player_hp = maxi(1, int(GameManager.player_hp / 2))
			GameManager.player_damage += 8
		"mana_flesh":
			GameManager.player_max_hp += 60
			GameManager.player_hp += 60
			GameManager.player_max_mana = maxi(10, int(round(float(GameManager.player_max_mana) * 0.7)))
			GameManager.player_mana = min(GameManager.player_mana, float(GameManager.player_max_mana))
		"cursed_luck":
			GameManager.player_crit_damage += 0.5
			GameManager.player_damage = maxi(1, int(round(float(GameManager.player_damage) * 0.9)))
	GameManager.player_stats_changed.emit()


func _scale_max_hp(factor: float) -> void:
	var new_max: int = maxi(1, int(round(float(GameManager.player_max_hp) * factor)))
	GameManager.player_max_hp = new_max
	GameManager.player_hp = mini(GameManager.player_hp, new_max)


func _close() -> void:
	closed.emit()
	queue_free()
