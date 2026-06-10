class_name ArenaZone
extends Node2D

## A "clear the zone" arena event: a ring appears; slay `goal` enemies INSIDE it before the
## timer runs out to earn local currency. Listens to GameEvents.enemy_died and counts deaths
## within RADIUS. Built in code (a simple drawn ring).

const RADIUS: float = 230.0
const DURATION: float = 16.0

var goal: int = 6
var reward: int = 55
var _kills: int = 0
var _t: float = 0.0
var _done: bool = false
var _label: Label = null


func _ready() -> void:
	add_to_group("arena_zone")
	if GameEvents and not GameEvents.enemy_died.is_connected(_on_enemy_died):
		GameEvents.enemy_died.connect(_on_enemy_died)
	_label = Label.new()
	_label.position = Vector2(-140, -RADIUS - 28)
	_label.custom_minimum_size = Vector2(280, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_refresh_label()
	if GameManager:
		GameManager.notice.emit("⚑ ZONE — slay %d foes inside the ring!" % goal, Color(0.5, 0.8, 1.0))
	queue_redraw()


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t >= DURATION:
		_finish(false)


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color(0.35, 0.65, 1.0, 0.14))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 56, Color(0.5, 0.8, 1.0, 0.8), 4.0, true)


func _refresh_label() -> void:
	if _label:
		_label.text = "ZONE  %d / %d" % [_kills, goal]


func _on_enemy_died(ev) -> void:
	if _done or ev == null:
		return
	var actor = ev.actor
	if (
		actor
		and is_instance_valid(actor)
		and actor is Node2D
		and (actor as Node2D).global_position.distance_to(global_position) <= RADIUS
	):
		_kills += 1
		_refresh_label()
		if _kills >= goal:
			_finish(true)


func _finish(success: bool) -> void:
	if _done:
		return
	_done = true
	if success and GameManager:
		GameManager.arena_award(reward)
		GameManager.notice.emit("Zone cleared!  +%d coin" % reward, Color(0.45, 0.9, 0.5))
	elif GameManager:
		GameManager.notice.emit("Zone failed — the foes endured", Color(0.8, 0.5, 0.4))
	queue_free()
