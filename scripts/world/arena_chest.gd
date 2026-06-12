class_name ArenaChest
extends Node2D

## A physical reward chest that appears in the arena after the finale boss. You walk up and
## press E to open it (spending local currency). Bigger scale + brighter shader = pricier
## cache with better loot; the smallest "coffer" dumps ALL remaining currency to gold (1:2).
## Built in code (no .tscn node_paths). One-shot.

const INTERACT_RANGE: float = 96.0
const GLOW_SHADER: Shader = preload("res://assets/shaders/pillar_glow.gdshader")

var kind: String = "cache"  # "cache" | "dump"
var cost: int = 30
var item_count: int = 1
var ilvl_bonus: int = 0
var chest_scale: float = 1.0
var color: Color = Color(0.4, 0.85, 0.5)
var label_text: String = "Тайник"
var wave_hint: int = 10

var _label: Label = null
var _in_range: bool = false
var _used: bool = false


func configure(cfg: Dictionary) -> void:
	kind = String(cfg.get("kind", kind))
	cost = int(cfg.get("cost", cost))
	item_count = int(cfg.get("items", item_count))
	ilvl_bonus = int(cfg.get("ilvl", ilvl_bonus))
	chest_scale = float(cfg.get("scale", chest_scale))
	color = cfg.get("color", color)
	label_text = String(cfg.get("label", label_text))
	wave_hint = int(cfg.get("wave_hint", wave_hint))


func _ready() -> void:
	add_to_group("arena_chest")
	_build()


func _build() -> void:
	var glow := ColorRect.new()
	glow.color = Color(1, 1, 1, 1)
	glow.size = Vector2(96, 80) * chest_scale
	glow.position = -glow.size * 0.5 + Vector2(0, -10)
	glow.z_index = -1
	var gmat := ShaderMaterial.new()
	gmat.shader = GLOW_SHADER
	var gc := color
	gc.a = 0.3
	gmat.set_shader_parameter("tint", gc)
	gmat.set_shader_parameter("pulse_speed", 2.5)
	glow.material = gmat
	add_child(glow)

	var body := ColorRect.new()
	body.color = color
	body.size = Vector2(64, 52) * chest_scale
	body.position = -body.size * 0.5
	add_child(body)
	var lid := ColorRect.new()
	lid.color = color.lightened(0.25)
	lid.size = Vector2(64, 16) * chest_scale
	lid.position = Vector2(-body.size.x * 0.5, -body.size.y * 0.5 - lid.size.y)
	add_child(lid)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-140, -60 - 40 * chest_scale)
	_label.custom_minimum_size = Vector2(280, 0)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.84))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_refresh_label()


func _price_text() -> String:
	if kind == "dump":
		return "%s — ALL coin → gold 1:%d" % [label_text, GameManager.ARENA_GOLD_RATE]
	return "%s — %d coin → %d item%s" % [label_text, cost, item_count, "s" if item_count > 1 else ""]


func _refresh_label() -> void:
	if _label:
		_label.text = _price_text()


func _process(_delta: float) -> void:
	if _used:
		return
	var p := _local_player()
	var in_range: bool = (
		p != null and global_position.distance_to(p.global_position) <= INTERACT_RANGE
	)
	if in_range != _in_range:
		_in_range = in_range
		_label.text = (_price_text() + "   [E]") if in_range else _price_text()
	if in_range and Input.is_action_just_pressed("interact"):
		_open()


func _open() -> void:
	if _used:
		return
	if kind == "dump":
		var gold_gained: int = GameManager.arena_dump_to_gold()
		if GameManager:
			GameManager.notice.emit("Сундучок опустошён — +%d золота" % gold_gained, Color(1.0, 0.84, 0.3))
		_consume()
		return
	# Priced cache.
	if not GameManager.arena_spend(cost):
		if GameManager:
			GameManager.notice.emit("Недостаточно монет для «%s»" % label_text, Color(0.85, 0.5, 0.4))
		return  # leave it — the player may open a cheaper one
	var cls: String = String(GameManager.player_class)
	for i in item_count:
		var it = LootRoller.roll_item(maxi(1, wave_hint + ilvl_bonus), cls, GameManager.run_difficulty)
		if it != null and InventorySystem:
			InventorySystem.add_item(it)
	if GameManager:
		GameManager.notice.emit("%s opened — %d item(s)!" % [label_text, item_count], color)
	_consume()


func _consume() -> void:
	_used = true
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.0, color)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_loot_reveal_common.mp3", -6.0)
	queue_free()


func _local_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p) and p is Node2D and not p.is_in_group("remote_player"):
			return p as Node2D
	return null
