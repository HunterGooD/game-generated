class_name SocketLinkOverlay
extends Control

# Слой линий-связей между гнёздами куклы экипировки (рисуется поверх плиток,
# мышь игнорирует). Сегменты строит character_sheet из SocketGems.resolve.

var segments: Array = []  # {from: Vector2, to: Vector2, color: Color, width: float}


func _draw() -> void:
	for s in segments:
		var seg: Dictionary = s
		var col: Color = seg.get("color", Color.WHITE)
		draw_line(
			seg.get("from", Vector2.ZERO),
			seg.get("to", Vector2.ZERO),
			Color(col.r, col.g, col.b, 0.9),
			float(seg.get("width", 3.0)),
			true
		)
