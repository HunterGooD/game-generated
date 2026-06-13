class_name GemFaceIcon
extends Control

# Procedurally drawn socket-gem icon: a square split into 4 triangles, one per
# face (up/right/down/left), tinted by the face's color — the icon IS the data.
# Used by bag cells, drag previews and the character sheet's socket dots.

var faces: Array = []  # world-space face colors ([up, right, down, left])


func _draw() -> void:
	draw_shape(self, Rect2(Vector2.ZERO, size), faces)


# Draw the gem square into `rect` on any CanvasItem (socket dots reuse this).
static func draw_shape(ci: CanvasItem, rect: Rect2, world_faces: Array) -> void:
	if world_faces.size() != 4:
		return
	var inset: float = minf(rect.size.x, rect.size.y) * 0.12
	var r: Rect2 = rect.grow(-inset)
	var tl: Vector2 = r.position
	var tr: Vector2 = r.position + Vector2(r.size.x, 0)
	var br: Vector2 = r.end
	var bl: Vector2 = r.position + Vector2(0, r.size.y)
	var c: Vector2 = r.get_center()
	var tris: Array = [[tl, tr], [tr, br], [br, bl], [bl, tl]]  # up, right, down, left
	for dir in 4:
		var col: Color = SocketGems.color_tint(String(world_faces[dir]))
		var pts := PackedVector2Array([c, (tris[dir] as Array)[0], (tris[dir] as Array)[1]])
		ci.draw_colored_polygon(pts, col)
	# Seams + outline keep the quadrants readable at small sizes.
	var line: Color = Color(0.08, 0.07, 0.1, 0.9)
	for corner in [tl, tr, br, bl]:
		ci.draw_line(c, corner, line, 1.0, true)
	ci.draw_polyline(PackedVector2Array([tl, tr, br, bl, tl]), line, 1.5, true)
