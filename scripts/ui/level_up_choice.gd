extends CanvasLayer

# Level-up choice overlay — pops up on every level-up. Pauses the game.
# 3 cards: stat boost, skill modifier, sometimes a transforming unique.

signal choice_made(choice_id: String)

const RARITY_COLORS := {
	"common": Color(0.8, 0.8, 0.85, 1),
	"rare": Color(0.4, 0.7, 1.0, 1),
	"legendary": Color(1.0, 0.6, 0.2, 1),
	"unique": Color(1.0, 0.4, 0.3, 1),
}

@export var card_row: HBoxContainer

var current_offers: Array = []
var chosen_id: String = ""


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Pause for the upgrade choice. In CO-OP this is safe (unlike character sheet /
	# merchant, which stay unpaused) because XP is shared — enemy._die and
	# net_sync grant identical party XP, so ALL players level up on the same kill
	# and open this overlay together → the pause is synchronized. The host's pause
	# also freezes the authoritative enemy sim for everyone, and the transport
	# (NetManager) is PROCESS_MODE_ALWAYS so it never stalls.
	get_tree().paused = true
	current_offers = _roll_offers()
	_build_cards()


func _roll_offers() -> Array:
	var picks: Array = []
	var taken_ids: Dictionary = {}

	# 0. Barbarian dual-2H perk — high priority slot, replaces card 1 if available.
	if _can_offer_berserker_grip():
		(
			picks
			. append(
				{
					"id": "barb_dual_2h",
					"kind": "perk",
					"title": "Berserker's Grip",
					"desc": "Wield TWO two-handed weapons at once. Weapon damage stacks.",
					"rarity": "legendary",
				}
			)
		)
		taken_ids["barb_dual_2h"] = true

	# 1. Stat boost (skip if perk took the slot).
	if picks.size() == 0:
		var stat_pool: Array = RewardData.STAT_REWARDS.duplicate()
		stat_pool.shuffle()
		for s in stat_pool:
			if not taken_ids.has(s["id"]):
				picks.append(_with_kind(s, "stat"))
				taken_ids[s["id"]] = true
				break

	var cls: String = String(GameManager.player_class) if GameManager else ""

	# 2. Skill modifier — ONLY this class' modifiers (a barbarian must never be
	# offered a Fire Wall tweak). If the class has no remaining modifier, fall
	# back to a stat so the player still gets a real third choice.
	var mod_pool: Array = RewardData.modifiers_for_class(cls)
	mod_pool.shuffle()
	var got_modifier: bool = false
	for m in mod_pool:
		if not taken_ids.has(m["id"]):
			picks.append(_with_kind(m, "modifier"))
			taken_ids[m["id"]] = true
			got_modifier = true
			break
	if not got_modifier:
		_append_stat(picks, taken_ids)

	# 3. ~25% chance a class unique, otherwise another class modifier, else stat.
	var third: Dictionary = {}
	if randf() < 0.25 and not _all_uniques_taken():
		var unique_pool: Array = RewardData.uniques_for_class(cls)
		unique_pool.shuffle()
		for u in unique_pool:
			if not _already_owns_unique(u) and not taken_ids.has(u["id"]):
				third = _with_kind(u, "unique")
				taken_ids[u["id"]] = true
				break
	if third.is_empty():
		var mod_pool2: Array = RewardData.modifiers_for_class(cls)
		mod_pool2.shuffle()
		for m in mod_pool2:
			if not taken_ids.has(m["id"]):
				third = _with_kind(m, "modifier")
				taken_ids[m["id"]] = true
				break
	if third.is_empty():
		_append_stat(picks, taken_ids)
	else:
		picks.append(third)

	return picks


# Append the first untaken stat reward (class-agnostic fallback choice).
func _append_stat(picks: Array, taken_ids: Dictionary) -> void:
	var stat_pool: Array = RewardData.STAT_REWARDS.duplicate()
	stat_pool.shuffle()
	for s in stat_pool:
		if not taken_ids.has(s["id"]):
			picks.append(_with_kind(s, "stat"))
			taken_ids[s["id"]] = true
			return


func _with_kind(d: Dictionary, kind: String) -> Dictionary:
	var c: Dictionary = d.duplicate(true)
	c["kind"] = kind
	return c


func _can_offer_berserker_grip() -> bool:
	if GameManager == null or InventorySystem == null:
		return false
	if GameManager.player_class != "barbarian":
		return false
	if InventorySystem.has_berserker_grip:
		return false
	# Available from player level 5+, with a 35% chance per qualifying level-up.
	if GameManager.player_level < 5:
		return false
	return randf() < 0.4


func _all_uniques_taken() -> bool:
	var ss := _find_skill_system()
	if ss == null:
		return false
	var transforms: Array = (
		ss.get("active_transforms") if ss.get("active_transforms") != null else []
	)
	# Compare against THIS class' transform uniques, not the whole catalog —
	# otherwise the gate (built from a mixed-class pool) never trips.
	var cls: String = String(GameManager.player_class) if GameManager else ""
	return transforms.size() >= RewardData.uniques_for_class(cls).size()


func _already_owns_unique(u: Dictionary) -> bool:
	var ss := _find_skill_system()
	if ss == null:
		return false
	var transforms: Array = (
		ss.get("active_transforms") if ss.get("active_transforms") != null else []
	)
	return transforms.has(String(u.get("transform", "")))


func _find_player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var ps := tree.get_nodes_in_group("player")
	if ps.is_empty():
		return null
	return ps[0]


func _find_skill_system() -> Node:
	var p := _find_player()
	if p == null:
		return null
	return p.get_node_or_null("SkillSystem")


func _build_cards() -> void:
	if card_row == null:
		return
	for c in card_row.get_children():
		c.queue_free()
	for i in current_offers.size():
		var data: Dictionary = current_offers[i]
		var card := _build_card(data)
		card_row.add_child(card)


func _build_card(data: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InventoryPanel"
	panel.custom_minimum_size = Vector2(320, 480)

	var rarity: String = String(data.get("rarity", "common"))
	var rarity_color: Color = RARITY_COLORS.get(rarity, Color.WHITE)

	# Hover wiring: bind tooltip.
	panel.mouse_entered.connect(_on_card_hover.bind(data, panel, rarity_color))
	panel.mouse_exited.connect(_on_card_exit.bind(panel))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(v)

	var rarity_label := Label.new()
	rarity_label.text = rarity.to_upper()
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_color_override("font_color", rarity_color)
	rarity_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	rarity_label.add_theme_constant_override("outline_size", 4)
	rarity_label.add_theme_font_size_override("font_size", 14)
	v.add_child(rarity_label)

	var icon_rect := TextureRect.new()
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.custom_minimum_size = Vector2(180, 180)
	icon_rect.texture = _icon_for(data)
	icon_rect.modulate = rarity_color.lerp(Color.WHITE, 0.5)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon_rect)

	var title := Label.new()
	title.text = String(data.get("title", "?"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 0.92, 0.65, 1))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	title.add_theme_constant_override("outline_size", 5)
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)

	var desc := Label.new()
	desc.text = String(data.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62, 1))
	desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	desc.add_theme_constant_override("outline_size", 3)
	desc.add_theme_font_size_override("font_size", 15)
	desc.custom_minimum_size = Vector2(0, 72)
	v.add_child(desc)

	var btn := Button.new()
	btn.text = "Take"
	btn.custom_minimum_size = Vector2(220, 56)
	btn.add_theme_font_size_override("font_size", 20)
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
	btn.pressed.connect(_on_pick.bind(data))
	btn.mouse_entered.connect(func(): btn.modulate = Color(1.15, 1.15, 1.15, 1))
	btn.mouse_exited.connect(func(): btn.modulate = Color(1, 1, 1, 1))
	v.add_child(btn)

	return panel


func _on_card_hover(data: Dictionary, panel: Control, rarity_color: Color) -> void:
	# Visual lift.
	var tw := create_tween()
	tw.tween_property(panel, "modulate", Color(1.18, 1.18, 1.18, 1), 0.12)
	# Tooltip with extended info.
	var kind: String = String(data.get("kind", "stat"))
	var title: String = String(data.get("title", ""))
	var rarity: String = String(data.get("rarity", "common"))
	var body: String = String(data.get("desc", ""))
	var meta: String = ""
	match kind:
		"modifier":
			var slot: int = int(data.get("slot", 0))
			meta = "Affects: %s" % RewardData.slot_name(slot)
			var existing: int = _existing_stack_count(slot, String(data.get("id", "")))
			if existing > 0:
				meta += "    You already own ×%d" % existing
		"unique":
			var slot: int = int(data.get("slot", 0))
			meta = "Transforms: %s" % RewardData.slot_name(slot)
		"stat":
			meta = "Permanent stat increase"
	if TooltipManager:
		TooltipManager.show_tooltip(title, rarity, body, meta)


func _on_card_exit(panel: Control) -> void:
	var tw := create_tween()
	tw.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.12)
	if TooltipManager:
		TooltipManager.hide_tooltip()


func _existing_stack_count(slot: int, modifier_id: String) -> int:
	var ss := _find_skill_system()
	if ss == null or not ss.has_method("get_modifier"):
		return 0
	return int(ss.call("get_modifier", slot, modifier_id))


func _icon_for(data: Dictionary) -> Texture2D:
	var kind: String = String(data.get("kind", "stat"))
	match kind:
		"stat":
			var id: String = String(data.get("id", ""))
			if id.begins_with("hp"):
				return _safe_load("res://assets/ui/icon_heart.png")
			if id.begins_with("mana"):
				return _safe_load("res://assets/ui/icon_mana.png")
			if id.begins_with("dmg"):
				return _safe_load("res://assets/ui/icon_strength.png")
			if id.begins_with("speed"):
				return _safe_load("res://assets/ui/icon_dexterity.png")
			if id.begins_with("crit"):
				return _safe_load("res://assets/ui/icon_strength.png")
			if id == "heal_full":
				return _safe_load("res://assets/ui/icon_heart.png")
			return _safe_load("res://assets/ui/icon_gold.png")
		"modifier", "unique":
			return RewardData.slot_icon(int(data.get("slot", 0)))
		"perk":
			return _safe_load("res://assets/sprites/items/weapon_barb_2h_axe.png")
	return null


func _safe_load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _on_pick(data: Dictionary) -> void:
	chosen_id = String(data.get("id", ""))
	_apply(data)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_ui_menu_click.mp3", -6.0)
	if VfxManager:
		var rar: String = String(data.get("rarity", "common"))
		var col: Color = RARITY_COLORS.get(rar, Color.WHITE)
		VfxManager.screen_flash(Color(col.r, col.g, col.b, 0.25), 0.3)
	if TooltipManager:
		TooltipManager.hide_tooltip()
	choice_made.emit(chosen_id)
	_close()


func _apply(data: Dictionary) -> void:
	var kind: String = String(data.get("kind", "stat"))
	var id: String = String(data.get("id", ""))
	match kind:
		"stat":
			_apply_stat(id)
		"modifier":
			_apply_modifier(int(data.get("slot", 0)), id)
		"unique":
			_apply_unique(int(data.get("slot", 0)), String(data.get("transform", "")), id)
		"perk":
			_apply_perk(id)


func _apply_perk(id: String) -> void:
	match id:
		"barb_dual_2h":
			if InventorySystem:
				InventorySystem.grant_berserker_grip()


func _apply_stat(id: String) -> void:
	if GameManager == null:
		return
	match id:
		"hp+20":
			GameManager.player_max_hp += 20
			GameManager.player_hp += 20
		"hp+40":
			GameManager.player_max_hp += 40
			GameManager.player_hp += 40
		"mana+15":
			GameManager.player_max_mana += 15
			GameManager.player_mana = min(
				GameManager.player_mana + 15.0, float(GameManager.player_max_mana)
			)
		"mana+30":
			GameManager.player_max_mana += 30
			GameManager.player_mana = min(
				GameManager.player_mana + 30.0, float(GameManager.player_max_mana)
			)
		"dmg+3":
			GameManager.player_damage += 3
		"dmg+7":
			GameManager.player_damage += 7
		"crit+5":
			GameManager.player_crit_chance += 0.05
		"crit_dmg+0.25":
			GameManager.player_crit_damage += 0.25
		"speed+15":
			GameManager.player_move_speed += 15.0
		"heal_full":
			GameManager.player_hp = GameManager.player_max_hp
	GameManager.player_stats_changed.emit()


func _apply_modifier(slot: int, id: String) -> void:
	var ss := _find_skill_system()
	if ss == null:
		return
	ss.call("add_modifier", slot, id)


func _apply_unique(slot: int, transform_id: String, _src_id: String) -> void:
	var ss := _find_skill_system()
	if ss == null:
		return
	ss.call("apply_transform", slot, transform_id)


func _close() -> void:
	get_tree().paused = false
	queue_free()
