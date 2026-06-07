extends Node2D

# Curse Field — places a circular hex on the ground at the target. Any enemy
# inside takes +50% damage from all sources for as long as they stand in it.
# Lasts 8 seconds. Replaces Raise Knight when the Curse Field unique is equipped.

const LIFETIME: float = 8.0
const RADIUS: float = 200.0
const DMG_AMP: float = 0.50

var visual_only: bool = false
var sprite: Sprite2D = null
var marked: Dictionary = {}  # enemy_instance_id -> true (for cleanup)


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 5  # under enemies but above floor
	sprite = Sprite2D.new()
	var path := "res://assets/sprites/effects/curse_field_zone.png"
	if ResourceLoader.exists(path):
		sprite.texture = load(path) as Texture2D
	sprite.modulate = Color(0.85, 0.4, 1.0, 0.85)
	# Scale to roughly RADIUS*2 px diameter.
	if sprite.texture:
		var src_w: float = float(sprite.texture.get_size().x)
		if src_w > 1.0:
			var sc: float = (RADIUS * 2.0) / src_w
			sprite.scale = Vector2(sc, sc)
	add_child(sprite)
	# Slow rotation for visual flair.
	var rot := sprite.create_tween().set_loops()
	rot.tween_property(sprite, "rotation", sprite.rotation + TAU, 6.0)
	# Lifetime + cleanup.
	var done := get_tree().create_timer(LIFETIME)
	done.timeout.connect(_finish)
	# Fade-out near the end.
	var fade := sprite.create_tween()
	fade.tween_interval(LIFETIME - 0.6)
	fade.tween_property(sprite, "modulate:a", 0.0, 0.6)


func _physics_process(_delta: float) -> void:
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	# Mark every enemy currently inside the radius with a damage-amp meta.
	# Damage callers read this through enemy.take_damage scaling below.
	var still_inside: Dictionary = {}
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d <= RADIUS:
			(e as Node2D).set_meta("curse_amp", DMG_AMP)
			still_inside[e.get_instance_id()] = true
			marked[e.get_instance_id()] = true
	# Clear the amp on enemies that left the zone.
	for id in marked.keys():
		if still_inside.has(id):
			continue
		# Look up by instance — Godot has no direct lookup, so iterate the
		# enemy group once and clear if matches. Cheap enough at typical wave
		# sizes; rare event.
		for e in tree.get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.get_instance_id() == id:
				(e as Node2D).set_meta("curse_amp", 0.0)
				break
	# Forget cleared ones.
	for id in marked.keys():
		if not still_inside.has(id):
			marked.erase(id)


func _finish() -> void:
	if visual_only:
		queue_free()
		return
	# Strip the curse meta from everyone we marked.
	var tree := get_tree()
	if tree != null:
		for e in tree.get_nodes_in_group("enemy"):
			if is_instance_valid(e):
				(e as Node2D).set_meta("curse_amp", 0.0)
	queue_free()
