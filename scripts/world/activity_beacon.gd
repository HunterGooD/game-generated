extends Node2D

# Activity beacon — a glowing icon in one of the room's corners marking
# a future event (treasure / altar / roulette / ritual). Phase 1: visual only.
# Phase 3 will wire the actual interaction.

@export var icon_sprite: Sprite2D
@export var label: Label

var activity_name: String = ""
var icon_key: String = ""
var label_text: String = ""


func configure(p_name: String, p_icon: String, p_label: String) -> void:
	activity_name = p_name
	icon_key = p_icon
	label_text = p_label
	_apply()


func _ready() -> void:
	if icon_key != "":
		_apply()
	# Gentle floating animation, bound to THIS node so freeing the node kills the tween.
	var tw := create_tween().set_loops()
	tw.tween_property(self, "position:y", position.y - 6.0, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "position:y", position.y + 6.0, 1.2).set_trans(Tween.TRANS_SINE)


func _apply() -> void:
	if icon_sprite and icon_key != "":
		var icon_path := "res://assets/sprites/items/%s.png" % icon_key
		if ResourceLoader.exists(icon_path):
			icon_sprite.texture = load(icon_path) as Texture2D
			var tex_size: Vector2 = (
				icon_sprite.texture.get_size() if icon_sprite.texture else Vector2(256, 256)
			)
			var max_dim: float = max(tex_size.x, tex_size.y)
			if max_dim > 0:
				var sc: float = 90.0 / max_dim
				icon_sprite.scale = Vector2(sc, sc)
	if label:
		label.text = label_text
