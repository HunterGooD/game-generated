extends Node2D
## Walkable hub — the staging area between runs. You spawn as your last-played hero
## (default barbarian), walk around, and use two props:
##   • WARDROBE (шкаф) → hero-select overlay (change class, live)
##   • PORTAL → the run map (difficulty pick → node selection)
## Solo for now; co-op (an NPC that creates a room + shows a lobby code) is a later task.
##
## Props use the beacon/merchant interaction pattern: proximity + the `interact` action,
## with an "[E]" prompt. Built in code to avoid .tscn node_path fragility.

const FLOOR_TEX: String = "res://assets/textures/floors/ruins_floor.webp"
const HERO_SELECT := preload("res://scripts/ui/hero_select.gd")
const INTERACT_RANGE: float = 96.0

@onready var _player: Node2D = $Player

# Each prop: {node:Node2D, label:Label, pos:Vector2, base_text:String, action:Callable, in_range:bool}
var _props: Array = []
var _overlay_open: bool = false


func _ready() -> void:
	# Spawn as the last-played hero. choose_class resets the run + emits class_selected,
	# so the Player (already _ready) re-applies the class live.
	if GameManager:
		var hero: String = GameManager.last_class
		if not GameManager.CLASSES.has(hero):
			hero = "barbarian"
		GameManager.choose_class(hero)

	_build_floor()
	_spawn_props()

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
	var cols: int = 16
	var rows: int = 11
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
			s.modulate = Color(0.62, 0.62, 0.72)  # cool, peaceful tone
			s.position = origin + Vector2(x * ts.x, y * ts.y)
			layer.add_child(s)


func _spawn_props() -> void:
	_props.append(
		_make_prop("Wardrobe  —  change hero", Vector2(-260, -40), Color(0.55, 0.7, 1.0), _open_wardrobe)
	)
	_props.append(
		_make_prop("Portal  —  begin the run", Vector2(260, -40), Color(1.0, 0.55, 0.35), _enter_portal)
	)


func _make_prop(text: String, pos: Vector2, tint: Color, action: Callable) -> Dictionary:
	var root := Node2D.new()
	root.position = pos
	add_child(root)
	# Simple glowing marker (art polish later).
	var body := ColorRect.new()
	body.color = tint
	body.size = Vector2(64, 88)
	body.position = Vector2(-32, -88)
	root.add_child(body)
	var glow := ColorRect.new()
	glow.color = Color(tint.r, tint.g, tint.b, 0.25)
	glow.size = Vector2(96, 120)
	glow.position = Vector2(-48, -104)
	glow.z_index = -1
	root.add_child(glow)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-120, -128)
	label.custom_minimum_size = Vector2(240, 0)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	root.add_child(label)
	return {"node": root, "label": label, "pos": pos, "base_text": text, "action": action, "in_range": false}


func _process(_delta: float) -> void:
	if _overlay_open or _player == null or not is_instance_valid(_player):
		return
	for prop in _props:
		var in_range: bool = _player.global_position.distance_to(prop["pos"]) <= INTERACT_RANGE
		if in_range != prop["in_range"]:
			prop["in_range"] = in_range
			prop["label"].text = (prop["base_text"] + "   [E]") if in_range else prop["base_text"]
		if in_range and Input.is_action_just_pressed("interact"):
			(prop["action"] as Callable).call()
			return


func _open_wardrobe() -> void:
	if _overlay_open:
		return
	_overlay_open = true
	var ov := HERO_SELECT.new()
	ov.closed.connect(func(): _overlay_open = false)
	add_child(ov)


func _enter_portal() -> void:
	if RunFlow:
		RunFlow.open_map()  # → run-map scene: difficulty pick → node selection
