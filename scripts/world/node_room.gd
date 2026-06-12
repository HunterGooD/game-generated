extends Node2D
## A small walkable room for the non-combat run-map nodes (merchant / campfire). Reads
## GameManager.run_node_active.type and builds the matching content, plus an exit portal
## that returns the party to the run map. Does NOT reset the run (HP/level/gold carry).

const FLOOR_TEX: String = "res://assets/textures/floors/ruins_floor.webp"
const MERCHANT_SCENE: PackedScene = preload("res://scenes/pickups/merchant.tscn")
const PORTAL_SCENE: PackedScene = preload("res://scenes/pickups/wave_portal.tscn")
const REST_CHOICE := preload("res://scripts/ui/rest_choice.gd")
const SHRINE_EVENT := preload("res://scripts/ui/shrine_event.gd")
const INTERACT_RANGE: float = 96.0

@onready var _player: Node2D = $Player

var content_kind: String = ""
var _campfire: Node2D = null
var _campfire_label: Label = null
var _campfire_used: bool = false
var _campfire_in_range: bool = false
var _rest_open: bool = false

# Event "shrine" — mirrors the campfire interaction pattern (walk up, press E once).
var _shrine: Node2D = null
var _shrine_label: Label = null
var _shrine_used: bool = false
var _shrine_in_range: bool = false
var _shrine_open: bool = false


func _ready() -> void:
	_build_floor()
	content_kind = String(GameManager.run_node_active.get("type", "")) if GameManager else ""
	match content_kind:
		"merchant":
			_build_merchant()
		"campfire":
			_build_campfire()
		"event":
			_build_shrine()
	_spawn_exit_portal()
	if AudioManager:
		var music: AudioStream = load("res://assets/audio/music/music_exploration_dungeon_explore.mp3") as AudioStream
		if music:
			AudioManager.play_music(music, -14.0)


func _build_floor() -> void:
	if not ResourceLoader.exists(FLOOR_TEX):
		return
	var tex: Texture2D = load(FLOOR_TEX) as Texture2D
	if tex == null:
		return
	var ts: Vector2 = tex.get_size()
	var cols: int = 14
	var rows: int = 10
	var origin := Vector2(-float(cols) * ts.x * 0.5, -float(rows) * ts.y * 0.5)
	var layer := Node2D.new()
	layer.name = "FloorLayer"
	layer.z_index = -10
	add_child(layer)
	for y in rows:
		for x in cols:
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.modulate = Color(0.6, 0.6, 0.7)
			s.position = origin + Vector2(x * ts.x, y * ts.y)
			layer.add_child(s)


func _build_merchant() -> void:
	var m: Node2D = MERCHANT_SCENE.instantiate()
	add_child(m)
	m.global_position = Vector2(-200, 0)


func _build_campfire() -> void:
	_campfire = Node2D.new()
	_campfire.position = Vector2(-180, 0)
	add_child(_campfire)
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.55, 0.2, 0.6)
	glow.size = Vector2(70, 70)
	glow.position = Vector2(-35, -60)
	_campfire.add_child(glow)
	var body := ColorRect.new()
	body.color = Color(1.0, 0.7, 0.3)
	body.size = Vector2(40, 28)
	body.position = Vector2(-20, -20)
	_campfire.add_child(body)
	_campfire_label = Label.new()
	_campfire_label.text = "Костёр — привал"
	_campfire_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_campfire_label.position = Vector2(-120, -96)
	_campfire_label.custom_minimum_size = Vector2(240, 0)
	_campfire_label.add_theme_font_size_override("font_size", 15)
	_campfire_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	_campfire_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_campfire_label.add_theme_constant_override("outline_size", 4)
	_campfire.add_child(_campfire_label)


func _build_shrine() -> void:
	# A teal altar prop built from glow rects (matches the run-map "?" event colour). Walk up
	# and press E to open the bargain overlay.
	_shrine = Node2D.new()
	_shrine.position = Vector2(-180, 0)
	add_child(_shrine)
	var glow := ColorRect.new()
	glow.color = Color(0.35, 0.95, 0.8, 0.45)
	glow.size = Vector2(80, 110)
	glow.position = Vector2(-40, -110)
	_shrine.add_child(glow)
	var body := ColorRect.new()
	body.color = Color(0.5, 0.9, 0.78)
	body.size = Vector2(44, 80)
	body.position = Vector2(-22, -80)
	_shrine.add_child(body)
	var gem := ColorRect.new()
	gem.color = Color(0.85, 1.0, 0.95)
	gem.size = Vector2(20, 20)
	gem.position = Vector2(-10, -70)
	_shrine.add_child(gem)
	_shrine_label = Label.new()
	_shrine_label.text = "Алтарь сделки"
	_shrine_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shrine_label.position = Vector2(-120, -140)
	_shrine_label.custom_minimum_size = Vector2(240, 0)
	_shrine_label.add_theme_font_size_override("font_size", 15)
	_shrine_label.add_theme_color_override("font_color", Color(0.55, 0.97, 0.85))
	_shrine_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_shrine_label.add_theme_constant_override("outline_size", 4)
	_shrine.add_child(_shrine_label)


func _spawn_exit_portal() -> void:
	var portal: Node2D = PORTAL_SCENE.instantiate()
	add_child(portal)
	portal.global_position = Vector2(220, 0)
	if portal.has_signal("activated"):
		portal.connect("activated", _on_exit_portal)


func _on_exit_portal() -> void:
	if GameManager:
		GameManager.clear_run_node()  # → run_node_cleared → RunFlow returns to the map


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_process_campfire()
	_process_shrine()


func _process_campfire() -> void:
	if _campfire == null or _campfire_used or _rest_open:
		return
	var in_range: bool = _player.global_position.distance_to(_campfire.global_position) <= INTERACT_RANGE
	if in_range != _campfire_in_range:
		_campfire_in_range = in_range
		_campfire_label.text = "Костёр — привал   [E]" if in_range else "Костёр — привал"
	if in_range and Input.is_action_just_pressed("interact"):
		_open_rest()


func _process_shrine() -> void:
	if _shrine == null or _shrine_used or _shrine_open:
		return
	var in_range: bool = _player.global_position.distance_to(_shrine.global_position) <= INTERACT_RANGE
	if in_range != _shrine_in_range:
		_shrine_in_range = in_range
		_shrine_label.text = "Алтарь сделки   [E]" if in_range else "Алтарь сделки"
	if in_range and Input.is_action_just_pressed("interact"):
		_open_shrine()


func _open_shrine() -> void:
	if _shrine_open or _shrine_used:
		return
	_shrine_open = true
	var ov := SHRINE_EVENT.new()
	ov.closed.connect(_on_shrine_closed)
	add_child(ov)


func _on_shrine_closed() -> void:
	_shrine_open = false
	_shrine_used = true
	if _shrine and is_instance_valid(_shrine):
		_shrine.modulate = Color(0.45, 0.45, 0.5)
	if _shrine_label:
		_shrine_label.text = "Алтарь — использован"


func _open_rest() -> void:
	if _rest_open or _campfire_used:
		return
	_rest_open = true
	var ov := REST_CHOICE.new()
	ov.closed.connect(_on_rest_closed)
	add_child(ov)


func _on_rest_closed() -> void:
	_rest_open = false
	_campfire_used = true
	if _campfire and is_instance_valid(_campfire):
		_campfire.modulate = Color(0.5, 0.5, 0.5)
	if _campfire_label:
		_campfire_label.text = "Костёр — использован"
