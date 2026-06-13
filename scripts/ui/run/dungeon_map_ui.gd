class_name DungeonMapUI
extends CanvasLayer

## A self-contained dungeon map component: an always-on mini-map (top-right corner) plus a
## full-screen map toggled with M. Drawn from the layer graph (rooms by cell, edges, spine,
## boss marker) with the party's current room highlighted and visited rooms remembered.
## The runner instantiates it with setup(layer, room_world, player). Read-only; no autoload
## deps beyond the passed refs.

const MINI_SIZE := Vector2(248, 176)
const PAD := 16.0

# Room-kind → dot colour (matches the dungeon's marker palette roughly).
const KIND_COLOR := {
	"entry": Color(0.45, 0.95, 0.55),
	"boss": Color(0.95, 0.25, 0.25),
	"pylon": Color(0.7, 0.8, 1.0),
	"pocket": Color(0.7, 0.8, 1.0),
	"elite_pylon": Color(1.0, 0.45, 0.9),
	"event_pillar": Color(0.55, 0.8, 1.0),
	"dead_end": Color(1.0, 0.84, 0.3),
	"vault": Color(1.0, 0.7, 0.25),
	"merchant": Color(0.92, 0.78, 0.3),
	"exit": Color(0.5, 0.95, 1.0),
	"descent": Color(1.0, 0.55, 0.5),
}

var _layer = null
var _room_world: Dictionary = {}
var _player: Node2D = null
var _cell_px := 700.0  # world units per graph cell (for the player marker)

var _draw_ctl: Control = null
var _full := false
var _cells: Dictionary = {}     # room id -> Vector2(cell)
var _kinds: Dictionary = {}     # room id -> String
var _cmin := Vector2.ZERO
var _cmax := Vector2.ZERO
var _visited: Dictionary = {}   # room id -> true
var _current := -1
var _boss_id := -1


func setup(layer, room_world: Dictionary, player: Node2D, cell_px: float = 700.0) -> void:
	_layer = layer
	_room_world = room_world
	_player = player
	_cell_px = maxf(1.0, cell_px)


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _layer == null:
		queue_free()
		return
	_compute_cells()
	_boss_id = int(_layer.call("boss_id"))
	_draw_ctl = _MapDraw.new()
	_draw_ctl.set("owner_map", self)
	add_child(_draw_ctl)
	_layout()
	set_process(true)


func _compute_cells() -> void:
	var first := true
	for r in _layer.call("rooms"):
		var id: int = int(r["id"])
		var c: Vector2i = r["cell"]
		var cv := Vector2(c)
		_cells[id] = cv
		_kinds[id] = String(r["kind"])
		if first:
			_cmin = cv
			_cmax = cv
			first = false
		else:
			_cmin = _cmin.min(cv)
			_cmax = _cmax.max(cv)


func _process(_delta: float) -> void:
	if _player and is_instance_valid(_player):
		var best := -1
		var bd := INF
		for id in _room_world:
			var d: float = _player.global_position.distance_squared_to(_room_world[id])
			if d < bd:
				bd = d
				best = int(id)
		_current = best
		if best >= 0:
			_visited[best] = true
	if _draw_ctl:
		_draw_ctl.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_full = not _full
		_layout()
		get_viewport().set_input_as_handled()


func _layout() -> void:
	if _draw_ctl == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if _full:
		_draw_ctl.size = vp * 0.72
		_draw_ctl.position = (vp - _draw_ctl.size) * 0.5
	else:
		_draw_ctl.size = MINI_SIZE
		_draw_ctl.position = Vector2(vp.x - MINI_SIZE.x - 20.0, 20.0)


# Called by the inner Control's _draw.
func render(ctl: Control) -> void:
	var sz: Vector2 = ctl.size
	# Backdrop.
	ctl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.04, 0.04, 0.07, 0.85 if _full else 0.6))
	ctl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.5, 0.55, 0.7, 0.6), false, 2.0)

	# Edges first, then nodes on top.
	for e in _layer.call("edges"):
		var a: int = int(e["a"])
		var b: int = int(e["b"])
		if _cells.has(a) and _cells.has(b):
			ctl.draw_line(_node_pos(a, sz), _node_pos(b, sz), Color(0.45, 0.5, 0.62, 0.7), 1.5, true)

	var base_r: float = 7.0 if _full else 4.0
	for id in _cells:
		var p: Vector2 = _node_pos(id, sz)
		var kind: String = String(_kinds.get(id, ""))
		var col: Color = KIND_COLOR.get(kind, Color(0.6, 0.6, 0.68))
		var r: float = base_r * (1.6 if id == _boss_id else 1.0)
		if not _visited.has(id) and id != _current:
			col = col.darkened(0.45)
		ctl.draw_circle(p, r, col)
		if id == _current:
			ctl.draw_arc(p, r + 4.0, 0.0, TAU, 20, Color(0.3, 0.95, 1.0), 2.0, true)

	# The player's live position (world → cell → map), so you always see where you are.
	if _player and is_instance_valid(_player):
		var pp: Vector2 = _cell_to_pos(_player.global_position / _cell_px, sz)
		var pr: float = base_r * 0.9
		ctl.draw_circle(pp, pr, Color(0.3, 1.0, 0.45))
		ctl.draw_arc(pp, pr + 2.5, 0.0, TAU, 16, Color(1, 1, 1, 0.85), 1.5, true)

	if _full:
		var title := "Dungeon Map        [M] close"
		ctl.draw_string(
			ThemeDB.fallback_font, Vector2(14, 26), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(0.9, 0.9, 0.78)
		)


func _node_pos(id: int, sz: Vector2) -> Vector2:
	return _cell_to_pos(_cells.get(id, Vector2.ZERO), sz)


func _cell_to_pos(cell: Vector2, sz: Vector2) -> Vector2:
	var span: Vector2 = (_cmax - _cmin)
	span.x = maxf(span.x, 1.0)
	span.y = maxf(span.y, 1.0)
	var inner: Vector2 = sz - Vector2(PAD, PAD) * 2.0
	var n: Vector2 = (cell - _cmin) / span
	return Vector2(PAD, PAD) + Vector2(n.x * inner.x, n.y * inner.y)


# Inner Control that forwards _draw to the owning map (CanvasLayer can't _draw itself).
class _MapDraw:
	extends Control
	var owner_map = null

	func _draw() -> void:
		if owner_map:
			owner_map.render(self)
