class_name RestChoice
extends CanvasLayer

## Campfire rest choice (Slay-the-Spire style). Pick ONE boon, then the campfire is spent.
## Code-built overlay. Choices reuse GameManager helpers (no new systems):
##   • Mend    — full heal
##   • Train   — a chunk of bonus XP
##   • Prosper — bonus gold
## (Richer options — item upgrade / skill reroll — are a later enhancement.)

const XP_BONUS: int = 60
const GOLD_BONUS: int = 120
# Talent respec price per refunded point (perk ranks are kept, see respec_talents).
const RESPEC_GOLD_PER_POINT: int = 20

signal closed


func _ready() -> void:
	layer = 32
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var dim := UIBuilder.dim_overlay(Color(0.02, 0.02, 0.05, 0.84))
	add_child(dim)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 12)
	dim.add_child(vb)

	var title := Label.new()
	title.text = "Костёр — привал"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
	vb.add_child(title)

	vb.add_child(_button("Исцелиться — полное лечение", _mend))
	vb.add_child(_button("Тренироваться — +%d опыта" % XP_BONUS, _train))
	vb.add_child(_button("Поживиться — +%d золота" % GOLD_BONUS, _prosper))

	# Talent respec — campfire-only. Spends the rest like the other boons (the
	# whole overlay closes on pick), priced per refunded point.
	if GameManager and GameManager.use_talent_tree:
		var refund: int = GameManager.talent_respec_refund()
		if refund > 0:
			var cost: int = refund * RESPEC_GOLD_PER_POINT
			var b := _button("Сброс талантов — вернуть %d очков (%d золота)" % [refund, cost], _respec)
			b.disabled = GameManager.gold < cost
			vb.add_child(b)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 48)
	b.pressed.connect(cb)
	return b


func _mend() -> void:
	if GameManager:
		GameManager.heal_player(GameManager.player_max_hp)
	_close()


func _train() -> void:
	if GameManager:
		GameManager.add_xp(XP_BONUS, false)
	_close()


func _prosper() -> void:
	if GameManager:
		GameManager.add_gold(GOLD_BONUS)
	_close()


func _respec() -> void:
	if GameManager:
		var cost: int = GameManager.talent_respec_refund() * RESPEC_GOLD_PER_POINT
		if GameManager.gold >= cost:
			GameManager.gold -= cost
			GameManager.gold_changed.emit(GameManager.gold)
			GameManager.respec_talents()
	_close()


func _close() -> void:
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_button_click.mp3", -6.0)
	closed.emit()
	queue_free()
